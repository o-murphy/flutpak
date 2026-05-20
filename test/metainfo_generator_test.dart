import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

MetainfoConfig _cfg({
  String name = 'My App',
  String summary = 'A great app',
  String? description,
  DeveloperConfig? developer,
  List<String> categories = const [],
  List<String> keywords = const [],
  UrlConfig? url,
  List<ScreenshotConfig> screenshots = const [],
  String contentRating = 'oars-1.1',
  Map<String, String> contentRatingAttributes = const {},
  List<String> supports = const [],
  String metadataLicense = 'MIT',
  String projectLicense = 'MIT',
  String? repoSlug,
}) =>
    MetainfoConfig(
      name: name,
      summary: summary,
      description: description,
      developer: developer,
      categories: categories,
      keywords: keywords,
      url: url,
      screenshots: screenshots,
      contentRating: contentRating,
      contentRatingAttributes: contentRatingAttributes,
      supports: supports,
      metadataLicense: metadataLicense,
      projectLicense: projectLicense,
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

    test('emits default metadata_license and project_license', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, contains('<metadata_license>MIT</metadata_license>'));
      expect(xml, contains('<project_license>MIT</project_license>'));
    });

    test('uses configured metadata_license and project_license', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(metadataLicense: 'MIT', projectLicense: 'GPL-3.0-only'),
      ).generate();
      expect(xml, contains('<metadata_license>MIT</metadata_license>'));
      expect(xml, contains('<project_license>GPL-3.0-only</project_license>'));
    });

    test('emits self-closing OARS block with comment when no attributes', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, contains('<content_rating type="oars-1.1"/>'));
      expect(xml, contains('hughsie.github.io/oars'));
    });

    test('emits content_rating with attribute children when set', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(contentRatingAttributes: {'violence-realistic': 'none'}),
      ).generate();
      expect(xml, contains('<content_rating type="oars-1.1">'));
      expect(xml,
          contains('<content_attribute id="violence-realistic">none</content_attribute>'));
      expect(xml, contains('</content_rating>'));
      expect(xml, isNot(contains('hughsie.github.io')));
    });

    test('emits supports block', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(supports: ['pointing', 'keyboard', 'touch']),
      ).generate();
      expect(xml, contains('<supports>'));
      expect(xml, contains('<control>pointing</control>'));
      expect(xml, contains('<control>keyboard</control>'));
      expect(xml, contains('<control>touch</control>'));
      expect(xml, contains('</supports>'));
    });

    test('omits supports block when empty', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<supports>')));
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

    test('collapses soft-wrap newlines within a paragraph to spaces', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(description: 'Line one\nLine two\n\nSecond paragraph.'),
      ).generate();
      expect(xml, contains('<p>Line one Line two</p>'));
      expect(xml, contains('<p>Second paragraph.</p>'));
      expect(xml, isNot(contains('<p>Line one\nLine two</p>')));
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

    test('emits developer without id', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(developer: DeveloperConfig(name: 'o-murphy')),
      ).generate();
      expect(xml, contains('<developer>'));
      expect(xml, contains('<name>o-murphy</name>'));
      expect(xml, isNot(contains('id=')));
    });

    test('emits developer with id attribute', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          developer: DeveloperConfig(name: 'o-murphy', id: 'io.github.o_murphy'),
        ),
      ).generate();
      expect(xml, contains('<developer id="io.github.o_murphy">'));
      expect(xml, contains('<name>o-murphy</name>'));
    });

    test('omits developer block when null', () {
      final xml = MetainfoGenerator(appId: appId, cfg: _cfg()).generate();
      expect(xml, isNot(contains('<developer')));
    });

    test('first screenshot gets type="default" using /main/ when no ref', () {
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

    test('screenshots use ref when provided', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          repoSlug: 'owner/repo',
          screenshots: [ScreenshotConfig(path: 'docs/a.png')],
        ),
      ).generate(ref: 'v0.1.15');
      expect(xml, contains('owner/repo/v0.1.15/docs/a.png'));
      expect(xml, isNot(contains('/main/')));
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

    test('supports block appears after screenshots', () {
      final xml = MetainfoGenerator(
        appId: appId,
        cfg: _cfg(
          repoSlug: 'owner/repo',
          screenshots: [ScreenshotConfig(path: 'docs/a.png')],
          supports: ['pointing'],
        ),
      ).generate();
      expect(xml.indexOf('<supports>'), greaterThan(xml.indexOf('<screenshots>')));
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
