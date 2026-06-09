import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'utils/log.dart';

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

  /// Paths to extra module YAML files (e.g. bclibc module).
  /// Additional PATH entries for build-options.append-path.
  final String? appendPath;

  /// Additional prepend-ld-library-path for build-options.
  final String? prependLdLibraryPath;

  /// Environment variables for build-options.env.
  final Map<String, String> env;

  /// Extra flatpak sources inserted verbatim into the app module sources list.
  /// Use for arch-specific prebuilt archives (e.g. objectbox-c) that have no
  /// pub package equivalent.
  final List<Map<String, dynamic>> sources;

  /// Additional finish-args to merge with the mandatory defaults.
  /// Duplicates are silently dropped; mandatory args always appear first.
  final List<String> finishArgs;

  /// Subdirectory within the source tree where the build is performed.
  /// Passed verbatim as `subdir:` on the app module. Useful when the Flutter
  /// project lives in a subdirectory of the git repository.
  final String? subdir;

  const ManifestConfig({
    required this.appId,
    required this.runtimeVersion,
    this.sdkExtensions = const [],
    required this.command,
    this.commandInferred = false,
    this.appendPath,
    this.prependLdLibraryPath,
    this.env = const {},
    this.sources = const [],
    this.finishArgs = const [],
    this.subdir,
  });

  factory ManifestConfig.fromYaml(Map yaml) {
    final appId = yaml['app-id'];
    if (appId == null) {
      throw ArgumentError('manifest.app-id is required in flutpak config');
    }

    final commandRaw = yaml['command'] as String?;
    final commandInferred = commandRaw == null;
    final command = commandRaw ?? (appId as String).split('.').last;

    final exts = (yaml['sdk-extensions'] as List?)?.cast<String>() ?? [];
    final buildOpts = yaml['build-options'] as Map? ?? {};

    // Accept env at both manifest.env and manifest.build-options.env levels;
    // build-options.env takes precedence for overlapping keys.
    final envTop = (yaml['env'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v.toString()));
    final envOpts = (buildOpts['env'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v.toString()));
    final envMap = {...envTop, ...envOpts};

    final sourcesRaw = yaml['sources'] as List? ?? [];
    final finishArgsRaw = (yaml['finish-args'] as List?)?.cast<String>() ?? [];

    return ManifestConfig(
      appId: appId as String,
      runtimeVersion: (yaml['runtime-version'] ?? '25.08').toString(),
      sdkExtensions: exts,
      command: command,
      commandInferred: commandInferred,
      appendPath: buildOpts['append-path'] as String?,
      prependLdLibraryPath: buildOpts['prepend-ld-library-path'] as String?,
      env: envMap,
      sources: sourcesRaw
          .map((e) => _deepConvertYaml(e) as Map<String, dynamic>)
          .toList(),
      finishArgs: finishArgsRaw,
      subdir: yaml['subdir'] as String?,
    );
  }
}

/// Parsed contents of `flutpak:` in `pubspec.yaml` or `flutpak.yaml`.
class FlatpakGenConfig {
  /// Directory where flatpak artifacts are written.
  /// Defaults to `flatpak/`. All generated files (sources, manifest, desktop,
  /// metainfo) live inside this directory unless overridden by per-file paths.
  final String output;

  /// Lock file paths.
  final List<String> pubLocks;

  /// Git ref (tag, branch, or commit SHA) for the Flutter SDK.
  /// When set, engine version files are fetched from GitHub raw API — no
  /// local Flutter installation needed. When null, flutter sources are skipped.
  final String? flutterRef;

  final String? patchPath;

  /// Local foreign dependency overrides in the same format as the remote
  /// `foreign_deps.json` registry. Deep-merged on top of the remote registry
  /// before resolution. See `ForeignDepsRegistry.resolve()`.
  final Map<String, dynamic> localForeignDeps;

  /// Project-level icon entries passed to the manifest generator.
  /// When empty, [effectiveIcons()] returns the default 256x256
  /// icon derived from the app-id.
  final List<IconEntry> icons;

  /// Paths to extra module YAML files injected before the app module at
  /// generate time. Each element is either a [String] path to a YAML file
  /// (which may contain a single module map or a list of module maps) or a
  /// [Map] inline module definition in standard Flatpak manifest format.
  final List<Object> extraModules;

  /// Git repository URL for the app source entry.
  final String? repoUrl;

  /// When true (default), `disable-submodules: true` is written into the git
  /// source entry of the generated template manifest.
  final bool disableSubmodules;

  /// Override for the metainfo XML path. When null, [effectiveMetainfoPath()]
  /// computes the default.
  final String? metainfoPath;

  /// Override for the desktop entry path. When null,
  /// [effectiveDesktopEntryPath()] computes the default.
  final String? desktopEntryPath;

  /// Optional manifest generation config.
  final ManifestConfig? manifest;

  /// Git ref used to fetch the foreign_deps registry and patch files.
  /// Defaults to 'main' when null.
  final String? foreignDepsRef;

  /// Rust toolchain version for offline rustup module generation.
  /// Corresponds to `rust.version` in YAML. Defaults to '1.85.0' at use-site.
  final String? rustVersion;

  /// RUSTUP_HOME / CARGO_HOME path inside the Flatpak sandbox.
  /// Corresponds to `rust.rustup-path` in YAML. Defaults to '/var/lib/rustup'.
  final String? rustupPath;

  /// Explicit Cargo.lock paths (`rust.locks` in YAML), resolved against the
  /// config directory at generate time. Combined with registry-discovered ones.
  final List<String> rustLocks;

  const FlatpakGenConfig({
    required this.output,
    required this.pubLocks,
    this.flutterRef,
    this.patchPath,
    this.localForeignDeps = const {},
    this.icons = const [],
    this.extraModules = const <Object>[],
    this.repoUrl,
    this.disableSubmodules = false,
    this.metainfoPath,
    this.desktopEntryPath,
    this.manifest,
    this.foreignDepsRef,
    this.rustVersion,
    this.rustupPath,
    this.rustLocks = const [],
  });

  /// Effective metainfo XML path (config override or default).
  String effectiveMetainfoPath(String appId) =>
      metainfoPath ?? 'app/share/metainfo/$appId.metainfo.xml';

  /// Effective .desktop entry path (config override or default).
  String effectiveDesktopEntryPath(String appId) =>
      desktopEntryPath ?? 'app/share/applications/$appId.desktop';

  /// Effective icon list. Returns the default 256x256 icon when [icons] is
  /// empty.
  List<IconEntry> effectiveIcons(String appId) => icons.isEmpty
      ? [
          IconEntry(
            size: '256x256',
            path: 'app/share/icons/hicolor/256x256/apps/$appId.png',
          )
        ]
      : icons;

  factory FlatpakGenConfig.fromYaml(Map yaml) {
    final pub = yaml['pub'] as Map? ?? {};
    final flutter = yaml['flutter'] as Map? ?? {};
    final rust = yaml['rust'] as Map? ?? {};

    final rawLocks =
        (pub['locks'] as List?)?.cast<String>() ?? ['pubspec.lock'];

    final output = yaml['output'] as String? ?? 'flatpak';

    // Parse project-level icons list with 256x256 validation.
    final iconsRaw = yaml['icons'] as List?;
    final List<IconEntry> iconsList;
    if (iconsRaw != null) {
      iconsList = iconsRaw.map((e) => IconEntry.fromYaml(e as Map)).toList();
      final has256 = iconsList.any((e) => e.size == '256x256');
      if (!has256) {
        throw ArgumentError(
          'flutpak.icons must contain a 256x256 entry when icons: is specified',
        );
      }
    } else {
      iconsList = const [];
    }

    final extraModules = (yaml['modules'] as List?)?.map((e) {
          if (e is String) return e as Object;
          if (e is Map) return _deepConvertYaml(e) as Object;
          throw ArgumentError(
              'modules: each entry must be a string path or a module map, got ${e.runtimeType}');
        }).toList() ??
        const <Object>[];

    if (flutter['sdk'] != null) {
      logWarn('flutter.sdk is deprecated; use flutter.ref instead.');
    }

    final localForeignDeps =
        _deepConvertYaml(yaml['foreign-deps'] as Map? ?? {})
            as Map<String, dynamic>;

    return FlatpakGenConfig(
      output: output,
      pubLocks: rawLocks,
      flutterRef: flutter['ref'] as String?,
      patchPath: flutter['patch'] as String?,
      localForeignDeps: localForeignDeps,
      icons: iconsList,
      extraModules: extraModules,
      repoUrl: yaml['repo-url'] as String?,
      disableSubmodules: yaml['disable-submodules'] as bool? ?? false,
      metainfoPath: yaml['metainfo-path'] as String?,
      desktopEntryPath: yaml['desktop-entry-path'] as String?,
      manifest: yaml['app-id'] != null ? ManifestConfig.fromYaml(yaml) : null,
      foreignDepsRef: yaml['foreign-deps-ref'] as String?,
      rustVersion: rust['version'] as String?,
      rustupPath: rust['rustup-path'] as String?,
      rustLocks: (rust['locks'] as List?)?.cast<String>() ?? const [],
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
      pubLocks: ['pubspec.lock'],
    );
  }

  static bool _hasFlatpakGenSection(File pubspecFile) {
    if (!pubspecFile.existsSync()) return false;
    final yaml = loadYaml(pubspecFile.readAsStringSync());
    return yaml is Map && yaml.containsKey('flutpak');
  }
}

/// Recursively converts [YamlMap] and [YamlList] to plain Dart [Map] and
/// [List] so that yaml_edit can serialize them without producing invalid YAML.
dynamic _deepConvertYaml(dynamic value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries) e.key as String: _deepConvertYaml(e.value),
    };
  }
  if (value is List) {
    return value.map(_deepConvertYaml).toList();
  }
  return value;
}
