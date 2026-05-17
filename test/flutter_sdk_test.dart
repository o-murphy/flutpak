import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final sdkFixture =
      p.join('test', 'fixtures', 'flutter_sdk');

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

      expect(
          gradleUrl, contains('fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa'));
    });

    test('engine_stamp.json is a FileSource in flutter/bin/cache', () async {
      final sources = await gen.generate();
      final stamp = sources.whereType<FileSource>().firstWhere(
          (s) => s.url.contains('engine_stamp.json'));

      expect(stamp.dest, 'flutter/bin/cache');
    });

    test('setup-flutter.sh is a ScriptSource', () async {
      final sources = await gen.generate();
      final script = sources.whereType<ScriptSource>().first;

      expect(script.destFilename, 'setup-flutter.sh');
      expect(script.commands.first, contains('--offline'));
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
