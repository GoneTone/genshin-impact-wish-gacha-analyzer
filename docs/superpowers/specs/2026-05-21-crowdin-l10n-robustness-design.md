# Crowdin l10n 流程強化 — 設計文件

- 日期：2026-05-21
- 狀態：已通過 brainstorming，待轉 writing-plans

## 背景與問題

Crowdin 的自動 PR（branch `l10n`，標題「New Crowdin updates」）反覆讓 CI 失敗。實際查證後確認**兩個獨立根因**，且都無法靠 Crowdin 端設定解決：

1. **`@@locale` 帶地區碼**：Crowdin 的 ARB exporter 把 `@@locale` 寫成該語言的完整 locale 代碼（`es` → `es-ES`、`pt` → `pt-PT`、`sv` → `sv-SE`、`zh_Hans` → `zh-CN`、`pt_BR` → `pt-BR`），但檔名用 `%two_letters_code%`。Flutter `gen-l10n` 要求 `@@locale` 與檔名衍生 locale 一致，於是在 `flutter pub get`（觸發 synthetic l10n 產生）階段直接失敗。
   - 已查證：ARB exporter 不可設定；`languages_mapping` 只影響路徑/檔名 placeholder，改不到 `@@locale` 內容。**Crowdin 端無任何旋鈕**。

2. **零翻譯空殼 `.arb`**：Crowdin GitHub 整合**不可靠地忽略** `crowdin.yml` 的 `skip_untranslated_files`（社群已知問題），會塞進一堆 `{ "@@locale": "xx" }` 的空檔（0 翻譯、無 `localeNativeName`）。gen-l10n 會把它們納入 `supportedLocales`，內容全部 fallback 成模板（裸 `zh` = 繁體中文），導致語言選單冒出多個「繁體中文」、且 OS 為該語系的使用者會被解析到 100% fallback 的空殼。
   - `test/l10n/locale_metadata_test.dart` 既有的「各保留 locale 的 nativeName 互不重複」guard 正確地擋下了這個。

附帶：master 上原本完整的 `app_pt.arb`（通用葡語）被這次更新清空、內容移到新的 `app_pt_BR.arb`。

## 目標

- Crowdin 自動 PR 不再卡 CI，且 merge 後 master 不會壞。
- 不依賴 Crowdin 端設定。
- 維持語言選單與 locale 解析乾淨（只出現真正釋出的語言）。

## 非目標（YAGNI）

- 不做翻譯完成度百分比門檻（runtime 不暴露完成度，過度複雜）。
- 不在 pipeline 刪除空殼檔（採純軟體過濾；空殼留 repo）。
- 不調整 Crowdin 專案端設定作為解法的一部分。

## 已定案決策

| 主題 | 決定 |
|------|------|
| 「已釋出」門檻 | **有翻 `localeNativeName` 就算**（偵測是否 fallback 成模板繁中） |
| `@@locale` 正規化落點 | **整合進 CI `quality` job**，正規化後 commit 回 `l10n` 分支再驗證 |
| 空殼檔處理 | **純軟體過濾，檔案留在 repo** |
| Portuguese | **以 `pt_BR`（巴西葡語）呈現**（gate 自然結果：空 `pt` 被濾、`pt_BR` 留下） |

---

## 元件 A：`@@locale` 正規化（CI pipeline）

### A1. `tool/normalize_arb_locale.dart`

- **單一職責**：掃描 `lib/l10n/app_*.arb`，把每個檔的 `@@locale` 值設成「檔名衍生 locale」。
  - 映射規則：去掉 `app_` 前綴與 `.arb` 副檔名即為目標 locale（`app_zh_Hans.arb` → `zh_Hans`、`app_es.arb` → `es`、`app_pt_BR.arb` → `pt_BR`）。底線格式正是 Flutter 期望。
  - 只有當現值與目標不同才寫回，避免無謂 diff。
- **零套件相依**：只用 `dart:io` 與 `dart:convert`，使其能在 `flutter pub get` 之前執行（pub get 會觸發 gen-l10n，是失敗點）。
  - 實作上以最小破壞性方式改寫 `@@locale` 那一行，盡量保留原檔格式（避免整檔重排造成大 diff）。
- 退出碼：正常結束回 0；寫回檔案數量輸出到 stdout 供 CI log。

### A2. `.github/workflows/ci.yml`（`quality` job）

- `permissions:` 由 `contents: read` 改為 `contents: write`。
- checkout：對 `pull_request` 事件需 checkout PR head 分支（`ref: ${{ github.head_ref }}`）並保留認證（`persist-credentials: true`），以便 push 回去。
- 步驟順序（pub get 之前插入正規化）：
  1. `dart tool/normalize_arb_locale.dart`（pub get 前；invocation 細節於實作期驗證能否免 pub get 執行，必要時退回等效 shell 步驟）。
  2. 若 `git status` 有變更**且**為同 repo 的 PR（`github.event.pull_request.head.repo.full_name == github.repository`）：設定 bot 身份、`git commit -m "fix(l10n): normalize @@locale to match filenames"`、`git push` 回 head 分支。
  3. `flutter pub get` → `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test`，在已正規化的工作樹上執行 → **同一次 run 變綠**。
- 安全性：
  - 同一 run 內 push + 驗證，**不需 PAT/secret**；GITHUB_TOKEN 的 push 不會再觸發新 workflow，無迴圈。
  - master push 與非 l10n PR：檔案已正確 → 無 diff → 不 commit。
  - fork PR：無寫入權，但檔案通常已正確（無 diff）→ 不嘗試 push；commit 步驟以同 repo 條件守門。
- 結果：merge 後 master 取得已正規化的 `.arb`。

---

## 元件 B：軟體端過濾未釋出 locale

### B1. fallback 偵測

- 載入模板 `Locale('zh')`，取其 `localeNativeName` 作為 sentinel（即 `繁體中文`）。
- 保留規則：locale L 屬「已釋出」⟺ `L == Locale('zh')`（模板本身）**或** `load(L).localeNativeName != sentinel`。
  - 空殼 → fallback 成 sentinel → 排除。
  - `zh_Hans`（简体中文）≠ sentinel → 保留。
- 不硬編碼字串 `繁體中文`，改以「載入模板取值」自動追蹤。

### B2. `lib/state/localization_metadata.dart`

- 新增 `releasedLocalesProvider`（`Provider<List<Locale>>`）：gate 邏輯**集中此一處**，從 `AppLocalizations.supportedLocales` 過濾出已釋出 locale。
- `localeMetadataProvider` 改為以 `releasedLocalesProvider` 為來源（只為已釋出 locale 建 metadata）。
- 更新檔頭/provider 註解，移除過時的「不再有重複空殼」敘述。

### B3. `lib/main.dart`

- `MaterialApp.router` 的 `supportedLocales:` 由 `AppLocalizations.supportedLocales` 改為 `ref.watch(releasedLocalesProvider)`。
- `localeListResolutionCallback: localeListResolution` 不變——Flutter 會把我們提供的 released set 當作 `supportedLocales` 參數傳入 `localeListResolution`，故解析自動只在已釋出 locale 中進行。

---

## 元件 C：收尾

### C1. `crowdin.yml`

- 移除 `skip_untranslated_files: true` 及其上方誤導註解（GitHub 整合不吃此設定；且「gen-l10n 自動排除空殼」的假設經測試證實為錯）。
- 保留 `languages_mapping`（仍負責正確檔名）。

### C2. 測試

`test/l10n/locale_metadata_test.dart`：
- 「葡萄牙文 localeNativeName 含 Portugu」：改載入 `Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR')`。
- 「localeMetadataProvider … contains 'pt'」：改為 `pt-BR`。
- 「各保留 locale 的 nativeName 互不重複」「每個保留的 locale 都有非空 nativeName」「裸 zh 與 zh-Hans 都保留」：改為 watch released set（過濾後通過）。
- 既有針對 `localeListResolution`、`sortedLocaleMetadata` 的測試維持不變。

`test/pages/contributors_page_test.dart`：
- 「已翻譯語言 SectionCard …」：依過濾後的 released set 修正預期。

新增測試：
- `releasedLocalesProvider` gate 行為：空殼/未翻 localeNativeName 的 locale 被排除；`zh`、`zh_Hans`、`pt_BR`、`en`、`ja` 等保留。
- （可選）`tool/normalize_arb_locale.dart` 的單元測試：餵入 `@@locale: es-ES` 的暫存檔 → 正規化為 `es`；已正確者不變。

## 風險與緩解

- **CI 自動 commit 回分支**：限定同 repo 的 PR 才 push；無 diff 不 commit；commit 訊息固定、易辨識。
- **正規化腳本需在 pub get 前可執行**：以零相依實作；實作期驗證 invocation，必要時退回等效 shell 步驟。
- **Portuguese 由 `pt` 改為 `pt_BR`**：已與使用者確認接受；測試同步更新。

## 影響檔案清單

- 新增：`tool/normalize_arb_locale.dart`
- 修改：`.github/workflows/ci.yml`、`lib/state/localization_metadata.dart`、`lib/main.dart`、`crowdin.yml`
- 測試：`test/l10n/locale_metadata_test.dart`、`test/pages/contributors_page_test.dart`、新增 released gate 測試（與可選的正規化腳本測試）
