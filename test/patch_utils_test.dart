import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

void main() {
  group('replaceMetainfoScreenshots', () {
    const screenshots = [
      ScreenshotConfig(path: 'docs/screenshots/home.png', default_: true),
      ScreenshotConfig(path: 'docs/screenshots/conditions.png'),
    ];

    const existingMetainfo = '''<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.o_murphy.ebalistyka</id>
  <screenshots>
    <screenshot type="default">
      <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/v0.1.14/docs/screenshots/home.png</image>
    </screenshot>
    <screenshot>
      <image>https://raw.githubusercontent.com/o-murphy/ebalistyka-app/v0.1.14/docs/screenshots/conditions.png</image>
    </screenshot>
  </screenshots>
</component>''';

    test('replaces block with config-built URLs for tag', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'v0.1.15',
      );
      expect(result, contains('ebalistyka-app/v0.1.15/docs/screenshots/home.png'));
      expect(result, contains('ebalistyka-app/v0.1.15/docs/screenshots/conditions.png'));
      expect(result, isNot(contains('v0.1.14')));
      expect(result, contains('<screenshot type="default">'));
    });

    test('replaces block with commit SHA', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'abc1234567890abcdef',
      );
      expect(result, contains('ebalistyka-app/abc1234567890abcdef/docs/screenshots/'));
      expect(result, isNot(contains('v0.1.14')));
    });

    test('falls back to /main/ when ref is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: '',
      );
      expect(result, contains('ebalistyka-app/main/docs/screenshots/home.png'));
    });

    test('returns content unchanged when screenshots list is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: const [],
        repoSlug: 'o-murphy/ebalistyka-app',
        ref: 'v0.1.15',
      );
      expect(result, equals(existingMetainfo));
    });

    test('returns content unchanged when repoSlug is empty', () {
      final result = replaceMetainfoScreenshots(
        existingMetainfo,
        screenshots: screenshots,
        repoSlug: '',
        ref: 'v0.1.15',
      );
      expect(result, equals(existingMetainfo));
    });
  });

  group('patchMetainfoReleases', () {
    final date = DateTime.utc(2026, 5, 19);

    test('strips leading v and updates version and date', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
      expect(result, isNot(contains('version="0.1.14"')));
      expect(result, isNot(contains('date="2026-05-14"')));
    });

    test('handles tag without leading v', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, '0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('handles pre-release tag (v0.1.15-beta.1)', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15-beta.1', date);
      expect(result, contains('version="0.1.15-beta.1"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('only updates first <release> entry', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
  <release version="0.1.13" date="2026-04-01"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      // Second entry should remain unchanged
      expect(result, contains('version="0.1.13"'));
      expect(result, contains('date="2026-04-01"'));
    });

    test('preserves surrounding whitespace and indentation', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('  <release version="0.1.15" date="2026-05-19"/>'));
    });

    test('returns content unchanged when tag is empty', () {
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, '', date);
      expect(result, equals(input));
    });

    test('returns content unchanged when no <releases> section exists', () {
      const input = '''
<component>
  <name>My App</name>
</component>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, equals(input));
    });

    test('pads month and day with leading zeros', () {
      final earlyDate = DateTime.utc(2026, 1, 5);
      const input = '''
<releases>
  <release version="0.1.14" date="2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', earlyDate);
      expect(result, contains('date="2026-01-05"'));
    });

    test('handles single-quoted attributes', () {
      const input = '''
<releases>
  <release version='0.1.14' date='2026-05-14'/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });

    test('handles spaces around equals sign in attributes', () {
      const input = '''
<releases>
  <release version = "0.1.14" date = "2026-05-14"/>
</releases>
''';
      final result = patchMetainfoReleases(input, 'v0.1.15', date);
      expect(result, contains('version="0.1.15"'));
      expect(result, contains('date="2026-05-19"'));
    });
  });
}
