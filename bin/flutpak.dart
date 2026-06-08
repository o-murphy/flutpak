import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutpak/src/commands/flutter_command.dart';
import 'package:flutpak/src/commands/generate_command.dart';
import 'package:flutpak/src/commands/init_command.dart';
import 'package:flutpak/src/commands/pub_command.dart';
import 'package:flutpak/src/commands/sdk_mod_command.dart';
import 'package:flutpak/src/commands/sources_command.dart';
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
        '  flutpak sources            # pub + Flutter SDK → generated-sources.json\n'
        '  flutpak pub                # only pub packages\n'
        '  flutpak flutter            # only Flutter SDK artifacts\n'
        '  flutpak sdk-mod            # Flutter SDK module JSON for !include\n'
        '  flutpak generate --dry-run # preview what generate would do',
  )
    ..addCommand(InitCommand())
    ..addCommand(GenerateCommand())
    ..addCommand(SourcesCommand())
    ..addCommand(PubCommand())
    ..addCommand(FlutterCommand())
    ..addCommand(SdkModCommand());

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
