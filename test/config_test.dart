import 'dart:io';
import 'package:flutpak/flutpak.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FlatpakGenConfig.fromYaml', () {
    test('parses full config', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'output': 'flatpak',
        'pub': {
          'locks': ['pubspec.lock', 'packages/a7p/pubspec.lock'],
        },
        'flutter': {
          'ref': '3.44.1',
          'patch': 'flatpak/patches/flutter/shared.sh.patch',
        },
      });

      expect(cfg.output, 'flatpak');
      expect(cfg.pubLocks, ['pubspec.lock', 'packages/a7p/pubspec.lock']);
      expect(cfg.flutterRef, '3.44.1');
      expect(cfg.patchPath, 'flatpak/patches/flutter/shared.sh.patch');
    });

    test('parses flutter.ref tag', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {'ref': '3.44.1'},
      });
      expect(cfg.flutterRef, '3.44.1');
    });

    test('flutterRef is null when flutter.ref absent', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.flutterRef, isNull);
    });

    test('defaults output when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.output, 'flatpak');
    });

    test('defaults pub locks to pubspec.lock when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.pubLocks, contains('pubspec.lock'));
    });

    test('reads flutter patch from flutter.patch key', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {
          'patch': 'patches/flutter/shared.sh.patch',
        },
      });
      expect(cfg.patchPath, 'patches/flutter/shared.sh.patch');
    });

    test('parses foreign-deps into localForeignDeps', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'foreign-deps': {
          'sqlite3_flutter_libs': {
            'manifest': {
              'sources': [
                {'type': 'patch', 'path': 'patches/sqlite3.patch', 'crlf': true}
              ]
            }
          }
        },
      });
      expect(cfg.localForeignDeps, contains('sqlite3_flutter_libs'));
      final entry = cfg.localForeignDeps['sqlite3_flutter_libs'] as Map;
      expect(entry['manifest'], isNotNull);
    });

    test('localForeignDeps defaults to empty map', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.localForeignDeps, isEmpty);
    });

    test('parses manifest config (kebab-case keys)', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'app-id': 'io.github.example.myapp',
        'runtime-version': '25.08',
        'command': 'myapp',
        'sdk-extensions': ['org.freedesktop.Sdk.Extension.llvm20'],
      });
      expect(cfg.manifest, isNotNull);
      expect(cfg.manifest!.appId, 'io.github.example.myapp');
      expect(cfg.manifest!.runtimeVersion, '25.08');
      expect(cfg.manifest!.command, 'myapp');
      expect(cfg.manifest!.sdkExtensions,
          contains('org.freedesktop.Sdk.Extension.llvm20'));
    });

    test('parses root-level icons', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'icons': [
          {'size': '256x256', 'path': 'app/share/icons/256/myapp.png'},
          {'size': '512x512', 'path': 'app/share/icons/512/myapp.png'},
        ],
        'app-id': 'io.example.app',
      });
      expect(cfg.icons, hasLength(2));
      expect(cfg.icons.first.size, '256x256');
    });

    test('icons without 256x256 throws ArgumentError', () {
      expect(
        () => FlatpakGenConfig.fromYaml({
          'icons': [
            {'size': '512x512', 'path': 'app/share/icons/512/myapp.png'},
          ],
          'app-id': 'io.example.app',
        }),
        throwsArgumentError,
      );
    });

    test('icons empty when key absent', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'app-id': 'io.example.app',
      });
      expect(cfg.icons, isEmpty);
    });

    test('disableSubmodules defaults to false when key absent', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.disableSubmodules, isFalse);
    });

    test('parses disable-submodules: true', () {
      final cfg = FlatpakGenConfig.fromYaml({'disable-submodules': true});
      expect(cfg.disableSubmodules, isTrue);
    });

    test('parses disable-submodules: false explicitly', () {
      final cfg = FlatpakGenConfig.fromYaml({'disable-submodules': false});
      expect(cfg.disableSubmodules, isFalse);
    });

    test('foreignDepsRef is null when foreign-deps-ref absent', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.foreignDepsRef, isNull);
    });

    test('parses foreign-deps-ref: main', () {
      final cfg = FlatpakGenConfig.fromYaml({'foreign-deps-ref': 'main'});
      expect(cfg.foreignDepsRef, 'main');
    });

    test('parses foreign-deps-ref: v0.6.0', () {
      final cfg = FlatpakGenConfig.fromYaml({'foreign-deps-ref': 'v0.6.0'});
      expect(cfg.foreignDepsRef, 'v0.6.0');
    });

    test('parses repo-url, metainfo-path, desktop-entry-path from root config',
        () {
      final cfg = FlatpakGenConfig.fromYaml({
        'repo-url': 'https://github.com/example/app.git',
        'metainfo-path': 'custom/path.metainfo.xml',
        'desktop-entry-path': 'custom/app.desktop',
      });
      expect(cfg.repoUrl, 'https://github.com/example/app.git');
      expect(cfg.metainfoPath, 'custom/path.metainfo.xml');
      expect(cfg.desktopEntryPath, 'custom/app.desktop');
    });

    test('effectiveMetainfoPath() returns default', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.effectiveMetainfoPath('io.example.app'),
          'app/share/metainfo/io.example.app.metainfo.xml');
    });

    test('effectiveMetainfoPath() returns config override', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'metainfo-path': 'custom/path.metainfo.xml',
      });
      expect(cfg.effectiveMetainfoPath('io.example.app'),
          'custom/path.metainfo.xml');
    });

    test('effectiveDesktopEntryPath() returns default', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.effectiveDesktopEntryPath('io.example.app'),
          'app/share/applications/io.example.app.desktop');
    });

    test('effectiveDesktopEntryPath() returns config override', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'desktop-entry-path': 'custom/app.desktop',
      });
      expect(cfg.effectiveDesktopEntryPath('io.example.app'),
          'custom/app.desktop');
    });

    test('effectiveIcons() returns default 256x256 when icons empty', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      final icons = cfg.effectiveIcons('io.example.app');
      expect(icons, hasLength(1));
      expect(icons.first.size, '256x256');
      expect(icons.first.path,
          'app/share/icons/hicolor/256x256/apps/io.example.app.png');
    });

    test('effectiveIcons() returns configured icons when present', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'icons': [
          {'size': '256x256', 'path': 'assets/256.png'},
          {'size': 'scalable', 'path': 'assets/icon.svg'},
        ],
      });
      final icons = cfg.effectiveIcons('io.example.app');
      expect(icons, hasLength(2));
      expect(icons[1].size, 'scalable');
    });
  });

  group('FlatpakGenConfig.load', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('flutpak_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('reads flatpak_gen: section from pubspec.yaml', () {
      File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('''
name: myapp
flutpak:
  output: flatpak/custom
  pub:
    locks:
      - pubspec.lock
''');
      final cfg = FlatpakGenConfig.load('flutpak.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak/custom');
    });

    test('reads from flutpak.yaml when no pubspec section', () {
      File('${tmpDir.path}/pubspec.yaml')
          .writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      File('${tmpDir.path}/flutpak.yaml').writeAsStringSync('''
output: flatpak/gen
pub:
  locks:
    - pubspec.lock
''');
      final cfg = FlatpakGenConfig.load('flutpak.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak/gen');
    });

    test('throws when both pubspec.yaml section and flutpak.yaml exist', () {
      File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('''
name: myapp
flutpak:
  output: flatpak/a
''');
      File('${tmpDir.path}/flutpak.yaml')
          .writeAsStringSync('output: flatpak/b\n');
      expect(() => FlatpakGenConfig.load('flutpak.yaml', tmpDir.path),
          throwsStateError);
    });

    test('returns defaults when neither config exists', () {
      File('${tmpDir.path}/pubspec.yaml')
          .writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      final cfg = FlatpakGenConfig.load('flutpak.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak');
      expect(cfg.pubLocks, contains('pubspec.lock'));
    });

    test('does not double subdirectory when configPath includes a subdir', () {
      // Regression: generate_command passes configDir=dirname(absolute(configPath))
      // as workingDir. If load() does p.join(workingDir, configPath) with a
      // relative configPath that already contains the subdir, the path doubles.
      final subDir = Directory('${tmpDir.path}/subdir')..createSync();
      File('${subDir.path}/flutpak.yaml')
          .writeAsStringSync('output: flatpak/gen\n');

      // Симулює generate_command: configPath вже абсолютний, configDir = dirname
      final configPath = p.absolute(p.join(subDir.path, 'flutpak.yaml'));
      final configDir = p.dirname(configPath);
      final cfg = FlatpakGenConfig.load(configPath, configDir);

      expect(cfg.output, 'flatpak/gen');
    });
  });

  group('ManifestConfig.fromYaml', () {
    test('parses build-options env and append-path (kebab-case)', () {
      final cfg = ManifestConfig.fromYaml({
        'app-id': 'io.example.app',
        'runtime-version': '25.08',
        'command': 'app',
        'build-options': {
          'append-path': '/custom/bin',
          'env': {
            'MY_VAR': 'value',
          },
        },
      });
      expect(cfg.appendPath, '/custom/bin');
      expect(cfg.env['MY_VAR'], 'value');
    });

    test('commandInferred is true when command not set', () {
      final cfg =
          ManifestConfig.fromYaml({'app-id': 'io.github.example.myapp'});
      expect(cfg.commandInferred, isTrue);
      expect(cfg.command, 'myapp');
    });

    test('commandInferred is false when command explicitly set', () {
      final cfg = ManifestConfig.fromYaml({
        'app-id': 'io.github.example.myapp',
        'command': 'launcher',
      });
      expect(cfg.commandInferred, isFalse);
      expect(cfg.command, 'launcher');
    });

    test('throws when app-id is missing', () {
      expect(
        () => ManifestConfig.fromYaml({}),
        throwsArgumentError,
      );
    });

    test('finishArgs defaults to empty list when not specified', () {
      final cfg = ManifestConfig.fromYaml({'app-id': 'io.example.app'});
      expect(cfg.finishArgs, isEmpty);
    });

    test('parses finish-args list from yaml', () {
      final cfg = ManifestConfig.fromYaml({
        'app-id': 'io.example.app',
        'finish-args': [
          '--filesystem=xdg-documents',
          '--share=network',
        ],
      });
      expect(cfg.finishArgs,
          containsAll(['--filesystem=xdg-documents', '--share=network']));
    });
  });
}
