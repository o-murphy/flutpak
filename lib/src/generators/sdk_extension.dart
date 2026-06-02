import '../utils/download_cache.dart';
import 'flutter_sdk.dart';
import 'remote_flutter_sdk.dart';

/// Generates a Flathub SDK Extension manifest for Flutter.
///
/// Supports two source modes:
/// - **Local** (`sdkPath`): reads version files from an existing Flutter SDK
///   clone on disk. Original behaviour, requires `FLUTTER_ROOT` or `--sdk`.
/// - **Remote** (`flutterVersion`): fetches version files from GitHub and
///   resolves the commit SHA via `git ls-remote`. No local SDK clone needed.
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
  final String? sdkPath;
  final String? flutterVersion;
  final String runtimeVersion; // e.g. '25.08'
  final String? patchPath;
  final String? extensionId;
  final DownloadCache _cache;

  SdkExtensionGenerator({
    this.sdkPath,
    this.flutterVersion,
    required this.runtimeVersion,
    this.patchPath,
    this.extensionId,
    DownloadCache? cache,
  })  : assert(sdkPath != null || flutterVersion != null,
            'Either sdkPath or flutterVersion must be provided'),
        _cache = cache ?? LocalDownloadCache();

  Future<Map<String, dynamic>> generate() async {
    final String flutterTag;
    final List sdkSources;

    if (flutterVersion != null) {
      // Remote mode: fetch version files from GitHub.
      flutterTag = flutterVersion!;
      final remoteGen = RemoteFlutterSdkGenerator(
        flutterTag: flutterTag,
        patchPath: patchPath,
        cache: _cache,
      );
      sdkSources = (await remoteGen.generate()).map((s) => s.toJson()).toList();
    } else {
      // Local mode: read version files from the local SDK clone.
      flutterTag = FlutterSdkGenerator.readFlutterVersion(sdkPath!);
      final sdkGen = FlutterSdkGenerator(
        sdkPath: sdkPath!,
        patchPath: patchPath,
        cache: _cache,
      );
      sdkSources = (await sdkGen.generate()).map((s) => s.toJson()).toList();
    }

    final major = flutterTag.split('.').first;
    final id = extensionId ?? 'org.freedesktop.Sdk.Extension.flutter$major';

    return {
      'id': id,
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
          'sources': sdkSources,
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
}
