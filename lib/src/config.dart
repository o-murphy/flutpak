import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Parsed contents of `flatpak_gen.yaml` in the project root.
class FlatpakGenConfig {
  final String output;
  final List<String> pubLocks;
  final String? flutterSdk;
  final String? patchPath;

  const FlatpakGenConfig({
    required this.output,
    required this.pubLocks,
    this.flutterSdk,
    this.patchPath,
  });

  factory FlatpakGenConfig.fromYaml(Map yaml) {
    String resolve(String s) => s.replaceAllMapped(
          RegExp(r'\$(\w+)'),
          (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
        );

    final pub = yaml['pub'] as Map? ?? {};
    final flutter = yaml['flutter'] as Map? ?? {};

    final rawLocks = (pub['locks'] as List?)?.cast<String>() ?? ['pubspec.lock'];

    return FlatpakGenConfig(
      output: yaml['output'] as String? ?? 'flatpak/generated-sources.json',
      pubLocks: rawLocks.map(resolve).toList(),
      flutterSdk: flutter['sdk'] != null
          ? resolve(flutter['sdk'] as String)
          : Platform.environment['FLUTTER_ROOT'],
      patchPath: yaml['patch_path'] as String?,
    );
  }

  /// Loads config from [path], falling back to sensible defaults.
  static FlatpakGenConfig load([String path = 'flatpak_gen.yaml']) {
    final file = File(path);
    if (file.existsSync()) {
      final yaml = loadYaml(file.readAsStringSync());
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
}
