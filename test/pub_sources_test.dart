import 'dart:convert';
import 'dart:io';

import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Fake SHA-256 (64 hex chars) returned by the mock API.
const _fakeSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

http.Client _mockPubDevClient() => MockClient((request) async {
      expect(request.url.host, 'pub.dev');
      expect(request.url.path, matches(r'^/api/packages/\w+/versions/.+$'));
      return http.Response(
        jsonEncode({'archive_sha256': _fakeSha256}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  final lockFile =
      p.join(Directory.current.path, 'test', 'fixtures', 'simple.lock');

  group('PubSourcesGenerator', () {
    test('generates one entry per hosted package', () async {
      final gen = PubSourcesGenerator(
        lockFilePaths: [lockFile],
        client: _mockPubDevClient(),
      );
      final sources = await gen.generate();

      // simple.lock has 3 hosted packages (yaml, collection, path)
      // sdk_dep is source: sdk — must be excluded
      expect(sources, hasLength(3));
    });

    test('each entry has correct flatpak format', () async {
      final gen = PubSourcesGenerator(
        lockFilePaths: [lockFile],
        client: _mockPubDevClient(),
      );
      final sources = await gen.generate();
      final yaml = sources.firstWhere(
          (s) => s.url.contains('/yaml/versions/'));

      expect(yaml.toJson(), {
        'type': 'archive',
        'url':
            'https://pub.dartlang.org/packages/yaml/versions/3.1.2.tar.gz',
        'sha256': _fakeSha256,
        'dest': '.pub-cache/hosted/pub.dev/yaml-3.1.2',
        'strip-components': 0,
      });
    });

    test('deduplicates packages across multiple lock files', () async {
      final gen = PubSourcesGenerator(
        lockFilePaths: [lockFile, lockFile], // same file twice
        client: _mockPubDevClient(),
      );
      final sources = await gen.generate();
      expect(sources, hasLength(3)); // still 3, not 6
    });

    test('skips missing lock files with a warning', () async {
      final gen = PubSourcesGenerator(
        lockFilePaths: [lockFile, 'nonexistent.lock'],
        client: _mockPubDevClient(),
      );
      // Should not throw
      final sources = await gen.generate();
      expect(sources, hasLength(3));
    });
  });
}
