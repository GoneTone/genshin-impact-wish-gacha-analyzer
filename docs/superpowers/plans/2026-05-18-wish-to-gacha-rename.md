# `wish` → `gacha` 中立化重構 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將專案內 `wish`（祈願）相關命名中立化為 `gacha`，讓未來 clone 成其他遊戲時無原神名稱殘留。

**Architecture:** 採做法 C — `git mv` 重新命名 17 個檔 + 對非 l10n 的 `.dart` 做大小寫敏感整體 token 取代（`wish`→`gacha`、`Wish`→`Gacha`，涵蓋 class / 識別子 / Logger 字串 / 路徑字串 / import / 英文註解）+ arb key 定向改名 + `flutter gen-l10n` 重產 + 繁中註解「祈願」→「卡池」。重構過程中間狀態**預期無法編譯**（原子 rename 本質），以最終 `flutter analyze` + `flutter test` 作為安全網一次驗證。

**Tech Stack:** Flutter / Dart、Flutter gen-l10n、git mv、PowerShell / bash。

**前置盤點結論（已驗證）：**
- 子字串安全：無 `wish` 混入非祈願概念的詞、無全大寫 `WISH` → 整體 token 取代安全。
- 繁中「祈願」恰 5 處，全在 doc-comment 且全為「卡池/類別」語意，機械換即可。
- i18n 含 wish 的 key 恰 3 個，僅存在於 `app_{en,ja,zh,zh_Hans}.arb`，純 `key:value` 無 `@meta`；值不含這 3 個 key token。
- `lib/src/rust/`、`rust/` 無 `wish` 識別子，免動。

**範圍外（絕不更動）：** package 名 `genshin_impact_wish_gacha_analyzer`、外部 API 字面（`authkey*`/`sign_type`/`game_biz`/`hoyoverse.com`/`hoyolab.com`/`mihoyo`）、gacha_type 代碼、`pity`/`banner`/`gachaType*`、i18n 顯示文字值、「頌願」、`lib/l10n/generated/`（改用重產）。

**注意：** 本計畫檔與 spec 位於 `docs/superpowers/`，已被 `.gitignore` 排除，**保留本地、不 commit**。最終只 commit 程式碼變更（單一 commit）。

---

### Task 1: git mv 重新命名 17 個檔

**Files:**
- Modify (rename): `lib/models/wish_record.dart`、`lib/services/wish_fetcher.dart`、`lib/services/wish_filter.dart`、`lib/services/wish_pity.dart`、`lib/services/wish_row.dart`、`lib/services/wish_stats.dart`、`lib/services/wish_storage.dart`、`lib/state/wish_capture.dart`、`lib/state/wish_repository.dart`
- Test (rename): `test/models/wish_record_test.dart`、`test/services/wish_fetcher_test.dart`、`test/services/wish_filter_test.dart`、`test/services/wish_pity_test.dart`、`test/services/wish_row_test.dart`、`test/services/wish_stats_test.dart`、`test/services/wish_storage_test.dart`、`test/state/wish_repository_test.dart`

- [ ] **Step 1: git mv 全部 17 檔（保留歷史）**

於專案根目錄 (bash 工具) 執行：

```bash
git mv lib/models/wish_record.dart       lib/models/gacha_record.dart
git mv lib/services/wish_fetcher.dart    lib/services/gacha_fetcher.dart
git mv lib/services/wish_filter.dart     lib/services/gacha_filter.dart
git mv lib/services/wish_pity.dart       lib/services/gacha_pity.dart
git mv lib/services/wish_row.dart        lib/services/gacha_row.dart
git mv lib/services/wish_stats.dart      lib/services/gacha_stats.dart
git mv lib/services/wish_storage.dart    lib/services/gacha_storage.dart
git mv lib/state/wish_capture.dart       lib/state/gacha_capture.dart
git mv lib/state/wish_repository.dart    lib/state/gacha_repository.dart
git mv test/models/wish_record_test.dart      test/models/gacha_record_test.dart
git mv test/services/wish_fetcher_test.dart   test/services/gacha_fetcher_test.dart
git mv test/services/wish_filter_test.dart    test/services/gacha_filter_test.dart
git mv test/services/wish_pity_test.dart      test/services/gacha_pity_test.dart
git mv test/services/wish_row_test.dart       test/services/gacha_row_test.dart
git mv test/services/wish_stats_test.dart     test/services/gacha_stats_test.dart
git mv test/services/wish_storage_test.dart   test/services/gacha_storage_test.dart
git mv test/state/wish_repository_test.dart   test/state/gacha_repository_test.dart
```

- [ ] **Step 2: 驗證檔案已搬移、無殘留 wish 檔名**

Run: `git status --short && find lib test -iname "*wish*"`
Expected: `git status` 顯示 17 筆 `R` (renamed)；`find` 無輸出（無殘留 wish 檔名）。

不在此 commit（最終 Task 7 一次提交）。

---

### Task 2: 非 l10n `.dart` 整體 token 取代（`Wish`→`Gacha`、`wish`→`gacha`）

**Files:**
- Modify: `lib/` 與 `test/` 下所有 `.dart`，**排除 `lib/l10n/`**（arb 與 generated 皆排除，於 Task 3 / Task 4 處理）

涵蓋：8 個 class（`WishRecord/Repository/Storage/Fetcher/Capture/Stats/State`、`RustWishCapture`→`Gacha*`）、全小寫識別子、Logger 字串（`'wish.capture'`→`'gacha.capture'` 等 4 個）、路徑字串（`main.dart` 的 `wish_data`→`gacha_data`）、import 路徑（對應 Task 1 改名）、英文註解。繁中「祈願」不受影響（非 `wish`/`Wish`），於 Task 5 處理。

- [ ] **Step 1: 對非 l10n `.dart` 執行大小寫敏感整體取代**

於專案根目錄 (bash 工具) 執行（先 `Wish`→`Gacha` 再 `wish`→`gacha`，大小寫敏感）：

```bash
grep -rl --include='*.dart' -e 'Wish' -e 'wish' lib test \
  | grep -v '^lib/l10n/' \
  | while IFS= read -r f; do
      sed -i 's/Wish/Gacha/g; s/wish/gacha/g' "$f"
    done
```

> 說明：`grep -v '^lib/l10n/'` 確保 `lib/l10n/`（arb + generated）完全不被掃。`test/` 下無 l10n 檔，全數納入。已驗證無 `wish` 子字串混入非祈願概念的詞、無全大寫 `WISH`，故整體取代安全。

- [ ] **Step 2: 驗證非 l10n `.dart` 已無 `wish`/`Wish` 殘留**

Run: `grep -rn --include='*.dart' -e 'Wish' -e 'wish' lib test | grep -v '^lib/l10n/'`
Expected: 無輸出（非 l10n `.dart` 已全數中立化）。

- [ ] **Step 3: 驗證 Logger 與路徑字串已正確改名**

Run: `grep -rn "Logger('gacha\.\(capture\|fetcher\|repo\|storage\)')" lib && grep -n "gacha_data" lib/main.dart`
Expected: 4 個 Logger 字串皆為 `gacha.*`；`lib/main.dart` 出現 `/gacha_data` 路徑（不做資料遷移）。

不在此 commit。

---

### Task 3: arb i18n key 定向改名（3 key × 4 檔，值不動）

**Files:**
- Modify: `lib/l10n/app_en.arb`、`lib/l10n/app_ja.arb`、`lib/l10n/app_zh.arb`、`lib/l10n/app_zh_Hans.arb`

key 對照：`navSectionWish`→`navSectionGacha`、`emptyNoWishRecords`→`emptyNoGachaRecords`、`pageOverviewWishSection`→`pageOverviewGachaSection`。這 3 個 token 在 arb 內僅作為 key 出現（顯示文字值不含此 token），故定向 token 取代安全；其餘 `es/fr/pt/th/vi` 無此 3 key（走 template `app_zh.arb` fallback），不需動。

- [ ] **Step 1: 對 4 個 arb 檔做定向 key 改名**

於專案根目錄 (bash 工具) 執行：

```bash
for f in lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb; do
  sed -i 's/navSectionWish/navSectionGacha/g; s/emptyNoWishRecords/emptyNoGachaRecords/g; s/pageOverviewWishSection/pageOverviewGachaSection/g' "$f"
done
```

- [ ] **Step 2: 驗證 key 已改、顯示文字值未被波及**

Run: `grep -n 'navSectionGacha\|emptyNoGachaRecords\|pageOverviewGachaSection' lib/l10n/app_en.arb && grep -c 'Genshin Wish Analyzer\|Character Event Wish' lib/l10n/app_en.arb`
Expected: 3 個新 key 出現於 `app_en.arb`；第二個 `grep -c` 仍 `>=1`（顯示文字值「Genshin Wish Analyzer」「Character Event Wish」原樣保留）。

不在此 commit。

---

### Task 4: `flutter gen-l10n` 重產 generated localizations

**Files:**
- Modify (regenerated): `lib/l10n/generated/app_localizations*.dart`（自動產生，不手改）

`l10n.yaml`：arb-dir `lib/l10n`，template `app_zh.arb`，output `lib/l10n/generated/`。Task 2 已把 `lib/pages/app_shell.dart` 與 `lib/pages/overview_page.dart` 的 `l.navSectionWish`/`l.pageOverviewWishSection`/`l.emptyNoWishRecords` 改成 `Gacha` 版；本 Task 重產 generated 使新 getter 名對齊。

- [ ] **Step 1: 重新產生 l10n**

於專案根目錄 (PowerShell 工具) 執行：

```
flutter gen-l10n
```

Expected: 指令成功結束（無 error），`lib/l10n/generated/` 被更新。

- [ ] **Step 2: 驗證 generated 已採用新 getter 名**

Run: `grep -rn 'navSectionGacha\|emptyNoGachaRecords\|pageOverviewGachaSection' lib/l10n/generated/app_localizations.dart`
Expected: 3 個新 getter 名出現於 generated 抽象類別。

不在此 commit。

---

### Task 5: 繁中註解「祈願」→「卡池」（5 處）

**Files:**（路徑為 Task 1 改名後的新路徑）
- Modify: `lib/models/gacha_record.dart`、`lib/services/gacha_row.dart`（2 處）、`lib/widgets/cards/banner_top_rarity_bars.dart`、`lib/widgets/data/sortable_table.dart`

已確認 5 處全為 doc-comment 且全屬「卡池/類別」語意（無「抽取動作」句），機械替換即可。「頌願」不在範圍、不動。

- [ ] **Step 1: 替換 5 處繁中註解「祈願」→「卡池」**

於專案根目錄 (bash 工具) 執行：

```bash
for f in lib/models/gacha_record.dart lib/services/gacha_row.dart lib/widgets/cards/banner_top_rarity_bars.dart lib/widgets/data/sortable_table.dart; do
  sed -i 's/祈願/卡池/g' "$f"
done
```

對照（替換後預期內容）：
- `lib/models/gacha_record.dart`：`/// - 卡池 (getGachaLog): \`name\` / \`gacha_type\` / \`lang\``
- `lib/services/gacha_row.dart`：`/// [buildRecordRows.mainRank] 決定（卡池預設 5★、常駐頌願 4★）。` 與 `/// [mainRank] 預設 5（卡池主稀有度）。常駐頌願須傳 4。`
- `lib/widgets/cards/banner_top_rarity_bars.dart`：`/// 每個 [GachaType] 依其 \`primaryPity.rank\` 決定該池要計數的稀有度（卡池是`
- `lib/widgets/data/sortable_table.dart`：`/// 該卡池的主稀有度 rank（卡池預設 5、常駐頌願 4），用於「保底內」欄`

- [ ] **Step 2: 驗證繁中「祈願」已清除（範圍內檔），「頌願」保留**

Run: `grep -rn '祈願' lib --include=*.dart | grep -v '^lib/l10n/' ; grep -rn '頌願' lib/services/gacha_row.dart`
Expected: 第一個 `grep`（祈願）無輸出；第二個 `grep`（頌願）仍有輸出（未被波及）。

不在此 commit。

---

### Task 6: 驗證閘門（CLAUDE.md 提交前品質檢查）

**Files:** 無（僅驗證）

- [ ] **Step 1: 格式化**

Run (PowerShell): `dart format lib/ test/`
Expected: 指令成功，回報已格式化的檔案數，無 error。

- [ ] **Step 2: 靜態分析**

Run (PowerShell): `flutter analyze`
Expected: 輸出 `No issues found!`。若有 error（多半是漏改的 import / getter），回到對應 Task 修正後重跑。

- [ ] **Step 3: 測試**

Run (PowerShell): `flutter test`
Expected: 輸出 `All tests passed!`。

- [ ] **Step 4: 殘留稽核**

Run (bash): `grep -rn -e 'Wish' -e 'wish' -e '祈願' lib test --include=*.dart --include=*.arb`
Expected: 殘留只允許落在白名單 —
  - i18n **顯示文字值**（如 `"Genshin Wish Analyzer"`、`"Character Event Wish"`、`"...祈願"` 等 arb value 行）；
  - 被排除的外部 API 字面（`getGachaLog` 等註解描述、無 `wish` 識別子）。

逐筆人工核對，確認無「應改未改」之識別子 / key / 英文註解 / 範圍內繁中「祈願」。

---

### Task 7: 單一 commit

**Files:** 全部變更

- [ ] **Step 1: 暫存所有變更並確認 rename 被辨識**

Run (bash): `git add -A && git status --short`
Expected: 17 筆 `R`（renamed）+ 內容修改檔；**不含** `docs/superpowers/`（已被 gitignore）。

- [ ] **Step 2: 提交**

Run (bash):

```bash
git commit -m "$(cat <<'EOF'
refactor(naming): rename wish→gacha for game-agnostic reuse

將 wish 相關 class / 識別子 / 檔名 / Logger / 路徑字串 / i18n key /
英文與繁中註解中立化為 gacha，便於後續 clone 成其他遊戲。
顯示文字值、外部 API 字面、package 名維持不變；wish_data 路徑改名不做資料遷移。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit 成功；`git show --stat HEAD` 顯示 17 個 rename + 內容變更。

- [ ] **Step 3: 提交後最終確認**

Run (PowerShell): `flutter analyze`
Expected: `No issues found!`（確認 commit 內容即為已驗證狀態）。

---

## Self-Review

**Spec coverage：**
- 識別子（8 class + 全小寫）→ Task 2 ✓
- 檔案 git mv（17）→ Task 1 ✓
- Logger（4）→ Task 2（含 Step 3 驗證）✓
- 路徑字串 `wish_data`→`gacha_data` 不遷移 → Task 2（含 Step 3 驗證）✓
- i18n key（3×4 檔）+ 重產 + 3 處 `.dart` 引用 → arb 改名 Task 3、`.dart` 引用 Task 2、重產 Task 4 ✓
- 註解（英文機械 / 繁中「祈願」→「卡池」）→ 英文 Task 2、繁中 Task 5 ✓
- 硬性排除（顯示值 / 外部 API / package / generated / rust / pity / banner / 頌願）→ Task 2 排除 l10n、Task 3 定向 key、Task 5 不動頌願、Task 6 Step 4 稽核 ✓
- 驗證（format / analyze / test / 殘留 grep）→ Task 6 ✓
- 單一 commit → Task 7 ✓

**Placeholder scan：** 無 TBD/TODO；每個程式步驟皆附確切指令與預期輸出。

**Type consistency：** class 對照表（`Wish*`→`Gacha*`、`RustWishCapture`→`RustGachaCapture`）、i18n key 三組對照、Logger 四組對照於各 Task 一致；Task 4 generated getter 名與 Task 2 `.dart` 引用、Task 3 arb key 三方對齊。

**中間狀態說明：** Task 2~5 完成前 `flutter analyze` 預期失敗（原子 rename 本質），首次完整驗證在 Task 6 — 此為 spec 做法 C 既定策略（編譯器 + 測試為安全網），非缺陷。
