# 手機 UI/UX 調整（子專案 9）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把鳴潮版子專案 9 的手機 UI/UX 調整（外殼、數字卡、精簡圓餅、紀錄列表、跳頁、空資料提示、物品詳情、帳號管理、對話框 ✕、版面間距）移植到原神，含頌願頁與綜合頁頌願段，最後在實機量滑動流暢度。

**Architecture:** 依鳴潮 commit 的時間順序、按功能區分組移植，每組套到原神現有結構上（不整檔換成鳴潮版）；新檔以鳴潮該 commit 之後的版本為底。原神沒有鳴潮的 `distribution_ring_pie.dart`，先照鳴潮抽出共用圓餅（Task 4），再套精簡圓餅。側欄社群連結依 spec 4.1 改成兩行（唯一的版面偏離）。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、go_router、flutter_test、gen-l10n。

**Spec:** `docs/superpowers/specs/2026-11-20-mobile-ui-ux-adjustments-design.md`（必讀；第二節是 commit 範圍，第四節與 4.1 是原神特有部分，第五節是做法，第六節是驗收）。鳴潮 spec：`git -C ../wuthering-waves-convene-gacha-analyzer show 5afe5e3:docs/superpowers/specs/2026-11-07-mobile-ui-ux-adjustments-design.md`。示意圖：https://claude.ai/artifact/TeMxuPicwtkHjezNCM7nsL

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。
- 看改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`；看某時點的整檔：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit>:<路徑>`。移植前的鳴潮基準是 `f720f7b`，比對原神與鳴潮差異時用它。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；Android 套件 `tw.reh.genshin.gacha`；鳴潮 `key` → 原神 `gachaType`；`itemImageIndexProvider` → `hoyowikiIndexProvider`；「紀錄」→「記錄」；「喚取」→「祈願」；字串 key 以原神 ARB 現有的為準。
- 原神特有的一律保留（spec 第四節）：綜合頁「祈願／頌願」兩段（`_OverviewSection`）、頌願頁共用 `BannerPage`、4 個社群圖示加「原神資訊站 Genshin Impact Info」、HoYoWiki 詳情內容（描述、標籤、衣裝、圖片清單、GIF、「在 HoYoWiki 查看」）、原神卡池的保底與次保底規則。
- 鳴潮的測試改寫到原神既有的測試 helper 上；既有斷言不可刪減。
- 鳴潮的改法在原神行不通、或需要改變原神特有內容時，回報 NEEDS_CONTEXT，不要自行改寫（使用者原則：偏離姐妹專案前先問）。

## Global Constraints

- 不新增依賴。不改 `android/`、manifest、`rust/`、`rust_builder/`。
- 電腦版外殼、電腦版紀錄表、電腦版圓餅不變（spec 非目標）；只改單一平台時用既有判斷（`phoneOrientationOf`（Task 1 產出）、`isCompactLayout`）隔開。
- 子專案 8 不可退步：頁面外層 `CustomScrollView` + slivers、`pageScrollCacheExtent()`、`SliverFiveStarOverview` 逐列、keep-alive（時間軸、篩選列、表格、分享按鈕、橫向時間軸）。
- 新字串與改成 `{icon}` 的字串加在 9 份已翻譯 ARB：`app_zh.arb`、`app_zh_Hans.arb`、`app_en.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`；其他 ARB（空殼）不動。先寫 `app_zh.arb`，再以中文為準翻其他語言；鳴潮有同 key 的語言參考鳴潮 master 再換術語。CJK 全形標點，省略號一律半形 `...`。改完跑 `fvm flutter gen-l10n`。
- 新 dialog 一律 `AppDialog`。
- 照搬鳴潮新增的 log（英文、`Logger('xxx')` 命名對齊既有樹、不記敏感資料），不另外新增。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；註解中文全形標點。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。commit 英文 conventional commits（subject 沿用鳴潮對應 commit 的 subject；合併多個鳴潮 commit 時用第一個的 subject，body 列出其餘 commit 的 subject），結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（Git Bash 裡 GPG 簽章會失敗，不可跳過簽章）。分支 `feat/android`，不開新分支、不 push。

## Review Focus

1. **頌願也要套用**：頌願頁（`BannerPage`）與綜合頁頌願段的數字卡並排、精簡圓餅、紀錄列表一列篩選與橫向卡片，和祈願一樣 → Task 3、5、6 各加一個以頌願資料跑的測試（`odes …`）。
2. **側欄社群連結兩行**：ja／en、1.3 倍字級、360dp 寬的側欄裡，4 個圖示一行（每個點擊範圍 ≥ 48dp）、團隊名稱換行不溢出；手機直向與橫向的底部列都沒有社群連結 → Task 1 測試。
3. **有 GIF 與衣裝的物品詳情**：左右滑動切換到 GIF 頁、切換衣裝時衣裝說明跟著換、只有一張圖時沒有頁點也不拋錯 → Task 9、10 測試。
4. **原神卡池的數字卡排列**：武器活動祈願（保底 80）、集錄祈願、常駐祈願、沒有次保底的卡池「總抽數獨佔一列」依原神卡池實際判斷 → Task 3 測試逐一跑原神的卡池類型。
5. **較長的語系**：fr 加 1.3 倍字級、360dp 寬，兩欄數字卡、精簡圓餅圖例、篩選排序列、帳號列不溢出（spec 驗收的核心四語之外，fr 字串最長）→ Task 3、5、6、11 的溢出測試多跑一次 `fr`。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `lib/theme/layout.dart`、`lib/widgets/last_updated_label.dart`（新）、`lib/widgets/page_header.dart`、`lib/widgets/team_links_bar.dart`、`lib/pages/app_shell.dart` | 手機排版判斷、最後更新、底部列、側欄社群連結 | 1 |
| `lib/pages/app_shell.dart` | 橫向標題列捲動收起 | 2 |
| `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart` | 數字卡並排 | 3 |
| `lib/widgets/distribution_ring_pie.dart`（新）、`rarity_pie.dart`、`item_type_pie.dart` | 共用圓餅（對齊鳴潮結構） | 4 |
| `lib/widgets/cards/chart_card.dart`、`distribution_legend.dart`、圓餅三檔、`relative_time_text.dart`、兩個頁面 | 精簡圓餅與圖例 | 5 |
| `lib/pages/banner_page.dart`、`lib/widgets/data/search_filter_bar.dart`、`sortable_table.dart` | 紀錄列表 | 6 |
| `lib/widgets/data/jump_to_page_dialog.dart`（新）、`pager.dart` | 跳頁 | 7 |
| `lib/widgets/empty_state.dart` | 空資料提示 | 8 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`gallery_chip_bar.dart`、`lib/widgets/scroll/scroll_affordance.dart`、`app_dialog.dart` | 物品詳情 | 9、10 |
| `lib/widgets/cards/account_management.dart`、`lib/widgets/dialogs/edit_alias_dialog.dart`（新）、`lib/state/settings.dart` | 帳號管理 | 11 |
| `lib/widgets/cards/banner_top_rarity_bars.dart`、`timeline_horizontal.dart` | 綜合頁五星條、時間軸高度 | 12 |
| `lib/widgets/dialogs/app_dialog.dart` 與各 dialog、`CLAUDE.md` | 對話框 ✕ | 13 |
| `lib/widgets/width_layout_builder.dart`（新）、兩個頁面、`settings_page.dart`、`contributors_page.dart`、`log_access_setup_page.dart` | 版面一致與重建 | 14 |
| spec 附錄 A／B | 落點、驗收、流暢度 | 15、16 |

---

### Task 1: 手機排版判斷、最後更新元件、底部列與側欄社群連結

鳴潮版 commit：`cbc3ebc`、`a441f46`、`cf03cb4`、`864fdd2`、`2912431`（後兩個依 spec 4.1 改成兩行）。

**Files:**
- Create: `lib/widgets/last_updated_label.dart`
- Modify: `lib/theme/layout.dart`、`lib/widgets/page_header.dart`、`lib/widgets/team_links_bar.dart`、`lib/pages/app_shell.dart`、`lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`
- Test: `test/theme/layout_test.dart`、`test/pages/app_shell_test.dart`、`test/pages/phone_layout_pages_test.dart`、`test/widgets/page_header_test.dart`、`test/widgets/team_links_bar_test.dart`（沒有就新增）

**Interfaces:**
- Produces：`phoneOrientationOf(context)` 與相關型別（`lib/theme/layout.dart`，名稱與回傳型別照鳴潮 `cbc3ebc`）；`last_updated_label.dart` 的 `LastUpdatedLabel` 與 `a441f46` 抽出的共用 helper（名稱照鳴潮 `cf03cb4` 之後的版本）。
- Produces：`const TeamLinksBar({super.key, this.compact = false, this.stacked = false})`；`stacked: true` 時為兩行：第一行 4 個圖示用 `compact` 尺寸（`BoxConstraints(minWidth: 48, minHeight: 48)`），第二行團隊名稱連結（`TextAlign.center`、可換行），兩行各自置中，不畫分隔線。

- [ ] **Step 1: 寫測試**：照搬 `cbc3ebc`、`cf03cb4`、`864fdd2`、`2912431` 新增的測試（外殼、頁面、`layout_test`、`page_header_test`）。鳴潮斷言側欄是單行 `FittedBox` 的地方改成 4.1 的兩行：`drawer team links stack icons over the team name`（圖示列的底 ≤ 名稱的頂；4 個 `IconButton` 的 size 都 ≥ 48×48；兩行的水平中心與側欄可見內容的中心差 ≤ 1）；`drawer team links fit at 1.3x text in en and ja`（側欄寬 304、`TextScaler.linear(1.3)`，`tester.takeException()` 為 null，名稱沒有被縮放：找不到 `FittedBox` 包住 `TeamLinksBar`）；`phone bottom bar has no team links in portrait or landscape`；`desktop bottom bar keeps the one-row team links`。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/pages/app_shell_test.dart test/theme/layout_test.dart`。
- [ ] **Step 3: 實作**：依序套 `cbc3ebc`、`a441f46`、`cf03cb4`；側欄 footer 用 `TeamLinksBar(stacked: true)`，不用 `FittedBox`、不需要 `iconInset` 補償；`864fdd2`／`2912431` 的置中意圖用兩行各自置中實現。綜合頁頌願段與頌願頁同樣套用最後更新的位置。
- [ ] **Step 4: 跑測試確認通過**：全套 `fvm flutter test`。
- [ ] **Step 5: Commit**：`feat(shell): move phone footer links into the drawer and hide the footer in landscape`（`a441f46`、`cf03cb4` 可各自一個 commit）。

### Task 2: 手機橫向標題列捲動收起

鳴潮版 commit：`921b84f`、`a272afa`、`6da689a`、`3a38987`、`664ec71`，以及 `46d5a00` 中 `app_shell.dart` 的註解。

**Files:**
- Modify: `lib/pages/app_shell.dart`
- Test: `test/pages/app_shell_test.dart`

- [ ] **Step 1: 寫測試**：照搬五個 commit 新增的 `app_shell_test` 測試（含收起時旋轉成直向標題列立即出現、鍵盤開啟不溢出、手指離開時的回彈不切換、只在手機橫向監聽、收起的標題列不在語意樹與焦點樹、接近剛好放得下時不閃爍）。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：依時間順序套五個 commit。原神 `app_shell.dart` 與鳴潮 `f720f7b` 先比對差異，保留原神特有部分。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個 commit，subject 照鳴潮。

### Task 3: 數字卡兩欄並排

鳴潮版 commit：`6e8345e`。

**Files:**
- Modify: `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`
- Test: `test/pages/phone_layout_pages_test.dart`

- [ ] **Step 1: 寫測試**：照搬 `6e8345e` 的測試；加 Review Focus 1 的 `odes banner page pairs stat cards on phones`、`overview odes section pairs stat cards on phones`；Review Focus 4 的 `stat card rows follow each Genshin banner's pity rules`（角色活動、武器活動、常駐、集錄、頌願逐一跑，有次保底的兩欄並排，沒有次保底的總抽數獨佔一列）；Review Focus 5 的溢出測試加跑 `fr`。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照 `6e8345e`；「有沒有次保底」用原神既有的卡池判斷，不寫死鳴潮的卡池。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`feat(pages): pair secondary stat cards on phones`

### Task 4: 抽出共用圓餅 `DistributionRingPie`（外觀不變）

原神的 `rarity_pie.dart`、`item_type_pie.dart` 各自畫 `PieChart`，鳴潮在 `f720f7b` 已抽成 `distribution_ring_pie.dart`；先對齊結構，Task 5 才能照搬（**我的判斷**：spec「架構一致」與「不重複造輪子」）。

**Files:**
- Create: `lib/widgets/distribution_ring_pie.dart`
- Modify: `lib/widgets/rarity_pie.dart`、`lib/widgets/item_type_pie.dart`
- Test: `test/widgets/rarity_pie_test.dart`、`test/widgets/item_type_pie_test.dart`（沒有就新增）

**Interfaces:**
- Produces：`DistributionRingPie`（建構子與參數照鳴潮 `f720f7b:lib/widgets/distribution_ring_pie.dart`）。`RarityPie`、`ItemTypePie` 的公開建構子不變。

- [ ] **Step 1: 先錄外觀**：在改程式前新增 `rarity pie sections are unchanged by the refactor`、`item type pie sections are unchanged by the refactor`，記下 `PieChart` 的 `PieChartData`（各 section 的 value、color、radius、`centerSpaceRadius`、`sectionsSpace`）與圖例文字，寫死成期望值。
- [ ] **Step 2: 跑測試確認在原程式上通過**。
- [ ] **Step 3: 實作**：新增 `distribution_ring_pie.dart`（鳴潮 `f720f7b` 版換套件名），兩個圓餅改用它，原神特有的分類與顏色保留。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`refactor(charts): share the ring pie with the sister app`

### Task 5: 精簡圓餅卡與圖例

鳴潮版 commit：`b8606c8`、`3ea9927`、`2fa8f18`、`583f720`、`de6797d`、`0650ff2`（`banner_top_rarity_bars_test.dart` 的部分留給 Task 12）、`ef14f78`、`36f6663`、`e20b255` 與 `47d5585` 的測試部分（原神 CI 沒有字型預快取步驟，`ci.yml` 不改）。

**Files:**
- Modify: `lib/widgets/cards/chart_card.dart`、`lib/widgets/distribution_legend.dart`、`lib/widgets/distribution_ring_pie.dart`、`lib/widgets/rarity_pie.dart`、`lib/widgets/item_type_pie.dart`、`lib/widgets/relative_time_text.dart`、`lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`
- Test: `test/widgets/cards/chart_card_test.dart`、`test/widgets/distribution_legend_test.dart`、`test/pages/phone_layout_pages_test.dart`

- [ ] **Step 1: 寫測試**：照搬各 commit 新增的測試；`distribution_legend_test` 的 Roboto 載入用 `47d5585` 之後的版本（不分大小寫找檔名）。加 `odes banner page uses compact pie cards on phones`；圖例溢出測試加跑 `fr`；Task 4 的兩個外觀測試在電腦版寬度仍通過。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：依時間順序套用。`583f720` 中與 Task 5 範圍無關的部分（如 `relative_time_text.dart` 的 sentinel）一起帶。
- [ ] **Step 4: 跑測試確認通過**：全套；Windows 執行 `fvm flutter test test/widgets/distribution_legend_test.dart` 確認 Roboto 找得到。
- [ ] **Step 5: Commit**：`b8606c8` 一個，後續修正依鳴潮 subject 各一個或合併相鄰的。

### Task 6: 紀錄列表：篩選排序同列、橫向卡片、換頁捲回表頭

鳴潮版 commit：`dd63046`、`b8cd4a8`、`b32a24d`。

**Files:**
- Modify: `lib/pages/banner_page.dart`、`lib/widgets/data/search_filter_bar.dart`、`lib/widgets/data/sortable_table.dart`
- Test: `test/pages/phone_layout_pages_test.dart`、`test/widgets/data/search_filter_bar_test.dart`、`test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: 寫測試**：照搬三個 commit 的測試；加 `odes banner page uses one-row filters and landscape cards`；篩選列溢出測試加跑 `fr`。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照 `dd63046`、`b8cd4a8`；子專案 8 的 keep-alive 與按需建構結構保留（`b32a24d` 的測試鎖住）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：三個，subject 照鳴潮。

### Task 7: 跳頁對話框

鳴潮版 commit：`ba47d26`、`431a17b`。

**Files:**
- Create: `lib/widgets/data/jump_to_page_dialog.dart`
- Modify: `lib/widgets/data/pager.dart`、`lib/widgets/data/sortable_table.dart`、9 份 ARB
- Test: `test/widgets/data/jump_to_page_dialog_test.dart`、`test/widgets/data/pager_test.dart`、`test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: 寫測試**：照搬兩個 commit 的測試（含非法輸入 `12a`、`0`、超過總頁數、空白，「前往」不可按）。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：新檔以鳴潮 `431a17b` 版為底；新字串照 Global Constraints 加到 9 份 ARB。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`feat(pager): jump to a typed page instead of a long dropdown`（`431a17b` 併入或另一個）。

### Task 8: 空資料提示嵌入更新按鈕圖案

鳴潮版 commit：`b0aadad`，以及 `46d5a00` 中 `empty_state.dart` 的 marker escape。

**Files:**
- Modify: `lib/widgets/empty_state.dart`、9 份 ARB 的 `emptyNoSyncMessage`
- Test: `test/widgets/empty_state_test.dart`

- [ ] **Step 1: 寫測試**：照搬 `b0aadad` 的測試；加 `every translated locale has exactly one {icon} in the no-sync hint`（對 9 個 locale 各載入 `AppLocalizations`，渲染後圖案只出現一次、畫面上沒有字面的 `{icon}`）。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照 `b0aadad`、`46d5a00`；9 份 ARB 的 `emptyNoSyncMessage` 改成 `{icon}` 版本（中文以鳴潮 zh 為準換術語）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`feat(empty-state): point the no-sync hint at the actual update button`

### Task 9: 物品詳情：左右滑動、頁點

鳴潮版 commit：`020cdcf`、`11bff3b`、`b79d73b`、`a48fba6`。

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`lib/widgets/dialogs/gallery_chip_bar.dart`、`lib/widgets/scroll/scroll_affordance.dart`
- Test: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`、`test/widgets/dialogs/gallery_chip_bar_test.dart`

- [ ] **Step 1: 寫測試**：照搬四個 commit 的測試；加 Review Focus 3 的 `swiping onto a GIF page shows the GIF`、`switching skin updates the skin caption`、`single image has no page dots and swipes do nothing`。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：版面規則照鳴潮；圖片載入、快取、GIF 處理、衣裝內容維持原神現狀（spec 第四節）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個，subject 照鳴潮。

### Task 10: 物品詳情：雙欄、左欄單一捲動區與捲動提示

鳴潮版 commit：`653c8fb`、`6b6ca28`、`8c71ea5`、`ce78d54`。

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`lib/widgets/dialogs/app_dialog.dart`、`lib/widgets/scroll/scroll_affordance.dart`（`8c71ea5` 對 `timeline_horizontal.dart` 的改動留給 Task 12，因為它接在 `e8aa326` 之後）
- Test: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`、`test/widgets/dialogs/app_dialog_test.dart`

- [ ] **Step 1: 寫測試**：照搬四個 commit 的測試；`ce78d54` 的捲動提示在原神單欄只測簡介區塊（衣裝說明不加 96dp 上限，spec 第四節）；加 `two-column detail keeps HoYoWiki tags, skins and the HoYoWiki link`。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：依時間順序套用；原神已有的 `_twoColumnDetailsWidth`、`maxHeight: 120` 說明沿用，不重複新增。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個，subject 照鳴潮。

### Task 11: 帳號管理收成一列與 ⋮ 選單

鳴潮版 commit：`32bc415`、`24ade5f`、`adfaf9c`，以及 `46d5a00` 中別名的用字。

**Files:**
- Create: `lib/widgets/dialogs/edit_alias_dialog.dart`
- Modify: `lib/widgets/cards/account_management.dart`、`lib/state/settings.dart`、9 份 ARB
- Test: `test/widgets/cards/account_management_test.dart`、`test/state/settings_test.dart`

- [ ] **Step 1: 寫測試**：照搬三個 commit 的測試（含 360dp、1.3 倍字級的 en／ja）；加跑 `fr`。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照搬，`adfaf9c` 的 log 照鳴潮（UID 經 `sanitizeUid`）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個，subject 照鳴潮。

### Task 12: 綜合頁五星條與時間軸高度

鳴潮版 commit：`5b12ec8`、`0650ff2`（只有 `banner_top_rarity_bars_test.dart` 的部分，其餘在 Task 5）、`b345408`、`e8aa326`、`8c71ea5`（只有 `timeline_horizontal.dart` 的部分，其餘在 Task 10）、`a3881a1`，依這個順序套。

**Files:**
- Modify: `lib/widgets/cards/banner_top_rarity_bars.dart`、`lib/widgets/cards/timeline_horizontal.dart`、`lib/widgets/cards/chart_card.dart`、`lib/pages/banner_page.dart`
- Test: `test/widgets/cards/banner_top_rarity_bars_test.dart`、`test/widgets/cards/timeline_horizontal_test.dart`、`test/pages/phone_layout_pages_test.dart`

- [ ] **Step 1: 寫測試**：照搬四個 commit 的測試；子專案 8 的時間軸測試（逐欄建構、icon 節點對齊）必須仍通過。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：依時間順序套用；橫向時間軸保留 `ListView.builder` 逐欄建構。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個，subject 照鳴潮。

### Task 13: 對話框右上角 ✕ 與 CLAUDE.md

鳴潮版 commit：`46ce750`、`2b39464`、`1175c19`、`97edeb4`（只剩英文 `settingsLogsHint`）、`5afe5e3`。

**Files:**
- Modify: `lib/widgets/dialogs/app_dialog.dart`、`gacha_item_detail_dialog.dart`、`share_progress_dialog.dart`、`lib/widgets/update_progress_dialog.dart`（只加 `showCloseButton: false`，spec 第二節）、`lib/l10n/app_en.arb`、`CLAUDE.md`
- Test: `46ce750` 列出的各 dialog 測試、`test/widgets/data/pager_test.dart`

- [ ] **Step 1: 寫測試**：照搬 `46ce750`、`2b39464`、`1175c19` 的測試；原神有而鳴潮沒有的 dialog（用 `grep -rln "AppDialog(" lib` 列出）各確認一次 ✕ 存在或照鳴潮規則隱藏。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照搬；`settingsLogsHint` 英文改成 `export the logs`；CLAUDE.md「Dialog 一律用 `AppDialog`」那條照 `5afe5e3` 補 `xl` 與預設 ✕ 的說明（中文全形）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`46ce750`、`2b39464`、`1175c19` 各一個；`fix(l10n): use logs consistently for the debug log actions`；`docs: note AppDialog xl size and the default close button`。

### Task 14: 版面一致、只因高度改變不整頁重建、補測試

鳴潮版 commit：`5e9bb52`、`8a8bca7`（廣告測試不搬）、`fae12c7`、`3d64225`、`a5aafcf`、`4d4c640`。

**Files:**
- Create: `lib/widgets/width_layout_builder.dart`
- Modify: `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`、`lib/pages/settings_page.dart`、`lib/pages/contributors_page.dart`、`lib/pages/log_access_setup_page.dart`、`lib/theme/layout.dart`
- Test: `test/pages/phone_layout_pages_test.dart`，以及 `4d4c640` 列出的各測試檔

**Interfaces:**
- Produces：`WidthLayoutBuilder`（照鳴潮 `5e9bb52`）；`pagePaddingOf(context)`（`lib/theme/layout.dart`，手機 12dp、其他 16dp，照鳴潮 `3d64225`）。

- [ ] **Step 1: 寫測試**：照搬六個 commit 的測試；`overview odes section does not rebuild on height-only changes`；設定頁 About 列與其他遊戲連結的窄寬度測試（`525c173`、`32614d2`）仍通過。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：依時間順序套用；綜合頁祈願、頌願兩段都改用 `WidthLayoutBuilder`。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：每個鳴潮 commit 一個，subject 照鳴潮（`4d4c640` 的測試若已在前面 Task 帶過，剩下的部分一個 commit）。

### Task 15: 模擬器與 Windows 驗收、附錄 A

**主控執行。** Windows 實體輸入要使用者當次同意。

- [ ] **Step 1: 模擬器**：`wuwa_api37` 裝 x64 debug 版（`--target-platform android-x64`），切到朋友帳號，直向與橫向逐頁截圖，和示意圖比對：外殼與側欄兩行社群連結、數字卡、圓餅、紀錄列表與跳頁、空資料提示、物品詳情（含 GIF、衣裝）、帳號管理、對話框 ✕；橫向往下捲標題列收起、往上捲立即出現；頌願頁與綜合頁頌願段同樣檢查。測完還原轉向與字級。
- [ ] **Step 2: Windows**（debug 版）：外殼、紀錄表、圓餅不變；物品詳情雙欄、空資料提示按鈕圖案、帳號一列＋⋮、對話框 ✕。若切帳號，測完切回 801…。
- [ ] **Step 3: 附錄 A**：spec 附錄 A 記每個鳴潮 commit 在原神的落點與偏離（含 Task 4 的抽出、4.1 的兩行），附錄 B 先記 Step 1、2 的結果。
- [ ] **Step 4: Commit**：`docs(spec): record the mobile UI/UX port and emulator check`

### Task 16: 實機滑動流暢度

**主控執行。** 使用者明講「接好了／可以測」才動手機。

- [ ] **Step 1: 記下手機現況**：`cmd window user-rotation`、無障礙服務狀態、目前安裝的原神 App 版本。
- [ ] **Step 2: 量測**：`fvm flutter build apk --profile` 覆蓋安裝（保留資料），用 `tool/measure_frame_pacing.sh` 量綜合頁、角色活動、武器活動、頌願頁的慣性滑動準時率，直向與橫向各一次，並記錄靜止時是否出幀。目標 ≥ 95%。
- [ ] **Step 3: 還原**：裝回 debug 版、轉向隔 5 秒再查、snapshot helper 問使用者要不要移除。
- [ ] **Step 4: 附錄 B 與狀態**：記流暢度數據（有子專案 8 之前的數據就一起列），spec 狀態改為已完成。
- [ ] **Step 5: Commit**：`docs(spec): record the phone frame pacing after the UI/UX port`
