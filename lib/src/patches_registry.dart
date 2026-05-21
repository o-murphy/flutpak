import 'dart:io';
import 'package:pub_semver/pub_semver.dart';
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
///   1. Checks [RegistryEntry.versionConstraint] if set; skips if not satisfied.
///   2. Looks for a patch file under `{patchesDir}/{entry.patchFilename}`.
///   3. If found, emits a [PatchEntry] with the resolved version and dest.
///
/// Explicit [projectPatches] from the project config override registry entries
/// for the same package (project wins).
///
/// [registryEntries] can be supplied to override the built-in registry; used
/// only in tests.
List<PatchEntry> resolvePatchEntries({
  required List<String> lockPaths,
  String patchesDir = 'flatpak/patches',
  List<PatchEntry> projectPatches = const [],
  List<RegistryEntry>? registryEntries,
}) {
  final registry = registryEntries ?? _registry;
  final lockedVersions = _readLockedVersions(lockPaths);
  final overriddenPackages = projectPatches.map((e) => e.package).toSet();

  // Back-fill version from lock file for project patches that omit it.
  final entries = <PatchEntry>[
    for (final p in projectPatches)
      p.version != null
          ? p
          : PatchEntry(
              package: p.package,
              version: lockedVersions[p.package],
              path: p.path,
              destSubpath: p.destSubpath,
            ),
  ];

  for (final entry in registry) {
    if (overriddenPackages.contains(entry.package)) continue;
    final version = lockedVersions[entry.package];
    if (version == null) continue;

    if (entry.versionConstraint != null) {
      if (!_satisfiesConstraint(version, entry.versionConstraint!)) continue;
    }

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

/// Returns true when [versionStr] satisfies [constraintStr].
/// Malformed inputs are treated as non-matching (returns false).
bool _satisfiesConstraint(String versionStr, String constraintStr) {
  try {
    final version = Version.parse(versionStr);
    final constraint = VersionConstraint.parse(constraintStr);
    return constraint.allows(version);
  } catch (_) {
    return false;
  }
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
