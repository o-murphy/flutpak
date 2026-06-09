import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../generators/flutter_sdk.dart';
import '../generators/pub_sources.dart';
import '../models/flatpak_source.dart';
import 'log.dart';

/// Generates `generated-sources.json` from pub lock files and an optional
/// Flutter SDK generator, writing the result to [outputPath].
///
/// When [flutterGen] is non-null its [FlutterSdkGenerator.generate()] is
/// called concurrently with pub sources generation.
/// [foreignDepSources] are appended after pub and Flutter SDK sources.
Future<void> generateSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  FlutterSdkGenerator? flutterGen,
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async {
  final allSources = <Map<String, dynamic>>[];
  final pubClient = http.Client();

  try {
    final pubFuture =
        PubSourcesGenerator(lockFilePaths: lockPaths, client: pubClient)
            .generate();

    final Future<List<FlatpakSource>> flutterFuture =
        flutterGen != null ? flutterGen.generate() : Future.value(const []);

    final results = await Future.wait([pubFuture, flutterFuture]);
    final pubSources = results[0];
    final flutterSources = results[1];

    allSources.addAll(pubSources.map((s) => s.toJson()));
    logInfo('pub: ${pubSources.length} entries');

    if (flutterSources.isNotEmpty) {
      allSources.addAll(flutterSources.map((s) => s.toJson()));
      logInfo('flutter: ${flutterSources.length} entries');
    }
  } finally {
    pubClient.close();
  }

  allSources.addAll(foreignDepSources);
  if (foreignDepSources.isNotEmpty) {
    logInfo('foreign-deps: ${foreignDepSources.length} entries');
  }

  final json = const JsonEncoder.withIndent('    ').convert(allSources);
  File(outputPath)
    ..createSync(recursive: true)
    ..writeAsStringSync('$json\n');

  logInfo('✓  ${allSources.length} total sources → $outputPath');
}
