@Tags(['integration'])
library;

import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final lockFile = p.join('test', 'fixtures', 'simple.lock');

  group('PubSourcesGenerator — real pub.dev API', () {
    late List<FlatpakSource> sources;
    late List<ArchiveSource> archives;
    late List<InlineSource> inlines;

    setUpAll(() async {
      final gen = PubSourcesGenerator(lockFilePaths: [lockFile]);
      sources = await gen.generate();
      archives = sources.whereType<ArchiveSource>().toList();
      inlines = sources.whereType<InlineSource>().toList();
    });

    test('returns two entries per hosted package (archive + inline)', () {
      expect(sources, hasLength(6));
      expect(archives, hasLength(3));
      expect(inlines, hasLength(3));
    });

    test('every archive SHA-256 is a valid 64-char hex string', () {
      for (final s in archives) {
        expect(
          s.sha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: 'invalid SHA-256 for ${s.url}',
        );
      }
    });

    test('each archive entry has correct flatpak archive format', () {
      for (final s in archives) {
        final j = s.toJson();
        expect(j['type'], 'archive');
        expect(j['strip-components'], 0);
        expect(j['dest'], startsWith('.pub-cache/hosted/pub.dev/'));
        expect(j['url'], contains('pub.dartlang.org'));
      }
    });

    test('each inline entry has correct flatpak inline format', () {
      for (final s in inlines) {
        final j = s.toJson();
        expect(j['type'], 'inline');
        expect(j['dest'], '.pub-cache/hosted-hashes/pub.dev');
        expect(j['dest-filename'], endsWith('.sha256'));
        expect(j['contents'], matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });

    test('contains expected packages', () {
      final urls = archives.map((s) => s.url).toList();
      expect(urls, anyElement(contains('/yaml/versions/3.1.2')));
      expect(urls, anyElement(contains('/collection/versions/1.18.0')));
      expect(urls, anyElement(contains('/path/versions/1.9.0')));
    });
  });
}
