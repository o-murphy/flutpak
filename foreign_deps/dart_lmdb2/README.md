# dart_lmdb2

`dart_lmdb2`'s `LMDBNative._resolveLibraryPath()` (`lib/src/lmdb_native.dart`) locates
`liblmdb.so`/`.dylib`/`.dll` at runtime via `Isolate.resolvePackageUriSync()` on a
`package:dart_lmdb2/...` URI. That API is backed by `.dart_tool/package_config.json` —
a dev-time artifact that only exists next to a JIT run (`dart run`/`flutter run`), not
inside a compiled AOT release build.

**Confirmed empirically, not just reasoned through:** built a scratch Flutter Linux app
depending on `dart_lmdb2`, ran `flutter build linux --release`, copied only
`build/linux/x64/release/bundle/` to an isolated directory (no source project, no
pub-cache — the same shape a Flatpak install has), and ran the binary. It crashed
immediately on the first `LMDB()` construction:

```
Unsupported operation: Isolate.resolvePackageUriSync
#1  LMDBNative._resolveLibraryPath (package:dart_lmdb2/src/lmdb_native.dart:89)
```

This isn't Flatpak-specific — it breaks **every** compiled Flutter Linux/Windows release
build using `dart_lmdb2`, regardless of how `liblmdb.so` itself was obtained (downloaded
via `fetch_native` or compiled from the vendored `mdb.c`/`midl.c` via `dart run
dart_lmdb2:build`). The prebuilt-vs-source-build question is a separate, smaller concern;
this patch fixes the deeper one — the code crashes before it even gets to opening a file.

## The fix

`0.9.12-lmdb_native.dart.patch` changes `_resolveLibraryPath()`'s non-Android/iOS branch
to:
1. Try `Isolate.resolvePackageUriSync()` first, wrapped in `try`/`on UnsupportedError` —
   keeps working exactly as before for `dart run`/`flutter run` (dev-time JIT use).
2. On `UnsupportedError` (AOT/release), or if the resolved path doesn't actually exist,
   fall back to a path next to the running executable:
   `<exe_dir>/lib/<libName>`, then `<exe_dir>/<libName>`.

`<exe_dir>/lib/` matches where Flutter's own native-library bundling convention already
places plugin libraries (confirmed in the same probe:
`build/linux/x64/release/bundle/lib/libapp.so` and `libflutter_linux_gtk.so` sit right
there) — so once a Linux-supporting plugin (see the `flutter_lmdb2` entry) copies
`liblmdb.so` into that same directory, this resolves correctly with no further
changes.

**Re-verified after patching, same probe methodology:** rebuilt the scratch app with the
patched package, copied `bundle/` to an isolated directory again — without
`liblmdb.so` present, it now fails with a plain, descriptive `FileSystemException`
instead of crashing; after copying `liblmdb.so` into `bundle/lib/` (mirroring what a
proper plugin build step would do), the app opened a real LMDB store successfully.

## Upstream

This is a genuine upstream bug (affects every consumer's release build, not just
Flatpak's offline constraint) — worth reporting to
[grammatek/dart_lmdb2](https://github.com/grammatek/dart_lmdb2), not just patching
locally forever.

## Why `patch -p1` against `$PUB_DEV` (not `--binary`, unlike the objectbox entry)

This patch targets a plain LF-encoded Dart source file (not a CRLF-sensitive
`CMakeLists.txt` fetched from Windows-authored history like the objectbox one), so a
plain `patch -p1` applies cleanly — verified by applying it to a fresh, unpatched copy
of `0.9.12`'s `lib/src/lmdb_native.dart` and diffing the result byte-for-byte against
the hand-tested, empirically-verified patched version.
