import 'dart:io';
import '../config.dart';

void validateManifestAssets(ManifestConfig cfg) {
  final checks = [
    cfg.effectiveMetainfoPath(),
    cfg.effectiveDesktopEntryPath(),
    ...cfg.effectiveIcons().map((e) => e.path),
  ];
  final missing = checks.where((path) => !File(path).existsSync()).toList();
  if (missing.isNotEmpty) {
    for (final m in missing) {
      stderr.writeln('error: asset file not found: $m');
    }
    exit(1);
  }
}
