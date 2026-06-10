# Plan: Flutter SDK as a Separate Module + Caching + Renaming

## Current State

### Current Architecture

**`generate` command:**

1. Creates `FlutterSdkGenerator(flutterRef: ...)`, calls `flutterGen.generate()` → ~20 sources
2. `generateSourcesJson()` in `sources_util.dart` merges pub sources + Flutter sources + foreign-deps into a single `generated-sources.json`
3. Flutter SDK sources (git repo, engine artifacts, shared.sh patch, sky_engine pubspec, engine_stamp.json) are stored **inside** `generated-sources.json` together with pub packages
4. The App module in the manifest contains `sources: [..., 'generated-sources.json']`

**`sdk-mod` command:**

* Already supports generating a standalone `flutter-sdk-{version}.json` file in Flatpak module format:

```json
{
  "name": "flutter-sdk",
  "buildsystem": "simple",
  "build-commands": ["cp ...", "mkdir -p /var/lib && cp -r flutter /var/lib"],
  "sources": [<git>, <engine artifacts>, <patches>, ...]
}
```

* However, `generate` does not use it and instead duplicates the logic via `sources_util.dart`

### Problems with the Current Approach

| Problem                                                                               | Consequence                                                                            |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Flutter SDK (~20 entries) is mixed with pub packages (~300+ entries) in a single file | `generated-sources.json` is an inaccurate name and difficult to understand             |
| Every `generate` run re-hashes all engine artifacts                                   | Slow (~20–30 seconds of network activity) even when the Flutter version hasn't changed |
| Rustup is a separate module, Flutter SDK is not                                       | Inconsistent architecture                                                              |
| No separation of origin: pub vs flutter vs foreign-deps                               | Harder to debug and maintain                                                           |

---

## Desired State

### Structure After Refactoring

```text
generated/
  io.github.o_murphy.flutpak.demo.yml   ← final manifest
  pubspec-sources.json                  ← pub packages + foreign-deps only
  cargo-sources.json                    ← cargo crates (if present)
  flutter-sdk-3.44.1.json               ← Flutter SDK module (new file)
  rustup-1.85.0.json                    ← Rustup module (already exists)
  patches/
    flutter/shared.sh.patch
    cargokit/run_build_tool.sh.patch
```

**Manifest modules:**

```yaml
modules:
  - flutter-sdk-3.44.1.json    # string ref (like rustup)
  - rustup-1.85.0.json         # string ref (already exists)
  - name: App
    sources:
      - type: git
        ...
      - pubspec-sources.json   # pub packages (formerly generated-sources.json)
      - cargo-sources.json
```

### Flutter SDK Module Caching Logic

Similar to `ForeignDepsRegistry`: flutpak checks whether a pre-built `flutter-sdk-{version}.json` exists in the flutpak repository (GitHub raw), downloads and caches it **without hashing artifacts**. Generation is used as a fallback when no pre-built module exists.

```text
https://raw.githubusercontent.com/o-murphy/flutpak/{ref}/flutter_sdk/flutter-sdk-{version}.json
```

---

## Detailed Implementation Plan

### Phase 1 — Extract Flutter SDK into a Separate Module in generate

**1.1** Remove `flutterGen` from `generateSourcesJson()` in `sources_util.dart`:

```dart
// Before:
Future<void> generateSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  FlutterSdkGenerator? flutterGen,          // ← remove
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async { ... }

// After: pub + foreign-deps only
Future<void> generatePubSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async { ... }
```

The function no longer requires `FlutterSdkGenerator`; remove log output such as `"flutter: N entries"`.

**1.2** In `generate_command.dart::runWithArgs()`, generate the Flutter SDK module separately, similar to rustup:

```dart
// After cargo/rustup block:
String? flutterSdkModule;
if (flutterGen != null) {
  // Fetch flutter_tools lock for pub sources (unchanged)
  final toolsLockContent = await flutterGen.fetchFlutterToolsLock();
  toolsLockFile = ...;
  allLockPaths = [...allPubLockPaths, toolsLockFile.path];

  // Generate standalone flutter-sdk module
  final sdkSources = await flutterGen.generate();
  final gitSrc = sdkSources.whereType<GitSource>().firstOrNull;
  final flutterVersion = gitSrc?.tag ?? flutterRef;
  final sdkModuleFilename = 'flutter-sdk-$flutterVersion.json';
  final sdkModulePath = p.join(generatedDir, sdkModuleFilename);

  final module = {
    'name': 'flutter-sdk',
    'buildsystem': 'simple',
    'build-commands': FlutterSdkGenerator.buildCommands(),
    'sources': sdkSources.map((s) => s.toJson()).toList(),
  };
  File(sdkModulePath)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(module));
  flutterSdkModule = sdkModuleFilename;
  logInfo('✓  flutter SDK module → $sdkModuleFilename');
}
```

**1.3** Pass `flutterSdkModule` into `injectGeneratedContent()`:

```dart
// New signature:
String injectGeneratedContent({
  ...
  String? flutterSdkModule,   // NEW — filename ref, similar to rustupModule
  String? rustupModule,
  ...
})
```

**1.4** In `injectGeneratedContent()`, insert `flutterSdkModule` before the rustup module:

```text
modules:
  - flutter-sdk-3.44.1.json   ← flutterSdkModule
  - rustup-1.85.0.json        ← rustupModule
  - App                       ← app module
```

Insertion order: insert `rustupModule` at `insertIdx`, then `flutterSdkModule` at `insertIdx`, so both appear before the app module. Since Flutter SDK is required before Rust (Cargokit depends on Flutter install scripts), it must appear first.

**1.5** Update tests in `generate_inject_test.dart`:

* Add test `'inserts flutter-sdk module before rustup'`
* Verify order:

  * `modules[0] == 'flutter-sdk-3.44.1.json'`
  * `modules[1] == 'rustup-1.85.0.json'`
  * `modules[2]['name'] == 'App'`

---

### Phase 2 — Rename generated-sources.json → pubspec-sources.json

**2.1** In `generate_command.dart::runWithArgs()`:

```dart
// Before:
final sourcesPath = p.join(generatedDir, 'generated-sources.json');

// After:
final sourcesPath = p.join(generatedDir, 'pubspec-sources.json');
```

**2.2** Rename `generateSourcesJson` → `generatePubSourcesJson` (already done in Phase 1):

* Update log:
  `'✓  N total sources → pubspec-sources.json'`
* Update docstring

**2.3** Rename the function in `sources_util.dart` and update all imports.

**2.4** Update tests:

* `generate_inject_test.dart`

  * `sourcesPath: '/out/pubspec-sources.json'`
  * assert `'pubspec-sources.json'`
* Any other tests that verify the filename

**2.5** Update documentation/README and template manifests (if they reference `generated-sources.json`).

**2.6** Update `init_command.dart` if it generates templates containing `generated-sources.json`.

**Backward compatibility:** `generate` now outputs `pubspec-sources.json` instead of `generated-sources.json`. Existing manifests with hardcoded references will break. Backward compatibility is unnecessary because this is a generated file and flutpak updates the manifest automatically. Updating `injectGeneratedContent()` is sufficient.

---

### Phase 3 — Caching / Pre-built Flutter SDK Modules

**Idea:** flutpak maintains a `flutter_sdk/` directory in its repository containing pre-built modules for LTS/stable Flutter releases. Similar to foreign_deps: check GitHub raw, download and cache locally. If not found, generate as before.

**3.1** Add `FlutterSdkRegistry` in `lib/src/flutter_sdk_registry.dart`:

```dart
class FlutterSdkRegistry {
  final String ref;         // flutpak branch/tag to search
  final http.Client _client;
  final DownloadCache _cache;

  /// URL template for pre-built modules in the flutpak repository.
  String moduleUrl(String flutterVersion) =>
      'https://raw.githubusercontent.com/o-murphy/flutpak/$ref'
      '/flutter_sdk/flutter-sdk-$flutterVersion.json';

  /// Attempt to fetch a pre-built module for [flutterVersion].
  /// Returns JSON text or null if not found (HTTP 404 or network error).
  Future<String?> fetchPrebuilt(String flutterVersion) async {
    final url = moduleUrl(flutterVersion);
    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        logInfo('flutter-sdk: pre-built module found for $flutterVersion');
        return resp.body;
      }
      if (resp.statusCode == 404) return null;
      logWarn('flutter-sdk: HTTP ${resp.statusCode} fetching pre-built module');
      return null;
    } catch (e) {
      logWarn('flutter-sdk: fetch failed ($e) — falling back to generation');
      return null;
    }
  }
}
```

**3.2** Cache in `~/.cache/flutpak/flutter_sdk/`:

* Cache key: `flutter-sdk-{version}.json`
* Save pre-built modules to cache
* Subsequent runs load directly from cache without network access

Cache invalidation is unnecessary because Flutter versions and artifact hashes are deterministic. If `flutter-sdk-3.44.1.json` exists in cache, it remains valid indefinitely.

**3.3** Integrate into `generate_command.dart`:

```dart
// Instead of directly calling flutterGen.generate():
String? flutterSdkModule;
if (flutterRef != null) {
  final sdkRegistry = FlutterSdkRegistry(ref: cfg.foreignDepsRef);
  final flutterVersion = await _resolveFlutterVersion(flutterRef);

  // 1. Try pre-built
  String? moduleJson = await sdkRegistry.fetchPrebuilt(flutterVersion);

  // 2. Fallback: generate
  if (moduleJson == null) {
    logInfo('flutter-sdk: generating for $flutterVersion (not in registry)');
    final sdkSources = await flutterGen.generate();
    // ... build module map, jsonEncode
    moduleJson = jsonEncode(module);
    // Cache locally to avoid regenerating next time
    sdkRegistry.cacheLocally(flutterVersion, moduleJson);
  }

  // 3. Write into generated/ and include in manifest
  final sdkModuleFilename = 'flutter-sdk-$flutterVersion.json';
  File(p.join(generatedDir, sdkModuleFilename))
    ..createSync(recursive: true)
    ..writeAsStringSync(moduleJson);
  flutterSdkModule = sdkModuleFilename;
  logInfo('✓  flutter SDK module → $sdkModuleFilename');
}
```

**3.4** Simpler caching alternative: `DownloadCache` already provides SHA-256 URL caching. Reuse it directly—if the content at the URL never changes (`flutter-sdk-3.44.1.json` is immutable), it will automatically be cached via `_fetchCached`.

**3.5** The `sdk-mod` command can also use `FlutterSdkRegistry` to check for pre-built modules before generation. Optionally add a `--no-cache` flag for forced regeneration.

---

### Phase 4 — Update sdk-mod Command

**4.1** Once Flutter SDK becomes a standalone module in `generate`, `sdk-mod` becomes the official way to **publish** new Flutter SDK modules into the repository's `flutter_sdk/` directory.

**4.2** Add a `--publish-path` flag, or simply document that the output of `sdk-mod` can be committed into the flutpak repository:

```bash
# Generate a pre-built module for a new Flutter release:
flutpak sdk-mod --flutter 3.45.0 --output flutter_sdk/

# Then commit flutter_sdk/flutter-sdk-3.45.0.json into the flutpak repository
```

---

### Phase 5 — Tests

**5.1** `generate_inject_test.dart`:

* `'inserts flutter-sdk module ref before rustup and app'`
* `'inserts only rustup when flutterSdkModule is null'`
* `'appends pubspec-sources.json (not generated-sources.json) to sources'`

**5.2** New `flutter_sdk_registry_test.dart`:

* Mock HTTP: 200 → returns pre-built JSON
* Mock HTTP: 404 → returns null (fallback to generation)
* Mock HTTP error → returns null with warning

**5.3** Update `integration/flutter_sdk_integration_test.dart` if it checks for the filename `generated-sources.json`.

---

## Implementation Order

```text
Phase 1 (Flutter SDK → standalone module in generate)
    → eliminates duplication with sdk-mod
    → all required infrastructure already exists

Phase 2 (rename generated-sources → pubspec-sources)
    → one-line change + test updates
    → ideally done together with Phase 1 (single PR to avoid breaking twice)

Phase 3 (FlutterSdkRegistry + caching)
    → separate PR, does not block anything
    → can be implemented incrementally

Phase 4 (sdk-mod + publishing pre-built modules)
    → depends on Phase 3
```

---

## Limitations and Edge Cases

| Situation                                             | Behavior                                                        |
| ----------------------------------------------------- | --------------------------------------------------------------- |
| Pre-built module unavailable (404)                    | Silent fallback to generation, no error                         |
| Network error while checking pre-built                | Fallback to generation + warning                                |
| Flutter version not present in registry (new release) | Generate and store result in local cache                        |
| `--no-flutter` / `flutterRef == null`                 | No module and no entries in pubspec-sources; behavior unchanged |
| Existing `generated-sources.json` committed in git    | Becomes obsolete after renaming; leave in `.gitignore`          |
| `sdk-mod` after Phase 1                               | Unchanged — fully independent                                   |
