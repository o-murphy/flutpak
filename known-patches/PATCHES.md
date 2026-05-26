# Known Patches

Patches for packages that commonly need modifications for Flatpak offline builds.

Copy the relevant `.patch` file to your project's `flatpak/patches/` directory
and reference it in `flutpak.yaml` (or `pubspec.yaml`):

```yaml
flutpak:
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

## `objectbox_flutter_libs/5.3.1/CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.1`  
**What it does:** Replaces the unconditional `FetchContent_Populate(objectbox-download)`
call with a check for `OBJECTBOX_PREBUILT_DIR` (CMake variable or env var).
When set and pointing to a directory that contains `lib/libobjectbox.so`, the
prebuilt archive is used instead of downloading at build time — required for
Flatpak sandbox builds where network access is not available.

**Usage:**

1. Add the objectbox-c prebuilt archive to `extra_sources` in your config:

```yaml
flutpak:
  manifest:
    env:
      OBJECTBOX_PREBUILT_DIR: /run/build/<appname>/objectbox-c
    extra_sources:
      - type: archive
        only-arches: [x86_64]
        url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-linux-x64.tar.gz
        sha256: <sha256>
        dest: objectbox-c
        strip-components: 0
      - type: archive
        only-arches: [aarch64]
        url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.1/objectbox-linux-aarch64.tar.gz
        sha256: <sha256>
        dest: objectbox-c
        strip-components: 0
```

2. Copy this patch to `flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch`

3. Add to your `flutpak.yaml`:

```yaml
flutpak:
  patches:
    - package: objectbox_flutter_libs
      path: flatpak/patches/objectbox_flutter_libs/CMakeLists.txt.patch
```
