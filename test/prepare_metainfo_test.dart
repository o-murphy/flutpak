import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('flutpak_generate_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeFile(String rel, String content) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  bool fileExists(String rel) => File(p.join(tmp.path, rel)).existsSync();

  // workingDirectory is set to tmp.path so that output paths in the config
  // (e.g. "output: flatpak") resolve relative to the temp dir.
  // The script path is absolute so dart can find it regardless of CWD.
  Future<_Result> runGenerate(List<String> extra) => _runCli(
        [
          'generate',
          '--no-sources',
          '--config',
          p.join(tmp.path, 'flutpak.yaml'),
          ...extra
        ],
        workingDirectory: tmp.path,
      );

  // ── dry-run ────────────────────────────────────────────────────────────────────

  group('generate --dry-run', () {
    setUp(() {
      writeFile('flutpak.yaml', '''
output: flatpak
manifest:
  app-id: io.example.App
  runtime-version: "25.08"
  command: app
''');
    });

    test('does not write any files', () async {
      final result = await runGenerate(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(fileExists('flatpak/generated/generated-sources.json'), isFalse);
      expect(fileExists('flatpak/generated/io.example.App.yml'), isFalse);
    });

    test('prints dry-run message', () async {
      final result = await runGenerate(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stderr, contains('dry-run'));
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────────

// Absolute path to the entry-point script, resolved from the test process CWD
// (project root). Must be evaluated here, not inside the subprocess.
final _flutpakScript = p.absolute('bin', 'flutpak.dart');

Future<_Result> _runCli(List<String> args, {String? workingDirectory}) async {
  final result = await Process.run(
    Platform.executable,
    ['run', _flutpakScript, ...args],
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
