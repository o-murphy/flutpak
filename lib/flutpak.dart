/// Flatpak source manifest generator for Flutter/Dart applications.
///
/// Provides generators for:
/// - Dart pub package sources (from pubspec.lock, using pub.dev API)
/// - Flutter SDK sources (from a local Flutter install, cached SHA-256)
/// - Combined generated-sources.json for offline Flatpak builds
/// - Flathub SDK Extension manifest for distributing Flutter SDK
library flutpak;

export 'src/config.dart';
export 'src/generators/flutter_sdk.dart';
export 'src/generators/manifest_generator.dart';
export 'src/generators/pub_sources.dart';
export 'src/generators/sdk_extension.dart';
export 'src/models/flatpak_source.dart';
export 'src/patches_registry.dart';
export 'src/utils/download_cache.dart';
