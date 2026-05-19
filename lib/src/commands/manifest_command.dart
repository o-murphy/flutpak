import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';
import '../config.dart';
import '../generators/flutter_sdk.dart';
import '../generators/pub_sources.dart';
import '../utils/download_cache.dart';

/// Updates a Flatpak manifest YAML: bumps `version:` and regenerates sources.
class ManifestCommand extends Command<void> {
  @override
  final name = 'manifest';
  @override
  final description =
      'Update a Flatpak manifest: sync version from pubspec.yaml and '
      'regenerate generated-sources.json.';

  ManifestCommand() {
    argParser
      ..addOption('manifest',
          abbr: 'm',
          help: 'Flatpak manifest YAML/JSON file to update.',
          mandatory: true)
      ..addOption('pubspec',
          abbr: 'p',
          help: 'pubspec.yaml to read version from.',
          defaultsTo: 'pubspec.yaml')
      ..addOption('version',
          abbr: 'v',
          help: 'Override version (default: read from pubspec.yaml).')
      ..addMultiOption('lock',
          abbr: 'l',
          help: 'pubspec.lock paths (glob and \$ENV supported).')
      ..addOption('sdk',
          abbr: 's',
          help: 'Flutter SDK path. Defaults to \$FLUTTER_ROOT.')
      ..addOption('output',
          abbr: 'o',
          help: 'Generated sources output path.')
      ..addOption('patch',
          help: 'Relative path to shared.sh.patch.')
      ..addFlag('pub-only', help: 'Skip Flutter SDK sources.')
      ..addFlag('flutter-only', help: 'Skip pub sources.')
      ..addFlag('no-sources',
          help: 'Skip source regeneration — update version only.')
      ..addOption('config',
          abbr: 'c',
          help: 'Config file.',
          defaultsTo: 'flutpak.yaml');
  }

  @override
  Future<void> run() async {
    final cfg = FlatpakGenConfig.load(argResults!['config'] as String);

    final manifestPath = argResults!['manifest'] as String;
    final pubspecPath = argResults!['pubspec'] as String;
    final versionArg = argResults!['version'] as String?;
    final noSources = argResults!['no-sources'] as bool;
    final pubOnly = argResults!['pub-only'] as bool;
    final flutterOnly = argResults!['flutter-only'] as bool;

    final lockArg = argResults!['lock'] as List<String>;
    final lockPaths = lockArg.isNotEmpty ? lockArg : cfg.pubLocks;
    final sdkPath = argResults!['sdk'] as String? ??
        cfg.flutterSdk ??
        Platform.environment['FLUTTER_ROOT'];
    final output = argResults!['output'] as String? ?? cfg.output;
    final patchPath = argResults!['patch'] as String? ?? cfg.patchPath;

    // ── 1. Resolve version ────────────────────────────────────────────────────
    final version = versionArg ?? _readVersionFromPubspec(pubspecPath);
    stderr.writeln('version: $version');

    // ── 2. Update manifest ───────────────────────────────────────────────────
    final manifestFile = File(manifestPath);
    if (!manifestFile.existsSync()) {
      usageException('Manifest not found: $manifestPath');
    }

    var content = manifestFile.readAsStringSync();
    final versionPattern = RegExp(r'^version:.*$', multiLine: true);

    if (versionPattern.hasMatch(content)) {
      content = content.replaceFirst(versionPattern, 'version: $version');
      manifestFile.writeAsStringSync(content);
      stderr.writeln('✓  version updated in $manifestPath');
    } else {
      stderr.writeln('⚠  version: field not found in $manifestPath — '
          'add it manually if needed');
    }

    if (noSources) return;

    // ── 3. Regenerate sources ─────────────────────────────────────────────────
    final allSources = <Map<String, dynamic>>[];
    final cache = LocalDownloadCache();

    try {
      if (!flutterOnly) {
        final pubSources =
            await PubSourcesGenerator(lockFilePaths: lockPaths).generate();
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
            patchPath: patchPath,
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
    File(output)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');

    stderr.writeln('✓  ${allSources.length} total sources → $output');
  }

  static String _readVersionFromPubspec(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('pubspec.yaml not found: $path');
    }
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! Map || yaml['version'] == null) {
      throw Exception('version field missing in $path');
    }
    return yaml['version'].toString();
  }
}
