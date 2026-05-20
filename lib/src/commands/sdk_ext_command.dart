import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../config.dart';
import '../generators/sdk_extension.dart';
import '../utils/download_cache.dart';

class SdkExtCommand extends Command<void> {
  @override
  final name = 'sdk-ext';
  @override
  final description =
      'Generate a Flathub SDK Extension manifest for the Flutter SDK.\n'
      'The output can be submitted as org.freedesktop.Sdk.Extension.flutter3.';

  SdkExtCommand() {
    argParser
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('runtime-version',
          abbr: 'r',
          help: 'Freedesktop SDK runtime version (e.g. 25.08).',
          defaultsTo: '25.08')
      ..addOption('output',
          abbr: 'o',
          help: 'Output YAML manifest file.',
          defaultsTo: 'org.freedesktop.Sdk.Extension.flutter3.yml')
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

    final runtimeVersion = argResults!['runtime-version'] as String;
    final output = argResults!['output'] as String;
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    final cache = LocalDownloadCache();
    try {
      final gen = SdkExtensionGenerator(
        sdkPath: sdkPath,
        runtimeVersion: runtimeVersion,
        patchPath: patchPath,
        cache: cache,
      );
      final manifest = await gen.generate();

      // Write as JSON (flatpak-builder accepts both JSON and YAML manifests)
      final json = const JsonEncoder.withIndent('  ').convert(manifest);
      File(output)
        ..createSync(recursive: true)
        ..writeAsStringSync('$json\n');

      stderr.writeln('✓  SDK Extension manifest → $output');
      stderr.writeln('   App ID: ${manifest['id']}  runtime: $runtimeVersion');
    } finally {
      cache.dispose();
    }
  }
}
