import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../models/flatpak_source.dart';
import '../utils/download_cache.dart';

/// Describes one artifact entry in the Flutter engine infra.
class _Artifact {
  final String path;
  final String dest;
  final List<String>? onlyArches;

  const _Artifact(this.path, this.dest, {this.onlyArches});
}

const String _infraBase =
    'https://storage.googleapis.com/flutter_infra_release';

/// Generates Flutter SDK [FlatpakSource] entries from a local Flutter SDK install.
///
/// Reads version files from [sdkPath] to determine the engine hash, fonts hash
/// and gradle wrapper hash, then constructs all artifact entries.
/// SHA-256 checksums are fetched by downloading each artifact (cached locally).
class FlutterSdkGenerator {
  final String sdkPath;
  final String? patchPath; // relative path to the shared.sh patch, if any
  final DownloadCache _cache;

  FlutterSdkGenerator({
    required this.sdkPath,
    this.patchPath,
    DownloadCache? cache,
  }) : _cache = cache ?? LocalDownloadCache();

  /// Returns flatpak sources representing the full Flutter SDK for offline builds.
  ///
  /// The returned list can be embedded directly into a flatpak manifest's
  /// `sources:` field or written to a generated-sources JSON file.
  Future<List<FlatpakSource>> generate() async {
    final internalDir = p.join(sdkPath, 'bin', 'internal');

    final engineHash =
        File(p.join(internalDir, 'engine.version')).readAsStringSync().trim();
    final fontsHash = File(p.join(internalDir, 'material_fonts.version'))
        .readAsStringSync()
        .trim();
    final gradleHash = File(p.join(internalDir, 'gradle_wrapper.version'))
        .readAsStringSync()
        .trim();
    final flutterTag = _readFlutterVersion(sdkPath);
    final flutterCommit = _gitRevParse(sdkPath);

    stderr.writeln('flutter: version=$flutterTag engine=$engineHash');

    final sources = <FlatpakSource>[];

    // 1. Flutter SDK git source
    sources.add(GitSource(
      url: 'https://github.com/flutter/flutter.git',
      tag: flutterTag,
      commit: flutterCommit,
      dest: 'flutter',
    ));

    // 2. Engine artifacts
    final artifacts = _buildArtifactList(engineHash, fontsHash, gradleHash);
    for (final art in artifacts) {
      final url = _urlFor(art, engineHash, fontsHash, gradleHash);
      final sha256 = await _cache.sha256For(url);

      sources.add(ArchiveSource(
        url: url,
        sha256: sha256,
        dest: art.dest,
        stripComponents: 0,
        onlyArches: art.onlyArches,
      ));
    }

    // 3. patch for shared.sh (forces --offline in pub upgrade)
    if (patchPath != null) {
      sources.add(PatchSource(path: patchPath!));
    }

    // 4. setup-flutter.sh script helper
    sources.add(ScriptSource(
      commands: ['flutter pub get --offline \$@'],
      dest: 'flutter/bin',
      destFilename: 'setup-flutter.sh',
    ));

    // 5. engine_stamp.json (type: file)
    final stampUrl =
        '$_infraBase/flutter/$engineHash/engine_stamp.json';
    final stampSha256 = await _cache.sha256For(stampUrl);
    sources.add(FileSource(
      url: stampUrl,
      sha256: stampSha256,
      dest: 'flutter/bin/cache',
    ));

    return sources;
  }

  List<_Artifact> _buildArtifactList(
      String engineHash, String fontsHash, String gradleHash) {
    return [
      // Dart SDK (arch-specific)
      _Artifact('dart-sdk-linux-x64.zip', 'flutter/bin/cache',
          onlyArches: ['x86_64']),
      _Artifact('dart-sdk-linux-arm64.zip', 'flutter/bin/cache',
          onlyArches: ['aarch64']),

      // Shared artifacts (no engine-hash prefix — use fontsHash/gradleHash)
      _Artifact('__fonts__', 'flutter/bin/cache/artifacts/material_fonts'),
      _Artifact('__gradle__',
          'flutter/bin/cache/artifacts/gradle_wrapper'),

      // Common engine artifacts
      _Artifact('sky_engine.zip',
          'flutter/bin/cache/pkg/sky_engine'),
      _Artifact('flutter_gpu.zip',
          'flutter/bin/cache/pkg/flutter_gpu'),
      _Artifact('flutter_patched_sdk.zip',
          'flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk'),
      _Artifact('flutter_patched_sdk_product.zip',
          'flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk_product'),

      // x86_64 engine artifacts
      _Artifact('linux-x64/artifacts.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64',
          onlyArches: ['x86_64']),
      _Artifact('linux-x64/font-subset.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64',
          onlyArches: ['x86_64']),
      _Artifact(
          'linux-x64-profile/linux-x64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64-profile',
          onlyArches: ['x86_64']),
      _Artifact(
          'linux-x64-release/linux-x64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64-release',
          onlyArches: ['x86_64']),

      // aarch64 engine artifacts
      _Artifact('linux-arm64/artifacts.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64',
          onlyArches: ['aarch64']),
      _Artifact('linux-arm64/font-subset.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64',
          onlyArches: ['aarch64']),
      _Artifact(
          'linux-arm64-profile/linux-arm64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64-profile',
          onlyArches: ['aarch64']),
      _Artifact(
          'linux-arm64-release/linux-arm64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64-release',
          onlyArches: ['aarch64']),
    ];
  }

  String _urlFor(
      _Artifact art, String engineHash, String fontsHash, String gradleHash) {
    if (art.path == '__fonts__') {
      // Newer Flutter stores a full GCS path in material_fonts.version
      // (e.g. "flutter_infra_release/flutter/fonts/<hash>/fonts.zip")
      // instead of just the bare hash.
      if (fontsHash.contains('/')) {
        return 'https://storage.googleapis.com/$fontsHash';
      }
      return '$_infraBase/flutter/fonts/$fontsHash/fonts.zip';
    }
    if (art.path == '__gradle__') {
      // Same pattern may apply to gradle_wrapper.version.
      if (gradleHash.contains('/')) {
        return 'https://storage.googleapis.com/$gradleHash';
      }
      return '$_infraBase/gradle-wrapper/$gradleHash/gradle-wrapper.tgz';
    }
    return '$_infraBase/flutter/$engineHash/${art.path}';
  }

  /// Reads the Flutter SDK version tag.
  ///
  /// Tries in order:
  ///   1. `flutter/version` — legacy flat file (Flutter < ~3.32)
  ///   2. `git describe --tags --abbrev=0` — works for any tagged git clone
  ///   3. `flutter/packages/flutter/pubspec.yaml` — inner package version
  static String _readFlutterVersion(String sdkPath) {
    final versionFile = File(p.join(sdkPath, 'version'));
    if (versionFile.existsSync()) return versionFile.readAsStringSync().trim();

    final gitResult = Process.runSync(
        'git', ['-C', sdkPath, 'describe', '--tags', '--abbrev=0']);
    if (gitResult.exitCode == 0) {
      return (gitResult.stdout as String).trim();
    }

    // Fall back to the inner flutter package pubspec.yaml.
    final innerPubspec =
        File(p.join(sdkPath, 'packages', 'flutter', 'pubspec.yaml'));
    if (innerPubspec.existsSync()) {
      final yaml = loadYaml(innerPubspec.readAsStringSync());
      if (yaml is Map && yaml['version'] != null) {
        return yaml['version'].toString();
      }
    }

    throw Exception('Cannot determine Flutter version from $sdkPath');
  }

  static String? _gitRevParse(String repoPath) {
    final result = Process.runSync('git', ['-C', repoPath, 'rev-parse', 'HEAD']);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}
