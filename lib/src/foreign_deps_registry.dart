import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'generators/manifest_generator.dart' show convertPatchToCrlf;
import 'utils/log.dart';

/// Resolves package dependencies from the flutpak foreign_deps registry,
/// compatible with the flatpak-flutter foreign_deps.json format.
///
/// The registry maps pub package names to per-version source lists
/// (archives, patches, files). On a `generate` run the registry is fetched
/// from GitHub and any packages found in the project's lock files are resolved
/// into flatpak source maps ready for `generated-sources.json`.
///
/// Local overrides from `config.foreign_deps` (see [FlatpakGenConfig.localForeignDeps])
/// are deep-merged on top of the remote registry before resolution.
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
  /// [localForeignDeps] entries are deep-merged on top of the remote registry
  /// before resolution — local package+version entries override remote ones.
  /// An entry with an empty `sources: []` suppresses the remote entry.
  ///
  /// For each resolved package version:
  ///   - `type: patch` sources with a remote URL are downloaded to
  ///     `[generatedPatchesDir]/<original-path>` as raw bytes.
  ///   - `type: patch` sources without a URL are copied from
  ///     `[projectPatchesDir]/<path>` when that directory exists, otherwise
  ///     fetched from the registry base URL.
  ///   - If `crlf: true` is set on a patch source, the file is normalised to
  ///     CRLF line endings after downloading/copying. The `crlf` key is always
  ///     stripped from the output map (not valid for flatpak-builder).
  ///   - All other source types have placeholder substitution applied and are
  ///     included as-is.
  ///
  /// Returns source maps ready to append to `generated-sources.json`.
  Future<List<Map<String, dynamic>>> resolve({
    required List<String> lockPaths,
    required String generatedPatchesDir,
    Map<String, dynamic> localForeignDeps = const {},
    String? projectPatchesDir,
  }) async {
    final Map<String, dynamic> registry;
    try {
      registry = await fetchJson();
    } catch (e) {
      logWarn('foreign-deps: registry unavailable ($e) — skipping');
      return const [];
    }

    final lockedVersions = _readLockedVersions(lockPaths);

    // Deep-merge local overrides on top of remote registry.
    final merged = _deepMergeRegistry(
      remote: registry,
      local: localForeignDeps,
      lockedVersions: lockedVersions,
    );

    final result = <Map<String, dynamic>>[];

    for (final package in merged.keys) {
      final version = lockedVersions[package];
      if (version == null) continue;

      final packageMap = merged[package];
      if (packageMap is! Map) continue;
      final (matchedVersion, versionEntry) = _matchVersion(packageMap, version);
      if (versionEntry == null) continue;
      final manifest = versionEntry['manifest'];
      if (manifest is! Map) continue;
      final sources = manifest['sources'];
      if (sources is! List) continue;

      // Empty sources list → local override suppresses this registry entry.
      if (sources.isEmpty) continue;

      for (final rawSource in sources) {
        if (rawSource is! Map) continue;
        var source = _deepConvert(rawSource);
        source = resolvePlaceholders(source, package, version);

        if (source['type'] == 'patch') {
          final crlf = source['crlf'] as bool? ?? false;
          source = Map<String, dynamic>.from(source)..remove('crlf');

          final origPath = source['path'] as String;
          final url = source['url'] as String?;
          final localFile = p.join(generatedPatchesDir, origPath);

          if (url != null) {
            await _downloadFile(url, localFile, crlf: crlf);
          } else {
            final srcFile = projectPatchesDir != null
                ? p.join(projectPatchesDir, origPath)
                : null;
            if (srcFile != null && File(srcFile).existsSync()) {
              _copyLocalPatch(srcFile, localFile, crlf: crlf);
            } else {
              await _downloadFile(baseUrl + origPath, localFile, crlf: crlf);
            }
          }

          source = Map<String, dynamic>.from(source);
          source['path'] = 'patches/$origPath';
        }

        result.add(source);
      }

      final versionLabel = matchedVersion == version
          ? version
          : '$version (matched registry $matchedVersion)';
      logInfo(
          'foreign-deps: $package $versionLabel — ${sources.length} source(s)');
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
  /// Normalises line endings when [crlf] is true.
  Future<void> _downloadFile(String url, String localPath,
      {bool crlf = false}) async {
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

    File(localPath).createSync(recursive: true);
    if (crlf) {
      File(localPath).writeAsStringSync(convertPatchToCrlf(utf8.decode(bytes)));
    } else {
      File(localPath).writeAsBytesSync(bytes);
    }
  }

  /// Copies a local patch file to [destPath], normalising line endings.
  void _copyLocalPatch(String srcPath, String destPath, {bool crlf = false}) {
    final src = File(srcPath);
    if (!src.existsSync()) {
      logWarn('foreign-deps: local patch not found: $srcPath');
      return;
    }
    File(destPath).createSync(recursive: true);
    if (crlf) {
      File(destPath)
          .writeAsStringSync(convertPatchToCrlf(src.readAsStringSync()));
    } else {
      File(destPath).writeAsBytesSync(src.readAsBytesSync());
    }
  }

  /// Deep-merges [local] entries on top of [remote].
  ///
  /// Local entries with a direct `manifest:` key (shorthand — no version)
  /// have their version resolved from [lockedVersions].
  /// Versioned entries (`"1.2.3": { manifest: ... }`) merge directly.
  static Map<String, dynamic> _deepMergeRegistry({
    required Map<String, dynamic> remote,
    required Map<String, dynamic> local,
    required Map<String, String> lockedVersions,
  }) {
    final result = <String, dynamic>{};
    for (final e in remote.entries) {
      result[e.key] = _deepConvert(e.value);
    }
    for (final entry in local.entries) {
      final package = entry.key;
      final value = entry.value;
      if (value is! Map) continue;

      if (value.containsKey('manifest')) {
        // Shorthand format: resolve version from lock file.
        final version = lockedVersions[package];
        if (version == null) continue;
        final existing = (result[package] as Map<String, dynamic>?) ?? {};
        result[package] = <String, dynamic>{
          ...existing,
          version: _deepConvert(value),
        };
      } else {
        // Versioned format: merge each version entry.
        final existing =
            Map<String, dynamic>.from(result[package] as Map? ?? {});
        for (final ve in value.entries) {
          existing[ve.key as String] = _deepConvert(ve.value);
        }
        result[package] = existing;
      }
    }
    return result;
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

/// Finds the best-matching registry version entry for [installedVersion].
///
/// Returns the entry with the highest registry version that is ≤ [installedVersion],
/// along with the matched version string. Returns `(installedVersion, null)` if no
/// suitable entry exists.
(String, Map<String, dynamic>?) _matchVersion(
    Map packageMap, String installedVersion) {
  final installed = _parseVersion(installedVersion);
  if (installed == null) return (installedVersion, null);

  String? bestKey;
  List<int>? bestParsed;

  for (final key in packageMap.keys) {
    final parsed = _parseVersion(key as String);
    if (parsed == null) continue;
    if (_compareVersions(parsed, installed) > 0)
      continue; // registry > installed
    if (bestParsed == null || _compareVersions(parsed, bestParsed) > 0) {
      bestKey = key;
      bestParsed = parsed;
    }
  }

  if (bestKey == null) return (installedVersion, null);
  final entry = packageMap[bestKey];
  return (bestKey, entry is Map ? Map<String, dynamic>.from(entry) : null);
}

/// Parses a version string into a list of numeric components.
/// Strips pre-release and build metadata. Returns null on parse failure.
List<int>? _parseVersion(String version) {
  final clean = version.split('+').first.split('-').first;
  final parts = clean.split('.');
  try {
    return parts.map(int.parse).toList();
  } catch (_) {
    return null;
  }
}

/// Compares two parsed version component lists lexicographically.
/// Returns negative if a < b, zero if equal, positive if a > b.
int _compareVersions(List<int> a, List<int> b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
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
