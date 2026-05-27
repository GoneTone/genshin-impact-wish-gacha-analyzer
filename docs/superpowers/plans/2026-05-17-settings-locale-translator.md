# 設定頁語言區塊顯示「翻譯者：」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 設定頁「語言」`SectionCard` 的下拉選單下方,新增一行「翻譯者：{譯者署名}」,生效語言 `localeTranslator` 為空(原始語言繁中)時整行不顯示。

**Architecture:** 新增帶 `{translator}` placeholder 的 l10n key `localeTranslatorLabel`(9 個 ARB),`_LocaleDropdown` 直接讀既有參數 `l.localeTranslator`(即 `AppLocalizations.of(context)` 的生效語言譯者字串),空字串隱藏,否則用單一既有 `TranslatorText` widget 渲染 `l.localeTranslatorLabel(l.localeTranslator)`(前綴為一般文字,內含 `<a href>` 連結可點)。不引入 `localeMetadataProvider`、不解析 locale tag、不抽新 widget。

**Tech Stack:** Flutter / Dart、gen_l10n(ARB)、flutter_riverpod、既有 `TranslatorText`(`lib/widgets/translator_text.dart`)。

依據 spec:`docs/superpowers/specs/2026-05-17-settings-locale-translator-design.md`

> **版控注意:** 依專案慣例,`docs/superpowers/` 下的 spec/plan 文件**不進版控**。各 Commit 步驟只 `git add` 異動到的 `lib/` 與 `test/` 檔,**不要** add 本 plan 或 spec md。

---

### Task 1: 新增 l10n key `localeTranslatorLabel`(含 placeholder)+ l10n 測試

**Files:**
- Modify: `lib/l10n/app_zh.arb`(template,需加 key + `@localeTranslatorLabel` metadata)
- Modify: `lib/l10n/app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、`app_fr.arb`、`app_es.arb`、`app_pt.arb`、`app_th.arb`、`app_vi.arb`(各加 key,無需 metadata)
- Generated(自動產生,勿手改): `lib/l10n/generated/app_localizations*.dart`
- Test: `test/l10n/locale_metadata_test.dart`(擴充,沿用既有 group)

- [ ] **Step 1: 先寫會失敗的 l10n 測試**

在 `test/l10n/locale_metadata_test.dart` 的 `group('AppLocalizations locale metadata', () { ... })` 內,最後一個 `test(...)` 之後、`});` 之前,新增以下三個 test:

```dart
    test('localeTranslatorLabel 帶 placeholder:每個 supported locale 都非空且含代入值', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = await AppLocalizations.delegate.load(locale);
        final out = l.localeTranslatorLabel('__TESTER__');
        expect(
          out,
          isNotEmpty,
          reason: '${locale.toLanguageTag()} 的 localeTranslatorLabel 不能為空',
        );
        expect(
          out,
          contains('__TESTER__'),
          reason: '${locale.toLanguageTag()} 的 localeTranslatorLabel 必須代入 {translator}',
        );
      }
    });

    test('裸 zh(繁中)localeTranslatorLabel = "翻譯者：X"', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.localeTranslatorLabel('X'), '翻譯者：X');
    });

    test('日文 localeTranslatorLabel = "翻訳者：X"', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.localeTranslatorLabel('X'), '翻訳者：X');
    });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/l10n/locale_metadata_test.dart`
Expected: FAIL — 編譯錯誤,`AppLocalizations` 沒有 `localeTranslatorLabel` method(key 尚未加、未重新產生)。

- [ ] **Step 3: 在 template `app_zh.arb` 加 key 與 metadata**

`lib/l10n/app_zh.arb` 目前開頭(第 1–12 行)為:

```json
{
  "@@locale": "zh",

  "localeNativeName": "繁體中文",
  "localeTranslator": "",

  "@localeNativeName": {
    "description": "Native name of this locale, shown in language picker."
  },
  "@localeTranslator": {
    "description": "Comma-separated list of translators for this locale. Empty = original language (no credit row shown)."
  },
```

改成(在 `"localeTranslator": "",` 後加一行 key;在 `@localeTranslator` 區塊後加 `@localeTranslatorLabel` 區塊):

```json
{
  "@@locale": "zh",

  "localeNativeName": "繁體中文",
  "localeTranslator": "",
  "localeTranslatorLabel": "翻譯者：{translator}",

  "@localeNativeName": {
    "description": "Native name of this locale, shown in language picker."
  },
  "@localeTranslator": {
    "description": "Comma-separated list of translators for this locale. Empty = original language (no credit row shown)."
  },
  "@localeTranslatorLabel": {
    "description": "Settings language section: shows who translated the currently active language. {translator} is the comma-separated translator credit (may contain <a href> markup), rendered by TranslatorText.",
    "placeholders": {
      "translator": { "type": "String" }
    }
  },
```

- [ ] **Step 4: 在其餘 8 個 ARB 各加 key(無 metadata)**

每個檔案在其 `"localeTranslator": "...",` 那一行的下一行,加入對應 key。各檔值如下(冒號用該語言慣例,`{translator}` 位置依語序):

- `lib/l10n/app_zh_Hans.arb`：`  "localeTranslatorLabel": "翻译者：{translator}",`
- `lib/l10n/app_en.arb`：`  "localeTranslatorLabel": "Translator: {translator}",`
- `lib/l10n/app_ja.arb`：`  "localeTranslatorLabel": "翻訳者：{translator}",`
- `lib/l10n/app_fr.arb`：`  "localeTranslatorLabel": "Traducteur : {translator}",`
- `lib/l10n/app_es.arb`：`  "localeTranslatorLabel": "Traductor: {translator}",`
- `lib/l10n/app_pt.arb`：`  "localeTranslatorLabel": "Tradutor: {translator}",`
- `lib/l10n/app_th.arb`：`  "localeTranslatorLabel": "ผู้แปล: {translator}",`
- `lib/l10n/app_vi.arb`：`  "localeTranslatorLabel": "Người dịch: {translator}",`

非 template ARB 不需要 `@localeTranslatorLabel` metadata(gen_l10n 只從 template 讀 placeholder 定義)。注意逗號:若插入點原本是檔內某區塊最後一個 key,確保新行尾逗號與 JSON 結構合法(對齊既有同檔風格即可)。

- [ ] **Step 5: 重新產生 localization 程式碼**

Run: `flutter gen-l10n`
Expected: 成功,無 error;`lib/l10n/generated/app_localizations.dart` 內出現 `String localeTranslatorLabel(String translator);`(及各語言子類實作)。

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/l10n/locale_metadata_test.dart`
Expected: PASS(含新增 3 個 test 與原有 test 全綠)。

- [ ] **Step 7: 格式化 + 靜態分析**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit(只 add lib/test 程式碼,勿 add docs)**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_fr.arb lib/l10n/app_es.arb lib/l10n/app_pt.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb lib/l10n/generated test/l10n/locale_metadata_test.dart
git commit -m "feat(l10n): add localeTranslatorLabel with translator placeholder"
```

---

### Task 2: `_LocaleDropdown` 下拉選單下方顯示翻譯者行

**Files:**
- Modify: `lib/pages/settings_page.dart`(`_LocaleDropdown.build`,約第 150–187 行;import 區約第 27–33 行)

**前置事實(已查證,勿改動行為):**
- `_LocaleDropdown` 已是 `ConsumerWidget`,已有參數 `final AppLocalizations l;`,`build(BuildContext context, WidgetRef ref)` 內已 `ref.watch(localeMetadataProvider)` 供 dropdown 選項清單用 —— 保留不動。
- `l.localeTranslator` 即「生效語言」的譯者字串(`AppLocalizations.of(context)` 本就是生效語言物件):明選語言或跟隨系統都自然正確,無需 `Localizations.localeOf` 或 tag 比對。
- `TranslatorText`(`lib/widgets/translator_text.dart`)建構式:`TranslatorText({required String raw, TextStyle? style})`;`raw` 內 `<a href="https://...">label</a>` 會渲染成 primary 色 + 底線可點連結,其餘為一般文字套 `style`。
- 次要色 token:`Theme.of(context).gacha.textSecondary`(`gacha` 擴充來自已 import 的 `theme/tokens.dart`,settings_page.dart 第 243 行已有同用法 `theme.gacha.textSecondary`)。
- 間距 token:`AppSpacing.xs`(同檔多處使用,例 `_AboutContent` 第 239 行 `const SizedBox(height: AppSpacing.xs)`)。

- [ ] **Step 1: 加入 `TranslatorText` import**

在 `lib/pages/settings_page.dart` import 區(現有第 33 行 `import '.../widgets/page_header.dart';` 之後)新增一行,維持結尾 widgets import 群組的字母序:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';
```

- [ ] **Step 2: 改寫 `_LocaleDropdown.build` 回傳值**

目前 `_LocaleDropdown.build`(`lib/pages/settings_page.dart`,約第 150–187 行)為:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(localeMetadataProvider);
    final sorted = sortedLocaleMetadata(metadata);
    final selectableTags = metadata.keys.toSet();
    // 防禦：使用者過去可能存了 supportedLocales 已不存在的代碼（例如
    // 整併前的 "pt-BR"）。若 current 不在當前 dropdown 選項裡，顯示為
    // SystemLanguage 避免 DropdownButtonFormField 因 value 找不到對應
    // 項目而 assert failed。
    final effectiveCurrent =
        current is SystemLanguage ||
            (current is LocaleLanguage &&
                selectableTags.contains((current as LocaleLanguage).code))
        ? current
        : const SystemLanguage();
    return DropdownButtonFormField<LanguagePreference>(
      initialValue: effectiveCurrent,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
          value: const SystemLanguage(),
          child: Text(l.settingsLocaleSystem),
        ),
        for (final entry in sorted)
          DropdownMenuItem(
            value: LocaleLanguage(entry.key),
            child: Text(entry.value.nativeName),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
```

把「最後 `return DropdownButtonFormField(...)` 」整段改為:先建好 dropdown,再用 `Column` 把 dropdown 與(條件性的)翻譯者行疊起來。將上面 `return DropdownButtonFormField<LanguagePreference>( ... );` 替換為:

```dart
    final dropdown = DropdownButtonFormField<LanguagePreference>(
      initialValue: effectiveCurrent,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
          value: const SystemLanguage(),
          child: Text(l.settingsLocaleSystem),
        ),
        for (final entry in sorted)
          DropdownMenuItem(
            value: LocaleLanguage(entry.key),
            child: Text(entry.value.nativeName),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

    final translator = l.localeTranslator;
    if (translator.isEmpty) return dropdown;

    final theme = Theme.of(context);
    final creditStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.gacha.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dropdown,
        const SizedBox(height: AppSpacing.xs),
        TranslatorText(
          raw: l.localeTranslatorLabel(translator),
          style: creditStyle,
        ),
      ],
    );
```

說明:`translator` 空(原始語言繁中)→ 直接回 `dropdown`,不加任何額外 widget/間距;非空 → dropdown 下方加 `AppSpacing.xs` 間距 + 單一 `TranslatorText`,前綴「翻譯者：」套次要色 `bodySmall`,字串內 `<a href>` 連結由 `TranslatorText` 內部以 primary 色渲染並可點。`SectionCard` 內容寬度已受限,`TranslatorText` 內部 `Text.rich` 預設自動換行,不會溢出邊界。

- [ ] **Step 3: 格式化 + 靜態分析**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 全測試回歸**

Run: `flutter test`
Expected: `All tests passed!`(Task 1 的 l10n 測試 + 既有測試全綠;本步不新增 widget 測試 —— 見下方「測試策略說明」)。

- [ ] **Step 5: 手動驗收(human / 執行者目視)**

啟動 app(`flutter run -d windows`,或既有 debug 流程),進設定頁:
1. 語言選「日本語」→ 下拉下方出現「翻訳者：jj、世界へいわ、Claude Code (Opus 4.7)」,其中 `世界へいわ` / `Claude Code (Opus 4.7)` 為可點連結(primary 色 + 底線),「翻訳者：」前綴為次要色小字。
2. 語言選「繁體中文」→ 下拉下方**不**出現任何翻譯者行,也無多餘空白間距。
3. 語言選「跟隨系統」(系統為非繁中語言時)→ 顯示該生效語言的譯者行;系統為繁中時不顯示。
4. 縮窄視窗 → 譯者行自動換行,不超出 `SectionCard` 邊界。

- [ ] **Step 6: Commit(只 add lib/ 程式碼)**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): show translator credit under language dropdown"
```

---

## 測試策略說明(寫入 plan 供執行者理解,勿略過)

- **唯一具邏輯的部分**是 placeholder 代入與 key 是否存在於所有 locale —— 由 Task 1 的 l10n 測試完整覆蓋(每個 supported locale 非空且含代入值;zh / ja 精確字串)。
- **顯示/隱藏**條件僅 `l.localeTranslator.isEmpty`,其值已由既有測試把關:`test/l10n/locale_metadata_test.dart` 既有 test「裸 zh(繁中)/ zh_Hans 的 localeTranslator 為空字串」+ `test/pages/contributors_page_test.dart`「繁體中文(localeTranslator 空字串)只顯示語言名稱」。邏輯為單一 `isEmpty` 三元,無額外分支。
- **不**新增 `SettingsPage` 全頁 widget 測試:該頁子樹依賴需 override 的 `appVersionProvider` / `logServiceProvider` / `wishStorageProvider`(`_LogsSection`、`_DataManagement`、`AccountManagement` 會觸發,且 `wishRepositoryProvider.build` 連帶做檔案 IO bootstrap),專案現無任何 `SettingsPage` 測試即因此。為此搭建重型且脆弱的 harness 違反 YAGNI 且收益低於 l10n 測試。show/hide 由 Step 5 手動驗收把關。

## Self-Review(已執行)

1. **Spec coverage:** spec 各項皆對應 —— l10n key+placeholder+各語言值表+template metadata → Task 1;`_LocaleDropdown` 改 `Column`、`l.localeTranslator` 空隱藏、單一 `TranslatorText` 帶次要色 bodySmall、import → Task 2;測試 → Task 1 l10n 測試 + 測試策略說明(spec「測試」節原列 widget show/hide,本 plan 以 l10n 測試 + 手動驗收替代並載明理由,符合 spec 的 YAGNI 取向)。
2. **Placeholder scan:** 無 TBD/TODO/「類似上面」;所有步驟含實際程式碼與精確指令、預期輸出。
3. **Type consistency:** `localeTranslatorLabel(String translator)` 在 Task 1 定義、Task 2 以 `l.localeTranslatorLabel(translator)` 呼叫,簽名一致;`TranslatorText({required raw, style})`、`theme.gacha.textSecondary`、`AppSpacing.xs` 均經查證與既有用法一致。
