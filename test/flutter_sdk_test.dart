import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final sdkFixture = p.join('test', 'fixtures', 'flutter_sdk');

  // We test URL construction only — actual SHA-256 download is skipped by
  // injecting a fake DownloadCache that returns deterministic hashes.
  group('FlutterSdkGenerator — artifact list', () {
    late FlutterSdkGenerator gen;

    setUp(() {
      gen = FlutterSdkGenerator(
        sdkPath: sdkFixture,
        cache: _FakeCache(),
      );
    });

    test('generates expected number of sources', () async {
      final sources = await gen.generate();

      // 1 git + 16 arch artifacts + 1 patch script + 1 setup script + 1 stamp file
      // Exact count depends on artifact list; assert > 15 as a sanity check.
      expect(sources.length, greaterThan(15));
    });

    test('includes Flutter git source as first entry', () async {
      final sources = await gen.generate();
      final git = sources.whereType<GitSource>().first;

      expect(git.url, 'https://github.com/flutter/flutter.git');
      expect(git.tag, '3.41.9');
      expect(git.dest, 'flutter');
    });

    test('x86_64-only artifacts have correct only-arches', () async {
      final sources = await gen.generate();
      final x64Only = sources
          .whereType<ArchiveSource>()
          .where((s) => s.onlyArches?.contains('x86_64') == true)
          .toList();

      expect(x64Only, isNotEmpty);
      for (final s in x64Only) {
        expect(s.onlyArches, ['x86_64']);
        expect(s.url, contains('x64'));
      }
    });

    test('aarch64-only artifacts have correct only-arches', () async {
      final sources = await gen.generate();
      final arm64Only = sources
          .whereType<ArchiveSource>()
          .where((s) => s.onlyArches?.contains('aarch64') == true)
          .toList();

      expect(arm64Only, isNotEmpty);
      for (final s in arm64Only) {
        expect(s.onlyArches, ['aarch64']);
        expect(s.url, contains('arm64'));
      }
    });

    test('fonts URL uses material_fonts.version hash', () async {
      final sources = await gen.generate();
      final fontsUrl = sources
          .whereType<ArchiveSource>()
          .map((s) => s.url)
          .firstWhere((u) => u.contains('fonts.zip'));

      // Must contain the fonts hash from the fixture, not the engine hash
      expect(fontsUrl, contains('3012db47f3130e62f7cc0beabff968a33cbec8d8'));
      expect(fontsUrl, isNot(contains('42d3d75a')));
    });

    test('gradle URL uses gradle_wrapper.version hash', () async {
      final sources = await gen.generate();
      final gradleUrl = sources
          .whereType<ArchiveSource>()
          .map((s) => s.url)
          .firstWhere((u) => u.contains('gradle-wrapper'));

      expect(gradleUrl, contains('fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa'));
    });

    test('engine_stamp.json is a FileSource in flutter/bin/cache', () async {
      final sources = await gen.generate();
      final stamp = sources
          .whereType<FileSource>()
          .firstWhere((s) => s.url.contains('engine_stamp.json'));

      expect(stamp.dest, 'flutter/bin/cache');
    });

    test('sky_engine/pubspec.yaml is an InlineSource', () async {
      final sources = await gen.generate();
      final inline = sources.whereType<InlineSource>().firstWhere(
          (s) =>
              s.destFilename == 'pubspec.yaml' &&
              s.dest.contains('sky_engine'));
      expect(inline.contents, contains('name: sky_engine'));
      expect(inline.contents, contains('version: 0.0.99'));
      expect(inline.contents, contains('sdk:'));
    });

    test('setup-flutter.sh is a ScriptSource', () async {
      final sources = await gen.generate();
      final script = sources.whereType<ScriptSource>().first;

      expect(script.destFilename, 'setup-flutter.sh');
      expect(script.commands.any((c) => c.contains('--offline')), isTrue);
    });

    test('pub archive URLs use pub.dev (not pub.dartlang.org)', () async {
      // This test ensures the deprecated pub.dartlang.org domain is not used.
      // FlutterSdkGenerator itself doesn't generate pub URLs, but verify the
      // ArchiveSource URLs it produces don't accidentally reference dartlang.org.
      final sources = await gen.generate();
      for (final s in sources.whereType<ArchiveSource>()) {
        expect(s.url, isNot(contains('pub.dartlang.org')));
      }
    });
  });

  group('FlutterSdkGenerator — patchPath normalisation', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('flutpak_patch_norm_');
    });
    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('explicit patchPath is made relative to outputDir', () async {
      // outputDir = tmpDir/flatpak
      // patchPath = tmpDir/flatpak/patches/flutter/shared.sh.patch
      // Expected path in sources: patches/flutter/shared.sh.patch
      final outputDir = p.join(tmpDir.path, 'flatpak');
      final patchFile = File(
          p.join(outputDir, 'patches', 'flutter', 'shared.sh.patch'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# dummy patch');

      final gen = FlutterSdkGenerator(
        sdkPath: sdkFixture,
        patchPath: patchFile.path,  // absolute path as given by cfg.patchPath after resolution
        outputDir: outputDir,
        cache: _FakeCache(),
      );

      final sources = await gen.generate();
      final patch = sources.whereType<PatchSource>().first;

      expect(patch.path, 'patches/flutter/shared.sh.patch');
      expect(patch.path, isNot(contains(outputDir)));
    });

    test('patchPath given as project-relative path is normalised', () async {
      // Simulate cfg.patchPath = 'flatpak/patches/flutter/shared.sh.patch'
      // relative to project CWD, with outputDir = absolute path to flatpak/.
      final outputDir = p.join(tmpDir.path, 'flatpak');
      File(p.join(outputDir, 'patches', 'flutter', 'shared.sh.patch'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# dummy patch');

      final projectRelativePath =
          p.relative(p.join(outputDir, 'patches', 'flutter', 'shared.sh.patch'));

      final gen = FlutterSdkGenerator(
        sdkPath: sdkFixture,
        patchPath: projectRelativePath,
        outputDir: outputDir,
        cache: _FakeCache(),
      );

      final sources = await gen.generate();
      final patch = sources.whereType<PatchSource>().first;

      expect(patch.path, 'patches/flutter/shared.sh.patch');
    });
  });

  group('FlutterSdkGenerator.readFlutterVersion', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('flutpak_ver_test_');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('reads version from version file when present', () {
      File(p.join(tmpDir.path, 'version')).writeAsStringSync('3.41.9\n');
      expect(FlutterSdkGenerator.readFlutterVersion(tmpDir.path), '3.41.9');
    });

    test('falls back to packages/flutter/pubspec.yaml when version file absent',
        () {
      final pubspecDir =
          Directory(p.join(tmpDir.path, 'packages', 'flutter'))
            ..createSync(recursive: true);
      File(p.join(pubspecDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: flutter\nversion: 3.27.1\nenvironment:\n  sdk: ">=3.3.0"\n',
      );
      expect(FlutterSdkGenerator.readFlutterVersion(tmpDir.path), '3.27.1');
    });

    test('throws when no version source is available', () {
      // Empty directory — no version file, no git, no pubspec.
      expect(
        () => FlutterSdkGenerator.readFlutterVersion(tmpDir.path),
        throwsException,
      );
    });
  });
}

/// Replaces [DownloadCache] for tests — returns a fake SHA-256 without
/// making any network requests or touching the filesystem.
class _FakeCache implements DownloadCache {
  @override
  Future<String> sha256For(String url) async =>
      'f' * 64; // valid-length hex string

  @override
  void dispose() {}
}
