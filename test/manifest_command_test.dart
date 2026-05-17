import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('flatpak_gen_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // ── Helpers ────────────────────────────────────────────────────────────────

  File writeFile(String name, String content) {
    final f = File(p.join(tmp.path, name));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  String readFile(String name) =>
      File(p.join(tmp.path, name)).readAsStringSync();

  // ── Version update ─────────────────────────────────────────────────────────

  group('manifest version update', () {
    test('replaces existing version field', () async {
      final manifest = writeFile('app.yml', '''
id: io.example.App
runtime: org.gnome.Platform
version: 1.0.0
command: app
''');
      writeFile('pubspec.yaml', 'name: app\nversion: 2.3.4\n');

      final result = await _runCli([
        'manifest',
        '--manifest', manifest.path,
        '--pubspec', p.join(tmp.path, 'pubspec.yaml'),
        '--no-sources',
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(readFile('app.yml'), contains('version: 2.3.4'));
      expect(readFile('app.yml'), isNot(contains('version: 1.0.0')));
    });

    test('accepts explicit --version flag', () async {
      final manifest = writeFile('app.yml', 'id: x\nversion: 0.0.1\n');

      final result = await _runCli([
        'manifest',
        '--manifest', manifest.path,
        '--version', '9.9.9',
        '--no-sources',
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(readFile('app.yml'), contains('version: 9.9.9'));
    });

    test('warns but does not fail when version field is missing', () async {
      final manifest = writeFile('app.yml', 'id: io.example.App\ncommand: app\n');
      writeFile('pubspec.yaml', 'name: app\nversion: 1.0.0\n');

      final result = await _runCli([
        'manifest',
        '--manifest', manifest.path,
        '--pubspec', p.join(tmp.path, 'pubspec.yaml'),
        '--no-sources',
      ]);

      expect(result.exitCode, 0);
      expect(result.stderr, contains('⚠'));
    });

    test('preserves rest of manifest content', () async {
      const original = '''
id: io.example.App
runtime: org.gnome.Platform
version: 1.0.0
command: app
modules:
  - name: app
    buildsystem: simple
''';
      final manifest = writeFile('app.yml', original);
      writeFile('pubspec.yaml', 'name: app\nversion: 1.2.3\n');

      await _runCli([
        'manifest',
        '--manifest', manifest.path,
        '--pubspec', p.join(tmp.path, 'pubspec.yaml'),
        '--no-sources',
      ]);

      final updated = readFile('app.yml');
      expect(updated, contains('id: io.example.App'));
      expect(updated, contains('modules:'));
      expect(updated, contains('version: 1.2.3'));
    });

    test('reads version with build number from pubspec', () async {
      final manifest = writeFile('app.yml', 'id: x\nversion: 0.0.1\n');
      writeFile('pubspec.yaml', 'name: app\nversion: 1.0.0+42\n');

      await _runCli([
        'manifest',
        '--manifest', manifest.path,
        '--pubspec', p.join(tmp.path, 'pubspec.yaml'),
        '--no-sources',
      ]);

      expect(readFile('app.yml'), contains('version: 1.0.0+42'));
    });

    test('exits non-zero when manifest file does not exist', () async {
      final result = await _runCli([
        'manifest',
        '--manifest', p.join(tmp.path, 'missing.yml'),
        '--version', '1.0.0',
        '--no-sources',
      ]);
      expect(result.exitCode, isNot(0));
    });
  });
}

// ── CLI runner helper ──────────────────────────────────────────────────────

Future<_Result> _runCli(List<String> args) async {
  final dart = Platform.executable;
  // Run via `dart run` so we pick up the local package without compiling.
  final result = await Process.run(
    dart,
    ['run', 'bin/flatpak_gen.dart', ...args],
    workingDirectory: _packageRoot(),
  );
  return _Result(result.exitCode, result.stdout as String,
      result.stderr as String);
}

String _packageRoot() {
  // Resolve from the test file location: test/ → package root
  var dir = Directory(p.dirname(Platform.script.toFilePath()));
  while (!File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('pubspec.yaml not found');
    dir = parent;
  }
  return dir.path;
}

class _Result {
  final int exitCode;
  final String stdout;
  final String stderr;
  const _Result(this.exitCode, this.stdout, this.stderr);
}
