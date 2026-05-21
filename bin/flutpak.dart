import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutpak/src/commands/flutter_command.dart';
import 'package:flutpak/src/commands/prepare_command.dart';
import 'package:flutpak/src/commands/pub_command.dart';
import 'package:flutpak/src/commands/sdk_ext_command.dart';
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
        '  flutpak prepare          # generate everything from pubspec.yaml config\n'
        '  flutpak prepare --tag v0.1.14 --commit abc1234  # CI: pin tag/commit\n'
        '  flutpak sources          # pub + Flutter SDK → generated-sources.json\n'
        '  flutpak pub              # only pub packages\n'
        '  flutpak flutter          # only Flutter SDK artifacts\n'
        '  flutpak sdk-ext          # Flutter SDK Extension manifest for Flathub\n'
        '  flutpak prepare --dry-run  # preview what prepare would do',
  )
    ..addCommand(PrepareCommand())
    ..addCommand(SourcesCommand())
    ..addCommand(PubCommand())
    ..addCommand(FlutterCommand())
    ..addCommand(SdkExtCommand());

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
