# i18n: 沿用 master 多國語言翻譯 — Design

| 欄位 | 內容 |
|---|---|
| 日期 | 2026-05-11 |
| 分支 | flutter-rewrite |
| 狀態 | Draft（待 user review） |
| Approach | C — 業界標準 i18n 擴充 + 翻譯者署名 |

---

## 1. 目標與範圍

把舊版（master 分支，Vue/Electron）31 種語言的翻譯內容透過離線一次性腳本，產出 Flutter ARB 對應檔案；同時把 Settings 語言選單從寫死 4 項擴成 30 + 1（system）共 31 項，新加「Translator」署名顯示。

**範圍內**：
- 重構 `AppLocale` 為可承載任意 BCP-47 code 的 sealed class。
- 新增 27 個 ARB 檔（pt 拆 BR/PT；sr 因舊檔為空 `{}` 跳過，不新增）。
- 既有 3 個 ARB（en / zh_Hant / zh_Hans）補上 `localeNativeName` / `localeTranslator`，並移除三個 hardcoded `settingsLocaleXxx` key。
- Settings 動態 dropdown，依各 ARB 自帶 `localeNativeName` 排序。
- About 區塊新增 Translator 顯示（原始語言為空字串時不顯示）。

**範圍外**：
- 不改 Flutter i18n 機制本身（仍用 `flutter_localizations` + `gen_l10n` + `MaterialApp.locale`）。
- 不沿用舊版 vue-i18n 的 loader 機制（架構不適用，新版的 Flutter standard 已是 best practice）。
- 不處理舊版有但新版用不到的字串（`web_signin` / `teyvat_interactive_map` / `lightbox` / DataTable 分頁等）。
- 不為新版有但舊版沒對應的字串（`progress*` / `pity*` / `timeline*` / `account*` / `confirm*` 等）翻譯——靠 Flutter 自動 fallback 到 template ARB（`app_zh_Hant.arb`）。
- 不寫腳本的自動化測試（一次性工具，YAGNI）。

---

## 2. 整體架構

### 2.1 程式變動範圍

| 檔案 | 變動 |
|---|---|
| `lib/services/settings_storage.dart` | `AppLocale` enum → `LanguagePreference` sealed class；`_parseLocale` / `_localeToString` 改成 BCP-47 code 字串處理 |
| `lib/state/settings.dart` | `setLocale` 參數型別更新；`localeProvider` 從 switch 改成 BCP-47 code → `Locale` 解析 |
| `lib/pages/settings_page.dart` | `_LocaleDropdown` 改成從 `AppLocalizations.supportedLocales` + ARB metadata 動態列出；About 區塊新增 Translator |
| `lib/state/localization_metadata.dart`（**新**） | `localeMetadataProvider`：一次性 load 所有 supported locale 的 `localeNativeName` / `localeTranslator`，cache 成 `Map` |
| `lib/l10n/app_*.arb` × 30 | 既有 3 個改寫、新增 27 個 |
| `l10n.yaml` | 不動（維持 `template-arb-file: app_zh_Hant.arb`） |
| `tool/i18n_port/`（**新**） | 一次性 ARB 生成腳本，**整個目錄列入 `.gitignore`，不進版控** |
| `.gitignore` | 新增 `tool/i18n_port/` |

### 2.2 執行階段資料流

```
shared_preferences
   ↓  (BCP-47 字串如 "zh-Hant" / "ja" / "pt-BR" / "system")
SettingsStorage._parseLocale
   ↓  LanguagePreference (sealed class)
settingsProvider.locale
   ↓  watch
localeProvider
   ↓  Locale? (system → null；其他 → Locale.fromSubtags 風格解析)
MaterialApp.locale + supportedLocales
   ↓
gen_l10n 自動挑 ARB；缺 key 自動 fallback 到 app_zh_Hant.arb
```

### 2.3 `LanguagePreference` 模型

```dart
sealed class LanguagePreference {
  const LanguagePreference();

  factory LanguagePreference.fromCode(String code) =>
      code == 'system' ? const SystemLanguage() : LocaleLanguage(code);

  String toCode();
}

class SystemLanguage extends LanguagePreference {
  const SystemLanguage();
  @override
  String toCode() => 'system';
}

class LocaleLanguage extends LanguagePreference {
  const LocaleLanguage(this.code);
  final String code; // BCP-47, e.g. "zh-Hant", "pt-BR", "ja"
  @override
  String toCode() => code;
}
```

理由：36 個 enum 值寫死太醜，每加一語要動 enum / `_parseLocale` / 母語名稱 Map 三處——sealed class 一個 code 字串就夠。

### 2.4 SharedPreferences 相容性

舊使用者存在 `pref.locale` 的 value 為 `"zh-Hant"` / `"zh-Hans"` / `"en"` / `"system"`，全部仍是合法 BCP-47 code，**直接相容、不需要遷移程式碼**。

---

## 3. ARB 結構與映射

### 3.1 30 個 ARB 檔清單

採用「純語言代碼 + region 有意義才分」策略。

| ARB 檔名 | Flutter `Locale` | 舊版 JSON |
|---|---|---|
| **app_af.arb** | `Locale('af')` | `af_ZA.json` |
| **app_ar.arb** | `Locale('ar')` | `ar_SA.json` |
| **app_ca.arb** | `Locale('ca')` | `ca_ES.json` |
| **app_cs.arb** | `Locale('cs')` | `cs_CZ.json` |
| **app_da.arb** | `Locale('da')` | `da_DK.json` |
| **app_de.arb** | `Locale('de')` | `de_DE.json` |
| **app_el.arb** | `Locale('el')` | `el_GR.json` |
| app_en.arb | `Locale('en')` | （現有；用 `en_US.json` 補可能遺漏） |
| **app_es.arb** | `Locale('es')` | `es_ES.json` |
| **app_fi.arb** | `Locale('fi')` | `fi_FI.json` |
| **app_fr.arb** | `Locale('fr')` | `fr_FR.json` |
| **app_he.arb** | `Locale('he')` | `he_IL.json` |
| **app_hu.arb** | `Locale('hu')` | `hu_HU.json` |
| **app_it.arb** | `Locale('it')` | `it_IT.json` |
| **app_ja.arb** | `Locale('ja')` | `ja_JP.json` |
| **app_ko.arb** | `Locale('ko')` | `ko_KR.json` |
| **app_nl.arb** | `Locale('nl')` | `nl_NL.json` |
| **app_no.arb** | `Locale('no')` | `no_NO.json` |
| **app_pl.arb** | `Locale('pl')` | `pl_PL.json` |
| **app_pt_BR.arb** | `Locale('pt', 'BR')` | `pt_BR.json` |
| **app_pt_PT.arb** | `Locale('pt', 'PT')` | `pt_PT.json` |
| **app_ro.arb** | `Locale('ro')` | `ro_RO.json` |
| **app_ru.arb** | `Locale('ru')` | `ru_RU.json` |
| ~~app_sr.arb~~ | — | `sr_SP.json`（**已 verify 為空檔 `{}`，跳過**） |
| **app_sv.arb** | `Locale('sv')` | `sv_SE.json` |
| **app_th.arb** | `Locale('th')` | `th_TH.json` |
| **app_tr.arb** | `Locale('tr')` | `tr_TR.json` |
| **app_uk.arb** | `Locale('uk')` | `uk_UA.json` |
| **app_vi.arb** | `Locale('vi')` | `vi_VN.json` |
| app_zh_Hans.arb | `Locale('zh', 'Hans')` | （現有；用 `zh_CN.json` 補） |
| app_zh_Hant.arb | `Locale('zh', 'Hant')` | （現有；template） |

> `sr_SP.json` 已 verify 為 `{}`（無任何翻譯）。直接跳過，不新增 `app_sr.arb`。

### 3.2 BCP-47 code ↔ Flutter Locale 對應

| SharedPrefs 存的 code | Flutter Locale | ARB 檔名 |
|---|---|---|
| `"system"` | `null`（跟系統） | — |
| `"zh-Hant"` | `Locale('zh', 'Hant')` | `app_zh_Hant.arb` |
| `"pt-BR"` | `Locale('pt', 'BR')` | `app_pt_BR.arb` |
| `"ja"` | `Locale('ja')` | `app_ja.arb` |

解析函式：

```dart
Locale localeFromCode(String code) {
  final parts = code.split('-');
  return parts.length == 1 ? Locale(parts[0]) : Locale(parts[0], parts[1]);
}
```

### 3.3 兩個新 ARB metadata key

每個 ARB 加（格式示意；實際翻譯者內容由腳本從舊 `lang.translator` 帶入）：

```json
{
  "@@locale": "ja",
  "localeNativeName": "日本語",
  "localeTranslator": "<from old lang.translator>",
  ...
}
```

- `localeNativeName`：Settings dropdown 顯示用；每個語言看到的是自己母語名稱（沿用舊版 `lang.name`）。
- `localeTranslator`：About 區塊顯示，沿用舊版 `lang.translator`。
  - 原始語言（zh_Hant / zh_Hans 為 GoneTone 親自編寫）填空字串 `""`，UI 看到空就不顯示。
  - en 若舊版有 translator 就填、沒有就空。

**讀取方式**：

```dart
final localeMetadataProvider = FutureProvider<Map<String, LocaleMetadata>>((ref) async {
  final result = <String, LocaleMetadata>{};
  for (final locale in AppLocalizations.supportedLocales) {
    final l = await AppLocalizations.delegate.load(locale);
    result[locale.toLanguageTag()] = LocaleMetadata(
      nativeName: l.localeNativeName,
      translator: l.localeTranslator,
    );
  }
  return result;
});
```

ARB 內容會被 gen_l10n 編譯成 const Dart，`delegate.load(locale)` 為 `SynchronousFuture`，幾無 cost。

### 3.4 新 key → 舊 key 映射表（YAML）

格式（`tool/i18n_port/key_map.yaml`）：

```yaml
mappings:
  # 1:1 對應，無 placeholder
  - new: actionUpdate
    old: ui.text.update_data
  - new: actionClose
    old: ui.text.close_msg

  # 含 placeholder 的對應，明確指定改名規則
  - new: footerLastUpdated          # "Last updated: {time}"
    old: ui.text.data_update_time   # "資料更新時間：{time}"
    placeholders:
      time: time                    # 新名 → 舊名，這裡剛好相同
  - new: progressFetchingBanner     # "Fetching: {name}"
    old: ui.text.loading.loading_gacha_data
    placeholders:
      name: gacha_name              # 新 {name} ← 舊 {gacha_name}
```

**處理規則**：
1. 腳本 load 舊 JSON → 取出 `old_value`
2. 對 `placeholders` 內每個 `(new_name, old_name)`，把字串裡的 `{old_name}` 取代為 `{new_name}`
3. 寫到結果 ARB 的 `new` key
4. **不寫 `@new_key` metadata**（type 訊息只在 template ARB 內）

**Review 流程**：
- 由 Claude 寫好 `key_map.yaml`，把「具爭議性對應」的 review note 附在 implementation plan（writing-plans 產出的那份）
- 使用者 review YAML 後再跑腳本

**舊版有但映射表沒列的 key**：直接忽略。

### 3.5 缺 key fallback 行為

- Flutter `gen_l10n` 對 non-template ARB 缺 key，自動 fallback 到 template ARB（`app_zh_Hant.arb`）。
- `flutter gen-l10n` 印 warning，不 fail build。
- 使用者選日文，新版獨有功能（`progress*` / `pity*` / `timeline*` / `account*` / `confirm*`）會顯示繁中——這是已知並接受的行為。

### 3.6 既有 settings 字串調整

現有三個 ARB（zh_Hant / zh_Hans / en）內：

- **保留**：`settingsLocaleSystem`（dropdown 第一項，「跟隨系統」）
- **移除**：`settingsLocaleZhHant` / `settingsLocaleZhHans` / `settingsLocaleEn`（被 `localeNativeName` 取代）
- **新增**：`localeNativeName`、`localeTranslator`（無「Translator:」標籤字串——About 區塊用 `Icon(Icons.translate)` + 翻譯者名字呈現，icon 提供語意，省一個跨 27 個新增語沒翻譯的 fallback 困擾）

---

## 4. 一次性生成腳本

### 4.1 位置與檔案佈局

```
tool/i18n_port/             ← 整個目錄在 .gitignore，不進版控
├── README.md
├── key_map.yaml            ← 新 key → 舊 key 映射表
├── locale_map.yaml         ← 舊 locale code → 新 ARB 檔名 + Flutter Locale
└── port.dart               ← 腳本本體
```

`old_locales/` 不放在 `tool/i18n_port/`——腳本執行時透過 `git show master:src/locales/<code>.json` 動態抓。

### 4.2 腳本邏輯（`port.dart` 偽碼）

```dart
Future<void> main() async {
  final keyMap = loadKeyMap('tool/i18n_port/key_map.yaml');
  final localeMap = loadLocaleMap('tool/i18n_port/locale_map.yaml');

  for (final entry in localeMap) {
    // 1. git show master:src/locales/<oldCode>.json
    final oldJson = await readOldLocale(entry.oldCode);

    // 2. 對 keyMap 內每個 mapping，套用 placeholder 重命名
    final arb = <String, dynamic>{'@@locale': entry.flutterLocale};
    for (final m in keyMap.mappings) {
      final oldValue = oldJson[m.old];
      if (oldValue == null) continue;
      arb[m.newKey] = applyPlaceholderRenames(oldValue, m.placeholders);
    }

    // 3. localeNativeName / localeTranslator 從舊 lang.name / lang.translator
    arb['localeNativeName'] = oldJson['lang.name'] ?? entry.flutterLocale;
    arb['localeTranslator'] = oldJson['lang.translator'] ?? '';

    // 4. 寫到 lib/l10n/<arbFile>.arb
    File('lib/l10n/${entry.arbFile}').writeAsStringSync(prettifyJson(arb));
  }
}
```

**依賴**：Dart 標準庫 + `package:yaml`（Flutter 隱含已有）。透過 `Process.runSync('git', ['show', ...])` 取舊版 JSON。

**執行**：`dart run tool/i18n_port/port.dart`。

**何時跑**：實作流程中跑一次生成 ARB；跑完即用即丟，目錄可手動刪除（或保留也無妨，反正不在版控內）。

---

## 5. 測試策略

加三個檔（`test/`）：

1. **`test/services/settings_storage_test.dart`**（新增/擴充）
   - `LanguagePreference.fromCode('system')` → `SystemLanguage`
   - `LanguagePreference.fromCode('zh-Hant')` → `LocaleLanguage('zh-Hant')`
   - `LanguagePreference.fromCode('pt-BR')` → `LocaleLanguage('pt-BR')`
   - SharedPreferences roundtrip
   - 舊資料相容（既有 `"zh-Hant"` 仍可解析）

2. **`test/state/locale_provider_test.dart`**（新增）
   - `LocaleLanguage('zh-Hant')` → `Locale('zh', 'Hant')`
   - `LocaleLanguage('pt-BR')` → `Locale('pt', 'BR')`
   - `LocaleLanguage('ja')` → `Locale('ja')`
   - `SystemLanguage` → `null`

3. **`test/l10n/locale_metadata_test.dart`**（新增）
   - 每個 `AppLocalizations.supportedLocales` 都能 load
   - 每個 locale 的 `localeNativeName` 都非空
   - `zh_Hant` / `zh_Hans` 的 `localeTranslator` 為空字串

**不測試**：ARB 字串內容正確性（人工 review）；腳本本身（一次性工具）。

---

## 6. 提交策略

實作分 5 階段 commit，每階段獨立通過 `dart format lib/ test/` + `flutter analyze` + `flutter test`：

1. `feat(i18n): refactor AppLocale to LanguagePreference sealed class`
   - 重構 `settings_storage.dart` / `settings.dart` / `localeProvider`
   - 仍只支援 zh_Hant / zh_Hans / en 三種
   - `_LocaleDropdown` 仍 hardcoded 4 個選項，文字仍用 `settingsLocaleZhHant` 等既有 key，但每個選項 value 改成 `LanguagePreference.fromCode('zh-Hant')` 等
   - 這階段不動 ARB
2. `chore(tool): ignore i18n port working dir`
   - `.gitignore` 新增 `tool/i18n_port/`
   - 本地建立 `tool/i18n_port/`（腳本、映射表、README）但不進 commit
3. `feat(i18n): import master translations and add locale metadata`
   - 跑腳本生成 27 個新 ARB
   - 補上 3 個既有 ARB 的 `localeNativeName` / `localeTranslator`
   - 既有 3 個 ARB 仍保留 `settingsLocaleZhHant` / `settingsLocaleZhHans` / `settingsLocaleEn`（下一階段才移除——這階段 dropdown 還用得到）
   - `lib/l10n/generated/` 重新生成
4. `feat(settings): dynamic language picker with native names`
   - `_LocaleDropdown` 改為動態列表（依 `localeMetadataProvider`）
   - 新增 `localeMetadataProvider`
   - 移除既有 3 個 ARB 的 `settingsLocaleZhHant` / `settingsLocaleZhHans` / `settingsLocaleEn` 三個 key
   - `lib/l10n/generated/` 重新生成
5. `feat(about): show locale translator credit`
   - About 區塊新增 Translator 顯示：`Icon(Icons.translate)` + `localeTranslator` 字串；空字串時整個 row 不顯示

---

## 7. 已知 trade-off / open question

| 主題 | 決定 |
|---|---|
| 非中文使用者看到新版獨有功能 | 顯示繁中（template fallback） |
| 舊版 `web_signin` / `lightbox` 等翻譯 | 直接丟棄，新版用不到 |
| 新加語言流程 | 丟一個 ARB（含 `localeNativeName`）即可，完全資料驅動 |
| `sr_SP` locale 對應 | 跳過（舊檔為空 `{}`） |
| 腳本進版控 | 不進；`tool/i18n_port/` 在 `.gitignore` |
| 翻譯者署名 | 沿用舊版 `lang.translator`；原始語言（zh_Hant / zh_Hans）為空字串 |
