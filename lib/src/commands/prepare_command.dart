import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
import '../generators/metainfo_generator.dart';
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
      ..addFlag('flutter-only', help: 'Skip pub sources.')
      ..addFlag('dry-run',
          abbr: 'n',
          help: 'Print what would be done without writing any files.');
  }

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
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
      _printDryRun(cfg, configDir: configDir, tag: tag, commit: commit,
          sdkPath: sdkPath);
      return;
    }

    // cfg.output is a directory; sources file lives inside it.
    final outputDir = _resolve(cfg.output, configDir);
    final sourcesPath = p.join(outputDir, 'generated-sources.json');

    // ── 1. Resolve patch entries ─────────────────────────────────────────────
    final patchesDir = p.join(outputDir, 'patches');
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
        outputDir: outputDir,
        sourcesPath: sourcesPath,
        sdkPath: sdkPath,
        pubOnly: pubOnly,
        flutterOnly: flutterOnly,
      );
    }

    // ── 3. Write flutter version file ────────────────────────────────────────
    if (sdkPath != null && cfg.flutterVersionFile != null) {
      _writeFlutterVersionFile(
          sdkPath, _resolve(cfg.flutterVersionFile!, configDir));
    }

    // ── 4. Create or update manifest ─────────────────────────────────────────
    final manifestCfg = cfg.manifest;
    if (manifestCfg != null) {
      final manifestPath =
          p.join(configDir, 'flatpak', '${manifestCfg.appId}.yml');
      final manifestFile = File(manifestPath);

      if (!manifestFile.existsSync()) {
        _generateManifest(
          manifestCfg: manifestCfg,
          manifestPath: manifestPath,
          generatedSourcesPath: sourcesPath,
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
      final desktopPath =
          p.join(configDir, 'flatpak', '${manifestCfg.appId}.desktop');
      if (!File(desktopPath).existsSync()) {
        _generateDesktopFile(manifestCfg: manifestCfg, desktopPath: desktopPath);
      }

      // ── 6. Generate metainfo (first run only) ─────────────────────────────
      if (manifestCfg.metainfo != null) {
        final metainfoPath = _resolve(
          manifestCfg.metainfo!.path ??
              'flatpak/${manifestCfg.appId}.metainfo.xml',
          configDir,
        );
        final metainfoFile = File(metainfoPath);
        if (!metainfoFile.existsSync() && manifestCfg.metainfo!.canGenerate) {
          _generateMetainfo(
            appId: manifestCfg.appId,
            metainfoPath: metainfoPath,
            cfg: manifestCfg.metainfo!,
            tag: tag,
            releaseDate: _tagDate(tag),
          );
        }

        // ── 7. Pin metainfo screenshot URLs ────────────────────────────────
        if (commit != null) {
          final ref = (tag != null && tag.isNotEmpty) ? tag : commit;
          _patchMetainfo(metainfoPath, ref);
        }

        // ── 8. Update <releases> in metainfo ───────────────────────────────
        if (tag != null && tag.isNotEmpty) {
          _patchMetainfoReleasesSection(metainfoPath, tag, _tagDate(tag));
        }
      }
    } else if (tag != null || commit != null) {
      // No manifest config but we have tag/commit — try to patch any existing
      // manifest that uses the placeholders.
      _patchAnyExistingManifest(
        tag: tag,
        commit: commit,
        flatpakDir: p.join(configDir, 'flatpak'),
      );
    }

    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('✓  prepare complete  ref=$ref');
  }

  Future<void> _generateSources({
    required FlatpakGenConfig cfg,
    required String outputDir,
    required String sourcesPath,
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

  void _patchMetainfoReleasesSection(
      String metainfoPath, String tag, DateTime date) {
    final f = File(metainfoPath);
    if (!f.existsSync()) return;
    final original = f.readAsStringSync();
    final patched = patchMetainfoReleases(original, tag, date);
    if (patched != original) {
      f.writeAsStringSync(patched);
      stderr.writeln('  metainfo releases → $tag');
    }
  }

  /// Returns the date of [tag] from git log, falling back to today.
  DateTime _tagDate(String? tag) {
    if (tag != null && tag.isNotEmpty) {
      try {
        final result =
            Process.runSync('git', ['log', '-1', '--format=%aI', tag]);
        if (result.exitCode == 0) {
          final s = (result.stdout as String).trim();
          if (s.isNotEmpty) return DateTime.parse(s).toUtc();
        }
      } catch (_) {}
    }
    return DateTime.now().toUtc();
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

  void _generateMetainfo({
    required String appId,
    required String metainfoPath,
    required MetainfoConfig cfg,
    String? tag,
    DateTime? releaseDate,
  }) {
    final content = MetainfoGenerator(
      appId: appId,
      cfg: cfg,
      version: tag,
      releaseDate: releaseDate ?? DateTime.now().toUtc(),
    ).generate();
    File(metainfoPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    stderr.writeln('✓  metainfo created: $metainfoPath');
  }

  void _generateDesktopFile({
    required ManifestConfig manifestCfg,
    required String desktopPath,
  }) {
    // name and categories fall back to metainfo config when not set in desktop.
    final name = manifestCfg.desktop?.name ?? manifestCfg.metainfo?.name;
    final categories = (manifestCfg.desktop?.categories.isNotEmpty == true)
        ? manifestCfg.desktop!.categories
        : (manifestCfg.metainfo?.categories ?? []);

    if (name == null) {
      stderr.writeln('⚠  desktop file skipped: no name in desktop or metainfo config');
      return;
    }

    final buf = StringBuffer();
    buf.writeln('# Generated by flutpak — https://github.com/o-murphy/flutpak');
    buf.writeln('[Desktop Entry]');
    buf.writeln('Type=Application');
    buf.writeln('Name=$name');
    buf.writeln('Exec=${manifestCfg.command}');
    buf.writeln('Icon=${manifestCfg.appId}');
    if (categories.isNotEmpty) {
      buf.writeln('Categories=${categories.join(';')};');
    }
    File(desktopPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(buf.toString());
    stderr.writeln('✓  desktop file created: $desktopPath');
  }

  void _printDryRun(
    FlatpakGenConfig cfg, {
    required String configDir,
    String? tag,
    String? commit,
    String? sdkPath,
  }) {
    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('dry-run: prepare  ref=$ref');
    stderr.writeln('');

    final outputDir = _resolve(cfg.output, configDir);
    stderr.writeln('  would write: ${p.join(outputDir, 'generated-sources.json')}');
    for (final lock in cfg.pubLocks) {
      stderr.writeln('    pub lock: $lock');
    }
    if (sdkPath != null) {
      stderr.writeln('    flutter sdk: $sdkPath');
    } else {
      stderr.writeln('    flutter sdk: (skipped — no sdk path)');
    }

    final manifestCfg = cfg.manifest;
    if (manifestCfg != null) {
      final manifestPath =
          p.join(configDir, 'flatpak', '${manifestCfg.appId}.yml');
      final manifestExists = File(manifestPath).existsSync();
      stderr.writeln(manifestExists
          ? '  would update placeholders: $manifestPath'
          : '  would create manifest: $manifestPath');

      final desktopPath =
          p.join(configDir, 'flatpak', '${manifestCfg.appId}.desktop');
      if (!File(desktopPath).existsSync()) {
        stderr.writeln('  would create desktop file: $desktopPath');
      }

      if (manifestCfg.metainfo != null) {
        final metainfoPath = _resolve(
          manifestCfg.metainfo!.path ??
              'flatpak/${manifestCfg.appId}.metainfo.xml',
          configDir,
        );
        if (!File(metainfoPath).existsSync() &&
            manifestCfg.metainfo!.canGenerate) {
          stderr.writeln('  would create metainfo: $metainfoPath');
        }
        if (commit != null) {
          stderr.writeln('  would pin metainfo screenshots → $ref');
        }
        if (tag != null && tag.isNotEmpty) {
          stderr.writeln('  would update metainfo releases → $tag');
        }
      }

      if (cfg.flutterVersionFile != null) {
        stderr
            .writeln('  would write: ${_resolve(cfg.flutterVersionFile!, configDir)}');
      }
    }

    stderr.writeln('');
    stderr.writeln('(dry-run: no files written)');
  }

  static String _resolve(String path, String base) =>
      p.isAbsolute(path) ? path : p.join(base, path);

  String? _gitHead() {
    try {
      final result = Process.runSync('git', ['rev-parse', 'HEAD']);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return null;
  }
}
