import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('flutpak_prepare_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeFile(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  String readFile(String rel) =>
      File(p.join(tmp.path, rel)).readAsStringSync();

  bool fileExists(String rel) => File(p.join(tmp.path, rel)).existsSync();

  // All prepare tests pass an absolute config path so prepare resolves all
  // paths relative to tmp.path without needing a special workingDirectory.
  Future<_Result> runPrepare(List<String> extra) => _runCli(
        ['prepare', '--no-sources',
         '--config', p.join(tmp.path, 'flutpak.yaml'),
         ...extra],
      );

  // ── metainfo generation ────────────────────────────────────────────────────

  group('prepare metainfo generation', () {
    setUp(() {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app_id: io.example.App
  runtime_version: "25.08"
  command: app
  metainfo:
    name: My App
    summary: A great app
    description: |
      First paragraph.

      Second paragraph.
    categories:
      - Education
''');
      // generated-sources.json must exist for prepare to proceed
      writeFile('flatpak/generated-sources.json', '[]\n');
    });

    test('creates metainfo.xml on first run', () async {
      final result = await runPrepare([]);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(fileExists('flatpak/io.example.App.metainfo.xml'), isTrue);
    });

    test('metainfo contains app-id', () async {
      await runPrepare([]);
      expect(
        readFile('flatpak/io.example.App.metainfo.xml'),
        contains('<id>io.example.App</id>'),
      );
    });

    test('metainfo contains name and summary', () async {
      await runPrepare([]);
      final xml = readFile('flatpak/io.example.App.metainfo.xml');
      expect(xml, contains('<name>My App</name>'));
      expect(xml, contains('<summary>A great app</summary>'));
    });

    test('metainfo contains description paragraphs', () async {
      await runPrepare([]);
      final xml = readFile('flatpak/io.example.App.metainfo.xml');
      expect(xml, contains('<p>First paragraph.</p>'));
      expect(xml, contains('<p>Second paragraph.</p>'));
    });

    test('metainfo contains category', () async {
      await runPrepare([]);
      expect(
        readFile('flatpak/io.example.App.metainfo.xml'),
        contains('<category>Education</category>'),
      );
    });

    test('does not overwrite existing metainfo', () async {
      writeFile('flatpak/io.example.App.metainfo.xml',
          '<!-- custom -->\n<component/>\n');
      await runPrepare([]);
      expect(
        readFile('flatpak/io.example.App.metainfo.xml'),
        contains('<!-- custom -->'),
      );
    });

    test('does not generate metainfo when name missing', () async {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app_id: io.example.App
  runtime_version: "25.08"
  command: app
  metainfo:
    summary: A great app
''');
      await runPrepare([]);
      expect(fileExists('flatpak/io.example.App.metainfo.xml'), isFalse);
    });
  });

  // ── metainfo patching (screenshots + releases) ─────────────────────────────

  group('prepare metainfo pinning', () {
    const metainfoXml = '''<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.example.App</id>
  <screenshots>
    <screenshot type="default">
      <image>https://raw.githubusercontent.com/owner/repo/main/docs/screen.png</image>
    </screenshot>
  </screenshots>
  <releases>
    <release version="0.0.1" date="2020-01-01"/>
  </releases>
</component>
''';

    setUp(() {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app_id: io.example.App
  runtime_version: "25.08"
  command: app
  metainfo:
    name: My App
    summary: A great app
    repo_slug: owner/repo
''');
      writeFile('flatpak/generated-sources.json', '[]\n');
      writeFile('flatpak/io.example.App.metainfo.xml', metainfoXml);
    });

    test('pins screenshot URLs to commit when --commit passed', () async {
      final result = await runPrepare(['--commit', 'abc1234567890']);
      expect(result.exitCode, 0, reason: result.stderr);
      final xml = readFile('flatpak/io.example.App.metainfo.xml');
      expect(xml, contains('/abc1234567890/'));
      expect(xml, isNot(contains('/main/')));
    });

    test('pins screenshot URLs to tag when --tag passed', () async {
      final result =
          await runPrepare(['--tag', 'v1.2.3', '--commit', 'abc1234567890']);
      expect(result.exitCode, 0, reason: result.stderr);
      final xml = readFile('flatpak/io.example.App.metainfo.xml');
      expect(xml, contains('/v1.2.3/'));
    });

    test('updates releases when --tag passed', () async {
      final result =
          await runPrepare(['--tag', 'v1.2.3', '--commit', 'abc1234567890']);
      expect(result.exitCode, 0, reason: result.stderr);
      final xml = readFile('flatpak/io.example.App.metainfo.xml');
      expect(xml, contains('version="1.2.3"'));
      expect(xml, isNot(contains('version="0.0.1"')));
    });
  });

  // ── dry-run ────────────────────────────────────────────────────────────────

  group('prepare --dry-run', () {
    setUp(() {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app_id: io.example.App
  runtime_version: "25.08"
  command: app
  metainfo:
    name: My App
    summary: A great app
''');
    });

    test('does not write any files', () async {
      final result = await runPrepare(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(fileExists('flatpak/generated-sources.json'), isFalse);
      expect(fileExists('flatpak/io.example.App.yml'), isFalse);
      expect(fileExists('flatpak/io.example.App.metainfo.xml'), isFalse);
    });

    test('prints what would be created', () async {
      final result = await runPrepare(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, contains('would write'));
      expect(result.stderr, contains('io.example.App.yml'));
      expect(result.stderr, contains('io.example.App.metainfo.xml'));
    });

    test('shows "would update" when manifest already exists', () async {
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      final result = await runPrepare(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, contains('would update'));
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

Future<_Result> _runCli(List<String> args,
    {String? workingDirectory}) async {
  final result = await Process.run(
    Platform.executable,
    ['run', 'bin/flutpak.dart', ...args],
    workingDirectory: workingDirectory,
  );
  return _Result(
      result.exitCode, result.stdout as String, result.stderr as String);
}

class _Result {
  final int exitCode;
  final String stdout;
  final String stderr;
  const _Result(this.exitCode, this.stdout, this.stderr);
}
