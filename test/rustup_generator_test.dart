import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:flutpak/src/generators/rustup_generator.dart';

// Minimal channel-rust-1.80.0.toml content used across tests.
const _version = '1.80.0';
const _rustupPath = '/var/lib/rustup';
const _date = '2024-07-25';

const _channelToml = '''
date = "$_date"

[pkg.cargo.target.x86_64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/cargo-$_version-x86_64-unknown-linux-gnu.tar.xz"
xz_hash = "aaaa1111"

[pkg.cargo.target.aarch64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/cargo-$_version-aarch64-unknown-linux-gnu.tar.xz"
xz_hash = "bbbb2222"

[pkg.rust-std.target.x86_64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/rust-std-$_version-x86_64-unknown-linux-gnu.tar.xz"
xz_hash = "cccc3333"

[pkg.rust-std.target.aarch64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/rust-std-$_version-aarch64-unknown-linux-gnu.tar.xz"
xz_hash = "dddd4444"

[pkg.rustc.target.x86_64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/rustc-$_version-x86_64-unknown-linux-gnu.tar.xz"
xz_hash = "eeee5555"

[pkg.rustc.target.aarch64-unknown-linux-gnu]
available = true
xz_url = "https://static.rust-lang.org/dist/$_date/rustc-$_version-aarch64-unknown-linux-gnu.tar.xz"
xz_hash = "ffff6666"
''';

const _tomlChecksum =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

void main() {
  late Map<String, dynamic> module;

  setUpAll(() async {
    final gen = RustupGenerator(
      rustVersion: _version,
      rustupPath: _rustupPath,
      client: _FakeClient(),
    );
    module = await gen.generateModule();
    gen.dispose();
  });

  group('RustupGenerator.generateModule', () {
    test('module name is rustup', () {
      expect(module['name'], 'rustup');
    });

    test('buildsystem is simple', () {
      expect(module['buildsystem'], 'simple');
    });

    test(
        'build-options.env contains CARGO_HOME, RUSTUP_HOME, RUSTUP_DIST_SERVER',
        () {
      final env = (module['build-options'] as Map)['env'] as Map;
      expect(env['CARGO_HOME'], _rustupPath);
      expect(env['RUSTUP_HOME'], _rustupPath);
      expect(env['RUSTUP_DIST_SERVER'],
          'file:///run/build/rustup/static.rust-lang.org');
    });

    test('build-commands installs with correct version and --no-modify-path',
        () {
      final cmds = (module['build-commands'] as List).cast<String>();
      expect(cmds.any((c) => c.contains(_version)), isTrue);
      expect(cmds.any((c) => c.contains('--no-modify-path')), isTrue);
    });

    test('build-commands creates stable symlink', () {
      final cmds = (module['build-commands'] as List).cast<String>();
      expect(cmds.any((c) => c.contains('stable-')), isTrue);
    });

    group('sources', () {
      late List<Map<String, dynamic>> sources;

      setUp(() {
        sources = (module['sources'] as List).cast<Map<String, dynamic>>();
      });

      test('first source is channel TOML file', () {
        final first = sources[0];
        expect(first['type'], 'file');
        expect(first['url'], contains('channel-rust-$_version.toml'));
        expect(first['sha256'], _tomlChecksum);
        expect(first['dest'], 'static.rust-lang.org/dist');
      });

      test('second source is channel TOML sha256 sidecar', () {
        final second = sources[1];
        expect(second['type'], 'file');
        expect(second['url'], endsWith('.toml.sha256'));
        expect(second['dest'], 'static.rust-lang.org/dist');
        // sha256 of the .sha256 file content itself
        final expectedSha = sha256
            .convert(utf8.encode('$_tomlChecksum  channel-rust-$_version.toml'))
            .toString();
        expect(second['sha256'], expectedSha);
      });

      test('rustup-init entries for aarch64 and x86_64 are present', () {
        final initEntries = sources
            .where((s) =>
                s['type'] == 'file' &&
                (s['url'] as String).contains('rustup-init') &&
                !((s['url'] as String).endsWith('.sha256')))
            .toList();
        expect(initEntries, hasLength(2));
        final arches = initEntries
            .expand((s) => (s['only-arches'] as List).cast<String>())
            .toSet();
        expect(arches, containsAll(['aarch64', 'x86_64']));
      });

      test('cargo, rust-std, rustc entries for both arches are present', () {
        final pkgEntries = sources
            .where((s) =>
                s['type'] == 'file' &&
                s.containsKey('dest') &&
                (s['dest'] as String).contains(_date))
            .toList();
        // 3 packages × 2 arches = 6 entries
        expect(pkgEntries, hasLength(6));
      });

      test('package entries have correct dest with date', () {
        final pkgEntries = sources
            .where((s) =>
                s['type'] == 'file' &&
                s.containsKey('dest') &&
                (s['dest'] as String).contains(_date))
            .toList();
        for (final e in pkgEntries) {
          expect(e['dest'], 'static.rust-lang.org/dist/$_date');
        }
      });

      test('package entries have only-arches set', () {
        final pkgEntries = sources
            .where((s) =>
                s['type'] == 'file' &&
                s.containsKey('dest') &&
                (s['dest'] as String).contains(_date))
            .toList();
        for (final e in pkgEntries) {
          expect(e['only-arches'], isNotEmpty);
        }
      });
    });
  });
}

class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    final body = _body(url);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }

  static String _body(String url) {
    // channel TOML sha256 sidecar
    if (url.endsWith('channel-rust-$_version.toml.sha256')) {
      return '$_tomlChecksum  channel-rust-$_version.toml';
    }
    // channel TOML itself
    if (url.endsWith('channel-rust-$_version.toml')) {
      return _channelToml;
    }
    // rustup-init sha256 sidecars
    if (url.contains('rustup-init') && url.endsWith('.sha256')) {
      final arch = url.contains('aarch64') ? 'aarch64' : 'x86_64';
      return 'rustup${arch}sha256fake000000000000000000000000000000000000  rustup-init';
    }
    return '';
  }
}
