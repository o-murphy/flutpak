import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../config.dart';

/// Collects all files needed for a Flathub submission into a single directory:
///   - <app_id>.yml (manifest)
///   - generated-sources.json
///   - <app_id>.metainfo.xml (if present)
///   - patches/ (all patch files referenced in the manifest)
class ExportCommand extends Command<void> {
  @override
  final name = 'export';
  @override
  final description =
      'Export manifest, sources, and patches into a ready-to-submit directory.';

  ExportCommand() {
    argParser
      ..addOption('config',
          abbr: 'c',
          help: 'Config file path.',
          defaultsTo: 'flutpak.yaml')
      ..addOption('out',
          abbr: 'o',
          help: 'Output directory.',
          defaultsTo: 'flatpak-export')
      ..addOption('manifest',
          abbr: 'm',
          help: 'Path to manifest YAML (auto-detected from config if omitted).');
  }

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    final configDir = p.dirname(p.absolute(configPath));
    final cfg = FlatpakGenConfig.load(configPath, configDir);
    final outDir = argResults!['out'] as String;
    final manifestPath = argResults!['manifest'] as String? ??
        _detectManifestPath(cfg, configDir);

    Directory(outDir).createSync(recursive: true);

    var exported = 0;

    // Manifest
    if (manifestPath == null) {
      stderr.writeln('⚠  manifest not found — skipping\n'
          '   pass --manifest <path> or add manifest.app_id to flutpak config');
    } else {
      final f = File(manifestPath);
      if (!f.existsSync()) {
        stderr.writeln('⚠  manifest not found: $manifestPath');
      } else {
        _copy(f, p.join(outDir, p.basename(manifestPath)));
        stderr.writeln('  ${p.basename(manifestPath)}');
        exported++;
      }
    }

    // generated-sources.json — mandatory
    final outputDir = _resolve(cfg.output, configDir);
    final sourcesPath = p.join(outputDir, 'generated-sources.json');
    final sourcesFile = File(sourcesPath);
    if (!sourcesFile.existsSync()) {
      stderr.writeln('error: generated-sources.json not found: $sourcesPath\n'
          '   run flutpak prepare first');
      exit(1);
    }
    _copy(sourcesFile, p.join(outDir, p.basename(sourcesPath)));
    stderr.writeln('  ${p.basename(sourcesPath)}');
    exported++;

    // metainfo.xml (optional)
    final metainfoPath = _resolveMetainfoPath(cfg, configDir);
    if (metainfoPath != null) {
      final mf = File(metainfoPath);
      if (mf.existsSync()) {
        _copy(mf, p.join(outDir, p.basename(metainfoPath)));
        stderr.writeln('  ${p.basename(metainfoPath)}');
        exported++;
      }
    }

    // patches/
    final patchesDir = Directory(p.join(outputDir, 'patches'));
    if (patchesDir.existsSync()) {
      final destPatches = p.join(outDir, 'patches');
      _copyDir(patchesDir, Directory(destPatches));
      final count = patchesDir
          .listSync(recursive: true)
          .whereType<File>()
          .length;
      stderr.writeln('  patches/ ($count files)');
      exported++;
    }

    if (exported == 0) {
      stderr.writeln('error: nothing to export — run flutpak prepare first');
      exit(1);
    }

    stderr.writeln('✓  exported $exported item(s) → $outDir');
  }

  void _copy(File src, String destPath) {
    File(destPath).parent.createSync(recursive: true);
    src.copySync(destPath);
  }

  void _copyDir(Directory src, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in src.listSync(recursive: false)) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        _copy(entity, destPath);
      } else if (entity is Directory) {
        _copyDir(entity, Directory(destPath));
      }
    }
  }

  static String _resolve(String path, String base) =>
      p.isAbsolute(path) ? path : p.join(base, path);

  String? _resolveMetainfoPath(FlatpakGenConfig cfg, String baseDir) {
    if (cfg.manifest == null) return null;
    if (cfg.manifest!.metainfo?.path != null) {
      final rel = cfg.manifest!.metainfo!.path!;
      return p.isAbsolute(rel) ? rel : p.join(baseDir, rel);
    }
    final outputDir = _resolve(cfg.output, baseDir);
    return p.join(outputDir, '${cfg.manifest!.appId}.metainfo.xml');
  }

  String? _detectManifestPath(FlatpakGenConfig cfg, String baseDir) {
    if (cfg.manifest != null) {
      final outputDir = _resolve(cfg.output, baseDir);
      return p.join(outputDir, '${cfg.manifest!.appId}.yml');
    }
    final outputDir = _resolve(cfg.output, baseDir);
    final dir = Directory(outputDir);
    if (!dir.existsSync()) return null;
    final candidates = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
        .toList();
    if (candidates.length == 1) return candidates.first.path;
    return null;
  }
}
