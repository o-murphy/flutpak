import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../utils/download_cache.dart';

class FlutterCommand extends Command<void> {
  @override
  final name = 'flutter';
  @override
  final description = 'Generate Flutter SDK sources from a local Flutter install.';

  FlutterCommand() {
    argParser
      ..addOption('sdk',
          abbr: 's',
          help: 'Path to Flutter SDK. Defaults to \$FLUTTER_ROOT.')
      ..addOption('output',
          abbr: 'o',
          help: 'Output JSON file.',
          defaultsTo: null)
      ..addOption('patch',
          help: 'Path to shared.sh.patch. '
              'Omit to use the built-in patch (written next to the output file).')
      ..addOption('config',
          abbr: 'c',
          help: 'Config file.',
          defaultsTo: 'flatpak_gen.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];

    if (sdkPath == null) {
      usageException(
          'Flutter SDK path required: --sdk or \$FLUTTER_ROOT or config flutter.sdk');
    }

    final output = argResults!['output'] as String? ?? cfg.output;
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    final cache = LocalDownloadCache();
    try {
      final gen = FlutterSdkGenerator(
        sdkPath: sdkPath,
        patchPath: patchPath,
        outputDir: p.dirname(p.absolute(output)),
        cache: cache,
      );
      final sources = await gen.generate();

      final json = const JsonEncoder.withIndent('    ')
          .convert(sources.map((s) => s.toJson()).toList());
      File(output)
        ..createSync(recursive: true)
        ..writeAsStringSync('$json\n');

      stderr.writeln('✓  ${sources.length} flutter SDK sources → $output');
    } finally {
      cache.dispose();
    }
  }
}
