import 'dart:io';
import 'package:flutpak/flutpak.dart';
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
        },
        'patch_path': 'flatpak/patches/flutter/shared.sh.patch',
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
      final cfg = FlatpakGenConfig.fromYaml({
        'pub': {
          'locks': [
            'pubspec.lock',
            r'$FLUTTER_ROOT/packages/flutter_tools/pubspec.lock',
          ],
        },
      });
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
            'dest_subpath': 'linux',
          },
        ],
      });
      expect(cfg.patches, hasLength(1));
      expect(cfg.patches.first.package, 'objectbox_flutter_libs');
      expect(cfg.patches.first.path, 'flatpak/patches/objectbox.patch');
      expect(cfg.patches.first.destSubpath, 'linux');
    });

    test('parses manifest config', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'manifest': {
          'app_id': 'io.github.example.myapp',
          'runtime_version': '25.08',
          'command': 'myapp',
          'finish_args': ['--share=ipc', '--socket=wayland'],
          'sdk_extensions': ['org.freedesktop.Sdk.Extension.llvm20'],
        },
      });
      expect(cfg.manifest, isNotNull);
      expect(cfg.manifest!.appId, 'io.github.example.myapp');
      expect(cfg.manifest!.runtimeVersion, '25.08');
      expect(cfg.manifest!.command, 'myapp');
      expect(cfg.manifest!.finishArgs, contains('--share=ipc'));
      expect(cfg.manifest!.sdkExtensions,
          contains('org.freedesktop.Sdk.Extension.llvm20'));
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

    test('throws when both pubspec.yaml section and flutpak.yaml exist',
        () {
      File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('''
name: myapp
flutpak:
  output: flatpak/a
''');
      File('${tmpDir.path}/flutpak.yaml')
          .writeAsStringSync('output: flatpak/b\n');
      expect(
          () => FlatpakGenConfig.load('flutpak.yaml', tmpDir.path),
          throwsStateError);
    });

    test('returns defaults when neither config exists', () {
      File('${tmpDir.path}/pubspec.yaml')
          .writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      final cfg = FlatpakGenConfig.load('flutpak.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak');
      expect(cfg.pubLocks, contains('pubspec.lock'));
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
  });

  group('DesktopConfig.fromYaml', () {
    test('parses all fields including comment and startup_wm_class', () {
      final cfg = DesktopConfig.fromYaml({
        'name': 'My App',
        'comment': 'A great app',
        'startup_wm_class': 'myapp',
        'categories': ['Utility', 'Science'],
      });
      expect(cfg.name, 'My App');
      expect(cfg.comment, 'A great app');
      expect(cfg.startupWmClass, 'myapp');
      expect(cfg.categories, ['Utility', 'Science']);
    });

    test('all fields are optional', () {
      final cfg = DesktopConfig.fromYaml({});
      expect(cfg.name, isNull);
      expect(cfg.comment, isNull);
      expect(cfg.startupWmClass, isNull);
      expect(cfg.categories, isEmpty);
    });
  });

  group('MetainfoConfig.fromYaml', () {
    test('defaults metadata_license and project_license to MIT', () {
      final cfg = MetainfoConfig.fromYaml({'name': 'App', 'summary': 'x'});
      expect(cfg.metadataLicense, 'MIT');
      expect(cfg.projectLicense, 'MIT');
    });

    test('parses custom project_license', () {
      final cfg = MetainfoConfig.fromYaml({
        'name': 'App',
        'summary': 'x',
        'metadata_license': 'MIT',
        'project_license': 'GPL-3.0-only',
      });
      expect(cfg.metadataLicense, 'MIT');
      expect(cfg.projectLicense, 'GPL-3.0-only');
    });

    test('parses supports list', () {
      final cfg = MetainfoConfig.fromYaml({
        'name': 'App',
        'summary': 'x',
        'supports': ['pointing', 'keyboard', 'touch'],
      });
      expect(cfg.supports, ['pointing', 'keyboard', 'touch']);
    });

    test('parses content_rating_attributes map', () {
      final cfg = MetainfoConfig.fromYaml({
        'name': 'App',
        'summary': 'x',
        'content_rating_attributes': {'violence-realistic': 'none'},
      });
      expect(cfg.contentRatingAttributes, {'violence-realistic': 'none'});
    });

    test('defaults supports and content_rating_attributes to empty', () {
      final cfg = MetainfoConfig.fromYaml({'name': 'App', 'summary': 'x'});
      expect(cfg.supports, isEmpty);
      expect(cfg.contentRatingAttributes, isEmpty);
    });
  });

  group('ManifestConfig.fromYaml', () {
    test('parses icons', () {
      final cfg = ManifestConfig.fromYaml({
        'app_id': 'io.github.example.app',
        'runtime_version': '25.08',
        'command': 'app',
        'icons': [
          {'size': '512x512', 'path': 'assets/icon_512x512.png'},
        ],
      });
      expect(cfg.icons, hasLength(1));
      expect(cfg.icons.first.size, '512x512');
    });

    test('parses metainfo screenshots', () {
      final cfg = ManifestConfig.fromYaml({
        'app_id': 'io.github.example.app',
        'runtime_version': '25.08',
        'command': 'app',
        'metainfo': {
          'name': 'My App',
          'summary': 'A great app',
          'screenshots': [
            {'path': 'docs/screenshots/home.png'},
            {'path': 'docs/screenshots/settings.png', 'default': true},
          ],
        },
      });
      expect(cfg.metainfo!.screenshots, hasLength(2));
      expect(cfg.metainfo!.screenshots.last.default_, true);
    });

    test('parses build_options env and append_path', () {
      final cfg = ManifestConfig.fromYaml({
        'app_id': 'io.example.app',
        'runtime_version': '25.08',
        'command': 'app',
        'build_options': {
          'append_path': '/custom/bin',
          'env': {
            'MY_VAR': 'value',
          },
        },
      });
      expect(cfg.appendPath, '/custom/bin');
      expect(cfg.env['MY_VAR'], 'value');
    });

    test('parses metainfo config', () {
      final cfg = ManifestConfig.fromYaml({
        'app_id': 'io.example.app',
        'runtime_version': '25.08',
        'command': 'app',
        'metainfo': {
          'path': 'flatpak/io.example.app.metainfo.xml',
          'repo_slug': 'owner/repo',
        },
      });
      expect(cfg.metainfo!.path, 'flatpak/io.example.app.metainfo.xml');
      expect(cfg.metainfo!.repoSlug, 'owner/repo');
    });
  });
}
