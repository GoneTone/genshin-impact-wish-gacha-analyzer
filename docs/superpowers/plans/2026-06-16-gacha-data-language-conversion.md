# 卡池歷史資料語言轉換 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁新增獨立於 App UI 語言的「資料語言」設定，把混語言的卡池歷史資料統一成單一語言，名稱透過 HoYoWiki `get_entry_page_list` 取得並本地快取。

**Architecture:** 對齊姐妹專案（鳴潮 PR #32／#33）的 catalog 為核心架構。新增 per-language 名冊快取（`lang_catalog/<lang>.json`，`hoyowiki_id → {name, kind}`＋衍生 `idByName`）、三態設定（`dataLanguage` + `dataLanguageSeeded`）、轉換引擎（名稱回查＋未命中自動刷新）。轉換改寫存檔的 `name`／`lang`，並把 `(目標語言::目標名 → id, menu_id)` 寫回既有 `HoYoWikiIndex`（`setSearch`）以維持類型判定／詳情 lookup。失敗一律吞例外、回原資料。

**Tech Stack:** Flutter / Dart 3、Riverpod（Notifier/Provider）、`http` + `package:http/testing.dart`（MockClient）、SharedPreferences、`synchronized`、gen_l10n（ARB）。

**設計來源：** `docs/superpowers/specs/2026-06-16-gacha-data-language-conversion-design.md`

**全程指令一律優先用 `fvm`**（找不到才退回 `flutter`／`dart`）。每個 Task 結尾 commit；commit message 用英文 conventional commits。

---

### Task 1: `GachaRecord.copyWith` 支援 `name`

**Files:**
- Modify: `lib/models/gacha_record.dart`（現有 `copyWith` 只支援 `lang`）
- Test: `test/models/gacha_record_test.dart`

- [ ] **Step 1: 寫失敗測試**

在 `test/models/gacha_record_test.dart` 既有 `copyWith` 群組內新增：

```dart
test('copyWith overrides name and lang independently', () {
  final r = GachaRecord(
    id: '1', uid: 'u', gachaType: '301', name: '胡桃',
    itemType: '角色', rankType: 5, time: DateTime(2024), lang: 'zh-tw',
  );
  final byName = r.copyWith(name: 'Hu Tao');
  expect(byName.name, 'Hu Tao');
  expect(byName.lang, 'zh-tw'); // 未指定保持原值
  final both = r.copyWith(name: 'Hu Tao', lang: 'en-us');
  expect(both.name, 'Hu Tao');
  expect(both.lang, 'en-us');
  expect(both.id, '1'); // 其餘欄位不變
  expect(both.itemType, '角色');
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/models/gacha_record_test.dart`
Expected: FAIL（`copyWith` 不接受 `name` 具名參數，編譯錯誤）

- [ ] **Step 3: 最小實作**

把 `lib/models/gacha_record.dart` 末端的 `copyWith` 改為：

```dart
  /// 複製本 record，可覆寫 [name] 與／或 [lang]（其餘欄位沿用原值）。
  GachaRecord copyWith({String? name, String? lang}) => GachaRecord(
    id: id,
    uid: uid,
    gachaType: gachaType,
    name: name ?? this.name,
    itemType: itemType,
    rankType: rankType,
    time: time,
    lang: lang ?? this.lang,
  );
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/models/gacha_record_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/gacha_record.dart test/models/gacha_record_test.dart
git commit -m "feat(model): support name override in GachaRecord.copyWith"
```

---

### Task 2: 資料語言定義 `data_language.dart`

**Files:**
- Create: `lib/services/data_language.dart`
- Test: `test/services/data_language_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/data_language_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';

void main() {
  test('has 15 options with unique codes', () {
    expect(kDataLanguageOptions.length, 15);
    final codes = kDataLanguageOptions.map((o) => o.code).toList();
    expect(codes.toSet().length, 15); // 無重複
    expect(kDataLanguageCodes, codes.toSet());
  });

  test('isSupportedDataLanguage matches the option set', () {
    expect(isSupportedDataLanguage('zh-tw'), isTrue);
    expect(isSupportedDataLanguage('en-us'), isTrue);
    expect(isSupportedDataLanguage('ja-jp'), isTrue);
    expect(isSupportedDataLanguage('en'), isFalse); // 短碼非選項
    expect(isSupportedDataLanguage('xx-yy'), isFalse);
  });

  test('every label is non-empty', () {
    for (final o in kDataLanguageOptions) {
      expect(o.label.isNotEmpty, isTrue, reason: 'code=${o.code}');
    }
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/data_language_test.dart`
Expected: FAIL（檔案不存在）

- [ ] **Step 3: 最小實作**

`lib/services/data_language.dart`：

```dart
/// 單一可選資料語言：HoYoWiki 對齊的 [code] 與母語顯示 [label]。
typedef DataLanguageOption = ({String code, String label});

/// 可選資料語言清單（顯示順序固定），代碼對齊 HoYoLab Wiki，與 App UI 語言獨立。
const List<DataLanguageOption> kDataLanguageOptions = [
  (code: 'zh-tw', label: '繁體中文'),
  (code: 'zh-cn', label: '简体中文'),
  (code: 'en-us', label: 'English'),
  (code: 'ja-jp', label: '日本語'),
  (code: 'ko-kr', label: '한국어'),
  (code: 'es-es', label: 'Español'),
  (code: 'fr-fr', label: 'Français'),
  (code: 'ru-ru', label: 'Русский'),
  (code: 'th-th', label: 'ภาษาไทย'),
  (code: 'vi-vn', label: 'Tiếng Việt'),
  (code: 'de-de', label: 'Deutsch'),
  (code: 'id-id', label: 'Bahasa Indonesia'),
  (code: 'pt-pt', label: 'Português'),
  (code: 'tr-tr', label: 'Türkçe'),
  (code: 'it-it', label: 'Italiano'),
];

/// 可選資料語言代碼集合（供 seeding 判定語言是否在選項內）。
final Set<String> kDataLanguageCodes = {
  for (final o in kDataLanguageOptions) o.code,
};

/// [code] 是否為可選資料語言（用於自動播種：落在選項外則維持未設定）。
bool isSupportedDataLanguage(String code) => kDataLanguageCodes.contains(code);
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/data_language_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/data_language.dart test/services/data_language_test.dart
git commit -m "feat(langconvert): add data language option list (15 HoYoWiki locales)"
```

---

### Task 3: `convertibleGachaTypes`（非頌願 gacha_type 集合）

**Files:**
- Modify: `lib/data/gacha_types.dart`（在 `gachaTypes` 常數定義之後新增）
- Test: `test/data/gacha_types_test.dart`（若無此檔則新建）

- [ ] **Step 1: 寫失敗測試**

`test/data/gacha_types_test.dart`（無則新建，有則加入）：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';

void main() {
  test('convertibleGachaTypes is all non-odes gacha types', () {
    expect(convertibleGachaTypes, {'301', '302', '500', '200', '100'});
    expect(convertibleGachaTypes.contains('2000'), isFalse); // 頌願排除
    expect(convertibleGachaTypes.contains('1000'), isFalse);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/data/gacha_types_test.dart`
Expected: FAIL（`convertibleGachaTypes` 未定義）

- [ ] **Step 3: 最小實作**

在 `lib/data/gacha_types.dart` 的 `const gachaTypes = <GachaType>[...]` 之後新增：

```dart
/// 可做資料語言轉換的 gacha_type 集合（非頌願；物品落在 HoYoWiki menu 2／4）。
/// 由 [gachaTypes] 依 category 衍生（DRY），與 `_fetchHoYoWiki` 的
/// `hoyoWikiTargetGachaTypes` 一致。
final Set<String> convertibleGachaTypes = {
  for (final t in gachaTypes)
    if (t.category == GachaCategory.gacha) t.gachaType,
};
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/data/gacha_types_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/gacha_types.dart test/data/gacha_types_test.dart
git commit -m "feat(langconvert): add convertibleGachaTypes set (non-odes wishes)"
```

---

### Task 4: 設定三態（AppSettings + SettingsStorage）

**Files:**
- Modify: `lib/services/settings_storage.dart`（`AppSettings` 加兩欄＋`copyWith`；`SettingsStorage` 加 key 與三態 load/save）
- Test: `test/services/settings_storage_data_language_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/settings_storage_data_language_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent key -> uninitialized (null, not seeded)', () async {
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, isNull);
    expect(s.dataLanguageSeeded, isFalse);
  });

  test('"none" -> explicitly unset (null, seeded)', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'none'});
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, isNull);
    expect(s.dataLanguageSeeded, isTrue);
  });

  test('language code -> specified (code, seeded)', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'ja-jp'});
    final s = await SettingsStorage.load();
    expect(s.dataLanguage, 'ja-jp');
    expect(s.dataLanguageSeeded, isTrue);
  });

  test('save: not seeded removes key', () async {
    SharedPreferences.setMockInitialValues({'pref.dataLanguage': 'ja-jp'});
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguageSeeded: false),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), isNull);
  });

  test('save: seeded + null writes "none"', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguageSeeded: true),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), 'none');
  });

  test('save: seeded + code writes code', () async {
    await SettingsStorage.save(
      AppSettings.defaults.copyWith(dataLanguage: 'en-us', dataLanguageSeeded: true),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref.dataLanguage'), 'en-us');
  });

  test('copyWith clearDataLanguage resets to null', () async {
    final s = AppSettings.defaults.copyWith(dataLanguage: 'ja-jp', dataLanguageSeeded: true);
    final cleared = s.copyWith(clearDataLanguage: true);
    expect(cleared.dataLanguage, isNull);
    expect(cleared.dataLanguageSeeded, isTrue); // seeded 不被 clear 影響
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/settings_storage_data_language_test.dart`
Expected: FAIL（`dataLanguage`/`dataLanguageSeeded` 不存在）

- [ ] **Step 3: 最小實作**

在 `lib/services/settings_storage.dart` 的 `AppSettings`：

(a) constructor 末端參數新增：
```dart
    this.maskUidInUi = false,
    this.dataLanguage,
    this.dataLanguageSeeded = false,
  });
```

(b) field 區（`maskUidInUi` 之後）新增：
```dart
  /// 資料語言代碼（如 `ja-jp`）；null 代表未設定（停用轉換）。獨立於 App UI 語言。
  final String? dataLanguage;

  /// 資料語言是否已初始化（自動播種或使用者明確選擇過）。false 代表可被自動播種。
  final bool dataLanguageSeeded;
```

(c) `copyWith` 簽名與 body 加上（沿用既有 `clearXxx` 慣例）：
```dart
    bool? maskUidInUi,
    String? dataLanguage,
    bool clearDataLanguage = false,
    bool? dataLanguageSeeded,
  }) => AppSettings(
    // ……既有欄位不變……
    maskUidInUi: maskUidInUi ?? this.maskUidInUi,
    dataLanguage: clearDataLanguage ? null : (dataLanguage ?? this.dataLanguage),
    dataLanguageSeeded: dataLanguageSeeded ?? this.dataLanguageSeeded,
  );
```

在 `SettingsStorage`：

(d) key 常數區新增：
```dart
  /// SharedPreferences key：資料語言（語言碼／`"none"`／不存在 三態）。
  static const _kDataLanguage = 'pref.dataLanguage';
```

(e) `load()` 內（回傳 `AppSettings(...)` 之前先讀 raw，並補兩欄）：
```dart
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dataLangRaw = prefs.getString(_kDataLanguage);
    return AppSettings(
      themeMode: _parseThemeMode(prefs.getString(_kThemeMode)),
      locale: _parseLocale(prefs.getString(_kLocale)),
      lastActiveUid: prefs.getString(_kLastActiveUid),
      uidAliases: _parseAliases(prefs.getString(_kUidAliases)),
      uidOrder: _parseOrder(prefs.getString(_kUidOrder)),
      skippedReleaseTag: prefs.getString(_kSkippedReleaseTag),
      maskUidInUi: prefs.getBool(_kMaskUidInUi) ?? false,
      dataLanguage: dataLangRaw == null || dataLangRaw == 'none' ? null : dataLangRaw,
      dataLanguageSeeded: dataLangRaw != null,
    );
  }
```

(f) `save()` 末端（`setBool(_kMaskUidInUi, ...)` 之後）新增：
```dart
    if (!s.dataLanguageSeeded) {
      await prefs.remove(_kDataLanguage);
    } else {
      await prefs.setString(_kDataLanguage, s.dataLanguage ?? 'none');
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/settings_storage_data_language_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/settings_storage.dart test/services/settings_storage_data_language_test.dart
git commit -m "feat(settings): persist three-state data language preference"
```

---

### Task 5: SettingsNotifier setter／seeder ＋ provider

**Files:**
- Modify: `lib/state/settings.dart`（新增 `setDataLanguage`／`seedDataLanguageIfUnset`／`dataLanguageProvider`）
- Test: `test/state/settings_data_language_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/state/settings_data_language_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('setDataLanguage(code) sets value and marks seeded', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setDataLanguage('en-us');
    expect(c.read(settingsProvider).dataLanguage, 'en-us');
    expect(c.read(settingsProvider).dataLanguageSeeded, isTrue);
    expect(c.read(dataLanguageProvider), 'en-us');
  });

  test('setDataLanguage(null) marks seeded (explicit no-convert)', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setDataLanguage(null);
    expect(c.read(settingsProvider).dataLanguage, isNull);
    expect(c.read(settingsProvider).dataLanguageSeeded, isTrue);
  });

  test('seedDataLanguageIfUnset seeds only when not seeded and code supported', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();

    await notifier.seedDataLanguageIfUnset('zh-tw');
    expect(c.read(settingsProvider).dataLanguage, 'zh-tw');

    // 已 seeded：不再被覆蓋
    await notifier.seedDataLanguageIfUnset('en-us');
    expect(c.read(settingsProvider).dataLanguage, 'zh-tw');
  });

  test('seedDataLanguageIfUnset no-op for unsupported code', () async {
    final c = makeContainer();
    final notifier = c.read(settingsProvider.notifier);
    await notifier.waitForLoad();
    await notifier.seedDataLanguageIfUnset('en'); // 短碼非選項
    expect(c.read(settingsProvider).dataLanguage, isNull);
    expect(c.read(settingsProvider).dataLanguageSeeded, isFalse);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/state/settings_data_language_test.dart`
Expected: FAIL（方法／provider 未定義）

- [ ] **Step 3: 最小實作**

在 `lib/state/settings.dart`：

(a) 檔頭 import：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';
```

(b) `SettingsNotifier` 內新增（接在 `setLocale` 之後）：
```dart
  /// 設定資料語言並持久化；[code] 為 null 代表使用者明確選「未設定（不轉換）」。
  /// 任何呼叫都標記 `dataLanguageSeeded=true`，停止後續自動播種。
  Future<void> setDataLanguage(String? code) async {
    state = state.copyWith(
      dataLanguage: code,
      clearDataLanguage: code == null,
      dataLanguageSeeded: true,
    );
    await SettingsStorage.save(state);
    Logger('app.settings').info('dataLanguage set=${code ?? 'none'}');
  }

  /// 僅當尚未初始化（`!dataLanguageSeeded`）且 [code] 屬可選資料語言時，
  /// 以 [code] 自動播種並標記 seeded；否則 no-op（留待之後在有效語言下播種）。
  Future<void> seedDataLanguageIfUnset(String code) async {
    if (state.dataLanguageSeeded) return;
    if (!isSupportedDataLanguage(code)) return;
    state = state.copyWith(dataLanguage: code, dataLanguageSeeded: true);
    await SettingsStorage.save(state);
    Logger('app.settings').info('dataLanguage seeded=$code');
  }
```

> `Logger` 已在 `lib/state/settings.dart` import（既有 `setMaskUidInUi` 已用）；若無則加 `import 'package:logging/logging.dart';`。

(c) 檔尾 provider 區新增：
```dart
/// 當前資料語言代碼（null = 未設定／停用轉換）。
final dataLanguageProvider = Provider<String?>(
  (ref) => ref.watch(settingsProvider.select((s) => s.dataLanguage)),
);
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/state/settings_data_language_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/state/settings.dart test/state/settings_data_language_test.dart
git commit -m "feat(settings): data language setter, seeder and provider"
```

---

### Task 6: `LangCatalog` 模型 + `LangCatalogStorage`

**Files:**
- Create: `lib/services/lang_catalog_storage.dart`（含 `LangCatalog` 模型與 `LangCatalogStorage`）
- Test: `test/services/lang_catalog_storage_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/lang_catalog_storage_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('langcat'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('LangCatalog.fromEntries derives idByName and drops ambiguous names', () {
    final c = LangCatalog.fromEntries('en-us', {
      '1': (name: 'Hu Tao', kind: 2),
      '2': (name: 'Staff', kind: 4),
      '3': (name: 'Staff', kind: 4), // 同名多 id → 剔除
    });
    expect(c.idByName['Hu Tao'], '1');
    expect(c.idByName.containsKey('Staff'), isFalse);
    expect(c.byId['1']!.kind, 2);
  });

  test('save then load round-trips', () async {
    final storage = LangCatalogStorage(tmp);
    final c = LangCatalog.fromEntries('zh-tw', {
      '5125428': (name: '胡桃', kind: 2),
    });
    await storage.save(c, fetchedAt: DateTime.utc(2026, 6, 16));
    final loaded = await storage.load('zh-tw');
    expect(loaded, isNotNull);
    expect(loaded!.byId['5125428']!.name, '胡桃');
    expect(loaded.byId['5125428']!.kind, 2);
    expect(loaded.idByName['胡桃'], '5125428');
  });

  test('load returns null when file missing', () async {
    final storage = LangCatalogStorage(tmp);
    expect(await storage.load('ja-jp'), isNull);
  });

  test('load returns null on corrupt file (logged, not thrown)', () async {
    final dir = Directory('${tmp.path}/sub')..createSync();
    File('${dir.path}/en-us.json').writeAsStringSync('{not json');
    final storage = LangCatalogStorage(dir);
    expect(await storage.load('en-us'), isNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/lang_catalog_storage_test.dart`
Expected: FAIL（檔案不存在）

- [ ] **Step 3: 最小實作**

`lib/services/lang_catalog_storage.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// 單一語言的物品名冊：`id → {name, kind}`（kind = HoYoWiki menu_id，2＝角色、
/// 4＝武器），附 `name → id` 反查表（同名多 id 者剔除以免誤判）。
class LangCatalog {
  /// 建立 [LangCatalog]。
  const LangCatalog({
    required this.lang,
    required this.byId,
    required this.idByName,
  });

  /// 此名冊的語言代碼。
  final String lang;

  /// `hoyowiki_id → {name, kind}`。
  final Map<String, ({String name, int kind})> byId;

  /// `name → id`；由 [byId] 推導，歧義（同名對多 id）者剔除。
  final Map<String, String> idByName;

  /// 由 [byId] 建構並推導 [idByName]（同名多 id 剔除）。
  factory LangCatalog.fromEntries(
    String lang,
    Map<String, ({String name, int kind})> byId,
  ) {
    final nameToIds = <String, Set<String>>{};
    byId.forEach((id, e) => nameToIds.putIfAbsent(e.name, () => {}).add(id));
    final idByName = <String, String>{};
    nameToIds.forEach((name, ids) {
      if (ids.length == 1) idByName[name] = ids.first;
    });
    return LangCatalog(lang: lang, byId: byId, idByName: idByName);
  }
}

/// 負責 `lang_catalog/<lang>.json` 的原子化讀寫。
class LangCatalogStorage {
  /// 建立 [LangCatalogStorage]，需指定資料根目錄 [baseDir]
  /// （通常為 `<hoyowikiCacheDir>/lang_catalog`）。
  LangCatalogStorage(this.baseDir);

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// 資料根目錄。
  final Directory baseDir;

  /// 回傳 [lang] 對應的名冊檔。
  File _file(String lang) => File('${baseDir.path}/$lang.json');

  /// 讀取 [lang] 名冊；不存在或解析失敗回 null（後者 log warning 視為缺檔重抓）。
  Future<LangCatalog?> load(String lang) async {
    final f = _file(lang);
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final items = json['items'] as Map<String, dynamic>;
      final byId = items.map((id, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(id, (name: m['name'] as String, kind: m['kind'] as int));
      });
      return LangCatalog.fromEntries(lang, byId);
    } catch (e, st) {
      _log.warning('lang catalog load failed lang=$lang', e, st);
      return null;
    }
  }

  /// 原子化寫入 [c]；[fetchedAt] 記錄抓取時間。
  Future<void> save(LangCatalog c, {required DateTime fetchedAt}) async {
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    final json = {
      'lang': c.lang,
      'fetched_at': fetchedAt.toUtc().toIso8601String(),
      'items': {
        for (final e in c.byId.entries)
          e.key: {'name': e.value.name, 'kind': e.value.kind},
      },
    };
    final target = _file(c.lang);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(target.path);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/lang_catalog_storage_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/lang_catalog_storage.dart test/services/lang_catalog_storage_test.dart
git commit -m "feat(langconvert): add LangCatalog model and storage"
```

---

### Task 7: `LangCatalogFetcher`（HoYoWiki get_entry_page_list）

**Files:**
- Create: `lib/services/lang_catalog_fetcher.dart`
- Test: `test/services/lang_catalog_fetcher_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/lang_catalog_fetcher_test.dart`（用 `MockClient`）：

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';

void main() {
  String pageBody(List<Map<String, String>> items) => jsonEncode({
    'retcode': 0, 'message': 'OK',
    'data': {'list': items, 'total': items.length},
  });

  test('paginates menu 2 and 4, accumulates id->name with kind', () async {
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      calls.add(body);
      final menu = body['menu_id'];
      final page = body['page_num'];
      // menu 2: 第1頁滿頁(2筆)、第2頁1筆(<pageSize 即停)；menu 4: 1筆。
      if (menu == '2' && page == 1) {
        return http.Response(pageBody([
          {'entry_page_id': '10', 'name': 'A'},
          {'entry_page_id': '11', 'name': 'B'},
        ]), 200);
      }
      if (menu == '2' && page == 2) {
        return http.Response(pageBody([{'entry_page_id': '12', 'name': 'C'}]), 200);
      }
      if (menu == '4') {
        return http.Response(pageBody([{'entry_page_id': '20', 'name': 'Sword'}]), 200);
      }
      return http.Response(pageBody(const []), 200);
    });

    final fetcher = LangCatalogFetcher(pageSize: 2);
    final cat = await fetcher.fetchCatalog(lang: 'en-us', client: client);

    expect(cat.byId['10'], (name: 'A', kind: 2));
    expect(cat.byId['12'], (name: 'C', kind: 2));
    expect(cat.byId['20'], (name: 'Sword', kind: 4));
    expect(cat.byId.length, 4);
    // header 帶 X-Rpc-Language
    // （此處僅驗證有打 menu 2 與 4）
    expect(calls.any((b) => b['menu_id'] == '2'), isTrue);
    expect(calls.any((b) => b['menu_id'] == '4'), isTrue);
  });

  test('throws ApiErrorException on retcode != 0', () async {
    final client = MockClient((req) async => http.Response(
      jsonEncode({'retcode': -1, 'message': 'bad', 'data': null}), 200));
    final fetcher = LangCatalogFetcher();
    expect(
      () => fetcher.fetchCatalog(lang: 'en-us', client: client),
      throwsA(isA<ApiErrorException>()),
    );
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/lang_catalog_fetcher_test.dart`
Expected: FAIL（檔案不存在）

- [ ] **Step 3: 最小實作**

`lib/services/lang_catalog_fetcher.dart`：

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

/// 以 HoYoWiki `get_entry_page_list` 抓取某語言的角色／武器全名冊。
class LangCatalogFetcher {
  /// 建立 [LangCatalogFetcher]，可調整分頁大小與逾時。
  LangCatalogFetcher({
    this.pageSize = 50,
    this.timeout = const Duration(seconds: 10),
  });

  /// 每頁筆數。
  final int pageSize;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// list API base URL（與 search 同 host）。
  static final _listBase = Uri.parse(
    'https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/get_entry_page_list',
  );

  /// 要抓的 menu_id：2＝角色、4＝武器。
  static const _menuIds = [2, 4];

  /// 單一 menu 分頁上限（安全閥，避免 API 異常時無限迴圈）。
  static const _maxPages = 50;

  /// 抓 [lang] 的角色＋武器名冊；retcode != 0 throw [ApiErrorException]。
  Future<LangCatalog> fetchCatalog({
    required String lang,
    required http.Client client,
  }) async {
    final byId = <String, ({String name, int kind})>{};
    for (final menuId in _menuIds) {
      var page = 1;
      while (page <= _maxPages) {
        final res = await client
            .post(
              _listBase,
              headers: {
                'Referer': 'https://wiki.hoyolab.com/',
                'X-Rpc-Language': lang,
                'X-Rpc-Wiki_app': 'genshin',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'filters': const [],
                'menu_id': '$menuId',
                'page_num': page,
                'page_size': pageSize,
                'use_es': true,
              }),
            )
            .timeout(timeout);
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final retcode = body['retcode'] as int;
        if (retcode != 0) {
          _log.warning('list retcode=$retcode lang=$lang menu=$menuId');
          throw ApiErrorException(retcode, body['message'] as String? ?? '');
        }
        final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
        for (final raw in list) {
          final m = raw as Map<String, dynamic>;
          final id = m['entry_page_id']?.toString();
          final name = m['name'] as String?;
          if (id == null || id.isEmpty || name == null || name.isEmpty) {
            continue;
          }
          byId[id] = (name: name, kind: menuId);
        }
        if (list.length < pageSize) break; // 末頁（含空頁）
        page++;
      }
    }
    _log.info('lang catalog fetched lang=$lang items=${byId.length}');
    return LangCatalog.fromEntries(lang, byId);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/lang_catalog_fetcher_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/lang_catalog_fetcher.dart test/services/lang_catalog_fetcher_test.dart
git commit -m "feat(langconvert): add LangCatalogFetcher via get_entry_page_list"
```

---

### Task 8: `LangCatalogService`（memo → disk → remote ＋ forceRefresh）

**Files:**
- Create: `lib/services/lang_catalog_service.dart`
- Test: `test/services/lang_catalog_service_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/lang_catalog_service_test.dart`（注入 fake fetcher／storage 的最小替身）：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

/// 計次用的可控 fetcher。
class _CountingFetcher extends LangCatalogFetcher {
  int calls = 0;
  @override
  Future<LangCatalog> fetchCatalog({required String lang, required http.Client client}) async {
    calls++;
    return LangCatalog.fromEntries(lang, {'1': (name: 'N$calls', kind: 2)});
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('langsvc'));
  tearDown(() => tmp.deleteSync(recursive: true));

  LangCatalogService make(_CountingFetcher f) => LangCatalogService(
    storage: LangCatalogStorage(tmp),
    fetcher: f,
    clientFactory: () => MockClient((_) async => http.Response('', 200)),
  );

  test('fetches once, then reuses memo and disk', () async {
    final f = _CountingFetcher();
    final svc = make(f);
    await svc.ensure('en-us');
    await svc.ensure('en-us'); // memo
    expect(f.calls, 1);

    // 新 service 實例 → memo 空，但 disk 已有 → 仍不重抓
    final svc2 = make(f);
    await svc2.ensure('en-us');
    expect(f.calls, 1);
  });

  test('forceRefresh bypasses memo and disk', () async {
    final f = _CountingFetcher();
    final svc = make(f);
    await svc.ensure('en-us');
    final refreshed = await svc.ensure('en-us', forceRefresh: true);
    expect(f.calls, 2);
    expect(refreshed.byId['1']!.name, 'N2'); // 取到新抓的
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/lang_catalog_service_test.dart`
Expected: FAIL（檔案不存在）

- [ ] **Step 3: 最小實作**

`lib/services/lang_catalog_service.dart`：

```dart
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

/// 解析某語言名冊：memo → 本地快取 → 抓取落地。同實例以 memo 避免單次轉換內
/// 重複讀檔／抓取。`forceRefresh` 供「未命中刷新」略過快取強制重抓。
class LangCatalogService {
  /// 建立 [LangCatalogService]。
  LangCatalogService({
    required this.storage,
    required this.fetcher,
    required this.clientFactory,
  });

  /// 名冊持久化。
  final LangCatalogStorage storage;

  /// 名冊抓取器。
  final LangCatalogFetcher fetcher;

  /// 建立 http client 的工廠（每次抓取用後即關）。
  final http.Client Function() clientFactory;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// 單次執行的記憶體快取；無時間過期（disk 為真相）。
  final Map<String, LangCatalog> _memo = {};

  /// 取得 [lang] 名冊：memo → 本地 → 抓取落地。網路失敗時拋出（呼叫端決定處理）。
  ///
  /// [forceRefresh] 為 true 時略過 memo／本地快取，強制重抓並覆寫（供未命中刷新）。
  Future<LangCatalog> ensure(String lang, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final memo = _memo[lang];
      if (memo != null) return memo;
      final cached = await storage.load(lang);
      if (cached != null) {
        _memo[lang] = cached;
        _log.fine('lang catalog from disk lang=$lang');
        return cached;
      }
    }
    final client = clientFactory();
    try {
      final c = await fetcher.fetchCatalog(lang: lang, client: client);
      await storage.save(c, fetchedAt: DateTime.now().toUtc());
      _memo[lang] = c;
      return c;
    } finally {
      client.close();
    }
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/lang_catalog_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/lang_catalog_service.dart test/services/lang_catalog_service_test.dart
git commit -m "feat(langconvert): add LangCatalogService with memo/disk/remote and forceRefresh"
```

---

### Task 9: catalog Riverpod providers

**Files:**
- Create: `lib/state/lang_catalog.dart`
- Test: 無獨立測試（純 wiring；由 Task 11 整合測試覆蓋）。本 Task 只需 analyze 通過。

- [ ] **Step 1: 實作 providers**

`lib/state/lang_catalog.dart`：

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// 名冊儲存層：放在 HoYoWiki 快取目錄下的 `lang_catalog/`。
final langCatalogStorageProvider = Provider<LangCatalogStorage>((ref) {
  final dir = ref.read(hoyowikiCacheDirProvider);
  return LangCatalogStorage(Directory('${dir.path}/lang_catalog'));
});

/// 名冊抓取器。
final langCatalogFetcherProvider = Provider<LangCatalogFetcher>(
  (ref) => LangCatalogFetcher(),
);

/// 名冊解析器（單例，memo 跨更新／轉換沿用）。
final langCatalogServiceProvider = Provider<LangCatalogService>((ref) {
  return LangCatalogService(
    storage: ref.read(langCatalogStorageProvider),
    fetcher: ref.read(langCatalogFetcherProvider),
    clientFactory: () => http.Client(),
  );
});
```

- [ ] **Step 2: analyze 確認通過**

Run: `fvm flutter analyze lib/state/lang_catalog.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/state/lang_catalog.dart
git commit -m "feat(langconvert): wire lang catalog providers"
```

---

### Task 10: 轉換引擎 `GachaLanguageConverter`

**Files:**
- Create: `lib/services/gacha_language_converter.dart`
- Test: `test/services/gacha_language_converter_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/services/gacha_language_converter_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

GachaRecord rec(String id, String type, String name, String lang) => GachaRecord(
  id: id, uid: '1', gachaType: type, name: name,
  itemType: '角色', rankType: 5, time: DateTime(2024), lang: lang,
);

BannerStorage storage(Map<String, List<GachaRecord>> banners) =>
    BannerStorage(uid: '1', lastUpdated: DateTime.utc(2024), banners: banners);

void main() {
  // 假名冊：zh-tw 與 en-us 都有 id=5125428（胡桃／Hu Tao）。
  final cats = <String, LangCatalog>{
    'zh-tw': LangCatalog.fromEntries('zh-tw', {'5125428': (name: '胡桃', kind: 2)}),
    'en-us': LangCatalog.fromEntries('en-us', {'5125428': (name: 'Hu Tao', kind: 2)}),
  };
  Future<LangCatalog> ensure(String lang, {bool forceRefresh = false}) async {
    final c = cats[lang];
    if (c == null) throw StateError('no catalog for $lang');
    return c;
  }

  test('converts name+lang via id round-trip and emits hint', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({'301': [rec('1', '301', '胡桃', 'zh-tw')]}),
      'en-us',
    );
    final r = out.data.banners['301']!.single;
    expect(r.name, 'Hu Tao');
    expect(r.lang, 'en-us');
    expect(out.result.converted, 1);
    expect(out.result.unresolved, 0);
    expect(out.hints.single.id, '5125428');
    expect(out.hints.single.menuId, 2);
    expect(out.hints.single.name, 'Hu Tao');
  });

  test('same-lang records are skipped and uncounted', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({'301': [rec('1', '301', 'Hu Tao', 'en-us')]}),
      'en-us',
    );
    expect(out.result.total, 0);
    expect(out.result.converted, 0);
    expect(out.data.banners['301']!.single.name, 'Hu Tao');
  });

  test('odes records are never touched', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({'2000': [rec('1', '2000', '某裝扮', 'zh-tw')]}),
      'en-us',
    );
    expect(out.result.total, 0);
    expect(out.data.banners['2000']!.single.name, '某裝扮');
    expect(out.data.banners['2000']!.single.lang, 'zh-tw');
  });

  test('unresolved name is kept as-is and counted', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({'301': [rec('1', '301', '不存在的物品', 'zh-tw')]}),
      'en-us',
    );
    expect(out.result.total, 1);
    expect(out.result.converted, 0);
    expect(out.result.unresolved, 1);
    expect(out.data.banners['301']!.single.name, '不存在的物品');
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/gacha_language_converter_test.dart`
Expected: FAIL（檔案不存在）

- [ ] **Step 3: 最小實作**

`lib/services/gacha_language_converter.dart`：

```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 轉換結果計數（genshin 無 resourceId，故無 backfilledId）。可相加聚合多帳號。
class LangConvertResult {
  /// 建立 [LangConvertResult]。
  const LangConvertResult({this.total = 0, this.converted = 0, this.unresolved = 0});

  /// 在範圍內且 lang != target 的候選筆數。
  final int total;

  /// 成功轉換筆數。
  final int converted;

  /// 無法轉換、保持原狀的筆數。
  final int unresolved;

  /// 逐項相加。
  LangConvertResult operator +(LangConvertResult o) => LangConvertResult(
    total: total + o.total,
    converted: converted + o.converted,
    unresolved: unresolved + o.unresolved,
  );
}

/// 轉換後要寫回 [HoYoWikiIndex] 的提示，維持類型判定與詳情／icon lookup。
class IndexHint {
  /// 建立 [IndexHint]。
  const IndexHint({
    required this.lang,
    required this.name,
    required this.id,
    required this.menuId,
  });

  /// 目標語言。
  final String lang;

  /// 目標語言的物品名。
  final String name;

  /// hoyowiki_id。
  final String id;

  /// menu_id（2／4）。
  final int menuId;
}

/// 把一份 [BannerStorage] 的非頌願紀錄名稱統一成目標語言。
///
/// 只改 `name`／`lang`，不動 `itemType`（類型顯示走 menu_id，見 spec D8）。
/// 轉不了的紀錄完全保持原狀。
class GachaLanguageConverter {
  /// 建立 [GachaLanguageConverter]；[ensureCatalog] 取得某語言名冊
  /// （生產接 `LangCatalogService.ensure`，測試注入 fake）。
  GachaLanguageConverter({required this.ensureCatalog});

  /// 取得某語言名冊；[forceRefresh] 為 true 時略過快取重抓。
  final Future<LangCatalog> Function(String lang, {bool forceRefresh}) ensureCatalog;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert');

  /// 轉換 [data] 為 [targetLang]，回傳新存檔、計數與 index 提示。
  Future<({BannerStorage data, LangConvertResult result, List<IndexHint> hints})>
  convert(BannerStorage data, String targetLang) async {
    var targetCat = await ensureCatalog(targetLang);

    // 蒐集需要的原語言名冊。
    final srcLangs = <String>{};
    for (final entry in data.banners.entries) {
      if (!convertibleGachaTypes.contains(entry.key)) continue;
      for (final r in entry.value) {
        if (r.lang == targetLang || r.lang.isEmpty) continue;
        srcLangs.add(r.lang);
      }
    }
    final srcCats = <String, LangCatalog>{};
    for (final lang in srcLangs) {
      srcCats[lang] = await ensureCatalog(lang);
    }

    // 未命中自動刷新（有界）：原/目標都是選項之一、卻在快取名冊解析不出 → 視為
    // 目錄過期（遊戲新版新增物品）→ 強制重抓目標＋來源各一次。
    bool resolvable(GachaRecord r) {
      final id = srcCats[r.lang]?.idByName[r.name];
      return id != null && targetCat.byId.containsKey(id);
    }
    final staleDetected = isSupportedDataLanguage(targetLang) &&
        data.banners.entries.any((e) =>
            convertibleGachaTypes.contains(e.key) &&
            e.value.any((r) =>
                r.lang != targetLang &&
                r.lang.isNotEmpty &&
                isSupportedDataLanguage(r.lang) &&
                !resolvable(r)));
    if (staleDetected) {
      _log.info('stale catalog detected, refreshing target=$targetLang');
      targetCat = await ensureCatalog(targetLang, forceRefresh: true);
      for (final lang in srcLangs) {
        if (isSupportedDataLanguage(lang)) {
          srcCats[lang] = await ensureCatalog(lang, forceRefresh: true);
        }
      }
    }

    var result = const LangConvertResult();
    final hints = <IndexHint>[];
    final newBanners = <String, List<GachaRecord>>{};
    data.banners.forEach((key, list) {
      if (!convertibleGachaTypes.contains(key)) {
        newBanners[key] = list;
        return;
      }
      final out = <GachaRecord>[];
      for (final r in list) {
        if (r.lang == targetLang) {
          out.add(r);
          continue;
        }
        result = result + const LangConvertResult(total: 1);
        final id = r.lang.isEmpty ? null : srcCats[r.lang]?.idByName[r.name];
        final target = id == null ? null : targetCat.byId[id];
        if (id != null && target != null) {
          out.add(r.copyWith(name: target.name, lang: targetLang));
          hints.add(IndexHint(
            lang: targetLang,
            name: target.name,
            id: id,
            menuId: target.kind,
          ));
          result = result + const LangConvertResult(converted: 1);
        } else {
          out.add(r);
          result = result + const LangConvertResult(unresolved: 1);
        }
      }
      newBanners[key] = out;
    });

    _log.info(
      'converted uid=${sanitizeUid(data.uid)} target=$targetLang '
      'total=${result.total} converted=${result.converted} '
      'unresolved=${result.unresolved}',
    );
    return (data: data.copyWith(banners: newBanners), result: result, hints: hints);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/gacha_language_converter_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/gacha_language_converter.dart test/services/gacha_language_converter_test.dart
git commit -m "feat(langconvert): add conversion engine (name backfill, hints)"
```

---

### Task 11: 轉換引擎「未命中自動刷新」回歸測試

**Files:**
- Modify: `test/services/gacha_language_converter_test.dart`（補一個 stale 測試，驗證 Task 10 已實作的刷新行為）

- [ ] **Step 1: 寫測試（針對既有實作的回歸鎖定）**

在 `test/services/gacha_language_converter_test.dart` 內新增：

```dart
test('stale cached catalog triggers one forced refresh then converts', () async {
  // 初始名冊：目標 en-us 沒有 id=999；刷新後才有 → 模擬遊戲新版新增物品。
  var refreshed = false;
  final staleEn = LangCatalog.fromEntries('en-us', {'5125428': (name: 'Hu Tao', kind: 2)});
  final freshEn = LangCatalog.fromEntries('en-us', {
    '5125428': (name: 'Hu Tao', kind: 2),
    '999': (name: 'NewChar', kind: 2),
  });
  final zh = LangCatalog.fromEntries('zh-tw', {
    '5125428': (name: '胡桃', kind: 2),
    '999': (name: '新角色', kind: 2),
  });
  Future<LangCatalog> ensureStale(String lang, {bool forceRefresh = false}) async {
    if (lang == 'zh-tw') return zh;
    if (lang == 'en-us') {
      if (forceRefresh) { refreshed = true; return freshEn; }
      return refreshed ? freshEn : staleEn;
    }
    throw StateError('no catalog $lang');
  }

  final conv = GachaLanguageConverter(ensureCatalog: ensureStale);
  final out = await conv.convert(
    storage({'301': [rec('1', '301', '新角色', 'zh-tw')]}),
    'en-us',
  );
  expect(refreshed, isTrue);
  expect(out.data.banners['301']!.single.name, 'NewChar');
  expect(out.result.converted, 1);
});
```

- [ ] **Step 2: 跑測試確認通過**

Run: `fvm flutter test test/services/gacha_language_converter_test.dart`
Expected: PASS（Task 10 的 stale 邏輯已實作）

> 若失敗，回 Task 10 檢查 `staleDetected` 與刷新分支。

- [ ] **Step 3: Commit**

```bash
git add test/services/gacha_language_converter_test.dart
git commit -m "test(langconvert): regression for stale-catalog auto-refresh"
```

---

### Task 12: 轉換引擎 provider

**Files:**
- Create: `lib/state/gacha_language_converter.dart`
- Test: 無獨立測試（wiring；Task 13 整合測試覆蓋）。analyze 通過即可。

- [ ] **Step 1: 實作**

`lib/state/gacha_language_converter.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/lang_catalog.dart';

/// 轉換引擎 provider；接 [LangCatalogService.ensure] 作為名冊解析器。
final gachaLanguageConverterProvider = Provider<GachaLanguageConverter>((ref) {
  final service = ref.read(langCatalogServiceProvider);
  return GachaLanguageConverter(ensureCatalog: service.ensure);
});
```

- [ ] **Step 2: analyze 確認通過**

Run: `fvm flutter analyze lib/state/gacha_language_converter.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/state/gacha_language_converter.dart
git commit -m "feat(langconvert): wire conversion engine provider"
```

---

### Task 13: Repository 串接（轉換、seeding、unify）

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Test: `test/state/gacha_repository_data_language_test.dart`

本 Task 較大，拆成多個 step。先讀懂既有 `_fetchAllBanners`（L334-444）、`_runImport`（L665-764）、`_bootstrapLoad`（L131-179）位置。

- [ ] **Step 1: 寫失敗測試（unify 聚合與失敗吞例外）**

`test/state/gacha_repository_data_language_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
// 下列 provider 依專案實際命名 import：gachaStorageProvider、hoyowikiCacheDirProvider 等。

void main() {
  // 說明：此測試需要既有測試 harness 注入 gachaStorageProvider（指向 tempDir）、
  // hoyowikiCacheDirProvider（tempDir）等。請參考既有
  // test/state/gacha_repository_*_test.dart 的 ProviderContainer override 寫法，
  // 並額外 override gachaLanguageConverterProvider 為下列 fake，繞過網路。

  // fake 名冊：兩語言皆有 id=1（胡桃／Hu Tao）。
  final cats = <String, LangCatalog>{
    'zh-tw': LangCatalog.fromEntries('zh-tw', {'1': (name: '胡桃', kind: 2)}),
    'en-us': LangCatalog.fromEntries('en-us', {'1': (name: 'Hu Tao', kind: 2)}),
  };
  Future<LangCatalog> ensure(String lang, {bool forceRefresh = false}) async => cats[lang]!;
  final fakeConverter = GachaLanguageConverter(ensureCatalog: ensure);

  // 實際 container 組裝請沿用既有 repo 測試樣板；以下為斷言重點示意：
  // 1) 設 dataLanguage=en-us，state 內有 zh-tw 的「胡桃」record。
  // 2) await notifier.unifyDataLanguage() → result.converted == 1。
  // 3) state.byUid 內該 record.name == 'Hu Tao'、lang == 'en-us'。
  // 4) 進度：呼叫後 state.progress 應為 null（結尾 clearProgress）。
  test('unifyDataLanguage converts and clears progress', () async {
    // 依專案 harness 實作；斷言如上。
  }, skip: 'fill in with project repo test harness');
}
```

> 註：repository 整合測試需沿用既有 `test/state/gacha_repository_*_test.dart` 的 container／override 樣板（注入 `gachaStorageProvider` 指向 tempDir、override `gachaLanguageConverterProvider` 為 `fakeConverter`、override `hoyowikiCacheDirProvider`）。實作者請開啟一個既有 repo 測試檔複製其 `setUp`／harness，移除 `skip` 並填入斷言。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/state/gacha_repository_data_language_test.dart`
Expected: FAIL（`unifyDataLanguage` 未定義）

- [ ] **Step 3: 新增 `_convertAccountToDataLanguage` 與 seeding helper**

在 `lib/state/gacha_repository.dart` 的 `GachaRepository` class 內新增（建議放 `_fetchHoYoWiki` 附近）：

```dart
  /// 若已設定資料語言則轉換 [data] 並把 hints 寫回 HoYoWikiIndex；
  /// 任何例外吞掉、回原 [data]（絕不中斷更新／匯入、絕不毀資料）。
  Future<BannerStorage> _convertAccountToDataLanguage(BannerStorage data) async {
    final targetLang = ref.read(dataLanguageProvider);
    if (targetLang == null) return data;
    try {
      final converter = ref.read(gachaLanguageConverterProvider);
      final outcome = await converter.convert(data, targetLang);
      if (outcome.hints.isNotEmpty) {
        final indexNotifier = ref.read(hoyowikiIndexProvider.notifier);
        for (final h in outcome.hints) {
          await indexNotifier.setSearch(
            name: h.name, lang: h.lang, id: h.id, menuId: h.menuId,
          );
        }
      }
      return outcome.data;
    } catch (e, st) {
      Logger('wish.langconvert')
          .warning('convert account failed uid=${sanitizeUid(data.uid)} (kept original)', e, st);
      return data;
    }
  }

  /// 取 [data] 中非頌願、有語言的「最新」一筆 record 的 lang（供 seeding）；無則 null。
  String? _seedLangFromData(BannerStorage data) {
    GachaRecord? latest;
    for (final e in data.banners.entries) {
      if (!convertibleGachaTypes.contains(e.key)) continue;
      for (final r in e.value) {
        if (r.lang.isEmpty) continue;
        if (latest == null || r.id.compareTo(latest.id) > 0) latest = r;
      }
    }
    return latest?.lang;
  }
```

> 檔頭補 import：`data_language.dart`（若未透過 settings.dart 傳遞，直接 import）、`gacha_language_converter.dart`（service，取 `IndexHint`）、`state/gacha_language_converter.dart`（provider）、`data/gacha_types.dart`（`convertibleGachaTypes`）。`dataLanguageProvider` 來自 `state/settings.dart`。確認 `Logger`/`sanitizeUid` 已 import（既有檔已用）。

- [ ] **Step 4: 在 `_fetchAllBanners` 串接轉換＋更新後播種**

在 `_fetchAllBanners`（L334-444）把「`final newData = BannerStorage(...)` → `await storage.save(newData)` → `state = state.copyWith(byUid: newByUid, activeUid: uid)`」這段改為先轉換再存：

```dart
    final updatedAt = DateTime.now().toUtc();
    final builtData = BannerStorage(
      uid: uid,
      lastUpdated: updatedAt,
      banners: mergedBanners,
    );
    final newData = await _convertAccountToDataLanguage(builtData); // 轉換（未設定則原樣）
    await storage.save(newData);
    if (!ref.mounted) return;
    await storage.saveCapturedUrl(uid, url);
    if (!ref.mounted) return;

    final newByUid = Map<String, BannerStorage>.from(state.byUid)..[uid] = newData;
    state = state.copyWith(byUid: newByUid, activeUid: uid);
    if (!ref.mounted) return;
    await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
    if (!ref.mounted) return;
    // 首次更新播種（取本次資料語言；已設定則 no-op）。
    final seedLang = _seedLangFromData(newData);
    if (seedLang != null) {
      await ref.read(settingsProvider.notifier).seedDataLanguageIfUnset(seedLang);
      if (!ref.mounted) return;
    }
```

> 其餘（`_fetchHoYoWiki` 補圖、`UpdateCompleted` emit）不變。注意 `totalNew` 的計算改用 `builtData`/`mergedBanners` 對既有的差（轉換不改變筆數，`totalNew` 邏輯維持原樣，只是 record 名稱被改寫）。

- [ ] **Step 5: 在 `_runImport` 串接轉換**

在 `_runImport`（L665-764）的逐帳號迴圈，把 `final toSave = localBefore == null ? incoming : localBefore.mergeWith(incoming);` 之後、`await storage.save(toSave);` 之前插入轉換：

```dart
        final merged = localBefore == null ? incoming : localBefore.mergeWith(incoming);
        final toSave = await _convertAccountToDataLanguage(merged);
        await storage.save(toSave);
```

並在方法尾端（套用偏好後、回傳前）以最新帳號語言播種。在 `state = state.copyWith(byUid: newByUid, ...)` 之後加：

```dart
    // 首次匯入播種：取所有匯入帳號中最新 lastUpdated 者的資料語言。
    BannerStorage? newest;
    for (final account in bundle.accounts) {
      final d = newByUid[account.data.uid];
      if (d == null) continue;
      if (newest == null || d.lastUpdated.isAfter(newest.lastUpdated)) newest = d;
    }
    if (newest != null) {
      final seedLang = _seedLangFromData(newest);
      if (seedLang != null) {
        await settingsNotifier.seedDataLanguageIfUnset(seedLang);
        if (!ref.mounted) {
          return ImportResult(
            successAccounts: successCount,
            addedRecords: addedRecords,
            duplicateRecords: duplicateRecords,
            failedUids: failed,
          );
        }
      }
    }
```

> `toSave` 已是轉換後資料，`addedRecords`/`duplicateRecords` 以 `toSave.allRecords.length` 計算（轉換不改筆數，計數正確）。

- [ ] **Step 6: 在 `_bootstrapLoad` 串接播種**

在 `_bootstrapLoad`（L131-179）設定 `activeUid` 之後（`if (saved != activeUid) {...}` 區塊附近、`finally` 之前）加：

```dart
      // bootstrap 播種：取最新 lastUpdated 帳號的資料語言（已 seeded 則 no-op）。
      BannerStorage? newest;
      for (final d in byUid.values) {
        if (newest == null || d.lastUpdated.isAfter(newest.lastUpdated)) newest = d;
      }
      if (newest != null) {
        final seedLang = _seedLangFromData(newest);
        if (seedLang != null) {
          await settingsNotifier.seedDataLanguageIfUnset(seedLang);
          if (!ref.mounted) return;
        }
      }
```

- [ ] **Step 7: 新增 `unifyDataLanguage`**

在 `GachaRepository` 內新增公開方法（建議放 `_runImport` 之後）：

```dart
  /// 把所有帳號的卡池資料統一成目前設定的資料語言；回傳聚合計數。
  /// 立即彈出進度（Preparing），結尾主動清進度。未設定資料語言時回零結果。
  Future<LangConvertResult> unifyDataLanguage() async {
    final targetLang = ref.read(dataLanguageProvider);
    if (targetLang == null) return const LangConvertResult();
    if (_isUpdating) return const LangConvertResult();
    _isUpdating = true;
    state = state.copyWith(progress: const Preparing());
    try {
      final storage = ref.read(gachaStorageProvider);
      final converter = ref.read(gachaLanguageConverterProvider);
      final indexNotifier = ref.read(hoyowikiIndexProvider.notifier);
      var agg = const LangConvertResult();
      final newByUid = Map<String, BannerStorage>.from(state.byUid);
      for (final uid in state.byUid.keys.toList()) {
        final data = state.byUid[uid]!;
        try {
          final outcome = await converter.convert(data, targetLang);
          await storage.save(outcome.data);
          for (final h in outcome.hints) {
            await indexNotifier.setSearch(
              name: h.name, lang: h.lang, id: h.id, menuId: h.menuId,
            );
          }
          newByUid[uid] = outcome.data;
          agg = agg + outcome.result;
        } catch (e, st) {
          Logger('wish.langconvert').warning('unify skip uid=${sanitizeUid(uid)}', e, st);
        }
      }
      if (ref.mounted) state = state.copyWith(byUid: newByUid);
      return agg;
    } finally {
      _isUpdating = false;
      if (ref.mounted) state = state.copyWith(clearProgress: true);
    }
  }
```

> `LangConvertResult` 來自 `services/gacha_language_converter.dart`，檔頭補 import。`Preparing`／`clearProgress` 為既有進度型別。`_isUpdating` 為既有欄位。

- [ ] **Step 8: 填好整合測試並跑通**

依既有 `test/state/gacha_repository_*_test.dart` 樣板補齊 Step 1 測試（移除 `skip`），涵蓋：
- update 後置轉換（dataLanguage=en-us 時，抓到的 zh-tw record 存檔後變 en-us）；
- update 首次播種（dataLanguage 未設定時，更新後 settings.dataLanguage 被播種為該次語言）；
- import 後置轉換與播種；
- bootstrap 播種（tempDir 預置一份 zh-tw 存檔，build 後 settings 被播種 zh-tw）；
- `unifyDataLanguage` 聚合 converted、結尾 `state.progress == null`；
- 轉換例外被吞（override converter 為會丟例外的 fake，驗證 `update()` 仍成功、資料保留原狀）。

Run: `fvm flutter test test/state/gacha_repository_data_language_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/state/gacha_repository.dart test/state/gacha_repository_data_language_test.dart
git commit -m "feat(langconvert): wire conversion, seeding and unify into repository"
```

---

### Task 14: i18n ARB 字串

**Files:**
- Modify: `lib/l10n/app_zh.arb`（模板，繁中先行）
- 之後翻譯到既有實體翻譯 ARB（`app_en`/`app_zh_Hans`/`app_ja`/`app_ko`/`app_de`/`app_fr`/`app_es`/`app_pt_BR` 等）—— 由 i18n 流程處理，本 Task 至少完成 zh 模板以利編譯。

- [ ] **Step 1: 加入 ARB key（含 placeholders metadata）**

在 `lib/l10n/app_zh.arb` 適當位置（settings 相關 key 附近）加入：

```json
  "settingsDataLanguage": "資料語言",
  "settingsDataLanguageDesc": "統一卡池歷史資料的物品名稱語言，獨立於應用程式介面語言。設定後更新或匯入資料會自動轉換成此語言。",
  "settingsDataLanguageUnset": "未設定（不轉換）",
  "settingsDataLanguageUnify": "立即轉換資料語言",
  "settingsDataLanguageUnifying": "轉換中...",
  "settingsDataLanguageUnifyDone": "已轉換 {converted} 筆，{unresolved} 筆無法轉換。",
  "@settingsDataLanguageUnifyDone": {
    "placeholders": {
      "converted": { "type": "int" },
      "unresolved": { "type": "int" }
    }
  },
  "settingsDataLanguageUnifyFailed": "轉換失敗，資料未變更。請檢查網路後重試。",
```

> 注意：`轉換中...` 結尾用半形 `...`（覆蓋 CJK 全形通則的既定例外）。

- [ ] **Step 2: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 成功，無錯誤；`lib/l10n/generated/app_localizations.dart` 出現對應 getter。

- [ ] **Step 3: analyze 確認通過**

Run: `fvm flutter analyze`
Expected: `No issues found!`（此時 settings 頁尚未用到這些 key，但生成檔已含；若 analyze 報未使用屬正常，待 Task 15 接上）

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/generated/
git commit -m "feat(l10n): add data language settings strings (zh template)"
```

---

### Task 15: 設定頁「資料語言」區塊 UI

**Files:**
- Modify: `lib/pages/settings_page.dart`（新增 `_DataLanguageSection` 並掛進 build）
- Test: `test/pages/settings_data_language_section_test.dart`

- [ ] **Step 1: 寫失敗測試**

`test/pages/settings_data_language_section_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_language.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dropdown lists unset + 15 options and selection persists', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: SettingsPage())),
      ),
    ));
    await tester.pumpAndSettle();

    // 開啟資料語言下拉
    final dropdown = find.byType(DropdownButtonFormField<String?>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    // 選單應有「未設定」+ 15 語言（母語名）
    expect(find.text(kDataLanguageOptions.first.label).hitTestable(), findsWidgets);

    // 選日本語
    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    expect(container.read(settingsProvider).dataLanguage, 'ja-jp');
  });
}
```

> 若 `SettingsPage` 需要額外 provider override 才能 pump（例如 `gachaRepositoryProvider` 觸發 bootstrap I/O），請沿用既有 `test/pages/settings_page_*_test.dart` 的 override 樣板。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/pages/settings_data_language_section_test.dart`
Expected: FAIL（找不到下拉 / `_DataLanguageSection` 未掛上）

- [ ] **Step 3: 實作 `_DataLanguageSection`**

在 `lib/pages/settings_page.dart` 檔尾新增（沿用既有 import；補 `data_language.dart`、`AppDialog`/`AppDialogSize` 來自 `widgets/dialogs/app_dialog.dart`、`gachaRepositoryProvider`）：

```dart
/// 設定頁「資料語言」區塊：下拉切換目標語言＋「立即轉換」按鈕。
class _DataLanguageSection extends ConsumerStatefulWidget {
  const _DataLanguageSection();

  @override
  ConsumerState<_DataLanguageSection> createState() =>
      _DataLanguageSectionState();
}

class _DataLanguageSectionState extends ConsumerState<_DataLanguageSection> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = ref.watch(settingsProvider.select((s) => s.dataLanguage));
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.settingsDataLanguageDesc,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.gacha.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        DropdownButtonFormField<String?>(
          initialValue: current,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(l.settingsDataLanguageUnset),
            ),
            for (final o in kDataLanguageOptions)
              DropdownMenuItem(value: o.code, child: Text(o.label)),
          ],
          onChanged: _busy ? null : (v) => notifier.setDataLanguage(v),
        ),
        const SizedBox(height: AppSpacing.m),
        OutlinedButton.icon(
          onPressed: (current == null || _busy) ? null : () => _unify(context),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(
            _busy ? l.settingsDataLanguageUnifying : l.settingsDataLanguageUnify,
          ),
        ),
      ],
    );
  }

  /// 執行統一轉換，期間 busy、結尾彈結果 [AppDialog]。
  Future<void> _unify(BuildContext ctx) async {
    final l = AppLocalizations.of(ctx)!;
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(gachaRepositoryProvider.notifier).unifyDataLanguage();
      if (!ctx.mounted) return;
      await showDialog<void>(
        context: ctx,
        builder: (dctx) => AppDialog(
          title: Text(l.settingsDataLanguage),
          content: Text(l.settingsDataLanguageUnifyDone(
            result.converted,
            result.unresolved,
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text(MaterialLocalizations.of(dctx).okButtonLabel),
            ),
          ],
        ),
      );
    } catch (e, st) {
      Logger('wish.langconvert').warning('unify ui failed', e, st);
      if (!ctx.mounted) return;
      await showDialog<void>(
        context: ctx,
        builder: (dctx) => AppDialog(
          title: Text(l.settingsDataLanguage),
          content: Text(l.settingsDataLanguageUnifyFailed),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text(MaterialLocalizations.of(dctx).okButtonLabel),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
```

> 檔頭若無 `Logger` import 請補 `import 'package:logging/logging.dart';`。

- [ ] **Step 4: 把區塊掛進 SettingsPage.build**

在 `SettingsPage.build`（L49-124）的 `Column` children 中、語言 `SectionCard` 之後插入：

```dart
            const SizedBox(height: AppSpacing.xl),
            SectionCard(
              title: l.settingsDataLanguage,
              icon: Icons.translate,
              child: const _DataLanguageSection(),
            ),
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/pages/settings_data_language_section_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/pages/settings_page.dart test/pages/settings_data_language_section_test.dart
git commit -m "feat(settings): add data language section UI"
```

---

### Task 16: 全量驗收

**Files:** 無（驗收）

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 僅本功能新增/修改檔被格式化。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全量測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 實機冒煙（建議）**

`fvm flutter run -d windows`，於設定頁：設資料語言 → 按「立即轉換資料語言」→ 進度框即時彈出並正常關閉 → 結果框顯示轉換筆數 → 列表物品名統一 → 切其他語言再切回不重抓（觀察無新網路請求 / log 顯示 from disk）。

- [ ] **Step 5: Commit（若 format 有變更）**

```bash
git add -A
git commit -m "style(langconvert): apply dart format"
```

---

## 自我檢查（spec 覆蓋）

- D1 突變存檔 → Task 1（copyWith name）＋ Task 10（convert 改 name/lang）＋ Task 13（save）。
- D2 三態 → Task 4。
- D3 播種 → Task 5（seeder）＋ Task 13 Step 4/5/6（三觸發點）。
- D4 改設定不動既有 → Task 5（setDataLanguage 不轉換）＋ Task 15（下拉只呼叫 setter）。
- D5/D6/G catalog → Task 6/7/8/9。
- D7 名稱回查 → Task 10（idByName → byId）。
- D8 類型不動 → Task 10（只改 name/lang）＋ Task 13（index 橋接 setSearch 維持判定）。
- D9 詳情跟隨 → 既有 `pageByLang` lazy；Task 13 setSearch 提供 lookupId。
- D10 update/import 後置轉換 → Task 13 Step 4/5。
- D11 失敗吞例外 → Task 13 Step 3（_convertAccountToDataLanguage try/catch）＋ Task 13 Step 7（unify per-account try/catch）。
- 未命中刷新（PR #33）→ Task 10（staleDetected + forceRefresh）＋ Task 11（回歸測試）。
- 三態 UI 含「未設定」＋進度生命週期 → Task 15。
- i18n → Task 14。
- 範圍（convertibleGachaTypes）→ Task 3。
