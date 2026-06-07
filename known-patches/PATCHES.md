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

## `objectbox_sync_flutter_libs/5.3.1/CMakeLists.txt.patch`

**Package:** `objectbox_sync_flutter_libs`  
**Version:** `5.3.1`  
**What it does:** Replaces the unconditional `FetchContent_Populate(objectbox-download)`
call with a check for `OBJECTBOX_PREBUILT_DIR` (CMake variable or env var).
When set and pointing to a directory that contains `lib/libobjectbox.so`, the
prebuilt sync archive is used instead of downloading at build time — required for
Flatpak sandbox builds where network access is not available.

**Usage:**

1. Copy `objectbox_sync_flutter_libs/5.3.1/objectbox-sync-c.yml` to `flatpak/modules/objectbox-sync-c.yml`

2. Copy `objectbox_sync_flutter_libs/5.3.1/CMakeLists.txt.patch` to `flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch`

3. Add to your `flutpak.yaml`:

```yaml
modules:
  - flatpak/modules/objectbox-sync-c.yml

manifest:
  env:
    OBJECTBOX_PREBUILT_DIR: /app

patches:
  - package: objectbox_sync_flutter_libs
    path: flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch
```

---

## `objectbox_sync_flutter_libs/5.3.2/CMakeLists.txt.patch`

**Package:** `objectbox_sync_flutter_libs`  
**Version:** `5.3.2`  
**What it does:** Same as the 5.3.1 patch — adds `OBJECTBOX_PREBUILT_DIR` support
for offline/sandboxed Flatpak builds.

> **Note on line endings:** `objectbox_sync_flutter_libs` 5.3.2 ships
> `linux/CMakeLists.txt` with CRLF line endings in the pub.dev archive. Use
> `crlf: true` so `flutpak generate` normalises the patch to CRLF in
> `generated/patches/` and adds `--binary` to the patch options, allowing
> `patch(1)` to apply it directly to the CRLF target without line-ending
> mismatches.

**Usage:**

1. Copy `objectbox_sync_flutter_libs/5.3.2/objectbox-sync-c.yml` to `flatpak/modules/objectbox-sync-c.yml`

2. Copy `objectbox_sync_flutter_libs/5.3.2/CMakeLists.txt.patch` to `flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch`

3. Add to your `flutpak.yaml`:

```yaml
modules:
  - flatpak/modules/objectbox-sync-c.yml

manifest:
  env:
    OBJECTBOX_PREBUILT_DIR: /app

patches:
  - package: objectbox_sync_flutter_libs
    path: flatpak/patches/objectbox_sync_flutter_libs/CMakeLists.txt.patch
    crlf: true
```

---

## `objectbox_flutter_libs/5.3.1/CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.1`  
**What it does:** Replaces the unconditional `FetchContent_Populate(objectbox-download)`
call with a check for `OBJECTBOX_PREBUILT_DIR` (CMake variable or env var).
When set and pointing to a directory that contains `lib/libobjectbox.so`, the
prebuilt archive is used instead of downloading at build time — required for
Flatpak sandbox builds where network access is not available.

**Usage:**

1. Copy `objectbox_flutter_libs/5.3.1/objectbox-c.yml` to `flatpak/modules/objectbox-c.yml`

2. Copy `objectbox_flutter_libs/5.3.1/CMakeLists.txt.patch` to `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch`

3. Add to your `flutpak.yaml`:

```yaml
modules:
  - flatpak/modules/objectbox-c.yml

manifest:
  env:
    OBJECTBOX_PREBUILT_DIR: /app

patches:
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
```

---

## `objectbox_flutter_libs/5.3.2/CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.2`  
**What it does:** Same as the 5.3.1 patch — adds `OBJECTBOX_PREBUILT_DIR` support
for offline/sandboxed Flatpak builds.

> **Note on line endings:** `objectbox_flutter_libs` 5.3.2 ships
> `linux/CMakeLists.txt` with CRLF line endings in the pub.dev archive. Use
> `crlf: true` so `flutpak generate` normalises the patch to CRLF in
> `generated/patches/` and adds `--binary` to the patch options, allowing
> `patch(1)` to apply it directly to the CRLF target without line-ending
> mismatches.

**Usage:**

1. Copy `objectbox_flutter_libs/5.3.2/objectbox-c.yml` to `flatpak/modules/objectbox-c.yml`

2. Copy `objectbox_flutter_libs/5.3.2/CMakeLists.txt.patch` to `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch`

3. Add to your `flutpak.yaml`:

```yaml
modules:
  - flatpak/modules/objectbox-c.yml

manifest:
  env:
    OBJECTBOX_PREBUILT_DIR: /app

patches:
  - package: objectbox_flutter_libs
    path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
    crlf: true
```
