import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../config.dart';
import '../generators/pub_sources.dart';

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
          help: 'Output JSON file.',
          defaultsTo: null)
      ..addOption('config',
          abbr: 'c',
          help: 'Config file.',
          defaultsTo: 'flutpak.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final locks = argResults!['lock'] as List<String>;
    final lockPaths = locks.isNotEmpty ? locks : cfg.pubLocks;
    final output = argResults!['output'] as String? ?? cfg.output;

    final gen = PubSourcesGenerator(lockFilePaths: lockPaths);
    final sources = await gen.generate();

    final json = const JsonEncoder.withIndent('    ')
        .convert(sources.map((s) => s.toJson()).toList());
    File(output)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    stderr.writeln('✓  ${sources.length} pub sources → $output');
  }
}
