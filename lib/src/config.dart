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

/// Config for the screenshot URL pinning in metainfo.xml.
class MetainfoConfig {
  /// Path to the metainfo.xml file (relative to project root).
  final String path;

  /// GitHub repo slug used for screenshot URLs (e.g. "owner/repo").
  final String? repoSlug;

  const MetainfoConfig({required this.path, this.repoSlug});

  factory MetainfoConfig.fromYaml(Map yaml) {
    return MetainfoConfig(
      path: yaml['path'] as String,
      repoSlug: yaml['repo_slug'] as String?,
    );
  }
}

/// Config for a screenshot entry in the generated manifest/metainfo.
class ScreenshotConfig {
  final String path;
  final bool? default_;

  const ScreenshotConfig({required this.path, this.default_});

  factory ScreenshotConfig.fromYaml(Map yaml) {
    return ScreenshotConfig(
      path: yaml['path'] as String,
      default_: yaml['default'] as bool?,
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
class DesktopConfig {
  final String name;
  final List<String> categories;

  const DesktopConfig({required this.name, required this.categories});

  factory DesktopConfig.fromYaml(Map yaml) {
    final cats = (yaml['categories'] as List?)?.cast<String>() ?? [];
    return DesktopConfig(
      name: yaml['name'] as String,
      categories: cats,
    );
  }
}

/// Config for manifest generation (`flatpak_gen.manifest:` section).
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
  final List<ScreenshotConfig> screenshots;
  final MetainfoConfig? metainfo;

  /// Git repository URL for the app source entry.
  final String? repoUrl;

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
    this.screenshots = const [],
    this.metainfo,
    this.repoUrl,
  });

  factory ManifestConfig.fromYaml(Map yaml) {
    final exts = (yaml['sdk_extensions'] as List?)?.cast<String>() ?? [];
    final finArgs = (yaml['finish_args'] as List?)?.cast<String>() ?? [];
    final extraMods = (yaml['extra_modules'] as List?)?.cast<String>() ?? [];
    final buildOpts = yaml['build_options'] as Map? ?? {};
    final envMap = (buildOpts['env'] as Map? ?? {})
        .map((k, v) => MapEntry(k as String, v.toString()));

    final iconsRaw = yaml['icons'] as List? ?? [];
    final screensRaw = yaml['screenshots'] as List? ?? [];

    return ManifestConfig(
      appId: yaml['app_id'] as String,
      runtimeVersion: (yaml['runtime_version'] ?? '25.08').toString(),
      sdkExtensions: exts,
      command: yaml['command'] as String,
      finishArgs: finArgs,
      extraModules: extraMods,
      appendPath: buildOpts['append_path'] as String?,
      prependLdLibraryPath: buildOpts['prepend_ld_library_path'] as String?,
      env: envMap,
      desktop: yaml['desktop'] != null
          ? DesktopConfig.fromYaml(yaml['desktop'] as Map)
          : null,
      icons: iconsRaw.map((e) => IconConfig.fromYaml(e as Map)).toList(),
      screenshots:
          screensRaw.map((e) => ScreenshotConfig.fromYaml(e as Map)).toList(),
      metainfo: yaml['metainfo'] != null
          ? MetainfoConfig.fromYaml(yaml['metainfo'] as Map)
          : null,
      repoUrl: yaml['repo_url'] as String?,
    );
  }
}

/// Parsed contents of `flatpak_gen:` in `pubspec.yaml` or `flatpak_gen.yaml`.
class FlatpakGenConfig {
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
      output: yaml['output'] as String? ?? 'flatpak/generated-sources.json',
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
  static FlatpakGenConfig load([String configPath = 'flatpak_gen.yaml']) {
    final pubspecFile = File('pubspec.yaml');
    final configFile = File(configPath);

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
      return FlatpakGenConfig.fromYaml(yaml['flatpak_gen'] as Map);
    }

    if (hasConfigFile) {
      final yaml = loadYaml(configFile.readAsStringSync());
      if (yaml is Map) return FlatpakGenConfig.fromYaml(yaml);
    }

    return FlatpakGenConfig(
      output: 'flatpak/generated-sources.json',
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
    return yaml is Map && yaml.containsKey('flatpak_gen');
  }
}
