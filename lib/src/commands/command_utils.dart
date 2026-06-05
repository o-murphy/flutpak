import 'dart:io';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../utils/log.dart';

void validateManifestAssets(
  FlatpakGenConfig cfg,
  String appId, {
  String? baseDir,
}) {
  String resolve(String path) =>
      (baseDir != null && !p.isAbsolute(path)) ? p.join(baseDir, path) : path;

  final checks = [
    cfg.effectiveMetainfoPath(appId),
    cfg.effectiveDesktopEntryPath(appId),
    ...cfg.effectiveIcons(appId).map((e) => e.path),
  ];
  final missing =
      checks.where((path) => !File(resolve(path)).existsSync()).toList();
  if (missing.isNotEmpty) {
    for (final m in missing) {
      logError('asset file not found: ${resolve(m)}');
    }
    exit(1);
  }
}
