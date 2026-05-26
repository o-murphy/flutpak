import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
import '../patches_registry.dart';
import '../utils/sources_util.dart';
import 'command_utils.dart';

/// Generates the Flatpak `generated/` output from an existing template manifest.
///
/// Reads `<output>/<app_id>.yml` as the template, validates it, substitutes
/// `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders, generates
/// `generated-sources.json`, copies patches, and writes the final manifest to
/// `<output>/generated/<app_id>.yml`.
class GenerateCommand extends Command<void> {
  @override
  final name = 'generate';
  @override
  final description =
      'Substitute tag/commit placeholders in the template manifest, generate\n'
      'generated-sources.json, and copy everything into generated/.';

  GenerateCommand() {
    argParser
      ..addOption('tag',
          help: 'Git tag to embed in the manifest (e.g. v0.1.14).')
      ..addOption('commit',
          help: 'Full git commit SHA. Defaults to HEAD if inside a git repo.')
      ..addOption('sdk',
          abbr: 's', help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('config',
          abbr: 'c', help: 'Config file path.', defaultsTo: 'flutpak.yaml')
      ..addFlag('no-sources',
          help: 'Skip source regeneration (placeholder substitution only).')
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

    final tagArg = argResults!['tag'] as String?;
    final commitArg = argResults!['commit'] as String?;
    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];
    final noSources = argResults!['no-sources'] as bool;
    final pubOnly = argResults!['pub-only'] as bool;
    final flutterOnly = argResults!['flutter-only'] as bool;
    final dryRun = argResults!['dry-run'] as bool;

    if (dryRun) {
      final (tag, commit) = _resolveRefs(tagArg: tagArg, commitArg: commitArg);
      final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
      stderr.writeln('dry-run: generate  ref=$ref');
      stderr.writeln('(dry-run: no files written)');
      return;
    }

    final outputDir = p.absolute(cfg.output);

    await runWithArgs(
      cfg: cfg,
      sdkPath: sdkPath,
      tagArg: tagArg,
      commitArg: commitArg,
      noSources: noSources,
      pubOnly: pubOnly,
      flutterOnly: flutterOnly,
      outputDir: outputDir,
    );
  }

  /// Core generate logic, callable from [InitCommand] as well.
  Future<void> runWithArgs({
    required FlatpakGenConfig cfg,
    required String? sdkPath,
    required String? tagArg,
    required String? commitArg,
    required bool noSources,
    required bool pubOnly,
    required bool flutterOnly,
    required String outputDir,
  }) async {
    final manifestCfg = cfg.manifest;
    if (manifestCfg == null) {
      stderr.writeln('error: manifest section required in config for generate');
      exit(1);
    }

    // ── Resolve refs ──────────────────────────────────────────────────────
    final (tag, commit) = _resolveRefs(tagArg: tagArg, commitArg: commitArg);

    // ── Read and validate template ────────────────────────────────────────
    final templatePath = p.join(outputDir, '${manifestCfg.appId}.yml');
    final templateFile = File(templatePath);
    if (!templateFile.existsSync()) {
      stderr.writeln('error: template not found: $templatePath\n'
          '  Run `flutpak init` first to create the template.');
      exit(1);
    }
    final templateContent = templateFile.readAsStringSync();

    // Validate YAML fields in template vs config.
    _validateTemplate(templateContent, manifestCfg, templatePath);

    // Validate placeholders.
    if (!templateContent.contains(tagPlaceholder)) {
      stderr.writeln(
          'error: $tagPlaceholder not found in template: $templatePath');
      exit(1);
    }
    if (!templateContent.contains(commitPlaceholder)) {
      stderr.writeln(
          'error: $commitPlaceholder not found in template: $templatePath');
      exit(1);
    }

    // ── Validate asset files exist ────────────────────────────────────────
    validateManifestAssets(manifestCfg);

    // ── Output paths ──────────────────────────────────────────────────────
    final generatedDir = p.join(outputDir, 'generated');
    final sourcesPath = p.join(generatedDir, 'generated-sources.json');
    final generatedManifestPath =
        p.join(generatedDir, '${manifestCfg.appId}.yml');
    final patchesDir = p.join(outputDir, 'patches');
    final generatedPatchesDir = p.join(generatedDir, 'patches');

    // Lock paths with $FLUTTER_ROOT substituted from the effective SDK path.
    final effectiveLocks = cfg.effectivePubLocks(sdkPath);

    // ── Resolve patch entries ─────────────────────────────────────────────
    final List<PatchEntry> patchEntries;
    try {
      patchEntries = resolvePatchEntries(
        lockPaths: effectiveLocks,
        patchesDir: patchesDir,
        projectPatches: cfg.patches,
      );
    } on Exception catch (e) {
      stderr.writeln('error: $e');
      exit(1);
    }
    if (patchEntries.isNotEmpty) {
      stderr.writeln('patches: ${patchEntries.length} entries resolved');
    }

    // ── Resolve Flutter patch (write built-in if needed) ─────────────────
    // The Flutter patch is injected into the generated manifest (not the JSON)
    // so it is visible alongside package patches and is not lost when the JSON
    // is regenerated independently.
    String? flutterPatchAbsPath;
    if (!pubOnly && sdkPath != null) {
      flutterPatchAbsPath = FlutterSdkGenerator.resolveAndWritePatch(
        configPatchPath: cfg.patchPath,
        outputDir: outputDir,
      );
    }

    // ── Generate sources ──────────────────────────────────────────────────
    if (!noSources) {
      await generateSourcesJson(
        lockPaths: effectiveLocks,
        sdkPath: sdkPath,
        patchPath: cfg.patchPath,
        outputDir: outputDir,
        outputPath: sourcesPath,
        pubOnly: pubOnly,
        flutterOnly: flutterOnly,
        emitFlutterPatch: false,
      );
    }

    // ── Write flutter version file ────────────────────────────────────────
    if (cfg.flutterVersionFile != null) {
      if (sdkPath == null) {
        stderr.writeln(
          '⚠  flutter_version_file is set but Flutter SDK path could not be '
          'resolved (\$FLUTTER_ROOT not set); skipping',
        );
      } else {
        _writeFlutterVersionFile(sdkPath, p.absolute(cfg.flutterVersionFile!));
      }
    }

    // ── Copy template with substituted placeholders ───────────────────────
    if (commit == null) {
      if (templateContent.contains(commitPlaceholder)) {
        stderr.writeln(
            '⚠  commit hash unknown (not in a git repo and --commit not set);\n'
            '   $commitPlaceholder placeholder will remain in $generatedManifestPath');
      }
    }

    final effectiveCommit = commit ?? commitPlaceholder;
    var generatedContent = stripTemplateGuidance(templateContent);
    generatedContent = patchManifestPlaceholders(
      generatedContent,
      tag: tag,
      commit: effectiveCommit,
    );
    final allPatches = [
      if (flutterPatchAbsPath != null)
        PatchEntry(package: 'flutter', path: flutterPatchAbsPath),
      ...patchEntries,
    ];
    generatedContent =
        injectPatchSources(generatedContent, allPatches, patchesDir);
    File(generatedManifestPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(generatedContent);
    stderr.writeln('✓  generated manifest → $generatedManifestPath');

    // ── Copy patches ──────────────────────────────────────────────────────
    if (Directory(patchesDir).existsSync()) {
      _copyDirectory(Directory(patchesDir), Directory(generatedPatchesDir));
    }

    // ── Copy flathub.json ─────────────────────────────────────────────────
    final flathubSrc = File(p.join(outputDir, 'flathub.json'));
    if (flathubSrc.existsSync()) {
      File(p.join(generatedDir, 'flathub.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(flathubSrc.readAsStringSync());
    }

    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    stderr.writeln('✓  generate complete  ref=$ref');
  }

  (String?, String?) _resolveRefs({String? tagArg, String? commitArg}) {
    if (tagArg != null && commitArg != null) return (tagArg, commitArg);
    if (tagArg != null) {
      final resolved = _gitRevParse('$tagArg^{}') ?? _gitRevParse(tagArg);
      if (resolved == null) {
        stderr.writeln('⚠  could not resolve commit for tag $tagArg...');
      }
      return (tagArg, resolved);
    }
    final sha = commitArg ?? _gitRevParse('HEAD');
    return (sha, sha);
  }

  String? _gitRevParse(String ref) {
    try {
      final result = Process.runSync('git', ['rev-parse', ref]);
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return null;
  }

  void _validateTemplate(
      String content, ManifestConfig cfg, String templatePath) {
    // Parse simple key: value fields from the YAML text for validation.
    String? extractField(String key) {
      final m = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(content);
      return m?.group(1)?.trim().replaceAll("'", '').replaceAll('"', '');
    }

    final appId = extractField('app-id');
    if (appId != null && appId != cfg.appId) {
      stderr.writeln(
          'error: template app-id "$appId" does not match config app_id "${cfg.appId}": $templatePath');
      exit(1);
    }

    final command = extractField('command');
    if (command != null && command != cfg.command) {
      stderr.writeln(
          'error: template command "$command" does not match config command "${cfg.command}": $templatePath');
      exit(1);
    }

    final runtimeVersion = extractField('runtime-version');
    if (runtimeVersion != null && runtimeVersion != cfg.runtimeVersion) {
      stderr.writeln(
          'error: template runtime-version "$runtimeVersion" does not match config runtime_version "${cfg.runtimeVersion}": $templatePath');
      exit(1);
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

  void _copyDirectory(Directory source, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in source.listSync()) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        entity.copySync(destPath);
      } else if (entity is Directory) {
        _copyDirectory(entity, Directory(destPath));
      }
    }
  }
}
