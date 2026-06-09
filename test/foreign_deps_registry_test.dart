import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutpak/flutpak.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

final _root = Directory.current.absolute.path;

Map<String, dynamic> _fixture() {
  final path = p.join(_root, 'test', 'fixtures', 'foreign_deps.json');
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

String _lockPath() =>
    p.join(_root, 'test', 'fixtures', 'foreign_deps_lock.lock');

MockClient _mockClient({
  required Map<String, dynamic> registryJson,
  Map<String, Uint8List> files = const {},
}) {
  return MockClient((request) async {
    final url = request.url.toString();
    if (url.endsWith('foreign_deps.json')) {
      return http.Response(jsonEncode(registryJson), 200);
    }
    for (final entry in files.entries) {
      if (url.endsWith(entry.key)) {
        return http.Response.bytes(entry.value, 200);
      }
    }
    return http.Response('not found', 404);
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tmpDir;
  late Directory cacheDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('flutpak_fdr_test_');
    cacheDir = Directory(p.join(tmpDir.path, 'cache'))..createSync();
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  // ── resolvePlaceholders ───────────────────────────────────────────────────

  group('resolvePlaceholders', () {
    late ForeignDepsRegistry registry;
    setUp(() {
      registry = ForeignDepsRegistry(
        client: MockClient((_) async => http.Response('', 200)),
        cacheDir: cacheDir,
      );
    });

    test('replaces \$PUB_DEV with correct path', () {
      final result = registry.resolvePlaceholders(
        {'dest': r'$PUB_DEV/sub'},
        'my_pkg',
        '1.0.0',
      );
      expect(result['dest'], '.pub-cache/hosted/pub.dev/my_pkg-1.0.0/sub');
    });

    test('leaves \$APP as-is', () {
      final result = registry.resolvePlaceholders(
        {'dest': r'$APP/build'},
        'my_pkg',
        '1.0.0',
      );
      expect(result['dest'], r'$APP/build');
    });

    test('handles nested maps recursively', () {
      final result = registry.resolvePlaceholders(
        {
          'outer': {
            'inner': r'$PUB_DEV/nested',
          }
        },
        'pkg',
        '2.0.0',
      );
      final inner = result['outer'] as Map<String, dynamic>;
      expect(inner['inner'], '.pub-cache/hosted/pub.dev/pkg-2.0.0/nested');
    });

    test('handles lists recursively', () {
      final result = registry.resolvePlaceholders(
        {
          'only-arches': ['x86_64', 'aarch64'],
          'dest': r'$PUB_DEV',
        },
        'pkg',
        '1.0.0',
      );
      expect(result['only-arches'], ['x86_64', 'aarch64']);
      expect(result['dest'], '.pub-cache/hosted/pub.dev/pkg-1.0.0');
    });
  });

  // ── ForeignDepsRegistry URL construction ─────────────────────────────────

  group('URL construction', () {
    test('ref=null builds URLs with main', () {
      final r = ForeignDepsRegistry(
        client: MockClient((_) async => http.Response('', 200)),
        cacheDir: cacheDir,
      );
      expect(r.registryUrl, contains('/main/'));
      expect(r.baseUrl, contains('/main/'));
    });

    test('ref=v0.6.0 builds URLs with v0.6.0', () {
      final r = ForeignDepsRegistry(
        ref: 'v0.6.0',
        client: MockClient((_) async => http.Response('', 200)),
        cacheDir: cacheDir,
      );
      expect(r.registryUrl, contains('/v0.6.0/'));
      expect(r.baseUrl, contains('/v0.6.0/'));
    });
  });

  // ── fetchJson ─────────────────────────────────────────────────────────────

  group('fetchJson', () {
    test('returns parsed JSON on success', () async {
      final data = {'pkg': {}};
      final r = ForeignDepsRegistry(
        client: _mockClient(registryJson: data),
        cacheDir: cacheDir,
      );
      expect(await r.fetchJson(), data);
    });

    test('falls back to cache on network failure with warning', () async {
      // Pre-populate cache.
      final data = {'cached': {}};
      final key = _urlKey(ForeignDepsRegistry(
              client: MockClient((_) async => http.Response('', 200)),
              cacheDir: cacheDir)
          .registryUrl);
      File(p.join(cacheDir.path, '$key.json'))
          .writeAsStringSync(jsonEncode(data));

      // Now fail the network.
      final r = ForeignDepsRegistry(
        client: MockClient((_) async => throw Exception('no network')),
        cacheDir: cacheDir,
      );
      final result = await r.fetchJson();
      expect(result, data);
    });

    test('throws when fetch fails and no cache exists', () async {
      final r = ForeignDepsRegistry(
        client: MockClient((_) async => throw Exception('no network')),
        cacheDir: cacheDir,
      );
      await expectLater(r.fetchJson(), throwsException);
    });
  });

  // ── resolve ───────────────────────────────────────────────────────────────

  group('resolve', () {
    test('suppresses entry via localForeignDeps empty sources', () async {
      final patchBytes = Uint8List.fromList(utf8.encode('patch content'));
      final r = ForeignDepsRegistry(
        client: _mockClient(
          registryJson: _fixture(),
          files: {'some_package/fix.patch': patchBytes},
        ),
        cacheDir: cacheDir,
      );
      final patchesDir = p.join(tmpDir.path, 'patches');
      // Suppress some_package by providing an empty sources list.
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        localForeignDeps: {
          'some_package': {
            'manifest': {'sources': []}
          }
        },
        generatedPatchesDir: patchesDir,
      );
      expect(result.every((s) {
        final dest = s['dest'] as String? ?? '';
        return !dest.contains('some_package');
      }), isTrue);
    });

    test('skips packages not in lock file', () async {
      final r = ForeignDepsRegistry(
        client: _mockClient(registryJson: {
          'not_in_lock': {
            '9.9.9': {
              'manifest': {
                'sources': [
                  {'type': 'file', 'url': 'https://x.com', 'dest': r'$PUB_DEV'}
                ]
              }
            }
          }
        }),
        cacheDir: cacheDir,
      );
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      expect(result, isEmpty);
    });

    test('returns empty list when registry has no matching entries', () async {
      final r = ForeignDepsRegistry(
        client: _mockClient(registryJson: {}),
        cacheDir: cacheDir,
      );
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      expect(result, isEmpty);
    });

    test('rewrites path to patches/<path> for type:patch sources', () async {
      final patchBytes = Uint8List.fromList(utf8.encode('--- a\n+++ b\n'));
      final r = ForeignDepsRegistry(
        client: _mockClient(
          registryJson: _fixture(),
          files: {'some_package/fix.patch': patchBytes},
        ),
        cacheDir: cacheDir,
      );
      final patchesDir = p.join(tmpDir.path, 'patches');
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: patchesDir,
      );
      final patch = result.firstWhere((s) => s['type'] == 'patch');
      expect(patch['path'], 'patches/some_package/fix.patch');
    });

    test('applies placeholder substitution to dest for all source types',
        () async {
      final patchBytes = Uint8List.fromList(utf8.encode('patch'));
      final r = ForeignDepsRegistry(
        client: _mockClient(
          registryJson: _fixture(),
          files: {'some_package/fix.patch': patchBytes},
        ),
        cacheDir: cacheDir,
      );
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      for (final src in result) {
        final dest = src['dest'] as String?;
        if (dest != null) {
          expect(dest, isNot(contains(r'$PUB_DEV')));
        }
      }
    });

    test('passes use-git field through unchanged', () async {
      final patchBytes = Uint8List.fromList(utf8.encode('patch'));
      final r = ForeignDepsRegistry(
        client: _mockClient(
          registryJson: _fixture(),
          files: {'some_package/fix.patch': patchBytes},
        ),
        cacheDir: cacheDir,
      );
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      final patch = result.firstWhere((s) => s['type'] == 'patch');
      expect(patch['use-git'], isTrue);
    });

    test('passes unknown fields through unchanged', () async {
      final r = ForeignDepsRegistry(
        client: _mockClient(registryJson: {
          'another_package': {
            '2.0.0': {
              'manifest': {
                'sources': [
                  {
                    'type': 'file',
                    'url': 'https://example.com/lib.so',
                    'sha256': 'abc123',
                    'dest': r'$APP/build/libs',
                    'dest-filename': 'lib.so',
                    'only-arches': ['x86_64'],
                  }
                ]
              }
            }
          }
        }),
        cacheDir: cacheDir,
      );
      final result = await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      expect(result, hasLength(1));
      expect(result.first['dest-filename'], 'lib.so');
      expect(result.first['only-arches'], ['x86_64']);
    });

    test('patch file bytes are written as-is without line ending modification',
        () async {
      const content = 'line1\r\nline2\r\n';
      final patchBytes = Uint8List.fromList(utf8.encode(content));
      final r = ForeignDepsRegistry(
        client: _mockClient(
          registryJson: _fixture(),
          files: {'some_package/fix.patch': patchBytes},
        ),
        cacheDir: cacheDir,
      );
      final patchesDir = p.join(tmpDir.path, 'patches');
      await r.resolve(
        lockPaths: [_lockPath()],
        generatedPatchesDir: patchesDir,
      );
      final written = File(p.join(patchesDir, 'some_package', 'fix.patch'))
          .readAsBytesSync();
      expect(written, patchBytes);
    });

    test('localForeignDeps shorthand overrides remote entry for locked version',
        () async {
      final r = ForeignDepsRegistry(
        client: _mockClient(registryJson: {
          'some_pkg': {
            '1.0.0': {
              'manifest': {
                'sources': [
                  {'type': 'file', 'url': 'https://remote.com/old.so', 'dest': r'$PUB_DEV'}
                ]
              }
            }
          }
        }),
        cacheDir: cacheDir,
      );
      // Shorthand: manifest key directly, version resolved from lock.
      // Use a lock file that has some_pkg at 1.0.0 — we write a temp one.
      final lockFile = File(p.join(tmpDir.path, 'test.lock'))
        ..writeAsStringSync('''
packages:
  some_pkg:
    dependency: "direct main"
    source: hosted
    version: "1.0.0"
''');
      final result = await r.resolve(
        lockPaths: [lockFile.path],
        localForeignDeps: {
          'some_pkg': {
            'manifest': {
              'sources': [
                {'type': 'file', 'url': 'https://local.com/new.so', 'dest': r'$PUB_DEV'}
              ]
            }
          }
        },
        generatedPatchesDir: p.join(tmpDir.path, 'patches'),
      );
      expect(result, hasLength(1));
      expect(result.first['url'], 'https://local.com/new.so');
    });
  });
}

// Compute the cache key the same way ForeignDepsRegistry does.
String _urlKey(String url) =>
    crypto.sha256.convert(utf8.encode(url)).toString();
