import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/log.dart';

class CacheCommand extends Command<void> {
  @override
  final name = 'cache';
  @override
  final description = 'Manage the flutpak local cache (~/.cache/flutpak/).';

  CacheCommand() {
    addSubcommand(_CacheClearCommand());
  }

  @override
  Future<void> run() async {
    printUsage();
  }
}

class _CacheClearCommand extends Command<void> {
  @override
  final name = 'clear';
  @override
  final description = 'Delete all cached data from ~/.cache/flutpak/.';

  @override
  Future<void> run() async {
    final cacheDir = Directory(p.join(
      Platform.environment['HOME'] ?? '.',
      '.cache',
      'flutpak',
    ));
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
      logInfo('✓  cache cleared: ${cacheDir.path}');
    } else {
      logInfo('cache is already empty: ${cacheDir.path}');
    }
  }
}
