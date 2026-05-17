import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flatpak_gen/src/commands/flutter_command.dart';
import 'package:flatpak_gen/src/commands/manifest_command.dart';
import 'package:flatpak_gen/src/commands/pub_command.dart';
import 'package:flatpak_gen/src/commands/sdk_ext_command.dart';
import 'package:flatpak_gen/src/commands/sources_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'flatpak_gen',
    'Generate Flatpak source manifests for Flutter/Dart applications.\n\n'
        'Usage examples:\n'
        '  flatpak_gen sources          # pub + Flutter SDK → generated-sources.json\n'
        '  flatpak_gen pub              # only pub packages\n'
        '  flatpak_gen flutter          # only Flutter SDK artifacts\n'
        '  flatpak_gen sdk-ext          # Flutter SDK Extension manifest for Flathub\n'
        '  flatpak_gen manifest -m app.yml  # sync version + regenerate sources',
  )
    ..addCommand(SourcesCommand())
    ..addCommand(PubCommand())
    ..addCommand(FlutterCommand())
    ..addCommand(SdkExtCommand())
    ..addCommand(ManifestCommand());

  // Default to 'sources' when no subcommand given
  final effectiveArgs =
      args.isEmpty || args.first.startsWith('-') ? ['sources', ...args] : args;

  try {
    await runner.run(effectiveArgs);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  } catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}
