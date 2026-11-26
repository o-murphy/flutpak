import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/log.dart';

/// A `source: path` package entry from a `pubspec.lock`.
class PathLockPackage {
  final String name;
  final String path;
  final bool relative;
  final String lockFilePath;

  const PathLockPackage({
    required this.name,
    required this.path,
    required this.relative,
    required this.lockFilePath,
  });
}

enum PathDepLocation {
  /// Resolved path is the repo root or a directory inside it.
  insideRepo,

  /// Relative path that resolves outside the repository.
  outsideRepo,

  /// Absolute `path:` (rejected explicitly).
  absolute,
}

class PathDepClassification {
  final PathLockPackage package;
  final PathDepLocation location;

  /// Canonical resolved path, if it could be computed.
  final String? resolvedPath;

  const PathDepClassification({
    required this.package,
    required this.location,
    this.resolvedPath,
  });
}

/// Thrown when a path dependency cannot be packaged (outside the repo or
/// an absolute path).
class PathDependencyException implements Exception {
  final String message;
  PathDependencyException(this.message);

  @override
  String toString() => message;
}

/// Reads every `source: path` package from [lockFilePath].
///
/// Missing files are skipped (the hosted-source generator already warns).
List<PathLockPackage> parsePathPackagesFromLock(String lockFilePath) {
  final file = File(lockFilePath);
  if (!file.existsSync()) return const [];
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! Map) return const [];
  final pkgs = yaml['packages'];
  if (pkgs is! Map) return const [];

  final out = <PathLockPackage>[];
  for (final entry in pkgs.entries) {
    final name = entry.key;
    final info = entry.value;
    if (name is! String || info is! Map) continue;
    if (info['source'] != 'path') continue;
    final description = info['description'];
    if (description is! Map) continue;
    final path = description['path'];
    if (path is! String || path.isEmpty) continue;
    final relative = description['relative'] == true || !p.isAbsolute(path);
    out.add(PathLockPackage(
      name: name,
      path: path,
      relative: relative && !p.isAbsolute(path),
      lockFilePath: lockFilePath,
    ));
  }
  return out;
}

/// Classifies a lock path entry against [appDir] and [repoRoot].
///
/// [appDir] must be the directory containing the lock file that declared the
/// path (lock `path:` entries are relative to that file). Do not join
/// `manifest.subdir` onto the config directory — `subdir` is relative to
/// the repository root and is only a Flatpak build working-directory hint.
/// [repoRoot] is the git checkout / Flatpak source root.
PathDepClassification classifyPathDependency({
  required PathLockPackage package,
  required String appDir,
  required String repoRoot,
}) {
  if (!package.relative || p.isAbsolute(package.path)) {
    return PathDepClassification(
      package: package,
      location: PathDepLocation.absolute,
      resolvedPath: p.normalize(package.path),
    );
  }

  final resolved = p.normalize(p.join(appDir, package.path));
  final root = p.normalize(repoRoot);
  final inside = p.equals(resolved, root) || p.isWithin(root, resolved);
  return PathDepClassification(
    package: package,
    location: inside ? PathDepLocation.insideRepo : PathDepLocation.outsideRepo,
    resolvedPath: resolved,
  );
}

/// Best-effort git repository root for [startDir], falling back to [startDir].
String resolveRepoRoot(String startDir) {
  try {
    final result = Process.runSync(
      'git',
      ['rev-parse', '--show-toplevel'],
      workingDirectory: startDir,
    );
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim();
      if (out.isNotEmpty) return p.normalize(out);
    }
  } on Object {
    // No git, or not a checkout — treat [startDir] as the repo root.
  }
  return p.normalize(startDir);
}

/// Detects path dependencies in [lockFilePaths], warns for each one, and
/// throws [PathDependencyException] for absolute or out-of-repo paths.
///
/// Each lock entry is resolved from the directory that contains that lock
/// file, not from `manifest.subdir`. In-repo path packages are expected to
/// already be present in the git checkout. The app module's `subdir:` only
/// changes the Flatpak build working directory, so relative `../` layouts
/// keep working when the checkout root is the repository root. Hosted
/// dependencies of those path packages are collected from the same lock
/// file as usual.
List<PathDepClassification> validatePathDependencies({
  required List<String> lockFilePaths,
  required String repoRoot,
}) {
  final seen = <String>{};
  final results = <PathDepClassification>[];

  for (final lockPath in lockFilePaths) {
    final lockAppDir = p.dirname(p.normalize(p.absolute(lockPath)));
    for (final package in parsePathPackagesFromLock(lockPath)) {
      final key = '${package.name}\u0000${package.path}';
      if (!seen.add(key)) continue;
      final classified = classifyPathDependency(
        package: package,
        appDir: lockAppDir,
        repoRoot: repoRoot,
      );
      results.add(classified);

      switch (classified.location) {
        case PathDepLocation.insideRepo:
          logWarn(
            'path dependency ${package.name}: ${package.path} is inside the '
            'repository at ${classified.resolvedPath} and is included via the '
            'git checkout (relative layout preserved).',
          );
        case PathDepLocation.outsideRepo:
          throw PathDependencyException(
            'path dependency ${package.name}: ${package.path} resolves to '
            '${classified.resolvedPath}, which is outside the repository '
            'root $repoRoot. Move it into the repo or vendor it; flutpak '
            'will not generate a manifest that cannot build offline.',
          );
        case PathDepLocation.absolute:
          throw PathDependencyException(
            'path dependency ${package.name} uses an absolute path '
            '(${package.path}). Absolute path dependencies are not supported; '
            'use a path relative to the app directory, inside the repository.',
          );
      }
    }
  }
  return results;
}
