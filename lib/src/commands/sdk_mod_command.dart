import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../utils/download_cache.dart';
import '../utils/log.dart';

/// Generates a standalone Flutter module JSON for a specific Flutter version.
///
/// The output can be `!include`-d in any flatpak manifest or SDK Extension:
///
/// ```yaml
/// modules:
///   - !include modules/flutter/flutter-3.44.1.json
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
      '    "modules": [{ "!include": "modules/flutter-sdk/flutter-sdk-3.44.1.json" }] }';

  SdkModCommand() {
    argParser
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
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

    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];

    if (sdkPath == null) {
      usageException(
          'Flutter SDK path required: --sdk or \$FLUTTER_ROOT or config flutter.sdk');
    }

    final outputDir = p.absolute(argResults!['output'] as String);
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    final flutterVersion = FlutterSdkGenerator.readFlutterVersion(sdkPath);
    final outputFile = p.join(outputDir, 'flutter-sdk-$flutterVersion.json');

    final cache = LocalDownloadCache();
    try {
      final sdkGen = FlutterSdkGenerator(
        sdkPath: sdkPath,
        patchPath: patchPath,
        outputDir: outputDir,
        cache: cache,
      );
      final sources = await sdkGen.generate();

      final module = {
        'name': 'flutter-sdk',
        'buildsystem': 'simple',
        'build-commands': _buildCommands(),
        'sources': sources.map((s) => s.toJson()).toList(),
      };

      final json = const JsonEncoder.withIndent('    ').convert(module);
      File(outputFile)
        ..createSync(recursive: true)
        ..writeAsStringSync('$json\n');

      logInfo('✓  Flutter SDK module → $outputFile');
      logInfo('   Version: $flutterVersion');
      logInfo('   Include in manifest: !include $outputFile');
    } finally {
      cache.dispose();
    }
  }

  static List<String> _buildCommands() => [
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine-dart-sdk.stamp',
        'cp flutter/bin/internal/material_fonts.version flutter/bin/cache/material_fonts.stamp',
        'cp flutter/bin/internal/gradle_wrapper.version flutter/bin/cache/gradle_wrapper.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine_stamp.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/flutter_sdk.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/font-subset.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/linux-sdk.stamp',
        'mkdir -p /var/lib && cp -r flutter /var/lib',
      ];
}
