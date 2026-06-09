import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:toml/toml.dart';

/// Generates a Flatpak module that installs Rust offline via rustup.
///
/// Port of rustup_generator.py from flatpak-flutter.
/// Fetches channel-rust-{version}.toml from static.rust-lang.org to obtain
/// URLs and checksums — no local Rust installation required.
class RustupGenerator {
  static const _arches = ['aarch64', 'x86_64'];
  static const _packages = ['cargo', 'rust-std', 'rustc'];

  final String rustVersion;
  final String rustupPath;
  final http.Client _client;
  final bool _ownsClient;

  RustupGenerator({
    required this.rustVersion,
    required this.rustupPath,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> generateModule() async {
    final sources = await _generateSources();
    return {
      'name': 'rustup',
      'buildsystem': 'simple',
      'build-options': {
        'env': {
          'CARGO_HOME': rustupPath,
          'RUSTUP_HOME': rustupPath,
          'RUSTUP_DIST_SERVER': 'file:///run/build/rustup/static.rust-lang.org',
        }
      },
      'build-commands': [
        'chmod +x rustup-init && ./rustup-init -y'
            ' --default-toolchain $rustVersion'
            ' --profile minimal --no-modify-path',
        'ln -s $rustupPath/toolchains/$rustVersion-'
            r'${FLATPAK_ARCH}-unknown-linux-gnu'
            ' $rustupPath/toolchains/stable-'
            r'${FLATPAK_ARCH}-unknown-linux-gnu',
      ],
      'sources': sources,
    };
  }

  Future<List<Map<String, dynamic>>> _generateSources() async {
    final channelUrl =
        'https://static.rust-lang.org/dist/channel-rust-$rustVersion.toml';
    final response = await _fetch(channelUrl);
    final channel = TomlDocument.parse(response.body).toMap();

    final date = channel['date'] as String;
    final pkgs = channel['pkg'] as Map<String, dynamic>;

    final sources = <Map<String, dynamic>>[];

    sources.addAll(await _channelEntries(channelUrl));

    for (final arch in _arches) {
      sources.add(await _rustupInitEntry(arch));
    }

    for (final package in _packages) {
      final pkgData = pkgs[package] as Map<String, dynamic>?;
      if (pkgData == null) continue;
      final targets = pkgData['target'] as Map<String, dynamic>?;
      if (targets == null) continue;

      for (final arch in _arches) {
        final details =
            targets['$arch-unknown-linux-gnu'] as Map<String, dynamic>?;
        if (details == null) continue;

        sources.add({
          'type': 'file',
          'only-arches': [arch],
          'url': details['xz_url'] as String,
          'sha256': details['xz_hash'] as String,
          'dest': 'static.rust-lang.org/dist/$date',
        });
      }
    }

    return sources;
  }

  /// Returns two entries: the channel TOML file and its .sha256 sidecar.
  Future<List<Map<String, dynamic>>> _channelEntries(String url) async {
    final sha256Url = '$url.sha256';
    final resp = await _fetch(sha256Url);

    // .sha256 file format: "<checksum>  <filename>"
    final tomlChecksum = resp.body.trim().split(' ').first;
    final sha256FileChecksum = sha256.convert(resp.bodyBytes).toString();

    return [
      {
        'type': 'file',
        'url': url,
        'sha256': tomlChecksum,
        'dest': 'static.rust-lang.org/dist',
      },
      {
        'type': 'file',
        'url': sha256Url,
        'sha256': sha256FileChecksum,
        'dest': 'static.rust-lang.org/dist',
      },
    ];
  }

  Future<Map<String, dynamic>> _rustupInitEntry(String arch) async {
    final url =
        'https://static.rust-lang.org/rustup/dist/$arch-unknown-linux-gnu/rustup-init';
    final resp = await _fetch('$url.sha256');
    final checksum = resp.body.trim().split(' ').first;

    return {
      'type': 'file',
      'only-arches': [arch],
      'url': url,
      'sha256': checksum,
    };
  }

  Future<http.Response> _fetch(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    return response;
  }
}
