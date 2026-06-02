import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/flatpak_source.dart';
import '../utils/download_cache.dart';
import 'flutter_sdk.dart';

const String _rawBase = 'https://raw.githubusercontent.com/flutter/flutter';
const String _infraBase =
    'https://storage.googleapis.com/flutter_infra_release';

/// Generates Flutter SDK [FlatpakSource] entries from a remote Flutter tag,
/// fetching version files directly from GitHub without a local SDK clone.
///
/// Drop-in replacement for [FlutterSdkGenerator] when only the Flutter version
/// tag is known (e.g. in CI or when generating an SDK extension manifest).
class RemoteFlutterSdkGenerator {
  final String flutterTag;
  final String? patchPath;
  final String? outputDir;
  final bool includePatchInSources;
  final DownloadCache _cache;

  RemoteFlutterSdkGenerator({
    required this.flutterTag,
    this.patchPath,
    this.outputDir,
    this.includePatchInSources = true,
    DownloadCache? cache,
  }) : _cache = cache ?? LocalDownloadCache();

  Future<List<FlatpakSource>> generate() async {
    final client = http.Client();
    try {
      final engineHash =
          await _fetchRaw('$_rawBase/$flutterTag/bin/internal/engine.version', client);
      final fontsHash =
          await _fetchRaw('$_rawBase/$flutterTag/bin/internal/material_fonts.version', client);
      final gradleHash =
          await _fetchRaw('$_rawBase/$flutterTag/bin/internal/gradle_wrapper.version', client);
      final commit = await resolveCommit(flutterTag);

      stderr.writeln('flutter: tag=$flutterTag engine=$engineHash commit=$commit');

      final sources = <FlatpakSource>[];

      // 1. Flutter SDK git source
      sources.add(GitSource(
        url: 'https://github.com/flutter/flutter.git',
        tag: flutterTag,
        commit: commit,
        dest: 'flutter',
      ));

      // 2. Engine artifacts (reuses FlutterSdkGenerator's public artifact list)
      final artifacts =
          FlutterSdkGenerator.buildArtifactList(engineHash, fontsHash, gradleHash);
      for (final art in artifacts) {
        final url =
            FlutterSdkGenerator.urlFor(art, engineHash, fontsHash, gradleHash);
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

      // 4. sky_engine/pubspec.yaml inline
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

      // 6. engine_stamp.json
      final stampUrl = '$_infraBase/flutter/$engineHash/engine_stamp.json';
      final stampSha256 = await _cache.sha256For(stampUrl);
      sources.add(FileSource(
        url: stampUrl,
        sha256: stampSha256,
        dest: 'flutter/bin/cache',
      ));

      return sources;
    } finally {
      client.close();
    }
  }

  String? _resolveOrWritePatch() {
    if (patchPath != null) {
      if (outputDir != null) {
        return p.relative(p.absolute(patchPath!), from: p.absolute(outputDir!));
      }
      return patchPath;
    }
    if (outputDir == null) return null;

    final target =
        File(p.join(outputDir!, defaultSharedShPatchPath));
    target.createSync(recursive: true);
    target.writeAsStringSync(builtinSharedShPatch);
    stderr.writeln('flutter: wrote built-in shared.sh patch → ${target.path}');
    return defaultSharedShPatchPath;
  }

  static Future<String> _fetchRaw(String url, http.Client client) async {
    final resp = await client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw Exception('GET $url → ${resp.statusCode}');
    }
    return resp.body.trim();
  }

  /// Resolves the git commit SHA for a Flutter tag via git ls-remote.
  /// Handles both lightweight and annotated tags (prefers the dereferenced SHA).
  static Future<String> resolveCommit(String tag) async {
    final result = await Process.run('git', [
      'ls-remote',
      'https://github.com/flutter/flutter.git',
      'refs/tags/$tag',
      'refs/tags/$tag^{}',
    ]);
    if (result.exitCode != 0) {
      throw Exception('git ls-remote failed: ${result.stderr}');
    }
    final lines = (result.stdout as String)
        .trim()
        .split('\n')
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) throw Exception('Tag $tag not found in flutter/flutter');
    // Annotated tags have a ^{} dereferenced line — use that commit SHA.
    final deref = lines.firstWhere(
      (l) => l.contains('^{}'),
      orElse: () => lines.first,
    );
    return deref.split('\t').first.trim();
  }

}
