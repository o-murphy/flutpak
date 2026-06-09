# Plan: Flutter SDK як окремий модуль + кешування + перейменування

## Поточний стан

### Як зараз влаштовано

**`generate` команда:**
1. Створює `FlutterSdkGenerator(flutterRef: ...)`, викликає `flutterGen.generate()` → ~20 sources
2. `generateSourcesJson()` в `sources_util.dart` об'єднує pub sources + flutter sources + foreign-deps → один `generated-sources.json`
3. Flutter SDK джерела (git repo, engine artifacts, shared.sh patch, sky_engine pubspec, engine_stamp.json) лежать **всередині** `generated-sources.json` разом з pub пакетами
4. App module в маніфесті має `sources: [..., 'generated-sources.json']`

**`sdk-mod` команда:**
- Вже вміє генерувати окремий файл `flutter-sdk-{version}.json` у форматі Flatpak module:
  ```json
  {
    "name": "flutter-sdk",
    "buildsystem": "simple",
    "build-commands": ["cp ...", "mkdir -p /var/lib && cp -r flutter /var/lib"],
    "sources": [<git>, <engine artifacts>, <patches>, ...]
  }
  ```
- Але `generate` цим не користується — дублює логіку через `sources_util.dart`

### Проблеми поточного підходу

| Проблема | Наслідок |
|----------|----------|
| Flutter SDK (~20 entries) змішаний з pub пакетами (~300+ entries) в одному файлі | `generated-sources.json` — неточна назва, важко розібратись |
| Кожен запуск `generate` заново хешує всі engine артефакти | Повільно (~20–30 секунд на мережу) навіть якщо Flutter версія не змінилась |
| Rustup — окремий модуль, Flutter SDK — ні | Непослідовна архітектура |
| Немає поділу "звідки взялось": pub vs flutter vs foreign-deps | Складно відлагоджувати, складно підтримувати |

---

## Бажаний стан

### Структура після рефакторингу

```
generated/
  io.github.o_murphy.flutpak.demo.yml   ← фінальний маніфест
  pubspec-sources.json                   ← тільки pub пакети + foreign-deps
  cargo-sources.json                     ← cargo crates (якщо є)
  flutter-sdk-3.44.1.json               ← Flutter SDK модуль (новий файл)
  rustup-1.85.0.json                    ← Rustup модуль (існує)
  patches/
    flutter/shared.sh.patch
    cargokit/run_build_tool.sh.patch
```

**Маніфест modules:**
```yaml
modules:
  - flutter-sdk-3.44.1.json    ← string ref (як rustup)
  - rustup-1.85.0.json         ← string ref (вже є)
  - name: App
    sources:
      - type: git
        ...
      - pubspec-sources.json   ← pub пакети (було generated-sources.json)
      - cargo-sources.json
```

### Логіка кешування Flutter SDK модуля

Аналог `ForeignDepsRegistry`: flutpak перевіряє чи є готовий `flutter-sdk-{version}.json` у репозиторії flutpak (GitHub raw), завантажує і кешує — **без хешування артефактів**. Генерація як fallback, коли pre-built не знайдено.

```
https://raw.githubusercontent.com/o-murphy/flutpak/{ref}/flutter_sdk/flutter-sdk-{version}.json
```

---

## Детальний план впровадження

### Фаза 1 — Виділення Flutter SDK в окремий модуль у generate

**1.1** Видалити `flutterGen` з `generateSourcesJson()` у `sources_util.dart`:

```dart
// Було:
Future<void> generateSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  FlutterSdkGenerator? flutterGen,          // ← прибрати
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async { ... }

// Стане: pub + foreign-deps тільки
Future<void> generatePubSourcesJson({
  required List<String> lockPaths,
  required String outputPath,
  List<Map<String, dynamic>> foreignDepSources = const [],
}) async { ... }
```

Функція більше не потребує `FlutterSdkGenerator` — логи змінити з `"flutter: N entries"` → відсутні.

**1.2** У `generate_command.dart::runWithArgs()` — генерувати Flutter SDK модуль окремо, аналогічно до rustup:

```dart
// Після блоку cargo/rustup:
String? flutterSdkModule;
if (flutterGen != null) {
  // Fetch flutter_tools lock для pub sources (не змінюється)
  final toolsLockContent = await flutterGen.fetchFlutterToolsLock();
  toolsLockFile = ...;
  allLockPaths = [...allPubLockPaths, toolsLockFile.path];

  // Generate standalone flutter-sdk module
  final sdkSources = await flutterGen.generate();
  final gitSrc = sdkSources.whereType<GitSource>().firstOrNull;
  final flutterVersion = gitSrc?.tag ?? flutterRef;
  final sdkModuleFilename = 'flutter-sdk-$flutterVersion.json';
  final sdkModulePath = p.join(generatedDir, sdkModuleFilename);

  final module = {
    'name': 'flutter-sdk',
    'buildsystem': 'simple',
    'build-commands': FlutterSdkGenerator.buildCommands(),
    'sources': sdkSources.map((s) => s.toJson()).toList(),
  };
  File(sdkModulePath)
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(module));
  flutterSdkModule = sdkModuleFilename;
  logInfo('✓  flutter SDK module → $sdkModuleFilename');
}
```

**1.3** Передати `flutterSdkModule` у `injectGeneratedContent()`:

```dart
// Нова сигнатура:
String injectGeneratedContent({
  ...
  String? flutterSdkModule,   // NEW — filename ref, аналог rustupModule
  String? rustupModule,
  ...
})
```

**1.4** У `injectGeneratedContent()` — вставляти `flutterSdkModule` перед rustup модулем:

```
modules:
  - flutter-sdk-3.44.1.json   ← flutterSdkModule
  - rustup-1.85.0.json        ← rustupModule
  - App                       ← app module
```

Порядок вставки: спочатку `rustupModule` at `insertIdx`, потім `flutterSdkModule` at `insertIdx` — обидва до app module. Оскільки Flutter SDK потрібен перед Rust (Flutter install script потрібен для cargokit), він має бути першим.

**1.5** Оновити тести `generate_inject_test.dart`:
- Додати тест `'inserts flutter-sdk module before rustup'`
- Перевірити порядок: `modules[0] == 'flutter-sdk-3.44.1.json'`, `modules[1] == 'rustup-1.85.0.json'`, `modules[2]['name'] == 'App'`

---

### Фаза 2 — Перейменування generated-sources.json → pubspec-sources.json

**2.1** У `generate_command.dart::runWithArgs()`:

```dart
// Було:
final sourcesPath = p.join(generatedDir, 'generated-sources.json');

// Стане:
final sourcesPath = p.join(generatedDir, 'pubspec-sources.json');
```

**2.2** У `generateSourcesJson` → `generatePubSourcesJson` (вже перейменована у Фазі 1):
- Змінити лог: `'✓  N total sources → pubspec-sources.json'`
- Оновити docstring

**2.3** У `sources_util.dart` перейменувати функцію і оновити всі імпорти.

**2.4** У тестах:
- `generate_inject_test.dart` — `sourcesPath: '/out/pubspec-sources.json'`, assert `'pubspec-sources.json'`
- Будь-які інші тести що перевіряють ім'я файлу

**2.5** У документації/README та template маніфесті (якщо є посилання на `generated-sources.json`) — оновити назву.

**2.6** В `init_command.dart` (якщо генерує шаблон з `generated-sources.json`) — оновити.

**Backward compatibility:** команда `generate` тепер пише `pubspec-sources.json` замість `generated-sources.json`. Якщо у кого в маніфесті є hardcoded `generated-sources.json` — зламається. Не потрібна back-compat: це генерований файл, flutpak сам його прописує. Достатньо оновити `injectGeneratedContent`.

---

### Фаза 3 — Кешування / pre-built Flutter SDK модулів

**Ідея:** flutpak підтримує директорію `flutter_sdk/` у репозиторії з pre-built модулями для LTS/stable версій Flutter. Аналог foreign_deps: перевіряємо GitHub raw, завантажуємо і кешуємо локально. Якщо не знайдено — генеруємо як зараз.

**3.1** Додати клас `FlutterSdkRegistry` у `lib/src/flutter_sdk_registry.dart`:

```dart
class FlutterSdkRegistry {
  final String ref;         // flutpak branch/tag для пошуку
  final http.Client _client;
  final DownloadCache _cache;

  /// URL шаблон для pre-built модулів у flutpak репо.
  String moduleUrl(String flutterVersion) =>
      'https://raw.githubusercontent.com/o-murphy/flutpak/$ref'
      '/flutter_sdk/flutter-sdk-$flutterVersion.json';

  /// Спробувати завантажити pre-built модуль для [flutterVersion].
  /// Повертає JSON-рядок або null якщо не знайдено (HTTP 404 або мережева помилка).
  Future<String?> fetchPrebuilt(String flutterVersion) async {
    final url = moduleUrl(flutterVersion);
    try {
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        logInfo('flutter-sdk: pre-built module found for $flutterVersion');
        return resp.body;
      }
      if (resp.statusCode == 404) return null;
      logWarn('flutter-sdk: HTTP ${resp.statusCode} fetching pre-built module');
      return null;
    } catch (e) {
      logWarn('flutter-sdk: fetch failed ($e) — falling back to generation');
      return null;
    }
  }
}
```

**3.2** Кешування у `~/.cache/flutpak/flutter_sdk/`:
- Ключ кешу: `flutter-sdk-{version}.json`
- При знаходженні pre-built: зберегти в кеш
- При наступному запуску: завантажити з кешу без мережевого запиту

Cache invalidation: не потрібна — Flutter версія + хеші артефактів детерміновані. Якщо `flutter-sdk-3.44.1.json` є в кеші — він валідний завжди.

**3.3** Інтеграція у `generate_command.dart`:

```dart
// Замість прямого виклику flutterGen.generate():
String? flutterSdkModule;
if (flutterRef != null) {
  final sdkRegistry = FlutterSdkRegistry(ref: cfg.foreignDepsRef);
  final flutterVersion = await _resolveFlutterVersion(flutterRef);

  // 1. Спробувати pre-built
  String? moduleJson = await sdkRegistry.fetchPrebuilt(flutterVersion);

  // 2. Fallback: generate
  if (moduleJson == null) {
    logInfo('flutter-sdk: generating for $flutterVersion (not in registry)');
    final sdkSources = await flutterGen.generate();
    // ... build module map, jsonEncode
    moduleJson = jsonEncode(module);
    // Зберегти в кеш щоб наступний запуск не генерував знову
    sdkRegistry.cacheLocally(flutterVersion, moduleJson);
  }

  // 3. Записати у generated/ та включити в маніфест
  final sdkModuleFilename = 'flutter-sdk-$flutterVersion.json';
  File(p.join(generatedDir, sdkModuleFilename))
    ..createSync(recursive: true)
    ..writeAsStringSync(moduleJson);
  flutterSdkModule = sdkModuleFilename;
  logInfo('✓  flutter SDK module → $sdkModuleFilename');
}
```

**3.4** Ще один варіант кешування (простіший): `DownloadCache` вже є для SHA-256 URL кешування. Використовувати його напряму — якщо контент по URL не змінився (flutter-sdk-3.44.1.json в репо стабільний), він буде закешований автоматично через `_fetchCached`.

**3.5** `sdk-mod` команда — також може скористатись `FlutterSdkRegistry` для перевірки pre-built перед генерацією. Опціонально — `--no-cache` флаг для примусової регенерації.

---

### Фаза 4 — Оновлення sdk-mod команди

**4.1** `sdk-mod` — після того як flutter-sdk є окремим модулем у `generate`, `sdk-mod` стає офіційним способом **публікувати** нові Flutter SDK модулі у `flutter_sdk/` директорію репо.

**4.2** Додати флаг `--publish-path` або просто документувати що вихід `sdk-mod` можна покласти у `flutter_sdk/` flutpak репо для pre-built кешу:

```bash
# Генерувати pre-built модуль для нової версії Flutter:
flutpak sdk-mod --flutter 3.45.0 --output flutter_sdk/
# Потім комітити flutter_sdk/flutter-sdk-3.45.0.json у flutpak репо
```

---

### Фаза 5 — Тести

**5.1** `generate_inject_test.dart`:
- `'inserts flutter-sdk module ref before rustup and app'`
- `'inserts only rustup when flutterSdkModule is null'`
- `'appends pubspec-sources.json (not generated-sources.json) to sources'`

**5.2** Новий `flutter_sdk_registry_test.dart`:
- Mock HTTP: 200 → повертає pre-built JSON
- Mock HTTP: 404 → повертає null (fallback до генерації)
- Mock HTTP: error → повертає null з попередженням

**5.3** Оновити `integration/flutter_sdk_integration_test.dart` якщо є перевірки на ім'я `generated-sources.json`.

---

## Порядок реалізації

```
Фаза 1 (Flutter SDK → окремий модуль у generate)
    → усуває дублювання з sdk-mod
    → вже є вся необхідна інфраструктура
Фаза 2 (перейменування generated-sources → pubspec-sources)
    → один рядок зміни + оновлення тестів
    → краще зробити разом з Фазою 1 (один PR, щоб не ламати двічі)
Фаза 3 (FlutterSdkRegistry + кешування)
    → окремий PR, не блокує нічого
    → можна впроваджувати поступово
Фаза 4 (sdk-mod + публікація pre-built)
    → залежить від Фази 3
```

---

## Обмеження та граничні випадки

| Ситуація | Поведінка |
|----------|-----------|
| Pre-built недоступний (404) | Тихий fallback до генерації, без помилки |
| Мережева помилка при перевірці pre-built | Fallback до генерації + warn |
| Flutter версія не в registry (новий реліз) | Генерація, результат зберігається в локальний кеш |
| `--no-flutter` / `flutterRef == null` | Ні модуля, ні entries в pubspec-sources — без змін |
| Існуючий `generated-sources.json` у git | Застаріє після перейменування — залишити в .gitignore |
| `sdk-mod` після Фази 1 | Не змінюється — повна незалежність |
