import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/pub_sources.dart';
import '../utils/download_cache.dart';

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
          abbr: 'l',
          help: 'pubspec.lock paths (glob and \$ENV supported).')
      ..addOption('sdk',
          abbr: 's',
          help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('output',
          abbr: 'o',
          help: 'Output directory (generated-sources.json is written inside).')
      ..addOption('patch',
          help: 'Relative path to shared.sh.patch.')
      ..addOption('config',
          abbr: 'c',
          help: 'Config file.',
          defaultsTo: 'flutpak.yaml')
      ..addFlag('pub-only', help: 'Skip Flutter SDK sources.')
      ..addFlag('flutter-only', help: 'Skip pub sources.');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final lockArg = argResults!['lock'] as List<String>;
    final lockPaths = lockArg.isNotEmpty ? lockArg : cfg.pubLocks;

    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];

    final outputDir = argResults!['output'] as String? ?? cfg.output;
    final outputFile = p.join(outputDir, 'generated-sources.json');
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;
    final pubOnly = argResults!['pub-only'] as bool;
    final flutterOnly = argResults!['flutter-only'] as bool;

    final allSources = <Map<String, dynamic>>[];
    final cache = LocalDownloadCache();

    try {
      if (!flutterOnly) {
        final pubGen = PubSourcesGenerator(lockFilePaths: lockPaths);
        final pubSources = await pubGen.generate();
        allSources.addAll(pubSources.map((s) => s.toJson()));
        stderr.writeln('pub: ${pubSources.length} entries');
      }

      if (!pubOnly) {
        if (sdkPath == null) {
          stderr.writeln(
              '⚠  Flutter SDK not found — skipping (set --sdk or \$FLUTTER_ROOT)');
        } else {
          final flutterGen = FlutterSdkGenerator(
            sdkPath: sdkPath,
            patchPath: patchPath,
            outputDir: outputDir,
            cache: cache,
          );
          final flutterSources = await flutterGen.generate();
          allSources.addAll(flutterSources.map((s) => s.toJson()));
          stderr.writeln('flutter: ${flutterSources.length} entries');
        }
      }
    } finally {
      cache.dispose();
    }

    final json =
        const JsonEncoder.withIndent('    ').convert(allSources);
    File(outputFile)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    stderr.writeln('✓  ${allSources.length} total sources → $outputFile');
  }
}
