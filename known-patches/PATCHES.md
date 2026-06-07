# Known Patches

Patches for packages that commonly need modifications for Flatpak offline builds.

Copy the relevant `.patch` file to your project's `flatpak/patches/` directory
and reference it in `flutpak.yaml`:

```yaml
patches:
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
```

`flutpak generate` will then copy the file to `flatpak/generated/patches/` and
inject the correct `type: patch` source (with the version-resolved `dest:` path)
into the generated manifest automatically.

---

## `flutter/shared.sh.patch`

**Applies to:** All Flutter SDK versions  
**What it does:** Replaces `pub upgrade` (requires network) with
`pub get --offline` inside Flutter's bootstrap script
`flutter/bin/internal/shared.sh`. Required for all Flutter Flatpak builds.

> **Note:** This patch is applied automatically by `flutpak generate` — you do
> not need to copy or configure it manually. It is listed here for reference only.

---

## `objectbox_sync_flutter_libs/5.3.1-CMakeLists.txt.patch`

**Package:** `objectbox_sync_flutter_libs`  
**Version:** `5.3.1`  
**What it does:** Replaces the unconditional `FetchContent_Populate(objectbox-download)`
call with a check for a prebuilt library at
`CMAKE_CURRENT_SOURCE_DIR/../objectbox-sync-c`. When the archive is present
there, CMake uses it instead of downloading at build time — required for
Flatpak sandbox builds where network access is not available.

**Usage:**

1. Copy `objectbox_sync_flutter_libs/5.3.1-CMakeLists.txt.patch` to
   `flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch`

2. Add to your `flutpak.yaml` (replace `5.3.1` with your locked version):

```yaml
manifest:
  sources:
    - type: archive
      only-arches: [x86_64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-sync-linux-x64.tar.gz
      sha256: 1d58e094b8cc5f08739748fa4113e983002c24784caa2674d3a0a51467831ea9
      dest: .pub-cache/hosted/pub.dev/objectbox_sync_flutter_libs-5.3.1/objectbox-sync-c
      strip-components: 0
    - type: archive
      only-arches: [aarch64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-sync-linux-aarch64.tar.gz
      sha256: 3f902002d93d0d26825e033212eeb3fdcbc6e15961b631a6f747b874b191f635
      dest: .pub-cache/hosted/pub.dev/objectbox_sync_flutter_libs-5.3.1/objectbox-sync-c
      strip-components: 0

patches:
  - package: objectbox_sync_flutter_libs
    path: flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch
    use-git: true
```

---

## `objectbox_sync_flutter_libs/5.3.2-CMakeLists.txt.patch`

**Package:** `objectbox_sync_flutter_libs`  
**Version:** `5.3.2`  
**What it does:** Same as the 5.3.1 patch — uses
`CMAKE_CURRENT_SOURCE_DIR/../objectbox-sync-c` to find the prebuilt library.

> **Note on line endings:** `objectbox_sync_flutter_libs` 5.3.2 ships
> `linux/CMakeLists.txt` with CRLF line endings in the pub.dev archive. The
> patch was generated from the CRLF source via `git diff`, so its context lines
> also have CRLF. Use `crlf: true` to ensure the patch is stored and applied
> as CRLF regardless of your git checkout settings.

**Usage:**

1. Copy `objectbox_sync_flutter_libs/5.3.2-CMakeLists.txt.patch` to
   `flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch`

2. Add to your `flutpak.yaml` (replace `5.3.2` with your locked version):

```yaml
manifest:
  sources:
    - type: archive
      only-arches: [x86_64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-sync-linux-x64.tar.gz
      sha256: dd18c0c8c809290a0dc052047971297202c60f4455e8d470749555e1da750fa8
      dest: .pub-cache/hosted/pub.dev/objectbox_sync_flutter_libs-5.3.2/objectbox-sync-c
      strip-components: 0
    - type: archive
      only-arches: [aarch64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-sync-linux-aarch64.tar.gz
      sha256: bacd88e26fde7f5ab07bf62a0643d70bc1da53ee291c70207b2e4b996ac68934
      dest: .pub-cache/hosted/pub.dev/objectbox_sync_flutter_libs-5.3.2/objectbox-sync-c
      strip-components: 0

patches:
  - package: objectbox_sync_flutter_libs
    path: flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch
    use-git: true
    crlf: true
```

---

## `objectbox_flutter_libs/5.3.1-CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.1`  
**What it does:** Replaces the unconditional `FetchContent_Populate(objectbox-download)`
call with a check for a prebuilt library at
`CMAKE_CURRENT_SOURCE_DIR/../objectbox-c`. When the archive is present
there, CMake uses it instead of downloading at build time — required for
Flatpak sandbox builds where network access is not available.

**Usage:**

1. Copy `objectbox_flutter_libs/5.3.1-CMakeLists.txt.patch` to
   `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch`

2. Add to your `flutpak.yaml` (replace `5.3.1` with your locked version):

```yaml
manifest:
  sources:
    - type: archive
      only-arches: [x86_64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-linux-x64.tar.gz
      sha256: d1a22f5a43e8aa438c987524c2ef97f5d179acb991b0f63ab03a30c33b882368
      dest: .pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1/objectbox-c
      strip-components: 0
    - type: archive
      only-arches: [aarch64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-linux-aarch64.tar.gz
      sha256: 948fe456904b8b0ae6b22a26a9f460734dc3c2ec58750df3a329ccae1ebe035d
      dest: .pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1/objectbox-c
      strip-components: 0

patches:
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
    use-git: true
```

---

## `objectbox_flutter_libs/5.3.2-CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.2`  
**What it does:** Same as the 5.3.1 patch — uses
`CMAKE_CURRENT_SOURCE_DIR/../objectbox-c` to find the prebuilt library.

> **Note on line endings:** `objectbox_flutter_libs` 5.3.2 ships
> `linux/CMakeLists.txt` with CRLF line endings in the pub.dev archive. The
> patch was generated from the CRLF source via `git diff`, so its context lines
> also have CRLF. Use `crlf: true` to ensure the patch is stored and applied
> as CRLF regardless of your git checkout settings.

**Usage:**

1. Copy `objectbox_flutter_libs/5.3.2-CMakeLists.txt.patch` to
   `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch`

2. Add to your `flutpak.yaml` (replace `5.3.2` with your locked version):

```yaml
manifest:
  sources:
    - type: archive
      only-arches: [x86_64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-linux-x64.tar.gz
      sha256: 6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613
      dest: .pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.2/objectbox-c
      strip-components: 0
    - type: archive
      only-arches: [aarch64]
      url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-linux-aarch64.tar.gz
      sha256: bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8
      dest: .pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.2/objectbox-c
      strip-components: 0

patches:
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
    use-git: true
    crlf: true
```

---

## `sqlite3/3.0.0-assets.dart.patch`

**Package:** `sqlite3`  
**Version:** `3.0.0` (applies to 3.0.0 – 3.2.x)  
**What it does:** Replaces the hash-derived download directory name with the
fixed string `'download-static'` in
`lib/src/hook/assets.dart`. This makes the pre-placed prebuilt library
discoverable at a known, predictable path instead of a runtime-computed one.

Also requires `sqlite3/3.0.0-build.dart.patch` (see below).

**Usage:**

1. Copy `sqlite3/3.0.0-assets.dart.patch` to
   `flatpak/patches/sqlite3/assets.dart.patch`

2. Copy `sqlite3/3.0.0-build.dart.patch` to
   `flatpak/patches/sqlite3/build.dart.patch`

3. Add to your `flutpak.yaml`:

```yaml
manifest:
  sources:
    - type: file
      only-arches: [x86_64]
      url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.1.1/libsqlite3.x64.linux.so
      sha256: c8a46dcdd4f59cb43aa2502311cfd2ad75a50d9b3a91812a3f634ff5fb3486be
      dest: .dart_tool/hooks_runner/shared/sqlite3/build/download-static
    - type: file
      only-arches: [aarch64]
      url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.1.1/libsqlite3.arm64.linux.so
      sha256: d581eb8af67a006cdfa5c634af773652df18aa586a02514f8da09129045c4ebb
      dest: .dart_tool/hooks_runner/shared/sqlite3/build/download-static

patches:
  - package: sqlite3
    path: flatpak/patches/sqlite3/assets.dart.patch
    use-git: true
  - package: sqlite3
    path: flatpak/patches/sqlite3/build.dart.patch
    use-git: true
```

> **Note:** `dest` paths in `manifest.sources` are relative to the Flatpak
> build directory, which equals the project root when `pubspec.yaml` is at the
> repository root. If your `pubspec.yaml` is in a subdirectory, prepend that
> subdirectory to the `dest` paths above.

---

## `sqlite3/3.0.0-build.dart.patch`

**Package:** `sqlite3`  
**Version:** `3.0.0` (applies to 3.0.0 – 3.2.x)  
**What it does:** Wraps the download logic in `hook/build.dart` with an
existence check (`if (!await File(target.path).exists())`), so the build hook
skips the network fetch when the prebuilt library is already present at
the expected path. Required alongside `assets.dart.patch` for 3.0.x.

See `sqlite3/3.0.0-assets.dart.patch` above for usage.

---

## `sqlite3/3.3.0-assets.dart.patch`

**Package:** `sqlite3`  
**Version:** `3.3.0` (applies to 3.3.0 and later)  
**What it does:** Same as the 3.0.0 `assets.dart.patch` — fixes the download
directory name to `'download-static'`. In 3.3.0 the build hook already skips
the download when the file is present, so `build.dart.patch` is no longer
needed.

**Usage:**

1. Copy `sqlite3/3.3.0-assets.dart.patch` to
   `flatpak/patches/sqlite3/assets.dart.patch`

2. Add to your `flutpak.yaml`:

```yaml
manifest:
  sources:
    - type: file
      only-arches: [x86_64]
      url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.1/libsqlite3.x64.linux.so
      sha256: 148c51687ac3be3487873845690ddbf3d8ee099a5521a193c856008907fb7361
      dest: .dart_tool/hooks_runner/shared/sqlite3/build/download-static
      dest-filename: libsqlite3.so
    - type: file
      only-arches: [aarch64]
      url: https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.1/libsqlite3.arm64.linux.so
      sha256: 0541443d38cd79160f6262e6a59892657d640459fef8acdd1f4f29a4ed0d2612
      dest: .dart_tool/hooks_runner/shared/sqlite3/build/download-static
      dest-filename: libsqlite3.so

patches:
  - package: sqlite3
    path: flatpak/patches/sqlite3/assets.dart.patch
    use-git: true
```

> **Note:** `dest` paths in `manifest.sources` are relative to the Flatpak
> build directory, which equals the project root when `pubspec.yaml` is at the
> repository root. If your `pubspec.yaml` is in a subdirectory, prepend that
> subdirectory to the `dest` paths above.
