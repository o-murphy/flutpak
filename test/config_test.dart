import 'dart:io';
import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakGenConfig.fromYaml', () {
    test('parses full config', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'output': 'flatpak/generated-sources.json',
        'pub': {
          'locks': ['pubspec.lock', 'packages/a7p/pubspec.lock'],
        },
        'flutter': {
          'sdk': '/home/user/flutter',
        },
        'patch_path': 'flatpak/patches/flutter/shared.sh.patch',
      });

      expect(cfg.output, 'flatpak/generated-sources.json');
      expect(cfg.pubLocks, ['pubspec.lock', 'packages/a7p/pubspec.lock']);
      expect(cfg.flutterSdk, '/home/user/flutter');
      expect(cfg.patchPath, 'flatpak/patches/flutter/shared.sh.patch');
    });

    test('defaults output when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.output, 'flatpak/generated-sources.json');
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
      tmpDir = Directory.systemTemp.createTempSync('flatpak_gen_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('reads flatpak_gen: section from pubspec.yaml', () {
      File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('''
name: myapp
flatpak_gen:
  output: flatpak/custom-sources.json
  pub:
    locks:
      - pubspec.lock
''');
      final cfg = FlatpakGenConfig.load('flatpak_gen.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak/custom-sources.json');
    });

    test('reads from flatpak_gen.yaml when no pubspec section', () {
      File('${tmpDir.path}/pubspec.yaml')
          .writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      File('${tmpDir.path}/flatpak_gen.yaml').writeAsStringSync('''
output: flatpak/gen-sources.json
pub:
  locks:
    - pubspec.lock
''');
      final cfg = FlatpakGenConfig.load('flatpak_gen.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak/gen-sources.json');
    });

    test('throws when both pubspec.yaml section and flatpak_gen.yaml exist',
        () {
      File('${tmpDir.path}/pubspec.yaml').writeAsStringSync('''
name: myapp
flatpak_gen:
  output: flatpak/a.json
''');
      File('${tmpDir.path}/flatpak_gen.yaml')
          .writeAsStringSync('output: flatpak/b.json\n');
      expect(
          () => FlatpakGenConfig.load('flatpak_gen.yaml', tmpDir.path),
          throwsStateError);
    });

    test('returns defaults when neither config exists', () {
      File('${tmpDir.path}/pubspec.yaml')
          .writeAsStringSync('name: myapp\nversion: 1.0.0\n');
      final cfg = FlatpakGenConfig.load('flatpak_gen.yaml', tmpDir.path);
      expect(cfg.output, 'flatpak/generated-sources.json');
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

  group('ManifestConfig.fromYaml', () {
    test('parses icons and screenshots', () {
      final cfg = ManifestConfig.fromYaml({
        'app_id': 'io.github.example.app',
        'runtime_version': '25.08',
        'command': 'app',
        'icons': [
          {'size': '512x512', 'path': 'assets/icon_512x512.png'},
        ],
        'screenshots': [
          {'path': 'docs/screenshots/home.png'},
          {'path': 'docs/screenshots/settings.png', 'default': true},
        ],
      });
      expect(cfg.icons, hasLength(1));
      expect(cfg.icons.first.size, '512x512');
      expect(cfg.screenshots, hasLength(2));
      expect(cfg.screenshots.last.default_, true);
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
