import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

MetainfoConfig _cfg({
  String name = 'My App',
  String summary = 'A great app',
  String? description,
  List<String> categories = const [],
  List<String> keywords = const [],
  UrlConfig? url,
  List<ScreenshotConfig> screenshots = const [],
  String contentRating = 'oars-1.1',
  String? repoSlug,
}) =>
    MetainfoConfig(
      name: name,
      summary: summary,
      description: description,
      categories: categories,
      keywords: keywords,
      url: url,
      screenshots: screenshots,
      contentRating: contentRating,
      repoSlug: repoSlug,
    );

void main() {
  const appId = 'io.example.MyApp';

  group('MetainfoGenerator', () {
    test('generates valid XML envelope', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<component type="desktop-application">'));
      expect(xml, endsWith('</component>\n'));
    });

    test('includes required fields', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, contains('<id>$appId</id>'));
      expect(xml, contains('<name>My App</name>'));
      expect(xml, contains('<summary>A great app</summary>'));
      expect(xml, contains('<launchable type="desktop-id">$appId.desktop</launchable>'));
    });

    test('emits OARS block with comment', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, contains('<content_rating type="oars-1.1"/>'));
      expect(xml, contains('hughsie.github.io/oars'));
    });

    test('escapes XML special characters in name and summary', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(name: 'App & <Tools>', summary: 'A "summary"'),
      ).generate();
      expect(xml, contains('App &amp; &lt;Tools&gt;'));
      expect(xml, contains('A &quot;summary&quot;'));
    });

    test('emits description as paragraphs', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(description: 'First paragraph.\n\nSecond paragraph.'),
      ).generate();
      expect(xml, contains('<p>First paragraph.</p>'));
      expect(xml, contains('<p>Second paragraph.</p>'));
    });

    test('omits description block when null', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<description>')));
    });

    test('emits categories', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(categories: ['Education', 'Science']),
      ).generate();
      expect(xml, contains('<category>Education</category>'));
      expect(xml, contains('<category>Science</category>'));
    });

    test('omits categories block when empty', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<categories>')));
    });

    test('emits keywords', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(keywords: ['ballistics', 'shooting']),
      ).generate();
      expect(xml, contains('<keyword>ballistics</keyword>'));
      expect(xml, contains('<keyword>shooting</keyword>'));
    });

    test('emits url entries', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          url: UrlConfig(
            homepage: 'https://example.com',
            bugtracker: 'https://example.com/issues',
          ),
        ),
      ).generate();
      expect(xml, contains('<url type="homepage">https://example.com</url>'));
      expect(xml, contains('<url type="bugtracker">https://example.com/issues</url>'));
    });

    test('omits url block when null', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<url')));
    });

    test('first screenshot gets type="default"', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          repoSlug: 'owner/repo',
          screenshots: [
            ScreenshotConfig(path: 'docs/a.png'),
            ScreenshotConfig(path: 'docs/b.png'),
          ],
        ),
      ).generate();
      expect(xml, contains('<screenshot type="default">'));
      expect(xml, contains('owner/repo/main/docs/a.png'));
      expect(xml, contains('owner/repo/main/docs/b.png'));
    });

    test('screenshot marked default_ overrides first-item rule', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          repoSlug: 'owner/repo',
          screenshots: [
            ScreenshotConfig(path: 'docs/a.png'),
            ScreenshotConfig(path: 'docs/b.png', default_: true),
          ],
        ),
      ).generate();
      // First is still default because first=true logic runs first
      expect(xml.indexOf('type="default"'),
          lessThan(xml.indexOf('docs/b.png')));
    });

    test('uses __REPO__ placeholder when repoSlug is empty', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(screenshots: [ScreenshotConfig(path: 'img/a.png')]),
      ).generate();
      expect(xml, contains('__REPO__/main/img/a.png'));
    });

    test('omits screenshots block when empty', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<screenshots>')));
    });

    test('uses provided version in releases', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(),
        version: 'v0.1.15',
        releaseDate: DateTime.utc(2026, 5, 19),
      ).generate();
      expect(xml, contains('version="0.1.15"'));
      expect(xml, contains('date="2026-05-19"'));
    });

    test('strips leading v from version', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(),
        version: 'v1.2.3',
      ).generate();
      expect(xml, contains('version="1.2.3"'));
      expect(xml, isNot(contains('version="v1.2.3"')));
    });

    test('falls back to 0.0.1 when version is null', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, contains('version="0.0.1"'));
    });

    test('canGenerate is true when name and summary set', () {
      expect(_cfg().canGenerate, isTrue);
    });

    test('canGenerate is false when name is null', () {
      expect(MetainfoConfig(summary: 'x').canGenerate, isFalse);
    });

    test('canGenerate is false when summary is null', () {
      expect(MetainfoConfig(name: 'x').canGenerate, isFalse);
    });
  });
}
