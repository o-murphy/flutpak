import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../generators/flutter_sdk.dart';
import '../generators/pub_sources.dart';
import '../models/flatpak_source.dart';
import 'download_cache.dart';
import 'log.dart';

/// Generates `generated-sources.json` from pub lock files and an optional
/// Flutter SDK, writing the result to [outputPath].
///
/// Pub and Flutter SDK sources are fetched concurrently.
Future<void> generateSourcesJson({
  required List<String> lockPaths,
  required String? sdkPath,
  required String? patchPath,
  required String outputDir,
  required String outputPath,
  required bool pubOnly,
  required bool flutterOnly,
  bool emitFlutterPatch = true,
}) async {
  final allSources = <Map<String, dynamic>>[];
  final cache = LocalDownloadCache();
  final pubClient = http.Client();

  try {
    final pubFuture = flutterOnly
        ? Future<List<FlatpakSource>>.value(const [])
        : PubSourcesGenerator(lockFilePaths: lockPaths, client: pubClient)
            .generate();

    Future<List<FlatpakSource>> flutterFuture;
    if (pubOnly || sdkPath == null) {
      if (!pubOnly && sdkPath == null) {
        logWarn('Flutter SDK not found — skipping (set --sdk or \$FLUTTER_ROOT)');
      }
      flutterFuture = Future.value(const []);
    } else {
      flutterFuture = FlutterSdkGenerator(
        sdkPath: sdkPath,
        patchPath: patchPath,
        outputDir: outputDir,
        includePatchInSources: emitFlutterPatch,
        cache: cache,
      ).generate();
    }

    final results = await Future.wait([pubFuture, flutterFuture]);
    final pubSources = results[0];
    final flutterSources = results[1];

    if (!flutterOnly) {
      allSources.addAll(pubSources.map((s) => s.toJson()));
      logInfo('pub: ${pubSources.length} entries');
    }
    if (!pubOnly && sdkPath != null) {
      allSources.addAll(flutterSources.map((s) => s.toJson()));
      logInfo('flutter: ${flutterSources.length} entries');
    }
  } finally {
    pubClient.close();
    cache.dispose();
  }

  final json = const JsonEncoder.withIndent('    ').convert(allSources);
  File(outputPath)
    ..createSync(recursive: true)
    ..writeAsStringSync('$json\n');

  logInfo('✓  ${allSources.length} total sources → $outputPath');
}
