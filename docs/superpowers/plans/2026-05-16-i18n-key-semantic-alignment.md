# i18n Key 整理重構 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以 `app_zh.arb` 中文原文為準，整理 i18n key：改名 5 筆、移除 5 個死 key、合併 2 組重複，不改任何顯示文字/UI/邏輯。

**Architecture:** 純識別字層級重構。每筆變更同步套用到「所有實際含該 key 的 arb 檔」（9 檔中 6 個為部分翻譯）、程式碼 `l.<key>` 引用、以及 `flutter gen-l10n` 重建的產生碼。驗證靠 `flutter analyze`（殘留/失效引用會編譯錯誤）+ `flutter test`（既有測試回歸網）。

**Tech Stack:** Flutter `gen-l10n`（template = `lib/l10n/app_zh.arb`，輸出 `lib/l10n/generated/`，已 gitignore）、Dart。

---

## 背景與不變式（實作者必讀）

- **arb 檔非一致**：`app_zh.arb`(template, 全)、`app_en.arb`/`app_zh_Hans.arb`（近全）、
  `app_es/fr/ja/pt/th/vi.arb`（Crowdin 部分翻譯，僅 14–40 key）。
  → 操作原則：**某 key 在某 arb 檔有才動，沒有就跳過**；以 grep 找出所有出現處。
- **產生碼 gitignore**：`lib/l10n/generated/` 不進版控，**commit 不含產生碼**；
  但 `flutter analyze`/`flutter test` 前**必須先 `flutter gen-l10n`** 重建 getter，否則編譯失敗。
- **每個 Task 自成原子變更**：arb + 程式碼在同一 Task 內一起改完再 gen-l10n + analyze，
  確保每次 commit 時 `flutter analyze` 為綠。
- **JSON 取代鎖定鍵形**：取代 arb 內 key 一律比對含引號的鍵形 `"key"`（含 `:`），
  **嚴禁裸字串子字串取代**。特別注意 `settingsTheme` 是 `settingsThemeSystem/Dark/Light`
  的子字串，必須只比對 `"settingsTheme":`。
- **刪除/改名後 JSON 須合法**：本計畫所有受影響 key 在各 arb 皆位於物件中段，
  整行刪除不破壞逗號；若任一 arb 中該 key 恰為最後一個屬性，需修正前一行尾逗號。
  `flutter gen-l10n` 會在 arb 非法時報錯，是即時防線。
- **docs/superpowers 不進版控**：任何 `git add` 一律不要加入 `docs/` 下本計畫/spec。
- **提交前品質檢查（CLAUDE.md，不可跳過）**：每個 commit 前依序
  `dart format lib/ test/` → `flutter analyze`（須 `No issues found!`）→
  `flutter test`（須 `All tests passed!`）。
- 提交訊息結尾固定加：
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

## File Structure（受影響檔）

- **arb（依 grep 結果，僅改有該 key 的檔）**：`lib/l10n/app_zh.arb`（必）、
  `lib/l10n/app_en.arb`、`lib/l10n/app_zh_Hans.arb`，其餘部分翻譯檔視 grep 而定。
- **Dart 程式碼引用**：
  - `lib/pages/settings_page.dart`（settingsExportAccounts / settingsImportAccounts / confirmCancel×4）
  - `lib/pages/banner_page.dart`、`lib/pages/overview_page.dart`（timelineCountTopRarity）
  - `lib/widgets/data/sortable_table.dart`（sortDirectionNone / emptyNoFiltered）
  - `lib/widgets/empty_state.dart`（emptyNoFiltered）
  - `lib/widgets/cards/account_management.dart`（confirmCancel / accountRecapture）
  - `lib/widgets/dialogs/accounts_picker_dialog.dart`（confirmCancel）
  - `lib/widgets/uid_indicator.dart`（uidRecapture）
- **產生碼**：`lib/l10n/generated/*.dart`（由 `flutter gen-l10n` 重建，不 commit）。
- **測試**：已確認 `test/` 內無任何上述變更 key 的 `l.` 引用，**不需改測試**；
  `flutter test` 僅作回歸網。

---

## Task 1: 改名 5 筆（名實對齊）

對照表（舊 → 新）：

| 舊 key | 新 key | 有 @metadata 區塊 |
|---|---|---|
| `settingsExportAccounts` | `settingsExportData` | 否 |
| `settingsImportAccounts` | `settingsImportData` | 否 |
| `timelineCountTopRarity` | `timelineTopRarityTitle` | **是**（zh/en/zh_Hans，placeholders rank,n） |
| `sortDirectionNone` | `sortHintClickToSort` | 否 |
| `emptyNoFiltered` | `emptyNoFilterMatch` | 否 |

**Files:**
- Modify（arb，依 grep）: `lib/l10n/app_zh.arb`、`lib/l10n/app_en.arb`、`lib/l10n/app_zh_Hans.arb`（及任何 grep 命中的部分翻譯檔）
- Modify（code）: `lib/pages/settings_page.dart`、`lib/pages/banner_page.dart`、`lib/pages/overview_page.dart`、`lib/widgets/data/sortable_table.dart`、`lib/widgets/empty_state.dart`

- [ ] **Step 1: 建立基準引用清單**

Run:
```bash
cd E:/IdeaProjects/genshin_impact_wish_gacha_analyzer
grep -rn 'settingsExportAccounts\|settingsImportAccounts\|timelineCountTopRarity\|sortDirectionNone\|emptyNoFiltered' lib/ test/
```
記下所有命中行作為改完後核銷依據（程式碼中應只有 `l.<key>` 形式）。

- [ ] **Step 2: arb 改名（5 筆，所有命中檔）**

對每個 arb 檔，將下列「鍵形字串」整體取代（保留引號與冒號，值不動）：

- `"settingsExportAccounts":` → `"settingsExportData":`
- `"settingsImportAccounts":` → `"settingsImportData":`
- `"sortDirectionNone":` → `"sortHintClickToSort":`
- `"emptyNoFiltered":` → `"emptyNoFilterMatch":`
- `"timelineCountTopRarity":` → `"timelineTopRarityTitle":`
- `"@timelineCountTopRarity":` → `"@timelineTopRarityTitle":`（zh/en/zh_Hans 各有此 metadata 區塊，區塊內容不動）

逐檔以 grep 確認命中位置後用 Edit 工具精準取代。**不要對 `settingsTheme` 之外做裸字串取代**（本 Task 無 settingsTheme，提醒沿用鍵形比對紀律）。

- [ ] **Step 3: 程式碼引用改名**

精準取代（token 唯一，逐檔 Edit）：
- `lib/pages/settings_page.dart`：`l.settingsExportAccounts` → `l.settingsExportData`；`l.settingsImportAccounts` → `l.settingsImportData`
- `lib/widgets/data/sortable_table.dart`：`l.sortDirectionNone` → `l.sortHintClickToSort`；`l.emptyNoFiltered` → `l.emptyNoFilterMatch`
- `lib/widgets/empty_state.dart`：`l.emptyNoFiltered` → `l.emptyNoFilterMatch`
- `lib/pages/banner_page.dart`：`l.timelineCountTopRarity(` → `l.timelineTopRarityTitle(`（方法呼叫，引數 `(primary.rank, ...)` 不動）
- `lib/pages/overview_page.dart`：`l.timelineCountTopRarity(` → `l.timelineTopRarityTitle(`（引數 `(timelineRank, timelineEntries.length)` 不動）

- [ ] **Step 4: 重建產生碼**

Run:
```bash
flutter gen-l10n
```
Expected: 無錯誤輸出（若 arb JSON 非法會在此報錯 → 回 Step 2 修正）。

- [ ] **Step 5: 核銷殘留**

Run:
```bash
grep -rn 'settingsExportAccounts\|settingsImportAccounts\|timelineCountTopRarity\|sortDirectionNone\|emptyNoFiltered' lib/ test/
```
Expected: **無任何輸出**（含 arb 與程式碼皆已無舊 key；`lib/l10n/generated/` 為重建後新名）。
若仍有命中，定位並改之，再重跑直到清空。

- [ ] **Step 6: 品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `flutter analyze` → `No issues found!`；`flutter test` → `All tests passed!`。
任一失敗先修再繼續。

- [ ] **Step 7: Commit**

```bash
git add lib/
git commit -m "refactor(i18n): rename 5 keys to match zh source text

settingsExportAccounts->settingsExportData, settingsImportAccounts->settingsImportData,
timelineCountTopRarity->timelineTopRarityTitle, sortDirectionNone->sortHintClickToSort,
emptyNoFiltered->emptyNoFilterMatch

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```
（`git add lib/` 不含 gitignore 的 generated；勿 add `docs/`。）

---

## Task 2: 移除 5 個未使用死 key

目標 key（程式碼/測試零引用，已查證）：`statsThreeStarCount`、`statsTwoStarCount`、
`settingsTheme`、`settingsPlaceholderPhase2`、`confirmTypeMismatch`。
出現於 `app_zh.arb`、`app_en.arb`、`app_zh_Hans.arb`（部分翻譯檔無）。

**Files:**
- Modify（arb）: `lib/l10n/app_zh.arb`、`lib/l10n/app_en.arb`、`lib/l10n/app_zh_Hans.arb`（及任何 grep 命中的其他 arb）

- [ ] **Step 1: 確認確實零引用（防呆）**

Run:
```bash
grep -rn 'statsThreeStarCount\|statsTwoStarCount\|settingsPlaceholderPhase2\|confirmTypeMismatch' lib/ test/
grep -rn '"settingsTheme"' lib/ test/
```
Expected: 僅 `lib/l10n/*.arb` 命中（外加重建後的 `lib/l10n/generated/` getter），
`lib/` 業務碼與 `test/` **零命中**。若業務碼有命中 → 停止，回報（spec 前提被推翻）。

- [ ] **Step 2: 從各 arb 刪除 key 行（鍵形比對）**

對每個命中的 arb 檔，刪除以下整行（含行尾逗號）；若同檔存在對應 `"@key": { ... }`
metadata 區塊也一併刪除：
- `"statsThreeStarCount": ...`
- `"statsTwoStarCount": ...`
- `"settingsTheme": ...` ← **只比對 `"settingsTheme":`，勿動 `"settingsThemeSystem/Dark/Light"`**
- `"settingsPlaceholderPhase2": ...`
- `"confirmTypeMismatch": ...`

刪除後確認該 key 在各 arb 非最後一個屬性（本專案皆位於中段，整行刪除即合法）。

- [ ] **Step 3: 重建產生碼**

Run:
```bash
flutter gen-l10n
```
Expected: 無錯誤（arb 非法會在此爆 → 回 Step 2 檢查逗號/括號）。

- [ ] **Step 4: 核銷殘留**

Run:
```bash
grep -rn 'statsThreeStarCount\|statsTwoStarCount\|settingsPlaceholderPhase2\|confirmTypeMismatch' lib/l10n/*.arb
grep -rn '"settingsTheme"' lib/l10n/*.arb
```
Expected: **無輸出**（5 個 key 已從所有 arb 消失）。

- [ ] **Step 5: 品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` / `All tests passed!`。

- [ ] **Step 6: Commit**

```bash
git add lib/
git commit -m "refactor(i18n): remove 5 unused dead keys

statsThreeStarCount, statsTwoStarCount, settingsTheme,
settingsPlaceholderPhase2, confirmTypeMismatch (zero code/test references)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 合併「取消」重複 → 保留 `actionCancel`

`confirmCancel` 與 `actionCancel` 原文/各語言譯文一致。保留 `actionCancel`，
移除 `confirmCancel`，所有引用改向 `actionCancel`。
`confirmCancel` 程式碼引用 6 處（已查證）：
`settings_page.dart:538,586,601,718`、`account_management.dart:99`、`accounts_picker_dialog.dart:140`。

**Files:**
- Modify（arb）: 含 `confirmCancel` 的 arb（`app_zh.arb`/`app_en.arb`/`app_zh_Hans.arb` 等 grep 命中者）
- Modify（code）: `lib/pages/settings_page.dart`、`lib/widgets/cards/account_management.dart`、`lib/widgets/dialogs/accounts_picker_dialog.dart`

- [ ] **Step 1: 基準清單**

Run:
```bash
grep -rn 'l\.confirmCancel' lib/
grep -rn '"confirmCancel"\|"actionCancel"' lib/l10n/*.arb
```
確認每個含 `confirmCancel` 的 arb 檔**同時也有 `actionCancel`**（survivor 不致遺失譯文）。

- [ ] **Step 2: arb 移除 `confirmCancel`**

對每個命中 arb 刪除 `"confirmCancel": ...` 整行（及對應 `"@confirmCancel"` 區塊若有）。
`actionCancel` 維持不動。

- [ ] **Step 3: 程式碼引用改向**

將下列 6 處 `l.confirmCancel` → `l.actionCancel`：
- `lib/pages/settings_page.dart` 行 538、586、601、718
- `lib/widgets/cards/account_management.dart` 行 99
- `lib/widgets/dialogs/accounts_picker_dialog.dart` 行 140
（用逐檔 Edit；token `l.confirmCancel` 唯一，可同檔 replace_all。）

- [ ] **Step 4: 重建產生碼**

Run:
```bash
flutter gen-l10n
```
Expected: 無錯誤。

- [ ] **Step 5: 核銷殘留**

Run:
```bash
grep -rn 'confirmCancel' lib/ test/
```
Expected: **無輸出**（程式碼、arb、重建後 generated 皆無 `confirmCancel`）。

- [ ] **Step 6: 品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` / `All tests passed!`。

- [ ] **Step 7: Commit**

```bash
git add lib/
git commit -m "refactor(i18n): merge confirmCancel into actionCancel

Identical text/translations; repoint 6 call sites to l.actionCancel

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: 合併「新增帳號」重複 → 新 survivor `accountAdd`

`uidRecapture` 與 `accountRecapture` 原文/各語言譯文一致（皆「新增帳號」/「Add account」）。
新 survivor 鍵名 `accountAdd`（貼合原文，同時達成原改名目的）。
作法：每個含 `accountRecapture` 的 arb 將其改名為 `accountAdd`；同檔的 `uidRecapture` 整行刪除。
程式碼：`uid_indicator.dart`（`l.uidRecapture`）與 `account_management.dart`（`l.accountRecapture`）皆改 `l.accountAdd`。

**Files:**
- Modify（arb）: 含該二 key 的 arb（`app_zh.arb`/`app_en.arb`/`app_zh_Hans.arb` 等 grep 命中者）
- Modify（code）: `lib/widgets/uid_indicator.dart`、`lib/widgets/cards/account_management.dart`

- [ ] **Step 1: 基準清單**

Run:
```bash
grep -rn 'l\.uidRecapture\|l\.accountRecapture' lib/
grep -rn '"uidRecapture"\|"accountRecapture"\|"accountAdd"' lib/l10n/*.arb
```
確認尚無 `accountAdd`（避免撞名）；記錄含 `uidRecapture`/`accountRecapture` 的 arb 檔清單。

- [ ] **Step 2: arb 合併**

對每個命中 arb：
- `"accountRecapture":` → `"accountAdd":`（值不動；若有 `"@accountRecapture"` 區塊一併 → `"@accountAdd"`）
- 刪除 `"uidRecapture": ...` 整行（及 `"@uidRecapture"` 區塊若有）

- [ ] **Step 3: 程式碼引用改向**

- `lib/widgets/uid_indicator.dart`：`l.uidRecapture` → `l.accountAdd`
- `lib/widgets/cards/account_management.dart`：`l.accountRecapture` → `l.accountAdd`

- [ ] **Step 4: 重建產生碼**

Run:
```bash
flutter gen-l10n
```
Expected: 無錯誤。

- [ ] **Step 5: 核銷殘留**

Run:
```bash
grep -rn 'uidRecapture\|accountRecapture' lib/ test/
```
Expected: **無輸出**。

- [ ] **Step 6: 品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `No issues found!` / `All tests passed!`。

- [ ] **Step 7: Commit**

```bash
git add lib/
git commit -m "refactor(i18n): merge uidRecapture/accountRecapture into accountAdd

Identical text/translations; new key matches zh source, repoint both call sites

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 全域一致性收尾稽核

確認三類變更無任何遺漏（跨全部 arb 與全部程式碼）。

**Files:** 無修改（僅查核；若發現遺漏回對應 Task 修補後重跑）

- [ ] **Step 1: 舊 key 全域歸零**

Run:
```bash
cd E:/IdeaProjects/genshin_impact_wish_gacha_analyzer
grep -rn 'settingsExportAccounts\|settingsImportAccounts\|timelineCountTopRarity\|sortDirectionNone\|emptyNoFiltered\|statsThreeStarCount\|statsTwoStarCount\|settingsPlaceholderPhase2\|confirmTypeMismatch\|confirmCancel\|uidRecapture\|accountRecapture' lib/ test/
grep -rn '"settingsTheme"' lib/ test/
```
Expected: **完全無輸出**（所有舊/死/被併 key 已從 arb、程式碼、重建後 generated 消失）。

- [ ] **Step 2: 新 key 確實存在於 template**

Run:
```bash
grep -n 'settingsExportData\|settingsImportData\|timelineTopRarityTitle\|sortHintClickToSort\|emptyNoFilterMatch\|accountAdd' lib/l10n/app_zh.arb
```
Expected: 6 個新 key 皆在 `app_zh.arb` 命中（`accountAdd` 一處、其餘各一）。

- [ ] **Step 3: 最終全套品質檢查**

Run:
```bash
dart format lib/ test/
flutter analyze
flutter test
```
Expected: `flutter analyze` → `No issues found!`；`flutter test` → `All tests passed!`。

- [ ] **Step 4: 收尾**

若 Step 1–3 全綠且前 4 Task 皆已 commit，重構完成，無額外 commit。
（產生碼 gitignore；spec/plan 於 `docs/superpowers/` 不進版控。）

---

## Self-Review（已於撰寫後自查）

- **Spec 覆蓋**：A 改名(含 Low 2 筆)→Task 1；B 移除 5 死 key→Task 2；
  C 合併取消→Task 3、合併新增帳號→Task 4；部分翻譯前提→各 Task「grep 命中才動」；
  驗證(format/analyze/test + 全 arb 殘留檢查)→各 Task Step 5–6 + Task 5。無缺口。
- **Placeholder 掃描**：無 TBD/TODO；每步皆具體指令與預期輸出。
- **型別/命名一致**：新 key 名稱（settingsExportData/settingsImportData/
  timelineTopRarityTitle/sortHintClickToSort/emptyNoFilterMatch/accountAdd）
  與 survivor（actionCancel）全文一致；`@timelineCountTopRarity`→`@timelineTopRarityTitle`
  metadata 重命名已納入 Task 1 Step 2。
