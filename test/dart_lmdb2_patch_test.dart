// Verifies the dart_lmdb2 foreign_deps registry entry resolves correctly
// against the real foreign_deps/foreign_deps.json (not the test fixture) —
// the actual file `flutpak` will fetch and apply for a real app build.
import 'dart:convert';
import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _root = Directory.current.absolute.path;

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('flutpak_dart_lmdb2_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('dart_lmdb2 0.9.12 resolves to the lmdb_native.dart patch with correct dest', () async {
    final registryJson = jsonDecode(
      File(p.join(_root, 'foreign_deps', 'foreign_deps.json')).readAsStringSync(),
    ) as Map<String, dynamic>;

    final lockFile = File(p.join(tmpDir.path, 'pubspec.lock'));
    lockFile.writeAsStringSync('''
packages:
  dart_lmdb2:
    dependency: "direct main"
    source: hosted
    version: "0.9.12"
''');

    final registry = ForeignDepsRegistry(
      client: MockClient((request) async {
        if (request.url.toString().endsWith('foreign_deps.json')) {
          return http.Response(jsonEncode(registryJson), 200);
        }
        return http.Response('not found', 404);
      }),
      cacheDir: Directory(p.join(tmpDir.path, 'cache')),
    );

    final generatedPatchesDir = p.join(tmpDir.path, 'generated_patches');
    final result = await registry.resolve(
      lockPaths: [lockFile.path],
      generatedPatchesDir: generatedPatchesDir,
      projectPatchesDir: p.join(_root, 'foreign_deps'),
    );
    registry.dispose();

    expect(result.sources, hasLength(1));
    final source = result.sources.single;
    expect(source['type'], 'patch');
    expect(source['dest'], '.pub-cache/hosted/pub.dev/dart_lmdb2-0.9.12');
    expect(source['path'], 'patches/dart_lmdb2/0.9.12-lmdb_native.dart.patch');

    // The patch file was actually copied (not just referenced) into
    // generatedPatchesDir, and its content matches the checked-in original.
    final copied = File(p.join(generatedPatchesDir, 'dart_lmdb2', '0.9.12-lmdb_native.dart.patch'));
    expect(copied.existsSync(), isTrue);
    final original = File(p.join(
      _root, 'foreign_deps', 'dart_lmdb2', '0.9.12-lmdb_native.dart.patch',
    ));
    expect(copied.readAsBytesSync(), original.readAsBytesSync());
  });

  test('flutter_lmdb2 0.9.5 resolves to LMDB git source + linux plugin patches', () async {
    final registryJson = jsonDecode(
      File(p.join(_root, 'foreign_deps', 'foreign_deps.json')).readAsStringSync(),
    ) as Map<String, dynamic>;

    final lockFile = File(p.join(tmpDir.path, 'pubspec.lock'));
    lockFile.writeAsStringSync('''
packages:
  flutter_lmdb2:
    dependency: "direct main"
    source: hosted
    version: "0.9.5"
''');

    final registry = ForeignDepsRegistry(
      client: MockClient((request) async {
        if (request.url.toString().endsWith('foreign_deps.json')) {
          return http.Response(jsonEncode(registryJson), 200);
        }
        return http.Response('not found', 404);
      }),
      cacheDir: Directory(p.join(tmpDir.path, 'cache')),
    );

    final generatedPatchesDir = p.join(tmpDir.path, 'generated_patches');
    final result = await registry.resolve(
      lockPaths: [lockFile.path],
      generatedPatchesDir: generatedPatchesDir,
      projectPatchesDir: p.join(_root, 'foreign_deps'),
    );
    registry.dispose();

    expect(result.sources, hasLength(3));

    final gitSource = result.sources[0];
    expect(gitSource['type'], 'git');
    expect(gitSource['url'], 'https://github.com/LMDB/lmdb.git');
    expect(gitSource['tag'], 'LMDB_0.9.31');
    expect(gitSource['commit'], 'ce201088de95d26fc0da36ba805bf2ddc2ba74ff');
    expect(gitSource['dest'],
        '.pub-cache/hosted/pub.dev/flutter_lmdb2-0.9.5/linux/lmdb-src');

    final pluginFilesPatch = result.sources[1];
    expect(pluginFilesPatch['type'], 'patch');
    expect(pluginFilesPatch['dest'], '.pub-cache/hosted/pub.dev/flutter_lmdb2-0.9.5');
    expect(pluginFilesPatch['path'],
        'patches/flutter_lmdb2/0.9.5-linux-plugin-files.patch');

    final pubspecPatch = result.sources[2];
    expect(pubspecPatch['type'], 'patch');
    expect(pubspecPatch['path'], 'patches/flutter_lmdb2/0.9.5-pubspec.yaml.patch');

    // Both patch files were actually copied and match the checked-in originals.
    for (final name in ['0.9.5-linux-plugin-files.patch', '0.9.5-pubspec.yaml.patch']) {
      final copied = File(p.join(generatedPatchesDir, 'flutter_lmdb2', name));
      expect(copied.existsSync(), isTrue, reason: name);
      final original =
          File(p.join(_root, 'foreign_deps', 'flutter_lmdb2', name));
      expect(copied.readAsBytesSync(), original.readAsBytesSync(), reason: name);
    }
  });
}
