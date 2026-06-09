import 'dart:convert';
import 'package:flutpak/flutpak.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const _engineHash = 'aabbccdd1122334455667788aabbccdd11223344';
const _fontsHash = '3012db47f3130e62f7cc0beabff968a33cbec8d8';
const _gradleHash = 'fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa';
const _lockContent = 'packages:\n  args:\n    version: "2.5.0"\n';

void main() {
  group('FlutterSdkGenerator — artifact list', () {
    late FlutterSdkGenerator gen;

    setUp(() {
      gen = FlutterSdkGenerator(
        flutterRef: '3.44.1',
        cache: _FakeCache(),
        client: _FakeClient(),
      );
    });

    test('generates expected number of sources', () async {
      final sources = await gen.generate();
      // 1 git + arch artifacts + 1 inline + 1 stamp + optional patch
      expect(sources.length, greaterThan(15));
    });

    test('includes Flutter git source as first entry', () async {
      final sources = await gen.generate();
      final git = sources.whereType<GitSource>().first;

      expect(git.url, 'https://github.com/flutter/flutter.git');
      expect(git.tag, '3.44.1');
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

      expect(fontsUrl, contains(_fontsHash));
    });

    test('gradle URL uses gradle_wrapper.version hash', () async {
      final sources = await gen.generate();
      final gradleUrl = sources
          .whereType<ArchiveSource>()
          .map((s) => s.url)
          .firstWhere((u) => u.contains('gradle-wrapper'));

      expect(gradleUrl, contains(_gradleHash));
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
      final inline = sources.whereType<InlineSource>().firstWhere((s) =>
          s.destFilename == 'pubspec.yaml' && s.dest.contains('sky_engine'));

      expect(inline.contents, contains('name: sky_engine'));
      expect(inline.contents, contains('version: 0.0.99'));
      expect(inline.contents, contains('sdk:'));
    });

    test('no pub.dartlang.org URLs', () async {
      final sources = await gen.generate();
      for (final s in sources.whereType<ArchiveSource>()) {
        expect(s.url, isNot(contains('pub.dartlang.org')));
      }
    });
  });

  group('FlutterSdkGenerator.buildCommands', () {
    test('returns non-empty list', () {
      expect(FlutterSdkGenerator.buildCommands(), isNotEmpty);
    });

    test('installs to /var/lib/flutter', () {
      final cmds = FlutterSdkGenerator.buildCommands();
      expect(cmds.any((c) => c.contains('/var/lib')), isTrue);
    });

    test('stamps engine.version into bin/cache', () {
      final cmds = FlutterSdkGenerator.buildCommands();
      expect(cmds.any((c) => c.contains('engine.version')), isTrue);
    });
  });

  group('FlutterSdkGenerator.fetchFlutterToolsLock', () {
    test('returns lock content when server returns 200', () async {
      final gen = FlutterSdkGenerator(
        flutterRef: '3.44.1',
        cache: _FakeCache(),
        client: _FakeClient(),
      );
      final lock = await gen.fetchFlutterToolsLock();
      expect(lock, contains('packages:'));
    });
  });
}

/// Returns deterministic SHA-256 without network or disk access.
class _FakeCache implements DownloadCache {
  @override
  Future<String> sha256For(String url) async => 'f' * 64;

  @override
  void dispose() {}
}

/// Returns fake HTTP responses for the URLs [FlutterSdkGenerator] fetches.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    final body = _bodyFor(url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
    );
  }

  static String _bodyFor(String url) {
    if (url.contains('engine.version')) return '$_engineHash\n';
    if (url.contains('material_fonts.version')) return '$_fontsHash\n';
    if (url.contains('gradle_wrapper.version')) return '$_gradleHash\n';
    if (url.contains('flutter_tools/pubspec.lock')) return _lockContent;
    // Flutter version file and ls-remote fallback
    if (url.endsWith('/version')) return '3.44.1\n';
    return '';
  }
}
