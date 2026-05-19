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

/// Full metainfo config — drives both generation and patching.
class MetainfoConfig {
  /// Output path for the generated metainfo file (relative to project root).
  /// Defaults to `flatpak/<app_id>.metainfo.xml`.
  final String? path;

  /// GitHub repo slug for raw screenshot URLs (e.g. "owner/repo").
  final String? repoSlug;

  // ── Generation fields ────────────────────────────────────────────────────

  final String? name;
  final String? summary;
  final String? description;
  final List<String> categories;
  final List<String> keywords;
  final UrlConfig? url;
  final List<ScreenshotConfig> screenshots;

  /// OARS content-rating type, e.g. "oars-1.1".
  /// A blank OARS block is emitted; fill in via https://hughsie.github.io/oars/
  final String contentRating;

  bool get canGenerate => name != null && summary != null;

  const MetainfoConfig({
    this.path,
    this.repoSlug,
    this.name,
    this.summary,
    this.description,
    this.categories = const [],
    this.keywords = const [],
    this.url,
    this.screenshots = const [],
    this.contentRating = 'oars-1.1',
  });

  factory MetainfoConfig.fromYaml(Map yaml) {
    final rawScreenshots = yaml['screenshots'];
    final screensRaw = rawScreenshots is List ? rawScreenshots : [];
    return MetainfoConfig(
      path: yaml['path'] as String?,
      repoSlug: yaml['repo_slug'] as String?,
      name: yaml['name'] as String?,
      summary: yaml['summary'] as String?,
      description: yaml['description'] as String?,
      categories: (yaml['categories'] as List?)?.cast<String>() ?? [],
      keywords: (yaml['keywords'] as List?)?.cast<String>() ?? [],
      url: yaml['url'] != null ? UrlConfig.fromYaml(yaml['url'] as Map) : null,
      screenshots:
          screensRaw.map((e) => ScreenshotConfig.fromYaml(e)).toList(),
      contentRating: yaml['content_rating'] as String? ?? 'oars-1.1',
    );
  }
}

/// Config for an icon install entry.
class IconConfig {
  final String size;
  final String path;

  const IconConfig({required this.size, required this.path});

  factory IconConfig.fromYaml(Map yaml) {
    return IconConfig(
      size: yaml['size'] as String,
      path: yaml['path'] as String,
    );
  }
}

/// Config for desktop entry metadata.
/// `name` and `categories` fall back to `MetainfoConfig` values when omitted.
class DesktopConfig {
  final String? name;
  final List<String> categories;

  const DesktopConfig({this.name, this.categories = const []});

  factory DesktopConfig.fromYaml(Map yaml) {
    final cats = (yaml['categories'] as List?)?.cast<String>() ?? [];
    return DesktopConfig(
      name: yaml['name'] as String?,
      categories: cats,
    );
  }
}

/// Config for manifest generation (`flutpak.manifest:` section).
class ManifestConfig {
  final String appId;
  final String runtimeVersion;
  final List<String> sdkExtensions;
  final String command;
  final List<String> finishArgs;

  /// Paths to extra module YAML files (e.g. bclibc module).
  final List<String> extraModules;

  /// Additional PATH entries for build-options.append-path.
  final String? appendPath;

  /// Additional prepend-ld-library-path for build-options.
  final String? prependLdLibraryPath;

  /// Environment variables for build-options.env.
  final Map<String, String> env;

  final DesktopConfig? desktop;
  final List<IconConfig> icons;
  final MetainfoConfig? metainfo;

  /// Git repository URL for the app source entry.
  final String? repoUrl;

  /// Extra flatpak sources inserted verbatim into the app module sources list.
  /// Use for arch-specific prebuilt archives (e.g. objectbox-c) that have no
  /// pub package equivalent.
  final List<Map<String, dynamic>> extraSources;

  const ManifestConfig({
    required this.appId,
    required this.runtimeVersion,
    this.sdkExtensions = const [],
    required this.command,
    this.finishArgs = const [],
    this.extraModules = const [],
    this.appendPath,
    this.prependLdLibraryPath,
    this.env = const {},
    this.desktop,
    this.icons = const [],
    this.metainfo,
    this.repoUrl,
    this.extraSources = const [],
  });

  factory ManifestConfig.fromYaml(Map yaml) {
    final appId = yaml['app_id'];
    final command = yaml['command'];
    if (appId == null) {
      throw ArgumentError('manifest.app_id is required in flutpak config');
    }
    if (command == null) {
      throw ArgumentError('manifest.command is required in flutpak config');
    }

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

    final iconsRaw = yaml['icons'] as List? ?? [];
    final extraSourcesRaw = yaml['extra_sources'] as List? ?? [];

    return ManifestConfig(
      appId: appId as String,
      runtimeVersion: (yaml['runtime_version'] ?? '25.08').toString(),
      sdkExtensions: exts,
      command: command as String,
      finishArgs: finArgs,
      extraModules: extraMods,
      appendPath: buildOpts['append_path'] as String?,
      prependLdLibraryPath: buildOpts['prepend_ld_library_path'] as String?,
      env: envMap,
      desktop: yaml['desktop'] != null
          ? DesktopConfig.fromYaml(yaml['desktop'] as Map)
          : null,
      icons: iconsRaw.map((e) => IconConfig.fromYaml(e as Map)).toList(),
      metainfo: yaml['metainfo'] != null
          ? MetainfoConfig.fromYaml(yaml['metainfo'] as Map)
          : null,
      repoUrl: yaml['repo_url'] as String?,
      extraSources: extraSourcesRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

/// Parsed contents of `flutpak:` in `pubspec.yaml` or `flutpak.yaml`.
class FlatpakGenConfig {
  /// Directory where flatpak artifacts are written.
  /// Defaults to `flatpak/`. Generated sources file is always
  /// `<output>/generated-sources.json`.
  final String output;
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

  factory FlatpakGenConfig.fromYaml(Map yaml) {
    String resolve(String s) => s.replaceAllMapped(
          RegExp(r'\$(\w+)'),
          (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
        );

    final pub = yaml['pub'] as Map? ?? {};
    final flutter = yaml['flutter'] as Map? ?? {};

    final rawLocks = (pub['locks'] as List?)?.cast<String>() ?? ['pubspec.lock'];

    final patchesRaw = yaml['patches'] as List? ?? [];
    final patchEntries =
        patchesRaw.map((e) => PatchEntry.fromYaml(e as Map)).toList();

    return FlatpakGenConfig(
      output: yaml['output'] as String? ?? 'flatpak',
      pubLocks: rawLocks.map(resolve).toList(),
      flutterSdk: flutter['sdk'] != null
          ? resolve(flutter['sdk'] as String)
          : Platform.environment['FLUTTER_ROOT'],
      patchPath: (flutter['patch'] ?? yaml['patch_path']) as String?,
      flutterVersionFile: yaml['flutter_version_file'] as String?,
      patches: patchEntries,
      manifest: yaml['manifest'] != null
          ? ManifestConfig.fromYaml(yaml['manifest'] as Map)
          : null,
    );
  }

  /// Loads config from pubspec.yaml (`flatpak_gen:` section) or flatpak_gen.yaml.
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
