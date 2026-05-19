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

    test('is idempotent when no placeholders present', () {
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
      // No placeholders → no replacement, content unchanged
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

  group('patchMetainfoScreenshots', () {
    const metainfo = '''
<screenshots>
  <screenshot type="default">
    <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/main/docs/screenshots/home.png</image>
  </screenshot>
  <screenshot>
    <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/main/docs/screenshots/conditions.png</image>
  </screenshot>
</screenshots>
''';

    test('replaces /main/ with tag', () {
      final result = patchMetainfoScreenshots(metainfo, ref: 'v0.1.14');
      expect(result,
          contains('ebalistyka-app/v0.1.14/docs/screenshots/home.png'));
      expect(result,
          contains('ebalistyka-app/v0.1.14/docs/screenshots/conditions.png'));
      expect(result, isNot(contains('/main/')));
    });

    test('replaces /main/ with commit SHA', () {
      final result = patchMetainfoScreenshots(
        metainfo,
        ref: 'abc1234567890abcdef',
      );
      expect(result, contains('ebalistyka-app/abc1234567890abcdef/docs/'));
      expect(result, isNot(contains('/main/')));
    });

    test('returns content unchanged when no /main/ present', () {
      const pinned = '''
<image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/v0.1.14/docs/screenshots/home.png</image>
''';
      final result = patchMetainfoScreenshots(pinned, ref: 'v0.2.0');
      expect(result, equals(pinned));
    });

    test('handles multiple repos in same file correctly', () {
      const content = '''
<image>https://raw.githubusercontent.com/owner/repo-a/main/img/a.png</image>
<image>https://raw.githubusercontent.com/owner/repo-b/main/img/b.png</image>
''';
      final result = patchMetainfoScreenshots(content, ref: 'v1.0.0');
      expect(result, contains('repo-a/v1.0.0/img/a.png'));
      expect(result, contains('repo-b/v1.0.0/img/b.png'));
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
  });
}
