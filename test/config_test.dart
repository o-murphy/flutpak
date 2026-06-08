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
          'sdk': '/home/user/flutter',
          'patch': 'flatpak/patches/flutter/shared.sh.patch',
        },
      });

      expect(cfg.output, 'flatpak');
      expect(cfg.pubLocks, ['pubspec.lock', 'packages/a7p/pubspec.lock']);
      expect(cfg.flutterSdk, '/home/user/flutter');
      expect(cfg.patchPath, 'flatpak/patches/flutter/shared.sh.patch');
    });

    test('defaults output when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.output, 'flatpak');
    });

    test('defaults pub locks to pubspec.lock when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.pubLocks, contains('pubspec.lock'));
    });

    test('resolves \$ENV variables in paths', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {'sdk': '\$HOME/flutter'},
      });
      expect(cfg.flutterSdk, isNotNull);
      expect(cfg.flutterSdk, isNot(isEmpty));
    });

    test('flutterSdk is null when \$VAR cannot be resolved', () {
      // Use a variable name that is guaranteed not to be set.
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {'sdk': r'$FLUTPAK_TEST_UNSET_VAR_XYZ/flutter'},
      });
      expect(cfg.flutterSdk, isNull);
    });

    test('pubLocks preserves unresolvable \$VAR paths for late resolution', () {
      // Paths with unresolvable \$VAR are kept so effectivePubLocks() can
      // substitute them later using the effective SDK path.
      final cfg = FlatpakGenConfig.fromYaml({
        'pub': {
          'locks': [
            'pubspec.lock',
            r'$FLUTPAK_TEST_UNSET_VAR_XYZ/packages/flutter_tools/pubspec.lock',
          ],
        },
      });
      expect(cfg.pubLocks, hasLength(2));
      expect(cfg.pubLocks.last, contains(r'$FLUTPAK_TEST_UNSET_VAR_XYZ'));
    });

    test('effectivePubLocks substitutes \$FLUTTER_ROOT with sdkPath', () {
      // Bypass fromYaml (which eagerly substitutes $FLUTTER_ROOT from the
      // environment) so the literal placeholder is preserved for the test.
      final cfg = FlatpakGenConfig(
        output: 'flatpak',
        pubLocks: [
          'pubspec.lock',
          r'$FLUTTER_ROOT/packages/flutter_tools/pubspec.lock',
        ],
      );
      final effective = cfg.effectivePubLocks('/home/user/flutter');
      expect(effective, [
        'pubspec.lock',
        '/home/user/flutter/packages/flutter_tools/pubspec.lock',
      ]);
    });

    test('effectivePubLocks returns pubLocks unchanged when sdkPath is null',
        () {
      final cfg = FlatpakGenConfig.fromYaml({
        'pub': {
          'locks': ['pubspec.lock'],
        },
      });
      expect(cfg.effectivePubLocks(null), cfg.pubLocks);
    });

    test('reads flutter patch from flutter.patch key', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {
          'sdk': '/flutter',
          'patch': 'patches/flutter/shared.sh.patch',
        },
      });
      expect(cfg.patchPath, 'patches/flutter/shared.sh.patch');
    });

    test('parses patches list', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'patches': [
          {
            'package': 'objectbox_flutter_libs',
            'path': 'flatpak/patches/objectbox.patch',
            'dest-subpath': 'linux',
          },
        ],
      });
      expect(cfg.patches, hasLength(1));
      expect(cfg.patches.first.package, 'objectbox_flutter_libs');
      expect(cfg.patches.first.path, 'flatpak/patches/objectbox.patch');
      expect(cfg.patches.first.destSubpath, 'linux');
    });

    test('parses manifest config (kebab-case keys)', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'manifest': {
          'app-id': 'io.github.example.myapp',
          'runtime-version': '25.08',
          'command': 'myapp',
          'sdk-extensions': ['org.freedesktop.Sdk.Extension.llvm20'],
        },
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
        'manifest': {'app-id': 'io.example.app'},
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
          'manifest': {'app-id': 'io.example.app'},
        }),
        throwsArgumentError,
      );
    });

    test('icons empty when key absent', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'manifest': {'app-id': 'io.example.app'},
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

  group('PatchEntry', () {
    test('dest with destSubpath appends subpath', () {
      final entry = PatchEntry(
        package: 'objectbox_flutter_libs',
        version: '5.3.1',
        path: 'patches/objectbox.patch',
        destSubpath: 'linux',
      );
      expect(entry.dest('5.3.1'),
          '.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1/linux');
    });

    test('dest without destSubpath returns package root', () {
      final entry = PatchEntry(
        package: 'objectbox_flutter_libs',
        version: '5.3.1',
        path: 'patches/objectbox.patch',
      );
      expect(entry.dest('5.3.1'),
          '.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1');
    });

    group('fromYaml', () {
      test('parses crlf: true', () {
        final entry = PatchEntry.fromYaml({
          'package': 'objectbox_flutter_libs',
          'path': 'patches/objectbox.patch',
          'crlf': true,
        });
        expect(entry.crlf, isTrue);
      });

      test('crlf defaults to false when absent', () {
        final entry = PatchEntry.fromYaml({
          'package': 'foo',
          'path': 'patches/foo.patch',
        });
        expect(entry.crlf, isFalse);
      });

      test('deprecated strip-trailing-cr sets crlf', () {
        final entry = PatchEntry.fromYaml({
          'package': 'objectbox_flutter_libs',
          'path': 'patches/objectbox.patch',
          'strip-trailing-cr': true,
        });
        expect(entry.crlf, isTrue);
      });

      test('crlf takes precedence over strip-trailing-cr', () {
        final entry = PatchEntry.fromYaml({
          'package': 'foo',
          'path': 'patches/foo.patch',
          'crlf': false,
          'strip-trailing-cr': true,
        });
        expect(entry.crlf, isFalse);
      });

      test('parses options list', () {
        final entry = PatchEntry.fromYaml({
          'package': 'foo',
          'path': 'patches/foo.patch',
          'options': ['--ignore-whitespace'],
        });
        expect(entry.options, ['--ignore-whitespace']);
      });

      test('parses use-git: true', () {
        final entry = PatchEntry.fromYaml({
          'package': 'foo',
          'path': 'patches/foo.patch',
          'use-git': true,
        });
        expect(entry.useGit, isTrue);
      });

      test('use-git defaults to false when absent', () {
        final entry = PatchEntry.fromYaml({
          'package': 'foo',
          'path': 'patches/foo.patch',
        });
        expect(entry.useGit, isFalse);
      });
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

  group('FlatpakGenConfig flutter-version-file defaults', () {
    test('defaults to <output>/flutter.version when flutter sdk is configured',
        () {
      final cfg = FlatpakGenConfig.fromYaml({
        'output': 'flatpak',
        'flutter': {'sdk': '/home/user/flutter'},
      });
      expect(cfg.flutterVersionFile, 'flatpak/flutter.version');
    });

    test('explicit flutter-version-file overrides default', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'output': 'flatpak',
        'flutter': {'sdk': '/home/user/flutter'},
        'flutter-version-file': 'custom/my.version',
      });
      expect(cfg.flutterVersionFile, 'custom/my.version');
    });

    test('flutter-version-file is null for pure-Dart projects with no SDK', () {
      if (Platform.environment.containsKey('FLUTTER_ROOT')) return;
      final cfg = FlatpakGenConfig.fromYaml({'output': 'flatpak'});
      expect(cfg.flutterVersionFile, isNull);
    });
  });
}
