# flatpak_gen

A Dart CLI tool that automates Flatpak packaging for Flutter/Dart applications.
Analogous to `flutter pub run build_runner build` — describe your Flatpak config once
in `pubspec.yaml` and let `flatpak_gen prepare` generate everything.

- **One command** — `flatpak_gen prepare` generates sources, resolves patches, and creates/updates the manifest
- **No Python dependency** — pure Dart, compiles to a single native binary
- **Config in `pubspec.yaml`** — same pattern as `msix_config`, `flutter_native_splash`
- **Manifest generation** — writes `flatpak/<app_id>.yml` with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders that CI patches
- **Patches registry** — known packages (e.g. `objectbox_flutter_libs`) get their patches resolved automatically

## Installation

```bash
dart pub global activate flatpak_gen
```

Or compile a native binary for CI:

```bash
git clone --depth 1 https://github.com/o-murphy/flutter_flatpak_gen.git /tmp/flatpak_gen_src
cd /tmp/flatpak_gen_src && dart pub get
dart compile exe bin/flatpak_gen.dart -o /tmp/flatpak_gen
```

## Quick start

### 1. Add config to `pubspec.yaml`

```yaml
flatpak_gen:
  output: flatpak/generated-sources.json

  pub:
    locks:
      - pubspec.lock
      - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock

  flutter:
    sdk: $FLUTTER_ROOT
    patch: patches/flutter/shared.sh.patch   # optional custom patch

  manifest:
    app_id: io.github.YourOrg.YourApp
    runtime_version: "25.08"
    command: yourapp
    repo_url: https://github.com/YourOrg/YourApp.git
    finish_args:
      - --share=ipc
      - --socket=wayland
      - --device=dri
    icons:
      - size: 512x512
        path: assets/icon_512x512.png
    metainfo:
      path: flatpak/io.github.YourOrg.YourApp.metainfo.xml
      repo_slug: YourOrg/YourApp
```

### 2. Generate everything (first run)

```bash
FLUTTER_ROOT=/path/to/flutter flatpak_gen prepare
```

This creates:
- `flatpak/io.github.YourOrg.YourApp.yml` — manifest with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders
- `flatpak/generated-sources.json` — pub packages + Flutter SDK artifacts
- `flatpak/patches/` — patch files from the built-in registry (if applicable)

Commit the generated files to git. The manifest is the **artifact of generation**, like `*.g.dart` from build_runner.

### 3. CI: patch placeholders and regenerate sources

```bash
flatpak_gen prepare \
  --tag "$TAG" \
  --commit "$COMMIT_SHA" \
  --sdk "$FLUTTER_ROOT"
```

This updates `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` in the manifest and regenerates `generated-sources.json`.

## Config

Config lives in **one** of two places (error if both exist):

| Location | Key |
|---|---|
| `pubspec.yaml` | `flatpak_gen:` section |
| `flatpak_gen.yaml` | top-level file |

### Full config reference

```yaml
flatpak_gen:
  output: flatpak/generated-sources.json   # generated-sources output path

  pub:
    locks:
      - pubspec.lock
      - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock  # $ENV expanded

  flutter:
    sdk: $FLUTTER_ROOT
    patch: flatpak/patches/flutter/shared.sh.patch  # optional custom shared.sh patch

  patches:                           # project-level patches (applied to pub packages)
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
      dest_subpath: linux            # optional: patch relative to package subdir

  manifest:
    app_id: io.github.YourOrg.YourApp
    runtime_version: "25.08"
    sdk_extensions:
      - org.freedesktop.Sdk.Extension.llvm20   # auto-adds llvm bin/lib to PATH
    command: yourapp
    repo_url: https://github.com/YourOrg/YourApp.git
    finish_args:
      - --share=ipc
      - --socket=fallback-x11
      - --socket=wayland
      - --device=dri
    extra_modules:
      - flatpak/modules/some-native-dep.yml    # included verbatim in modules list
    build_options:
      append_path: /custom/bin
      env:
        MY_VAR: value
    icons:
      - size: 512x512
        path: assets/icon_512x512.png
    screenshots:
      - path: docs/screenshots/home.png
      - path: docs/screenshots/settings.png
    metainfo:
      path: flatpak/io.github.YourOrg.YourApp.metainfo.xml
      repo_slug: YourOrg/YourApp   # screenshot URLs pinned to tag/commit on prepare
```

## Patches registry

`flatpak_gen` ships a built-in registry of patches for packages that need special
handling to build inside the Flatpak sandbox. Patches are applied automatically if
the package is found in any of your lock files.

| Package | What the patch does |
|---|---|
| `objectbox_flutter_libs` | Replaces prebuilt download with local objectbox-c binary |
| `sqflite_common_ffi` | Adjusts CMake for sandbox builds |

To override a registry entry or add custom patches, use the `patches:` section in
your config. Project-level patches always take priority over the registry.

## Commands

### `prepare` (recommended)

One-shot command: generates sources, resolves patches, creates or updates the manifest,
and pins metainfo screenshot URLs to the given tag/commit.

```bash
# First run: generate everything from scratch
flatpak_gen prepare

# CI: update placeholders + regenerate sources
flatpak_gen prepare --tag v1.2.3 --commit abc1234567890
```

| Flag | Description |
|---|---|
| `--tag` | Git tag embedded in manifest (e.g. `v0.1.14`). Omit to remove the `tag:` line. |
| `--commit` | Full git commit SHA. Defaults to `git rev-parse HEAD`. |
| `-s, --sdk` | Flutter SDK path. Defaults to `$FLUTTER_ROOT`. |
| `--no-sources` | Skip source regeneration (manifest update only). |
| `--pub-only` | Skip Flutter SDK sources. |
| `--flutter-only` | Skip pub sources. |
| `-c, --config` | Config file (default: `flatpak_gen.yaml`). |

**Workflow:**

```
pubspec.yaml [flatpak_gen: ...]
       ↓
flatpak_gen prepare            # first run: generates everything from scratch
       ↓
flatpak/<app_id>.yml           # manifest with __FLATPAK_TAG__ / __FLATPAK_COMMIT__
flatpak/generated-sources.json # pub + flutter SDK sources
flatpak/patches/               # patches from registry (if applicable)
       ↓
git commit + push
       ↓
CI: flatpak_gen prepare --tag $TAG --commit $SHA   # patches placeholders + regen sources
       ↓
flatpak-builder build
```

### `sources`

Generates `generated-sources.json` combining pub packages and Flutter SDK artifacts.

```bash
flatpak_gen sources \
  --lock pubspec.lock \
  --lock $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock \
  --sdk $FLUTTER_ROOT \
  --output flatpak/generated-sources.json
```

| Flag | Description |
|---|---|
| `-l, --lock` | `pubspec.lock` paths (repeatable, `$ENV` expanded) |
| `-s, --sdk` | Flutter SDK path |
| `-o, --output` | Output JSON file |
| `--pub-only` | Skip Flutter SDK sources |
| `--flutter-only` | Skip pub sources |

### `pub`

Generates sources for pub packages only.

```bash
flatpak_gen pub --lock pubspec.lock --output flatpak/pub-sources.json
```

### `flutter`

Generates sources for Flutter SDK artifacts only.

```bash
flatpak_gen flutter --sdk $FLUTTER_ROOT --output flatpak/flutter-sources.json
```

### `sdk-ext`

Generates a Flathub SDK Extension manifest (`org.freedesktop.Sdk.Extension.flutter3`)
to share the Flutter SDK across multiple Flatpak apps.

```bash
flatpak_gen sdk-ext \
  --sdk $FLUTTER_ROOT \
  --runtime-version 25.08 \
  --output org.freedesktop.Sdk.Extension.flutter3.json
```

### `manifest`

Updates `version:` in an existing manifest from `pubspec.yaml`.

```bash
flatpak_gen manifest --manifest flatpak/io.github.YourOrg.YourApp.yml
```

## CI/CD integration

### GitHub Actions

```yaml
      - name: Build flatpak_gen
        run: |
          git clone --depth 1 \
            https://github.com/o-murphy/flutter_flatpak_gen.git /tmp/flatpak_gen_src
          cd /tmp/flatpak_gen_src && dart pub get
          dart compile exe bin/flatpak_gen.dart -o /tmp/flatpak_gen

      - name: Prepare Flatpak sources and manifest
        run: |
          COMMIT=$(git rev-parse HEAD)
          REF_TYPE="${{ github.ref_type }}"
          TAG=""
          if [ "$REF_TYPE" = "tag" ]; then TAG="${{ github.ref_name }}"; fi
          /tmp/flatpak_gen prepare \
            --tag "$TAG" \
            --commit "$COMMIT" \
            --sdk "$FLUTTER_ROOT"
```

## Why include `flutter_tools/pubspec.lock`?

Before any `flutter` command runs, the Flutter tool bootstraps itself by running
`pub get` inside `flutter/packages/flutter_tools/`. This requires flutter_tools
dependencies to already be in the offline pub cache.

Pass both lock files so the generated sources cover both the app and the tool:

```bash
--lock pubspec.lock
--lock $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock
```

When the same package appears at different versions (e.g. `json_annotation 4.8.x`
in the app vs `4.9.0` in flutter_tools), both versions are included — deduplication
is by `(name, version)` pair.

## How it works

### Pub packages

For each hosted package, the tool calls the pub.dev API for the SHA-256 hash and
generates two flatpak source entries:

```json
[
  {
    "type": "archive",
    "url": "https://pub.dartlang.org/packages/yaml/versions/3.1.2.tar.gz",
    "sha256": "abc123...",
    "dest": ".pub-cache/hosted/pub.dev/yaml-3.1.2",
    "strip-components": 0
  },
  {
    "type": "inline",
    "contents": "abc123...",
    "dest": ".pub-cache/hosted-hashes/pub.dev",
    "dest-filename": "yaml-3.1.2.sha256"
  }
]
```

Both are required: `pub get --offline` checks for the hash file and fails if it is
missing even when the archive is present.

### Flutter SDK artifacts

Reads version files from a local Flutter install and constructs download URLs for
each artifact (Dart SDK, engine, fonts, Gradle wrapper, etc.). SHA-256 checksums
are cached in `~/.cache/flatpak_gen/` keyed by URL.

Two extra entries are always added:

- **`sky_engine/pubspec.yaml` (inline)** — `packages/sky_engine/` was removed from
  the Flutter git tree in Flutter 3.x. Written inline so `pub get --offline` can
  resolve it without network.

- **`shared.sh.patch`** — Flutter's `shared.sh` bootstraps with `pub upgrade` (requires
  network). The built-in patch replaces it with `pub get --offline`. Written to
  `patches/flutter/shared.sh.patch` next to the output file.

## License

MIT
