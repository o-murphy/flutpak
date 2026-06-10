import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:flutpak/src/flutter_sdk_registry.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('flutpakmakeRegistry_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  FlutterSdkRegistry makeRegistry(MockClient client) => FlutterSdkRegistry(
        ref: 'main',
        client: client,
        cacheDir: Directory('${tmpDir.path}/flutter_sdk'),
      );

  group('FlutterSdkRegistry', () {
    test('returns pre-built JSON when HTTP 200', () async {
      const json = '{"name":"flutter-sdk"}';
      final reg =
          makeRegistry(MockClient((_) async => http.Response(json, 200)));
      final result = await reg.fetchPrebuilt('3.44.1');
      expect(result, json);
    });

    test('caches pre-built to disk on first fetch', () async {
      const json = '{"name":"flutter-sdk"}';
      final reg =
          makeRegistry(MockClient((_) async => http.Response(json, 200)));
      await reg.fetchPrebuilt('3.44.1');
      final cacheFile =
          File('${tmpDir.path}/flutter_sdk/flutter-sdk-3.44.1.json');
      expect(cacheFile.existsSync(), isTrue);
      expect(cacheFile.readAsStringSync(), json);
    });

    test('returns cached file without HTTP request on second fetch', () async {
      const json = '{"name":"flutter-sdk"}';
      var callCount = 0;
      final reg = makeRegistry(MockClient((_) async {
        callCount++;
        return http.Response(json, 200);
      }));
      await reg.fetchPrebuilt('3.44.1');
      final result2 = await reg.fetchPrebuilt('3.44.1');
      expect(callCount, 1);
      expect(result2, json);
    });

    test('returns null on HTTP 404', () async {
      final reg = makeRegistry(MockClient((_) async => http.Response('', 404)));
      expect(await reg.fetchPrebuilt('9.99.9'), isNull);
    });

    test('returns null on network error', () async {
      final reg =
          makeRegistry(MockClient((_) async => throw Exception('offline')));
      expect(await reg.fetchPrebuilt('3.44.1'), isNull);
    });

    test('cacheLocally writes file that is returned on next fetch', () async {
      const json = '{"name":"flutter-sdk","cached":true}';
      var callCount = 0;
      final reg = makeRegistry(MockClient((_) async {
        callCount++;
        return http.Response('', 404);
      }));
      reg.cacheLocally('3.44.1', json);
      final result = await reg.fetchPrebuilt('3.44.1');
      expect(callCount, 0);
      expect(result, json);
    });

    test('moduleUrl uses ref and version', () {
      final reg = FlutterSdkRegistry(ref: 'feat/test');
      expect(
        reg.moduleUrl('3.44.1'),
        'https://raw.githubusercontent.com/o-murphy/flutpak/feat/test'
        '/flutter_sdk/flutter-sdk-3.44.1.json',
      );
      reg.dispose();
    });
  });
}
