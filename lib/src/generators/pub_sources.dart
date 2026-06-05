import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/flatpak_source.dart';
import '../utils/log.dart';

class PubSourcesGenerator {
  final List<String> lockFilePaths;
  final http.Client _client;

  PubSourcesGenerator({
    required this.lockFilePaths,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<List<FlatpakSource>> generate() async {
    // Deduplicate by (name, version) so different lock files can require
    // different versions of the same package (e.g. app vs flutter_tools).
    final packages = <({String name, String version})>{};

    for (final raw in lockFilePaths) {
      final pattern = _resolveEnv(raw);
      if (pattern.contains('*')) {
        for (final entity in Glob(pattern).listSync()) {
          if (entity is File) _parseLock(entity.path, packages);
        }
      } else {
        final f = File(pattern);
        if (f.existsSync()) {
          _parseLock(pattern, packages);
        } else {
          logWarn('lock file not found: $pattern');
        }
      }
    }

    logInfo('pub: ${packages.length} unique hosted package versions');

    final entries = <FlatpakSource>[];
    var done = 0;

    // Batch parallel requests — pub.dev can handle concurrency.
    const batchSize = 20;
    final pkgList = packages.toList();

    for (var i = 0; i < pkgList.length; i += batchSize) {
      final batch = pkgList.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((pkg) async {
        final (:name, :version) = pkg;
        final sha256 = await _fetchSha256(name, version);
        return [
          ArchiveSource(
            url: 'https://pub.dev/packages/$name/versions/$version.tar.gz',
            sha256: sha256,
            dest: '.pub-cache/hosted/pub.dev/$name-$version',
            stripComponents: 0,
          ),
          InlineSource(
            contents: sha256,
            dest: '.pub-cache/hosted-hashes/pub.dev',
            destFilename: '$name-$version.sha256',
          ),
        ];
      }));
      for (final pair in results) {
        entries.addAll(pair);
      }
      done += batch.length;
      logDebug('pub: $done / ${pkgList.length}');
    }

    return entries;
  }

  void _parseLock(String path, Set<({String name, String version})> out) {
    final raw = File(path).readAsStringSync();
    final yaml = loadYaml(raw);
    if (yaml is! Map) return;
    final pkgs = yaml['packages'];
    if (pkgs is! Map) return;

    for (final e in pkgs.entries) {
      final name = e.key as String;
      final info = e.value;
      if (info is! Map) continue;
      if (info['source'] != 'hosted') continue;
      final version = info['version'] as String?;
      if (version != null) out.add((name: name, version: version));
    }
  }

  Future<String> _fetchSha256(String name, String version) async {
    final uri =
        Uri.parse('https://pub.dev/api/packages/$name/versions/$version');
    final response = await _retryGet(
      uri,
      tag: '$name@$version',
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
          'pub.dev API error $name@$version: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final hash = json['archive_sha256'] as String?;
    if (hash != null) return hash;

    // Fallback: download archive and hash it (pre-2023 packages).
    return _downloadAndHash(
        'https://pub.dev/packages/$name/versions/$version.tar.gz');
  }

  Future<String> _downloadAndHash(String url) async {
    final response = await _retryGet(Uri.parse(url), tag: url);
    if (response.statusCode != 200) {
      throw Exception('Download failed $url: ${response.statusCode}');
    }
    return sha256.convert(response.bodyBytes).toString();
  }

  // Transient HTTP status codes worth retrying.
  static const _retryStatuses = {429, 500, 502, 503, 504};

  Future<http.Response> _retryGet(
    Uri uri, {
    required String tag,
    Map<String, String>? headers,
  }) async {
    var delay = const Duration(seconds: 2);
    for (var attempt = 1; attempt <= 4; attempt++) {
      final response = await _client.get(uri, headers: headers);
      if (!_retryStatuses.contains(response.statusCode)) return response;
      if (attempt == 4) return response;
      logWarn(
          '$tag ${response.statusCode} — retry $attempt/3 in ${delay.inSeconds}s');
      await Future.delayed(delay);
      delay *= 2;
    }
    throw StateError('unreachable');
  }

  static String _resolveEnv(String s) => s.replaceAllMapped(
        RegExp(r'\$(\w+)'),
        (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
      );
}
