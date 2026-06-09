import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import '../config.dart';
import '../foreign_deps_registry.dart';
import '../generators/cargo_sources.dart';
import '../generators/flutter_sdk.dart';
import '../generators/manifest_generator.dart';
import '../generators/rustup_generator.dart';
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
    List<String> foreignCargoLockPaths = const [];
    List<String> foreignExtraPubspecPaths = const [];
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
        foreignCargoLockPaths = depsResult.cargoLockPaths;
        foreignExtraPubspecPaths = depsResult.extraPubspecPaths;
      } finally {
        registry.dispose();
      }
    }

    final (:allPubLockPaths, :allCargoLockPaths) = buildLockPaths(
      effectiveLocks: effectiveLocks,
      extraPubspecPaths: foreignExtraPubspecPaths,
      cargoLockPaths: foreignCargoLockPaths,
      rustLocks: cfg.rustLocks,
      baseDir: baseDir,
    );

    // ── Build Flutter SDK generator if ref is configured ─────────────────
    final flutterRef = flutterRefOverride ?? cfg.flutterRef;
    if (flutterRef == null) {
      logWarn(
          'flutter.ref is not set — Flutter SDK sources will not be generated. '
          'Pass --flutter <ref> or add flutter.ref to flutpak.yaml.');
    }
    FlutterSdkGenerator? flutterGen;
    var allLockPaths = allPubLockPaths;
    if (flutterRef != null) {
      flutterGen = FlutterSdkGenerator(
        flutterRef: flutterRef,
        outputDir: outputDir,
        patchPath: cfg.patchPath,
        patchDestDir: generatedDir,
      );
    }

    // ── Generate sources ──────────────────────────────────────────────────
    String? generatedCargoSourcesPath;
    Map<String, dynamic>? rustupModule;
    final effectiveRustupPath = cfg.rustupPath ?? '/var/lib/rustup';

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

      // ── Generate Rust/Cargo artifacts ─────────────────────────────────
      if (allCargoLockPaths.isNotEmpty) {
        final effectiveRustVersion = cfg.rustVersion ?? '1.85.0';

        final cargoSources =
            await CargoSourcesGenerator.generate(allCargoLockPaths);
        generatedCargoSourcesPath = p.join(generatedDir, 'cargo-sources.json');
        File(generatedCargoSourcesPath)
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(cargoSources));
        logInfo('✓  cargo sources → cargo-sources.json');

        final rustupGen = RustupGenerator(
          rustVersion: effectiveRustVersion,
          rustupPath: effectiveRustupPath,
        );
        try {
          rustupModule = await rustupGen.generateModule();
          final rustupModulePath =
              p.join(generatedDir, 'rustup-$effectiveRustVersion.json');
          File(rustupModulePath)
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(rustupModule));
          logInfo('✓  rustup module → rustup-$effectiveRustVersion.json');
        } finally {
          rustupGen.dispose();
        }
      }
    } finally {
      flutterGen?.dispose();
    }

    if (commit == null) {
      logWarn('commit hash unknown (not in a git repo and --commit not set); '
          'commit will be missing from $generatedManifestPath');
    }

    var generatedContent = stripTemplateGuidance(templateContent);

    // ── Inject tag/commit, modules, and sources via yaml_edit ────────────
    generatedContent = injectGeneratedContent(
      content: generatedContent,
      manifestCfg: manifestCfg,
      extraModules: cfg.extraModules,
      sourcesPath: sourcesPath,
      cargoSourcesPath: generatedCargoSourcesPath,
      rustupModule: rustupModule,
      rustupPath: effectiveRustupPath,
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
}

/// Injects tag/commit, modules, sources, and Rust/Cargo artifacts into the
/// manifest YAML using yaml_edit.
///
/// The whole app module map is replaced in a single editor.update() to avoid
/// the yaml_edit 2.x crash when creating new keys in block-sequence elements.
/// Source appends happen after that replacement so they land in the right place.
String injectGeneratedContent({
  required String content,
  required ManifestConfig manifestCfg,
  required List<Object> extraModules,
  required String sourcesPath,
  String? cargoSourcesPath,
  Map<String, dynamic>? rustupModule,
  String? rustupPath,
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
    logWarn('app module "$appName" not found in template — skipping injection');
    return content;
  }

  final appModule = modules.toList()[appModuleIdx];
  if (appModule is! Map || appModule['sources'] is! List) {
    logWarn(
        'sources key not found or not a list in app module "$appName" — skipping injection');
    return content;
  }

  // Deep-convert once; ALL mutations (git source, sources list, build-options)
  // happen in-memory on this plain map before the single editor.update() call.
  // Mixing editor.update() with subsequent editor.appendToList() on the same
  // module triggers a yaml_edit 2.x stale-node bug, so we build the final
  // module in one shot.
  final appModuleMap =
      jsonDecode(jsonEncode(appModule)) as Map<String, dynamic>;
  final srcList = appModuleMap['sources'] as List;

  // ── Set tag and commit on git source ──────────────────────────────────
  if (tag != null || commit != null) {
    final gitSrcIdx = srcList.indexWhere((s) => s is Map && s['type'] == 'git');
    if (gitSrcIdx >= 0) {
      final src = srcList[gitSrcIdx] as Map<String, dynamic>;
      if (tag != null) src['tag'] = tag;
      if (commit != null) src['commit'] = commit;
    }
  }

  // ── Append sources ────────────────────────────────────────────────────
  // Order: generated-sources.json → manifest.sources → cargo-sources.json
  srcList.add(p.basename(sourcesPath));
  for (final src in manifestCfg.sources) {
    srcList.add(Map<String, dynamic>.from(src));
  }
  if (cargoSourcesPath != null) {
    srcList.add(p.basename(cargoSourcesPath));
  }

  // ── Merge CARGO_HOME / RUSTUP_HOME / append-path into build-options ───
  if (cargoSourcesPath != null && rustupPath != null) {
    final buildOpts =
        (appModuleMap['build-options'] as Map<String, dynamic>?) ?? {};
    final env = (buildOpts['env'] as Map<String, dynamic>?) ?? {};
    final appendPath = buildOpts['append-path'] as String?;
    appModuleMap['build-options'] = <String, dynamic>{
      ...buildOpts,
      'env': <String, dynamic>{
        ...env,
        'CARGO_HOME': rustupPath,
        'RUSTUP_HOME': rustupPath,
      },
      'append-path': appendPath != null
          ? '$appendPath:$rustupPath/bin'
          : '$rustupPath/bin',
    };
  }

  // Replace the whole app module in one shot.
  editor.update(['modules', appModuleIdx], appModuleMap);

  // ── Insert modules before app module ──────────────────────────────────
  // Inserting at the same index in reverse preserves original order.
  // rustup is inserted last (at insertIdx), so it ends up first — before
  // extraModules — which is correct (Rust must be set up before the app).
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
  if (rustupModule != null) {
    editor.insertIntoList(['modules'], insertIdx, rustupModule);
  }

  return editor.toString();
}

/// Merges effective pub locks with extra pubspec paths from the registry and
/// cargo lock paths from the registry + explicit config entries.
///
/// Extracted as a top-level function so it can be tested independently.
({List<String> allPubLockPaths, List<String> allCargoLockPaths})
    buildLockPaths({
  required List<String> effectiveLocks,
  required List<String> extraPubspecPaths,
  required List<String> cargoLockPaths,
  required List<String> rustLocks,
  required String baseDir,
}) {
  return (
    allPubLockPaths: [...effectiveLocks, ...extraPubspecPaths],
    allCargoLockPaths: [
      ...cargoLockPaths,
      ...rustLocks
          .map((l) => p.isAbsolute(l) ? l : p.absolute(p.join(baseDir, l))),
    ],
  );
}
