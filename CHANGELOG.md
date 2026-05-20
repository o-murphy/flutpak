# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [0.2.8] - 2026-05-20
 
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

[Unreleased]: https://github.com/o-murphy/flutpak/compare/v0.2.8...HEAD
[0.2.8]: https://github.com/o-murphy/flutpak/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/o-murphy/flutpak/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/o-murphy/flutpak/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/o-murphy/flutpak/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/o-murphy/flutpak/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/o-murphy/flutpak/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/o-murphy/flutpak/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/o-murphy/flutpak/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/o-murphy/flutpak/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/o-murphy/flutpak/releases/tag/v0.1.1
[0.1.0]: https://github.com/o-murphy/flutpak/releases/tag/v0.1.0
