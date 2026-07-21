# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.3] — 2026-07-21

### Fixed
- Flutter action version resolver

### Added
- **Flutter SDK module for 3.44.7** — pre-built `flutter-sdk-3.44.7.json` added to
  `modules/flutter-sdk/`.
- **Flutter SDK module for 3.44.6** — pre-built `flutter-sdk-3.44.6.json` added to
  `modules/flutter-sdk/`.
- **Flutter SDK module for 3.44.5** — pre-built `flutter-sdk-3.44.5.json` added to
  `modules/flutter-sdk/`.
- **`dart_lmdb2` foreign deps entry (0.9.12)** — patches
  `LMDBNative._resolveLibraryPath()` (`lib/src/lmdb_native.dart`), which
  locates the native LMDB library via `Isolate.resolvePackageUriSync()` on
  Linux/Windows. That API only works in JIT mode (`dart run`/`flutter run`);
  a compiled AOT release build throws `Unsupported operation` immediately on
  the first LMDB open, confirmed empirically with a real
  `flutter build linux --release` run in an isolated directory (no source
  project, no pub cache — the same shape a Flatpak install has). This is not
  Flatpak-specific; it breaks every compiled Flutter Linux/Windows release
  build using `dart_lmdb2`, regardless of prebuilt-vs-source-built native
  library. The patch tries `resolvePackageUriSync` first (unchanged dev-time
  behaviour), then falls back to a path next to the running executable
  (`<exe_dir>/lib/<libName>`, matching Flutter's own native-library bundling
  convention) on `UnsupportedError`.
- **`flutter_lmdb2` foreign deps entry (0.9.5)** — `flutter_lmdb2` has no
  Linux (or Windows) support at all as published: both platforms are
  commented out in its own `pubspec.yaml`, and there is no `linux/`
  directory. Two patches add it: a new `linux/CMakeLists.txt` (+ a minimal
  no-op GObject plugin, same shape as every other no-op Linux Flutter
  plugin) that **compiles `liblmdb.so` from source** — `LMDB/lmdb.git` at
  tag `LMDB_0.9.31`, fetched via a plain `git` source (pinned by tag and
  commit hash) rather than a prebuilt-binary download, following the same
  "vendor source, no prebuilt binaries" principle as the parent `ob-dump`
  project this pairs with — and a `pubspec.yaml` patch uncommenting the
  `linux:` plugin platform block. The new `lmdb_native` CMake target also
  links `Threads::Threads` (`find_package(Threads REQUIRED)`) explicitly —
  `mdb.c` uses `pthread_mutex`/pthread-specific data, and relying on it
  being pulled in transitively (which happens to work on this development
  machine, since glibc ≥ 2.34 merges pthread into `libc.so.6`) isn't
  portable to older glibc or non-glibc Flatpak runtimes. Verified
  empirically end-to-end: built a scratch Flutter app depending on
  `flutter_lmdb2`, ran `flutter build linux --release`, confirmed
  `liblmdb.so` was compiled and bundled into
  `build/linux/x64/release/bundle/lib/` alongside `libapp.so` with zero
  undefined symbols (`ldd -r`), then copied only `bundle/` to an isolated
  directory and confirmed `LMDB` opened successfully — zero network
  access, zero prebuilt binaries, at any step.

## [0.8.2] — 2026-06-26

### Added

- **`flutter.ref` symbolic channel names** — `flutter.ref` now accepts `'stable'`,
  `'latest'`, and `'beta'` in addition to explicit tags, branches, and commit SHAs.
  The concrete version is resolved at generate time from the Flutter releases API
  (`storage.googleapis.com/flutter_infra_release/releases/releases_linux.json`):

  | Value                                           | Resolves to                                   |
  | ----------------------------------------------- | --------------------------------------------- |
  | `'stable'` or omitted within `flutter:` section | latest stable release                         |
  | `'latest'` / `'beta'`                           | latest beta (pre-release)                     |
  | anything else                                   | passed through unchanged (tag / branch / SHA) |

  The resolved version is printed at generate time:
  `flutter: stable → 3.44.4`

  Flutter SDK generation is triggered whenever the `flutter:` key is present in
  the config (even if empty) or `--flutter` is passed on the CLI. When the key is
  absent entirely, a warning is shown and Flutter SDK sources are skipped — same
  as before.

  ```yaml
  # Empty flutter: key → resolves latest stable automatically
  flutter:

  # Explicit channel
  flutter:
    ref: stable    # or: latest / beta / 3.44.2 / main / <sha>
  ```
- **Flutter SDK module for 3.44.3** — pre-built `flutter-sdk-3.44.4.json` added to
  `modules/flutter-sdk/`.
- **Flutter SDK module for 3.44.4** — pre-built `flutter-sdk-3.44.4.json` added to
  `modules/flutter-sdk/`.

## [0.8.1] — 2026-06-17

### Added

- **Flutter SDK module for 3.44.2** — pre-built `flutter-sdk-3.44.2.json` added to
  `modules/flutter-sdk/`.

- **Automated flutter-sdk registry CI** (`.github/workflows/flutter-sdk-module.yml`) —
  daily cron at 06:00 UTC resolves the latest Flutter stable release, runs
  `flutpak sdk-mod`, and opens a PR when a new module JSON is not yet in the registry.
  Can also be triggered manually (`workflow_dispatch`) with an optional explicit version
  and `force` flag.

- **`pdfium_dart` foreign deps entries** — versions 0.1.2, 0.2.0, 0.2.1, 0.2.2, 0.2.3
  added to the registry. Each entry provides architecture-specific pdfium binary archives
  and the `0.2.0-build.dart.patch` patch for offline Flatpak builds.

### Fixed

- **objectbox-c license note corrected** — the previous note incorrectly argued Mere
  Aggregation (GPLv3 §5) as justification for GPL-3.0 app compatibility. The GPL FAQ
  is explicit that modules linked in a shared address space form a combined work;
  containers do not change this analysis. The note now states clearly that **GPL-3.0
  apps cannot use `objectbox_flutter_libs` or `objectbox_sync_flutter_libs` for Flathub
  submissions**. Permissive-licensed apps (MIT, Apache 2.0) are unaffected.

## [0.8.0] — 2026-06-10

### Breaking Changes

- **`generated-sources.json` renamed to `pubspec-sources.json`** — the pub and
  foreign-deps sources file is now named `pubspec-sources.json` in all generated
  output. Update your Flathub submission manifest's `!include` reference and any
  scripts that reference this filename by name.

- **Flutter SDK moved to a standalone module** — when `flutter.ref` is set,
  `generate` no longer embeds Flutter SDK sources inside `pubspec-sources.json`.
  Instead it produces a separate `flutter-sdk-<version>.json` module (analogous
  to `rustup-<version>.json`) that installs Flutter to `/var/lib/flutter`. The
  cache-stamp `cp` build-commands are no longer emitted in the app module; they
  live inside the flutter-sdk module. Re-run `flutpak init --force` to regenerate
  a clean template.

### Added

- **Rust/Cargo support via cargokit** — `flutpak generate` now handles Flutter
  packages that use [cargokit](https://github.com/nickel-lang/cargokit) for Rust
  native code. When a project uses cargokit-based packages (e.g. `rhttp`,
  `metadata_god`) and the `rust:` config section is present, `generate`:
  - Parses all resolved `Cargo.lock` files and fetches crate checksums from
    crates.io to emit a `cargo-sources.json` for offline builds.
  - Generates a `rustup-<version>.json` module that installs Rust offline:
    downloads the channel manifest, `rustup-init` binary, and a minimal toolchain
    (rustc, cargo, rust-std) for both `x86_64` and `aarch64`; creates a `stable`
    symlink to the pinned version.
  - Inserts the `rustup` module before the app module in the generated manifest.
  - Injects `CARGO_HOME`, `RUSTUP_HOME`, and `<rustup-path>/bin` in the app
    module's `build-options.env` / `append-path`.
  - Appends `cargo-sources.json` to the app module's `sources` list after
    `pubspec-sources.json`.

- **`rust:` config section** in `flutpak.yaml`:
  ```yaml
  rust:
    version: 1.85.0              # Rust toolchain version; default: 1.85.0
    rustup-path: /var/lib/rustup  # CARGO_HOME / RUSTUP_HOME; default: /var/lib/rustup
    locks:                        # extra Cargo.lock paths (resolved vs config dir)
      - rust/Cargo.lock
  ```

- **`CargoSourcesGenerator`** — parses one or more `Cargo.lock` files, fetches
  SHA-256 checksums from the crates.io sparse registry index, and emits a
  `flatpak-builder`-ready archive source list (`cargo-sources.json`).

- **`RustupGenerator`** — generates a complete `rustup-<version>.json` Flatpak
  module (offline Rust toolchain installer). Downloads channel manifests,
  architecture-specific `rustup-init` binaries, and the minimal toolchain
  components; adds `RUSTUP_DIST_SERVER` pointing at the pre-downloaded static
  directory so `rustup-init` never touches the network at build time.

- **Foreign deps registry — 5 cargokit packages added** (alphabetical order):

  | Package                   | Version |
  | ------------------------- | ------- |
  | `flutter_discord_rpc`     | 1.0.0   |
  | `flutter_vodozemac`       | 0.5.0   |
  | `metadata_god`            | 1.1.0   |
  | `rhttp`                   | 0.12.0  |
  | `super_native_extensions` | 0.8.24  |

  Each entry specifies `cargo_locks` (for `Cargo.lock` extraction from the
  pub.dev archive) and `extra_pubspecs` (for `cargokit/build_tool/pubspec.lock`),
  plus a `cargokit/run_build_tool.sh.patch` source that adds `--offline` to
  `pub get` inside the cargokit build tool.

- **`foreign_deps/cargokit/run_build_tool.sh.patch`** — adds `--offline` to
  `pub get` in cargokit's `run_build_tool.sh`; required for Flatpak offline builds.

- **Flutter SDK as standalone module** — when `flutter.ref` is set, `generate`
  produces a separate `flutter-sdk-<version>.json` module. The module uses
  `buildsystem: simple` and installs the Flutter SDK to `/var/lib/flutter`. It is
  inserted before all other extra modules in the generated manifest. The app
  module's `append-path` references `/var/lib/flutter/bin`.

- **`FlutterSdkRegistry`** — before generating a flutter-sdk module from
  scratch, `generate` checks for a pre-built `flutter-sdk-<version>.json` in the
  flutpak repository. Lookup order:
  1. `~/.cache/flutpak/flutter_sdk/flutter-sdk-<version>.json` (local cache)
  2. `flutter_sdk/flutter-sdk-<version>.json` on the `main` branch of the
     flutpak GitHub repo (raw URL)
  3. Fallback to generation when not available

  Pre-built modules are cached locally after the first fetch for subsequent runs.

- **`flutter-sdk-ref` config field** — optional git ref (branch or tag) of the
  flutpak repo from which pre-built flutter-sdk modules are fetched. Defaults to
  `'main'` when unset.
  ```yaml
  flutter-sdk-ref: main   # optional; default: main
  ```

- **`flutpak cache clear`** — new subcommand that deletes the entire
  `~/.cache/flutpak/` directory (SHA-256 download cache and cached flutter-sdk
  modules).

### Fixed

- **`extraPubspecPaths` not wired into pub sources** — `cargokit/build_tool/pubspec.lock`
  paths extracted by the foreign deps registry were collected but never passed to
  `generateSourcesJson`. Cargokit build tool Dart dependencies were missing from
  `pubspec-sources.json`. Fixed by extracting `buildLockPaths` as a top-level
  testable function that explicitly merges `extraPubspecPaths` into `allPubLockPaths`.

### Demo

- **Demo app** (`examples/demo_app/`) extended to exercise sqlite3 + rhttp:
  - Added `sqlite3 ^2.7.0`, `sqlite3_flutter_libs ^0.6.0`, `rhttp ^0.12.0`
  - `main.dart` now shows the SQLite version string (from `SELECT sqlite_version()`)
    and rhttp initialisation status
  - `flutpak.yaml` gains `rust:` section (`version: 1.85.0`,
    `rustup-path: /var/lib/rustup`) and `foreign-deps-ref: feat/rust-based-deps`
  - Template manifest gains two post-build smoke checks:
    `test -f "$BUNDLE_PATH/lib/librhttp.so"` (Rust native lib bundled by cargokit)
    and `ldconfig -p | grep -q libsqlite3` (SQLite available from Flatpak runtime)

## [0.7.1] — 2026-06-09

### Added

- **README: flutpak vs flatpak-flutter** — new section explaining similarities,
  differences, compatibility, and use cases for both tools.

### Changed

- **Foreign deps version matching changed to `≤`** — the registry now uses
  "highest entry ≤ installed version" instead of exact match. A registry entry
  for `1.0.0` also applies to `1.2.3`, `1.5.0`, etc. A new major entry
  (e.g. `2.0.0`) is only picked when the installed version reaches `2.x`. When
  the matched registry version differs from the installed version, `generate`
  logs the matched key for traceability
  (e.g. `rhttp 0.12.1 (matched registry 0.12.0)`).

## [0.7.0] — 2026-06-09

### Breaking Changes

- **`flutter.sdk` removed** — replace with `flutter.ref: "<tag-or-branch>"` in
  `flutpak.yaml`. Engine versions are now fetched from GitHub raw API; no local
  Flutter installation is required for `flutpak generate`.
  ```yaml
  # before
  flutter:
    sdk: $FLUTTER_ROOT

  # after
  flutter:
    ref: "3.44.1"   # tag, "stable", "main", or commit SHA
  ```

- **`--sdk` flag removed** from `generate` and `init` — use `--flutter <ref>`
  (`-f`) instead.

- **`--no-sources`, `--pub-only`, `--flutter-only` flags removed** from
  `generate` — use `--no-foreign-deps` for offline runs; pub-only vs. full
  generation is now driven by whether `flutter.ref` is set in config.

- **`config.patches` / `PatchEntry` removed** — replaced by `foreign-deps:`
  in `flutpak.yaml`. Local overrides use the same format as
  `foreign_deps/foreign_deps.json`.
  ```yaml
  # before
  patches:
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox.patch
      crlf: true

  # after
  foreign-deps:
    objectbox_flutter_libs:
      manifest:
        sources:
          - type: patch
            path: patches/objectbox.patch
            crlf: true
  ```

- **`pub`, `flutter`, `sources` commands removed** — use `generate` directly.

- **`sdk-ext` command replaced by `sdk-mod`** — generates a standalone Flutter
  SDK module JSON (installs Flutter to `/var/lib/flutter`) instead of an SDK
  Extension. Pre-generated JSONs for Flutter 3.35.x, 3.38.x, and 3.41.x are
  available in [`modules/flutter-sdk/`](modules/flutter-sdk/).

- **`generate` action input `sdk` renamed to `flutter-ref`**.

- **`manifest:` section removed** — all fields (`app-id`, `runtime-version`,
  `command`, `sdk-extensions`, `finish-args`, `subdir`, `sources`, `env`,
  `build-options`) are now top-level keys in `flutpak.yaml`.
  ```yaml
  # before
  manifest:
    app-id: io.github.YourOrg.YourApp
    runtime-version: '25.08'
    finish-args:
      - --share=network

  # after
  app-id: io.github.YourOrg.YourApp
  runtime-version: '25.08'
  finish-args:
    - --share=network
  ```

- **`patches[].strip-trailing-cr` removed** — this key was deprecated in 0.5.0
  in favour of `crlf:`. The alias is no longer recognised; use `crlf: true`.

### Added

- **`flutter.ref` config key** — git ref (tag, branch, or commit SHA) for
  the Flutter SDK. Engine version files (`engine.version`,
  `material_fonts.version`, `gradle_wrapper.version`) are fetched from GitHub
  raw API. No local Flutter install needed for source generation.

- **`flutter_tools/pubspec.lock` auto-fetched** — when `flutter.ref` is set,
  `generate` fetches `packages/flutter_tools/pubspec.lock` from GitHub and
  includes its deps in `generated-sources.json`. No longer needs to be listed
  in `pub.locks`.

- **`foreign-deps:` config key** — local overrides for the remote registry.
  Deep-merged on top before resolution. Shorthand format (no version key)
  resolves from `pubspec.lock`. `sources: []` suppresses a remote entry.

- **`crlf:` on `type: patch` sources** in `foreign-deps:` — normalises the
  patch file to CRLF after download/copy; key is stripped from output JSON.

- **`subdir:` config key** — when the Flutter project lives in a subdirectory
  of the git repo, set `subdir: apps/myapp` in `flutpak.yaml`; `flutpak init`
  emits it on the app module automatically. The generated stamp `cp` commands
  use `$FLATPAK_BUILDER_BUILDDIR` and are unaffected by `subdir:`.

- **Inline modules in `modules:`** — entries can now be either a string path
  to a YAML file or an inline module map in standard Flatpak manifest format:
  ```yaml
  modules:
    - flatpak/modules/bclibc.yml        # file path (existing)
    - name: some-dep                    # inline map (new)
      buildsystem: simple
      sources:
        - type: archive
          url: https://example.com/dep.tar.gz
          sha256: abc123
  ```

- **`FlutterSdkGenerator.dispose()`** — `_ownsClient` pattern; closes the
  internal HTTP client only when it was created internally. Eliminates the
  multi-second hang after `generate` completes.

- **`--flutter` / `-f` flag** on `generate` and `init` — overrides
  `flutter.ref` from config at the CLI level.

- **`flutpak sdk-mod`** — new command replacing `sdk-ext`. Generates a
  standalone Flutter SDK module JSON for `!include` in any manifest. Output:
  `modules/flutter-sdk/flutter-sdk-<version>.json`. Pre-generated JSONs
  shipped in the repository.

### Changed

- **Built-in `shared.sh.patch` updated** — replaced `pub get --offline`
  with `pub upgrade --offline` for more reliable flutter_tools bootstrap.

- **Foreign deps registry deep-merge** — `ForeignDepsRegistry.resolve()` now
  accepts `localForeignDeps: Map<String, dynamic>` instead of
  `overriddenPackages: Set<String>`. Supports both shorthand and versioned
  override formats.

- **`generate` action** — removed `sdk` input, added `flutter-ref` input.
  Flutter SDK is still installed via the `flutter` action for `flutter pub get`
  / `flutter build`; `flutpak generate` itself no longer reads from a local SDK.

## [0.6.1] — 2026-06-08

### Changed

- **`setup-flutter.sh` removed** — the generated manifest now calls
  `flutter pub get --offline` directly instead of going through the
  `setup-flutter.sh` wrapper script. The script was a one-liner with no
  added value; removing it eliminates the `ScriptSource` from the Flutter
  SDK source list and avoids sandbox path issues when the Flutter SDK is
  included as a separate module.

## [0.6.0] — 2026-06-08

### Added

- **`manifest.finish-args`** config key — list of extra `finish-args` entries
  appended to the mandatory Flutter desktop defaults (`--share=ipc`,
  `--socket=fallback-x11`, `--socket=wayland`, `--device=dri`). Duplicates are
  silently dropped, so repeating a mandatory arg is safe.
  ```yaml
  manifest:
    app-id: io.github.YourOrg.YourApp
    finish-args:
      - --filesystem=xdg-documents
      - --filesystem=xdg-download
      - --share=network
  ```

- **Foreign deps registry** — `flutpak generate` now automatically resolves
  known pub packages (e.g. `objectbox_flutter_libs`) from a remote registry
  at `foreign_deps/foreign_deps.json`, compatible with the `flatpak-flutter`
  `foreign_deps.json` format. For each package found in the project's lock
  files the registry provides the full set of flatpak sources (archives and
  patches) needed for an offline Flatpak build. Sources are appended to
  `generated-sources.json`; patch files are downloaded to
  `generated/patches/<path>`.
  - Local `patches:` entries always override the registry for the same package.
  - `--no-foreign-deps` flag skips the registry fetch for offline/air-gapped
    use.
  - `foreign-deps-ref` config key pins the registry fetch to a specific git
    ref (tag, branch, SHA). Defaults to `main`.
  - Uses `~/.cache/flutpak/` as offline fallback when the network is
    unavailable; prints a warning and continues.
  - `foreign_deps/` directory added to the flutpak repository with the
    initial registry (`objectbox_flutter_libs` 5.3.1/5.3.2 and
    `objectbox_sync_flutter_libs` 5.3.1/5.3.2), matching the
    `flatpak-flutter` entries exactly.
  ```yaml
  # Optional — override the git ref used to fetch the registry:
  foreign-deps-ref: v0.5.0
  ```

- **`patches[].use-git` option** in `flutpak.yaml`. When set to `true`, the
  generated flatpak-builder patch source includes `use-git: true`, which causes
  flatpak-builder to apply the patch via `git apply` instead of `patch -p1`.
  This is more robust for patches in git extended format (e.g. produced by
  `git diff`). Compatible with `crlf` (patch is normalised to CRLF before
  `git apply` runs). Mutually exclusive with `options` only.
  ```yaml
  patches:
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
      use-git: true
  ```
- **Known patches for `sqlite3`** (versions 3.0.0 and 3.3.0) added to
  `known-patches/`. Patches `lib/src/hook/assets.dart` and `hook/build.dart`
  to use a predictable download directory (`download-static`) and skip the
  network fetch when the prebuilt library is already present. Requires
  `manifest.sources` entries for the architecture-specific `libsqlite3.so`
  prebuilts — see `known-patches/PATCHES.md` for the full usage snippet.

- **Foreign deps registry expanded** — 12 packages added, mirroring the
  `flatpak-flutter` registry exactly:
  - **`sqlite3`** (2.9.4 empty, 3.0.0, 3.3.0) — prebuilt `libsqlite3.so`
    archives + `assets.dart.patch` / `build.dart.patch` to redirect the hook
    to a predictable offline path.
  - **`sqlite3_flutter_libs`** (0.5.30, 0.5.32, 0.5.34, 0.5.39, 0.5.41,
    0.5.42, 0.6.0 empty) — SQLite source tarballs pre-placed for CMake
    `FetchContent`, one per upstream SQLite release; `CMakeLists.txt.patch`
    disables the network fetch.
  - **`simple_secure_storage_linux`** (0.2.5) — pre-placed `json.tar.xz`
    for the nlohmann/json `FetchContent` dependency; `CMakeLists.txt.patch`
    adds an explicit `URL_HASH` so CMake accepts the cached archive offline.
  - **`audiotags`** (1.4.5), **`flutter_new_pipe_extractor`** (0.1.0),
    **`flutter_webrtc`** (1.3.0), **`fvp`** (0.35.0),
    **`media_kit_libs_linux`** (1.2.1), **`pdfium_flutter`** (0.1.7),
    **`powersync`** (2.1.0), **`printing`** (5.14.2),
    **`sqlcipher_flutter_libs`** (0.6.8) — pre-placed native library
    archives/files; `printing` additionally patches `CMakeLists.txt` to
    disable the pdfium network fetch. All entries copied verbatim from
    `flatpak-flutter`.

### Fixed

- **Foreign deps patch entries** — changed `"use-git": true` to
  `"options": ["--binary"]` in all four `objectbox_flutter_libs` /
  `objectbox_sync_flutter_libs` entries in `foreign_deps/foreign_deps.json`.
  When `use-git: true` is set, flatpak-builder applies the patch via
  `git apply`, which resolves file paths relative to the **git worktree root**
  rather than the `dest` directory. Because the app build directory is itself a
  git checkout, `git apply` looked for `linux/CMakeLists.txt` at the repo root
  (where it does not exist) and failed silently, leaving the patch unapplied and
  causing objectbox to attempt a network download at CMake time. Using
  `"options": ["--binary"]` runs `patch -p1 --binary` instead, which always
  applies relative to `dest` and handles CRLF patches correctly.

### Changed

- **Flutter `shared.sh.patch` moved to `generated-sources.json`** — the
  built-in flutter patch is now emitted into `generated-sources.json` alongside
  pub/SDK archives instead of being injected directly into the generated
  manifest's `sources:` list. Behaviour is identical at build time; the change
  makes the sources file self-contained and consistent with all other source
  entries.

- **Built-in flutter patch written to gitignored `generated/` directory** —
  when no explicit `flutter.patch` path is set in config, `flutpak generate`
  writes the built-in `shared.sh.patch` to
  `<output>/generated/patches/flutter/shared.sh.patch` (inside the gitignored
  `generated/` tree) rather than `<output>/patches/flutter/shared.sh.patch`
  (committed). The committed `patches/` directory is now reserved exclusively
  for user-supplied patch files. `flutpak sources` retains the previous
  behaviour (writes to `<output>/patches/` so the path survives outside a
  `generate` run).

- **Known patch files renamed** from `VERSION/FILENAME.patch` directory layout
  to `VERSION-FILENAME.patch` flat naming (e.g.
  `objectbox_flutter_libs/5.3.1-CMakeLists.txt.patch`), consistent with the
  `flatpak-flutter` `foreign_deps/` naming convention.
- **`objectbox_flutter_libs` and `objectbox_sync_flutter_libs` known patches**
  simplified: dropped the separate `objectbox-c.yml` / `objectbox-sync-c.yml`
  module files and the `OBJECTBOX_PREBUILT_DIR` env var. Patches now use
  `CMAKE_CURRENT_SOURCE_DIR/../objectbox-c` (or `../objectbox-sync-c`) to
  locate the prebuilt archive placed via `manifest.sources` — the same
  self-contained approach as `flatpak-flutter`. No extra module or env var
  needed.

## [0.5.0] — 2026-06-05

### Removed

- **`flathub.json` is no longer generated by `flutpak init`** and no longer
  copied into `generated/` by `flutpak generate`. The file is not required for
  Flathub submission and should be created manually by the app author when needed.

### Breaking Changes

- **`patches[].strip-trailing-cr` renamed to `patches[].crlf`** (boolean).
  The old key is still accepted as a fallback for backward compatibility but is
  considered deprecated. Update your `flutpak.yaml`:
  ```yaml
  # before
  patches:
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
      strip-trailing-cr: true

  # after
  patches:
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
      crlf: true
  ```

### Changed

- **Flutter cache-stamp `cp` commands** in generated templates now use
  `$FLATPAK_BUILDER_BUILDDIR/flutter/...` instead of relative `flutter/...` paths.
  `$FLATPAK_BUILDER_BUILDDIR` is always the module build root (regardless of whether
  `subdir:` is set), so the commands work correctly both for projects at the repo root
  and for Flutter projects that live in a subdirectory of a larger git repository.
  Existing committed templates are unaffected; re-run `flutpak init --force` to
  regenerate them.
- **`--binary` is always added to every `type: patch` entry** in the generated manifest.
  This prevents `patch(1)` from silently stripping `\r` bytes, which was the root cause
  of "Hunk FAILED at N (different line endings)" errors for CRLF target files. Harmless
  for LF patches against LF targets.

### Added

- **`disable-submodules` top-level config option** in `flutpak.yaml`. When set to
  `true`, adds `disable-submodules: true` to the git source entry in the generated
  template manifest, preventing flatpak-builder from cloning git submodules. Defaults
  to `false`, matching flatpak-builder's own default behaviour.
- **LLVM SDK extension is now auto-injected** for Flutter projects. When no `llvm`
  extension is present in `manifest.sdk-extensions`, `flutpak` automatically adds
  `org.freedesktop.Sdk.Extension.llvmXX` based on `runtime-version` (25.08 → llvm20,
  24.08 → llvm19, 23.08 → llvm17; falls back to llvm20 for unknown versions). The
  corresponding paths are also added to `append-path` and `prepend-ld-library-path`.
  No longer need to specify the extension manually in `flutpak.yaml` for Flutter projects.
- **`.gitattributes`** — `*.patch -text` prevents git from normalising line endings in
  patch files on any platform. Without this, git on Windows would re-convert CRLF
  patches to LF on checkout, defeating `--binary`.

### Fixed

- **`--config` with a subdirectory path** (e.g. `--config subdir/flutpak.yaml`) now
  resolves all paths correctly. Previously the config file path was doubled; additionally,
  `output`, lock files, and asset paths were all resolved against CWD instead of the
  config file's directory, causing template-not-found and missing-asset errors when the
  config lived in a subdirectory.
- **yaml_edit crash when injecting `tag`/`commit`** into a fresh template. yaml_edit 2.x
  panics when creating new keys inside a map that is an element of a block sequence. The
  generate command now replaces the whole git source map in one operation instead of
  updating individual keys.
- **Wrapper script installed to wrong path** when `manifest.command` differs from the last
  segment of the app-id (e.g. `command: demo_app` with `app-id: io.example.demo`). The
  generated template and `flutpak init` now install the wrapper to `/app/bin/<command>`
  and the wrapper's `exec` line now calls `$APP/<command>` — matching the Flutter
  executable name rather than the app-id suffix.

- **`strip-trailing-cr: true`** no longer injects a `type: shell` source running
  `sed -i 's/\r//'` on the target file. `flutpak generate` now normalises the patch
  file itself: `crlf: true` → CRLF, `crlf: false` (default) → LF. This keeps the
  generated manifest clean and avoids the `type: shell` pattern that Flathub reviewers
  flag as a code smell.
- Line-ending normalisation is now **deterministic on any host OS** — patches are
  always rewritten to the correct encoding regardless of git `autocrlf` settings or
  platform defaults.


## [0.4.0] — 2026-06-02

### Breaking Changes

- **`prepare` command removed** — replaced by `init` + `generate`.
- **CI pipelines must be updated:** `flutpak generate` must now run before `flatpak-builder`. Patch sources are no longer baked into the template at `init` time; they are injected into the manifest dynamically at `generate` time.

  ```yaml
  # before
  - run: flutpak prepare
  - run: flatpak-builder ... flatpak/<app-id>.yaml

  # after
  - run: flutpak prepare
  - run: flutpak generate
  - run: flatpak-builder ... flatpak/generated/<app-id>.yaml
  ```

- **Config keys converted to kebab-case** (to match the Flatpak manifest format):
  - `app_id` → `app-id`, `runtime_version` → `runtime-version`, `sdk_extensions` → `sdk-extensions`, `build_options` → `build-options`, `append_path` → `append-path`, `prepend_ld_library_path` → `prepend-ld-library-path`
  - `flutter_version_file` → `flutter-version-file`
  - `patches[].dest_subpath` → `dest-subpath`, `patches[].strip_trailing_cr` → `strip-trailing-cr`
- **Fields moved from `manifest` section to root config level:**
  - `repo_url` → `repo-url`, `metainfo_path` → `metainfo-path`, `desktop_entry_path` → `desktop-entry-path`, `icons` → `icons:`
- **`manifest.extra_modules` removed** — use the root `modules:` key instead.
- **`manifest.extra_sources` renamed** to `manifest.sources`.
- **`pub_patches` removed** — use `patches:` only.
- **`patch_path` root key removed** — use `flutter.patch` instead.
- **`finish_args` removed from config.** `ManifestGenerator` now writes sensible Flutter desktop defaults (`--share=ipc`, `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`) into the template at `init`. Edit the template manifest to adjust sandbox permissions.
- **`__FLATPAK_TAG__` and `__FLATPAK_COMMIT__` placeholders removed.** `generate` now sets `tag:` and `commit:` directly on the git source block in the template via `yaml_edit`.

### Added

- **`flutpak init`** — one-time setup: generates the template manifest (`<output>/<app_id>.yml`), `<name>-wrapper.sh`, `flathub.json`, and `.gitignore`; immediately runs `generate`.
- **`flutpak generate [--tag] [--commit]`** — replaces `prepare`; reads the template, validates it against config, substitutes placeholders, copies everything to `<output>/generated/`.
- **`actions/generate`** composite action — installs flutpak, auto-detects Flutter SDK from `FLUTTER_ROOT` or `PATH`, runs `flutpak generate`, validates metainfo, and uploads generated artifacts.
- **`actions/build-flatpak`** composite action — installs `org.flatpak.Builder`, lints the manifest, builds the Flatpak, lints the repo, exports a `.flatpak` bundle. Outputs `bundle`, `arch`, `artifact-url`.
- **`scripts/flatpak-build.sh`** — shared shell library with reusable Flatpak build functions.
- **`patches[].options`** — extra flags forwarded to the `patch(1)` command via the flatpak-builder patch source `options` field.
- **`patches[].strip-trailing-cr`** — when `true`, flutpak converts the patch file to CRLF line endings in `generated/patches/` and adds `--binary` to the patch options, so `patch(1)` applies it cleanly to CRLF target files. Useful for packages with CRLF line endings (e.g. `objectbox_flutter_libs` ≥ 5.3.2).
- **`known-patches/`** — directory with ready-to-use reference patches:
  - `flutter/shared.sh.patch`
  - `objectbox_flutter_libs/5.3.1/CMakeLists.txt.patch`
  - `objectbox_flutter_libs/5.3.2/CMakeLists.txt.patch`
  - `objectbox_flutter_libs/5.3.1/objectbox-c.yml` and `5.3.2/objectbox-c.yml` — ready-to-use Flatpak module files that install `libobjectbox.so` to `/app/lib/`.
- **`manifest.icons:`** — list of entries with `size:` and `path:`; default is a single `256x256` entry (fixes previously hardcoded `512x512`).
- **`manifest.metainfo_path:` / `manifest.desktop_entry_path:`** — overrides for the metainfo XML and `.desktop` source paths.
- Auto-generated `<name>-wrapper.sh` for Flutter projects (sets `LD_LIBRARY_PATH`).
- **Version is now derived at compile time** from the git tag via `--define=version=$(git describe --tags --always)`; `lib/src/version.dart` and `tool/update_version.dart` removed.

### Changed

- Generated output now lives in `<output>/generated/` (gitignored); the template manifest in `<output>/` is committed and edited by hand.
- `generate` validates template fields (`app-id`, `command`, `runtime-version`) against config and errors if they diverge.
- `--tag` only: commit SHA is auto-resolved via `git rev-parse v1.2.3^{}`; `--commit` only or no flags: SHA is written to both `tag:` and `commit:` fields.
- `manifest.command` is now optional — defaults to the last reverse-DNS segment of `app-id`.
- `manifest.repo_url` is auto-detected from `git remote get-url origin` on the first `flutpak init` run.
- `flutter_version_file` defaults to `<output>/flutter.version` for Flutter projects.
- All `${{ inputs.* }}` expansions inside composite action shell steps replaced with `env:` variable declarations to prevent shell injection.
- Built-in patch registry (`_registry`) cleared — known patches are now maintained as reference files in `known-patches/`.
- Template manifest now includes inline guidance comments explaining which sections are safe to edit.

---

### Fixed

- Patch version in `pubspec.lock` is now checked against `version:` in config — `generate` exits with an error on mismatch instead of silently producing a broken manifest.
- Patch subdirectory structure is now preserved in the generated manifest (e.g. `patches/objectbox_flutter_libs/CMakeLists.txt.patch` instead of `patches/CMakeLists.txt.patch`).
- All fields (`options`, `strip_trailing_cr`) are now preserved when resolving patch entries without an explicit `version:`.
- `PubSourcesGenerator` now explicitly closes `http.Client` in a `finally` block — eliminates a multi-second hang after `generate` completes.
- Patch sources are injected into the **generated** manifest at `generate` time, not into the template at `init` time — `dest:` path always matches the current `pubspec.lock`.
- `SdkExtensionGenerator` now uses `FlutterSdkGenerator.readFlutterVersion()` — fixes `PathNotFoundException` crash on Flutter ≥ 3.32 where the flat `version` file was removed.

### Removed

- `prepare` command — replaced by `init` + `generate`.
- `tagPlaceholder` / `commitPlaceholder` constants and `patchManifestPlaceholders` / `injectPatchSources` functions from the public API.
- `tool/update_version.dart` — no longer needed with compile-time `--define=version=`.
- `prepare` and `verify` composite actions — replaced by `setup-flutpak` + `flutpak prepare`.
- `export`, `manifest`, `lint`, `validate` commands — removed; use the official tools directly.
- Metainfo XML generation and `.desktop` generation — removed; maintain files manually in `app/share/`.

### Minimum config

The minimum viable config is now just `app-id`:

```yaml
flutpak:
  manifest:
    app-id: io.github.YourOrg.YourApp
```

All other fields (`command`, `repo-url`, `flutter-version-file`, `pub.locks`, `flutter.sdk`, `output`) are resolved automatically from the environment and git remote.


## [0.4.0-rc.2] - 2026-06-01

### Fixed
- `generate` composite action still called `dart run tool/update_version.dart`
  (deleted in rc.1); now builds with `--define=version=$(git describe)` like
  the other actions.


## [0.4.0-rc.1] - 2026-06-01

### Changed
- `finish_args` removed from config. `ManifestGenerator` now writes a
  sensible Flutter desktop default (`--share=ipc`, `--socket=wayland`,
  `--socket=fallback-x11`, `--device=dri`) directly into the template on
  `init`. Edit the template manifest to add, remove, or adjust sandbox
  permissions — no config change needed.
- `__FLATPAK_TAG__` and `__FLATPAK_COMMIT__` string placeholders removed.
  `generate` now sets `tag:` and `commit:` directly on the git source block in
  the template via `yaml_edit`, so the template no longer needs to carry
  placeholder strings. When `--tag` is omitted, the HEAD SHA is written to both
  fields so `flatpak-builder` can fetch the revision without a release tag.
- `manifest` config section keys converted to kebab-case to match the Flatpak
  manifest format: `app_id` → `app-id`, `runtime_version` → `runtime-version`,
  `sdk_extensions` → `sdk-extensions`, `build_options` → `build-options`,
  `append_path` → `append-path`, `prepend_ld_library_path` →
  `prepend-ld-library-path`.
- `repo_url`, `metainfo_path`, `desktop_entry_path` moved from the `manifest`
  section to the root config level as `repo-url`, `metainfo-path`,
  `desktop-entry-path`. These are flutpak-specific settings, not part of the
  Flatpak manifest schema.
- `manifest.icons` moved to the root config level as `icons:`. Icons are a
  flutpak-specific concept (file path validation, default 256x256 fallback) and
  do not belong in the Flatpak manifest schema.
- `manifest.extra_modules` removed; use the root `modules:` key instead.
- `manifest.extra_sources` renamed to `manifest.sources`.
- Root config keys converted to kebab-case: `flutter_version_file` →
  `flutter-version-file`.
- `patches[].dest_subpath` → `dest-subpath`,
  `patches[].strip_trailing_cr` → `strip-trailing-cr`.
- `pub_patches` key removed; use `patches` only.
- `patch_path` root key removed; use `flutter.patch` instead.
- Version is now derived at compile time from the git tag via
  `--define=version=$(git describe --tags --always)`. The generated
  `lib/src/version.dart` file and `tool/update_version.dart` script are
  removed; `pubspec.yaml` remains the single source of truth for the published
  package version.

### Fixed
- Process hung for a few seconds after `generate complete` due to
  `PubSourcesGenerator`'s `http.Client` never being closed; the client is now
  explicitly closed in a `finally` block after sources are generated.

### Removed
- `tagPlaceholder` / `commitPlaceholder` constants and `patchManifestPlaceholders`
  / `injectPatchSources` functions removed from the public API.
- `tool/update_version.dart` removed; no longer needed with compile-time
  `--define=version=` injection.

### Added
- `known-patches/objectbox_flutter_libs/5.3.1/objectbox-c.yml` and
  `known-patches/objectbox_flutter_libs/5.3.2/objectbox-c.yml` — ready-to-use
  Flatpak module files that install the prebuilt `libobjectbox.so` to `/app/lib/`.
  Copy to `flatpak/modules/objectbox-c.yml` and reference via the `modules:`
  config key. See `known-patches/PATCHES.md` for full instructions.


## [0.4.0-beta.4] - 2026-05-27

### Added
- `patches[].options` config key — extra flags forwarded to the `patch(1)`
  command via the flatpak-builder patch source `options` field.
- `patches[].strip_trailing_cr` config key — when `true`, flutpak injects a
  `type: shell` source before the patch that runs `sed -i 's/\r//'` on the
  target file. Use this when the upstream pub.dev archive ships sources with
  CRLF line endings (e.g. `objectbox_flutter_libs` ≥ 5.3.2); GNU `patch(1)`
  does not reliably handle CRLF/LF mismatches even with `--ignore-whitespace`.
- `known-patches/objectbox_flutter_libs/5.3.2/CMakeLists.txt.patch` — known
  patch for `objectbox_flutter_libs` 5.3.2 (same `OBJECTBOX_PREBUILT_DIR`
  logic as 5.3.1; use with `strip_trailing_cr: true` due to CRLF sources).

### Fixed
- `patches[].options` and `patches[].strip_trailing_cr` were silently dropped
  when `version` was omitted from the patch entry and back-filled from the lock
  file; `resolvePatchEntries` now preserves all fields during version resolution.


## [0.4.0-beta.3] - 2026-05-27

### Added
- `scripts/flatpak-build.sh` — shared shell library with reusable Flatpak build
  functions (`_dbus_run`, `install_flatpak_builder`, `lint_flatpak_manifest`,
  `build_flatpak`, `lint_flatpak_repo`, `export_flatpak_bundle`); sourced by both
  composite actions and local scripts.
- `actions/generate` composite action — installs flutpak, optionally fetches the
  target tag so `--tag` SHA resolution works with `--depth=1` checkouts, auto-detects
  the Flutter SDK path from `FLUTTER_ROOT` or `PATH`, runs `flutpak generate`,
  auto-installs `appstream` and validates metainfo when `metainfo-path` is set,
  and uploads the generated manifest + sources as a workflow artifact.
- `actions/build-flatpak` composite action — installs `org.flatpak.Builder`,
  lints the manifest, builds the Flatpak via `flathub-build`, lints the resulting
  repo, exports a `.flatpak` bundle, and optionally uploads it as a workflow
  artifact. Outputs `bundle`, `arch`, and `artifact-url`.

### Changed
- All `${{ inputs.* }}` expansions inside shell steps in composite actions replaced
  with `env:` variable declarations to prevent shell injection.


## [0.4.0-beta.2] - 2026-05-26

### Fixed
- Patch sources are now injected into the **generated** manifest at `generate`
  time instead of being baked into the template at `init` time. Previously, the
  `dest:` path (e.g. `.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1`)
  was written into the template once and became stale whenever the package
  version changed in `pubspec.lock`. Now the version is resolved from the
  current lock file on every `generate` run.
- Patch subdirectory structure is preserved in the generated manifest. A patch
  at `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch` is now
  correctly referenced as `patches/objectbox_flutter_libs/CMakeLists.txt.patch`
  instead of the bare filename `patches/CMakeLists.txt.patch`.

### Added
- `known-patches/` directory with reference `.patch` files for packages that
  commonly need Flatpak modifications: `flutter/shared.sh.patch` and
  `objectbox_flutter_libs/5.3.1/CMakeLists.txt.patch`. Usage instructions are
  in `known-patches/PATCHES.md`.
- Version mismatch check for project `patches:` entries: `generate` now exits
  with an error when a `version:` pinned in config differs from the version
  resolved from `pubspec.lock`, instead of silently producing a broken manifest.

### Changed
- `ManifestGenerator` no longer accepts or emits `patchEntries`; the template
  manifest intentionally contains no `type: patch` sources.
- The template manifest now includes inline guidance comments explaining which
  sections are safe to edit, which placeholders must not be removed, and that
  patch sources are auto-injected by `generate`.
- The Flutter `shared.sh.patch` is now injected directly into the generated
  manifest's `sources:` section alongside package patches, instead of being
  embedded in `generated-sources.json`. This makes it visible and prevents a
  broken source list when the JSON is regenerated without the patch being
  copied. For pure Dart projects (`--pub-only`) the Flutter patch is skipped
  entirely.
- The built-in Dart patch registry (`_registry`) has been emptied. Known patches
  are now maintained as reference files in `known-patches/` rather than as
  half-working auto-detection logic without shipped patch content. The
  `patches:` config key and all project-level patch support remain unchanged.

### Breaking Changes
- **CI workflows must now run `flutpak generate` before `flatpak-builder`.**
  Previously, patch sources were baked into `generated-sources.json` at `init`
  time, so a committed JSON file was sufficient for CI. Now all patch sources
  (`type: patch`) are injected into the manifest by `flutpak generate` at build
  time. Update your CI pipeline:
  ```yaml
  # before
  - run: flutpak prepare
  - run: flatpak-builder ... flatpak/<app-id>.yaml

  # after
  - run: flutpak prepare
  - run: flutpak generate
  - run: flatpak-builder ... flatpak/generated/<app-id>.yaml
  ```


## [0.4.0-beta.1] - 2026-05-21

### Notes
- This is a beta release. The stable 0.4.0 will follow after testing.
- Patches injection: Currently patches are injected into the template
  manifest during init, but this may cause issues when package versions change.
  The dest path includes the package version
  (e.g., .pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1).
  If the version updates in pubspec.lock, the patch would be applied
  to the wrong directory.
  TODO: Move patch injection to generate phase where we have access
  to current locked versions.

### Added
- `flutpak init` command — one-time setup: generates the template manifest
  (`<output>/<app_id>.yml`), `<name>-wrapper.sh`, `flathub.json`, and
  `.gitignore`; immediately runs `generate` to populate `generated/`
- `flutpak generate [--tag] [--commit]` command — replaces `prepare`; reads the
  template, validates it against config, substitutes placeholders, copies
  everything to `<output>/generated/`
- `manifest.icons:` config list — each entry has `size:` and `path:`; default
  is a single `256x256` entry (fixes previously hardcoded `512x512`); when
  `icons:` key is present a `256x256` entry is required
- `manifest.metainfo_path:` — override for the metainfo XML source path
  (default: `app/share/metainfo/<app_id>.metainfo.xml`)
- `manifest.desktop_entry_path:` — override for the `.desktop` source path
  (default: `app/share/applications/<app_id>.desktop`)
- Auto-generated `<name>-wrapper.sh` in `<output>/` for Flutter projects
  (sets `LD_LIBRARY_PATH` and execs the bundle binary)

### Removed
- `prepare` command — replaced by `init` + `generate`

### Changed
- Generated output now lives in `<output>/generated/` (gitignored via
  auto-generated `.gitignore`); the template manifest in `<output>/` is
  committed and edited by hand
- `generate` validates template fields (`app-id`, `command`, `runtime-version`)
  against config and errors if they diverge
- `generate` errors if `__FLATPAK_TAG__` or `__FLATPAK_COMMIT__` placeholders
  are missing from the template
- Asset files (metainfo, desktop, icons) are validated for existence on both
  `init` and `generate` — missing files are errors, not warnings
- `--tag` and `--commit` flags now work exclusively; passing only `--tag v1.2.3`
  auto-resolves the commit SHA via `git rev-parse v1.2.3^{}`; passing only
  `--commit <sha>` (or nothing) writes the SHA into both `tag:` and `commit:`
  in the manifest so `flatpak-builder` can fetch and build without a release tag;
  previously omitting `--tag` would remove the `tag:` line which broke builds
- `manifest.command` is now optional; defaults to the last reverse-DNS segment of
  `manifest.app_id` (e.g. `io.github.example.myapp` → `myapp`); explicit
  `command:` still accepted and takes precedence; an info message is printed on
  first run when the value is inferred so the user can verify or override it
- `flutter_version_file` now defaults to `<output>/flutter.version` when a Flutter
  SDK is configured (via `flutter.sdk:` or `$FLUTTER_ROOT`); pure-Dart projects
  with no Flutter SDK configured are unaffected (field stays `null`, no warning)
- `manifest.repo_url` is now auto-detected from `git remote get-url origin` on
  the first `flutpak init` run when not set in config; the resolved URL is
  written into the manifest; explicit `repo_url:` still accepted and takes
  precedence; an info message is printed when the URL is inferred; if the project
  has no git remote the field is simply omitted

### Minimum config
The minimum viable config is now just `app_id` + `finish_args`:

```yaml
flutpak:
  manifest:
    app_id: io.github.YourOrg.YourApp
    finish_args:
      - --share=ipc
      - --socket=wayland
      - --device=dri
```

All other fields (`command`, `repo_url`, `flutter_version_file`, `pub.locks`,
`flutter.sdk`, `output`) are resolved automatically from the environment and
git remote.


## [0.3.0] - 2026-05-21

### Added
- `-V` / `--version` global flag — prints `flutpak <version>` and exits;
  `setup-flutpak` action now runs `flutpak --version` to verify the installation
- `tool/update_version.dart` — generator script that reads `version:` from
  `pubspec.yaml` and writes `lib/src/version.dart`; run after every version bump:
  `dart run tool/update_version.dart`; the `setup-flutpak` action and `release.yml`
  run it automatically so `pubspec.yaml` is the single source of truth
- `Makefile` — `make build` (regenerate version + compile binary), `make version`
  (regenerate only), `make test` (run test suite)
- `test/version_test.dart` — enforces that `packageVersion` in `lib/src/version.dart`
  matches `pubspec.yaml`; CI will fail if they diverge

### Fixed
- `setup-flutpak` action: when `version` input is empty, build from
  `$GITHUB_ACTION_PATH` (the ref used in the `uses:` directive) instead of
  cloning `main`; explicit tag/SHA/branch still supported via `version` input
- `prepare`: warn when `flutter_version_file` is set but `$FLUTTER_ROOT` is
  unresolvable instead of silently skipping; no warning emitted for pure-Dart
  projects that do not set `flutter_version_file`
- `release.yml`: regenerate `lib/src/version.dart` (via
  `dart run tool/update_version.dart`) alongside the `pubspec.yaml` version
  bump, so compiled binaries always report the correct release version

### Fixed
- `SdkExtensionGenerator` now uses `FlutterSdkGenerator.readFlutterVersion()`
  instead of reading the `version` file directly; this prevents a
  `PathNotFoundException` crash on Flutter ≥ 3.32 where the flat `version` file
  was removed (falls back to `git describe` then `packages/flutter/pubspec.yaml`)
- `RegistryEntry.versionConstraint` is now evaluated when resolving registry
  patch entries; previously the field was declared but silently ignored, so
  constrained entries were applied to every matched package version
- Pub archive URLs switched from deprecated `pub.dartlang.org` to `pub.dev`
- Fixed duplicate step-5 comment in `FlutterSdkGenerator.generate()`;
  `engine_stamp.json` is now labelled step 6

### Changed
- `FlutterSdkGenerator._readFlutterVersion` renamed to
  `FlutterSdkGenerator.readFlutterVersion` (public static) so that
  `SdkExtensionGenerator` (and external tooling) can reuse the multi-fallback
  version-resolution logic
- `resolvePatchEntries` accepts an optional `registryEntries` parameter to
  allow injecting a custom registry in tests


## [0.2.8] - 2026-05-25
 
### Removed
- `export` command — removed; files can be copied manually if needed
- `manifest` command — removed
- Metainfo XML generation — `manifest.metainfo:` config and `MetainfoGenerator` removed;
  maintain your `<app_id>.metainfo.xml` manually in `app/share/metainfo/`
- `.desktop` file generation — `manifest.desktop:` config and desktop generator removed;
  maintain your `<app_id>.desktop` manually in `app/share/applications/`
- `DesktopConfig`, `MetainfoConfig`, `DeveloperConfig`, `UrlConfig`, `ScreenshotConfig`
  config classes removed
- `replaceMetainfoScreenshots()` / `patchMetainfoReleases()` helpers removed
### Added
- `setup-flutpak` composite action — installs the `flutpak` binary (downloads
  pre-built release or compiles from source); replaces the inline build steps
  that were previously embedded in `prepare` and `verify` actions
### Removed
- `prepare` composite action — removed; use `setup-flutpak` + `flutpak prepare` directly
- `verify` composite action — removed
### Changed
- Generated manifest now installs shared assets directly from the `app/` directory
  tree that must be present in the repository:
  - `app/share/metainfo/<app_id>.metainfo.xml` → `/app/share/metainfo/`
  - `app/share/applications/<app_id>.desktop` → `/app/share/applications/`
  - `app/share/icons/hicolor/512x512/apps/<app_id>.png` → `/app/share/icons/hicolor/512x512/apps/`
- Config simplified: `manifest.metainfo:`, `manifest.desktop:`, `manifest.icons:`
  sections no longer recognised
- `prepare` no longer pins screenshot URLs or patches release dates in metainfo


## [0.2.7] - 2026-05-20

### Added
- `DesktopConfig`: new `comment` field → `Comment=` in `.desktop` file (falls back to
  `metainfo.summary` or pubspec `description` when omitted)
- `DesktopConfig`: new `startup_wm_class` field → `StartupWMClass=` in `.desktop` file
  (defaults to `manifest.command` when omitted)
- `MetainfoConfig`: new `metadata_license` field (default: `MIT`) — controls
  `<metadata_license>` in generated XML
- `MetainfoConfig`: new `project_license` field (default: `MIT`) — controls
  `<project_license>` in generated XML (e.g. set to `GPL-3.0-only` for GPL apps)
- `MetainfoConfig`: new `supports` list — emits
  `<supports><control>…</control></supports>` block
  (e.g. `[pointing, keyboard, touch]`)
- `MetainfoConfig`: new `content_rating_attributes` map — emits
  `<content_attribute id="…">value</content_attribute>` children inside
  `<content_rating>`; when empty a comment placeholder is written instead
- `.desktop` and metainfo generation now fall back to pubspec.yaml `name` /
  `description` when the corresponding config fields are absent

### Fixed
- `$VAR` env placeholders that remain unresolved at runtime (e.g. `$FLUTTER_ROOT`
  not set) now yield `null` instead of the literal string, preventing a
  `PathNotFoundException` crash in `FlutterSdkGenerator`
- Lock file paths containing unresolvable `$VAR` references are silently skipped
  instead of triggering a `⚠ lock file not found: $FLUTTER_ROOT/…` warning
- `output:` directory now controls paths for **all** generated artifacts —
  manifest, `.desktop`, and metainfo — not just `generated-sources.json`


## [0.2.6] - 2026-05-20

### Removed
- `lint` command — use `flatpak run --command=flatpak-builder-lint org.flatpak.Builder`
  directly; wrapping an official tool added complexity without value and
  made it hard to keep up with upstream CLI changes (`--exceptions`,
  `--user-exceptions`, etc.)
- `validate` command — `appstreamcli` is only available on Ubuntu/Debian
  and not universally present in CI environments; call it directly when needed


## [0.2.5] - 2026-05-20

### Fixed
- `lint` command: pass both `--exceptions` and `--user-exceptions` to
  `flatpak-builder-lint`; `--exceptions` is required to activate exception
  filtering — without it `--user-exceptions` has no effect
- `lint` command: use absolute path for `--user-exceptions` so it is
  resolvable inside the Flatpak sandbox regardless of CWD


## [0.2.4] - 2026-05-20

### Fixed
- `lint` command: auto-detect `flathub.json` in the manifest/repo directory and pass
  `--user-exceptions` to `flatpak-builder-lint`, so local exception entries (e.g.
  `appid-url-not-reachable`) are respected without a PR to the central Flathub
  exceptions file


## [0.2.3] - 2026-05-20

### Fixed
- `lint` command: pass `--filesystem=host` to `flatpak run` so the sandboxed
  `flatpak-builder-lint` process can read `flathub.json` from the host filesystem
  (without this the `exceptions` list in `flathub.json` was silently ignored)


## [0.2.2] - 2026-05-20

### Fixed
- `validate` command: switched from `appstream-util` to `appstreamcli`
  (the modern AppStream CLI available as `appstream` package on Debian/Ubuntu 22.04+).
  Added `--explain` (always on) and `--no-net` (on by default) flags.


## [0.2.1] - 2026-05-19

### Added
- `DeveloperConfig` — new `developer:` field in `MetainfoConfig`; generates
  `<developer [id="..."]><name>...</name></developer>` in metainfo XML
  (AppStream 1.0 / Flathub requirement)

### Changed
- Screenshot URL pinning is now config-driven: `replaceMetainfoScreenshots()`
  rebuilds the entire `<screenshots>` block from `metainfo.screenshots:` config
  + `repo_slug` + ref, instead of regex-replacing `/main/` in the existing file.
  Works correctly regardless of what ref the file currently contains.
- `MetainfoGenerator.generate({ref})` bakes the correct ref into screenshot URLs
  at generation time; `main` is used as a fallback when no ref is provided.


## [0.2.0] - 2026-05-19

### Added
- `lint` command — `flatpak-builder-lint` wrapper (requires `org.flatpak.Builder`)
- `export` command — collects manifest, `generated-sources.json`, metainfo, and patches into a ready-to-submit directory
- `validate` command — `appstream-util validate` wrapper for AppStream metainfo
- Metainfo XML generation from `manifest.metainfo:` config (name, summary, description, categories, keywords, URLs, screenshots, OARS content rating)
- `.desktop` file generation from `manifest.desktop:` config
- `prepare --dry-run` / `-n` — prints what would be written without touching any files
- `pin-manifest` composite action: `flutter_version` / `flutter_version_file` inputs (one required), `config`, `validate`, `flutpak_binary`
- `test-action.yml` — CI workflow that builds the binary from source and smoke-tests the action

### Changed
- `output:` config field is now a **directory** (default: `flatpak`); `generated-sources.json` is always written as `<output>/generated-sources.json`
- `--output` CLI flag is now a directory in all sub-commands (`sources`, `pub`, `flutter`, `manifest`)
- All commands resolve paths relative to the config file directory, not CWD
- `pin-manifest` action: replaced `flatpak_dir` input with `config` + `flutter_version`/`flutter_version_file`

### Fixed
- Screenshot URL pinning uses git tag date for deterministic release dates
- `ScreenshotConfig.fromYaml` handles non-Map input safely


## [0.1.1] - 2026-05-19

### Fixed
- Fix/re pin manifest placeholders 


## [0.1.0] - 2026-05-19

### Added

- `prepare` command — one-shot: generates sources, resolves patches, creates/updates
  manifest, pins metainfo screenshot URLs to tag/commit
- Config in `pubspec.yaml` (`flutpak:` section) or standalone `flutpak.yaml`
  (error if both exist)
- Manifest generation with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders
  that CI replaces on each release
- `extra_modules` — include verbatim YAML module files into the manifest
- `extra_sources` — arch-specific verbatim flatpak sources (e.g. prebuilt C libraries)
- `env` at manifest level merged with `build_options.env`
- `flutter_version_file` — writes the Flutter SDK version string to a file for CI
- `.desktop` file generation from `desktop:` config (`name`, `categories`)
- `sdk-extensions` auto-wires LLVM bin/lib paths into `append-path` /
  `prepend-ld-library-path`
- Flutter SDK `bin/` always appended to `append-path` automatically
- Patches registry — `objectbox_flutter_libs` and `sqflite_common_ffi` resolved
  automatically when found in `pubspec.lock`
- Project-level `patches:` config with version auto-resolved from lock file
- Patch paths made relative to the manifest directory for correct flatpak-builder
  resolution
- Retry with exponential back-off (2 s → 4 s → 8 s) on HTTP 429 / 5xx for
  pub.dev API and Flutter SDK artifact downloads
- Warning when `--commit` is not available and `__FLATPAK_COMMIT__` would remain
  in the manifest
- Warning when `extra_modules` file is not found
- Validation of required `manifest.app_id` and `manifest.command` fields with
  clear error messages
- SHA-256 download cache at `~/.cache/flutpak/` to avoid redundant Flutter
  artifact downloads across runs
- `# Generated by flutpak` header in manifest, `.desktop`, and `flutter.version`
  output files
- MIT License

[Unreleased]: https://github.com/o-murphy/flutpak/compare/v0.8.3...HEAD
[0.8.3]: https://github.com/o-murphy/flutpak/compare/v0.8.2...v0.8.3
[0.8.2]: https://github.com/o-murphy/flutpak/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/o-murphy/flutpak/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/o-murphy/flutpak/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/o-murphy/flutpak/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/o-murphy/flutpak/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/o-murphy/flutpak/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/o-murphy/flutpak/compare/v0.6.0
[0.5.0]: https://github.com/o-murphy/flutpak/compare/v0.5.0
[0.4.0]: https://github.com/o-murphy/flutpak/compare/v0.4.0
[0.4.0-rc.2]: https://github.com/o-murphy/flutpak/compare/v0.4.0-rc.2
[0.4.0-rc.1]: https://github.com/o-murphy/flutpak/releases/tag/v0.4.0-rc.1
[0.4.0-beta.4]: https://github.com/o-murphy/flutpak/releases/tag/v0.4.0-beta.4
[0.4.0-beta.3]: https://github.com/o-murphy/flutpak/releases/tag/v0.4.0-beta.3
[0.4.0-beta.2]: https://github.com/o-murphy/flutpak/releases/tag/v0.4.0-beta.2
[0.4.0-beta.1]: https://github.com/o-murphy/flutpak/releases/tag/v0.4.0-beta.1
[0.3.0]: https://github.com/o-murphy/flutpak/releases/tag/v0.3.0
[0.2.8]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.8
[0.2.7]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.7
[0.2.6]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.6
[0.2.5]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.5
[0.2.4]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.4
[0.2.3]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.3
[0.2.2]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.2
[0.2.1]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.1
[0.2.0]: https://github.com/o-murphy/flutpak/releases/tag/v0.2.0
[0.1.1]: https://github.com/o-murphy/flutpak/releases/tag/v0.1.1
[0.1.0]: https://github.com/o-murphy/flutpak/releases/tag/v0.1.0
