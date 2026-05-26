import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

const _templateWithSources = '''
    sources:
      - type: git
        url: https://github.com/example/app.git
        tag: v1.0.0
        commit: abc123
        disable-submodules: true
      - generated-sources.json
''';


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

    test('test build: SHA used as both tag and commit', () {
      // When --commit is passed without --tag, prepare uses the SHA for both
      // fields so flatpak-builder can fetch and build without a release tag.
      const sha = 'abc1234567890abcdef';
      final result = patchManifestPlaceholders(
        base,
        tag: sha,
        commit: sha,
      );
      expect(result, contains('tag: $sha'));
      expect(result, contains('commit: $sha'));
      expect(result, isNot(contains('__FLATPAK_TAG__')));
      expect(result, isNot(contains('__FLATPAK_COMMIT__')));
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

    test('re-pins with SHA as both tag and commit when previously pinned', () {
      const pinned = '''
sources:
  - type: git
    url: https://github.com/example/app.git
    tag: v0.1.14
    commit: abc1234567890
    disable-submodules: true
''';
      const sha = 'deadbeefdeadbeef';
      final result = patchManifestPlaceholders(
        pinned,
        tag: sha,
        commit: sha,
      );
      expect(result, contains('tag: $sha'));
      expect(result, contains('commit: $sha'));
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

  group('stripTemplateGuidance', () {
    const templateHeader = '''# Generated by flutpak — https://github.com/o-murphy/flutpak
#
# This is your editable TEMPLATE manifest — commit it to git.
# Run "flutpak generate" on every build to produce the final output in generated/.
#
# SAFE TO EDIT   finish-args, build-commands, build-options, sdk-extensions, modules
# DO NOT REMOVE  __FLATPAK_TAG__ and __FLATPAK_COMMIT__ placeholders — required by generate
# AUTO-INJECTED  patch sources are appended after generated-sources.json by generate
app-id: io.github.example.myapp
''';

    const cleanHeader = '''# Generated by flutpak — https://github.com/o-murphy/flutpak
app-id: io.github.example.myapp
''';

    test('strips guidance header block', () {
      final result = stripTemplateGuidance(templateHeader);
      expect(result, equals(cleanHeader));
    });

    test('strips inline finish-args comment', () {
      const input = '# Sandbox permissions — add or remove as your app requires.\nfinish-args:\n';
      final result = stripTemplateGuidance(input);
      expect(result, equals('finish-args:\n'));
    });

    test('strips indented build-commands comment', () {
      const input = '    # Build steps — review and customise for your project.\n    build-commands:\n';
      final result = stripTemplateGuidance(input);
      expect(result, equals('    build-commands:\n'));
    });

    test('strips indented sources comment', () {
      const input = '    # Sources — do not remove __FLATPAK_TAG__ / __FLATPAK_COMMIT__.\n    sources:\n';
      final result = stripTemplateGuidance(input);
      expect(result, equals('    sources:\n'));
    });

    test('strips generated-sources inject comment', () {
      const input = '      # "flutpak generate" injects patch sources after this line.\n      - generated-sources.json\n';
      final result = stripTemplateGuidance(input);
      expect(result, equals('      - generated-sources.json\n'));
    });

    test('preserves user-written comments', () {
      const input = '''app-id: io.example.App
# my custom note
finish-args:
  - --share=ipc
''';
      final result = stripTemplateGuidance(input);
      expect(result, contains('# my custom note'));
    });

    test('returns content unchanged when no guidance comments present', () {
      const input = '# Generated by flutpak — https://github.com/o-murphy/flutpak\napp-id: test\n';
      final result = stripTemplateGuidance(input);
      expect(result, equals(input));
    });

    test('placeholder strings in guidance comments are not replaced', () {
      // stripTemplateGuidance must run before patchManifestPlaceholders so that
      // __FLATPAK_TAG__ / __FLATPAK_COMMIT__ inside comment lines are removed
      // rather than substituted with the actual SHA.
      const input = '''# Generated by flutpak — https://github.com/o-murphy/flutpak
#
# This is your editable TEMPLATE manifest — commit it to git.
# Run "flutpak generate" on every build to produce the final output in generated/.
#
# SAFE TO EDIT   finish-args
# DO NOT REMOVE  __FLATPAK_TAG__ and __FLATPAK_COMMIT__ placeholders — required by generate
# AUTO-INJECTED  patch sources are appended after generated-sources.json by generate
app-id: io.example.App
    # Sources — do not remove __FLATPAK_TAG__ / __FLATPAK_COMMIT__.
    sources:
      - type: git
        tag: __FLATPAK_TAG__
        commit: __FLATPAK_COMMIT__
''';
      final stripped = stripTemplateGuidance(input);
      final result = patchManifestPlaceholders(stripped, tag: 'v1.0.0', commit: 'abc123');

      // Placeholders in YAML are substituted.
      expect(result, contains('tag: v1.0.0'));
      expect(result, contains('commit: abc123'));

      // The comment lines referencing placeholders are gone entirely.
      expect(result, isNot(contains('DO NOT REMOVE')));
      expect(result, isNot(contains('Sources — do not remove')));
    });
  });

  group('injectPatchSources', () {
    const patchesDir = '/abs/flatpak/patches';

    test('injects patch after generated-sources.json line', () {
      final patches = [
        PatchEntry(
          package: 'objectbox_flutter_libs',
          version: '5.3.1',
          path: '/abs/flatpak/patches/objectbox_flutter_libs.patch',
        ),
      ];

      final result =
          injectPatchSources(_templateWithSources, patches, patchesDir);

      expect(result, contains('type: patch'));
      expect(result, contains('path: patches/objectbox_flutter_libs.patch'));
      expect(result,
          contains('.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1'));

      final sourcesIdx = result.indexOf('generated-sources.json');
      final patchIdx = result.indexOf('type: patch');
      expect(patchIdx, greaterThan(sourcesIdx));
    });

    test('returns content unchanged when patches is empty', () {
      final result = injectPatchSources(_templateWithSources, [], patchesDir);
      expect(result, equals(_templateWithSources));
    });

    test('omits dest when version is null', () {
      final patches = [
        PatchEntry(
          package: 'mypkg',
          version: null,
          path: '/abs/flatpak/patches/mypkg.patch',
        ),
      ];

      final result =
          injectPatchSources(_templateWithSources, patches, patchesDir);

      expect(result, contains('type: patch'));
      expect(result, contains('path: patches/mypkg.patch'));
      expect(result, isNot(contains('dest:')));
    });

    test('injects multiple patches in order', () {
      final patches = [
        PatchEntry(
          package: 'objectbox_flutter_libs',
          version: '5.3.1',
          path: '/abs/flatpak/patches/objectbox_flutter_libs.patch',
        ),
        PatchEntry(
          package: 'sqflite_common_ffi',
          version: '2.3.4',
          path: '/abs/flatpak/patches/sqflite_common_ffi.patch',
          destSubpath: 'linux',
        ),
      ];

      final result =
          injectPatchSources(_templateWithSources, patches, patchesDir);

      final objectboxIdx = result.indexOf('objectbox_flutter_libs');
      final sqfliteIdx = result.indexOf('sqflite_common_ffi');
      expect(objectboxIdx, lessThan(sqfliteIdx));
      expect(result,
          contains('.pub-cache/hosted/pub.dev/sqflite_common_ffi-2.3.4/linux'));
    });

    test('preserves subdirectory structure relative to patchesDir', () {
      final patches = [
        PatchEntry(
          package: 'objectbox_flutter_libs',
          version: '5.3.1',
          path: '/abs/flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch',
        ),
      ];

      final result =
          injectPatchSources(_templateWithSources, patches, patchesDir);

      expect(result,
          contains('path: patches/objectbox_flutter_libs/CMakeLists.txt.patch'));
      expect(result, isNot(contains('path: patches/CMakeLists.txt.patch')));
    });

    test('returns content unchanged when anchor line not found', () {
      const noAnchor = '''
    sources:
      - type: git
        tag: v1.0.0
''';
      final patches = [
        PatchEntry(
          package: 'mypkg',
          version: '1.0.0',
          path: '/abs/flatpak/patches/mypkg.patch',
        ),
      ];

      final result = injectPatchSources(noAnchor, patches, patchesDir);
      expect(result, equals(noAnchor));
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

    const testRegistry = [
      RegistryEntry(
        package: 'objectbox_flutter_libs',
        versionConstraint: '5.3.1',
        patchFilename: 'objectbox_flutter_libs.patch',
      ),
    ];

    test('resolves registry entry when package in lock and patch file exists',
        () {
      final lockPath = writeLock(lockWithObjectbox);
      writePatch('objectbox_flutter_libs.patch');

      final entries = resolvePatchEntries(
        lockPaths: [lockPath],
        patchesDir: '${tmpDir.path}/flatpak/patches',
        registryEntries: testRegistry,
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
        registryEntries: testRegistry,
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
        registryEntries: testRegistry,
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
        registryEntries: testRegistry,
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
