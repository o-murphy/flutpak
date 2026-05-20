import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
import '../generators/pub_sources.dart';
import '../patches_registry.dart';
import '../utils/download_cache.dart';

/// Orchestrates the full Flatpak build preparation in one command:
///   1. Generates generated-sources.json (pub + Flutter SDK)
///   2. Resolves patch entries (registry + project config)
///   3. Generates the manifest if it doesn't exist, or updates placeholders
class PrepareCommand extends Command<void> {
  @override
  final name = 'prepare';
  @override
  final description =
      'Generate sources, resolve patches, and create/update the Flatpak manifest.\n'
      'On first run: generates the manifest, .desktop, and metainfo from config.\n'
      'On subsequent runs: updates __FLATPAK_TAG__/__FLATPAK_COMMIT__ placeholders.';

  PrepareCommand() {
    argParser
      ..addOption('tag',
          help: 'Git tag to embed in the manifest (e.g. v0.1.14). '
              'If omitted the tag: line is removed from the source entry.')
      ..addOption('commit',
          help: 'Full git commit SHA to embed in the manifest. '
              'Defaults to HEAD if inside a git repo.')
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('config',
          abbr: 'c', help: 'Config file path.', defaultsTo: 'flutpak.yaml')
      ..addFlag('no-sources',
          help: 'Skip source regeneration (manifest update only).')
      ..addFlag('pub-only', help: 'Skip Flutter SDK sources.')
      ..addFlag('flutter-only', help: 'Skip pub sources.')
      ..addFlag('dry-run',
          abbr: 'n',
          help: 'Print what would be done without writing any files.');
  }

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    // configDir is only used to locate the config file itself and load it.
    // All output/asset paths from the config are resolved relative to CWD.
    final configDir = p.dirname(p.absolute(configPath));
    final cfg = FlatpakGenConfig.load(configPath, configDir);

    final tag = argResults!['tag'] as String?;
    final commit = (argResults!['commit'] as String?) ?? _gitHead();
    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];
    final noSources = argResults!['no-sources'] as bool;
    final pubOnly = argResults!['pub-only'] as bool;
    final flutterOnly = argResults!['flutter-only'] as bool;
    final dryRun = argResults!['dry-run'] as bool;

    if (dryRun) {
      _printDryRun(cfg, tag: tag, commit: commit, sdkPath: sdkPath);
      return;
    }

    // cfg.output is resolved relative to CWD so that "output: flatpak" always
    // means ./flatpak/ regardless of where the config file lives.
    final outputDir = p.absolute(cfg.output);
    final sourcesPath = p.join(outputDir, 'generated-sources.json');

    // Lock paths with $FLUTTER_ROOT substituted from the effective SDK path.
    final effectiveLocks = cfg.effectivePubLocks(sdkPath);

    // ── 1. Resolve patch entries ────────────────────────────────────────────
    final patchesDir = p.join(outputDir, 'patches');
    final patchEntries = resolvePatchEntries(
      lockPaths: effectiveLocks,
      patchesDir: patchesDir,
      projectPatches: cfg.patches,
    );
    if (patchEntries.isNotEmpty) {
      stderr.writeln('patches: ${patchEntries.length} entries resolved');
    }

    // ── 2. Generate sources ──────────────────────────────────────────────
    if (!noSources) {
      await _generateSources(
        lockPaths: effectiveLocks,
        outputDir: outputDir,
        sourcesPath: sourcesPath,
        sdkPath: sdkPath,
        patchPath: cfg.patchPath,
        pubOnly: pubOnly,
        flutterOnly: flutterOnly,
      );
    }

    // ── 3. Write flutter version file ────────────────────────────────────
    if (sdkPath != null && cfg.flutterVersionFile != null) {
      _writeFlutterVersionFile(sdkPath, p.absolute(cfg.flutterVersionFile!));
    }

    // ── 4. Create or update manifest ───────────────────────────────────
    final manifestCfg = cfg.manifest;
    if (manifestCfg != null) {
      final manifestPath = p.join(outputDir, '${manifestCfg.appId}.yml');
      final manifestFile = File(manifestPath);

      final manifestCreated = !manifestFile.existsSync();
      if (manifestCreated) {
        _generateManifest(
          manifestCfg: manifestCfg,
          manifestPath: manifestPath,
          generatedSourcesPath: sourcesPath,
          patchEntries: patchEntries,
          outputRelDir: cfg.output,
        );
      }

      // Substitute placeholders for both first-run and subsequent runs.
      if (commit == null) {
        final content = manifestFile.readAsStringSync();
        if (content.contains('__FLATPAK_COMMIT__')) {
          stderr.writeln(
              '⚠  commit hash unknown (not in a git repo and --commit not set);\n'
              '   __FLATPAK_COMMIT__ placeholder will remain in $manifestPath');
        }
      } else {
        _updateManifestPlaceholders(
          manifestFile: manifestFile,
          tag: tag,
          commit: commit,
        );
      }

      stderr.writeln(
          '✓  manifest ${manifestCreated ? 'created' : 'updated'}: $manifestPath');
    } else if (tag != null || commit != null) {
      // No manifest config but we have tag/commit — try to patch any existing
      // manifest that uses the placeholders.
      _patchAnyExistingManifest(
        tag: tag,
        commit: commit,
        flatpakDir: outputDir,
      );
    }

    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('✓  prepare complete  ref=$ref');
  }

  Future<void> _generateSources({
    required List<String> lockPaths,
    required String outputDir,
    required String sourcesPath,
    String? sdkPath,
    String? patchPath,
    required bool pubOnly,
    required bool flutterOnly,
  }) async {
    final allSources = <Map<String, dynamic>>[];
    final cache = LocalDownloadCache();

    try {
      if (!flutterOnly) {
        final pubSources =
            await PubSourcesGenerator(lockFilePaths: lockPaths).generate();
        allSources.addAll(pubSources.map((s) => s.toJson()));
        stderr.writeln('pub: ${pubSources.length} entries');
      }

      if (!pubOnly) {
        if (sdkPath == null) {
          stderr.writeln(
              '⚠  Flutter SDK not found — skipping (set --sdk or \$FLUTTER_ROOT)');
        } else {
          final flutterSources = await FlutterSdkGenerator(
            sdkPath: sdkPath,
            patchPath: patchPath,
            outputDir: outputDir,
            cache: cache,
          ).generate();
          allSources.addAll(flutterSources.map((s) => s.toJson()));
          stderr.writeln('flutter: ${flutterSources.length} entries');
        }
      }
    } finally {
      cache.dispose();
    }

    final json = const JsonEncoder.withIndent('    ').convert(allSources);
    File(sourcesPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    stderr.writeln('✓  ${allSources.length} total sources → $sourcesPath');
  }

  void _generateManifest({
    required ManifestConfig manifestCfg,
    required String manifestPath,
    required String generatedSourcesPath,
    required List<PatchEntry> patchEntries,
    String outputRelDir = 'flatpak',
  }) {
    final generator = ManifestGenerator(
      cfg: manifestCfg,
      generatedSourcesPath: generatedSourcesPath,
      patchEntries: patchEntries,
      outputRelDir: outputRelDir,
    );
    File(manifestPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(generator.generate());
  }

  void _updateManifestPlaceholders({
    required File manifestFile,
    required String? tag,
    required String? commit,
  }) {
    if (commit == null) return;
    final content = patchManifestPlaceholders(
      manifestFile.readAsStringSync(),
      commit: commit,
      tag: tag,
    );
    manifestFile.writeAsStringSync(content);
  }

  void _patchAnyExistingManifest({
    String? tag,
    String? commit,
    required String flatpakDir,
  }) {
    if (commit == null) return;
    final dir = Directory(flatpakDir);
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.yml') && !f.path.endsWith('.yaml')) continue;
      final content = f.readAsStringSync();
      if (!content.contains('__FLATPAK_')) continue;
      f.writeAsStringSync(
        patchManifestPlaceholders(content, commit: commit, tag: tag),
      );
      stderr.writeln('✓  placeholders updated: ${f.path}');
    }
  }

  void _writeFlutterVersionFile(String sdkPath, String outputPath) {
    final versionFile = File(p.join(sdkPath, 'version'));
    if (!versionFile.existsSync()) return;
    final version = versionFile.readAsStringSync().trim();
    File(outputPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '# Generated by flutpak — https://github.com/o-murphy/flutpak\n'
          '$version\n');
    stderr.writeln('✓  flutter.version → $outputPath ($version)');
  }

  void _printDryRun(
    FlatpakGenConfig cfg, {
    String? tag,
    String? commit,
    String? sdkPath,
  }) {
    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('dry-run: prepare  ref=$ref');
    stderr.writeln('');

    final outputDir = p.absolute(cfg.output);
    stderr.writeln(
        '  would write: ${p.join(outputDir, 'generated-sources.json')}');
    for (final lock in cfg.effectivePubLocks(sdkPath)) {
      stderr.writeln('    pub lock: $lock');
    }
    if (sdkPath != null) {
      stderr.writeln('    flutter sdk: $sdkPath');
    } else {
      stderr.writeln('    flutter sdk: (skipped — no sdk path)');
    }

    final manifestCfg = cfg.manifest;
    if (manifestCfg != null) {
      final manifestPath = p.join(outputDir, '${manifestCfg.appId}.yml');
      final manifestExists = File(manifestPath).existsSync();
      stderr.writeln(manifestExists
          ? '  would update placeholders: $manifestPath'
          : '  would create manifest (and pin placeholders): $manifestPath');

      final desktopPath = p.join(outputDir, '${manifestCfg.appId}.desktop');
      if (!File(desktopPath).existsSync()) {
        stderr.writeln('  would create desktop file: $desktopPath');
      }

      if (cfg.flutterVersionFile != null) {
        stderr.writeln('  would write: ${p.absolute(cfg.flutterVersionFile!)}');
      }
    }

    stderr.writeln('');
    stderr.writeln('(dry-run: no files written)');
  }

  String? _gitHead() {
    try {
      final result = Process.runSync('git', ['rev-parse', 'HEAD']);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return null;
  }
}
