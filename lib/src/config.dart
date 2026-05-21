import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A project-level patch entry: applies a patch file to a specific pub package.
class PatchEntry {
  final String package;
  final String? version;
  final String path;
  final String? destSubpath;

  const PatchEntry({
    required this.package,
    this.version,
    required this.path,
    this.destSubpath,
  });

  /// Resolves the dest path for this patch given the package version.
  String dest(String resolvedVersion) {
    final base = '.pub-cache/hosted/pub.dev/$package-$resolvedVersion';
    return destSubpath != null ? '$base/$destSubpath' : base;
  }

  factory PatchEntry.fromYaml(Map yaml) {
    return PatchEntry(
      package: yaml['package'] as String,
      version: yaml['version'] as String?,
      path: yaml['path'] as String,
      destSubpath: yaml['dest_subpath'] as String?,
    );
  }
}

/// Developer info for metainfo `<developer>` element.
class DeveloperConfig {
  /// Display name shown in software centres.
  final String name;

  /// Reverse-DNS id matching the app-id (e.g. "io.github.o_murphy").
  /// Required by AppStream 1.0 / Flathub guidelines.
  final String? id;

  const DeveloperConfig({required this.name, this.id});

  factory DeveloperConfig.fromYaml(dynamic yaml) {
    if (yaml is String) return DeveloperConfig(name: yaml);
    if (yaml is! Map) {
      throw ArgumentError(
          'developer config must be a String or Map, got ${yaml.runtimeType}');
    }
    return DeveloperConfig(
      name: yaml['name'] as String,
      id: yaml['id'] as String?,
    );
  }
}

/// Homepage / issue tracker URLs for metainfo.
class UrlConfig {
  final String? homepage;
  final String? bugtracker;
  final String? donation;

  const UrlConfig({this.homepage, this.bugtracker, this.donation});

  factory UrlConfig.fromYaml(Map yaml) {
    return UrlConfig(
      homepage: yaml['homepage'] as String?,
      bugtracker: yaml['bugtracker'] as String?,
      donation: yaml['donation'] as String?,
    );
  }
}

/// Config for a screenshot entry in metainfo.
class ScreenshotConfig {
  /// Local image path (relative to project root) used as a label/reference.
  /// The actual URL in metainfo is a raw.githubusercontent.com URL pinned to
  /// the current tag/commit by flutpak prepare.
  final String path;
  final bool default_;

  const ScreenshotConfig({required this.path, this.default_ = false});

  factory ScreenshotConfig.fromYaml(dynamic yaml) {
    if (yaml is String) return ScreenshotConfig(path: yaml);
    if (yaml is! Map) {
      throw ArgumentError(
          'Screenshot config must be a String or Map, got ${yaml.runtimeType}');
    }
    return ScreenshotConfig(
      path: yaml['path'] as String,
      default_: (yaml['default'] as bool?) ?? false,
    );
  }
}

/// An icon entry specifying the size and source path of an icon asset.
class IconEntry {
  /// Icon size string, e.g. '256x256', '512x512', 'scalable'.
  final String size;

  /// Source path in the repo (relative to project root).
  final String path;

  const IconEntry({required this.size, required this.path});

  factory IconEntry.fromYaml(Map yaml) => IconEntry(
        size: yaml['size'] as String,
        path: yaml['path'] as String,
      );
}

/// Config for manifest generation (`flutpak.manifest:` section).
class ManifestConfig {
  final String appId;
  final String runtimeVersion;
  final List<String> sdkExtensions;
  final String command;

  /// True when [command] was derived from [appId] rather than set explicitly.
  final bool commandInferred;

  final List<String> finishArgs;

  /// Paths to extra module YAML files (e.g. bclibc module).
  final List<String> extraModules;

  /// Additional PATH entries for build-options.append-path.
  final String? appendPath;

  /// Additional prepend-ld-library-path for build-options.
  final String? prependLdLibraryPath;

  /// Environment variables for build-options.env.
  final Map<String, String> env;

  /// Git repository URL for the app source entry.
  final String? repoUrl;

  /// Extra flatpak sources inserted verbatim into the app module sources list.
  /// Use for arch-specific prebuilt archives (e.g. objectbox-c) that have no
  /// pub package equivalent.
  final List<Map<String, dynamic>> extraSources;

  /// Override for the metainfo XML path. When null, [effectiveMetainfoPath()]
  /// computes the default.
  final String? metainfoPath;

  /// Override for the desktop entry path. When null,
  /// [effectiveDesktopEntryPath()] computes the default.
  final String? desktopEntryPath;

  /// Icon entries. When empty, [effectiveIcons()] returns the default 256x256
  /// icon derived from [appId].
  final List<IconEntry> icons;

  const ManifestConfig({
    required this.appId,
    required this.runtimeVersion,
    this.sdkExtensions = const [],
    required this.command,
    this.commandInferred = false,
    this.finishArgs = const [],
    this.extraModules = const [],
    this.appendPath,
    this.prependLdLibraryPath,
    this.env = const {},
    this.repoUrl,
    this.extraSources = const [],
    this.metainfoPath,
    this.desktopEntryPath,
    this.icons = const [],
  });

  /// Effective metainfo XML path (config override or default).
  String effectiveMetainfoPath() =>
      metainfoPath ?? 'app/share/metainfo/$appId.metainfo.xml';

  /// Effective .desktop entry path (config override or default).
  String effectiveDesktopEntryPath() =>
      desktopEntryPath ?? 'app/share/applications/$appId.desktop';

  /// Effective icon list. Returns the default 256x256 icon when [icons] is
  /// empty.
  List<IconEntry> effectiveIcons() => icons.isEmpty
      ? [
          IconEntry(
            size: '256x256',
            path: 'app/share/icons/hicolor/256x256/apps/$appId.png',
          )
        ]
      : icons;

  factory ManifestConfig.fromYaml(Map yaml) {
    final appId = yaml['app_id'];
    if (appId == null) {
      throw ArgumentError('manifest.app_id is required in flutpak config');
    }

    final commandRaw = yaml['command'] as String?;
    final commandInferred = commandRaw == null;
    final command = commandRaw ?? (appId as String).split('.').last;

    final exts = (yaml['sdk_extensions'] as List?)?.cast<String>() ?? [];
    final finArgs = (yaml['finish_args'] as List?)?.cast<String>() ?? [];
    final extraMods = (yaml['extra_modules'] as List?)?.cast<String>() ?? [];
    final buildOpts = yaml['build_options'] as Map? ?? {};

    // Accept env at both manifest.env and manifest.build_options.env levels;
    // build_options.env takes precedence for overlapping keys.
    final envTop = (yaml['env'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v.toString()));
    final envOpts = (buildOpts['env'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v.toString()));
    final envMap = {...envTop, ...envOpts};

    final extraSourcesRaw = yaml['extra_sources'] as List? ?? [];

    // Parse icons list.
    final iconsRaw = yaml['icons'] as List?;
    final List<IconEntry> iconsList;
    if (iconsRaw != null) {
      iconsList = iconsRaw.map((e) => IconEntry.fromYaml(e as Map)).toList();
      // Validate: if icons key is present, there must be a 256x256 entry.
      final has256 = iconsList.any((e) => e.size == '256x256');
      if (!has256) {
        throw ArgumentError(
          'manifest.icons must contain a 256x256 entry when icons: is specified',
        );
      }
    } else {
      iconsList = const [];
    }

    return ManifestConfig(
      appId: appId as String,
      runtimeVersion: (yaml['runtime_version'] ?? '25.08').toString(),
      sdkExtensions: exts,
      command: command,
      commandInferred: commandInferred,
      finishArgs: finArgs,
      extraModules: extraMods,
      appendPath: buildOpts['append_path'] as String?,
      prependLdLibraryPath: buildOpts['prepend_ld_library_path'] as String?,
      env: envMap,
      repoUrl: yaml['repo_url'] as String?,
      extraSources: extraSourcesRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      metainfoPath: yaml['metainfo_path'] as String?,
      desktopEntryPath: yaml['desktop_entry_path'] as String?,
      icons: iconsList,
    );
  }
}

/// Parsed contents of `flutpak:` in `pubspec.yaml` or `flutpak.yaml`.
class FlatpakGenConfig {
  /// Directory where flatpak artifacts are written.
  /// Defaults to `flatpak/`. All generated files (sources, manifest, desktop,
  /// metainfo) live inside this directory unless overridden by per-file paths.
  final String output;

  /// Lock file paths after env-var substitution at config-load time.
  /// Paths that still contain `\$FLUTTER_ROOT` (because the env var was not set)
  /// are preserved and resolved lazily via [effectivePubLocks].
  final List<String> pubLocks;
  final String? flutterSdk;
  final String? patchPath;

  /// Optional path to a file storing the pinned Flutter version string.
  final String? flutterVersionFile;

  /// Project-level patch entries applied to specific pub packages.
  final List<PatchEntry> patches;

  /// Optional manifest generation config.
  final ManifestConfig? manifest;

  const FlatpakGenConfig({
    required this.output,
    required this.pubLocks,
    this.flutterSdk,
    this.patchPath,
    this.flutterVersionFile,
    this.patches = const [],
    this.manifest,
  });

  /// Returns lock paths with any remaining `\$FLUTTER_ROOT` placeholders
  /// substituted by [sdkPath]. Use this instead of [pubLocks] whenever
  /// the effective SDK path is known (e.g. from the `--sdk` CLI flag).
  List<String> effectivePubLocks(String? sdkPath) {
    if (sdkPath == null) return pubLocks;
    return pubLocks
        .map((l) => l.replaceAll(r'$FLUTTER_ROOT', sdkPath))
        .toList();
  }

  factory FlatpakGenConfig.fromYaml(Map yaml) {
    String resolve(String s) => s.replaceAllMapped(
          RegExp(r'\$(\w+)'),
          (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
        );

    // Returns null if any \$VAR placeholder remains after substitution.
    // Used only for flutterSdk to avoid PathNotFoundException crashes.
    String? tryResolve(String s) {
      final result = resolve(s);
      return RegExp(r'\$[A-Za-z_]\w*').hasMatch(result) ? null : result;
    }

    final pub = yaml['pub'] as Map? ?? {};
    final flutter = yaml['flutter'] as Map? ?? {};

    final rawLocks =
        (pub['locks'] as List?)?.cast<String>() ?? ['pubspec.lock'];

    final patchesRaw = yaml['patches'] as List? ?? [];
    final patchEntries =
        patchesRaw.map((e) => PatchEntry.fromYaml(e as Map)).toList();

    final output = yaml['output'] as String? ?? 'flatpak';

    // Determine if a Flutter SDK is configured (either via flutter.sdk or
    // FLUTTER_ROOT env var) to decide the default flutter_version_file path.
    final flutterSdkPresent =
        flutter['sdk'] != null || Platform.environment['FLUTTER_ROOT'] != null;

    return FlatpakGenConfig(
      output: output,
      // Substitute env vars that ARE set; keep \$FLUTTER_ROOT literally when
      // not set — effectivePubLocks() resolves it with the CLI --sdk value.
      pubLocks: rawLocks.map(resolve).toList(),
      // tryResolve returns null when \$FLUTTER_ROOT is unset, preventing a
      // crash in FlutterSdkGenerator when the literal path is used.
      flutterSdk: flutter['sdk'] != null
          ? tryResolve(flutter['sdk'] as String)
          : Platform.environment['FLUTTER_ROOT'],
      patchPath: (flutter['patch'] ?? yaml['patch_path']) as String?,
      flutterVersionFile: yaml['flutter_version_file'] as String? ??
          (flutterSdkPresent ? p.join(output, 'flutter.version') : null),
      patches: patchEntries,
      manifest: yaml['manifest'] != null
          ? ManifestConfig.fromYaml(yaml['manifest'] as Map)
          : null,
    );
  }

  /// Loads config from pubspec.yaml (`flutpak:` section) or flutpak.yaml.
  ///
  /// Throws if both sources are found (ambiguous config).
  /// Falls back to sensible defaults if neither exists.
  static FlatpakGenConfig load(
      [String configPath = 'flutpak.yaml', String? workingDir]) {
    final dir = workingDir ?? Directory.current.path;
    final pubspecFile = File(p.join(dir, 'pubspec.yaml'));
    final configFile = File(p.join(dir, configPath));

    final hasPubspecSection = _hasFlatpakGenSection(pubspecFile);
    final hasConfigFile = configFile.existsSync();

    if (hasPubspecSection && hasConfigFile) {
      throw StateError(
        'Ambiguous config: both pubspec.yaml (flatpak_gen: section) and '
        '$configPath exist. Remove one.',
      );
    }

    if (hasPubspecSection) {
      final yaml = loadYaml(pubspecFile.readAsStringSync()) as Map;
      return FlatpakGenConfig.fromYaml(yaml['flutpak'] as Map);
    }

    if (hasConfigFile) {
      final yaml = loadYaml(configFile.readAsStringSync());
      if (yaml is Map) return FlatpakGenConfig.fromYaml(yaml);
    }

    return FlatpakGenConfig(
      output: 'flatpak',
      pubLocks: [
        'pubspec.lock',
        if (Platform.environment['FLUTTER_ROOT'] != null)
          p.join(
            Platform.environment['FLUTTER_ROOT']!,
            'packages/flutter_tools/pubspec.lock',
          ),
      ],
      flutterSdk: Platform.environment['FLUTTER_ROOT'],
    );
  }

  static bool _hasFlatpakGenSection(File pubspecFile) {
    if (!pubspecFile.existsSync()) return false;
    final yaml = loadYaml(pubspecFile.readAsStringSync());
    return yaml is Map && yaml.containsKey('flutpak');
  }
}
