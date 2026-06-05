import 'dart:io';
import '../config.dart';
import '../utils/log.dart';

void validateManifestAssets(FlatpakGenConfig cfg, String appId) {
  final checks = [
    cfg.effectiveMetainfoPath(appId),
    cfg.effectiveDesktopEntryPath(appId),
    ...cfg.effectiveIcons(appId).map((e) => e.path),
  ];
  final missing = checks.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    for (final m in missing) {
      logError('asset file not found: $m');
    }
    exit(1);
  }
}
