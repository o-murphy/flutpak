# flutpak

[![Pub Version](https://img.shields.io/pub/v/flutpak?logo=dart&link=https%3A%2F%2Fpub.dev%2Fpackages%2Fflutpak)](https://pub.dev/packages/flutpak)

A Dart CLI tool that automates Flatpak packaging for Flutter applications.
Analogous to `flutter pub run build_runner build` — describe your config once
in `pubspec.yaml` and let `flutpak prepare` generate everything needed for a
Flathub-compatible offline build.

- **One command** — `flutpak prepare` generates sources, resolves patches, and creates/updates the manifest
- **No Python** — pure Dart, compiles to a single native binary for CI
- **Config in `pubspec.yaml`** — same pattern as `msix_config`, `flutter_native_splash`
- **Manifest generation** — writes `flatpak/<app_id>.yml` with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders that CI patches
- **Patches registry** — known packages (e.g. `objectbox_flutter_libs`) get their patches resolved automatically
- **Retry on transient errors** — pub.dev and Flutter artifact downloads retry on 429/5xx

## Installation

```bash
dart pub global activate flutpak
```

Or compile a native binary (for CI without a Dart SDK):

```bash
git clone --depth 1 https://github.com/o-murphy/flutpak.git /tmp/flutpak_src
cd /tmp/flutpak_src && dart pub get
dart compile exe bin/flutpak.dart -o /tmp/flutpak
```

## Quick start

### 1. Add config to `pubspec.yaml`

```yaml
flutpak:
  output: flatpak
  flutter_version_file: flatpak/flutter.version  # optional

  pub:
    locks:
      - pubspec.lock
      - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock

  flutter:
    sdk: $FLUTTER_ROOT

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

### 2. First run — generate everything

```bash
FLUTTER_ROOT=/path/to/flutter flutpak prepare
```

This creates:
- `flatpak/io.github.YourOrg.YourApp.yml` — manifest with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders
- `flatpak/generated-sources.json` — pub packages + Flutter SDK artifacts
- `flatpak/patches/` — patch files from the built-in registry (if needed)
- `flatpak/flutter.version` — pinned Flutter version string (if `flutter_version_file` set)

**Commit the generated files to git.** The manifest is a generated artifact (like `*.g.dart` from build_runner) that you check in for Flathub review.

### 3. CI: pin tag/commit and regenerate sources

```bash
flutpak prepare \
  --tag "$TAG" \
  --commit "$COMMIT_SHA" \
  --sdk "$FLUTTER_ROOT"
```

This replaces `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` in the manifest and regenerates `generated-sources.json`. Screenshot URLs in `metainfo.xml` are also pinned to the tag/commit.

## Full config reference

Config lives in **one** of two places (error if both exist):

| Location | Key |
|---|---|
| `pubspec.yaml` | `flutpak:` section |
| `flutpak.yaml` | standalone file |

```yaml
flutpak:
  output: flatpak   # output directory for all generated files (default: flatpak)

  flutter_version_file: flatpak/flutter.version  # optional: write Flutter version here

  pub:
    locks:
      - pubspec.lock
      - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock  # $ENV vars are expanded

  flutter:
    sdk: $FLUTTER_ROOT
    patch: flatpak/patches/flutter/shared.sh.patch  # optional: custom shared.sh patch

  patches:                    # project-level patches for pub packages
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
      dest_subpath: linux     # optional: subdir within the pub package root
      # version: 5.3.1        # optional: auto-resolved from pubspec.lock if omitted

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
    env:                                       # build-options env vars (shorthand)
      MY_VAR: value
    build_options:
      append_path: /custom/bin               # appended to PATH
      prepend_ld_library_path: /custom/lib   # prepended to LD_LIBRARY_PATH
      env:                                   # merged with top-level env:
        ANOTHER_VAR: value
    extra_sources:                           # verbatim flatpak sources (arch-specific archives, etc.)
      - type: archive
        only-arches:
          - x86_64
        url: https://github.com/example/lib/releases/download/v1.0/lib-linux-x64.tar.gz
        sha256: abc123...
        dest: lib-prebuilt
        strip-components: 0
      - type: archive
        only-arches:
          - aarch64
        url: https://github.com/example/lib/releases/download/v1.0/lib-linux-aarch64.tar.gz
        sha256: def456...
        dest: lib-prebuilt
        strip-components: 0
    desktop:
      name: Your App           # optional; falls back to metainfo.name
      categories:              # optional; falls back to metainfo.categories
        - Utility
    icons:
      - size: 512x512
        path: assets/icon_512x512.png
    metainfo:
      path: flatpak/io.github.YourOrg.YourApp.metainfo.xml  # optional; default derived from app_id
      repo_slug: YourOrg/YourApp   # screenshot <image> URLs rebuilt from config on every prepare
      # Fields below drive automatic metainfo.xml generation on first run.
      # Generation requires at minimum name + summary.
      name: Your App
      summary: A brief one-liner
      description: |
        First paragraph.

        Second paragraph.
      categories:
        - Education
        - Science
      keywords:
        - yourapp
      url:
        homepage: https://github.com/YourOrg/YourApp
        bugtracker: https://github.com/YourOrg/YourApp/issues
        donation: https://example.com/donate   # optional
      developer:
        id: io.github.YourOrg              # recommended for Flathub (AppStream 1.0)
        name: Your Name
      screenshots:
        - path: docs/screenshots/home.png
        - path: docs/screenshots/settings.png
          default: true                        # marks as type="default"
      content_rating: oars-1.1                 # default
```

## Patches registry

`flutpak` ships a built-in registry of patches for packages that need special
handling inside the Flatpak sandbox. Patches are applied automatically when the
package is found in any of your lock files.

| Package | What the patch does |
|---|---|
| `objectbox_flutter_libs` | Replaces prebuilt binary download with a local objectbox-c archive |
| `sqflite_common_ffi` | Adjusts CMake for sandbox builds |

Project-level `patches:` entries always take priority over registry entries for
the same package.

## Metainfo generation

When `manifest.metainfo.name` and `manifest.metainfo.summary` are set,
`flutpak prepare` generates a valid AppStream XML file on the first run
(see all available fields in the [Full config reference](#full-config-reference) above).

**On subsequent `flutpak prepare --tag v1.2.3 --commit <sha>` runs:**
- Screenshot URLs are pinned from `/main/` to the tag (or commit when no tag)
- The `<release version="..." date="..."/>` entry is updated to the current date

The file is never overwritten once it exists — edit it manually if needed.

Validate the generated file with:
```bash
flutpak validate
```

## Commands

### `prepare` (recommended)

One-shot command — generates sources, resolves patches, creates or updates the
manifest, and pins metainfo screenshot URLs.

```bash
# First run: generate everything from scratch
flutpak prepare

# CI: update placeholders + regenerate sources
flutpak prepare --tag v1.2.3 --commit abc1234567890 --sdk "$FLUTTER_ROOT"
```

| Flag | Description |
|---|---|
| `--tag` | Git tag embedded in the manifest (e.g. `v0.1.14`). Omit to remove the `tag:` line. |
| `--commit` | Full git commit SHA. Defaults to `git rev-parse HEAD`. |
| `-s, --sdk` | Flutter SDK path. Defaults to `$FLUTTER_ROOT`. |
| `--no-sources` | Skip source regeneration (manifest update only). |
| `--pub-only` | Skip Flutter SDK sources, generate only pub packages. |
| `--flutter-only` | Skip pub sources, generate only Flutter SDK artifacts. |
| `-n, --dry-run` | Print what would be done without writing any files. |
| `-c, --config` | Path to config file (default: `flutpak.yaml`). |

**Workflow:**

```
pubspec.yaml  [flutpak: ...]
      ↓
flutpak prepare                    # first run: generates everything
      ↓
flatpak/<app_id>.yml               # manifest with __FLATPAK_TAG__ / __FLATPAK_COMMIT__
flatpak/generated-sources.json     # pub packages + Flutter SDK artifacts
flatpak/patches/                   # patches from registry (if applicable)
      ↓
git commit + push
      ↓
CI: flutpak prepare --tag $TAG --commit $SHA --sdk $FLUTTER_ROOT
      ↓
flatpak-builder build --repo=...
```

### `sources`

Generates `generated-sources.json` combining pub packages and Flutter SDK.

```bash
flutpak sources \
  --lock pubspec.lock \
  --lock "$FLUTTER_ROOT/packages/flutter_tools/pubspec.lock" \
  --sdk "$FLUTTER_ROOT" \
  --output flatpak
```

`generated-sources.json` is always written as `<output>/generated-sources.json`.

| Flag | Description |
|---|---|
| `-l, --lock` | `pubspec.lock` path (repeatable, `$ENV` expanded) |
| `-s, --sdk` | Flutter SDK path |
| `-o, --output` | Output directory (default: `flatpak`) |
| `--pub-only` | Skip Flutter SDK sources |
| `--flutter-only` | Skip pub sources |

### `pub`

Generates sources for pub packages only.

```bash
flutpak pub --lock pubspec.lock --output flatpak
```

### `flutter`

Generates sources for Flutter SDK artifacts only.

```bash
flutpak flutter --sdk "$FLUTTER_ROOT" --output flatpak
```

### `sdk-ext`

Generates a Flathub SDK Extension manifest (`org.freedesktop.Sdk.Extension.flutter3`)
to share the Flutter SDK across multiple apps on the same machine.

```bash
flutpak sdk-ext \
  --sdk "$FLUTTER_ROOT" \
  --runtime-version 25.08 \
  --output org.freedesktop.Sdk.Extension.flutter3.json
```

### `validate`

Validates the AppStream metainfo file using `appstream-util`.

```bash
# Auto-detect from config
flutpak validate

# Explicit path
flutpak validate --metainfo flatpak/io.github.YourOrg.YourApp.metainfo.xml

# Stricter checks
flutpak validate --pedantic
```

| Flag | Description |
|---|---|
| `-m, --metainfo` | Path to metainfo XML (auto-detected from config if omitted). |
| `--pedantic` | Pass `--pedantic` to `appstream-util` for stricter checks. |
| `-c, --config` | Path to config file. |

Install `appstream-util`:
```bash
sudo apt install appstream   # Debian/Ubuntu
sudo dnf install appstream   # Fedora
```

### `export`

Copies all files needed for a Flathub submission into a single directory:
`<app_id>.yml`, `generated-sources.json`, `<app_id>.metainfo.xml` (if present),
and `patches/`.

```bash
# Default output dir: flatpak-export/
flutpak export

# Custom output dir
flutpak export --out /tmp/my-submission
```

| Flag | Description |
|---|---|
| `-o, --out` | Output directory (default: `flatpak-export/`). |
| `-m, --manifest` | Path to manifest YAML (auto-detected if omitted). |
| `-c, --config` | Path to config file. |

`generated-sources.json` is mandatory — export exits with an error if it does not
exist. Run `flutpak prepare` first.

### `manifest`

Updates version-related fields in an existing manifest from `pubspec.yaml`.

```bash
flutpak manifest --manifest flatpak/io.github.YourOrg.YourApp.yml
```

## CI/CD integration

### GitHub Actions — composite action (recommended)

The `pin-manifest` composite action handles Flutter SDK setup, binary download,
and `flutpak prepare` in one step. Add it to your release workflow:

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Pin Flatpak manifest
        uses: o-murphy/flutpak/.github/actions/pin-manifest@main
        with:
          tag_name: ${{ github.ref_name }}        # e.g. v1.2.3
          flutter_version_file: flatpak/flutter.version  # committed version file
          # flutter_version: stable               # or explicit version
          # config: flutpak.yaml                  # default: auto-detected
          # validate: 'true'                      # run flutpak validate (default)
```

| Input | Description |
|---|---|
| `tag_name` | Tag to embed in the manifest (required) |
| `flutter_version` | Flutter SDK version (e.g. `stable`, `3.41.9`) |
| `flutter_version_file` | Path to committed version file (one of these two required) |
| `commit` | Commit SHA (default: resolved from tag) |
| `config` | Path to config file (default: auto-detected from CWD) |
| `validate` | Run `flutpak validate` after prepare (default: `true`) |
| `flutpak_version` | flutpak release tag to download (default: latest) |
| `cache` | Cache Flutter SDK between runs (default: `true`) |

### GitHub Actions — manual

```yaml
      - name: Build flutpak
        run: |
          git clone --depth 1 https://github.com/o-murphy/flutpak.git /tmp/flutpak_src
          cd /tmp/flutpak_src && dart pub get
          dart compile exe bin/flutpak.dart -o /tmp/flutpak

      - name: Prepare Flatpak sources and manifest
        run: |
          REF_TYPE="${{ github.ref_type }}"
          TAG=""
          if [ "$REF_TYPE" = "tag" ]; then TAG="${{ github.ref_name }}"; fi
          /tmp/flutpak prepare \
            --tag "$TAG" \
            --commit "${{ github.sha }}" \
            --sdk "$FLUTTER_ROOT"
```

## Why include `flutter_tools/pubspec.lock`?

Before any `flutter` command runs, the Flutter tooling bootstraps itself by running
`pub get` inside `packages/flutter_tools/`. This requires flutter_tools dependencies
to be present in the offline pub cache.

Pass both lock files so the generated sources cover the app **and** the tool:

```yaml
pub:
  locks:
    - pubspec.lock
    - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock
```

When the same package appears at different versions (e.g. `yaml 3.1.2` in the app
and `yaml 3.1.3` in flutter_tools), both versions are included — deduplication is
by `(name, version)` pair.

## How it works

### Pub packages

For each hosted package, `flutpak` fetches the SHA-256 from the pub.dev API and
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

Both entries are required: `pub get --offline` checks the hash file and fails if
it's missing even when the archive is present.

### Flutter SDK artifacts

Reads version files from a local Flutter install (`bin/internal/engine.version`, etc.)
and constructs download URLs for each artifact (Dart SDK, engine binaries, fonts,
Gradle wrapper). SHA-256 checksums are cached in `~/.cache/flutpak/` by URL hash to
avoid redundant downloads across runs.

Two extra entries are always added:

- **`sky_engine/pubspec.yaml` (inline)** — `packages/sky_engine/` was removed from
  the Flutter git tree in Flutter 3.x. Written inline so `pub get --offline` resolves it.

- **`shared.sh.patch`** — Flutter's bootstrap script runs `pub upgrade` (requires
  network). The built-in patch replaces it with `pub get --offline`. Written to
  `flatpak/patches/flutter/shared.sh.patch` next to the output file.

## License

MIT
