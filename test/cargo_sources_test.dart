import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:flutpak/src/generators/cargo_sources.dart';

void main() {
  final fixturesDir = '${Directory.current.path}/test/fixtures';

  group('CargoSourcesGenerator', () {
    test('v3 lock — generates archive + checksum inline per crate', () async {
      final lockPath = '$fixturesDir/cargo_lock_v3.lock';
      final sources = await CargoSourcesGenerator.generate([lockPath]);

      // Last entry is always the config.toml inline.
      final crateSources = sources.sublist(0, sources.length - 1);

      expect(crateSources, hasLength(2)); // archive + checksum for libc

      final archive = crateSources[0];
      expect(archive['type'], 'archive');
      expect(archive['archive-type'], 'tar-gzip');
      expect(archive['url'],
          'https://static.crates.io/crates/libc/libc-0.2.172.crate');
      expect(archive['sha256'],
          'ab8b3df399b4cf5f7ad60dc59b8f6dcca8a37ed38b5a6b741a2891c22e9e9d3b');
      expect(archive['dest'], 'cargo/vendor/libc-0.2.172');

      final checksum = crateSources[1];
      expect(checksum['type'], 'inline');
      expect(checksum['dest'], 'cargo/vendor/libc-0.2.172');
      expect(checksum['dest-filename'], '.cargo-checksum.json');
      final checksumContents =
          jsonDecode(checksum['contents'] as String) as Map;
      expect(checksumContents['package'],
          'ab8b3df399b4cf5f7ad60dc59b8f6dcca8a37ed38b5a6b741a2891c22e9e9d3b');
      expect(checksumContents['files'], isEmpty);
    });

    test('v3 lock — last source is config.toml inline with vendored-sources',
        () async {
      final lockPath = '$fixturesDir/cargo_lock_v3.lock';
      final sources = await CargoSourcesGenerator.generate([lockPath]);

      final configSource = sources.last;
      expect(configSource['type'], 'inline');
      expect(configSource['dest'], 'cargo');
      expect(configSource['dest-filename'], 'config.toml');

      final contents = configSource['contents'] as String;
      expect(contents, contains('vendored-sources'));
      expect(contents, contains('cargo/vendor'));
      expect(contents, contains('crates-io'));
    });

    test('v2 lock — reads checksum from [metadata] table', () async {
      final lockPath = '$fixturesDir/cargo_lock_v2.lock';
      final sources = await CargoSourcesGenerator.generate([lockPath]);

      final archive = sources.firstWhere((s) => s['type'] == 'archive');
      expect(archive['url'],
          'https://static.crates.io/crates/serde/serde-1.0.219.crate');
      expect(archive['sha256'],
          '5f0e2d78a1e0be0a2b43bda0c8e0de08eb6d5c8fd02c37854cd3c7d5c15c5c6d');
    });

    test('configFilename parameter is respected', () async {
      final lockPath = '$fixturesDir/cargo_lock_v3.lock';
      final sources = await CargoSourcesGenerator.generate(
        [lockPath],
        configFilename: 'my-config.toml',
      );
      expect(sources.last['dest-filename'], 'my-config.toml');
    });

    test('duplicate crates across multiple locks are deduplicated', () async {
      final lockPath = '$fixturesDir/cargo_lock_v3.lock';
      final sources =
          await CargoSourcesGenerator.generate([lockPath, lockPath]);

      // libc should appear exactly once (archive + checksum) despite two locks
      final archivesForLibc = sources
          .where((s) =>
              s['type'] == 'archive' && (s['url'] as String).contains('libc'))
          .toList();
      expect(archivesForLibc, hasLength(1));
    });

    test('packages without source field are silently skipped', () async {
      final lockPath = '$fixturesDir/cargo_lock_v3.lock';
      final sources = await CargoSourcesGenerator.generate([lockPath]);
      // myapp has no source — only libc contributes 2 entries + config.toml
      expect(sources, hasLength(3));
    });

    test('missing Cargo.lock file is warned and skipped', () async {
      final sources = await CargoSourcesGenerator.generate(
        ['/nonexistent/Cargo.lock'],
      );
      // Only the config.toml inline is emitted
      expect(sources, hasLength(1));
      expect(sources.last['dest-filename'], 'config.toml');
    });

    test('git+ source packages are warned and skipped', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutpak_test_');
      final lockFile = File('${tmpDir.path}/Cargo.lock')..writeAsStringSync('''
version = 3

[[package]]
name = "some-git-crate"
version = "0.1.0"
source = "git+https://github.com/example/repo#abc123"
''');

      try {
        final sources = await CargoSourcesGenerator.generate([lockFile.path]);
        // Only config.toml — git crate is skipped
        expect(sources, hasLength(1));
        expect(sources.last['dest-filename'], 'config.toml');
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });
}
