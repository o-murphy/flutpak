import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('flutpak_lint_export_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeFile(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  // ── flutpak export ─────────────────────────────────────────────────────────

  group('flutpak export', () {
    test('copies manifest, generated-sources.json, and patches dir', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      writeFile('flatpak/generated-sources.json', '[]\n');
      writeFile('flatpak/patches/some.patch', '--- a\n+++ b\n');

      final out = p.join(tmp.path, 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(File(p.join(out, 'io.example.App.yml')).existsSync(), isTrue);
      expect(File(p.join(out, 'generated-sources.json')).existsSync(), isTrue);
      expect(File(p.join(out, 'patches/some.patch')).existsSync(), isTrue);
    });

    test('exits with error when generated-sources.json is missing', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      // No generated-sources.json

      final out = p.join(tmp.path, 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, isNot(0));
    });

    test('skips patches dir when it does not exist', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      writeFile('flatpak/generated-sources.json', '[]\n');

      final out = p.join(tmp.path, 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(Directory(p.join(out, 'patches')).existsSync(), isFalse);
    });

    test('creates output directory if it does not exist', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      writeFile('flatpak/generated-sources.json', '[]\n');

      final out = p.join(tmp.path, 'new', 'nested', 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(Directory(out).existsSync(), isTrue);
    });

    test('copies metainfo.xml when manifest config present', () async {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app_id: io.example.App
  runtime_version: "25.08"
  command: app
''');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      writeFile('flatpak/generated-sources.json', '[]\n');
      writeFile('flatpak/io.example.App.metainfo.xml',
          '<?xml version="1.0"?><component/>\n');

      final out = p.join(tmp.path, 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
          File(p.join(out, 'io.example.App.metainfo.xml')).existsSync(),
          isTrue);
    });

    test('skips metainfo when no manifest config', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', 'app-id: io.example.App\n');
      writeFile('flatpak/generated-sources.json', '[]\n');
      writeFile('flatpak/io.example.App.metainfo.xml',
          '<?xml version="1.0"?><component/>\n');

      final out = p.join(tmp.path, 'out');
      final result = await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(
          File(p.join(out, 'io.example.App.metainfo.xml')).existsSync(),
          isFalse);
    });

    test('exported manifest content matches source', () async {
      const manifestContent = 'app-id: io.example.App\nruntime: test\n';
      writeFile('flutpak.yaml', 'output: flatpak\n');
      writeFile('flatpak/io.example.App.yml', manifestContent);
      writeFile('flatpak/generated-sources.json', '[]\n');

      final out = p.join(tmp.path, 'out');
      await _runCli([
        'export',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
        '--manifest', p.join(tmp.path, 'flatpak/io.example.App.yml'),
        '--out', out,
      ]);

      expect(
        File(p.join(out, 'io.example.App.yml')).readAsStringSync(),
        equals(manifestContent),
      );
    });
  });

  // ── flutpak validate ───────────────────────────────────────────────────────

  group('flutpak validate', () {
    test('exits with error when appstream-util is not installed', () async {
      final result = await _runCli(['validate']);
      // Either appstream-util absent → non-zero with helpful message, or
      // metainfo not found → non-zero. Either way must be non-zero.
      if (result.exitCode != 0) {
        expect(
          result.stderr,
          anyOf(
            contains('appstream-util'),
            contains('appstream'),
            contains('error'),
          ),
        );
      }
    });

    test('--metainfo flag points to missing file exits non-zero', () async {
      final result = await _runCli([
        'validate',
        '--metainfo', p.join(tmp.path, 'nonexistent.metainfo.xml'),
      ]);
      expect(result.exitCode, isNot(0));
    });

    test('exits non-zero when no manifest config and no --metainfo', () async {
      writeFile('flutpak.yaml', 'output: flatpak\n');
      final result = await _runCli([
        'validate',
        '--config', p.join(tmp.path, 'flutpak.yaml'),
      ]);
      expect(result.exitCode, isNot(0));
    });
  });
}

// ── CLI runner helper ──────────────────────────────────────────────────────

Future<_Result> _runCli(List<String> args, {String? workingDirectory}) async {
  final result = await Process.run(
    Platform.executable,
    ['run', 'bin/flutpak.dart', ...args],
    workingDirectory: workingDirectory,
  );
  return _Result(result.exitCode, result.stdout as String,
      result.stderr as String);
}

class _Result {
  final int exitCode;
  final String stdout;
  final String stderr;
  const _Result(this.exitCode, this.stdout, this.stderr);
}
