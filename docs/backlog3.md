# Plan: Rust/Cargo підтримка в flutpak

## Як це влаштовано у flatpak-flutter

**Три окремих механізми:**

### 1. `foreign_deps.json` — новий формат для Rust пакетів
Записи для Cargokit-based пакетів мають два нові поля поряд із `manifest`:
```json
"rhttp": {
  "0.12.0": {
    "cargo_locks": ["$PUB_DEV/rust"],
    "extra_pubspecs": ["$PUB_DEV/cargokit/build_tool"],
    "manifest": {
      "sources": [{ "type": "patch", "path": "cargokit/run_build_tool.sh.patch", "dest": "$PUB_DEV/cargokit" }]
    }
  }
}
```
- `cargo_locks` — шляхи до `Cargo.lock` файлів (відносно директорії пакету, `$PUB_DEV` як плейсхолдер)
- `extra_pubspecs` — додаткові Dart pubspec-и (cargokit build_tool має свій pub lock)

Пакети у реєстрі: `rhttp`, `flutter_vodozemac`, `super_native_extensions`, `metadata_god`, `flutter_discord_rpc`.

### 2. `cargo_generator.py` — парсить `Cargo.lock`, генерує flatpak sources
- Читає TOML, для кожного crates.io пакету → `archive` (.crate файл) + `inline` (`.cargo-checksum.json`)
- Для git deps → `git` source + `shell` (cp) + `inline` Cargo.toml + `inline` checksum
- Дописує `inline` запис із `cargo/config.toml` що встановлює vendored-sources
- **Checksums беруться прямо з `Cargo.lock`** — мережа не потрібна для crates.io пакетів

### 3. `rustup_generator.py` — генерує окремий Flatpak модуль для встановлення Rust
- Скачує `channel-rust-{version}.toml` з `static.rust-lang.org` → отримує URLs і checksums
- Генерує модуль `rustup` що встановлює toolchain офлайн під час збірки
- `CARGO_HOME=/run/build/{app}/cargo`, `RUSTUP_HOME=/var/lib/rustup`
- App module отримує `CARGO_HOME`/`RUSTUP_HOME` env + `{rustupPath}/bin` в `append-path`

### Ключовий патч
`cargokit/run_build_tool.sh.patch` — додає `--offline` до `pub get` в Cargokit, щоб він не ліз у мережу під час Flatpak збірки.

---

## Отримання Cargo.lock файлів у flutpak

**Корінна відмінність:** flatpak-flutter клонує репо і запускає `flutter pub get` локально → читає `Cargo.lock` з розпакованих пакетів. flutpak цього **не робить**.

**Рішення: завантажити pub package archive з pub.dev і витягнути `Cargo.lock` з нього.**

flutpak вже знає точні версії всіх пакетів з `pubspec.lock`. Pub.dev публікує кожен пакет як tar.gz за детермінованою URL:
```
https://pub.dev/packages/{name}/versions/{version}.tar.gz
```
Це **той самий архів**, що вже потрапляє в `generated-sources.json` для flatpak-builder. flutpak завантажує його, витягує лише потрібні `Cargo.lock` файли (шляхи вказані у `cargo_locks` в реєстрі), потім обробляє.

Архів кешується в `~/.cache/flutpak/` по SHA-256 URL (як вже робиться для registry fetch) — повторні запуски безплатні.

**Переваги:**
- Не потребує `flutter pub get` перед запуском
- Не залежить від стану `~/.pub-cache`
- Детерміновано — версія зафіксована в `pubspec.lock`
- Без додаткових передумов для CI

---

## Детальний план впровадження

### Фаза 1 — Залежності та базова інфраструктура

**1.1** Додати TOML-парсер до `flutpak/pubspec.yaml`:
```yaml
dependencies:
  toml: ^0.6.0
```

**1.2** Додати `lib/src/generators/cargo_sources.dart` — порт `cargo_generator.py`:

```dart
// Входить: список шляхів до Cargo.lock
// Виходить: List<Map<String,dynamic>> (flatpak-builder sources format) + config.toml inline
class CargoSourcesGenerator {
  static Future<List<Map<String, dynamic>>> generate(
    List<String> cargoLockPaths, {
    String configFilename = 'config.toml',
  }) async { ... }
}
```

Внутрішня логіка:
- Parse TOML кожного `Cargo.lock`
- Для `registry+` packages: `archive` (`https://static.crates.io/crates/{name}/{name}-{ver}.crate`, sha256 з lock) + `inline` (`.cargo-checksum.json`)
- Для `git+` packages: `git` source + `shell` (cp) + `inline` Cargo.toml + `inline` checksum (MVP: warn + skip)
- Дедуплікація по `(type, url, dest)`
- Фінальний `inline` запис: `cargo/config.toml` з vendored-sources конфігом

**1.3** Додати `lib/src/generators/rustup_generator.dart` — порт `rustup_generator.py`:

```dart
class RustupGenerator {
  final String rustVersion;
  final String rustupPath;

  Future<Map<String, dynamic>> generateModule() async {
    // Fetch channel-rust-{version}.toml → отримати URLs+sha256 для rustup-init, cargo, rust-std, rustc
    // Return повний Flatpak module map
  }
}
```

### Фаза 2 — Розширення ForeignDepsRegistry

**2.1** У `foreign_deps_registry.dart` розширити парсинг записів.

Поточна структура повернення `resolve()`:
```dart
Future<List<Map<String, dynamic>>> resolve(...)
```

Нова структура:
```dart
class ForeignDepsResult {
  final List<Map<String, dynamic>> sources;
  final List<String> cargoLockPaths;    // resolved $PUB_DEV → actual paths
  final List<String> extraPubspecPaths; // for extra pub locks inclusion
}

Future<ForeignDepsResult> resolve(...)
```

**2.2** При резолюції кожного запису — розпізнавати поля `cargo_locks` і `extra_pubspecs`. Для кожного пакету де є `cargo_locks`:

1. Скласти URL пакету: `https://pub.dev/packages/{name}/versions/{version}.tar.gz`
2. Завантажити архів (з кешу `~/.cache/flutpak/` якщо є)
3. Витягнути з архіву файли за шляхами з `cargo_locks` (підставивши `$PUB_DEV` → `""`, тобто корінь архіву) у temp dir
4. Повернути реальні шляхи до витягнутих `Cargo.lock` файлів

**2.3** Аналогічно для `extra_pubspecs` — витягнути `pubspec.lock` з відповідних підпапок архіву і включити в `extraPubspecPaths`.

### Фаза 3 — Розширення конфігу

**3.1** У `config.dart` додати до `FlatpakGenConfig`:

```dart
/// Explicit Cargo.lock paths (rust.locks in YAML), in addition to registry-discovered ones.
/// Paths relative to project root or absolute.
final List<String> rustLocks;

/// Rust toolchain version for rustup module generation.
/// Defaults to '1.94.0' when Rust deps are present.
final String? rustVersion;

/// RUSTUP_HOME path inside the Flatpak environment.
/// Defaults to '/var/lib/rustup'.
final String? rustupPath;
```

YAML конфіг:
```yaml
rust:
  version: "1.94.0"           # за замовчуванням
  rustup-path: /var/lib/rustup # за замовчуванням
  locks:                       # явні Cargo.lock (зазвичай не потрібні — авто з реєстру)
    - path/to/some/Cargo.lock
```

### Фаза 4 — Інтеграція у generate command

**4.1** У `generate_command.dart::runWithArgs()`, після `registry.resolve()`:

```dart
final depsResult = await registry.resolve(
  lockPaths: effectiveLocks,
  localForeignDeps: cfg.localForeignDeps,
  generatedPatchesDir: generatedPatchesDir,
  projectPatchesDir: p.join(outputDir, 'patches'),
  // registry.resolve() тепер сам завантажує pub архіви і витягує Cargo.lock у temp dir
);

final allCargoLockPaths = [
  ...depsResult.cargoLockPaths,                                              // з реєстру (auto)
  ...cfg.rustLocks.map((l) => p.isAbsolute(l) ? l : p.join(baseDir, l)), // explicit з config (rust.locks)
].toList();
```

**4.2** Генерація cargo/rustup артефактів:

```dart
String? generatedCargoSourcesPath;
String? generatedRustupModulePath;

if (allCargoLockPaths.isNotEmpty) {
  final rustVersion = cfg.rustVersion ?? '1.94.0';
  final rustupPath = cfg.rustupPath ?? '/var/lib/rustup';

  // cargo sources
  final cargoSources = await CargoSourcesGenerator.generate(allCargoLockPaths);
  generatedCargoSourcesPath = p.join(generatedDir, 'cargo-sources.json');
  File(generatedCargoSourcesPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(cargoSources));
  logInfo('✓  cargo sources → cargo-sources.json');

  // rustup module
  final rustupGen = RustupGenerator(rustVersion: rustVersion, rustupPath: rustupPath);
  final rustupModule = await rustupGen.generateModule();
  generatedRustupModulePath = p.join(generatedDir, 'rustup-$rustVersion.json');
  File(generatedRustupModulePath)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(rustupModule));
  logInfo('✓  rustup module → rustup-$rustVersion.json');
}
```

**4.3** Передати в `_injectGeneratedContent()`:

```dart
generatedContent = _injectGeneratedContent(
  content: generatedContent,
  manifestCfg: manifestCfg,
  extraModules: cfg.extraModules,
  sourcesPath: sourcesPath,
  cargoSourcesPath: generatedCargoSourcesPath,      // NEW
  rustupModulePath: generatedRustupModulePath,      // NEW
  rustVersion: cfg.rustVersion ?? '1.94.0',         // NEW
  rustupPath: cfg.rustupPath ?? '/var/lib/rustup',  // NEW
  tag: tag,
  commit: commit,
);
```

**4.4** У `_injectGeneratedContent()`:

Якщо `rustupModulePath != null`:
- Вставити rustup модуль у `modules` перед app модулем (аналогічно `extraModules`)
- Додати `cargo-sources.json` до sources app модуля
- Дописати/злити до `build-options.env`: `CARGO_HOME`, `RUSTUP_HOME`
- Дописати до `build-options.append-path`: `{rustupPath}/bin`

### Фаза 5 — Оновлення foreign_deps у flutpak репо

**5.1** Перенести Cargokit-based записи з `flatpak-flutter/foreign_deps/foreign_deps.json` до `flutpak/foreign_deps/foreign_deps.json`:
- `rhttp`
- `flutter_vodozemac`
- `super_native_extensions`
- `metadata_god`
- `flutter_discord_rpc`

З полями `cargo_locks` та `extra_pubspecs`.

**5.2** Скопіювати `cargokit/run_build_tool.sh.patch` з flatpak-flutter до `flutpak/foreign_deps/cargokit/`.

### Фаза 6 — Тести

**6.1** Юніт-тест для `CargoSourcesGenerator`:
- Fixture: мінімальний `Cargo.lock` з кількома crates.io пакетами
- Assert: коректні `archive` + `inline` + `config.toml` у виводі

**6.2** Тест для `ForeignDepsRegistry`:
- Запис з `cargo_locks` + `extra_pubspecs`
- Assert: `ForeignDepsResult.cargoLockPaths` містить правильно розрезолвлені шляхи

**6.3** Оновити `config_test.dart`:
- Тест парсингу `rust.version`, `rust.rustup-path`, `rust.locks` з YAML

---

## Обмеження MVP

| Обмеження | Причина |
|-----------|---------|
| Git crate залежності (git+https) — тільки warn+skip | Потребує клонування репо під час генерації |
| Rust toolchain версія зафіксована або explicit | `stable` динамічно не резолвиться без мережі |
| pub.dev недоступний | `generate` потребує мережі для завантаження pub архівів (аналогічно registry fetch) |
| Тільки `x86_64`/`aarch64` arch | Відповідає flatpak-flutter |

Git crate залежності зустрічаються рідко (практично ніколи у Flutter плагінах), тому MVP без них повністю покриває реальні use cases.

---

## Порядок реалізації (з урахуванням залежностей)

```
Фаза 1.1 (toml dep)
    → Фаза 1.2 (CargoSourcesGenerator)
    → Фаза 1.3 (RustupGenerator)          // потребує HTTP, паралельно з 1.2
→ Фаза 2 (Registry extension)             // потребує нову структуру result
→ Фаза 3 (Config extension)
→ Фаза 4 (Generate command)               // все разом
→ Фаза 5 (foreign_deps оновлення)
→ Фаза 6 (Тести)
```
