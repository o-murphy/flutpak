import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
import '../patches_registry.dart';
import '../utils/log.dart';
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
      logDebug('dry-run: generate  ref=$ref');
      logDebug('(dry-run: no files written)');
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
      logError('manifest section required in config for generate');
      exit(1);
    }

    // ── Resolve refs ──────────────────────────────────────────────────────
    final (tag, commit) = _resolveRefs(tagArg: tagArg, commitArg: commitArg);

    // ── Read and validate template ────────────────────────────────────────
    final templatePath = p.join(outputDir, '${manifestCfg.appId}.yml');
    final templateFile = File(templatePath);
    if (!templateFile.existsSync()) {
      logError('template not found: $templatePath');
      logError('  Run `flutpak init` first to create the template.');
      exit(1);
    }
    final templateContent = templateFile.readAsStringSync();

    // Validate YAML fields in template vs config.
    _validateTemplate(templateContent, manifestCfg, templatePath);

    // ── Validate asset files exist ────────────────────────────────────────
    validateManifestAssets(cfg, manifestCfg.appId);

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
      logError('$e');
      exit(1);
    }
    if (patchEntries.isNotEmpty) {
      logInfo('patches: ${patchEntries.length} entries resolved');
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
        logWarn('flutter_version_file is set but Flutter SDK path could not be '
            'resolved (\$FLUTTER_ROOT not set); skipping');
      } else {
        _writeFlutterVersionFile(sdkPath, p.absolute(cfg.flutterVersionFile!));
      }
    }

    if (commit == null) {
      logWarn('commit hash unknown (not in a git repo and --commit not set); '
          'commit will be missing from $generatedManifestPath');
    }

    var generatedContent = stripTemplateGuidance(templateContent);

    // ── Inject tag/commit, modules, and sources via yaml_edit ────────────
    generatedContent = _injectGeneratedContent(
      content: generatedContent,
      manifestCfg: manifestCfg,
      extraModules: cfg.extraModules,
      sourcesPath: sourcesPath,
      patchesDir: patchesDir,
      flutterPatchAbsPath: flutterPatchAbsPath,
      patchEntries: patchEntries,
      tag: tag,
      commit: commit,
    );

    File(generatedManifestPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(generatedContent);
    logInfo('✓  generated manifest → $generatedManifestPath');

    // ── Copy patches ──────────────────────────────────────────────────────
    // Every patch is normalised to a deterministic line-ending on copy:
    //   crlf: true  → CRLF  (target file in the pub.dev archive uses CRLF)
    //   crlf: false → LF    (default; most Linux packages)
    // This guarantees generated/patches/ is portable regardless of the host
    // OS or git line-ending settings.
    if (Directory(patchesDir).existsSync()) {
      final crlfPaths = {
        for (final e in patchEntries)
          if (e.crlf) p.canonicalize(e.path),
      };
      _copyPatches(
        Directory(patchesDir),
        Directory(generatedPatchesDir),
        crlfPaths: crlfPaths,
      );
    }

    final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
    logInfo('✓  generate complete  ref=$ref');
  }

  (String?, String?) _resolveRefs({String? tagArg, String? commitArg}) {
    if (tagArg != null && commitArg != null) return (tagArg, commitArg);
    if (tagArg != null) {
      final resolved = _gitRevParse('$tagArg^{}') ?? _gitRevParse(tagArg);
      if (resolved == null) {
        logWarn('could not resolve commit for tag $tagArg');
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
    String? extractField(String key) {
      final m = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(content);
      return m?.group(1)?.trim().replaceAll("'", '').replaceAll('"', '');
    }

    final appId = extractField('app-id');
    if (appId != null && appId != cfg.appId) {
      logError('template app-id "$appId" does not match config "${cfg.appId}": $templatePath');
      exit(1);
    }

    final command = extractField('command');
    if (command != null && command != cfg.command) {
      logError('template command "$command" does not match config "${cfg.command}": $templatePath');
      exit(1);
    }

    final runtimeVersion = extractField('runtime-version');
    if (runtimeVersion != null && runtimeVersion != cfg.runtimeVersion) {
      logError('template runtime-version "$runtimeVersion" does not match config "${cfg.runtimeVersion}": $templatePath');
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
    logInfo('✓  flutter.version → $outputPath ($version)');
  }

  /// Copies [source] into [dest] recursively, normalising line endings.
  ///
  /// Every patch file is rewritten with deterministic endings:
  /// - Files whose absolute path is in [crlfPaths] → CRLF.
  /// - All other files → LF.
  ///
  /// This ensures generated/patches/ is portable regardless of host OS or
  /// git autocrlf settings.
  void _copyPatches(
    Directory source,
    Directory dest, {
    Set<String> crlfPaths = const {},
  }) {
    dest.createSync(recursive: true);
    for (final entity in source.listSync()) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        final content = entity.readAsStringSync();
        final absPath = p.canonicalize(entity.path);
        if (crlfPaths.contains(absPath)) {
          File(destPath).writeAsStringSync(convertPatchToCrlf(content));
          logInfo('✓  patch → CRLF: ${p.relative(entity.path)}');
        } else {
          File(destPath).writeAsStringSync(content.replaceAll('\r\n', '\n'));
        }
      } else if (entity is Directory) {
        _copyPatches(entity, Directory(destPath), crlfPaths: crlfPaths);
      }
    }
  }

  /// Injects tag/commit, modules, manifest.sources, generated-sources.json,
  /// and patches into the manifest YAML using yaml_edit.
  ///
  /// - tag and commit are set on the git source entry.
  /// - modules file contents are inserted before the app module.
  /// - generated-sources.json, manifest.sources, and patch sources are appended
  ///   to the app module's sources list.
  String _injectGeneratedContent({
    required String content,
    required ManifestConfig manifestCfg,
    required List<String> extraModules,
    required String sourcesPath,
    required String patchesDir,
    required String? flutterPatchAbsPath,
    required List<PatchEntry> patchEntries,
    required String? tag,
    required String? commit,
  }) {
    final editor = YamlEditor(content);
    final yamlTree = loadYaml(content);

    final modules = yamlTree['modules'];
    if (modules is! List) {
      logWarn('modules key not found or not a list in template — skipping injection');
      return content;
    }

    final appName = manifestCfg.appId.split('.').last;
    final appModuleIdx =
        modules.toList().indexWhere((m) => m is Map && m['name'] == appName);
    if (appModuleIdx < 0) {
      logWarn('app module "$appName" not found in template — skipping injection');
      return content;
    }

    final appModule = modules.toList()[appModuleIdx];
    if (appModule is! Map || appModule['sources'] is! List) {
      logWarn('sources key not found or not a list in app module "$appName" — skipping injection');
      return content;
    }

    // ── Set tag and commit on git source ──────────────────────────────────
    // Both fields are always written (when commit is available). When no
    // --tag is given, _resolveRefs returns (sha, sha) so both fields get the
    // same SHA value.
    final sourcesBase = ['modules', appModuleIdx, 'sources'];
    final appSources = modules.toList()[appModuleIdx]['sources'];
    if (appSources is List && (tag != null || commit != null)) {
      final gitSrcIdx = appSources.toList().indexWhere(
            (s) => s is Map && s['type'] == 'git',
          );
      if (gitSrcIdx >= 0) {
        final gitBase = [...sourcesBase, gitSrcIdx];
        if (tag != null) editor.update([...gitBase, 'tag'], tag);
        if (commit != null) editor.update([...gitBase, 'commit'], commit);
      }
    }

    // ── Append to app module sources ──────────────────────────────────────
    // Order: generated-sources.json → manifest.sources → flutter patch → pub patches

    editor.appendToList(sourcesBase, p.basename(sourcesPath));

    for (final src in manifestCfg.sources) {
      editor.appendToList(sourcesBase, Map<String, dynamic>.from(src));
    }

    final allPatches = [
      if (flutterPatchAbsPath != null)
        PatchEntry(package: 'flutter', path: flutterPatchAbsPath),
      ...patchEntries,
    ];
    for (final patchMap in buildPatchSourceMaps(allPatches, patchesDir)) {
      editor.appendToList(sourcesBase, patchMap);
    }

    // ── Insert modules before app module ────────────────────────────
    // Iterate in reverse so that sequential insertions at the same index
    // preserve the original order from modules.
    var insertIdx = appModuleIdx;
    for (final modPath in extraModules.reversed) {
      final f = File(modPath);
      if (!f.existsSync()) {
        logWarn('modules: file not found: $modPath');
        continue;
      }
      final modYaml = loadYaml(f.readAsStringSync());
      if (modYaml is List) {
        for (final mod in modYaml.reversed) {
          editor.insertIntoList(['modules'], insertIdx, mod);
        }
      } else if (modYaml is Map) {
        editor.insertIntoList(['modules'], insertIdx, modYaml);
      }
    }

    return editor.toString();
  }
}
