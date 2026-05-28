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

---

## `objectbox_flutter_libs/5.3.2/CMakeLists.txt.patch`

**Package:** `objectbox_flutter_libs`  
**Version:** `5.3.2`  
**What it does:** Same as the 5.3.1 patch — adds `OBJECTBOX_PREBUILT_DIR` support
for offline/sandboxed Flatpak builds.

> **Note on line endings:** `objectbox_flutter_libs` 5.3.2 ships
> `linux/CMakeLists.txt` with CRLF line endings in the pub.dev archive, while
> this patch is stored with LF. Use `strip_trailing_cr: true` so flutpak injects
> a `type: shell` source that runs `sed -i 's/\r//'` on the file before the patch
> is applied. GNU `patch(1)` does not reliably handle CRLF/LF mismatches even
> with `--ignore-whitespace`.

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
        url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-linux-x64.tar.gz
        sha256: 6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613
        dest: objectbox-c
        strip-components: 0
      - type: archive
        only-arches: [aarch64]
        url: https://github.com/objectbox/objectbox-c/releases/download/v5.3.2/objectbox-linux-aarch64.tar.gz
        sha256: bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8
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
      strip_trailing_cr: true
```
