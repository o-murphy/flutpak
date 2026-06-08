import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'utils/log.dart';

/// Resolves package dependencies from the flutpak foreign_deps registry,
/// compatible with the flatpak-flutter foreign_deps.json format.
///
/// The registry maps pub package names to per-version source lists
/// (archives, patches, files). On a `generate` run the registry is fetched
/// from GitHub and any packages found in the project's lock files are resolved
/// into flatpak source maps ready for `generated-sources.json`.
class ForeignDepsRegistry {
  final String ref;
  final http.Client _client;
  final Directory _cacheDir;

  ForeignDepsRegistry({
    String? ref,
    http.Client? client,
    Directory? cacheDir,
  })  : ref = ref ?? 'main',
        _client = client ?? http.Client(),
        _cacheDir = cacheDir ??
            Directory(p.join(
              Platform.environment['HOME'] ?? '.',
              '.cache',
              'flutpak',
            ));

  String get registryUrl =>
      'https://raw.githubusercontent.com/o-murphy/flutpak/$ref/foreign_deps/foreign_deps.json';

  String get baseUrl =>
      'https://raw.githubusercontent.com/o-murphy/flutpak/$ref/foreign_deps/';

  /// Fetches the registry JSON. Always attempts a network fetch first.
  /// Falls back to a local cache when the network is unavailable, with a
  /// warning. Throws if neither fetch nor cache succeeds.
  Future<Map<String, dynamic>> fetchJson() async {
    final cacheKey = sha256.convert(utf8.encode(registryUrl)).toString();
    final cacheFile = File(p.join(_cacheDir.path, '$cacheKey.json'));

    try {
      final response = await _client.get(Uri.parse(registryUrl));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} for $registryUrl');
      }
      _cacheDir.createSync(recursive: true);
      cacheFile.writeAsBytesSync(response.bodyBytes);
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (e) {
      if (cacheFile.existsSync()) {
        logWarn('foreign-deps: fetch failed ($e) — using cached registry');
        return jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  /// Resolves registry entries for packages found in [lockPaths].
  ///
  /// Packages in [overriddenPackages] are skipped (local `patches:` wins).
  /// For each resolved package version:
  ///   - `type: patch` sources are downloaded to
  ///     `[generatedPatchesDir]/<original-path>` as raw bytes (no line-ending
  ///     conversion), and their `path` field is rewritten to
  ///     `patches/<original-path>` so flatpak-builder can find them relative
  ///     to the manifest directory.
  ///   - All other source types have placeholder substitution applied and are
  ///     included as-is.
  ///
  /// Returns source maps ready to append to `generated-sources.json`.
  Future<List<Map<String, dynamic>>> resolve({
    required List<String> lockPaths,
    required Set<String> overriddenPackages,
    required String generatedPatchesDir,
  }) async {
    final Map<String, dynamic> registry;
    try {
      registry = await fetchJson();
    } catch (e) {
      logWarn('foreign-deps: registry unavailable ($e) — skipping');
      return const [];
    }

    final lockedVersions = _readLockedVersions(lockPaths);
    final result = <Map<String, dynamic>>[];

    for (final package in registry.keys) {
      if (overriddenPackages.contains(package)) continue;
      final version = lockedVersions[package];
      if (version == null) continue;

      final packageMap = registry[package];
      if (packageMap is! Map) continue;
      final versionEntry = packageMap[version];
      if (versionEntry is! Map) continue;
      final manifest = versionEntry['manifest'];
      if (manifest is! Map) continue;
      final sources = manifest['sources'];
      if (sources is! List) continue;

      for (final rawSource in sources) {
        if (rawSource is! Map) continue;
        var source = _deepConvert(rawSource);
        source = resolvePlaceholders(source, package, version);

        if (source['type'] == 'patch') {
          final origPath = source['path'] as String;
          final url = baseUrl + origPath;
          final localFile = p.join(generatedPatchesDir, origPath);
          await _downloadFile(url, localFile);
          source = Map<String, dynamic>.from(source);
          source['path'] = 'patches/$origPath';
        }

        result.add(source);
      }

      logInfo('foreign-deps: $package $version — ${sources.length} source(s)');
    }

    return result;
  }

  void dispose() => _client.close();

  /// Replaces `\$PUB_DEV` with `.pub-cache/hosted/pub.dev/<package>-<version>`
  /// recursively in all string values of [source]. `\$APP` is left as-is.
  Map<String, dynamic> resolvePlaceholders(
    Map<String, dynamic> source,
    String package,
    String version,
  ) {
    final pubDev = '.pub-cache/hosted/pub.dev/$package-$version';
    return _substituteMap(source, pubDev);
  }

  Map<String, dynamic> _substituteMap(Map<String, dynamic> m, String pubDev) =>
      {for (final e in m.entries) e.key: _substituteValue(e.value, pubDev)};

  dynamic _substituteValue(dynamic value, String pubDev) {
    if (value is String) return value.replaceAll(r'$PUB_DEV', pubDev);
    if (value is Map<String, dynamic>) return _substituteMap(value, pubDev);
    if (value is List) {
      return value.map((e) => _substituteValue(e, pubDev)).toList();
    }
    return value;
  }

  /// Downloads [url] bytes to [localPath], using [_cacheDir] as a
  /// content-addressed cache keyed by URL SHA-256.
  Future<void> _downloadFile(String url, String localPath) async {
    final cacheKey = sha256.convert(utf8.encode(url)).toString();
    final cacheFile = File(p.join(_cacheDir.path, cacheKey));

    final Uint8List bytes;
    if (cacheFile.existsSync()) {
      bytes = cacheFile.readAsBytesSync();
    } else {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} for $url');
      }
      bytes = response.bodyBytes;
      _cacheDir.createSync(recursive: true);
      cacheFile.writeAsBytesSync(bytes);
    }

    File(localPath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }
}

/// Reads package name → version from [lockPaths] (pub lock file format).
Map<String, String> _readLockedVersions(List<String> lockPaths) {
  final versions = <String, String>{};
  for (final path in lockPaths) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final yaml = loadYaml(f.readAsStringSync());
    if (yaml is! Map) continue;
    final pkgs = yaml['packages'];
    if (pkgs is! Map) continue;
    for (final e in pkgs.entries) {
      final name = e.key as String;
      final info = e.value;
      if (info is! Map || info['source'] != 'hosted') continue;
      final ver = info['version'] as String?;
      if (ver != null) versions[name] = ver;
    }
  }
  return versions;
}

/// Recursively converts YamlMap/YamlList to plain Dart Map/List.
dynamic _deepConvert(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) e.key as String: _deepConvert(e.value),
    };
  }
  if (value is List) return value.map(_deepConvert).toList();
  return value;
}
