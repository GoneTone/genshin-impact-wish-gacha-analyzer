# i18n Key 整理重構 — 設計 spec

日期：2026-05-16
分支：flutter-rewrite
範圍：i18n key 衛生整理（**改名 + 移除未使用 + 合併重複**）。純識別字層級，**不改任何顯示文字、UI、業務邏輯**。

## 目標

以 `lib/l10n/app_zh.arb`（繁體中文，l10n template / Crowdin source）的中文原文為準：

1. **改名**：名稱語意與原文不符者，改名貼合原文。
2. **移除未使用**：程式碼/測試完全零引用的死 key 移除。
3. **合併重複**：中文相同且語境一致、跨語言譯文也一致的真正重複，合併為單一 key。

## 決策（已與使用者確認）

1. **判定範圍**：全面對齊語意。
2. **命名規則**：保留領域前綴分組為主；前綴錯置可一併調整。
3. **翻譯處理**：本地同步改全部相關 arb 檔（含 `@key` metadata），各語言譯文值原封不動只換鍵名。Crowdin 推送由使用者後續自理。
4. **合併政策**：保守 — 僅「中文相同 + 語境/語意相同 + 各語言現有譯文實際也一致」才合併。

## 重要前提（稽核時發現）

各 arb 檔 key 數量**並非一致**，6 個語言為 Crowdin 進行中的部分翻譯：

| 檔 | 角色 | 概略 key 數 |
|---|---|---|
| `app_zh.arb` | template / source（真值來源） | 199 內容 key（全） |
| `app_en.arb` | 完整 | ~全 |
| `app_zh_Hans.arb` | 大致完整 | ~全 |
| `app_es/fr/ja/pt/th/vi.arb` | **部分翻譯** | 14–40 |

→ 因此每筆改名/移除/合併的操作原則是：**「該 arb 檔有此 key 才動，沒有就跳過」**，
而非假設 9 檔 key 集合一致。

## A. 改名（名實不符）

### Strong — 名稱明顯誤導

| 舊 key | 原文 | 問題 | 新 key |
|---|---|---|---|
| `settingsExportAccounts` | `匯出資料` | 名稱 Accounts，原文是「資料」 | `settingsExportData` |
| `settingsImportAccounts` | `匯入資料` | 同上 | `settingsImportData` |
| `timelineCountTopRarity` | `{rank}★ 時間軸 ({n})` | 名稱 CountTopRarity，實際是「最高稀有度時間軸」標題，語序誤導 | `timelineTopRarityTitle` |

> 原 spec 的 `uidRecapture`/`accountRecapture`/`settingsPlaceholderPhase2` 三筆已移轉：
> 前兩者改為「合併」（見 C 段，效果含改名），後者經查為未使用 → 改為「移除」（見 B 段）。

### Low — 經使用者裁示「納入都改」

| 舊 key | 原文 | 新 key |
|---|---|---|
| `sortDirectionNone` | `點擊排序` | `sortHintClickToSort`（脫離 sortDirection* 群，sortDirectionDesc/Asc 保留） |
| `emptyNoFiltered` | `沒有符合條件的紀錄` | `emptyNoFilterMatch` |

## B. 移除未使用（死 key）

下列 5 個 key **僅存在於 arb 檔，全專案 lib/ 與 test/ 零引用**（已 grep 確認，含非 `l.` 字串/動態引用）。
從所有含該 key 的 arb 檔移除（含 `@key` metadata）：

| key | 原文 | 出現於 |
|---|---|---|
| `statsThreeStarCount` | `3★ 件數` | zh, en, zh_Hans |
| `statsTwoStarCount` | `2★ 件數` | zh, en, zh_Hans |
| `settingsTheme` | `主題` | zh, en, zh_Hans |
| `settingsPlaceholderPhase2` | `（即將推出）` | zh, en, zh_Hans |
| `confirmTypeMismatch` | `輸入不符，操作已取消` | zh, en, zh_Hans |

## C. 合併重複

### 通過保守政策 — 執行合併（使用者裁示「兩組都合」）

跨語言查證：兩組在「所有實際擁有該 key 的檔」中譯文完全一致。

| 重複組（原文相同） | survivor | 移除 | 程式碼引用改向 |
|---|---|---|---|
| `actionCancel` + `confirmCancel`（皆「取消」） | **`actionCancel`** | `confirmCancel` | 所有 `l.confirmCancel` → `l.actionCancel` |
| `uidRecapture` + `accountRecapture`（皆「新增帳號」） | **`accountAdd`**（新名，貼合原文） | `uidRecapture`、`accountRecapture` | `l.uidRecapture` / `l.accountRecapture` → `l.accountAdd` |

- 取消組保留 `actionCancel`：confirm 對話框沿用 `actionCancel`（`confirmCancel` 使用點散見
  `settings_page.dart`、`account_management.dart`、`accounts_picker_dialog.dart`，全部改向）。
- 新增帳號組 survivor 取新名 `accountAdd`：uid_indicator 與 account_management 共用，
  同時達成原 `uidRecapture`/`accountRecapture` 改名貼合原文的目的。

### 已檢視，依保守政策「不」合併（語境不同）

| 重複組（原文相同） | 不合併原因 |
|---|---|
| `relativeNow` + `timelineNowLabel`（「現在」） | 相對時間字串 vs 時間軸座標標籤，語境不同 |
| `navStandard` + `navOdesStandard`（「常駐」） | 祈願區 vs 頌願區的平行 nav，語境不同 |
| `settingsThemeSystem` + `settingsLocaleSystem`（「跟隨系統」） | 主題 vs 語言設定，語境不同（其他語言可能分開譯） |
| `statsTotal` + `tableTotalIndex`（「總抽數」） | 統計卡大數字 vs 表格欄位標題，語境不同 |

## 實作設計

一輪重構，A/B/C 三類變更共用同一批 arb/程式碼修改與一次產生碼、一次驗證。

### 受影響面向

1. **arb 檔**：對每筆變更，套用到**所有實際含該 key 的 arb 檔**（zh 必有；en/zh_Hans 多半有；部分語言視情況）。
   - 改名：改 key 與其 `@key` metadata；譯文值不動。
   - 移除：刪 key 與其 `@key` metadata。
   - 合併：保留 survivor key，移除被併 key（及其 metadata）；survivor 譯文值維持不變。
2. **程式碼引用**：`l.<oldKey>` → `<newKey>` / survivor key；含帶 placeholder 的方法呼叫。
   主要引用點（grep 已確認）：`settings_page.dart`、`uid_indicator.dart`、
   `account_management.dart`、`accounts_picker_dialog.dart`、`update_progress_dialog.dart`、
   `banner_page.dart`、`overview_page.dart`、`sortable_table.dart`、`empty_state.dart` 等。
   - 變更前先 grep 建立完整「key → 引用位置」基準清單，逐一核銷。
3. **產生碼**：全部變更完成後一次 `flutter gen-l10n` 重建 `lib/l10n/generated/app_localizations*.dart`。

### 執行順序

1. grep 全部受影響 key 的引用位置，記錄基準。
2. arb 檔：逐 key 套用 A（改名）、B（移除）、C（合併）。
3. dart 程式碼：改引用（合併組把兩處引用都指向 survivor）。
4. 一次 `flutter gen-l10n`。

### 驗證（對齊 CLAUDE.md 提交前品質檢查）

1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
   （殘留舊 key / 被移除 key / 被併 key 的引用會在此編譯錯誤爆出，是主要安全網）
3. `flutter test` → 必須 `All tests passed!`
4. 一致性檢查：grep 全 arb 確認**無任何舊 key / 已移除 key / 被併 key 殘留**，
   亦無遺留對應 `@oldKey` metadata。

### 風險與控制

- **部分翻譯檔遺漏**：操作原則「該檔有才動」；步驟 4 全 arb grep 殘留檢查涵蓋所有檔。
- **placeholder 方法漏改**：帶參數 key 是方法呼叫；以步驟 1 基準清單核銷。
- **合併誤傷語境**：已採保守政策且逐組跨語言查證，不合併語境不同者。
- **不可逆性**：純 key 層級、譯文值不動，git 可完整 diff，風險低。

## 不做（YAGNI / 範圍外）

- 不改任何顯示文字、UI、邏輯。
- 不處理 Crowdin 平台端推送/TM 對應（使用者後續自理）。
- 不補齊部分翻譯語言缺少的 key。
- 不重整名實相符的 key，不合併語境不同的重複，避免無謂 churn。
- 不新增 key，不調整 placeholder 定義內容。
