@Tags(['integration'])
library;

import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final lockFile = p.join('test', 'fixtures', 'simple.lock');

  group('PubSourcesGenerator — real pub.dev API', () {
    late List<ArchiveSource> sources;

    setUpAll(() async {
      final gen = PubSourcesGenerator(lockFilePaths: [lockFile]);
      sources = await gen.generate();
    });

    test('returns one entry per hosted package', () {
      expect(sources, hasLength(3));
    });

    test('every SHA-256 is a valid 64-char hex string', () {
      for (final s in sources) {
        expect(
          s.sha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'invalid SHA-256 for ${s.url}',
        );
      }
    });

    test('each entry has correct flatpak archive format', () {
      for (final s in sources) {
        final j = s.toJson();
        expect(j['type'], 'archive');
        expect(j['strip-components'], 0);
        expect(j['dest'], startsWith('.pub-cache/hosted/pub.dev/'));
        expect(j['url'], contains('pub.dartlang.org'));
      }
    });

    test('contains expected packages', () {
      final urls = sources.map((s) => s.url).toList();
      expect(urls, anyElement(contains('/yaml/versions/3.1.2')));
      expect(urls, anyElement(contains('/collection/versions/1.18.0')));
      expect(urls, anyElement(contains('/path/versions/1.9.0')));
    });
  });
}
