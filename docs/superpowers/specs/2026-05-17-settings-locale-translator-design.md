# 設定頁語言區塊顯示「翻譯者：」設計

日期：2026-05-17

## 目標

設定頁（`lib/pages/settings_page.dart`）的「語言」`SectionCard` 中，於語言下拉選單下方新增一行「翻譯者：xxxxx」。當該語言的 `localeTranslator` 為空字串（原始語言，目前為繁體中文）時，整行不顯示。

## 背景與既有基礎設施

- `localeMetadataProvider`（`lib/state/localization_metadata.dart`）已提供每個 supported locale 的 `LocaleMetadata { nativeName, translator }`。`translator` 為逗號分隔署名字串，原始語言為空字串，可含 `<a href="https://...">label</a>` markup。
- `TranslatorText`（`lib/widgets/translator_text.dart`）已能把含 `<a href>` 的字串渲染為可點擊文字。`raw` 為空時 `parseTranslatorMarkup` 回傳空 segments。
- `ContributorsPage`（`lib/pages/contributors_page.dart`）已建立慣例：`translator.isEmpty` 時只顯示母語名，否則 `母語名 — TranslatorText(raw: translator)`。
- 9 個 ARB 檔（`lib/l10n/app_*.arb`）皆有 `localeNativeName` / `localeTranslator`，但**尚無**「翻譯者」標籤字串。

## 設計決策

| 項目 | 決策 |
|---|---|
| 「跟隨系統」時顯示哪個譯者 | 顯示**實際生效語言**的譯者：直接讀 `l.localeTranslator`（`AppLocalizations.of(context)` 本就是生效語言的本地化物件）。明選具體語言與跟隨系統自然走同一路徑，無需查 metadata 或解析 locale tag。 |
| 樣式 | 次要色小字輔助文字：`theme.gacha.textSecondary` + `bodySmall`，呈現為下拉選單的 helper text。 |
| l10n key | `localeTranslatorLabel`，帶 `{translator}` placeholder（值如 `"翻譯者：{translator}"`），讓 Crowdin 譯者更直覺看到上下文。`{translator}` 代入 `l.localeTranslator`（可含 `<a href>` markup），整串交由 `TranslatorText` 渲染。 |
| 防溢出 | 單一 `TranslatorText`，`Text.rich` 預設自動換行，無需 `Wrap`。 |

## 實作範圍

### 1. l10n

- 9 個 `lib/l10n/app_*.arb` 各新增 `localeTranslatorLabel` 鍵，帶 `{translator}` placeholder。`app_zh.arb`（template，最先）需附 `@localeTranslatorLabel`，內含 `placeholders.translator`（`type: String`）與 description。
- 重新產生 `lib/l10n/generated/app_localizations*`（透過 `flutter gen-l10n` 或既有產生流程）。

各語言建議值（冒號用各語言慣例，placeholder 位置依語序）：

| 檔案 | 值 |
|---|---|
| app_zh.arb（繁中） | `翻譯者：{translator}` |
| app_zh_Hans.arb（簡中） | `翻译者：{translator}` |
| app_en.arb | `Translator: {translator}` |
| app_ja.arb | `翻訳者：{translator}` |
| app_fr.arb | `Traducteur : {translator}` |
| app_es.arb | `Traductor: {translator}` |
| app_pt.arb | `Tradutor: {translator}` |
| app_th.arb | `ผู้แปล: {translator}` |
| app_vi.arb | `Người dịch: {translator}` |

template ARB（`app_zh.arb`）metadata 範例：

```json
"@localeTranslatorLabel": {
  "description": "Settings language section: shows who translated the current language. {translator} is the comma-separated translator credit (may contain <a href> markup), rendered by TranslatorText.",
  "placeholders": { "translator": { "type": "String" } }
}
```

（實作時若 ARB 內既有譯者署名慣例與上表衝突，以既有慣例為準並於 commit 說明。）

### 2. `_LocaleDropdown`（`lib/pages/settings_page.dart`）

- 目前 `build` 直接回傳 `DropdownButtonFormField`。改為回傳 `Column(crossAxisAlignment: stretch, children: [ dropdown, ...translatorRow ])`。
- 生效語言譯者：`final translator = l.localeTranslator;`（`l` 已是參數，即 `AppLocalizations.of(context)` 的生效語言物件）。不需 `localeMetadataProvider`、`Localizations.localeOf` 或 tag 比對。
- `translator` 為空 → 不加譯者行（不額外加 `SizedBox`）。
- 否則於 dropdown 下方加 `SizedBox(height: AppSpacing.xs/s)` + 單一 `TranslatorText`：
  - `TranslatorText(raw: l.localeTranslatorLabel(translator), style: bodySmall.copyWith(color: theme.gacha.textSecondary))`
  - 前綴「翻譯者：」為 `TextSegment` 套上述次要色 bodySmall；譯者字串內 `<a href>` 連結由 `TranslatorText` 內部以 primary 色 + 底線渲染並可點擊。
- 需 `import 'translator_text.dart'`。

### 3. 測試

擴充/新增 `test/pages/settings_page_*` widget test：

- **有譯者**：以某具體有譯者的 locale 渲染 `SettingsPage`，斷言出現 `localeTranslatorLabel` 文字與該語言譯者名。
- **空譯者隱藏**：以繁中（`localeTranslator` 空）渲染，斷言不出現 `localeTranslatorLabel`。
- 參考既有 `test/pages/contributors_page_test.dart` 的 metadata 載入/pump 模式。

## 不做（YAGNI）

- 不抽共用「譯者列」widget（ContributorsPage 用法不同：那邊是 `母語名 — 譯者` 列表，這邊是單一生效語言 + 標籤），維持各自簡單實作。
- 不新增設定開關控制是否顯示。
- 不處理 metadata 尚未載入的 loading 狀態（`localeMetadataProvider` 為同步 Provider，既有 dropdown 已直接使用，沿用相同假設）。

## 提交前檢查

`dart format lib/ test/` → `flutter analyze`（No issues found!）→ `flutter test`（All tests passed!）。
