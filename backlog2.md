---

**Context:** Refactoring the `flutpak` CLI tool (Flutter → Flatpak packager). Codebase at `/home/user/flutpak`, branch `feature/flutter-module`. The goal is simplification — revert to `main` branch behavior as the baseline and add only targeted improvements.

**Branch context:**
- `main` — current production, stable. `flutpak generate` bundles Flutter SDK inline into `generated-sources.json` alongside pub sources. This is the correct and only approach going forward.
- `feature/flutter-module` — experimental module approach is **abandoned**. The final result of this refactor must behave like `main` + the changes below.

---

**Changes to implement:**

**1. Add `flutpak sdk-mod` command**
Port `SdkModCommand` from this branch as a standalone tool. It remains purely a utility for generating a reusable flutter-sdk module JSON — it is not integrated into `generate`. No changes to how `generate` works relative to `main`.

**2. Remove obsolete commands**
Delete `SourcesCommand`, `FlutterCommand`, `PubCommand` and their files. Remove from `bin/flutpak.dart` and `lib/flutpak.dart` exports.

**3. Remove `patches_registry.dart` entirely**
The entire `lib/src/patches_registry.dart` is obsolete (superseded by `foreign_deps`). Remove file and all imports. `config.patches` / `PatchEntry` are also removed — replaced by `config.foreign_deps` (see point 5).

**4. Replace `flutter.sdk` (local path) with `flutter.ref` (git ref)**

Currently `FlutterSdkGenerator` reads version files from a locally installed Flutter SDK. Instead, fetch them from GitHub raw API — no local Flutter installation required for source generation.

Files to fetch by ref:
```
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/engine.version
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/material_fonts.version
raw.githubusercontent.com/flutter/flutter/{ref}/bin/internal/gradle_wrapper.version
raw.githubusercontent.com/flutter/flutter/{ref}/version
raw.githubusercontent.com/flutter/flutter/{ref}/packages/flutter_tools/pubspec.lock
```

For commit hash: `git ls-remote https://github.com/flutter/flutter.git refs/tags/{ref}`.

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
- `flutter.version` file removed — version is already explicit in `flutter.ref`
- `flutter_tools/pubspec.lock` fetched from GitHub — no local SDK needed for `flutpak generate` itself
- `FlutterSdkGenerator` becomes network-only (cached in `~/.cache/flutpak`)
- `setup-flutter` / `flutter/action.yml` are still needed in CI — not for `flutpak generate`, but to run `flutter pub get` and keep `pubspec.lock` current
- `generate/action.yml`: remove `sdk` input, add `flutter-ref` input instead

**5. Replace `config.patches` with `config.foreign_deps`**

Add `foreign-deps:` key to `flutpak.yaml` — local entries in the same format as `foreign_deps/foreign_deps.json`. Parsed into `FlatpakGenConfig.localForeignDeps: Map<String, dynamic>`.

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
    "1.2.3":
      manifest:
        sources: []            # empty = suppresses remote registry entry
```

**Merge logic in `ForeignDepsRegistry.resolve()`:**
1. Fetch remote `foreign_deps.json`
2. Deep-merge `localForeignDeps` on top — local overrides remote for same package+version
3. Empty `sources: []` suppresses a remote entry

**`crlf:` on `type: patch` sources:**
- Normalize line endings after downloading/copying to `generated/patches/`
- Strip `crlf` from output before writing to `generated-sources.json`

**Patch file copying:**
- `foreign_deps` patches: downloaded to `generated/patches/` (existing behavior, unchanged)
- `output/patches/` → `generated/patches/` recursive copy remains for custom sources in `manifest.sources:`

**6. Refactor `GenerateCommand`**
Remove flags `--pub-only`, `--flutter-only`, `--no-sources`. Logic driven by config:
- `flutter.ref` absent → pub-only
- `flutter.ref` present → SDK sources + pub sources in `generated-sources.json` (always inline, same as `main`)

**7. Verify Flutter SDK install path for `sdk-mod`**
`SdkModCommand._buildCommands()` installs Flutter to `/var/lib/flutter`. Verify this is correct for the separate-module use case and that flatpak-builder sandbox rules allow writing to `/var/lib` during build. `generate` is unaffected (always inline, SDK stays in `/run/build/{app-name}/flutter/`).

**8. Update `ManifestGenerator` / `InitCommand`**
Remove `flutterViaModule` flag entirely — it only existed for the abandoned module approach. Remove all references to `flutter.version` file generation. Revert `append-path` and stamp `build-commands` to `main` branch behavior.

**9. Keep unchanged**
- `config.modules` — custom extra modules (bclibc etc.)
- `foreign_deps` remote registry fetch logic
- `flutter/action.yml` — kept for `flutter pub get` / lock file maintenance in CI

---

Start by reading: `bin/flutpak.dart`, `lib/src/config.dart`, `lib/src/commands/generate_command.dart`, `lib/src/commands/sdk_mod_command.dart`, `lib/src/generators/flutter_sdk.dart`, `lib/src/foreign_deps_registry.dart`, `lib/src/patches_registry.dart`, `lib/src/commands/init_command.dart`, `.github/actions/generate/action.yml`, `.github/actions/flutter/action.yml`. Confirm your understanding of the plan before writing any code.