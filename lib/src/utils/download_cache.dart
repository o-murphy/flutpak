import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Interface for SHA-256 resolution — injectable for testing.
abstract interface class DownloadCache {
  Future<String> sha256For(String url);
  void dispose();
}

/// SHA-256 cache keyed by URL — avoids re-downloading Flutter SDK artifacts
/// across runs. Stored in ~/.cache/flatpak_gen/.
class LocalDownloadCache implements DownloadCache {
  final Directory _dir;
  final http.Client _client;

  LocalDownloadCache({http.Client? client})
      : _dir = Directory(p.join(
          Platform.environment['HOME'] ?? '.',
          '.cache',
          'flatpak_gen',
        )),
        _client = client ?? http.Client();

  @override
  Future<String> sha256For(String url) async {
    _dir.createSync(recursive: true);

    final key = sha256.convert(utf8.encode(url)).toString();
    final cacheFile = File(p.join(_dir.path, key));

    if (cacheFile.existsSync()) {
      return cacheFile.readAsStringSync().trim();
    }

    stderr.writeln('  downloading $url ...');
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }

    final digest = sha256.convert(response.bodyBytes).toString();
    cacheFile.writeAsStringSync(digest);
    return digest;
  }

  @override
  void dispose() => _client.close();
}
