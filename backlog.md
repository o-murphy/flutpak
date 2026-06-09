---

**Context:** Refactoring the `flutpak` CLI tool (Flutter → Flatpak packager). Codebase at `/home/user/flutpak`, branch `feature/flutter-module`. Read all affected files before making changes.

**Branch context:**
- `main` — current production. `flutpak generate` bundles Flutter SDK inline into `generated-sources.json` alongside pub sources. This is the stable, working approach.
- `feature/flutter-module` (current branch) — experimental. Introduces `sdk-mod` command and the concept of a separate flutter-sdk module JSON. Some things work (see `examples/demo_app`), but the branch is not production-ready and has redundant commands/flags that this refactor aims to clean up.

When in doubt about intended behavior, treat `main` as the reference for what must keep working. The refactor must not break the `flutter.inline: true` path (equivalent to current `main` behavior).

---

**Changes to implement:**

**1. Remove obsolete commands**
Delete `SourcesCommand`, `FlutterCommand`, `PubCommand` and their files. Remove from `bin/flutpak.dart` and `lib/flutpak.dart` exports.

**2. Remove `patches_registry.dart` entirely**
The entire `lib/src/patches_registry.dart` is obsolete. Remove file and all imports. `config.patches` / `PatchEntry` are also removed (replaced by `config.foreign_deps`).

**3. Replace `flutter.sdk` (local path) with `flutter.ref` (git ref)**

This is a fundamental architectural change. Currently `FlutterSdkGenerator` reads version files from a locally installed Flutter SDK (`$FLUTTER_ROOT`). Instead, fetch them from GitHub raw API — no local Flutter installation required at all.

Files to fetch by ref:
```
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/engine.version
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/material_fonts.version
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/gradle_wrapper.version
raw.githubusercontent.com/flutter/flutter/{ref}/version
raw.githubusercontent.com/flutter/flutter/{ref}/packages/flutter_tools/pubspec.lock
```

For commit hash: use GitHub API or `git ls-remote https://github.com/flutter/flutter.git refs/tags/{ref}`.

**Config change:**
```yaml
# was
flutter:
  sdk: $FLUTTER_ROOT

# becomes
flutter:
  ref: "3.44.1"   # tag, branch ("stable", "main"), or commit SHA
```

**CLI change:** `--sdk <path>` → `--flutter <ref>` in `GenerateCommand` and `SdkModCommand`.

**Consequences:**
- `flutter.version` file (previously written to record which SDK was used) is removed — version is already explicit in `flutter.ref`
- `flutter_tools/pubspec.lock` is fetched from GitHub for pub sources generation — no local SDK needed for `flutpak generate` itself
- `FlutterSdkGenerator` becomes network-only (version file fetching + artifact SHA-256 downloads already cached in `~/.cache/flutpak`)
- `setup-flutter` / `flutter/action.yml` are still needed in CI — not for `flutpak generate` itself, but to run `flutter pub get` and keep `pubspec.lock` current if the developer forgot to update it before committing
- `generate/action.yml`: remove `sdk` input and Flutter SDK path detection; add `flutter-ref` input instead. Keep optional `setup-flutter` step for lock file maintenance

**4. Add `flutter.inline` to config**
In `FlatpakGenConfig`, add `flutterInline: bool` (default `false`). Parse from `flutter.inline:` in YAML.

**5. Replace `config.patches` with `config.foreign_deps`**

In `flutpak.yaml`, add `foreign-deps:` key — local entries in the same format as `foreign_deps/foreign_deps.json`. Parsed into `FlatpakGenConfig.localForeignDeps: Map<String, dynamic>`.

Format — version is optional (falls back to pubspec.lock version):
```yaml
foreign-deps:
  sqlite3_flutter_libs:        # no version → resolved from pubspec.lock
    manifest:
      sources:
        - type: patch
          path: patches/sqlite3.patch
          crlf: true           # flutpak-specific, stripped from output
  some_package:
    "1.2.3":                   # explicit version
      manifest:
        sources: []            # empty = removes remote registry entry for this package
```

**Merge logic in `ForeignDepsRegistry.resolve()`:**
1. Fetch remote `foreign_deps.json`
2. Deep-merge `localForeignDeps` on top — local entries override remote for same package+version, never delete unmentioned packages
3. Empty `sources: []` effectively suppresses a remote entry

**`crlf:` field on `type: patch` sources:**
- Supported in both remote registry and `config.foreign_deps` entries
- During resolve, if `crlf: true`: normalize patch file to CRLF line endings after downloading/copying to `generated/patches/`
- Strip `crlf` field from the source map before writing to `generated-sources.json` (must not appear in flatpak-builder output)
- Same behavior as current `PatchEntry.crlf` but applied uniformly

**Patch file copying:**
- `foreign_deps` patches: downloaded/copied to `generated/patches/` (existing behavior, unchanged)
- `output/patches/` → `generated/patches/` recursive copy remains for any custom sources referenced directly in `manifest.sources:` entries

**6. Refactor `GenerateCommand`**
Remove flags `--pub-only`, `--flutter-only`, `--no-sources`. Logic driven by config:

- `flutter.ref` absent → pub-only (dart, no flutter)
- `flutter.ref` present + `flutter.inline: true` → current `main` behavior (SDK sources in `generated-sources.json`)
- `flutter.ref` present + `flutter.inline: false` (default) → new behavior:
  1. Run `FlutterSdkGenerator.generate()` (now network-based) to get SDK sources
  2. Write module JSON to `{config.output}/modules/flutter-sdk/flutter-sdk-{version}.json` using same structure as `SdkModCommand` (extract `_buildCommands()` to `FlutterSdkGenerator` to avoid duplication)
  3. Write built-in patch to `{config.output}/modules/flutter-sdk/patches/flutter/shared.sh.patch` (relative to module file — flatpak-builder resolves patch paths relative to the including module file)
  4. Insert module file path into manifest via existing `p.relative(absoluteModPath, from: generatedDir)` mechanism
  5. `generated-sources.json` → pub sources only

**7. Verify Flutter SDK install path for both modes**

Before implementing, verify the correct install location for each mode:

- `flutter.inline: true` — SDK bundled into app module's own build dir, currently accessible as `/run/build/{app-name}/flutter/bin`. Check whether this path is still correct and whether `/var/lib/flutter` would also work here.
- `flutter.inline: false` — SDK installed to `/var/lib/flutter/` by the separate flutter-sdk module (see `SdkModCommand._buildCommands()`). Required so the SDK is visible to other modules.

**Question to verify:** Can `/var/lib/flutter` be used as the single install location for both modes, or must inline mode keep `/run/build/{app-name}/flutter/`? Check flatpak-builder sandbox rules — `/var/lib` is writable during build for all modules, `/run/build/{app-name}` is only the current module's build dir. If unified path is possible, simplify `ManifestGenerator` to always emit `/var/lib/flutter/bin` in `append-path` regardless of `flutterInline`.

**8. Update `ManifestGenerator` / `InitCommand`**
`flutterViaModule` = `hasFlutter && !flutterInline`. Adjust `append-path` and stamp `build-commands` accordingly based on verification from point 7. Remove any references to `flutter.version` file generation.

**9. Keep unchanged**
- `flutpak sdk-mod` — standalone tool (update to use `--flutter <ref>` instead of `--sdk <path>`)
- `config.modules` — custom extra modules (bclibc etc.)
- `foreign_deps` remote registry fetch logic

10. **Update README.md and Changelog**

11. **Create a plan what to update actions and scripts**


---

Start by reading: `bin/flutpak.dart`, `lib/src/config.dart`, `lib/src/commands/generate_command.dart`, `lib/src/commands/sdk_mod_command.dart`, `lib/src/generators/flutter_sdk.dart`, `lib/src/foreign_deps_registry.dart`, `lib/src/patches_registry.dart`, `lib/src/commands/init_command.dart`, `.github/actions/generate/action.yml`, `.github/actions/flutter/action.yml`. Confirm your understanding of the plan before writing any code.