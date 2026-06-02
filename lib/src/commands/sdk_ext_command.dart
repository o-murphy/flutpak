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
      'The output can be submitted as org.freedesktop.Sdk.Extension.flutter3.\n\n'
      'Source modes (pick one):\n'
      '  --flutter-version   fetch version info from GitHub (no local SDK needed)\n'
      '  --sdk               read version info from a local Flutter SDK clone\n'
      '  extension.flutter-version in flutpak.yaml  (same as --flutter-version)';

  SdkExtCommand() {
    argParser
      ..addOption('flutter-version',
          abbr: 'f',
          help: 'Flutter version tag to generate the extension for (e.g. 3.44.0).\n'
              'Fetches version files from GitHub; no local SDK required.\n'
              'Takes precedence over config extension.flutter-version and --sdk.')
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('runtime-version',
          abbr: 'r',
          help: 'Freedesktop SDK runtime version (e.g. 25.08).',
          defaultsTo: '25.08')
      ..addOption('output',
          abbr: 'o',
          help: 'Output JSON manifest file.',
          defaultsTo: 'org.freedesktop.Sdk.Extension.flutter3.json')
      ..addOption('patch',
          help: 'Relative path to shared.sh.patch to embed in sources.')
      ..addOption('id',
          help: 'Override the extension app-id.\n'
              'Defaults to org.freedesktop.Sdk.Extension.flutter<major>.')
      ..addOption('config',
          abbr: 'c', help: 'Config file.', defaultsTo: 'flutpak.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    // Resolve flutter version: CLI flag > config extension.flutter-version
    final cliFlutterVersion = argResults!['flutter-version'] as String?;
    final cfgFlutterVersion = cfg.extension?.flutterVersion;
    final flutterVersion = cliFlutterVersion ?? cfgFlutterVersion;

    // Resolve SDK path: CLI flag > FLUTTER_ROOT > config flutter.sdk
    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];

    if (flutterVersion == null && sdkPath == null) {
      usageException(
        'Flutter source required. Provide one of:\n'
        '  --flutter-version <tag>        (fetches from GitHub)\n'
        '  --sdk <path>                   (reads local SDK)\n'
        '  extension.flutter-version in flutpak.yaml',
      );
    }

    // Resolve remaining options (CLI flags take precedence over config)
    final runtimeVersion = argResults!['runtime-version'] as String? ??
        cfg.extension?.runtimeVersion ??
        '25.08';
    final output = argResults!['output'] as String;
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;
    final extensionId =
        argResults!['id'] as String? ?? cfg.extension?.id;

    final cache = LocalDownloadCache();
    try {
      final gen = SdkExtensionGenerator(
        sdkPath: flutterVersion != null ? null : sdkPath,
        flutterVersion: flutterVersion,
        runtimeVersion: runtimeVersion,
        patchPath: patchPath,
        extensionId: extensionId,
        cache: cache,
      );
      final manifest = await gen.generate();

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
