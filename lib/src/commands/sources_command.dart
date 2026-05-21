import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../utils/sources_util.dart';

/// Combines pub + Flutter SDK sources into a single generated-sources.json.
class SourcesCommand extends Command<void> {
  @override
  final name = 'sources';
  @override
  final description =
      'Generate combined pub + Flutter SDK sources (default command).';

  SourcesCommand() {
    argParser
      ..addMultiOption('lock',
          abbr: 'l', help: 'pubspec.lock paths (glob and \$ENV supported).')
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('output',
          abbr: 'o',
          help: 'Output directory (generated-sources.json is written inside).')
      ..addOption('patch', help: 'Relative path to shared.sh.patch.')
      ..addOption('config',
          abbr: 'c', help: 'Config file.', defaultsTo: 'flutpak.yaml')
      ..addFlag('pub-only', help: 'Skip Flutter SDK sources.')
      ..addFlag('flutter-only', help: 'Skip pub sources.');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];

    final lockArg = argResults!['lock'] as List<String>;
    final lockPaths =
        lockArg.isNotEmpty ? lockArg : cfg.effectivePubLocks(sdkPath);

    final outputDir = argResults!['output'] as String? ?? cfg.output;
    final outputPath = p.join(outputDir, 'generated-sources.json');
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    await generateSourcesJson(
      lockPaths: lockPaths,
      sdkPath: sdkPath,
      patchPath: patchPath,
      outputDir: outputDir,
      outputPath: outputPath,
      pubOnly: argResults!['pub-only'] as bool,
      flutterOnly: argResults!['flutter-only'] as bool,
    );
  }
}
