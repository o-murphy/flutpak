import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/flatpak_source.dart';
import '../utils/download_cache.dart';
import '../utils/log.dart';

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

const String _rawBase = 'https://raw.githubusercontent.com/flutter/flutter';

/// Patch content to replace `pub upgrade` with `pub get --offline` inside
/// Flutter's shared.sh bootstrap function.  Applied automatically when no
/// explicit [patchPath] is given to [FlutterSdkGenerator].
const String builtinSharedShPatch = r'''
diff --git a/flutter/bin/internal/shared.sh b/flutter/bin/internal/shared.sh
index d78e0cd..b8eb978 100644
--- a/flutter/bin/internal/shared.sh
+++ b/flutter/bin/internal/shared.sh
@@ -20,7 +20,7 @@ function pub_upgrade_with_retry {
   local total_tries="10"
   local remaining_tries=$((total_tries - 1))
   while [[ "$remaining_tries" -gt 0 ]]; do
-    (cd "$FLUTTER_TOOLS_DIR" && "$DART" pub upgrade --suppress-analytics >&2) && break
+    (cd "$FLUTTER_TOOLS_DIR" && "$DART" pub upgrade --offline --suppress-analytics >&2) && break
     >&2 echo "Error: Unable to 'pub upgrade' flutter tool. Retrying in five seconds... ($remaining_tries tries left)"
     remaining_tries=$((remaining_tries - 1))
     sleep 5
''';

/// Default relative path (from the output dir) where the built-in patch is
/// written when no explicit [patchPath] is provided.
const String defaultSharedShPatchPath = 'patches/flutter/shared.sh.patch';

/// Generates Flutter SDK [FlatpakSource] entries by fetching metadata from
/// the Flutter GitHub repository at [flutterRef].
///
/// No local Flutter installation is required — engine version hashes and the
/// flutter_tools pubspec.lock are fetched from GitHub raw content API.
/// SHA-256 checksums for engine artifacts are obtained via [DownloadCache]
/// (cached locally in ~/.cache/flutpak/).
///
/// If [patchPath] is null, the built-in [builtinSharedShPatch] is written to
/// [defaultSharedShPatchPath] relative to [patchDestDir] (or [outputDir] when
/// [patchDestDir] is omitted) and included automatically.
/// Pass an explicit [patchPath] to override, or set [outputDir] to null to skip
/// the patch entirely (not recommended for Flatpak offline builds).
class FlutterSdkGenerator {
  final String flutterRef;
  final String? patchPath;
  final String? outputDir;

  /// Directory where the built-in patch file is written. Defaults to [outputDir].
  ///
  /// Set this to the `generated/` directory so the built-in patch is placed in
  /// the gitignored output tree and never written to the committed `patches/`
  /// directory. Custom user patches (via [patchPath]) are unaffected.
  final String? patchDestDir;

  final DownloadCache _cache;

  /// HTTP client used to fetch text files (version hashes) from GitHub.
  final http.Client _client;

  /// When false, the patch source is not added to the returned list even if a
  /// patch file exists. The caller is responsible for injecting it elsewhere
  /// (e.g. directly into the manifest). Defaults to true for standalone use.
  final bool includePatchInSources;

  final bool _ownsClient;

  FlutterSdkGenerator({
    required this.flutterRef,
    this.patchPath,
    this.outputDir,
    this.patchDestDir,
    this.includePatchInSources = true,
    DownloadCache? cache,
    http.Client? client,
  })  : _cache = cache ?? LocalDownloadCache(),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  /// Returns flatpak sources representing the full Flutter SDK for offline builds.
  ///
  /// The returned list can be embedded directly into a flatpak manifest's
  /// `sources:` field or written to a generated-sources JSON file.
  Future<List<FlatpakSource>> generate() async {
    final engineHash = await _fetchText('engine.version');
    final fontsHash =
        await _fetchText('material_fonts.version', subdir: 'bin/internal');
    final gradleHash =
        await _fetchText('gradle_wrapper.version', subdir: 'bin/internal');
    final flutterVersion = await _fetchFlutterVersion();
    final flutterCommit = await _resolveCommit();

    logInfo(
        'flutter: ref=$flutterRef version=$flutterVersion engine=$engineHash');

    final sources = <FlatpakSource>[];

    // 1. Flutter SDK git source
    sources.add(GitSource(
      url: 'https://github.com/flutter/flutter.git',
      tag: flutterVersion,
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
    if (includePatchInSources) {
      final effectivePatchPath = _resolveOrWritePatch();
      if (effectivePatchPath != null) {
        sources.add(PatchSource(path: effectivePatchPath));
      }
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

  /// Returns the content of `flutter_tools/pubspec.lock` for [flutterRef].
  ///
  /// Tries to fetch the committed lockfile first (older Flutter versions that
  /// committed it). Falls back to fetching `pubspec.yaml` and running
  /// `dart pub get` in a temp directory to generate the lockfile — Flutter
  /// stopped committing it for newer releases but still pins all versions
  /// explicitly, so the generated file is fully deterministic.
  Future<String> fetchFlutterToolsLock() async {
    final lockUrl = '$_rawBase/$flutterRef/packages/flutter_tools/pubspec.lock';
    final lockResp = await _client.get(Uri.parse(lockUrl));
    if (lockResp.statusCode == 200) return lockResp.body;

    // Fallback: generate from pubspec.yaml via `dart pub get`.
    final yamlUrl = '$_rawBase/$flutterRef/packages/flutter_tools/pubspec.yaml';
    final yamlResp = await _client.get(Uri.parse(yamlUrl));
    if (yamlResp.statusCode != 200) {
      throw Exception(
          'Failed to fetch flutter_tools/pubspec.lock for ref=$flutterRef '
          '(HTTP ${lockResp.statusCode})');
    }
    return _generateLockFromPubspecYaml(yamlResp.body);
  }

  /// Writes [pubspecYaml] to a temp directory, runs `dart pub get`, and
  /// returns the content of the generated `pubspec.lock`.
  Future<String> _generateLockFromPubspecYaml(String pubspecYaml) async {
    final tmpDir = Directory.systemTemp.createTempSync('flutpak_tools_');
    try {
      File(p.join(tmpDir.path, 'pubspec.yaml')).writeAsStringSync(pubspecYaml);
      final result = await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: tmpDir.path,
      );
      if (result.exitCode != 0) {
        throw Exception(
            'dart pub get failed for flutter_tools: ${result.stderr}');
      }
      return File(p.join(tmpDir.path, 'pubspec.lock')).readAsStringSync();
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  }

  /// Returns the Flutter version string for [flutterRef].
  ///
  /// For a semver tag like "3.44.1" the tag itself is the version; for other
  /// refs the `version` file is fetched from GitHub.
  Future<String> _fetchFlutterVersion() async {
    final url = '$_rawBase/$flutterRef/version';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) return response.body.trim();
    // For a plain semver tag, the ref itself may be the version.
    if (RegExp(r'^\d+\.\d+\.\d+').hasMatch(flutterRef)) return flutterRef;
    throw Exception('Cannot determine Flutter version for ref=$flutterRef '
        '(HTTP ${response.statusCode})');
  }

  /// Fetches a text file from GitHub at the given path under [flutterRef].
  ///
  /// [subdir] defaults to `bin/internal`; pass an empty string for repo-root files.
  Future<String> _fetchText(String filename,
      {String subdir = 'bin/internal'}) async {
    final path = subdir.isEmpty ? filename : '$subdir/$filename';
    final url = '$_rawBase/$flutterRef/$path';
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch $path for ref=$flutterRef (HTTP ${response.statusCode})');
    }
    return response.body.trim();
  }

  /// Returns the full commit SHA for [flutterRef] using git ls-remote.
  ///
  /// Falls back to null when git is unavailable or the ref can't be resolved.
  Future<String?> _resolveCommit() async {
    if (RegExp(r'^[0-9a-f]{40}$').hasMatch(flutterRef)) return flutterRef;

    try {
      for (final refSpec in [
        'refs/tags/$flutterRef',
        'refs/heads/$flutterRef',
      ]) {
        final result = await Process.run(
          'git',
          ['ls-remote', 'https://github.com/flutter/flutter.git', refSpec],
        );
        if (result.exitCode == 0) {
          final line = (result.stdout as String).trim();
          if (line.isNotEmpty) return line.split('\t').first;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Returns the patch path to embed in the source list.
  String? _resolveOrWritePatch() {
    if (patchPath != null) {
      if (outputDir != null) {
        return p.relative(p.absolute(patchPath!), from: p.absolute(outputDir!));
      }
      return patchPath;
    }
    if (outputDir == null) return null;

    final destDir = patchDestDir ?? outputDir!;
    final target = File(p.join(destDir, defaultSharedShPatchPath));
    target.createSync(recursive: true);
    target.writeAsStringSync(builtinSharedShPatch);
    logInfo('✓  flutter: wrote built-in shared.sh patch → ${target.path}');
    return defaultSharedShPatchPath;
  }

  List<_Artifact> _buildArtifactList(
      String engineHash, String fontsHash, String gradleHash) {
    return [
      _Artifact('dart-sdk-linux-x64.zip', 'flutter/bin/cache',
          onlyArches: ['x86_64'], stripComponents: 0),
      _Artifact('dart-sdk-linux-arm64.zip', 'flutter/bin/cache',
          onlyArches: ['aarch64'], stripComponents: 0),
      _Artifact('__fonts__', 'flutter/bin/cache/artifacts/material_fonts',
          stripComponents: 0),
      _Artifact('__gradle__', 'flutter/bin/cache/artifacts/gradle_wrapper',
          stripComponents: 0),
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
      if (fontsHash.contains('/')) {
        return 'https://storage.googleapis.com/$fontsHash';
      }
      return '$_infraBase/flutter/fonts/$fontsHash/fonts.zip';
    }
    if (art.path == '__gradle__') {
      if (gradleHash.contains('/')) {
        return 'https://storage.googleapis.com/$gradleHash';
      }
      return '$_infraBase/gradle-wrapper/$gradleHash/gradle-wrapper.tgz';
    }
    return '$_infraBase/flutter/$engineHash/${art.path}';
  }

  /// Build-commands for the flutter-sdk module (used by `flutpak sdk-mod`).
  ///
  /// Stamps the engine version files into Flutter's cache directory and
  /// installs the SDK to `/var/lib/flutter`.
  static List<String> buildCommands() => [
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine-dart-sdk.stamp',
        'cp flutter/bin/internal/material_fonts.version flutter/bin/cache/material_fonts.stamp',
        'cp flutter/bin/internal/gradle_wrapper.version flutter/bin/cache/gradle_wrapper.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine_stamp.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/flutter_sdk.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/font-subset.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/linux-sdk.stamp',
        'mkdir -p /var/lib && cp -r flutter /var/lib',
      ];
}
