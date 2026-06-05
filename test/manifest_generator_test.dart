import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

ManifestConfig _baseConfig({
  String appId = 'io.github.example.myapp',
  String? command,
  List<String> sdkExtensions = const [],
  String runtimeVersion = '25.08',
}) =>
    ManifestConfig(
      appId: appId,
      runtimeVersion: runtimeVersion,
      sdkExtensions: sdkExtensions,
      command: command ?? appId.split('.').last,
      commandInferred: command == null,
    );


ManifestGenerator _generator({
  ManifestConfig? cfg,
  String? resolvedRepoUrl,
  bool hasFlutter = true,
  bool disableSubmodules = false,
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
      disableSubmodules: disableSubmodules,
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

    test('auto-injects llvm20 for Flutter project with runtime 25.08 when no llvm in config', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp', runtimeVersion: '25.08'),
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm20'));
      expect(yaml, contains('/usr/lib/sdk/llvm20/bin'));
      expect(yaml, contains('prepend-ld-library-path: /usr/lib/sdk/llvm20/lib'));
    });

    test('auto-injects llvm19 for Flutter project with runtime 24.08', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp', runtimeVersion: '24.08'),
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm19'));
      expect(yaml, contains('/usr/lib/sdk/llvm19/bin'));
    });

    test('auto-injects llvm20 as fallback for unknown runtime version', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp', runtimeVersion: '99.08'),
        hasFlutter: true,
      ).generate();

      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm20'));
    });

    test('does not auto-inject llvm when llvm already in sdk-extensions', () {
      final yaml = _generator(
        cfg: _baseConfig(
            command: 'myapp',
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
        hasFlutter: true,
      ).generate();

      final count = RegExp('llvm20').allMatches(yaml).length;
      // llvm20 appears in sdk-extensions, append-path, prepend-ld-library-path — not duplicated
      expect(yaml, isNot(contains('- org.freedesktop.Sdk.Extension.llvm20\n'
          '  - org.freedesktop.Sdk.Extension.llvm20')));
      expect(count, lessThan(5));
    });

    test('does not auto-inject llvm for non-Flutter projects', () {
      final yaml = _generator(
        cfg: _baseConfig(command: 'myapp'),
        hasFlutter: false,
      ).generate();

      expect(yaml, isNot(contains('llvm')));
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

    test('wrapper install uses command, not last app-id segment, when they differ', () {
      final yaml = _generator(
        cfg: _baseConfig(appId: 'io.github.example.demo', command: 'demo_app'),
        outputRelDir: 'flatpak',
        hasFlutter: true,
        metainfoPath: 'app/share/metainfo/io.github.example.demo.metainfo.xml',
        desktopEntryPath:
            'app/share/applications/io.github.example.demo.desktop',
      ).generate();

      expect(yaml,
          contains('install -Dm755 flatpak/demo-wrapper.sh /app/bin/demo_app'));
      expect(yaml, isNot(contains('/app/bin/demo\n')));
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

    test('omits disable-submodules by default (matches flatpak-builder default)', () {
      final yaml = _generator(
        resolvedRepoUrl: 'https://github.com/example/app.git',
      ).generate();

      expect(yaml, isNot(contains('disable-submodules')));
    });

    test('emits disable-submodules: true when disableSubmodules is true', () {
      final yaml = _generator(
        resolvedRepoUrl: 'https://github.com/example/app.git',
        disableSubmodules: true,
      ).generate();

      expect(yaml, contains('disable-submodules: true'));
    });

    test('header comment is present', () {
      final yaml = _generator(cfg: _baseConfig(command: 'myapp')).generate();

      expect(
        yaml,
        startsWith(
            '# Generated by flutpak — https://github.com/o-murphy/flutpak\n'),
      );
    });

    // Regression: yaml_edit 2.x crashes when creating new keys inside a map
    // that is an element of a block sequence.  The generate command must
    // replace the whole git source map at once rather than updating individual
    // keys.  This test verifies the template → injection round-trip produces
    // valid YAML containing the injected tag and commit.
    test('tag and commit can be injected into generated template via yaml_edit', () {
      final template = stripTemplateGuidance(
        _generator(
          resolvedRepoUrl: 'https://github.com/example/app.git',
        ).generate(),
      );

      final tree = loadYaml(template);
      final modules = tree['modules'] as List;
      final sources = modules[0]['sources'] as List;
      final gitSrcIdx =
          sources.indexWhere((s) => s is Map && s['type'] == 'git');

      expect(gitSrcIdx, greaterThanOrEqualTo(0));

      final editor = YamlEditor(template);
      final existing =
          Map<String, dynamic>.from(sources[gitSrcIdx] as Map);
      existing['tag'] = 'v1.0.0';
      existing['commit'] = 'abc123def456';
      editor.update(['modules', 0, 'sources', gitSrcIdx], existing);

      final result = editor.toString();
      expect(result, contains('tag: v1.0.0'));
      expect(result, contains('commit: abc123def456'));
      expect(result, contains('url: https://github.com/example/app.git'));
    });
  });

  _patchSourceMapsTests();
  _crlfHelpersTests();
}

// ── buildPatchSourceMaps ─────────────────────────────────────────────────────

void _patchSourceMapsTests() {
  group('buildPatchSourceMaps', () {
    test('emits a single type:patch entry per patch', () {
      final patches = [
        PatchEntry(
          package: 'foo',
          version: '1.0.0',
          path: '/patches/foo.patch',
        ),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps, hasLength(1));
      expect(maps.first['type'], 'patch');
    });

    test('always includes --binary option in every patch entry', () {
      final patches = [
        PatchEntry(
          package: 'foo',
          version: '1.0.0',
          path: '/patches/foo.patch',
        ),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps.first['options'], contains('--binary'));
    });

    test('crlf: true patch gets --binary (no type:shell emitted)', () {
      final patches = [
        PatchEntry(
          package: 'foo',
          version: '1.0.0',
          path: '/patches/foo.patch',
          crlf: true,
        ),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps, hasLength(1));
      expect(maps.first['type'], 'patch');
      expect(maps.first['options'], contains('--binary'));
      expect(maps.any((m) => m['type'] == 'shell'), isFalse);
    });

    test('sets dest when version is provided', () {
      final patches = [
        PatchEntry(
          package: 'bar',
          version: '2.3.4',
          path: '/patches/bar.patch',
        ),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps.first['dest'],
          '.pub-cache/hosted/pub.dev/bar-2.3.4');
    });

    test('omits dest when version is null', () {
      final patches = [
        PatchEntry(package: 'baz', path: '/patches/baz.patch'),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps.first.containsKey('dest'), isFalse);
    });

    test('includes user options appended after --binary', () {
      final patches = [
        PatchEntry(
          package: 'qux',
          version: '1.0.0',
          path: '/patches/qux.patch',
          options: ['--ignore-whitespace'],
        ),
      ];
      final maps = buildPatchSourceMaps(patches, '/patches');

      expect(maps.first['options'], ['--binary', '--ignore-whitespace']);
    });
  });
}

// ── convertPatchToCrlf / patchHasLfLineEndings ───────────────────────────────

void _crlfHelpersTests() {
  group('convertPatchToCrlf', () {
    test('converts LF to CRLF', () {
      const input = 'line1\nline2\nline3\n';
      final result = convertPatchToCrlf(input);
      expect(result, 'line1\r\nline2\r\nline3\r\n');
    });

    test('does not double-convert existing CRLF', () {
      const input = 'line1\r\nline2\r\n';
      final result = convertPatchToCrlf(input);
      expect(result, 'line1\r\nline2\r\n');
    });

    test('handles mixed line endings', () {
      const input = 'line1\r\nline2\nline3\r\n';
      final result = convertPatchToCrlf(input);
      expect(result, 'line1\r\nline2\r\nline3\r\n');
    });
  });

  group('patchHasLfLineEndings', () {
    test('returns true for LF content', () {
      expect(patchHasLfLineEndings('a\nb\n'), isTrue);
    });

    test('returns false for pure CRLF content', () {
      expect(patchHasLfLineEndings('a\r\nb\r\n'), isFalse);
    });

    test('returns true for mixed content', () {
      expect(patchHasLfLineEndings('a\r\nb\n'), isTrue);
    });

    test('returns false for empty string', () {
      expect(patchHasLfLineEndings(''), isFalse);
    });
  });
}

