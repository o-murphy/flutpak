import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'log.dart';

/// Interface for SHA-256 resolution — injectable for testing.
abstract interface class DownloadCache {
  Future<String> sha256For(String url);
  void dispose();
}

/// SHA-256 cache keyed by URL — avoids re-downloading Flutter SDK artifacts
/// across runs. Stored in ~/.cache/flutpak/.
class LocalDownloadCache implements DownloadCache {
  final Directory _dir;
  final http.Client _client;

  LocalDownloadCache({http.Client? client})
      : _dir = Directory(p.join(
          Platform.environment['HOME'] ?? '.',
          '.cache',
          'flutpak',
        )),
        _client = client ?? http.Client();

  static const _retryStatuses = {429, 500, 502, 503, 504};

  @override
  Future<String> sha256For(String url) async {
    _dir.createSync(recursive: true);

    final key = sha256.convert(utf8.encode(url)).toString();
    final cacheFile = File(p.join(_dir.path, key));

    if (cacheFile.existsSync()) {
      return cacheFile.readAsStringSync().trim();
    }

    logDebug('downloading $url ...');
    final response = await _retryGet(Uri.parse(url), tag: url);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }

    final digest = sha256.convert(response.bodyBytes).toString();
    cacheFile.writeAsStringSync(digest);
    return digest;
  }

  Future<http.Response> _retryGet(Uri uri, {required String tag}) async {
    var delay = const Duration(seconds: 2);
    for (var attempt = 1; attempt <= 4; attempt++) {
      final response = await _client.get(uri);
      if (!_retryStatuses.contains(response.statusCode)) return response;
      if (attempt == 4) return response;
      logWarn('$tag ${response.statusCode} — retry $attempt/3 in ${delay.inSeconds}s');
      await Future.delayed(delay);
      delay *= 2;
    }
    throw StateError('unreachable');
  }

  @override
  void dispose() => _client.close();
}
