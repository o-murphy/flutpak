import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:flutpak/src/commands/generate_command.dart';
import 'package:flutpak/src/config.dart';

final _projectRoot = Directory.current.absolute.path;
final _templatePath =
    p.join(_projectRoot, 'test', 'fixtures', 'template_manifest.yml');

String _template() => File(_templatePath).readAsStringSync();

ManifestConfig _cfg({Map<String, dynamic> extra = const {}}) =>
    ManifestConfig.fromYaml({'app-id': 'org.example.App', ...extra});

Map _appModule(String yaml) {
  final tree = loadYaml(yaml) as Map;
  final modules = tree['modules'] as List;
  return modules.firstWhere((m) => m is Map && m['name'] == 'App') as Map;
}

void main() {
  group('injectGeneratedContent', () {
    test('sets tag and commit on git source', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        tag: 'v1.2.3',
        commit: 'deadbeef',
      );
      final src = (_appModule(result)['sources'] as List)
          .firstWhere((s) => s is Map && s['type'] == 'git') as Map;
      expect(src['tag'], 'v1.2.3');
      expect(src['commit'], 'deadbeef');
    });

    test('appends generated-sources.json to app module sources', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        tag: null,
        commit: null,
      );
      final sources = (_appModule(result)['sources'] as List);
      expect(sources.last, 'generated-sources.json');
    });

    test('appends cargo-sources.json after generated-sources.json', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupPath: '/var/lib/rustup',
        tag: null,
        commit: null,
      );
      final sources = (_appModule(result)['sources'] as List);
      expect(sources[sources.length - 2], 'generated-sources.json');
      expect(sources.last, 'cargo-sources.json');
    });

    test('injects CARGO_HOME and RUSTUP_HOME into build-options.env', () {
      const rustupPath = '/var/lib/rustup';
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupPath: rustupPath,
        tag: null,
        commit: null,
      );
      final env = (_appModule(result)['build-options'] as Map)['env'] as Map;
      expect(env['CARGO_HOME'], '/run/build/App/cargo');
      expect(env['RUSTUP_HOME'], rustupPath);
    });

    test('sets append-path to rustupPath/bin when not previously set', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupPath: '/var/lib/rustup',
        tag: null,
        commit: null,
      );
      final buildOpts = _appModule(result)['build-options'] as Map;
      expect(buildOpts['append-path'], '/var/lib/rustup/bin');
    });

    test('appends to existing append-path', () {
      const templateWithPath = '''
app-id: org.example.App
runtime: org.freedesktop.Platform
runtime-version: '25.08'
sdk: org.freedesktop.Sdk
command: App
modules:
  - name: App
    buildsystem: simple
    build-commands: []
    build-options:
      append-path: /app/bin
    sources:
      - type: git
        url: https://github.com/example/App.git
''';
      final result = injectGeneratedContent(
        content: templateWithPath,
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupPath: '/var/lib/rustup',
        tag: null,
        commit: null,
      );
      final buildOpts = _appModule(result)['build-options'] as Map;
      expect(buildOpts['append-path'], '/app/bin:/var/lib/rustup/bin');
    });

    test('preserves existing env vars when merging build-options', () {
      const templateWithEnv = '''
app-id: org.example.App
runtime: org.freedesktop.Platform
runtime-version: '25.08'
sdk: org.freedesktop.Sdk
command: App
modules:
  - name: App
    buildsystem: simple
    build-commands: []
    build-options:
      env:
        MY_VAR: hello
    sources:
      - type: git
        url: https://github.com/example/App.git
''';
      final result = injectGeneratedContent(
        content: templateWithEnv,
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupPath: '/var/lib/rustup',
        tag: null,
        commit: null,
      );
      final env = (_appModule(result)['build-options'] as Map)['env'] as Map;
      expect(env['MY_VAR'], 'hello');
      expect(env['CARGO_HOME'], '/run/build/App/cargo');
    });

    test('inserts rustup module before app module', () {
      final rustupMod = <String, dynamic>{
        'name': 'rustup',
        'buildsystem': 'simple',
        'build-commands': ['./rustup-init -y'],
        'sources': <dynamic>[],
      };
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        cargoSourcesPath: '/out/cargo-sources.json',
        rustupModule: rustupMod,
        rustupPath: '/var/lib/rustup',
        tag: null,
        commit: null,
      );
      final modules = (loadYaml(result) as Map)['modules'] as List;
      expect(modules[0]['name'], 'rustup');
      expect(modules[1]['name'], 'App');
    });

    test('no build-options changes when cargoSourcesPath is null', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        tag: null,
        commit: null,
      );
      expect(_appModule(result).containsKey('build-options'), isFalse);
    });

    test('no rustup module inserted when rustupModule is null', () {
      final result = injectGeneratedContent(
        content: _template(),
        manifestCfg: _cfg(),
        extraModules: [],
        sourcesPath: '/out/generated-sources.json',
        tag: null,
        commit: null,
      );
      final modules = (loadYaml(result) as Map)['modules'] as List;
      expect(modules, hasLength(1));
      expect(modules[0]['name'], 'App');
    });
  });

  group('buildLockPaths', () {
    test('includes extraPubspecPaths in allPubLockPaths', () {
      final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
        effectiveLocks: ['/app/pubspec.lock'],
        extraPubspecPaths: ['/tmp/cargokit/build_tool/pubspec.lock'],
        cargoLockPaths: [],
        rustLocks: [],
        baseDir: '/app',
      );
      expect(
          allPubLockPaths,
          containsAll(
              ['/app/pubspec.lock', '/tmp/cargokit/build_tool/pubspec.lock']));
    });

    test('allPubLockPaths is just effectiveLocks when extraPubspecPaths empty',
        () {
      final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
        effectiveLocks: ['/app/pubspec.lock'],
        extraPubspecPaths: [],
        cargoLockPaths: [],
        rustLocks: [],
        baseDir: '/app',
      );
      expect(allPubLockPaths, ['/app/pubspec.lock']);
    });

    test('merges cargoLockPaths and rustLocks into allCargoLockPaths', () {
      final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
        effectiveLocks: [],
        extraPubspecPaths: [],
        cargoLockPaths: ['/tmp/registry/Cargo.lock'],
        rustLocks: ['rust/Cargo.lock'],
        baseDir: '/app',
      );
      expect(allCargoLockPaths, hasLength(2));
      expect(allCargoLockPaths[0], '/tmp/registry/Cargo.lock');
      expect(allCargoLockPaths[1], endsWith('rust/Cargo.lock'));
    });

    test('rustLocks relative path is resolved against baseDir', () {
      final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
        effectiveLocks: [],
        extraPubspecPaths: [],
        cargoLockPaths: [],
        rustLocks: ['rust/Cargo.lock'],
        baseDir: '/app',
      );
      expect(allCargoLockPaths.first, p.join('/app', 'rust/Cargo.lock'));
    });

    test('rustLocks absolute path is kept as-is', () {
      final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
        effectiveLocks: [],
        extraPubspecPaths: [],
        cargoLockPaths: [],
        rustLocks: ['/absolute/Cargo.lock'],
        baseDir: '/app',
      );
      expect(allCargoLockPaths.first, '/absolute/Cargo.lock');
    });
  });
}
