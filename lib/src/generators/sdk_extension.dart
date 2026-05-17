import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/flatpak_source.dart';
import '../utils/download_cache.dart';
import 'flutter_sdk.dart';

/// Generates a Flathub SDK Extension manifest for Flutter.
///
/// The resulting manifest can be submitted as
/// `org.freedesktop.Sdk.Extension.flutter3` (or versioned variant),
/// allowing Flutter apps on Flathub to use:
///
/// ```yaml
/// sdk-extensions:
///   - org.freedesktop.Sdk.Extension.flutter3
/// ```
///
/// instead of bundling the Flutter SDK in their own sources.
class SdkExtensionGenerator {
  final String sdkPath;
  final String runtimeVersion; // e.g. '25.08'
  final String? patchPath;
  final DownloadCache _cache;

  SdkExtensionGenerator({
    required this.sdkPath,
    required this.runtimeVersion,
    this.patchPath,
    DownloadCache? cache,
  }) : _cache = cache ?? DownloadCache();

  Future<Map<String, dynamic>> generate() async {
    final flutterTag =
        File(p.join(sdkPath, 'version')).readAsStringSync().trim();
    final majorMinor = _majorMinor(flutterTag); // e.g. '3.41' → '3'

    final sdkGen = FlutterSdkGenerator(
      sdkPath: sdkPath,
      patchPath: patchPath,
      cache: _cache,
    );
    final sdkSources = await sdkGen.generate();

    return {
      'id': 'org.freedesktop.Sdk.Extension.flutter$majorMinor',
      'branch': runtimeVersion,
      'runtime': 'org.freedesktop.Sdk',
      'runtime-version': runtimeVersion,
      'sdk': 'org.freedesktop.Sdk',
      'build-extension': true,
      'separate-locales': false,
      'modules': [
        {
          'name': 'flutter',
          'buildsystem': 'simple',
          'build-commands': _buildCommands(flutterTag),
          'sources': sdkSources.map((s) => s.toJson()).toList(),
        }
      ],
    };
  }

  List<String> _buildCommands(String flutterTag) => [
        // Stamp files so Flutter doesn't try to download at runtime
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine-dart-sdk.stamp',
        'cp flutter/bin/internal/material_fonts.version flutter/bin/cache/material_fonts.stamp',
        'cp flutter/bin/internal/gradle_wrapper.version flutter/bin/cache/gradle_wrapper.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/engine_stamp.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/flutter_sdk.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/font-subset.stamp',
        'cp flutter/bin/internal/engine.version flutter/bin/cache/linux-sdk.stamp',
        // Install into SDK extension path
        'install -d /usr/lib/sdk/flutter/',
        'cp -a flutter/. /usr/lib/sdk/flutter/',
        // env activation script (sourced by apps via sdk-extensions)
        r"printf '%s\n' 'export PATH=$PATH:/usr/lib/sdk/flutter/bin' "
            r"'export FLUTTER_ROOT=/usr/lib/sdk/flutter' "
            '> /usr/lib/sdk/flutter/enable.sh',
        'chmod 755 /usr/lib/sdk/flutter/enable.sh',
      ];

  static String _majorMinor(String tag) {
    // '3.41.9' → '3', just use major version for the extension ID
    return tag.split('.').first;
  }
}
