import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

ManifestConfig _baseConfig({
  String appId = 'io.github.example.myapp',
  String command = 'myapp',
  List<String> sdkExtensions = const [],
  List<String> finishArgs = const [],
  String? repoUrl,
}) =>
    ManifestConfig(
      appId: appId,
      runtimeVersion: '25.08',
      sdkExtensions: sdkExtensions,
      command: command,
      finishArgs: finishArgs,
      repoUrl: repoUrl,
    );

void main() {
  group('ManifestGenerator.generate', () {
    test('includes app-id, runtime, sdk, command', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
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
        cfg: _baseConfig(finishArgs: ['--share=ipc', '--socket=wayland']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('finish-args:'));
      expect(yaml, contains('- --share=ipc'));
      expect(yaml, contains('- --socket=wayland'));
    });

    test('omits finish-args when empty', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, isNot(contains('finish-args:')));
    });

    test('includes sdk-extensions when provided', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('sdk-extensions:'));
      expect(yaml, contains('org.freedesktop.Sdk.Extension.llvm20'));
    });

    test('auto-adds llvm path to append-path when llvm extension present', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(
            sdkExtensions: ['org.freedesktop.Sdk.Extension.llvm20']),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('/usr/lib/sdk/llvm20/bin'));
      expect(yaml, contains('/run/build/myapp/flutter/bin'));
      expect(yaml, contains('prepend-ld-library-path: /usr/lib/sdk/llvm20/lib'));
    });

    test('includes __FLATPAK_TAG__ and __FLATPAK_COMMIT__ placeholders', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(repoUrl: 'https://github.com/example/app.git'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('tag: __FLATPAK_TAG__'));
      expect(yaml, contains('commit: __FLATPAK_COMMIT__'));
    });

    test('includes repo url in git source when provided', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(repoUrl: 'https://github.com/example/app.git'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('url: https://github.com/example/app.git'));
    });

    test('includes generated-sources.json reference', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
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
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
        patchEntries: patches,
      ).generate();

      expect(yaml, contains('type: patch'));
      // Path is made relative to manifest dir (flatpak/), so flatpak/ prefix is stripped.
      expect(yaml, contains('path: patches/objectbox.patch'));
      expect(yaml,
          contains('.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1'));
    });

    test('includes Flutter cache stamp copy commands', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('engine-dart-sdk.stamp'));
      expect(yaml, contains('material_fonts.stamp'));
      expect(yaml, contains('setup-flutter.sh'));
      expect(yaml, contains('flutter build linux --release --no-pub'));
    });

    test('includes arch-specific BUNDLE_PATH env vars', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('x86_64:'));
      expect(yaml, contains('aarch64:'));
      expect(yaml, contains('build/linux/x64/release/bundle'));
      expect(yaml, contains('build/linux/arm64/release/bundle'));
    });

    test('app module name is last segment of app-id', () {
      final yaml = ManifestGenerator(
        cfg: _baseConfig(appId: 'io.github.example.myapp'),
        generatedSourcesPath: 'flatpak/generated-sources.json',
      ).generate();

      expect(yaml, contains('name: myapp'));
    });
  });
}
