import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'utils/log.dart';

/// Fetches and caches pre-built `flutter-sdk-{version}.json` modules from the
/// flutpak GitHub repository. Falls back silently to generation when not found.
///
/// Cache location: `~/.cache/flutpak/flutter_sdk/flutter-sdk-{version}.json`
/// Cache invalidation: not needed — version + content are deterministic.
class FlutterSdkRegistry {
  final String ref;
  final http.Client _client;
  final bool _ownsClient;
  final Directory cacheDir;

  FlutterSdkRegistry({
    required this.ref,
    http.Client? client,
    Directory? cacheDir,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        cacheDir = cacheDir ??
            Directory(p.join(
              Platform.environment['HOME'] ?? '.',
              '.cache',
              'flutpak',
              'flutter_sdk',
            ));

  String moduleUrl(String flutterVersion) =>
      'https://raw.githubusercontent.com/o-murphy/flutpak/$ref'
      '/flutter_sdk/flutter-sdk-$flutterVersion.json';

  /// Returns cached or remotely fetched pre-built module JSON, or null if
  /// not available (HTTP 404, network error — caller should fall back to
  /// generation).
  Future<String?> fetchPrebuilt(String flutterVersion) async {
    final cacheFile =
        File(p.join(cacheDir.path, 'flutter-sdk-$flutterVersion.json'));

    if (cacheFile.existsSync()) {
      logInfo('flutter-sdk: cache hit for $flutterVersion');
      return cacheFile.readAsStringSync();
    }

    final url = moduleUrl(flutterVersion);
    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        logInfo('flutter-sdk: pre-built module found for $flutterVersion');
        cacheDir.createSync(recursive: true);
        cacheFile.writeAsStringSync(resp.body);
        return resp.body;
      }
      if (resp.statusCode != 404) {
        logWarn(
            'flutter-sdk: HTTP ${resp.statusCode} fetching pre-built module');
      }
      return null;
    } catch (e) {
      logWarn('flutter-sdk: fetch failed ($e) — falling back to generation');
      return null;
    }
  }

  /// Writes [json] to the local cache for future runs.
  void cacheLocally(String flutterVersion, String json) {
    cacheDir.createSync(recursive: true);
    File(p.join(cacheDir.path, 'flutter-sdk-$flutterVersion.json'))
        .writeAsStringSync(json);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
