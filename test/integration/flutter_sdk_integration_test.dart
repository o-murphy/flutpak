@Tags(['flutter'])
library;

import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

void main() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];

  group(
    'FlutterSdkGenerator — real Flutter SDK',
    skip: flutterRoot == null ? 'FLUTTER_ROOT not set' : null,
    () {
      late List<FlatpakSource> sources;

      setUpAll(() async {
        // Resolve the current Flutter ref from the local SDK so we can pass
        // it to FlutterSdkGenerator without needing a pre-known version.
        final result = Process.runSync(
          'git',
          ['describe', '--tags', '--exact-match', 'HEAD'],
          workingDirectory: flutterRoot,
        );
        final flutterRef = result.exitCode == 0
            ? (result.stdout as String).trim()
            : (Process.runSync('git', ['rev-parse', 'HEAD'],
                        workingDirectory: flutterRoot)
                    .stdout as String)
                .trim();

        final gen = FlutterSdkGenerator(
          flutterRef: flutterRef,
          cache: _FakeCache(),
        );
        sources = await gen.generate();
      });

      test('generates more than 15 sources', () {
        expect(sources.length, greaterThan(15));
      });

      test('Flutter git source is first and has a real commit hash', () {
        final git = sources.whereType<GitSource>().first;
        expect(git.url, 'https://github.com/flutter/flutter.git');
        expect(git.commit, isNotNull,
            reason: 'real Flutter SDK has a .git dir');
        expect(git.commit, matches(RegExp(r'^[0-9a-f]{40}$')),
            reason: 'commit must be a 40-char SHA-1');
        expect(git.tag, matches(RegExp(r'^\d+\.\d+\.\d+')));
      });

      test('x86_64 and aarch64 artifacts are present', () {
        final arches = sources
            .whereType<ArchiveSource>()
            .where((s) => s.onlyArches != null)
            .expand((s) => s.onlyArches!)
            .toSet();
        expect(arches, containsAll(['x86_64', 'aarch64']));
      });

      test('engine_stamp.json is a FileSource in flutter/bin/cache', () {
        final stamp = sources
            .whereType<FileSource>()
            .firstWhere((s) => s.url.contains('engine_stamp.json'));
        expect(stamp.dest, 'flutter/bin/cache');
      });
    },
  );
}

class _FakeCache implements DownloadCache {
  @override
  Future<String> sha256For(String url) async => 'f' * 64;
  @override
  void dispose() {}
}
