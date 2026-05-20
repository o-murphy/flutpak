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
  // strip-components for flatpak-builder (default in flatpak-builder is 1).
  // Packages with a top-level directory matching their name (sky_engine/,
  // flutter_gpu/, flutter_patched_sdk/) need stripComponents=1 so files land
  // directly in dest/.  Archives that are already flat (dart-sdk/, linux
  // engine binaries) need stripComponents=0 to preserve the outer directory.
  final int stripComponents;

  const _Artifact(this.path, this.dest,
      {this.onlyArches, this.stripComponents = 0});
}

const String _infraBase =
    'https://storage.googleapis.com/flutter_infra_release';

/// Patch content to replace `pub upgrade` with `pub get --offline` inside
/// Flutter's shared.sh bootstrap function.  Applied automatically when no
/// explicit [patchPath] is given to [FlutterSdkGenerator].
const String builtinSharedShPatch = r'''
--- a/flutter/bin/internal/shared.sh
+++ b/flutter/bin/internal/shared.sh
@@ -20,8 +20,8 @@ function pub_upgrade_with_retry {
   local total_tries="10"
   local remaining_tries=$((total_tries - 1))
   while [[ "$remaining_tries" -gt 0 ]]; do
-    (cd "$FLUTTER_TOOLS_DIR" && "$DART" pub upgrade --suppress-analytics >&2) && break
-    >&2 echo "Error: Unable to 'pub upgrade' flutter tool. Retrying in five seconds... ($remaining_tries tries left)"
+    (cd "$FLUTTER_TOOLS_DIR" && "$DART" pub get --offline --suppress-analytics >&2) && break
+    >&2 echo "Error: Unable to 'pub get --offline' flutter tool. Retrying in five seconds... ($remaining_tries tries left)"
     remaining_tries=$((remaining_tries - 1))
     sleep 5
''';

/// Default relative path (from the output dir) where the built-in patch is
/// written when no explicit [patchPath] is provided.
const String defaultSharedShPatchPath = 'patches/flutter/shared.sh.patch';

/// Generates Flutter SDK [FlatpakSource] entries from a local Flutter SDK install.
///
/// Reads version files from [sdkPath] to determine the engine hash, fonts hash
/// and gradle wrapper hash, then constructs all artifact entries.
/// SHA-256 checksums are fetched by downloading each artifact (cached locally).
///
/// If [patchPath] is null, the built-in [builtinSharedShPatch] is written to
/// [defaultSharedShPatchPath] relative to [outputDir] and included automatically.
/// Pass an explicit [patchPath] to override, or set [outputDir] to null to skip
/// the patch entirely (not recommended for Flatpak offline builds).
class FlutterSdkGenerator {
  final String sdkPath;
  final String? patchPath;
  final String? outputDir;
  final DownloadCache _cache;

  FlutterSdkGenerator({
    required this.sdkPath,
    this.patchPath,
    this.outputDir,
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
        stripComponents: art.stripComponents,
        onlyArches: art.onlyArches,
      ));
    }

    // 3. patch for shared.sh (replaces pub upgrade with pub get --offline)
    final effectivePatchPath = _resolveOrWritePatch();
    if (effectivePatchPath != null) {
      sources.add(PatchSource(path: effectivePatchPath));
    }

    // 4. sky_engine/pubspec.yaml — not in the Flutter git tree (removed in
    //    Flutter 3.x).  Even if sky_engine.zip includes it, the path inside
    //    the zip may differ from the expected dest.  Write it inline to
    //    guarantee the correct content at the correct location.
    //    The environment constraint must start at >=2.12.0 to enable null
    //    safety; without it pub rejects the package entirely.
    sources.add(InlineSource(
      contents: 'name: sky_engine\n'
          'description: "Dart API for the Sky engine."\n'
          'publish_to: none\n'
          'version: 0.0.99\n'
          '\n'
          'environment:\n'
          '  sdk: ">=2.12.0 <4.0.0"\n',
      dest: 'flutter/bin/cache/pkg/sky_engine',
      destFilename: 'pubspec.yaml',
    ));

    // 5. setup-flutter.sh script helper
    sources.add(ScriptSource(
      commands: ['flutter pub get --offline \$@'],
      dest: 'flutter/bin',
      destFilename: 'setup-flutter.sh',
    ));

    // 5. engine_stamp.json (type: file)
    final stampUrl = '$_infraBase/flutter/$engineHash/engine_stamp.json';
    final stampSha256 = await _cache.sha256For(stampUrl);
    sources.add(FileSource(
      url: stampUrl,
      sha256: stampSha256,
      dest: 'flutter/bin/cache',
    ));

    return sources;
  }

  /// Returns the patch path to embed in the source list.
  ///
  /// - If [patchPath] was provided explicitly: returns it as-is.
  /// - If [outputDir] is set: writes [builtinSharedShPatch] to
  ///   `outputDir/defaultSharedShPatchPath` and returns the relative path.
  /// - Otherwise: returns null (no patch included).
  String? _resolveOrWritePatch() {
    if (patchPath != null) return patchPath;
    if (outputDir == null) return null;

    final target = File(p.join(outputDir!, defaultSharedShPatchPath));
    target.createSync(recursive: true);
    target.writeAsStringSync(builtinSharedShPatch);
    stderr.writeln('flutter: wrote built-in shared.sh patch → ${target.path}');
    return defaultSharedShPatchPath;
  }

  List<_Artifact> _buildArtifactList(
      String engineHash, String fontsHash, String gradleHash) {
    return [
      // Dart SDK zips contain a top-level dart-sdk/ directory we want to
      // keep → strip-components: 0.
      _Artifact('dart-sdk-linux-x64.zip', 'flutter/bin/cache',
          onlyArches: ['x86_64'], stripComponents: 0),
      _Artifact('dart-sdk-linux-arm64.zip', 'flutter/bin/cache',
          onlyArches: ['aarch64'], stripComponents: 0),

      // Fonts and gradle — flat archives, keep as-is.
      _Artifact('__fonts__', 'flutter/bin/cache/artifacts/material_fonts',
          stripComponents: 0),
      _Artifact('__gradle__', 'flutter/bin/cache/artifacts/gradle_wrapper',
          stripComponents: 0),

      // Package-style engine artifacts: the zip has a top-level directory
      // matching the package name (e.g. sky_engine/lib/...) → strip it so
      // files land directly in dest/.  stripComponents: 1 matches the
      // default flatpak-builder behaviour used in the hand-crafted manifests
      // that are known to work.
      _Artifact('sky_engine.zip', 'flutter/bin/cache/pkg/sky_engine',
          stripComponents: 1),
      _Artifact('flutter_gpu.zip', 'flutter/bin/cache/pkg/flutter_gpu',
          stripComponents: 1),
      _Artifact('flutter_patched_sdk.zip',
          'flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk',
          stripComponents: 1),
      _Artifact('flutter_patched_sdk_product.zip',
          'flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk_product',
          stripComponents: 1),

      // Per-arch engine binary archives — already flat, keep as-is.
      _Artifact('linux-x64/artifacts.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64',
          onlyArches: ['x86_64'], stripComponents: 0),
      _Artifact('linux-x64/font-subset.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64',
          onlyArches: ['x86_64'], stripComponents: 0),
      _Artifact('linux-x64-profile/linux-x64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64-profile',
          onlyArches: ['x86_64'], stripComponents: 0),
      _Artifact('linux-x64-release/linux-x64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-x64-release',
          onlyArches: ['x86_64'], stripComponents: 0),

      _Artifact('linux-arm64/artifacts.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64',
          onlyArches: ['aarch64'], stripComponents: 0),
      _Artifact('linux-arm64/font-subset.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64',
          onlyArches: ['aarch64'], stripComponents: 0),
      _Artifact('linux-arm64-profile/linux-arm64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64-profile',
          onlyArches: ['aarch64'], stripComponents: 0),
      _Artifact('linux-arm64-release/linux-arm64-flutter-gtk.zip',
          'flutter/bin/cache/artifacts/engine/linux-arm64-release',
          onlyArches: ['aarch64'], stripComponents: 0),
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
    final result =
        Process.runSync('git', ['-C', repoPath, 'rev-parse', 'HEAD']);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}
