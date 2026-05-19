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
///   4. Pins metainfo screenshot URLs
class PrepareCommand extends Command<void> {
  @override
  final name = 'prepare';
  @override
  final description =
      'Generate sources, resolve patches, and create/update the Flatpak manifest.\n'
      'On first run: generates the manifest from pubspec.yaml flatpak_gen.manifest config.\n'
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
          abbr: 's',
          help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('config',
          abbr: 'c',
          help: 'Config file path.',
          defaultsTo: 'flutpak.yaml')
      ..addFlag('no-sources',
          help: 'Skip source regeneration (manifest update only).')
      ..addFlag('pub-only', help: 'Skip Flutter SDK sources.')
      ..addFlag('flutter-only', help: 'Skip pub sources.');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final tag = argResults!['tag'] as String?;
    final commit = (argResults!['commit'] as String?) ?? _gitHead();
    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];
    final noSources = argResults!['no-sources'] as bool;
    final pubOnly = argResults!['pub-only'] as bool;
    final flutterOnly = argResults!['flutter-only'] as bool;

    // ── 1. Resolve patch entries ─────────────────────────────────────────────
    final patchesDir = '${p.dirname(p.absolute(cfg.output))}/patches';
    final patchEntries = resolvePatchEntries(
      lockPaths: cfg.pubLocks,
      patchesDir: patchesDir,
      projectPatches: cfg.patches,
    );
    if (patchEntries.isNotEmpty) {
      stderr.writeln('patches: ${patchEntries.length} entries resolved');
    }

    // ── 2. Generate sources ──────────────────────────────────────────────────
    if (!noSources) {
      await _generateSources(
        cfg: cfg,
        sdkPath: sdkPath,
        pubOnly: pubOnly,
        flutterOnly: flutterOnly,
      );
    }

    // ── 3. Write flutter version file ────────────────────────────────────────
    if (sdkPath != null && cfg.flutterVersionFile != null) {
      _writeFlutterVersionFile(sdkPath, cfg.flutterVersionFile!);
    }

    // ── 4. Create or update manifest ─────────────────────────────────────────
    final manifestCfg = cfg.manifest;
    if (manifestCfg != null) {
      final manifestPath = 'flatpak/${manifestCfg.appId}.yml';
      final manifestFile = File(manifestPath);

      if (!manifestFile.existsSync()) {
        _generateManifest(
          manifestCfg: manifestCfg,
          manifestPath: manifestPath,
          generatedSourcesPath: cfg.output,
          patchEntries: patchEntries,
        );
        stderr.writeln('✓  manifest created: $manifestPath');
      } else {
        if (commit == null) {
          final content = manifestFile.readAsStringSync();
          if (content.contains('__FLATPAK_COMMIT__')) {
            stderr.writeln(
                '⚠  commit hash unknown (not in a git repo and --commit not set);\n'
                '   __FLATPAK_COMMIT__ placeholder will remain in $manifestPath');
          }
        }
        _updateManifestPlaceholders(
          manifestFile: manifestFile,
          tag: tag,
          commit: commit,
        );
        stderr.writeln('✓  manifest updated: $manifestPath');
      }

      // ── 5. Generate .desktop file (first run only) ────────────────────────
      if (manifestCfg.desktop != null) {
        final desktopPath = 'flatpak/${manifestCfg.appId}.desktop';
        if (!File(desktopPath).existsSync()) {
          _generateDesktopFile(manifestCfg: manifestCfg, desktopPath: desktopPath);
        }
      }

      // ── 6. Pin metainfo screenshot URLs ──────────────────────────────────
      if (manifestCfg.metainfo != null && commit != null) {
        final ref = (tag != null && tag.isNotEmpty) ? tag : commit;
        _patchMetainfo(manifestCfg.metainfo!.path, ref);
      }
    } else if (tag != null || commit != null) {
      // No manifest config but we have tag/commit — try to patch any existing
      // manifest that uses the placeholders.
      _patchAnyExistingManifest(
        tag: tag,
        commit: commit,
        flatpakDir: 'flatpak',
      );
    }

    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('✓  prepare complete  ref=$ref');
  }

  Future<void> _generateSources({
    required FlatpakGenConfig cfg,
    String? sdkPath,
    required bool pubOnly,
    required bool flutterOnly,
  }) async {
    final allSources = <Map<String, dynamic>>[];
    final cache = LocalDownloadCache();

    try {
      if (!flutterOnly) {
        final pubSources =
            await PubSourcesGenerator(lockFilePaths: cfg.pubLocks).generate();
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
            patchPath: cfg.patchPath,
            outputDir: p.dirname(p.absolute(cfg.output)),
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
    File(cfg.output)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    stderr.writeln('✓  ${allSources.length} total sources → ${cfg.output}');
  }

  void _generateManifest({
    required ManifestConfig manifestCfg,
    required String manifestPath,
    required String generatedSourcesPath,
    required List<PatchEntry> patchEntries,
  }) {
    final generator = ManifestGenerator(
      cfg: manifestCfg,
      generatedSourcesPath: generatedSourcesPath,
      patchEntries: patchEntries,
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

  void _patchMetainfo(String metainfoPath, String ref) {
    final f = File(metainfoPath);
    if (!f.existsSync()) return;
    final original = f.readAsStringSync();
    final patched = patchMetainfoScreenshots(original, ref: ref);
    if (patched != original) {
      f.writeAsStringSync(patched);
      stderr.writeln('  metainfo screenshot URLs → $ref');
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

  void _generateDesktopFile({
    required ManifestConfig manifestCfg,
    required String desktopPath,
  }) {
    final desktop = manifestCfg.desktop!;
    final buf = StringBuffer();
    buf.writeln('# Generated by flutpak — https://github.com/o-murphy/flutpak');
    buf.writeln('[Desktop Entry]');
    buf.writeln('Type=Application');
    buf.writeln('Name=${desktop.name}');
    buf.writeln('Exec=${manifestCfg.command}');
    buf.writeln('Icon=${manifestCfg.appId}');
    if (desktop.categories.isNotEmpty) {
      buf.writeln('Categories=${desktop.categories.join(';')};');
    }
    File(desktopPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(buf.toString());
    stderr.writeln('✓  desktop file created: $desktopPath');
  }

  String? _gitHead() {
    try {
      final result = Process.runSync('git', ['rev-parse', 'HEAD']);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return null;
  }
}
