import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import '../config.dart';
import '../foreign_deps_registry.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
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
      ..addOption('flutter',
          abbr: 'f',
          help: 'Flutter SDK git ref (tag, branch, or commit SHA). '
              'Overrides flutter.ref from config.')
      ..addOption('config',
          abbr: 'c', help: 'Config file path.', defaultsTo: 'flutpak.yaml')
      ..addFlag('no-foreign-deps',
          help: 'Skip foreign deps registry fetch (offline/air-gapped use).')
      ..addFlag('dry-run',
          abbr: 'n',
          help: 'Print what would be done without writing any files.');
  }

  @override
  Future<void> run() async {
    final configPath = p.absolute(argResults!['config'] as String);
    final configDir = p.dirname(configPath);
    final cfg = FlatpakGenConfig.load(configPath, configDir);

    final tagArg = argResults!['tag'] as String?;
    final commitArg = argResults!['commit'] as String?;
    final flutterArg = argResults!['flutter'] as String?;
    final noForeignDeps = argResults!['no-foreign-deps'] as bool;
    final dryRun = argResults!['dry-run'] as bool;

    if (dryRun) {
      final (tag, commit) = _resolveRefs(tagArg: tagArg, commitArg: commitArg);
      final ref = tag ?? commit?.substring(0, 12) ?? '(no ref)';
      logDebug('dry-run: generate  ref=$ref');
      logDebug('(dry-run: no files written)');
      return;
    }

    final outputDir = p.absolute(p.join(configDir, cfg.output));

    await runWithArgs(
      cfg: cfg,
      baseDir: configDir,
      flutterRefOverride: flutterArg,
      tagArg: tagArg,
      commitArg: commitArg,
      noForeignDeps: noForeignDeps,
      outputDir: outputDir,
    );
  }

  /// Core generate logic, callable from [InitCommand] as well.
  ///
  /// [baseDir] is the directory of the config file; relative paths from the
  /// config (lock files, asset files) are resolved against it.
  Future<void> runWithArgs({
    required FlatpakGenConfig cfg,
    required String baseDir,
    required String? tagArg,
    required String? commitArg,
    String? flutterRefOverride,
    required String outputDir,
    bool noForeignDeps = false,
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
    validateManifestAssets(cfg, manifestCfg.appId, baseDir: baseDir);

    // ── Output paths ──────────────────────────────────────────────────────
    final generatedDir = p.join(outputDir, 'generated');
    final sourcesPath = p.join(generatedDir, 'generated-sources.json');
    final generatedManifestPath =
        p.join(generatedDir, '${manifestCfg.appId}.yml');
    final generatedPatchesDir = p.join(generatedDir, 'patches');

    // Lock paths resolved against baseDir.
    final effectiveLocks = cfg.pubLocks.map((l) {
      if (p.isAbsolute(l)) return l;
      return p.absolute(p.join(baseDir, l));
    }).toList();

    // ── Resolve foreign deps from registry ───────────────────────────────
    List<Map<String, dynamic>> foreignDepSources = const [];
    if (!noForeignDeps) {
      final registry = ForeignDepsRegistry(ref: cfg.foreignDepsRef);
      try {
        final depsResult = await registry.resolve(
          lockPaths: effectiveLocks,
          localForeignDeps: cfg.localForeignDeps,
          generatedPatchesDir: generatedPatchesDir,
          projectPatchesDir: p.join(outputDir, 'patches'),
        );
        foreignDepSources = depsResult.sources;
      } finally {
        registry.dispose();
      }
    }

    // ── Build Flutter SDK generator if ref is configured ─────────────────
    final flutterRef = flutterRefOverride ?? cfg.flutterRef;
    if (flutterRef == null) {
      logWarn(
          'flutter.ref is not set — Flutter SDK sources will not be generated. '
          'Pass --flutter <ref> or add flutter.ref to flutpak.yaml.');
    }
    FlutterSdkGenerator? flutterGen;
    var allLockPaths = effectiveLocks;
    if (flutterRef != null) {
      flutterGen = FlutterSdkGenerator(
        flutterRef: flutterRef,
        outputDir: outputDir,
        patchPath: cfg.patchPath,
        patchDestDir: generatedDir,
      );
    }

    // ── Generate sources ──────────────────────────────────────────────────
    try {
      if (flutterGen != null) {
        // Fetch flutter_tools pubspec.lock so its deps appear in generated-sources.json.
        final toolsLockContent = await flutterGen.fetchFlutterToolsLock();
        final toolsLockFile = File(p.join(generatedDir, 'flutter_tools.lock'))
          ..createSync(recursive: true)
          ..writeAsStringSync(toolsLockContent);
        allLockPaths = [...effectiveLocks, toolsLockFile.path];
      }

      await generateSourcesJson(
        lockPaths: allLockPaths,
        outputPath: sourcesPath,
        flutterGen: flutterGen,
        foreignDepSources: foreignDepSources,
      );
    } finally {
      flutterGen?.dispose();
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
      tag: tag,
      commit: commit,
    );

    File(generatedManifestPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(generatedContent);
    logInfo('✓  generated manifest → $generatedManifestPath');

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
      logError(
          'template app-id "$appId" does not match config "${cfg.appId}": $templatePath');
      exit(1);
    }

    final command = extractField('command');
    if (command != null && command != cfg.command) {
      logError(
          'template command "$command" does not match config "${cfg.command}": $templatePath');
      exit(1);
    }

    final runtimeVersion = extractField('runtime-version');
    if (runtimeVersion != null && runtimeVersion != cfg.runtimeVersion) {
      logError(
          'template runtime-version "$runtimeVersion" does not match config "${cfg.runtimeVersion}": $templatePath');
      exit(1);
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
    required List<Object> extraModules,
    required String sourcesPath,
    required String? tag,
    required String? commit,
  }) {
    final editor = YamlEditor(content);
    final yamlTree = loadYaml(content);

    final modules = yamlTree['modules'];
    if (modules is! List) {
      logWarn(
          'modules key not found or not a list in template — skipping injection');
      return content;
    }

    final appName = manifestCfg.appId.split('.').last;
    final appModuleIdx =
        modules.toList().indexWhere((m) => m is Map && m['name'] == appName);
    if (appModuleIdx < 0) {
      logWarn(
          'app module "$appName" not found in template — skipping injection');
      return content;
    }

    final appModule = modules.toList()[appModuleIdx];
    if (appModule is! Map || appModule['sources'] is! List) {
      logWarn(
          'sources key not found or not a list in app module "$appName" — skipping injection');
      return content;
    }

    // ── Set tag and commit on git source ──────────────────────────────────
    // Both fields are always written (when commit is available). When no
    // --tag is given, _resolveRefs returns (sha, sha) so both fields get the
    // same SHA value.
    //
    // We replace the whole git source map in one editor.update() call rather
    // than updating individual keys.  yaml_edit 2.x crashes when asked to
    // CREATE a new key inside a map that is an element of a block sequence
    // (the tag/commit keys are absent from fresh templates).  Replacing the
    // entire list element avoids that code path.
    final sourcesBase = ['modules', appModuleIdx, 'sources'];
    final appSources = modules.toList()[appModuleIdx]['sources'];
    if (appSources is List && (tag != null || commit != null)) {
      final gitSrcIdx = appSources.toList().indexWhere(
            (s) => s is Map && s['type'] == 'git',
          );
      if (gitSrcIdx >= 0) {
        final existing =
            Map<String, dynamic>.from(appSources.toList()[gitSrcIdx] as Map);
        if (tag != null) existing['tag'] = tag;
        if (commit != null) existing['commit'] = commit;
        editor.update([...sourcesBase, gitSrcIdx], existing);
      }
    }

    // ── Append to app module sources ──────────────────────────────────────
    // Order: generated-sources.json → manifest.sources → flutter patch → pub patches

    editor.appendToList(sourcesBase, p.basename(sourcesPath));

    for (final src in manifestCfg.sources) {
      editor.appendToList(sourcesBase, Map<String, dynamic>.from(src));
    }

    // ── Insert modules before app module ────────────────────────────
    // Iterate in reverse so that sequential insertions at the same index
    // preserve the original order from modules.
    var insertIdx = appModuleIdx;
    for (final mod in extraModules.reversed) {
      if (mod is String) {
        final f = File(mod);
        if (!f.existsSync()) {
          logWarn('modules: file not found: $mod');
          continue;
        }
        final modYaml = loadYaml(f.readAsStringSync());
        if (modYaml is List) {
          for (final m in modYaml.reversed) {
            editor.insertIntoList(['modules'], insertIdx, m);
          }
        } else if (modYaml is Map) {
          editor.insertIntoList(['modules'], insertIdx, modYaml);
        }
      } else if (mod is Map) {
        editor.insertIntoList(['modules'], insertIdx, mod);
      }
    }

    return editor.toString();
  }
}
