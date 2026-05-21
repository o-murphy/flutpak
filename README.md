# flutpak

[![Pub Version](https://img.shields.io/pub/v/flutpak?logo=dart&link=https%3A%2F%2Fpub.dev%2Fpackages%2Fflutpak)](https://pub.dev/packages/flutpak)

A Dart CLI tool that automates Flatpak packaging for Flutter applications.
Analogous to `flutter pub run build_runner build` — describe your config once
in `pubspec.yaml` and let `flutpak prepare` generate everything needed for a
Flathub-compatible offline sandboxed build.

- **One command** — `flutpak prepare` generates sources, resolves patches, and creates/updates the manifest
- **No Python** — pure Dart, compiles to a single native binary for CI
- **Config in `pubspec.yaml`** — same pattern as `msix_config`, `flutter_native_splash`
- **Manifest generation** — writes `flatpak/<app_id>.yml` with `__FLATPAK_TAG__` / `__FLATPAK_COMMIT__` placeholders that CI patches
- **Patches registry** — known packages (e.g. `objectbox_flutter_libs`) get their patches resolved automatically
- **Retry on transient errors** — pub.dev and Flutter artifact downloads retry on 429/5xx

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Step-by-step setup](#step-by-step-setup)
   - [Step 1 — Add config](#step-1--add-config-to-pubspecyaml)
   - [Step 2 — Prepare the project structure](#step-2--prepare-the-project-structure)
   - [Step 3 — First run](#step-3--first-run-generate-everything)
   - [Step 4 — Customize the manifest](#step-4--customize-the-generated-manifest)
   - [Step 5 — CI: pin tag/commit on each release](#step-5--ci-pin-tagcommit-on-each-release)
   - [Step 6 — Submit to Flathub](#step-6--submit-to-flathub)
3. [Full config reference](#full-config-reference)
4. [Manifest lifecycle](#manifest-lifecycle)
5. [Commands](#commands)
6. [CI/CD integration](#cicd-integration)
7. [Validating and building locally](#validating-and-building-locally)
8. [Why include `flutter_tools/pubspec.lock`?](#why-include-flutter_toolspubspeclock)
9. [How it works](#how-it-works)

---

## Prerequisites

| Requirement | When needed | Notes |
|---|---|---|
| **Linux** | Always | `flutpak` targets Linux only |
| **git** | Always | Version detection and commit-hash resolution |
| **Internet access** | `prepare` / `sources` / `flutter` | Downloads from `pub.dev` and `storage.googleapis.com` |
| **Flutter SDK** | Flutter projects | Path via `$FLUTTER_ROOT` or `--sdk`; pure-Dart projects can omit this |
| **Dart SDK** | Building from source only | Not required when using a pre-built binary |
| **flatpak-builder** | Local Flatpak builds | Only needed when you actually build the Flatpak, not during `flutpak prepare` |

---

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

---

## Step-by-step setup

### Step 1 — Add config to `pubspec.yaml`

Add a `flutpak:` section to your app's `pubspec.yaml` (or create a standalone
`flutpak.yaml` — but not both):

```yaml
flutpak:
  output: flatpak                              # directory for all generated files
  flutter_version_file: flatpak/flutter.version  # optional — records the Flutter version

  pub:
    locks:
      - pubspec.lock
      - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock  # include flutter_tools deps

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
```

See [Full config reference](#full-config-reference) for all options.

---

### Step 2 — Prepare the project structure

The generated manifest installs app assets from a fixed `app/` directory in
your repository root.  Create these files before running `flutpak prepare`:

```
app/
└── share/
    ├── applications/
    │   └── <app_id>.desktop          # XDG desktop entry
    ├── icons/
    │   └── hicolor/
    │       └── 512x512/
    │           └── apps/
    │               └── <app_id>.png  # 512×512 application icon
    └── metainfo/
        └── <app_id>.metainfo.xml     # AppStream metainfo
```

> **Note:** The `app/` source directory is fixed in the generated manifest.
> After the initial generation you can manually edit the manifest to point to
> a different path; only the `tag:` and `commit:` lines are updated
> automatically on subsequent `flutpak prepare` runs.
> For questions about what files belong in the share directory and their required
> format, see the [Flathub app-author docs](https://docs.flathub.org/docs/for-app-authors/submission).

These files are read directly from your git source tree during the Flatpak
build. `flutpak` does not generate them — maintain them manually.

**Minimal `<app_id>.desktop`:**
```ini
[Desktop Entry]
Name=Your App
Exec=yourapp
Icon=io.github.YourOrg.YourApp
Type=Application
Categories=Utility;
```

**Minimal `<app_id>.metainfo.xml`:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>io.github.YourOrg.YourApp</id>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <name>Your App</name>
  <summary>Short one-line description</summary>
  <releases>
    <release version="0.1.0" date="2025-01-01"/>
  </releases>
</component>
```

---

### Step 3 — First run: generate everything

```bash
FLUTTER_ROOT=/path/to/flutter flutpak prepare
```

This creates:

```
flatpak/
├── <app_id>.yml               # manifest template (with __FLATPAK_TAG__ placeholders)
├── generated-sources.json     # pub packages + Flutter SDK artifacts
├── patches/
│   └── flutter/
│       └── shared.sh.patch    # built-in offline patch for Flutter bootstrap
└── flutter.version            # pinned Flutter version (if flutter_version_file set)
```

**Commit all generated files to git.** The manifest is a template artifact
(analogous to `*.g.dart` from build_runner) that Flathub reviewers inspect.

---

### Step 4 — Customize the generated manifest

After the first run, open `flatpak/<app_id>.yml` and review it.  You can
freely edit everything in this file — it will **not** be overwritten on the
next `flutpak prepare` run.

The **only lines** that `flutpak prepare --tag ... --commit ...` updates
automatically are the `tag:` and `commit:` values in the app git source block
(the one marked `disable-submodules: true`).  Everything else is yours to edit:

| Section | Safe to edit? |
|---|---|
| `finish-args:` | Yes |
| `build-commands:` | Yes |
| `build-options:` (env, PATH) | Yes |
| `sdk-extensions:` | Yes |
| `modules:` (extra modules) | Yes |
| `sources:` (extra archives, patches) | Yes |
| `app/` directory in install commands | Yes — change to any path you need |
| `tag:` / `commit:` in the app git source | **Updated automatically by flutpak** |

Common customisations:

- Add a `flathub.json` exception for lint rules (see [Step 6](#step-6--submit-to-flathub))
- Add extra build dependencies as modules before the app module
- Adjust `finish-args` for Wayland/X11 fallback, filesystem permissions, etc.
- Change the `app/` prefix in `install` commands if your repo uses a different layout

---

### Step 5 — CI: pin tag/commit on each release

On every release, regenerate sources and pin the tag:

```bash
flutpak prepare \
  --tag "$TAG" \
  --commit "$COMMIT_SHA" \
  --sdk "$FLUTTER_ROOT"
```

This updates the manifest's `tag:` and `commit:` lines and rewrites
`generated-sources.json` with fresh checksums.

Using the [setup-flutpak](#github-actions--setup-flutpak-action-recommended) composite action handles Flutter
setup and binary download automatically.

---

### Step 6 — Submit to Flathub

A Flathub submission is a PR to the app's dedicated Flathub repository.
The repository must contain these files at its root:

```
<flathub-repo>/
├── <app_id>.yml               # pinned manifest (tag + commit set)
├── generated-sources.json     # pub + Flutter SDK sources
├── flathub.json               # Flathub build metadata (see below)
└── patches/
    └── flutter/
        └── shared.sh.patch    # offline patch for Flutter bootstrap
```

The CI example in this README uploads these as a `flathub-submission-*`
artifact on tag-triggered builds — download it and copy the contents into
your Flathub repository.

**`flathub.json`** lives in the root of your Flathub repository alongside
the manifest.  Keep a copy in `flatpak/flathub.json` in your app's repo so it
is picked up by the CI artifact upload.  Minimal example:

```json
{
  "only-arches": ["x86_64", "aarch64"]
}
```

Common fields:

| Field | Description |
|---|---|
| `only-arches` | Architectures Flathub should build for |
| `end-of-life` | Mark the app as end-of-life with a message |
| `end-of-life-rebase` | Suggest a replacement app ID |

For all `flathub.json` options and full submission requirements — including
what the `app/share/` tree must contain, required metainfo fields, icon
specifications, and the review process — see the
[Flathub app-author documentation](https://docs.flathub.org/docs/for-app-authors/submission).

Before opening the PR, validate locally:

```bash
# 1. Validate metainfo
appstreamcli validate --explain --no-net app/share/metainfo/<app_id>.metainfo.xml

# 2. Lint the manifest
dbus-run-session flatpak run --filesystem=host \
  --command=flatpak-builder-lint org.flatpak.Builder \
  --exceptions manifest flatpak/<app_id>.yml

# 3. Build
dbus-run-session flatpak run --command=flathub-build \
  org.flatpak.Builder flatpak/<app_id>.yml
```

See [Validating and building locally](#validating-and-building-locally) for the full workflow.

---

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
```

---

## Manifest lifecycle

The generated manifest goes through two phases:

```
Phase 1 — Template (after first `flutpak prepare`)

  flatpak/<app_id>.yml contains:
    tag: __FLATPAK_TAG__
    commit: __FLATPAK_COMMIT__
    disable-submodules: true

  Commit this file to git — it's the starting point for Flathub review.


Phase 2 — Pinned (after `flutpak prepare --tag vX.Y.Z --commit SHA`)

  flatpak/<app_id>.yml becomes:
    tag: v0.1.15
    commit: abc1234567890abcdef...
    disable-submodules: true

  Commit the pinned manifest + regenerated generated-sources.json.
  These are the files you submit in the Flathub PR.
```

On each subsequent release, run `flutpak prepare --tag ... --commit ...` again.
Only the `tag:` and `commit:` lines change; everything else you edited manually
is preserved.

---

## Patches registry

`flutpak` ships a built-in registry of patches for packages that need special
handling inside the Flatpak sandbox. Patches are applied automatically when the
package is found in any of your lock files **and** a patch file exists in
`<output>/patches/`.

| Package | What the patch does |
|---|---|
| `objectbox_flutter_libs` | Replaces prebuilt binary download with a local objectbox-c archive |
| `sqflite_common_ffi` | Adjusts CMake for sandbox builds |

Registry entries may specify a `versionConstraint` (semver range) to limit
which package versions the patch applies to.  Project-level `patches:` entries
always take priority over registry entries for the same package.

---

## Commands

### `prepare` (recommended)

One-shot command — generates sources, resolves patches, and creates or updates the manifest.

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

---

## CI/CD integration

### `--tag` and `--commit` — test builds vs. releases

The behaviour of `--tag` and `--commit` differs between test/PR builds and
official releases:

| Scenario | `--tag` | `--commit` | Result in manifest |
|---|---|---|---|
| **PR / test build** | omit (or pass the commit SHA) | full commit SHA | no `tag:` line; `commit:` pinned to SHA |
| **Release** | version tag, e.g. `v1.2.3` | full commit SHA | `tag: v1.2.3` + `commit:` pinned |

```bash
# PR / test build — no tag, commit only
flutpak prepare \
  --commit "$(git rev-parse HEAD)" \
  --sdk "$FLUTTER_ROOT"

# Release — tag + commit
flutpak prepare \
  --tag "v1.2.3" \
  --commit "$(git rev-parse HEAD)" \
  --sdk "$FLUTTER_ROOT"
```

Flatpak manifests submitted to Flathub **must** have both `tag:` and `commit:`
set to a specific release tag.  Test builds without a tag are useful for local
validation and PR artifacts.

---

### GitHub Actions — composite actions

The flutpak repository ships two composite actions for use in your workflows.

#### `setup-flutpak`

Clones the `flutpak` repository, compiles the binary from source, and adds it
to `PATH`.  Use it before any `flutpak` commands:

```yaml
      - name: Set up flutpak
        uses: o-murphy/flutpak/.github/actions/setup-flutpak@main
        # with:
        #   version: v0.2.8        # pin to a specific release tag (default: latest)
        #   install_dir: /usr/local/bin   # default
```

| Input | Description | Default |
|---|---|---|
| `version` | Release tag, commit SHA, or branch to compile | latest release |
| `install_dir` | Directory where the `flutpak` binary is placed | `/usr/local/bin` |

#### `flutter`

Installs the Flutter SDK with `runner.arch`-aware caching.  Unlike
`subosito/flutter-action`, the cache key includes `runner.arch`, which makes
it work correctly on `ubuntu-24.04-arm` runners — the upstream action has not
fixed this.

```yaml
      - name: Set up Flutter
        uses: o-murphy/flutpak/.github/actions/flutter@main
        with:
          flutter-version: "3.41.9"   # or read from flatpak/flutter.version
          cache: true                 # default
```

| Input | Description | Default |
|---|---|---|
| `flutter-version` | Version tag, `stable`, or `beta` | `stable` |
| `cache` | Cache the SDK between runs | `true` |

| Output | Description |
|---|---|
| `flutter-path` | Absolute path to the installed Flutter SDK |

---

### Full build workflow example

The example below mirrors a real-world workflow that:

- Runs on `pull_request` (both amd64 and arm64) and on `workflow_call` /
  `workflow_dispatch` (single arch)
- Installs Flutter via the bundled `flutter` action, which caches correctly on
  both `x86_64` and `aarch64` runners
- Passes the commit SHA as `--tag` for PR builds and the git tag for releases
- Caches `org.flatpak.Builder` and `.flatpak-builder/downloads` between runs
- Exports a `.flatpak` bundle as a workflow artifact
- Uploads a ready-to-submit Flathub artifact (manifest + sources + patches +
  `flathub.json`) on tag-triggered builds only

```yaml
name: Build Flatpak

on:
  pull_request:
    paths:
      - "app/**"
      - "lib/**"
      - "linux/**"
      - "flatpak/**"
      - "pubspec.yaml"
  workflow_call:
    inputs:
      arch:
        description: "Target architecture"
        required: true
        type: string   # amd64 | arm64
      build_name:
        description: "Version name override"
        required: false
        type: string
        default: ""
      retention_days:
        required: false
        type: number
        default: 2
    outputs:
      artifact_name:
        value: ${{ jobs.build.outputs.artifact_name }}
      artifact_url:
        value: ${{ jobs.build.outputs.artifact_url }}
  workflow_dispatch:
    inputs:
      arch:
        description: "Target architecture"
        required: true
        default: "amd64"
        type: choice
        options: [amd64, arm64]
      build_name:
        required: false
        default: ""
        type: string

concurrency:
  group: build-flatpak-${{ github.ref }}-${{ inputs.arch || 'all' }}
  cancel-in-progress: true

jobs:
  build:
    name: flatpak-${{ matrix.arch }}
    strategy:
      fail-fast: false
      matrix:
        arch: >-
          ${{
            github.event_name == 'pull_request'
              && fromJSON('["amd64","arm64"]')
              || fromJSON(format('["{0}"]', inputs.arch || 'amd64'))
          }}
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-latest' }}
    permissions:
      pull-requests: write
      issues: write

    outputs:
      artifact_name: ${{ steps.meta.outputs.artifact_name }}
      artifact_url:  ${{ steps.upload.outputs.artifact-url }}

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set build metadata
        id: meta
        run: |
          BUILD_NAME="${{ inputs.build_name }}"
          if [ -z "$BUILD_NAME" ]; then
            BUILD_NAME=$(grep '^version:' pubspec.yaml \
              | sed 's/version:[[:space:]]*//' | sed 's/+.*//')
          fi
          BUILD_NAME="${BUILD_NAME#v}"
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            BUILD_NAME="${BUILD_NAME%%-*}-pr.${{ github.event.number }}"
          fi
          BUILD_NUMBER=$(git rev-list --count --first-parent HEAD)
          ARCH="${{ matrix.arch }}"
          [ "$ARCH" = "amd64" ] && ARCH_SUFFIX="x86_64" || ARCH_SUFFIX="aarch64"
          echo "build_name=$BUILD_NAME"     >> $GITHUB_OUTPUT
          echo "build_number=$BUILD_NUMBER" >> $GITHUB_OUTPUT
          echo "arch_suffix=$ARCH_SUFFIX"   >> $GITHUB_OUTPUT
          echo "bundle=myapp_linux_${ARCH_SUFFIX}.flatpak" >> $GITHUB_OUTPUT
          echo "artifact_name=myapp-flatpak-${ARCH_SUFFIX}-${BUILD_NAME}-${BUILD_NUMBER}" \
            >> $GITHUB_OUTPUT

      - name: Read Flutter version
        id: flutter-ver
        run: echo "version=$(cat flatpak/flutter.version)" >> $GITHUB_OUTPUT

      # Uses the bundled flutter action — cache key includes runner.arch so
      # it works correctly on both ubuntu-latest (x86_64) and ubuntu-24.04-arm.
      - name: Set up Flutter
        uses: o-murphy/flutpak/.github/actions/flutter@main
        with:
          flutter-version: ${{ steps.flutter-ver.outputs.version }}
          cache: true

      - run: flutter pub get

      # For PR/test builds pass the commit SHA as --tag so flatpak-builder
      # can still build a reproducible image without a real release tag.
      # For tag-triggered builds pass the version tag so Flathub can match
      # the source to a GitHub release.
      - name: Resolve ref for flutpak
        id: resolve-ref
        run: |
          if [[ "${{ github.ref }}" == refs/tags/* ]]; then
            echo "tag=${{ github.ref_name }}" >> $GITHUB_OUTPUT
          else
            echo "tag=$(git rev-parse HEAD)"  >> $GITHUB_OUTPUT
          fi

      - name: Prepare Flatpak sources and manifest
        run: |
          dart run flutpak prepare \
            --tag  "${{ steps.resolve-ref.outputs.tag }}" \
            --commit "$(git rev-parse HEAD)" \
            --sdk "$FLUTTER_ROOT"

      - name: Install flatpak and appstream
        run: sudo apt-get update -qq && sudo apt-get install -y flatpak appstream

      - name: Validate metainfo
        run: |
          appstreamcli validate --explain --no-net \
            app/share/metainfo/<app_id>.metainfo.xml

      - name: Cache org.flatpak.Builder + runtimes
        uses: actions/cache@v5
        with:
          path: ~/.local/share/flatpak
          key: flatpak-builder-25.08-${{ runner.arch }}-v1

      - name: Cache flatpak-builder downloads
        uses: actions/cache@v5
        with:
          path: .flatpak-builder/downloads
          key: >-
            flatpak-dl-${{ steps.meta.outputs.arch_suffix }}-${{
              hashFiles('flatpak/<app_id>.yml','pubspec.lock','flatpak/flutter.version')
            }}
          restore-keys: flatpak-dl-${{ steps.meta.outputs.arch_suffix }}-

      - name: Install org.flatpak.Builder
        run: |
          flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
          dbus-run-session flatpak install --user -y --noninteractive flathub \
            org.flatpak.Builder

      - name: Lint manifest
        run: |
          dbus-run-session flatpak run \
            --filesystem=host \
            --command=flatpak-builder-lint \
            org.flatpak.Builder --exceptions \
            manifest flatpak/<app_id>.yml

      - name: Configure GitHub token for flatpak-builder
        run: |
          echo "machine github.com login x-access-token password ${{ secrets.GITHUB_TOKEN }}" \
            >> ~/.netrc
          chmod 600 ~/.netrc

      - name: Build Flatpak
        run: |
          dbus-run-session flatpak run --command=flathub-build \
            org.flatpak.Builder flatpak/<app_id>.yml

      - name: Lint repo
        run: |
          dbus-run-session flatpak run \
            --filesystem=host \
            --command=flatpak-builder-lint \
            org.flatpak.Builder --exceptions \
            repo repo

      - name: Export .flatpak bundle
        run: |
          flatpak build-bundle \
            --arch="${{ steps.meta.outputs.arch_suffix }}" \
            repo "${{ steps.meta.outputs.bundle }}" <app_id>

      - name: Upload artifact
        id: upload
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.meta.outputs.artifact_name }}
          path: ${{ steps.meta.outputs.bundle }}
          retention-days: ${{ inputs.retention_days || 2 }}
          if-no-files-found: error

      # Upload the Flathub submission package on tag-triggered builds only.
      # Download this artifact and copy its contents into your Flathub
      # repository to open a submission PR.
      - name: Upload Flathub submission artifacts
        if: startsWith(github.ref, 'refs/tags/')
        uses: actions/upload-artifact@v4
        with:
          name: flathub-submission-${{ steps.meta.outputs.arch_suffix }}-${{ github.ref_name }}
          path: |
            flatpak/<app_id>.yml
            flatpak/generated-sources.json
            flatpak/flathub.json
            flatpak/patches/
          retention-days: 90
          if-no-files-found: warn
```

> Replace `<app_id>` with your actual app ID (e.g. `io.github.YourOrg.YourApp`).

---

## Validating and building locally

`flutpak` generates sources and manifests.  The actual build, lint, and validation
steps use the official Flatpak toolchain.

### Prerequisites

```bash
# Install appstreamcli (Debian/Ubuntu)
sudo apt-get install appstream

# Install org.flatpak.Builder (required for build + lint)
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.flatpak.Builder
```

### 1. Validate metainfo (AppStream XML)

```bash
appstreamcli validate --explain --no-net app/share/metainfo/<app_id>.metainfo.xml
```

### 2. Lint the manifest

```bash
dbus-run-session flatpak run \
  --filesystem=host \
  --command=flatpak-builder-lint \
  org.flatpak.Builder \
  --exceptions \
  manifest flatpak/<app_id>.yml
```

- `--exceptions` — apply the built-in Flathub exception list
- `--filesystem=host` — lets the sandboxed linter read files from the host
- Run this **before** building to catch manifest errors early

> **Note:** do **not** set a top-level `branch:` in your manifest —
> `flatpak-builder-lint` flags this as `toplevel-unnecessary-branch`.

### 3. Build with flathub-build

`flathub-build` is the same script Flathub CI uses.  It runs `flatpak-builder`
with `--sandbox`, `--install-deps-from=flathub`, `--repo=repo`, and other
Flathub-specific flags.

```bash
dbus-run-session flatpak run --command=flathub-build org.flatpak.Builder \
  flatpak/<app_id>.yml
```

### 4. Lint the built repo

```bash
dbus-run-session flatpak run \
  --filesystem=host \
  --command=flatpak-builder-lint \
  org.flatpak.Builder \
  --exceptions \
  repo repo
```

### 5. Export a single-file bundle (optional, for local testing)

```bash
flatpak build-bundle repo myapp.flatpak <app_id>
flatpak install --user myapp.flatpak
flatpak run <app_id>
```

### Full GitHub Actions CI example

```yaml
      - name: Install flatpak and appstream
        run: sudo apt-get install -y flatpak appstream

      - name: Validate metainfo
        run: |
          appstreamcli validate --explain --no-net \
            app/share/metainfo/<app_id>.metainfo.xml

      - name: Cache org.flatpak.Builder
        uses: actions/cache@v5
        with:
          path: ~/.local/share/flatpak
          key: flatpak-builder-25.08-${{ runner.arch }}-v1

      - name: Install org.flatpak.Builder
        run: |
          flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
          dbus-run-session flatpak install --user -y --noninteractive flathub \
            org.flatpak.Builder

      - name: Lint manifest
        run: |
          dbus-run-session flatpak run \
            --filesystem=host \
            --command=flatpak-builder-lint \
            org.flatpak.Builder \
            --exceptions \
            manifest flatpak/<app_id>.yml

      - name: Build Flatpak
        run: |
          dbus-run-session flatpak run --command=flathub-build \
            org.flatpak.Builder \
            flatpak/<app_id>.yml

      - name: Lint repo
        run: |
          dbus-run-session flatpak run \
            --filesystem=host \
            --command=flatpak-builder-lint \
            org.flatpak.Builder \
            --exceptions \
            repo repo

      - name: Export bundle
        run: |
          flatpak build-bundle repo myapp.flatpak <app_id>
```

---

## Why include `flutter_tools/pubspec.lock`?

Before any `flutter` command runs, the Flutter tooling bootstraps itself by running
`pub get` inside `packages/flutter_tools/`.  This requires flutter_tools dependencies
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

---

## How it works

### Pub packages

For each hosted package, `flutpak` fetches the SHA-256 from the pub.dev API and
generates two flatpak source entries:

```json
[
  {
    "type": "archive",
    "url": "https://pub.dev/packages/yaml/versions/3.1.2.tar.gz",
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
Gradle wrapper).  SHA-256 checksums are cached in `~/.cache/flutpak/` by URL hash to
avoid redundant downloads across runs.

Two extra entries are always added:

- **`sky_engine/pubspec.yaml` (inline)** — `packages/sky_engine/` was removed from
  the Flutter git tree in Flutter 3.x.  Written inline so `pub get --offline` resolves it.

- **`shared.sh.patch`** — Flutter's bootstrap script runs `pub upgrade` (requires
  network).  The built-in patch replaces it with `pub get --offline`.  Written to
  `flatpak/patches/flutter/shared.sh.patch` next to the output file.

### Flutter version resolution

`flutpak` determines the Flutter version from the SDK path using the following
fallback chain:

1. `<sdk>/version` — flat version file present in Flutter < 3.32
2. `git describe --tags --abbrev=0` — works for any tagged git clone
3. `<sdk>/packages/flutter/pubspec.yaml` — inner package version field

---

## Contributing / building from source

```bash
git clone https://github.com/o-murphy/flutpak.git
cd flutpak
dart pub get
make build          # regenerates lib/src/version.dart, then compiles the binary
make test           # runs the test suite
```

### Bumping the version

1. Update `version:` in `pubspec.yaml`
2. Run `make version` (or `dart run tool/update_version.dart`) — rewrites `lib/src/version.dart`
3. Commit both files

During a release, `release.yml` does steps 1–3 automatically when you push a
`v*` tag, so the compiled binaries always report the correct version.

---

## License

MIT
