import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/pub_sources.dart';
import '../utils/log.dart';

class PubCommand extends Command<void> {
  @override
  final name = 'pub';
  @override
  final description = 'Generate pub package sources from pubspec.lock files.';

  PubCommand() {
    argParser
      ..addMultiOption('lock',
          abbr: 'l',
          help: 'pubspec.lock paths (glob and \$ENV supported). '
              'Repeatable. Defaults to config file or pubspec.lock.')
      ..addOption('output',
          abbr: 'o',
          help: 'Output directory (generated-sources.json is written inside).',
          defaultsTo: null)
      ..addOption('config',
          abbr: 'c', help: 'Config file.', defaultsTo: 'flutpak.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final locks = argResults!['lock'] as List<String>;
    final lockPaths = locks.isNotEmpty ? locks : cfg.pubLocks;
    final outputDir = argResults!['output'] as String? ?? cfg.output;
    final outputFile = p.join(outputDir, 'generated-sources.json');

    final gen = PubSourcesGenerator(lockFilePaths: lockPaths);
    final sources = await gen.generate();

    final json = const JsonEncoder.withIndent('    ')
        .convert(sources.map((s) => s.toJson()).toList());
    File(outputFile)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    logInfo('✓  ${sources.length} pub sources → $outputFile');
  }
}
