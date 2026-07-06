# flutter_lmdb2

`flutter_lmdb2` (the Flutter-plugin wrapper around `dart_lmdb2`, used to bundle the
native LMDB library into a shipped app) has no Linux (or Windows) support at all as
published: its own `pubspec.yaml` has both platforms commented out —

```yaml
flutter:
  plugin:
    platforms:
      ios: {...}
      android: {...}
      macos: {...}
#      linux:
#        pluginClass: FlutterLmdb2Plugin
#      windows:
#        pluginClass: FlutterLmdb2Plugin
```

— and there is no `linux/` directory in the package at all. Without this, Flutter's
plugin-discovery tooling never touches `dart_lmdb2`'s native library for a Linux build;
nothing bundles `liblmdb.so` into the app at all, regardless of the `dart_lmdb2` fix
in the sibling foreign_deps entry.

## The fix

Two patches, applied together:

- **`0.9.5-linux-plugin-files.patch`** adds a `linux/` platform directory: a minimal
  no-op GObject plugin (`flutter_lmdb2_plugin.cc` + header — same shape as every other
  no-op Linux Flutter plugin; all real work happens through `dart_lmdb2`'s Dart FFI,
  not a method channel) and a `linux/CMakeLists.txt` that **compiles `liblmdb.so` from
  source** — `mdb.c`/`midl.c` from `LMDB/lmdb.git` at tag `LMDB_0.9.31` (the exact same
  commit `ob-dump`'s own C++ core builds and has verified; pinned by both tag and
  commit hash in `foreign_deps.json`, fetched via a plain `git` source, not a
  prebuilt-binary download) — and registers the result via the
  `flutter_lmdb2_bundled_libraries` `PARENT_SCOPE` variable, the same convention
  `objectbox_flutter_libs`'s own (working) `linux/CMakeLists.txt` uses to get Flutter's
  build to copy a library into `build/linux/<arch>/release/bundle/lib/`. Also links
  `Threads::Threads` (`find_package(Threads REQUIRED)`) explicitly against the new
  `lmdb_native` target — `mdb.c` uses `pthread_mutex`/pthread-specific data, and while
  glibc ≥ 2.34 merges pthread into `libc.so.6` (making this a no-op on this
  development machine, confirmed via `ldd -r` showing zero undefined symbols either
  way), relying on that instead of linking explicitly isn't portable to older glibc
  or non-glibc runtimes — Flathub's own base runtime shouldn't be assumed to match
  whatever happens to be on the machine this was developed on.

- **`0.9.5-pubspec.yaml.patch`** uncomments the `linux:` plugin platform block so
  Flutter's tooling actually picks up the new `linux/` directory.

## Verified empirically, full pipeline, not just reasoned through

Applied both patches to a real `flutter_lmdb2` install, plus the sibling `dart_lmdb2`
patch (see that entry — fixes a separate, more fundamental crash in compiled release
builds), cloned the pinned LMDB tag into `linux/lmdb-src`, built a scratch Flutter app
depending on `flutter_lmdb2`, and ran `flutter build linux --release`:

- `build/linux/x64/release/bundle/lib/` contained `liblmdb.so` right next to
  `libapp.so`/`libflutter_lmdb2_plugin.so` — confirming the CMake build + bundling
  step worked.
- `.flutter-plugins-dependencies` listed `flutter_lmdb2` under `"linux"` with
  `"native_build": true` — confirming Flutter's plugin discovery picked up the new
  platform support.
- Copied only `bundle/` to an isolated directory (no source project, no pub-cache —
  the same shape a Flatpak install has) and ran the binary: **`LMDB` opened
  successfully** — the full pipeline (source fetch → compile → bundle → runtime
  resolve, using the patched `dart_lmdb2` from the sibling entry) works end-to-end
  with zero network access and zero prebuilt binaries at any step.

## Why `git` source instead of downloading a prebuilt archive

Unlike `objectbox_flutter_libs`'s own `linux/CMakeLists.txt` (which `FetchContent`s a
prebuilt `objectbox-c` archive — see that entry's README for why GPL-3.0 apps can't
even use it), LMDB is compiled from its own real source here, matching the same
"vendor source, don't ship prebuilt binaries" principle the parent `ob-dump` project
was built around in the first place. `LMDB_0.9.31` is pinned by both `tag` and
`commit` for reproducibility.

## Upstream

Like the `dart_lmdb2` entry, this is a genuine, reportable gap (`flutter_lmdb2`
supporting iOS/Android/macOS but not Linux/Windows at all) — worth raising with
[grammatek/dart_lmdb2](https://github.com/grammatek/dart_lmdb2) so this patch can
eventually be retired.
