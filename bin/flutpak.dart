import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutpak/src/commands/generate_command.dart';
import 'package:flutpak/src/commands/init_command.dart';
import 'package:flutpak/src/commands/sdk_ext_command.dart';
import 'package:flutpak/src/version.dart';

Future<void> main(List<String> args) async {
  if (args.contains('-V') || args.contains('--version')) {
    stdout.writeln('flutpak $packageVersion');
    return;
  }

  final runner = CommandRunner<void>(
    'flutpak',
    'Generate Flatpak manifests and offline source bundles for Flutter apps.\n\n'
        'Usage examples:\n'
        '  flutpak init               # first-run: create template + run generate\n'
        '  flutpak init --force       # overwrite existing template files\n'
        '  flutpak generate           # update generated/ from existing template\n'
        '  flutpak generate --tag v0.1.14 --commit abc1234  # CI: pin tag/commit\n'
        '  flutpak sdk-ext            # Flutter SDK Extension manifest for Flathub\n'
        '  flutpak generate --dry-run # preview what generate would do',
  )
    ..addCommand(InitCommand())
    ..addCommand(GenerateCommand())
    ..addCommand(SdkExtCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  } catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}
