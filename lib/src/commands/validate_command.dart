import 'dart:io';
import 'package:args/command_runner.dart';
import '../config.dart';

/// Validates the AppStream metainfo file using appstream-util.
///
/// Requires appstream-util to be installed:
///   sudo apt install appstream
class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';
  @override
  final description =
      'Validate the AppStream metainfo file using appstream-util.\n'
      'Requires appstream-util: sudo apt install appstream';

  ValidateCommand() {
    argParser
      ..addOption('config',
          abbr: 'c',
          help: 'Config file path.',
          defaultsTo: 'flutpak.yaml')
      ..addOption('metainfo',
          abbr: 'm',
          help: 'Path to metainfo XML (auto-detected from config if omitted).')
      ..addFlag('pedantic',
          help: 'Pass --pedantic to appstream-util for stricter checks.');
  }

  @override
  Future<void> run() async {
    _checkAppstreamUtil();

    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);
    final pedantic = argResults!['pedantic'] as bool;

    final metainfoPath = argResults!['metainfo'] as String? ??
        _resolveMetainfoPath(cfg);

    if (metainfoPath == null) {
      stderr.writeln('error: metainfo path not found.\n'
          '   Add manifest.app_id to flutpak config or pass --metainfo <path>.');
      exit(1);
    }

    if (!File(metainfoPath).existsSync()) {
      stderr.writeln('error: metainfo file not found: $metainfoPath\n'
          '   Run flutpak prepare first.');
      exit(1);
    }

    stderr.writeln('→  validating: $metainfoPath');

    final args = [
      'validate',
      if (pedantic) '--pedantic',
      metainfoPath,
    ];

    final result = Process.runSync('appstream-util', args);

    if (result.stdout.toString().trim().isNotEmpty) {
      stdout.write(result.stdout);
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      stderr.write(result.stderr);
    }

    if (result.exitCode != 0) {
      exit(result.exitCode);
    }
    stderr.writeln('✓  metainfo valid');
  }

  String? _resolveMetainfoPath(FlatpakGenConfig cfg) {
    if (cfg.manifest == null) return null;
    return cfg.manifest!.metainfo?.path ??
        'flatpak/${cfg.manifest!.appId}.metainfo.xml';
  }

  void _checkAppstreamUtil() {
    final result = Process.runSync('appstream-util', ['--version']);
    if (result.exitCode != 0) {
      stderr.writeln('error: appstream-util is not installed.\n'
          'Install it with:\n'
          '  sudo apt install appstream   # Debian/Ubuntu\n'
          '  sudo dnf install appstream   # Fedora');
      exit(1);
    }
  }
}
