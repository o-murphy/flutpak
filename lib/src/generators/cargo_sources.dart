import 'dart:convert';
import 'dart:io';
import 'package:toml/toml.dart';
import '../utils/log.dart';

const _cratesIo = 'https://static.crates.io/crates';
const _cargoHome = 'cargo';
const _cargoCrates = '$_cargoHome/vendor';
const _vendoredSources = 'vendored-sources';

/// Generates flatpak-builder source entries from one or more [Cargo.lock] files.
///
/// Port of cargo_generator.py from flatpak-flutter.
/// Git crate dependencies are not supported in MVP — they are warned and skipped.
class CargoSourcesGenerator {
  static Future<List<Map<String, dynamic>>> generate(
    List<String> cargoLockPaths, {
    String configFilename = 'config.toml',
  }) async {
    final sources = <Map<String, dynamic>>[];
    final cargoVendoredSources = <String, dynamic>{
      _vendoredSources: {'directory': _cargoCrates},
    };

    for (final lockPath in cargoLockPaths) {
      final file = File(lockPath);
      if (!file.existsSync()) {
        logWarn('cargo: Cargo.lock not found: $lockPath — skipping');
        continue;
      }

      final cargoLock = TomlDocument.parse(file.readAsStringSync()).toMap();
      final packages = cargoLock['package'] as List? ?? [];
      final packageSources = <Map<String, dynamic>>[];

      for (final rawPkg in packages) {
        final pkg = rawPkg as Map<String, dynamic>;
        final result = _getPackageSources(pkg, cargoLock);
        if (result == null) continue;
        final (pkgSources, vendoredEntry) = result;
        packageSources.addAll(pkgSources);
        cargoVendoredSources.addAll(vendoredEntry);
      }

      _dedupe(sources, packageSources);
    }

    sources.add({
      'type': 'inline',
      'contents':
          TomlDocument.fromMap({'source': cargoVendoredSources}).toString(),
      'dest': _cargoHome,
      'dest-filename': configFilename,
    });

    return sources;
  }

  static (List<Map<String, dynamic>>, Map<String, dynamic>)? _getPackageSources(
    Map<String, dynamic> pkg,
    Map<String, dynamic> cargoLock,
  ) {
    final name = pkg['name'] as String?;
    final version = pkg['version'] as String?;
    final source = pkg['source'] as String?;

    if (name == null || version == null || source == null) return null;

    if (source.startsWith('git+')) {
      logWarn(
          'cargo: git dep "$name" ($source) — not supported in MVP, skipping');
      return null;
    }

    final checksum = _checksum(pkg, cargoLock, name, version, source);
    if (checksum == null) {
      logWarn('cargo: $name $version has no checksum — skipping');
      return null;
    }

    return (
      [
        {
          'type': 'archive',
          'archive-type': 'tar-gzip',
          'url': '$_cratesIo/$name/$name-$version.crate',
          'sha256': checksum,
          'dest': '$_cargoCrates/$name-$version',
        },
        {
          'type': 'inline',
          'contents':
              jsonEncode({'package': checksum, 'files': <String, dynamic>{}}),
          'dest': '$_cargoCrates/$name-$version',
          'dest-filename': '.cargo-checksum.json',
        },
      ],
      {
        'crates-io': {'replace-with': _vendoredSources}
      },
    );
  }

  // Cargo.lock v3: checksum on package directly.
  // Cargo.lock v1/v2: checksum in [metadata] table.
  static String? _checksum(
    Map<String, dynamic> pkg,
    Map<String, dynamic> cargoLock,
    String name,
    String version,
    String source,
  ) {
    if (pkg['checksum'] is String) return pkg['checksum'] as String;
    final metadata = cargoLock['metadata'];
    if (metadata is Map) {
      final val = metadata['checksum $name $version ($source)'];
      if (val is String) return val;
    }
    return null;
  }

  static void _dedupe(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> items,
  ) {
    for (final item in items) {
      if (!current.any((e) => _deepEquals(e, item))) {
        current.add(item);
      }
    }
  }

  static bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
