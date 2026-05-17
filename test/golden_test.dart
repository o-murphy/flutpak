import 'dart:convert';
import 'dart:io';

import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fakeSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _goldenPath = 'test/fixtures/pub_sources_golden.json';

void main() {
  group('PubSourcesGenerator golden output', () {
    test('matches golden file', () async {
      final gen = PubSourcesGenerator(
        lockFilePaths: [p.join('test', 'fixtures', 'simple.lock')],
        client: MockClient(
          (req) async => http.Response(
            jsonEncode({'archive_sha256': _fakeSha256}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final sources = await gen.generate();
      final actual = const JsonEncoder.withIndent('  ')
          .convert(sources.map((s) => s.toJson()).toList());

      final goldenFile = File(_goldenPath);
      if (!goldenFile.existsSync()) {
        goldenFile
          ..createSync(recursive: true)
          ..writeAsStringSync('$actual\n');
        fail('Golden file did not exist — created at $_goldenPath. '
            'Review it and re-run the test.');
      }

      expect(actual, goldenFile.readAsStringSync().trimRight());
    });
  });
}
