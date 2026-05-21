import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

ManifestConfig _baseConfig({
  String appId = 'io.github.example.myapp',
  String? command,
  List<String> sdkExtensions = const [],
  List<String> finishArgs = const [],
  String? repoUrl,
  List<IconEntry> icons = const [],
}) =>
    ManifestConfig(
      appId: appId,
      runtimeVersion: '25.08',
      sdkExtensions: sdkExtensions,
      command: command ?? appId.split('.').last,
      commandInferred: command == null,
      finishArgs: finishArgs,
      repoUrl: repoUrl,
      icons: icons,
    );

void main() {
  group('ManifestGenerator.generate', () {
    test('includes app-id, runtime, sdk, command', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('app-id: io.github.example.myapp'));
      expect(yaml, contains('runtime: org.freedesktop.Platform'));
      expect(yaml, contains("runtime-version: '25.08'"));
      expect(yaml, contains('sdk: org.freedesktop.Sdk'));
      expect(yaml, contains('command: myapp'));
    });

    test('includes finish-args when provided', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            command: 'myapp',
            finishArgs: ['--share=ipc', '--socket=wayland']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('finish-args:'));
      expect(yaml, contains('- --share=ipc'));
      expect(yaml, contains('- --socket=wayland'));
    });

    test('omits finish-args when empty', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, isNot(contains('finish-args:')));
    });

    test('includes sdk-extensions when provided', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            command: 'myapp',
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('sdk-extensions:'));
      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm20'));
    });

    test('auto-adds llvm path to append-path when llvm extension present', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            command: 'myapp',
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('/usr/lib/sdk/llvm20/bin'));
      expect(yaml, contains('/run/build/myapp/flutter/bin'));
      expect(yaml, contains('prepend-ld-library-path: /usr/lib/sdk/llvm20/lib'));
    });

    test('includes __FLATPAK_TAG__ and __FLATPAK_COMMIT__ placeholders', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            command: 'myapp',
            repoUrl: 'https://github.com/example/app.git'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('tag: __FLATPAK_TAG__'));
      expect(yaml, contains('commit: __FLATPAK_COMMIT__'));
    });

    test('includes repo url in git source when provided via cfg', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            command: 'myapp',
            repoUrl: 'https://github.com/example/app.git'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/app.git'));
    });

    test('resolvedRepoUrl overrides cfg.repoUrl', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(repoUrl: 'https://github.com/example/old.git'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        resolvedRepoUrl: 'https://github.com/example/resolved.git',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/resolved.git'));
      expect(yaml, isNot(contains('url: https://github.com/example/old.git')));
    });

    test('resolvedRepoUrl is used when cfg.repoUrl is null', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        resolvedRepoUrl: 'https://github.com/example/auto.git',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/auto.git'));
    });

    test('omits url when both cfg.repoUrl and resolvedRepoUrl are null', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, isNot(contains('url:')));
    });

    test('includes generated-sources.json reference', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('- generated-sources.json'));
    });

    test('includes patch sources with correct dest', () {
      final patches = [
        PatchEntry(
          package: 'objectbox_flutter_libs',
          version: '5.3.1',
          path: 'flatpak/patches/objectbox.patch',
        ),
      ];
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        patchEntries: patches,
      ).generate();

      expect(yaml, contains('type: patch'));
      // Path is made relative to manifest dir (flatpak/), so flatpak/ prefix is stripped.
      expect(yaml, contains('path: patches/objectbox.patch'));
      expect(yaml,
          contains('.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1'));
    });

    test('includes Flutter cache stamp copy commands when hasFlutter is true',
        () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('engine-dart-sdk.stamp'));
      expect(yaml, contains('material_fonts.stamp'));
      expect(yaml, contains('setup-flutter.sh'));
      expect(yaml, contains('flutter build linux --release --no-pub'));
    });

    test('omits Flutter build commands when hasFlutter is false', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('engine-dart-sdk.stamp')));
      expect(yaml, isNot(contains('setup-flutter.sh')));
      expect(yaml, isNot(contains('flutter build linux')));
      expect(yaml, contains('# TODO: add your build commands here'));
    });

    test('pure-Dart build omits flutter/bin from append-path', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('/run/build/myapp/flutter/bin')));
    });

    test('includes wrapper install command when hasFlutter is true', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        outputRelDir: 'flatpak',
        hasFlutter: true,
      ).generate();

      expect(yaml,
          contains('install -Dm755 flatpak/myapp-wrapper.sh /app/bin/myapp'));
    });

    test('includes arch-specific BUNDLE_PATH env vars when hasFlutter', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('x86_64:'));
      expect(yaml, contains('aarch64:'));
      expect(yaml, contains('build/linux/x64/release/bundle'));
      expect(yaml, contains('build/linux/arm64/release/bundle'));
    });

    test('omits arch BUNDLE_PATH env when hasFlutter is false', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('build/linux/x64/release/bundle')));
      expect(yaml, isNot(contains('build/linux/arm64/release/bundle')));
    });

    test('app module name is last segment of app-id', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(appId: 'io.github.example.myapp', command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('name: myapp'));
    });

    test('uses default 256x256 icon install command when icons empty', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(
        yaml,
        contains(
          'install -Dm644 '
          'app/share/icons/hicolor/256x256/apps/io.github.example.myapp.png '
          '/app/share/icons/hicolor/256x256/apps/io.github.example.myapp.png',
        ),
      );
    });

    test('uses scalable icon with svg extension when size is scalable', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
          command: 'myapp',
          icons: [
            const IconEntry(
                size: '256x256',
                path: 'app/share/icons/hicolor/256x256/apps/myapp.png'),
            const IconEntry(size: 'scalable', path: 'assets/icon.svg'),
          ],
        ),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(
        yaml,
        contains(
          'install -Dm644 assets/icon.svg '
          '/app/share/icons/hicolor/scalable/apps/io.github.example.myapp.svg',
        ),
      );
    });

    test('includes metainfo install command using effectiveMetainfoPath', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(
        yaml,
        contains(
          'install -Dm644 '
          'app/share/metainfo/io.github.example.myapp.metainfo.xml '
          '/app/share/metainfo/io.github.example.myapp.metainfo.xml',
        ),
      );
    });

    test('includes desktop entry install command using effectiveDesktopEntryPath',
        () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(
        yaml,
        contains(
          'install -Dm644 '
          'app/share/applications/io.github.example.myapp.desktop '
          '/app/share/applications/io.github.example.myapp.desktop',
        ),
      );
    });

    test('header comment is present', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(command: 'myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(
        yaml,
        startsWith(
            '# Generated by flutpak — https://github.com/o-murphy/flutpak\n'),
      );
    });
  });
}
