import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';

/// Runs flatpak-builder-lint against the generated manifest and repo.
///
/// Requires org.flatpak.Builder to be installed:
///   flatpak install flathub org.flatpak.Builder
class LintCommand extends Command<void> {
  @override
  final name = 'lint';
  @override
  final description =
      'Lint the Flatpak manifest and repo using flatpak-builder-lint.\n'
      'Requires org.flatpak.Builder: flatpak install flathub org.flatpak.Builder';

  LintCommand() {
    argParser
      ..addOption('config',
          abbr: 'c',
          help: 'Config file path.',
          defaultsTo: 'flutpak.yaml')
      ..addOption('manifest',
          abbr: 'm',
          help: 'Path to manifest YAML (auto-detected from config if omitted).')
      ..addOption('repo',
          abbr: 'r',
          help: 'Path to flatpak repo to lint (optional).')
      ..addFlag('manifest-only',
          help: 'Only lint the manifest, skip repo lint.')
      ..addFlag('repo-only',
          help: 'Only lint the repo, skip manifest lint.');
  }

  @override
  Future<void> run() async {
    _checkFlatpakBuilder();

    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);
    final manifestOnly = argResults!['manifest-only'] as bool;
    final repoOnly = argResults!['repo-only'] as bool;

    final manifestPath = argResults!['manifest'] as String? ??
        _detectManifestPath(cfg);
    final repoPath = argResults!['repo'] as String?;

    var failed = false;

    if (!repoOnly) {
      if (manifestPath == null) {
        stderr.writeln('⚠  manifest not found — skipping manifest lint\n'
            '   pass --manifest <path> or add manifest.app_id to flutpak config');
      } else if (!File(manifestPath).existsSync()) {
        stderr.writeln('⚠  manifest not found: $manifestPath');
        failed = true;
      } else {
        stderr.writeln('→  linting manifest: $manifestPath');
        final ok = _runLint('manifest', manifestPath);
        if (!ok) failed = true;
      }
    }

    if (!manifestOnly && repoPath != null) {
      if (!Directory(repoPath).existsSync()) {
        stderr.writeln('⚠  repo not found: $repoPath — skipping repo lint');
      } else {
        stderr.writeln('→  linting repo: $repoPath');
        final ok = _runLint('repo', repoPath);
        if (!ok) failed = true;
      }
    }

    if (failed) exit(1);
    stderr.writeln('✓  lint passed');
  }

  bool _runLint(String subject, String path) {
    final result = Process.runSync('flatpak', [
      'run',
      '--filesystem=host',
      '--command=flatpak-builder-lint',
      'org.flatpak.Builder',
      subject,
      path,
    ]);
    if (result.stdout.toString().trim().isNotEmpty) {
      stdout.write(result.stdout);
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      stderr.write(result.stderr);
    }
    return result.exitCode == 0;
  }

  String? _detectManifestPath(FlatpakGenConfig cfg) {
    if (cfg.manifest != null) {
      return p.join('flatpak', '${cfg.manifest!.appId}.yml');
    }
    // Fall back: look for any *.yml in flatpak/
    final dir = Directory('flatpak');
    if (!dir.existsSync()) return null;
    final candidates = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
        .toList();
    if (candidates.length == 1) return candidates.first.path;
    return null;
  }

  void _checkFlatpakBuilder() {
    final result = Process.runSync('flatpak', [
      'info',
      'org.flatpak.Builder',
    ]);
    if (result.exitCode != 0) {
      stderr.writeln(
          'error: org.flatpak.Builder is not installed.\n'
          'Install it with:\n'
          '  flatpak install flathub org.flatpak.Builder');
      exit(1);
    }
  }
}
