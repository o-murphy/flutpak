# Plan: Rust/Cargo Support in flutpak

## How It Works in flatpak-flutter

### Three distinct mechanisms:

### 1. foreign_deps.json — a new format for Rust packages

Entries for Cargokit-based packages have two new fields alongside `manifest`:

```json
"rhttp": {
  "0.12.0": {
    "cargo_locks": ["$PUB_DEV/rust"],
    "extra_pubspecs": ["$PUB_DEV/cargokit/build_tool"],
    "manifest": {
      "sources": [{
        "type": "patch",
        "path": "cargokit/run_build_tool.sh.patch",
        "dest": "$PUB_DEV/cargokit"
      }]
    }
  }
}
```

* `cargo_locks` — paths to Cargo.lock files (relative to the package directory, with `$PUB_DEV` acting as a placeholder)
* `extra_pubspecs` — additional Dart pubspecs (cargokit build_tool has its own pub lock)

Packages in the registry:

* rhttp
* flutter_vodozemac
* super_native_extensions
* metadata_god
* flutter_discord_rpc

---

### 2. cargo_generator.py — parses Cargo.lock, generates Flatpak sources

Reads TOML, for each crates.io package:

* Generates archive (`.crate` file)
* Generates inline (`.cargo-checksum.json`)

For git dependencies:

* Generates git source
* Generates shell (`cp`)
* Generates inline Cargo.toml
* Generates inline checksum

Appends an inline entry with `cargo/config.toml` that sets up `vendored-sources`.

Checksums are fetched directly from Cargo.lock — no network connection is required for crates.io packages.

---

### 3. rustup_generator.py — generates a separate Flatpak module to install Rust

Downloads `channel-rust-{version}.toml` from static.rust-lang.org and extracts URLs and checksums.

Generates a rustup module that installs the toolchain offline during the build process.

```text
CARGO_HOME=/run/build/{app}/cargo
RUSTUP_HOME=/var/lib/rustup
```

The App module receives:

* `CARGO_HOME`
* `RUSTUP_HOME`

environment variables, plus:

```text
{rustupPath}/bin
```

added to `append-path`.

---

## Key Patch

### cargokit/run_build_tool.sh.patch

Adds `--offline` to `pub get` in Cargokit, ensuring it doesn't access the network during the Flatpak build.

---

# Retrieving Cargo.lock Files in flutpak

Fundamental difference:

`flatpak-flutter` clones the repository and runs `flutter pub get` locally, then reads Cargo.lock from the extracted packages.

`flutpak` does not do this.

## Solution

Download the pub package archive from pub.dev and extract Cargo.lock from it.

flutpak already knows the exact versions of all packages from `pubspec.lock`.

Pub.dev publishes every package as a tar.gz archive at a deterministic URL:

```text
https://pub.dev/packages/{name}/versions/{version}.tar.gz
```

This is the exact same archive that already ends up in `generated-sources.json` for flatpak-builder.

flutpak will:

* Download it
* Extract only the required Cargo.lock files (paths specified in the registry's `cargo_locks`)
* Process them

The archive is cached in:

```text
~/.cache/flutpak/
```

keyed by the SHA-256 of the URL (similar to how registry fetches are handled), making subsequent runs instant.

### Benefits

* Does not require running `flutter pub get` before execution
* Is completely independent of the `~/.pub-cache` state
* Is deterministic — the version is locked in `pubspec.lock`
* Requires no additional setup for CI environments

---

# Detailed Implementation Plan

## Phase 1 — Dependencies and Base Infrastructure

### 1.1 Add TOML parser dependency to flutpak/pubspec.yaml

```yaml
dependencies:
  toml: ^0.6.0
```

### 1.2 Create `lib/src/generators/cargo_sources.dart`

Port of `cargo_generator.py`.

```dart
// Input: List of paths to Cargo.lock files
// Output: List<Map<String, dynamic>> (flatpak-builder sources format)
//         + config.toml inline configuration

class CargoSourcesGenerator {
  static Future<List<Map<String, dynamic>>> generate(
    List<String> cargoLockPaths, {
    String configFilename = 'config.toml',
  }) async { ... }
}
```

#### Internal logic

* Parse TOML content of each Cargo.lock
* For `registry+` packages:

  * archive (`https://static.crates.io/crates/{name}/{name}-{ver}.crate`)
  * inline (`.cargo-checksum.json`)
* For `git+` packages:

  * git source
  * shell (`cp`)
  * inline Cargo.toml
  * inline checksum

MVP:

* warn + skip git dependencies

Additional behavior:

* Deduplicate by `(type, url, dest)`
* Final inline entry:

  * `cargo/config.toml` containing the `vendored-sources` configuration

### 1.3 Create `lib/src/generators/rustup_generator.dart`

Port of `rustup_generator.py`.

```dart
class RustupGenerator {
  final String rustVersion;
  final String rustupPath;

  Future<Map<String, dynamic>> generateModule() async {
    // Fetch channel-rust-{version}.toml
    // Extract URLs + sha256
    // Return complete Flatpak module map
  }
}
```

---

## Phase 2 — Extending ForeignDepsRegistry

### 2.1 Extend entry parsing in foreign_deps_registry.dart

Current structure:

```dart
Future<List<Map<String, dynamic>>> resolve(...)
```

New structure:

```dart
class ForeignDepsResult {
  final List<Map<String, dynamic>> sources;
  final List<String> cargoLockPaths;
  final List<String> extraPubspecPaths;
}

Future<ForeignDepsResult> resolve(...)
```

### 2.2 Handle cargo_locks

For each package that contains `cargo_locks`:

1. Build package URL:

```text
https://pub.dev/packages/{name}/versions/{version}.tar.gz
```

2. Download archive (or use cache)
3. Extract specified files
4. Replace `$PUB_DEV` → archive root
5. Return extracted Cargo.lock paths

### 2.3 Handle extra_pubspecs

Extract `pubspec.lock` from specified subfolders and include them in:

```dart
extraPubspecPaths
```

---

## Phase 3 — Configuration Extension

### 3.1 Add to FlatpakGenConfig

```dart
/// Explicit Cargo.lock paths (rust.locks in YAML)
final List<String> rustLocks;

/// Rust toolchain version
final String? rustVersion;

/// RUSTUP_HOME path
final String? rustupPath;
```

### YAML format

```yaml
rust:
  version: "1.94.0"
  rustup-path: /var/lib/rustup

  locks:
    - path/to/some/Cargo.lock
```

---

## Phase 4 — Integration into the generate Command

### 4.1 After registry.resolve()

```dart
final depsResult = await registry.resolve(...);

final allCargoLockPaths = [
  ...depsResult.cargoLockPaths,
  ...cfg.rustLocks.map(
    (l) => p.isAbsolute(l) ? l : p.join(baseDir, l),
  ),
].toList();
```

### 4.2 Generate cargo/rustup artifacts

```dart
String? generatedCargoSourcesPath;
String? generatedRustupModulePath;

if (allCargoLockPaths.isNotEmpty) {
  ...
}
```

Creates:

* `cargo-sources.json`
* `rustup-{version}.json`

and logs:

```text
✓ cargo sources → cargo-sources.json
✓ rustup module → rustup-{version}.json
```

### 4.3 Pass to `_injectGeneratedContent()`

```dart
generatedContent = _injectGeneratedContent(
  ...
  cargoSourcesPath: generatedCargoSourcesPath,
  rustupModulePath: generatedRustupModulePath,
  rustVersion: cfg.rustVersion ?? '1.94.0',
  rustupPath: cfg.rustupPath ?? '/var/lib/rustup',
  ...
);
```

### 4.4 Modify `_injectGeneratedContent()`

If `rustupModulePath != null`:

* Insert rustup module before app module
* Add `cargo-sources.json` to app sources
* Merge into build-options.env:

  * `CARGO_HOME`
  * `RUSTUP_HOME`
* Add to append-path:

```text
{rustupPath}/bin
```

---

## Phase 5 — Updating foreign_deps in the flutpak Repository

### 5.1 Migrate entries

From:

```text
flatpak-flutter/foreign_deps/foreign_deps.json
```

To:

```text
flutpak/foreign_deps/foreign_deps.json
```

Packages:

* rhttp
* flutter_vodozemac
* super_native_extensions
* metadata_god
* flutter_discord_rpc

Including:

* cargo_locks
* extra_pubspecs

### 5.2 Copy patch

```text
cargokit/run_build_tool.sh.patch
```

from flatpak-flutter to:

```text
flutpak/foreign_deps/cargokit/
```

---

## Phase 6 — Testing

### 6.1 CargoSourcesGenerator

Fixture:

* minimal Cargo.lock
* several crates.io packages

Assert:

* correct archive output
* correct inline output
* correct config.toml structure

### 6.2 ForeignDepsRegistry

Registry entry containing:

* cargo_locks
* extra_pubspecs

Assert:

```dart
ForeignDepsResult.cargoLockPaths
```

contains correctly resolved paths.

### 6.3 config_test.dart

Verify parsing of:

```yaml
rust:
  version:
  rustup-path:
  locks:
```

---

# MVP Limitations

| Limitation                                                      | Reason                                        |
| --------------------------------------------------------------- | --------------------------------------------- |
| Git crate dependencies (`git+https`) are skipped with a warning | Requires repository cloning during generation |
| Rust toolchain version must be pinned or explicit               | `stable` cannot be resolved offline           |
| pub.dev must be accessible                                      | Package archives must be downloaded           |
| Only x86_64/aarch64 architectures                               | Matches flatpak-flutter behavior              |

Git crate dependencies are highly uncommon (virtually non-existent in Flutter plugins), so excluding them from the MVP still covers real-world use cases.

---

# Implementation Order (Considering Dependencies)

```text
Phase 1.1 (toml dep)
    → Phase 1.2 (CargoSourcesGenerator)
    → Phase 1.3 (RustupGenerator)
→ Phase 2 (Registry extension)
→ Phase 3 (Config extension)
→ Phase 4 (Generate command)
→ Phase 5 (foreign_deps update)
→ Phase 6 (Testing)
```
