import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../models/flatpak_source.dart';
import '../utils/download_cache.dart';
import '../utils/log.dart';

/// Generates a standalone Flutter module JSON for a specific Flutter version.
///
/// The output can be `!include`-d in any flatpak manifest or SDK Extension:
///
/// ```yaml
/// modules:
///   - !include modules/flutter-sdk/flutter-sdk-3.44.1.json
/// ```
class SdkModCommand extends Command<void> {
  @override
  final name = 'sdk-mod';
  @override
  final description =
      'Generate a reusable Flutter SDK module JSON for !include in flatpak manifests.\n'
      'Output: modules/flutter-sdk/flutter-sdk-{version}.json\n\n'
      'To wrap as an SDK Extension, create a thin manifest alongside it:\n'
      '  { "id": "org.freedesktop.Sdk.Extension.flutter3", "build-extension": true,\n'
      '    "modules": [{ "!include": "modules/flutter-sdk/flutter-sdk-3.44.2.json" }] }';

  SdkModCommand() {
    argParser
      ..addOption('flutter',
          abbr: 'f',
          help: 'Flutter SDK git ref (tag, branch, or commit SHA). '
              'Overrides flutter.ref from config.')
      ..addOption('output',
          abbr: 'o',
          help: 'Output directory for the module file.',
          defaultsTo: 'modules/flutter-sdk')
      ..addOption('patch',
          help: 'Relative path to shared.sh.patch to embed in sources.')
      ..addOption('config',
          abbr: 'c', help: 'Config file.', defaultsTo: 'flutpak.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final flutterRef = argResults!['flutter'] as String? ?? cfg.flutterRef;

    if (flutterRef == null) {
      usageException(
          'Flutter ref required: --flutter <ref> or config flutter.ref');
    }

    final outputDir = p.absolute(argResults!['output'] as String);
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    final cache = LocalDownloadCache();
    final sdkGen = FlutterSdkGenerator(
      flutterRef: flutterRef,
      patchPath: patchPath,
      outputDir: outputDir,
      cache: cache,
    );
    try {
      final sources = await sdkGen.generate();

      final flutterVersion =
          sources.whereType<GitSource>().firstOrNull?.tag ?? flutterRef;

      final outputFile = p.join(outputDir, 'flutter-sdk-$flutterVersion.json');

      final module = {
        'name': 'flutter-sdk',
        'buildsystem': 'simple',
        'build-commands': FlutterSdkGenerator.buildCommands(),
        'sources': sources.map((s) => s.toJson()).toList(),
      };

      final json = const JsonEncoder.withIndent('    ').convert(module);
      File(outputFile)
        ..createSync(recursive: true)
        ..writeAsStringSync('$json\n');

      logInfo('✓  Flutter SDK module → $outputFile');
      logInfo('   Ref: $flutterRef');
      logInfo('   Include in manifest: !include $outputFile');
    } finally {
      sdkGen.dispose();
      cache.dispose();
    }
  }
}
