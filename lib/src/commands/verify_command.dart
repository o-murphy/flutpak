import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../config.dart';

/// Verifies that a Flatpak manifest's app module is pinned to a specific
/// tag and commit.
///
/// The app module is always the LAST entry in the manifest's `modules:` list;
/// dependency modules (e.g. bclibc) come first and are ignored.
class VerifyCommand extends Command<void> {
  @override
  final name = 'verify';
  @override
  final description =
      'Verify that a Flatpak manifest is pinned to a specific tag and commit.\n'
      'Reads the last module\'s first git source — dependency modules are skipped.';

  VerifyCommand() {
    argParser
      ..addOption('manifest',
          abbr: 'm',
          help: 'Path to the Flatpak manifest YAML. '
              'Auto-detected from config output dir if omitted.')
      ..addOption('config',
          abbr: 'c',
          help: 'flutpak config file (used for manifest auto-detection).',
          defaultsTo: 'flutpak.yaml')
      ..addOption('tag',
          abbr: 't',
          help: 'Expected release tag (e.g. v0.1.15). '
              'If omitted, only checks that no placeholder remains.')
      ..addOption('commit',
          help: 'Expected full commit SHA. '
              'If omitted, only checks that no placeholder remains.');
  }

  @override
  Future<void> run() async {
    final manifestPath = _resolveManifest();
    final expectedTag = argResults!['tag'] as String?;
    final expectedCommit = argResults!['commit'] as String?;

    final file = File(manifestPath);
    if (!file.existsSync()) {
      usageException('Manifest not found: $manifestPath');
    }

    final raw = loadYaml(file.readAsStringSync());
    if (raw is! Map) {
      _fail('Invalid YAML in manifest: $manifestPath');
    }

    final modules = raw['modules'];
    if (modules is! List || modules.isEmpty) {
      _fail('No modules list in manifest: $manifestPath');
    }

    // The app module is always last; dependency modules come first.
    final lastModule = modules.last;
    if (lastModule is! Map) {
      _fail('Last module must be an inline map (not a file reference): $manifestPath');
    }

    final sources = lastModule['sources'];
    if (sources is! List) {
      _fail('No sources list in last module of: $manifestPath');
    }

    Map? gitSource;
    for (final s in sources) {
      if (s is Map && s['type'] == 'git') {
        gitSource = s;
        break;
      }
    }
    if (gitSource == null) {
      _fail('No git source found in last module of: $manifestPath');
    }

    final manifestTag = gitSource['tag']?.toString() ?? '';
    final manifestCommit = gitSource['commit']?.toString() ?? '';

    if (manifestTag.contains('__FLATPAK') ||
        manifestCommit.contains('__FLATPAK')) {
      stderr.writeln(
          '::error::Manifest contains unresolved __FLATPAK_* placeholder values');
      stderr.writeln(
          "Run 'flutpak prepare --tag <tag> --commit <sha>' and commit the result.");
      exit(1);
    }

    if (manifestTag.isEmpty || manifestCommit.isEmpty) {
      _fail('Last module git source is missing tag or commit in: $manifestPath');
    }

    if (expectedTag != null || expectedCommit != null) {
      var fail = false;
      if (expectedTag != null && manifestTag != expectedTag) {
        stderr.writeln(
            '::error::Manifest tag ($manifestTag) ≠ expected ($expectedTag)');
        fail = true;
      }
      if (expectedCommit != null && manifestCommit != expectedCommit) {
        final short =
            manifestCommit.substring(0, manifestCommit.length.clamp(0, 12));
        final shortExp =
            expectedCommit.substring(0, expectedCommit.length.clamp(0, 12));
        stderr.writeln(
            '::error::Manifest commit ($short) ≠ expected ($shortExp)');
        fail = true;
      }
      if (fail) {
        stderr.writeln('');
        stderr.writeln(
            "Run 'flutpak prepare --tag ${expectedTag ?? manifestTag} "
            "--commit ${expectedCommit ?? manifestCommit}' locally,");
        stderr.writeln(
            'commit the updated flatpak/ files, and re-push the tag.');
        exit(1);
      }
    }

    final short =
        manifestCommit.substring(0, manifestCommit.length.clamp(0, 12));
    stderr.writeln('✓ manifest is pinned: tag=$manifestTag  commit=$short');
  }

  String _resolveManifest() {
    final arg = argResults!['manifest'] as String?;
    if (arg != null && arg.isNotEmpty) return arg;

    try {
      final cfg = FlatpakGenConfig.load(argResults!['config'] as String);
      final dir = Directory(p.absolute(cfg.output));
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (f.path.endsWith('.yml') || f.path.endsWith('.yaml')) {
            stderr.writeln('Auto-detected manifest: ${f.path}');
            return f.path;
          }
        }
      }
    } catch (_) {}

    usageException(
        'No manifest path provided and none auto-detected. '
        'Pass --manifest <path> or ensure flutpak.yaml is present.');
  }

  Never _fail(String message) {
    stderr.writeln('::error::$message');
    exit(1);
  }
}
