import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

ManifestConfig _baseConfig({
  String appId = 'io.github.example.myapp',
  String? command,
  List<String> sdkExtensions = const [],
}) =>
    ManifestConfig(
      appId: appId,
      runtimeVersion: '25.08',
      sdkExtensions: sdkExtensions,
      command: command ?? appId.split('.').last,
      commandInferred: command == null,
    );


ManifestGenerator _generator({
  ManifestConfig? cfg,
  String? resolvedRepoUrl,
  bool hasFlutter = true,
  String outputRelDir = 'flatpak',
  String metainfoPath =
      'app/share/metainfo/io.github.example.myapp.metainfo.xml',
  String desktopEntryPath =
      'app/share/applications/io.github.example.myapp.desktop',
  List<IconEntry> icons = const [],
}) =>
    ManifestGenerator(
      cfg: cfg ?? _baseConfig(),
      generatedSourcesPath: 'flatpak/generated-sources.json',
      outputRelDir: outputRelDir,
      resolvedRepoUrl: resolvedRepoUrl,
      hasFlutter: hasFlutter,
      metainfoPath: metainfoPath,
      desktopEntryPath: desktopEntryPath,
      icons: icons,
    );

void main() {
  group('ManifestGenerator.generate', () {
    test('includes app-id, runtime, sdk, command', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(yaml, contains('app-id: io.github.example.myapp'));
      expect(yaml, contains('runtime: org.freedesktop.Platform'));
      expect(yaml, contains("runtime-version: '25.08'"));
      expect(yaml, contains('sdk: org.freedesktop.Sdk'));
      expect(yaml, contains('command: myapp'));
    });

    test('always includes default finish-args', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(yaml, contains('finish-args:'));
      expect(yaml, contains('- --share=ipc'));
      expect(yaml, contains('- --socket=fallback-x11'));
      expect(yaml, contains('- --socket=wayland'));
      expect(yaml, contains('- --device=dri'));
    });

    test('includes sdk-extensions when provided', () {
      final yaml = _generator(
        cfg: _baseConfig(
            command: 'myapp',
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
      ).generate();

      expect(yaml, contains('sdk-extensions:'));
      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm20'));
    });

    test('auto-adds llvm path to append-path when llvm extension present', () {
      final yaml = _generator(
        cfg: _baseConfig(
            command: 'myapp',
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
      ).generate();

      expect(yaml, contains('/usr/lib/sdk/llvm20/bin'));
      expect(yaml, contains('/run/build/myapp/flutter/bin'));
      expect(yaml, contains('prepend-ld-library-path: /usr/lib/sdk/llvm20/lib'));
    });

    test('does not include tag or commit in template (set by generate via yaml_edit)', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        resolvedRepoUrl: 'https://github.com/example/app.git',
      ).generate();

      expect(yaml, isNot(contains('tag:')));
      expect(yaml, isNot(contains('commit:')));
    });

    test('includes repo url in git source when provided via resolvedRepoUrl', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        resolvedRepoUrl: 'https://github.com/example/app.git',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/app.git'));
    });

    test('resolvedRepoUrl is used when provided', () {
      final yaml = _generator(
        resolvedRepoUrl: 'https://github.com/example/resolved.git',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/resolved.git'));
    });

    test('omits url when resolvedRepoUrl is null', () {
      final yaml = _generator().generate();

      expect(yaml, isNot(contains('url:')));
    });

    test('does not include generated-sources.json (injected at generate time)', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      // generated-sources.json may appear in the header comment but not as a source entry
      expect(yaml, isNot(contains('- generated-sources.json')));
    });

    test('does not include patch or extra sources (injected at generate time)', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(yaml, isNot(contains('type: patch')));
      expect(yaml, isNot(contains('type: archive')));
    });

    test('header contains template guidance comments', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(yaml, contains('editable TEMPLATE manifest'));
      expect(yaml, contains('SAFE TO EDIT'));
      expect(yaml, contains('AUTO-INJECTED'));
    });

    test('includes Flutter cache stamp copy commands when hasFlutter is true',
        () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('engine-dart-sdk.stamp'));
      expect(yaml, contains('material_fonts.stamp'));
      expect(yaml, contains('setup-flutter.sh'));
      expect(yaml, contains('flutter build linux --release --no-pub'));
    });

    test('omits Flutter build commands when hasFlutter is false', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('engine-dart-sdk.stamp')));
      expect(yaml, isNot(contains('setup-flutter.sh')));
      expect(yaml, isNot(contains('flutter build linux')));
      expect(yaml, contains('# TODO: add your build commands here'));
    });

    test('pure-Dart build omits flutter/bin from append-path', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('/run/build/myapp/flutter/bin')));
    });

    test('includes wrapper install command when hasFlutter is true', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        outputRelDir: 'flatpak',
        hasFlutter: true,
      ).generate();

      expect(yaml,
          contains('install -Dm755 flatpak/myapp-wrapper.sh /app/bin/myapp'));
    });

    test('includes arch-specific BUNDLE_PATH env vars when hasFlutter', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('x86_64:'));
      expect(yaml, contains('aarch64:'));
      expect(yaml, contains('build/linux/x64/release/bundle'));
      expect(yaml, contains('build/linux/arm64/release/bundle'));
    });

    test('omits arch BUNDLE_PATH env when hasFlutter is false', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('build/linux/x64/release/bundle')));
      expect(yaml, isNot(contains('build/linux/arm64/release/bundle')));
    });

    test('app module name is last segment of app-id', () {
      final yaml = _generator(
        cfg: _baseConfig(appId: 'io.github.example.myapp', command: 'myapp'),
      ).generate();

      expect(yaml, contains('name: myapp'));
    });

    test('uses default 256x256 icon install command when icons empty', () {
      // When icons list is empty, caller should pass the effective icons.
      final effectiveIcons = [
        const IconEntry(
          size: '256x256',
          path: 'app/share/icons/hicolor/256x256/apps/io.github.example.myapp.png',
        ),
      ];
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        icons: effectiveIcons,
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
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        icons: [
          const IconEntry(
              size: '256x256',
              path: 'app/share/icons/hicolor/256x256/apps/myapp.png'),
          const IconEntry(size: 'scalable', path: 'assets/icon.svg'),
        ],
      ).generate();

      expect(
        yaml,
        contains(
          'install -Dm644 assets/icon.svg '
          '/app/share/icons/hicolor/scalable/apps/io.github.example.myapp.svg',
        ),
      );
    });

    test('includes metainfo install command using provided metainfoPath', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        metainfoPath:
            'app/share/metainfo/io.github.example.myapp.metainfo.xml',
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

    test('includes desktop entry install command using provided desktopEntryPath',
        () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        desktopEntryPath:
            'app/share/applications/io.github.example.myapp.desktop',
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
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(
        yaml,
        startsWith(
            '# Generated by flutpak — https://github.com/o-murphy/flutpak\n'),
      );
    });
  });
}
