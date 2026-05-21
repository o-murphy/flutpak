import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

void main() {
  group('patchManifestPlaceholders', () {
    const base = '''
sources:
  - type: git
    url: https://github.com/example/app.git
    tag: __FLATPAK_TAG__
    commit: __FLATPAK_COMMIT__
    disable-submodules: true
''';

    test('replaces tag and commit placeholders', () {
      final result = patchManifestPlaceholders(
        base,
        tag: 'v0.1.14',
        commit: 'abc1234567890',
      );
      expect(result, contains('tag: v0.1.14'));
      expect(result, contains('commit: abc1234567890'));
      expect(result, isNot(contains('__FLATPAK_TAG__')));
      expect(result, isNot(contains('__FLATPAK_COMMIT__')));
    });

    test('removes tag: line when tag is null', () {
      final result = patchManifestPlaceholders(
        base,
        tag: null,
        commit: 'abc1234567890',
      );
      expect(result, isNot(contains('tag:')));
      expect(result, contains('commit: abc1234567890'));
    });

    test('removes tag: line when tag is empty string', () {
      final result = patchManifestPlaceholders(
        base,
        tag: '',
        commit: 'abc1234567890',
      );
      expect(result, isNot(contains('tag:')));
      expect(result, contains('commit: abc1234567890'));
    });

    test('re-pins tag and commit when placeholders already replaced', () {
      const pinned = '''
sources:
  - type: git
    url: https://github.com/example/app.git
    tag: v0.1.14
    commit: abc1234567890
    disable-submodules: true
''';
      final result = patchManifestPlaceholders(
        pinned,
        tag: 'v0.2.0',
        commit: 'deadbeef',
      );
      expect(result, contains('tag: v0.2.0'));
      expect(result, contains('commit: deadbeef'));
      expect(result, isNot(contains('v0.1.14')));
      expect(result, isNot(contains('abc1234567890')));
    });

    test('re-pins commit only (no tag) when placeholders already replaced', () {
      const pinned = '''
sources:
  - type: git
    url: https://github.com/example/app.git
    tag: v0.1.14
    commit: abc1234567890
    disable-submodules: true
''';
      final result = patchManifestPlaceholders(
        pinned,
        tag: null,
        commit: 'deadbeef',
      );
      expect(result, isNot(contains('tag:')));
      expect(result, contains('commit: deadbeef'));
    });

    test('does not touch other modules without disable-submodules when re-pinning', () {
      const manifest = '''
  - name: lib
    sources:
      - type: git
        url: https://github.com/example/lib.git
        tag: v1.0.6
        commit: 0000000000000000000000000000000000000001
  - name: app
    sources:
      - type: git
        url: https://github.com/example/app.git
        tag: v0.1.14
        commit: abc1234567890
        disable-submodules: true
''';
      final result = patchManifestPlaceholders(
        manifest,
        tag: 'v0.2.0',
        commit: 'deadbeef',
      );
      // lib module unchanged
      expect(result, contains('tag: v1.0.6'));
      expect(result, contains('commit: 0000000000000000000000000000000000000001'));
      // app module updated
      expect(result, contains('tag: v0.2.0'));
      expect(result, contains('commit: deadbeef'));
    });

    test('is idempotent when no placeholders and no disable-submodules marker', () {
      const noPlaceholders = '''
sources:
  - type: git
    url: https://github.com/example/app.git
    tag: v0.1.14
    commit: abc1234567890
''';
      final result = patchManifestPlaceholders(
        noPlaceholders,
        tag: 'v0.2.0',
        commit: 'deadbeef',
      );
      // No placeholders and no disable-submodules anchor → unchanged
      expect(result, equals(noPlaceholders));
    });

    test('replaces all occurrences if placeholder appears multiple times', () {
      const content = '''
tag: __FLATPAK_TAG__
# another ref: __FLATPAK_TAG__
commit: __FLATPAK_COMMIT__
''';
      final result = patchManifestPlaceholders(
        content,
        tag: 'v1.0.0',
        commit: 'cafebabe',
      );
      expect(result, isNot(contains('__FLATPAK_TAG__')));
      expect(result, isNot(contains('__FLATPAK_COMMIT__')));
    });
  });

  group('replaceMetainfoScreenshots', () {
    const screenshots = [
      ScreenshotConfig(path: 'docs/screenshots/home.png', default_: true),
      ScreenshotConfig(path: 'docs/screenshots/conditions.png'),
    ];

    const existingMetainfo = '''<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.o_murphy.ebalistyka</id>
  <screenshots>
    <screenshot type="default">
      <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/v0.1.14/docs/screenshots/home.png</image>
    </screenshot>
    <screenshot>
      <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/v0.1.14/docs/screenshots/conditions.png</image>
    </screenshot>
  </screenshots>
</component>''';

    test('replaces block with config-built URLs for tag', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'v0.1.15',
      );
      expect(result, contains('ebalistyka-app/v0.1.15/docs/screenshots/home.png'));
      expect(result, contains('ebalistyka-app/v0.1.15/docs/screenshots/conditions.png'));
      expect(result, isNot(contains('v0.1.14')));
      expect(result, contains('<screenshot type="default">'));
    });

    test('replaces block with commit SHA', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'abc1234567890abcdef',
      );
      expect(result, contains('ebalistyka-app/abc1234567890abcdef/docs/screenshots/'));
      expect(result, isNot(contains('v0.1.14')));
    });

    test('falls back to /main/ when ref is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: '',
      );
      expect(result, contains('ebalistyka-app/main/docs/screenshots/home.png'));
    });

    test('returns content unchanged when screenshots list is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: const [],
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'v0.1.15',
      );
      expect(result, equals(existingMetainfo));
    });

    test('returns content unchanged when repoSlug is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: '',
        ref: 'v0.1.15',
      );
      expect(result, equals(existingMetainfo));
    });
  });

  group('patchMetainfoReleases', () {
    final date = DateTime.utc(2026, 5, 19);

    test('strips leading v and updates version and date', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
      expect(result, isNot(contains('version="0.1.14"')));
      expect(result, isNot(contains('date="2026-05-14"')));
    });

    test('handles tag without leading v', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, '0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('handles pre-release tag (v0.1.15-beta.1)', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15-beta.1', date);
      expect(result, contains('version="0.1.15-beta.1"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('only updates first <release> entry', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
  <release version="0.1.13" date="2026-04-01"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      // Second entry should remain unchanged
      expect(result, contains('version="0.1.13"'));
      expect(result, contains('date="2026-04-01"'));
    });

    test('preserves surrounding whitespace and indentation', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('  <release version="0.1.15" date="2026-05-19"/>'));
    });

    test('returns content unchanged when tag is empty', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, '', date);
      expect(result, equals(input));
    });

    test('returns content unchanged when no <releases> section exists', () {
      const input = '''
<component>
  <name>My App</name>
</component>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, equals(input));
    });

    test('pads month and day with leading zeros', () {
      final earlyDate = DateTime.utc(2026, 1, 5);
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', earlyDate);
      expect(result, contains('date="2026-01-05"'));
    });

    test('handles single-quoted attributes', () {
      const input = '''
<releases>
  <release version='0.1.14' date='2026-05-14'/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('handles spaces around equals sign in attributes', () {
      const input = '''
<releases>
  <release version = "0.1.14" date = "2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });
  });

  group('resolvePatchEntries', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('flutpak_patch_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    String writeLock(String content) {
      final f = File('${tmpDir.path}/pubspec.lock')
        ..writeAsStringSync(content);
      return f.path;
    }

    void writePatch(String name) {
      final dir = Directory('${tmpDir.path}/flatpak/patches')
        ..createSync(recursive: true);
      File('${dir.path}/$name').writeAsStringSync('--- a/file\n+++ b/file\n');
    }

    const lockWithObjectbox = '''
packages:
  objectbox_flutter_libs:
    dependency: "direct main"
    description:
      name: objectbox_flutter_libs
      url: "https://pub.dev"
    source: hosted
    version: "5.3.1"
''';

    test('resolves registry entry when package in lock and patch file exists',
        () {
      final lockPath = writeLock(lockWithObjectbox);
      writePatch('objectbox_flutter_libs.patch');

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
      );

      expect(entries, hasLength(1));
      expect(entries.first.package, 'objectbox_flutter_libs');
      expect(entries.first.version, '5.3.1');
    });

    test('skips registry entry when patch file does not exist', () {
      final lockPath = writeLock(lockWithObjectbox);
      // No patch file written

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
      );

      expect(entries, isEmpty);
    });

    test('skips registry entry when package not in lock', () {
      final lockPath = writeLock('''
packages:
  some_other_package:
    source: hosted
    version: "1.0.0"
''');
      writePatch('objectbox_flutter_libs.patch');

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
      );

      expect(entries, isEmpty);
    });

    test('project patches override registry entries for same package', () {
      final lockPath = writeLock(lockWithObjectbox);
      writePatch('objectbox_flutter_libs.patch');

      final projectPatch = PatchEntry(
        package: 'objectbox_flutter_libs',
        version: '5.3.1',
        path: 'custom/path/objectbox.patch',
      );

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
        projectPatches: [projectPatch],
      );

      expect(entries, hasLength(1));
      expect(entries.first.path, 'custom/path/objectbox.patch');
    });

    test('project patches are always included regardless of lock', () {
      final lockPath = writeLock('packages: {}\n');

      final projectPatch = PatchEntry(
        package: 'my_custom_package',
        version: '1.0.0',
        path: 'patches/my_custom.patch',
      );

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
        projectPatches: [projectPatch],
      );

      expect(entries, hasLength(1));
      expect(entries.first.package, 'my_custom_package');
    });

    test('handles missing lock file gracefully', () {
      final entries = resolvePatchEntries(
        lockPaths: ['${tmpDir.path}/nonexistent.lock'],
        patchesDir: '${tmpDir.path}/flatpak/patches',
      );
      expect(entries, isEmpty);
    });

    group('versionConstraint', () {
      const lockWithMypkg = '''
packages:
  mypkg:
    source: hosted
    version: "5.3.1"
''';

      const lockWithMypkgOld = '''
packages:
  mypkg:
    source: hosted
    version: "4.9.0"
''';

      final constrainedEntry = RegistryEntry(
        package: 'mypkg',
        versionConstraint: '>=5.0.0 <6.0.0',
        patchFilename: 'mypkg.patch',
      );

      test('includes entry when locked version satisfies constraint', () {
        final lockPath = writeLock(lockWithMypkg);
        writePatch('mypkg.patch');

        final entries = resolvePatchEntries(
          lockPaths: [lockPath],
          patchesDir: '${tmpDir.path}/flatpak/patches',
          registryEntries: [constrainedEntry],
        );

        expect(entries, hasLength(1));
        expect(entries.first.package, 'mypkg');
        expect(entries.first.version, '5.3.1');
      });

      test('skips entry when locked version does not satisfy constraint', () {
        final lockPath = writeLock(lockWithMypkgOld);
        writePatch('mypkg.patch');

        final entries = resolvePatchEntries(
          lockPaths: [lockPath],
          patchesDir: '${tmpDir.path}/flatpak/patches',
          registryEntries: [constrainedEntry],
        );

        expect(entries, isEmpty);
      });

      test('includes entry when constraint is null (any version)', () {
        final lockPath = writeLock(lockWithMypkgOld);
        writePatch('mypkg.patch');

        final entries = resolvePatchEntries(
          lockPaths: [lockPath],
          patchesDir: '${tmpDir.path}/flatpak/patches',
          registryEntries: [
            const RegistryEntry(
              package: 'mypkg',
              patchFilename: 'mypkg.patch',
            ),
          ],
        );

        expect(entries, hasLength(1));
        expect(entries.first.version, '4.9.0');
      });

      test('skips entry when constraint is malformed', () {
        final lockPath = writeLock(lockWithMypkg);
        writePatch('mypkg.patch');

        final entries = resolvePatchEntries(
          lockPaths: [lockPath],
          patchesDir: '${tmpDir.path}/flatpak/patches',
          registryEntries: [
            const RegistryEntry(
              package: 'mypkg',
              versionConstraint: 'not-a-valid-constraint',
              patchFilename: 'mypkg.patch',
            ),
          ],
        );

        expect(entries, isEmpty);
      });

      test('exact version constraint matches only that version', () {
        final lockPath = writeLock(lockWithMypkg);
        writePatch('mypkg.patch');

        final entries = resolvePatchEntries(
          lockPaths: [lockPath],
          patchesDir: '${tmpDir.path}/flatpak/patches',
          registryEntries: [
            const RegistryEntry(
              package: 'mypkg',
              versionConstraint: '5.3.1',
              patchFilename: 'mypkg.patch',
            ),
          ],
        );

        expect(entries, hasLength(1));
        expect(entries.first.version, '5.3.1');
      });
    });
  });
}
