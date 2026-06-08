# flutpak

[![Pub Version]][Pub]
[![Development Status]][Repo]
[![Platform]][Repo]
[![Flatpak Runtime]][Flatpak Org]
[![GitHub License]](LICENSE)
[![GitHub last commit]][Github commits]
[![Made in Ukraine]][SWUBadge]
[![CI](https://github.com/o-murphy/flutpak/actions/workflows/ci.yml/badge.svg)](https://github.com/o-murphy/flutpak/actions/workflows/ci.yml)
[![Demo](https://github.com/o-murphy/flutpak/actions/workflows/demo.yml/badge.svg)](https://github.com/o-murphy/flutpak/actions/workflows/demo.yml)

Dart CLI tool that automates Flatpak packaging for Flutter applications.
Describe your config once in `flutpak.yaml`, run `flutpak init` once to
scaffold your template manifest, then run `flutpak generate` on every CI
build to produce a fully-substituted, `flatpak-builder`-ready output.

## Highlights

- **`init` + `generate` split** — one-time scaffold vs. every-build generation; the editable template is committed to git, the substituted output is gitignored
- **No Python** — pure Dart, compiles to a single native binary for CI
- **Standalone `flutpak.yaml`** — recommended; keeps Flatpak config separate from your Dart project metadata (a `flutpak:` section in `pubspec.yaml` is also supported)
- **yaml_edit injection** — `generate` sets `tag:` and `commit:` directly in the git source block via `yaml_edit`; no placeholder strings to maintain in the template
- **Patches registry** — known packages (e.g. `objectbox_flutter_libs`) get their patches resolved and injected into the generated manifest automatically at `generate` time
- **Validation on every run** — `generate` errors early if the template is missing or its `app-id`, `command`, or `runtime-version` diverge from config
- **Retry on transient errors** — pub.dev and Flutter artifact downloads retry on 429/5xx

## Demo application

The repository ships a real Flutter application in [`examples/demo_app/`](examples/demo_app/)
that is built on every pull request via the `demo.yml` workflow — an end-to-end
**proof of concept** that the tool works, and a **proof of work** that every PR
is gated on a real Flatpak build.

The CI pipeline runs the full cycle:

1. `flutpak generate --commit <sha>` — generates the manifest and sources
2. `flatpak-builder` via `flathub-build` — builds and lints the Flatpak
3. `flatpak install` + smoke test — installs the app and verifies it starts

The demo is intentionally built from the **same git repository** it lives in
(`repo-url: https://github.com/o-murphy/flutpak.git`), with
`subdir: examples/demo_app` in the Flatpak module. This exercises several
features added in v0.6.0:

- **Subdirectory project support** — the Flutter project lives inside a larger
  git repo; the generated `cp` stamp commands use `$FLATPAK_BUILDER_BUILDDIR`
  so they resolve correctly regardless of `subdir:`.
- **LLVM SDK extension auto-injection** — `runtime-version: '25.08'` is all
  that is needed; `flutpak` injects `org.freedesktop.Sdk.Extension.llvm20`
  automatically.
- **`--config` with a subdirectory path** — the workflow passes
  `--config examples/demo_app/flutpak.yaml`; all paths are resolved relative
  to the config file's directory.
- **Minimum viable `flutpak.yaml`** — the demo config has only `app-id`,
  `runtime-version`, `command`, `flutter.sdk`, and `repo-url`; everything
  else is auto-detected.

The demo app config: [`examples/demo_app/flutpak.yaml`](examples/demo_app/flutpak.yaml)
The template manifest: [`examples/demo_app/flatpak/io.github.o_murphy.flutpak.demo.yml`](examples/demo_app/flatpak/io.github.o_murphy.flutpak.demo.yml)

---

## Table of Contents

- [flutpak](#flutpak)
  - [Highlights](#highlights)
  - [Demo application](#demo-application)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [Pre-built binary (recommended)](#pre-built-binary-recommended)
    - [Via setup-flutpak action (CI)](#via-setup-flutpak-action-ci)
    - [From source](#from-source)
  - [Step-by-step setup](#step-by-step-setup)
    - [Step 1 — Create `flutpak.yaml`](#step-1--create-flutpakyaml)
    - [Step 2 — Create required asset files](#step-2--create-required-asset-files)
    - [Step 3 — First run](#step-3--first-run)
    - [Step 4 — Review and customize the template](#step-4--review-and-customize-the-template)
    - [Step 5 — Build locally](#step-5--build-locally)
    - [Step 6 — CI: generate on each release](#step-6--ci-generate-on-each-release)
    - [Step 7 — Submit to Flathub](#step-7--submit-to-flathub)
  - [Foreign deps registry](#foreign-deps-registry)
    - [How it works](#how-it-works)
    - [Priority](#priority)
    - [Currently supported packages](#currently-supported-packages)
    - [Offline / air-gapped use](#offline--air-gapped-use)
    - [Pinning the registry version](#pinning-the-registry-version)
  - [Full config reference](#full-config-reference)
    - [Complete YAML with all options](#complete-yaml-with-all-options)
    - [Field reference table](#field-reference-table)
  - [Commands reference](#commands-reference)
    - [`init`](#init)
    - [`generate`](#generate)
    - [`pub`](#pub)
    - [`flutter`](#flutter)
    - [`sources`](#sources)
    - [`sdk-ext`](#sdk-ext)
    - [`--tag` / `--commit` behavior](#--tag----commit-behavior)
  - [Manifest lifecycle](#manifest-lifecycle)
  - [CI/CD integration](#cicd-integration)
    - [`setup-flutpak` action](#setup-flutpak-action)
    - [`generate` action](#generate-action)
    - [`build-flatpak` action](#build-flatpak-action)
    - [Release workflow example](#release-workflow-example)
  - [Validating and building locally](#validating-and-building-locally)
    - [Install toolchain](#install-toolchain)
    - [1. Validate metainfo](#1-validate-metainfo)
    - [2. Lint the manifest](#2-lint-the-manifest)
    - [3. Build with flathub-build](#3-build-with-flathub-build)
    - [4. Lint the built repo](#4-lint-the-built-repo)
    - [5. Export a single-file bundle (optional)](#5-export-a-single-file-bundle-optional)
  - [Why include `flutter_tools/pubspec.lock`?](#why-include-flutter_toolspubspeclock)
  - [How it works](#how-it-works-1)
    - [Pub sources](#pub-sources)
    - [Flutter SDK sources](#flutter-sdk-sources)
    - [Patches registry](#patches-registry)
    - [Wrapper script](#wrapper-script)
    - [Template vs generated](#template-vs-generated)
  - [Building from source / contributing](#building-from-source--contributing)
    - [Bumping the version](#bumping-the-version)
  - [License](#license)

---

## Prerequisites

| Tool | When needed | Notes |
|---|---|---|
| **Linux** | Always | `flutpak` targets Linux Flatpak packaging only |
| **git** | Always | Version detection and commit-hash resolution |
| **Internet access** | `init`, `generate`, `sources`, `flutter` | Downloads from `pub.dev` and `storage.googleapis.com` |
| **Flutter SDK** | Flutter projects | Path via `$FLUTTER_ROOT` or `--sdk`; pure-Dart projects can omit this |
| **Dart SDK ≥ 3.0** | Building from source only | Not required when using a pre-built binary |
| **`flatpak-builder`** | Local Flatpak builds | Only needed when actually building the Flatpak, not during `flutpak generate` |
| **`org.freedesktop.Sdk`** | Local Flatpak builds | Install via `flatpak install flathub org.freedesktop.Sdk//25.08` |

---

## Installation

### Pre-built binary (recommended)

Download the binary for your platform from the
[releases page](https://github.com/o-murphy/flutpak/releases) and place it
somewhere on your `$PATH`:

```bash
sudo mv flutpak /usr/local/bin/
```

### Via setup-flutpak action (CI)

The repository ships a composite action that compiles and installs `flutpak`
automatically. See [CI/CD integration](#cicd-integration) for full usage.

```yaml
- uses: o-murphy/flutpak/.github/actions/setup-flutpak@v0.6.1
```

### From source

Using `make`:

```bash
git clone https://github.com/o-murphy/flutpak.git
cd flutpak
make build           # regenerates version.dart + compiles binary
sudo mv flutpak /usr/local/bin/
```

Without `make`:

```bash
dart compile exe bin/flutpak.dart -o flutpak --define=version=$(git describe --tags --always)
```

---

## Step-by-step setup

### Step 1 — Create `flutpak.yaml`

Create a standalone `flutpak.yaml` in your project root. This is the
recommended approach — it keeps Flatpak config separate from your Dart project
metadata and avoids any key-convention ambiguity with `pubspec.yaml`.

> [!TIP]
> **Alternative:** you can put a `flutpak:` section directly in `pubspec.yaml`
> instead, but not both at once. Note that `pubspec.yaml` conventionally uses
> snake_case for its own keys; flutpak uses kebab-case, so a standalone
> `flutpak.yaml` is cleaner.

**Minimum viable config** — only `app-id` is truly required:

```yaml
# flutpak.yaml
manifest:
  app-id: io.github.YourOrg.YourApp
```

Everything else is either optional or auto-detected at runtime. For Flutter
projects, add the SDK path:

```yaml
# flutpak.yaml
flutter:
  sdk: $FLUTTER_ROOT        # or absolute path; omit for pure-Dart projects
manifest:
  app-id: io.github.YourOrg.YourApp
```

> [!TIP]
> **Sandbox permissions (`finish-args`)** — `flutpak init` writes sensible
> Flutter desktop defaults into the template. To add extras (e.g.
> `--filesystem=xdg-documents`), list them under `manifest.finish-args:` in
> your config — they are merged after the mandatory args with duplicates
> removed. You can also edit the template directly.

See [Full config reference](#full-config-reference) for all options.

---

### Step 2 — Create required asset files

`flutpak init` validates that these files exist before generating anything.
Create and commit them first:

```
<your-project>/
├── pubspec.yaml
├── pubspec.lock
└── app/
    └── share/
        ├── metainfo/
        │   └── <app-id>.metainfo.xml
        ├── applications/
        │   └── <app-id>.desktop
        └── icons/
            └── hicolor/
                └── 256x256/
                    └── apps/
                        └── <app-id>.png    # minimum 256x256 required by Flathub
```

**Minimal `<app-id>.desktop`:**

```ini
[Desktop Entry]
Name=Your App
Exec=yourapp
Icon=io.github.YourOrg.YourApp
Type=Application
Categories=Utility;
```

**Minimal `<app-id>.metainfo.xml`:**

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

For full requirements on these files, see the
[Flathub app-author documentation](https://docs.flathub.org/docs/for-app-authors/submission).

---

### Step 3 — First run

```bash
flutpak init
```

This is a one-time command. It generates the following files and then
immediately runs `generate` to populate `flatpak/generated/`:

```
flatpak/
├── <app-id>.yml          # editable template manifest — commit this
├── <name>-wrapper.sh     # Flutter launcher wrapper — commit this
├── .gitignore            # contains: generated/
└── generated/            # gitignored, ready for flatpak-builder
    ├── <app-id>.yml
    ├── generated-sources.json
    └── patches/
```

**Commit** `flatpak/<app-id>.yml`, `flatpak/<name>-wrapper.sh`,
and `flatpak/.gitignore`. Do not commit
`flatpak/generated/` — it is gitignored by design.

`flutpak init` errors if the template already exists. Use `--force` to
overwrite an existing scaffold.

---

### Step 4 — Review and customize the template

Open `flatpak/<app-id>.yml` and adjust `build-commands`, `sdk-extensions`,
`finish-args`, and any other fields for your project. The template is yours —
`flutpak` never overwrites it on subsequent runs.

The generated template already contains inline guidance comments that explain
which sections are safe to edit. Key rules:

| Section | Guidance |
|---|---|
| `finish-args:` | Safe to edit — add/remove sandbox permissions |
| `build-commands:` | Safe to edit — add steps, adjust install paths |
| `build-options:` | Safe to edit — add env vars, path overrides |
| `sdk-extensions:` | Safe to edit |
| `modules:` | Safe to edit — add extra modules |
| `sources:` — extra archives | Safe to add/remove |
| `tag:` / `commit:` in git source | Set automatically by `generate` via `yaml_edit` — you can leave them absent or set them manually; `generate` will overwrite them |
| Flutter `cp` stamp commands | Use `$FLATPAK_BUILDER_BUILDDIR/flutter/…` — always the module build root, works with or without `subdir:` |
| Patch sources (`type: patch`) | **Do not add manually** — injected automatically by `generate` from your `patches:` config; adding them to the template causes duplicates |

> [!TIP]
> If your Flutter project lives in a **subdirectory** of the git repo (e.g. `apps/myapp/`),
> add `subdir: apps/myapp` to the module in the template. The generated `cp` stamp commands
> already use `$FLATPAK_BUILDER_BUILDDIR` (always the module root, not the `subdir`), so
> they resolve correctly. Other paths in `build-commands` that reference files inside
> the Flutter project (assets, desktop entry, etc.) remain relative to the `subdir`.

---

### Step 5 — Build locally

Point `flatpak-builder` at the generated manifest:

```bash
flatpak-builder --repo=repo --force-clean build-dir \
  flatpak/generated/<app-id>.yml
```

See [Validating and building locally](#validating-and-building-locally) for
the full lint and validation workflow.

---

### Step 6 — CI: generate on each release

On every release build, run `generate` with the release tag:

```bash
flutpak generate --tag ${{ github.ref_name }}
```

This reads the committed template, resolves the tag and commit SHA, sets
`tag:` and `commit:` in the git source block, generates `generated-sources.json`,
and writes everything to `flatpak/generated/`.

See [CI/CD integration](#cicd-integration) for a complete GitHub Actions
workflow.

---

### Step 7 — Submit to Flathub

Open a PR to your app's Flathub repository. Copy the contents of
`flatpak/generated/` into the repo root:

```
<flathub-repo>/
├── <app-id>.yml               # flatpak/generated/<app-id>.yml
├── generated-sources.json     # flatpak/generated/generated-sources.json
└── patches/                   # flatpak/generated/patches/ (if any)
```

For complete submission requirements see the
[Flathub app-author documentation](https://docs.flathub.org/docs/for-app-authors/submission).

---

## Foreign deps registry

`flutpak generate` automatically resolves known pub packages from a remote
registry at
[`foreign_deps/foreign_deps.json`](foreign_deps/foreign_deps.json), using
the same format as `flatpak-flutter`. For each package found in your lock
files the registry provides the complete set of flatpak sources — prebuilt
archives and patches — needed for an offline Flatpak build.

### How it works

1. The registry is fetched from GitHub on every `generate` run (network
   required; cached in `~/.cache/flutpak/` as offline fallback).
2. For every package in your `pubspec.lock` that appears in the registry at
   the exact locked version, its sources are appended to
   `generated-sources.json`.
3. Patch files from the registry are downloaded to
   `generated/patches/<path>` and referenced with a relative `path:` so
   flatpak-builder can find them alongside the manifest.

### Priority

Local `patches:` entries always override the registry. If a package has a
`patches:` entry in `flutpak.yaml`, the registry is skipped for that package.

### Currently supported packages

| Package | Versions |
|---|---|
| `audiotags` | 1.4.5 |
| `flutter_new_pipe_extractor` | 0.1.0 |
| `flutter_webrtc` | 1.3.0 |
| `fvp` | 0.35.0 |
| `media_kit_libs_linux` | 1.2.1 |
| `pdfium_flutter` | 0.1.7 |
| `powersync` | 2.1.0 |
| `printing` | 5.14.2 |
| `simple_secure_storage_linux` | 0.2.5 |
| `sqlcipher_flutter_libs` | 0.6.8 |
| `sqlite3` | 2.9.4, 3.0.0, 3.3.0 |
| `sqlite3_flutter_libs` | 0.5.30, 0.5.32, 0.5.34, 0.5.39, 0.5.41, 0.5.42, 0.6.0 |
| `objectbox_flutter_libs` | 5.3.1, 5.3.2 |
| `objectbox_sync_flutter_libs` | 5.3.1, 5.3.2 |

For the full list see [`foreign_deps/foreign_deps.json`](foreign_deps/foreign_deps.json).

### Offline / air-gapped use

```bash
flutpak generate --no-foreign-deps
```

### Pinning the registry version

```yaml
# flutpak.yaml
foreign-deps-ref: v0.6.1   # tag, branch, or SHA; default: main
```

---

## Full config reference

Config lives in **one** of two places (error if both exist):

| Location | Notes |
|---|---|
| `flutpak.yaml` | **Recommended** — standalone file |
| `pubspec.yaml` | `flutpak:` section — also works; note that flutpak uses kebab-case keys which look unusual alongside pubspec's own snake_case keys |

### Complete YAML with all options

```yaml
# flutpak.yaml (recommended) — or flutpak: section in pubspec.yaml
output: flatpak                    # default

pub:
  locks:
    - pubspec.lock
    - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock  # optional

flutter:
  sdk: /home/user/flutter          # or set $FLUTTER_ROOT; omit for pure-Dart
  patch: flatpak/patches/flutter/shared.sh.patch  # optional

patches:                           # optional project-level patches
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox.patch
    dest-subpath: linux            # optional: subdirectory inside package root
    crlf: true                     # optional: target file has CRLF (e.g. objectbox_flutter_libs ≥ 5.3.2)
    options:                       # optional: extra flags forwarded to patch(1)
      - --some-flag
    use-git: true                  # optional: use git apply instead of patch(1); mutually exclusive with options only

# flutpak-specific overrides (not part of the Flatpak manifest schema):
repo-url: https://github.com/...   # default: git remote get-url origin
disable-submodules: false          # default: false (matches flatpak-builder default)
metainfo-path: app/share/metainfo/<app-id>.metainfo.xml   # default
desktop-entry-path: app/share/applications/<app-id>.desktop  # default

icons:                             # default: single 256x256 entry
  - size: 256x256                  # required when icons: key is present
    path: app/share/icons/hicolor/256x256/apps/<app-id>.png
  # optional additional sizes:
  - size: 512x512
    path: app/share/icons/hicolor/512x512/apps/<app-id>.png
  - size: scalable
    path: app/share/icons/hicolor/scalable/apps/<app-id>.svg

modules:
  - flatpak/modules/bclibc.yml

manifest:
  app-id: io.github.YourOrg.YourApp  # required
  runtime-version: '25.08'           # default: '25.08'

  # For Flutter projects, org.freedesktop.Sdk.Extension.llvmXX is auto-injected
  # based on runtime-version (25.08→llvm20, 24.08→llvm19, 23.08→llvm17).
  # Add extra extensions manually if needed:
  sdk-extensions:
    - org.freedesktop.Sdk.Extension.rust-stable

  # Auto-detected if omitted (info printed on init):
  command: yourapp                   # default: last segment of app-id

  # Extra finish-args merged after the mandatory Flutter defaults:
  finish-args:
    - --filesystem=xdg-documents
    - --share=network

  # Verbatim flatpak source entries appended to the app module:
  sources: []
  env: {}
  build-options:
    append-path: /custom/bin
    prepend-ld-library-path: /custom/lib
    env:
      MY_VAR: value

flutter-version-file: flatpak/flutter.version  # default when flutter configured
```

### Field reference table

| Field | Type | Default | Notes |
|---|---|---|---|
| `output` | string | `flatpak` | Output directory for generated files |
| `pub.locks` | list | `[pubspec.lock]` | Lock files to scan; `$ENV` vars expanded |
| `flutter.sdk` | string | `$FLUTTER_ROOT` | Flutter SDK path; omit for pure-Dart |
| `flutter.patch` | string | — | Custom patch for `setup-flutter.sh` |
| `flutter-version-file` | string | `<output>/flutter.version` | Written when Flutter is configured |
| `patches` | list | `[]` | Project-level package patches |
| `patches[].options` | list | `[]` | Extra flags forwarded to `patch(1)`. Ignored when `use-git: true`. |
| `patches[].crlf` | bool | `false` | When `true`, normalise the patch to CRLF in `generated/patches/`; when `false` (default), normalise to LF. `--binary` is always added to patch options. Use `crlf: true` when the upstream pub.dev archive ships CRLF sources (e.g. `objectbox_flutter_libs` ≥ 5.3.2). Compatible with `use-git: true`. |
| `patches[].use-git` | bool | `false` | When `true`, the generated patch source includes `use-git: true`, causing flatpak-builder to apply the patch via `git apply` instead of `patch -p1`. More robust for patches in git extended format. Compatible with `crlf`. **Caution:** `git apply` resolves paths relative to the git worktree root, not `dest`. Only use this for patches targeting files at or below the app git root. For patches that target pub package subdirectories (e.g. `objectbox_flutter_libs`), use `--binary` via `options:` instead. |
| `foreign-deps-ref` | string | `main` | Git ref used to fetch the foreign deps registry. Pin to a tag or SHA for reproducible builds. |
| `repo-url` | string | `git remote get-url origin` | Source git URL written into template |
| `disable-submodules` | bool | `false` | When `true`, adds `disable-submodules: true` to the git source in the generated template, preventing flatpak-builder from cloning git submodules |
| `metainfo-path` | string | `app/share/metainfo/<id>.metainfo.xml` | Validated on `init` and `generate` |
| `desktop-entry-path` | string | `app/share/applications/<id>.desktop` | Validated on `init` and `generate` |
| `icons` | list | `[{size: 256x256, path: app/share/icons/…}]` | Must include 256x256 if key is present |
| `modules` | list | `[]` | YAML files injected as extra modules before the app module |
| `manifest.app-id` | string | **required** | Reverse-DNS app ID |
| `manifest.runtime-version` | string | `25.08` | Freedesktop runtime version |
| `manifest.command` | string | last segment of `app-id` | Executable name inside `/app/bin/` |
| `manifest.sdk-extensions` | list | `[]` | For Flutter projects, `llvmXX` is **auto-injected** based on `runtime-version` (25.08 → llvm20, 24.08 → llvm19, 23.08 → llvm17). Add here only extensions beyond llvm (e.g. `rust-stable`). |
| `manifest.finish-args` | list | `[]` | Extra sandbox permission flags appended after the mandatory Flutter defaults (`--share=ipc`, `--socket=fallback-x11`, `--socket=wayland`, `--device=dri`). Duplicates are silently removed. |
| `manifest.sources` | list | `[]` | Verbatim flatpak source entries appended to the app module |
| `manifest.env` | map | `{}` | Build-time env vars (shorthand) |
| `manifest.build-options.append-path` | string | — | Appended to `PATH` during build |
| `manifest.build-options.prepend-ld-library-path` | string | — | Prepended to `LD_LIBRARY_PATH` |
| `manifest.build-options.env` | map | `{}` | Merged with top-level `env:` |

> [!NOTE]
> The `manifest:` section currently supports only the fields listed above. It is
> **not** a full Flatpak manifest — fields like `build-commands` and `modules`
> are not read from config. Edit the template file (`flatpak/<app-id>.yml`)
> directly to change those.
>
> Future versions plan to treat `manifest:` as a full Flatpak manifest fragment,
> with flutpak injecting sources, patches, and modules in merge mode (adding
> only what is not already present) rather than generating a fixed template.

---

## Commands reference

### `init`

```
flutpak init [--config <path>] [--sdk <path>] [--force]
```

One-time setup. Generates the editable template manifest, wrapper script,
and `flatpak/.gitignore`, then immediately runs `generate`.

- Errors if the template (`flatpak/<app-id>.yml`) already exists — use
  `--force` to overwrite.
- Validates that all asset files (metainfo, desktop entry, icons) exist.
- Auto-detects `repo_url` from `git remote get-url origin`.

| Flag | Description |
|---|---|
| `--config` | Path to config file (default: auto-detected `pubspec.yaml` or `flutpak.yaml`) |
| `--sdk` | Flutter SDK path; overrides `flutter.sdk:` in config and `$FLUTTER_ROOT` |
| `--force` | Overwrite existing template and wrapper |

### `generate`

```
flutpak generate [--tag v1.2.3] [--commit sha] [--config <path>] [--sdk <path>]
                 [--no-sources] [--pub-only] [--flutter-only] [--dry-run]
```

Every-build command. Reads the committed template, validates it against
config, sets `tag:` and `commit:` in the git source block via `yaml_edit`,
generates `generated-sources.json`, and writes everything to `flatpak/generated/`.

- Errors if the template does not exist (run `flutpak init` first).
- Errors if `app-id`, `command`, or `runtime-version` in the template differ
  from config.
- Errors if any asset file (metainfo, desktop entry, icon) does not exist.

| Flag | Description |
|---|---|
| `--tag` | Git tag embedded in the manifest (e.g. `v1.2.3`) |
| `--commit` | Full git commit SHA; defaults to `git rev-parse HEAD` |
| `--config` | Path to config file |
| `--sdk` | Flutter SDK path |
| `--no-sources` | Skip source generation; copy template only |
| `--pub-only` | Generate only pub package sources |
| `--flutter-only` | Generate only Flutter SDK sources |
| `--dry-run` | Print what would be written without writing any files |

### `pub`

```
flutpak pub [--lock <path>] [--output <dir>]
```

Generate pub package sources only. Reads `pubspec.lock` (and any additional
lock files specified via `--lock`) and writes `generated-sources.json`.

### `flutter`

```
flutpak flutter [--sdk <path>] [--output <dir>]
```

Generate Flutter SDK sources only. Reads engine version from the SDK and
writes artifact entries to `generated-sources.json`.

### `sources`

```
flutpak sources [--lock <path>] [--sdk <path>] [--output <dir>]
```

Generate all sources (pub + Flutter SDK) combined into a single
`generated-sources.json`.

> [!NOTE]
> **`pub`, `flutter`, and `sources` are for advanced / standalone use.**
> They are intended for users who write their Flatpak manifest by hand and need
> only the source list as a JSON file to embed themselves. In the standard
> `init` + `generate` workflow you never need to call them directly — `generate`
> handles source generation internally and injects patch sources into the
> generated manifest automatically.

### `sdk-ext`

```
flutpak sdk-ext [--sdk <path>] [--output <dir>]
```

Generate a Flutter SDK Extension manifest for Flathub
(`org.freedesktop.Sdk.Extension.flutter3`) to share the Flutter SDK across
multiple apps on the same machine.

---

### `--tag` / `--commit` behavior

| `--tag` | `--commit` | Tag in manifest | Commit in manifest |
|---|---|---|---|
| `v1.2.3` | — | `v1.2.3` | Resolved via `git rev-parse v1.2.3^{}` |
| — | `abc123` | `abc123` | `abc123` |
| — | — | HEAD SHA | HEAD SHA |
| `v1.2.3` | `abc123` | `v1.2.3` | `abc123` (explicit override) |

When neither flag is passed, the current HEAD SHA is used for both values so
`flatpak-builder` can fetch and build the revision without a real release tag.

For release builds, always pass `--tag`. `--tag` requires the tag to exist
locally — use `fetch-depth: 0` in your checkout step so the tag is available.

---

## Manifest lifecycle

The architecture separates the editable template (committed to git) from the
generated output (gitignored):

```
flatpak/
├── <app-id>.yml          <- editable template — committed to git
├── <name>-wrapper.sh     <- committed to git
├── patches/              <- patch files — committed to git
├── .gitignore            <- contains: generated/
└── generated/            <- gitignored, never commit this
    ├── <app-id>.yml      <- final manifest (tag/commit set, sources injected)
    ├── generated-sources.json
    └── patches/          <- copy
```

**Phase 1 — `flutpak init`** (run once)

Creates `flatpak/<app-id>.yml` — the editable template with guidance comments
and a git source block (no `tag:` / `commit:` yet). Commit this file — it is
the starting point that reviewers inspect and that `generate` reads on every
subsequent build.

**Phase 2 — `flutpak generate --tag vX.Y.Z`** (run on every CI build)

Reads the committed template, resolves the tag and commit SHA, sets `tag:` and
`commit:` directly in the git source block (via `yaml_edit`), generates
`generated-sources.json`, and copies everything to `flatpak/generated/`. The
template is never modified. `flatpak-builder` consumes
`flatpak/generated/<app-id>.yml`.

---

## CI/CD integration

### `setup-flutpak` action

```yaml
- uses: o-murphy/flutpak/.github/actions/setup-flutpak@v0.6.1
  # Builds from the same ref as the 'uses:' directive by default.
  # Pin to a specific release:
  # with:
  #   version: v
```

| Input | Description | Default |
|---|---|---|
| `version` | Release tag, commit SHA, or branch to compile | ref pinned in `uses:` directive |
| `install_dir` | Directory where the `flutpak` binary is placed | `/usr/local/bin` |

The repository also ships a `flutter` composite action with
`runner.arch`-aware cache keys — it works correctly on both `ubuntu-latest`
(x86_64) and `ubuntu-24.04-arm` (aarch64) runners:

```yaml
- uses: o-murphy/flutpak/.github/actions/flutter@v0.6.1
  with:
    flutter-version: stable   # or read from flatpak/flutter.version
    cache: true
```

| Input | Description | Default |
|---|---|---|
| `flutter-version` | Version tag (e.g. `3.41.6`), `stable`, or `beta` | `stable` |
| `cache` | Cache the SDK between runs | `true` |

| Output | Description |
|---|---|
| `flutter-path` | Absolute path to the installed Flutter SDK |

The action also exports `FLUTTER_ROOT` and `FLUTTER_HOME` env vars and adds
`flutter/bin` to `$PATH`, so `flutpak generate` picks up the SDK automatically
without an explicit `--sdk` flag.

### `generate` action

Runs `flutpak generate`, validates metainfo, and uploads the generated manifest
and sources as a workflow artifact. Requires Flutter to be installed beforehand
(e.g. via the `flutter` action above).

```yaml
- uses: o-murphy/flutpak/.github/actions/generate@v0.6.1
  with:
    tag: ${{ inputs.tag }}      # or pass 'commit:' for non-tag builds
    # commit: ${{ github.sha }} # used when 'tag' is empty
    metainfo-path: app/share/metainfo/<app-id>.metainfo.xml
    artifact-name: flatpak-generated
```

| Input | Description | Default |
|---|---|---|
| `tag` | Git tag to embed in the manifest (mutually exclusive with `commit`) | — |
| `commit` | Commit SHA; defaults to `github.sha` when empty | — |
| `sdk` | Flutter SDK path; auto-detected from `FLUTTER_ROOT` or `flutter` in `PATH` | — |
| `metainfo-path` | Path to `.metainfo.xml`; `appstream` is installed automatically if needed | — |
| `artifact-name` | Upload generated files under this artifact name | `flutpak-artifacts` |
| `retention-days` | Artifact retention in days | `2` |
| `flutpak-version` | flutpak version to install; defaults to the same ref as the `uses:` directive | — |

### `build-flatpak` action

Installs `org.flatpak.Builder`, lints the manifest, builds via `flathub-build`,
lints the repo, exports a `.flatpak` bundle, and optionally uploads it.

```yaml
- uses: o-murphy/flutpak/.github/actions/build-flatpak@v0.6.1
  id: build
  with:
    manifest: flatpak/generated/<app-id>.yml
    app-id: io.github.YourOrg.YourApp
    artifact-name: myapp-flatpak
    github-token: ${{ secrets.GITHUB_TOKEN }}   # for private source downloads

# Downstream steps can reference:
# ${{ steps.build.outputs.bundle }}       — path to the .flatpak file
# ${{ steps.build.outputs.arch }}         — x86_64 or aarch64
# ${{ steps.build.outputs.artifact-url }} — download URL of the uploaded artifact
```

| Input | Description | Default |
|---|---|---|
| `manifest` | Path to the generated Flatpak manifest | **required** |
| `app-id` | Flatpak application ID | **required** |
| `arch` | Target architecture (`x86_64` or `aarch64`); auto-detected from `flatpak --default-arch` | — |
| `bundle` | Output `.flatpak` filename | `<app-id>_<arch>.flatpak` |
| `artifact-name` | Upload bundle under this artifact name; skip upload if empty | — |
| `retention-days` | Artifact retention in days | `2` |
| `github-token` | GitHub token written to `~/.netrc` for private source downloads | — |

| Output | Description |
|---|---|
| `bundle` | Path to the exported `.flatpak` bundle |
| `arch` | Architecture used for the build |
| `artifact-url` | Download URL of the uploaded artifact (empty if `artifact-name` is unset) |

### Release workflow example

The `generate` and `build-flatpak` actions let you split generation (runs once)
from building (can fan out across multiple architectures):

```yaml
name: Flatpak release

on:
  push:
    tags: ['v*']

jobs:
  generate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0          # required for --tag to resolve the commit

      - uses: o-murphy/flutpak/.github/actions/flutter@v0.6.1
        id: flutter
        with:
          flutter-version: stable
          cache: true

      - run: flutter pub get

      - uses: o-murphy/flutpak/.github/actions/generate@v0.6.1
        with:
          tag: ${{ github.ref_name }}
          metainfo-path: app/share/metainfo/<app-id>.metainfo.xml
          artifact-name: flatpak-generated

  build:
    needs: generate
    strategy:
      matrix:
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'arm64' && 'ubuntu-24.04-arm' || 'ubuntu-latest' }}
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: flatpak-generated
          path: flatpak/generated

      - uses: o-murphy/flutpak/.github/actions/build-flatpak@v0.6.1
        id: build
        with:
          manifest: flatpak/generated/<app-id>.yml
          app-id: io.github.YourOrg.YourApp
          artifact-name: myapp-${{ matrix.arch }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

For a minimal single-job workflow that uses `setup-flutpak` + manual steps, see
the legacy example below.

<details>
<summary>Legacy single-job example (manual steps)</summary>

```yaml
name: Flatpak release (manual)

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: o-murphy/flutpak/.github/actions/setup-flutpak@v0.6.1

      - uses: o-murphy/flutpak/.github/actions/flutter@v0.6.1
        with:
          flutter-version: stable
          cache: true

      - run: flutter pub get

      - run: flutpak generate --tag ${{ github.ref_name }}
```

</details>

---

## Validating and building locally

`flutpak` generates sources and manifests. The actual lint, build, and
validation steps use the official Flatpak toolchain.

### Install toolchain

```bash
# Install appstreamcli (Debian/Ubuntu)
sudo apt-get install appstream

# Install org.flatpak.Builder (required for build + lint)
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.flatpak.Builder

# Install the Freedesktop runtime
flatpak install flathub org.freedesktop.Sdk//25.08
```

### 1. Validate metainfo

```bash
appstreamcli validate --explain --no-net \
  app/share/metainfo/<app-id>.metainfo.xml
```

### 2. Lint the manifest

```bash
dbus-run-session flatpak run \
  --filesystem=host \
  --command=flatpak-builder-lint \
  org.flatpak.Builder \
  --exceptions \
  manifest flatpak/generated/<app-id>.yml
```

`--exceptions` applies the built-in Flathub exception list. Run this before
building to catch manifest errors early.

> [!IMPORTANT]
> Do not set a top-level `branch:` in your manifest —
> `flatpak-builder-lint` flags this as `toplevel-unnecessary-branch`.

### 3. Build with flathub-build

`flathub-build` is the same script Flathub CI uses. It runs `flatpak-builder`
with `--sandbox`, `--install-deps-from=flathub`, `--repo=repo`, and other
Flathub-specific flags.

```bash
dbus-run-session flatpak run --command=flathub-build \
  org.flatpak.Builder \
  flatpak/generated/<app-id>.yml
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

### 5. Export a single-file bundle (optional)

```bash
flatpak build-bundle repo myapp.flatpak <app-id>
flatpak install --user myapp.flatpak
flatpak run <app-id>
```

---

## Why include `flutter_tools/pubspec.lock`?

Before any `flutter` command runs inside the Flatpak sandbox, the Flutter
tooling bootstraps itself by running `pub get` inside
`packages/flutter_tools/`. This requires the flutter_tools dependencies to be
present in the offline pub cache.

Pass both lock files so the generated sources cover the app **and** the tool:

```yaml
pub:
  locks:
    - pubspec.lock
    - $FLUTTER_ROOT/packages/flutter_tools/pubspec.lock
```

When the same package appears at different versions in the two lock files (e.g.
`yaml 3.1.2` in the app and `yaml 3.1.3` in flutter_tools), both versions are
included — deduplication is by `(name, version)` pair.

---

## How it works

### Pub sources

For each hosted package in your lock file(s), `flutpak` fetches the SHA-256
checksum from the pub.dev API and generates two `flatpak-builder` source
entries:

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

Both entries are required: `pub get --offline` checks the hash file and fails
if it is missing even when the archive is present.

### Flutter SDK sources

When `flutter.sdk:` is configured, `flutpak` reads the engine version from the
local Flutter install (`bin/internal/engine.version`, etc.) and constructs
download URLs for each artifact — Dart SDK, engine binaries, fonts, and the
Gradle wrapper — for both `x86_64` and `aarch64`. SHA-256 checksums are cached
in `~/.cache/flutpak/` by URL hash to avoid redundant downloads across runs.

All sources (pub + Flutter SDK) are combined into a single
`generated-sources.json`. This matches the convention expected by Flathub
reviewers — splitting into multiple files offers no practical benefit and
typically prompts questions during review.

Two extra entries are always added:

- **`sky_engine/pubspec.yaml` (inline)** — `packages/sky_engine/` was removed
  from the Flutter git tree in Flutter 3.x. Written inline so `pub get
  --offline` resolves it.
- **`setup-flutter.sh`** — wires the downloaded artifacts together inside the
  Flatpak sandbox.

`flutpak` determines the Flutter version from the SDK path using the following
fallback chain:

1. `<sdk>/version` — flat version file present in Flutter < 3.32
2. `git describe --tags --abbrev=0` — works for any tagged git clone
3. `<sdk>/packages/flutter/pubspec.yaml` — inner package version field

### Patches registry

**Patch injection happens at `generate` time, not `init` time.** The template
manifest contains no `type: patch` entries — this is by design. On every
`generate` run, `flutpak` resolves the current package versions from
`pubspec.lock` and injects the correct `type: patch` entries (with accurate
`dest: .pub-cache/hosted/pub.dev/<package>-<version>` paths) into the generated
manifest after the `generated-sources.json` line. Patch files themselves are
committed to `flatpak/patches/` and copied to `generated/patches/` during
generation.

The built-in Flutter bootstrap patch (`shared.sh.patch`) replaces
`pub upgrade` (requires network) with `pub get --offline` inside the Flutter
SDK's `shared.sh` bootstrap script. It is injected directly into the generated
manifest's `sources:` section and applied automatically — no configuration
needed. For pure Dart projects (`--pub-only`) it is skipped entirely.

**Known patches for common packages** are maintained as reference files in the
[`known-patches/`](known-patches/) directory of this repository, with usage
instructions in [`known-patches/PATCHES.md`](known-patches/PATCHES.md).
Copy the relevant `.patch` file to your project's `flatpak/patches/` directory
and reference it via the `patches:` config key — `flutpak generate` will then
copy it to `generated/patches/` and inject it into the manifest automatically.

Some upstream packages ship sources with CRLF line endings (e.g.
`objectbox_flutter_libs` ≥ 5.3.2). GNU `patch(1)` fails with "different line
endings" in this case. Use `crlf: true` — `flutpak generate` normalises the
patch file to CRLF line endings when writing to `generated/patches/`, and
always adds `--binary` to the patch source options so that `patch(1)` preserves
line endings exactly as written. Patches without `crlf: true` are normalised to
LF, making the output deterministic on any host OS.

> [!CAUTION]
> `use-git: true` causes `git apply`, which resolves paths relative to the **git
> worktree root**, not the `dest` directory. Avoid it for patches targeting pub
> package subdirectories (e.g. `objectbox_flutter_libs`) — use `--binary` via
> `options:` instead:
>
> ```yaml
> patches:
>   - package: objectbox_flutter_libs
>     path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
>     crlf: true
>     options:
>       - --binary
> ```
>
> `use-git: true` is appropriate only for patches that target files within the
> app's own git checkout (at or below the module root).

> [!NOTE]
> Add `*.patch -text` to your project's `.gitattributes` to prevent git from
> re-normalising line endings in patch files on Windows checkouts.
> Without this, the CRLF conversion performed by `flutpak generate` would be
> undone on the next checkout.

### Wrapper script

For Flutter apps, `init` generates `flatpak/<name>-wrapper.sh`:

```sh
#!/bin/sh
# Generated by flutpak — https://github.com/o-murphy/flutpak
APP=/app/<name>
export LD_LIBRARY_PATH="$APP/lib:${LD_LIBRARY_PATH:-}"
exec "$APP/<name>" "$@"
```

This bridges Flatpak's `command:` entry (pointing to `/app/bin/<name>`) to the
Flutter bundle at `/app/<name>/<name>`, setting `LD_LIBRARY_PATH` for shared
libraries bundled with the app.

### Template vs generated

The template (`flatpak/<app-id>.yml`) is a standard Flatpak manifest that you
commit to git. It contains no placeholder strings — `generate` writes `tag:` and
`commit:` directly into the git source block via `yaml_edit`.

`generate` copies the template to `flatpak/generated/<app-id>.yml`, sets `tag:`
and `commit:` in the git source block, and **injects patch sources** immediately
after the `generated-sources.json` reference. Patches are never baked into the
template — they are resolved from `pubspec.lock` at generate time so the
`dest:` path always contains the correct package version. The template is
never modified; the generated file is gitignored and rebuilt on every CI run.

`generate` also validates consistency between the template and config before
writing anything:

- `app-id` in template must match `manifest.app-id` in config
- `command` in template must match `manifest.command` in config (or its default)
- `runtime-version` in template must match `manifest.runtime-version` in config

---

## Building from source / contributing

```bash
git clone https://github.com/o-murphy/flutpak.git
cd flutpak
make test        # run test suite
make build       # compile binary (version from git describe --tags)
```

### Bumping the version

1. Update `version:` in `pubspec.yaml`
2. Commit and tag (`git tag v1.2.3`) — `make build` picks the version from the
   tag automatically via `git describe`

During a release, `release.yml` performs step 1 automatically when a `v*`
tag is pushed, so the compiled binaries always report the correct version.

---

## License

MIT


<!-- LINKS -->

[Pub]: https://pub.dev/packages/flutpak
[Repo]: https://github.com/o-murphy/flutpak
[Pub Version]: https://img.shields.io/pub/v/flutpak?logo=dart
[Development Status]: https://img.shields.io/badge/status-beta-orange
[Platform]: https://img.shields.io/badge/platform-linux-9c59b6?logo=linux&logoColor=white
[Flatpak Runtime]: https://img.shields.io/badge/Flatpak--Runtime-25.08-blue?logo=flatpak&logoColor=white
[Flatpak Org]: https://flatpak.org/
[GitHub License]: https://img.shields.io/github/license/o-murphy/flutpak
[GitHub last commit]: https://img.shields.io/github/last-commit/o-murphy/flutpak?logo=git
[Github commits]: https://github.com/o-murphy/flutpak/commits/main
[Made in Ukraine]:https://img.shields.io/badge/made_in-Ukraine-ffd700.svg?labelColor=0057b7&style=flat-square
[SWUBadge]: https://stand-with-ukraine.pp.ua
