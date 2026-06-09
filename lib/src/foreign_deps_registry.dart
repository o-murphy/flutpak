import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:pub_semver/pub_semver.dart';
import 'generators/manifest_generator.dart' show convertPatchToCrlf;
import 'utils/log.dart';

/// Result returned by [ForeignDepsRegistry.resolve].
class ForeignDepsResult {
  /// Flatpak source maps ready for `generated-sources.json`.
  final List<Map<String, dynamic>> sources;

  /// Paths to extracted `Cargo.lock` files for packages with `cargo_locks`
  /// entries in the registry. Populated in phase 2.2.
  final List<String> cargoLockPaths;

  /// Paths to extracted `pubspec.lock` files for packages with
  /// `extra_pubspecs` entries in the registry. Populated in phase 2.3.
  final List<String> extraPubspecPaths;

  const ForeignDepsResult({
    required this.sources,
    this.cargoLockPaths = const [],
    this.extraPubspecPaths = const [],
  });
}

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
  Directory? _extractDir;

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
  Future<ForeignDepsResult> resolve({
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
      return const ForeignDepsResult(sources: []);
    }

    final lockedVersions = _readLockedVersions(lockPaths);

    // Deep-merge local overrides on top of remote registry.
    final merged = _deepMergeRegistry(
      remote: registry,
      local: localForeignDeps,
      lockedVersions: lockedVersions,
    );

    final result = <Map<String, dynamic>>[];
    final allCargoLockPaths = <String>[];
    final allExtraPubspecPaths = <String>[];

    for (final package in merged.keys) {
      final version = lockedVersions[package];
      if (version == null) continue;

      final packageMap = merged[package];
      if (packageMap is! Map) continue;
      final (matchedVersion, versionEntry) = _matchVersion(packageMap, version);
      if (versionEntry == null) continue;

      // cargo_locks — extract Cargo.lock files from the pub.dev archive.
      final cargoLocks = versionEntry['cargo_locks'];
      if (cargoLocks is List && cargoLocks.isNotEmpty) {
        _extractDir ??= Directory.systemTemp.createTempSync('flutpak_extract_');
        allCargoLockPaths.addAll(await _extractFromArchive(
            package, version, cargoLocks, 'Cargo.lock', _extractDir!));
      }

      // extra_pubspecs — extract pubspec.lock from sub-package directories.
      final extraPubspecs = versionEntry['extra_pubspecs'];
      if (extraPubspecs is List && extraPubspecs.isNotEmpty) {
        _extractDir ??= Directory.systemTemp.createTempSync('flutpak_extract_');
        allExtraPubspecPaths.addAll(await _extractFromArchive(
            package, version, extraPubspecs, 'pubspec.lock', _extractDir!));
      }

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

    return ForeignDepsResult(
      sources: result,
      cargoLockPaths: allCargoLockPaths,
      extraPubspecPaths: allExtraPubspecPaths,
    );
  }

  void dispose() {
    _client.close();
    _extractDir?.deleteSync(recursive: true);
    _extractDir = null;
  }

  /// Downloads [url] bytes to the cache and returns the cache [File].
  ///
  /// Identical semantics to [_downloadFile] but returns the cached file
  /// instead of copying bytes to a destination path.
  Future<File> _fetchCached(String url) async {
    final cacheKey = sha256.convert(utf8.encode(url)).toString();
    final cacheFile = File(p.join(_cacheDir.path, cacheKey));
    if (!cacheFile.existsSync()) {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} for $url');
      }
      _cacheDir.createSync(recursive: true);
      cacheFile.writeAsBytesSync(response.bodyBytes);
    }
    return cacheFile;
  }

  /// Downloads the pub.dev archive for [package] [version] and extracts
  /// [filename] from each directory in [entries] into [extractDir].
  ///
  /// Each entry is a path string like `\$PUB_DEV/rust`; `\$PUB_DEV/` is
  /// stripped to obtain the archive-relative directory (e.g. `rust`), and
  /// [filename] is appended (e.g. `rust/Cargo.lock`).
  ///
  /// Returns the absolute paths of the successfully extracted files.
  Future<List<String>> _extractFromArchive(
    String package,
    String version,
    List<dynamic> entries,
    String filename,
    Directory extractDir,
  ) async {
    final archiveUrl =
        'https://pub.dev/packages/$package/versions/$version.tar.gz';
    final File archiveFile;
    try {
      archiveFile = await _fetchCached(archiveUrl);
    } catch (e) {
      logWarn(
          'foreign-deps: could not download $package-$version archive ($e) — skipping');
      return const [];
    }

    final extracted = <String>[];
    for (final raw in entries) {
      if (raw is! String) continue;
      final relDir =
          raw.replaceFirst(r'$PUB_DEV/', '').replaceFirst(r'$PUB_DEV', '');
      final archivePath = relDir.isEmpty ? filename : '$relDir/$filename';

      final destFile =
          File(p.join(extractDir.path, '$package-$version', archivePath));
      destFile.parent.createSync(recursive: true);

      final proc = await Process.run(
        'tar',
        ['-xzOf', archiveFile.path, archivePath],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (proc.exitCode != 0) {
        logWarn(
            'foreign-deps: $package-$version: could not extract $archivePath'
            ' (${(proc.stderr as String).trim()}) — skipping');
        continue;
      }

      destFile.writeAsStringSync(proc.stdout as String);
      logInfo('foreign-deps: extracted $archivePath from $package-$version');
      extracted.add(destFile.path);
    }
    return extracted;
  }

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
  Version? bestParsed;

  for (final key in packageMap.keys) {
    final parsed = _parseVersion(key as String);
    if (parsed == null) continue;
    if (parsed > installed) continue; // registry > installed
    if (bestParsed == null || parsed > bestParsed) {
      bestKey = key;
      bestParsed = parsed;
    }
  }

  if (bestKey == null) return (installedVersion, null);
  final entry = packageMap[bestKey];
  return (bestKey, entry is Map ? Map<String, dynamic>.from(entry) : null);
}

/// Parses a version string via [Version.parse], padding short versions
/// (e.g. `1.2` → `1.2.0`) to satisfy semver's three-component requirement.
/// Returns null if parsing fails after padding.
Version? _parseVersion(String version) {
  try {
    return Version.parse(version);
  } catch (_) {
    try {
      final parts = version.split('-');
      final numeric = parts.first.split('.');
      if (numeric.length < 3) {
        final padded = [...numeric, ...List.filled(3 - numeric.length, '0')];
        final normalized = padded.join('.') +
            (parts.length > 1 ? '-${parts.sublist(1).join("-")}' : '');
        return Version.parse(normalized);
      }
    } catch (_) {}
    return null;
  }
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
