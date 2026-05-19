import 'dart:io';
import 'package:yaml/yaml.dart';
import 'config.dart';

/// A registry entry describing how to patch a known pub package for Flatpak.
class RegistryEntry {
  final String package;

  /// Semver constraint string (e.g. ">=5.0.0 <6.0.0"). Null = any version.
  final String? versionConstraint;

  /// Subpath within the package root where the patch should be applied.
  final String? destSubpath;

  /// Filename to look for inside the project's patches directory.
  final String patchFilename;

  const RegistryEntry({
    required this.package,
    this.versionConstraint,
    this.destSubpath,
    required this.patchFilename,
  });
}

/// Community-maintained registry of packages that commonly need Flatpak patches.
///
/// When [resolvePatchEntries] finds a matching package in pubspec.lock and a
/// patch file on disk, it emits a [PatchEntry] with the correct `dest` path.
const List<RegistryEntry> _registry = [
  RegistryEntry(
    package: 'objectbox_flutter_libs',
    patchFilename: 'objectbox_flutter_libs.patch',
  ),
  RegistryEntry(
    package: 'sqflite_common_ffi',
    destSubpath: 'linux',
    patchFilename: 'sqflite_common_ffi.patch',
  ),
];

/// Resolves patch entries from the registry for packages found in [lockPath].
///
/// For each registry entry whose package appears in the lock file:
///   1. Looks for a patch file under `{patchesDir}/{entry.patchFilename}`.
///   2. If found, emits a [PatchEntry] with the resolved version and dest.
///
/// Explicit [projectPatches] from the project config override registry entries
/// for the same package (project wins).
List<PatchEntry> resolvePatchEntries({
  required List<String> lockPaths,
  String patchesDir = 'flatpak/patches',
  List<PatchEntry> projectPatches = const [],
}) {
  final lockedVersions = _readLockedVersions(lockPaths);
  final overriddenPackages =
      projectPatches.map((e) => e.package).toSet();

  final entries = <PatchEntry>[...projectPatches];

  for (final entry in _registry) {
    if (overriddenPackages.contains(entry.package)) continue;
    final version = lockedVersions[entry.package];
    if (version == null) continue;

    final patchFile = File('$patchesDir/${entry.patchFilename}');
    if (!patchFile.existsSync()) continue;

    entries.add(PatchEntry(
      package: entry.package,
      version: version,
      path: patchFile.path,
      destSubpath: entry.destSubpath,
    ));
  }

  return entries;
}

Map<String, String> _readLockedVersions(List<String> lockPaths) {
  final versions = <String, String>{};
  for (final path in lockPaths) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final yaml = loadYaml(f.readAsStringSync());
    if (yaml is! Map) continue;
    final pkgs = yaml['packages'];
    if (pkgs is! Map) continue;
    for (final e in pkgs.entries) {
      final name = e.key as String;
      final info = e.value;
      if (info is! Map || info['source'] != 'hosted') continue;
      final ver = info['version'] as String?;
      if (ver != null) versions[name] = ver;
    }
  }
  return versions;
}
