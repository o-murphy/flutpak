import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../generators/pub_sources.dart';
import 'log.dart';

/// Generates `pubspec-sources.json` from pub lock files, writing the result
/// to [outputPath]. Flutter SDK sources are NOT included here — they are
/// written as a standalone module by the generate command (see backlog4 §1.1).
/// [foreignDepSources] are appended after pub sources.
Future<void> generatePubSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async {
  final allSources = <Map<String, dynamic>>[];
  final pubClient = http.Client();

  try {
    final pubSources =
        await PubSourcesGenerator(lockFilePaths: lockPaths, client: pubClient)
            .generate();
    allSources.addAll(pubSources.map((s) => s.toJson()));
    logInfo('pub: ${pubSources.length} entries');
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
