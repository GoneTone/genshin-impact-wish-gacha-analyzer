# 手機滑動流暢度（子專案 8）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手機上綜合頁、卡池頁、頌願頁、橫向時間軸、五星一覽改成按需建構，保底卡呼吸動畫只在快保底時跑；外觀與互動不變（唯一例外是直向時間軸兩處對齊鳴潮）。

**Architecture:** 先把時間軸寫法對齊鳴潮（抽 `TimelineNode`、共用小工具），再照鳴潮子專案 8 的 commit 把頁面外層換成 `CustomScrollView` + slivers、有狀態區塊 keep-alive、時間軸 `ListView.builder`、五星一覽逐列建構；電腦版用 `pageScrollCacheExtent()` 整頁預建。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-20-mobile-scroll-smoothness-design.md`（必讀；4.1 是時間軸對齊，4.2 是移植，第五節是驗收）

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。
- 看改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`；看某時點的整檔：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit>:<路徑>`。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；鳴潮 `key` → 原神 `gachaType`；鳴潮圖片索引 `itemImageIndexProvider` → 原神 `hoyowikiIndexProvider`；「紀錄」→「記錄」；「喚取」→「祈願」。
- **移植改動，不整檔換成鳴潮版**（時間軸三檔例外，見 Task 2）。原神特有的保留：綜合頁「祈願／頌願」兩段（`_OverviewSection`）、HoYoWiki 圖示與 GIF、`gachaType` 命名、原神字串 key。
- 鳴潮的測試改寫到原神既有的測試 helper 上；既有斷言不可刪減。
- 不確定要不要偏離時回報 NEEDS_CONTEXT，不要自行改寫。

## Global Constraints

- 不新增依賴。不改 `android/`、manifest。
- 平台判斷：`pageScrollCacheExtent()` 用 `defaultTargetPlatform`（Windows／macOS／Linux → `const ScrollCacheExtent.pixels(100000)`，其他 → `null`），放 `lib/theme/layout.dart`。
- 頁面外層照鳴潮：`CustomScrollView(scrollCacheExtent: pageScrollCacheExtent(), slivers: [SliverPadding(sliver: SliverMainAxisGroup(slivers: [SliverList.list(...), ...]))])`，以鳴潮 `6ab24d1` 的 `overview_page.dart`／`banner_page.dart` 為準。
- 外觀只允許 Task 3 的兩處改動：直向時間軸圖例上方 `AppSpacing.m`（12）；`withLegend: widget.showLuckLegend && entries.isNotEmpty`。
- 不新增 log（純畫面結構）。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；中文全形標點、省略號半形 `...`。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。commit 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（Git Bash 裡 GPG 簽章會失敗，不可跳過簽章）。分支 `feat/android`，不開新分支、不 push。

## Review Focus

1. **頌願段捲出畫面再捲回**：綜合頁頌願段與頌願頁（`BannerPage`）的表格頁碼、搜尋文字、時間軸位置要保留，和祈願一樣 → Task 7 測試 `odes banner page keeps table page after scrolling out`（以頌願的 `BannerPage` 跑鳴潮 `9317776`／`819f3f4` 同款情境）。
2. **重構後時間軸畫面位移**：節點、月份標籤、年／月分隔線位置一像素都不能動 → Task 2 測試 `horizontal timeline geometry is unchanged by the refactor`、`vertical timeline geometry is unchanged by the refactor`（重構前先錄下數值）。
3. **Windows 視窗拉窄到手機寬度**：仍是電腦版，整頁預建，捲軸滑塊不跳 → Task 7 照搬鳴潮 `9d6be8c` 的測試，並加 `narrow desktop window still builds the whole overview`。
4. **頌願段沒有五星一覽**：逐列建構不能在頌願段多出空區塊或間距 → Task 7 測試 `odes section has no five-star overview rows`。
5. **進出快保底**：同一個 `PityCard` 收到新資料由 normal 變 close 再變回 normal，動畫要跟著啟停 → Task 4 照搬鳴潮 `fe269e9` 的第三個測試（`didUpdateWidget` 啟停）。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `lib/theme/tokens.dart`、`lib/utils/relative_time.dart`、`lib` 內 14 處 `FontFeature.tabularFigures()` | 共用小工具 | 1 |
| `lib/widgets/cards/timeline_node.dart`（新）、`timeline_horizontal.dart`、`timeline_vertical.dart` | 時間軸寫法對齊鳴潮 | 2、3、6 |
| `lib/widgets/cards/pity_card.dart` | 呼吸動畫啟停 | 4 |
| `timeline_vertical.dart`、`lib/widgets/data/search_filter_bar.dart`、`lib/widgets/data/sortable_table.dart`、`lib/widgets/share/share_action_button.dart` | keep-alive | 5 |
| `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`、`lib/theme/layout.dart`、`lib/widgets/cards/five_star_overview.dart`、`.gitattributes`、`tool/measure_frame_pacing.sh`（新） | 頁面按需建構、量測腳本 | 7 |
| spec 附錄 A／B | 落點與驗收 | 8 |

---

### Task 1: 共用小工具 `kTabularFigures`、`formatShortMonthDay`

**Files:**
- Modify: `lib/theme/tokens.dart`、`lib/utils/relative_time.dart`、`lib` 內所有 `const [FontFeature.tabularFigures()]` 的檔案（`grep -rn "FontFeature.tabularFigures" lib`，目前 14 處）
- Test: `test/utils/relative_time_test.dart`（沒有就新增）

**Interfaces:**
- Produces：`const List<FontFeature> kTabularFigures`（`lib/theme/tokens.dart`，照鳴潮定義與 dartdoc）；`String formatShortMonthDay(DateTime t)`（`lib/utils/relative_time.dart`，`DateFormat('MM/dd').format(t)`，照鳴潮）。

- [ ] **Step 1: 寫測試**：`formatShortMonthDay` → `formatShortMonthDay(DateTime(2026, 3, 7)) == '03/07'`、`formatShortMonthDay(DateTime(2026, 12, 25)) == '12/25'`。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/utils/relative_time_test.dart` → 編譯失敗（未定義）。
- [ ] **Step 3: 實作**：加兩個定義；14 處 `const [FontFeature.tabularFigures()]` 全換成 `kTabularFigures`（包含 `fontFeatures: const [...]` 的寫法，換完 `grep -rn "FontFeature.tabularFigures" lib` 只剩 `tokens.dart` 的定義）。時間軸裡的 `_formatShortDate` 留給 Task 2 換。
- [ ] **Step 4: 跑測試確認通過**：全套 `fvm flutter test` → `All tests passed!`。
- [ ] **Step 5: Commit**：`refactor: share tabular figures and short month-day formatting`

### Task 2: 時間軸寫法對齊鳴潮（外觀不變）

**Files:**
- Create: `lib/widgets/cards/timeline_node.dart`
- Modify: `lib/widgets/cards/timeline_horizontal.dart`、`lib/widgets/cards/timeline_vertical.dart`
- Test: `test/widgets/cards/timeline_horizontal_test.dart`、`test/widgets/cards/timeline_vertical_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `kTabularFigures`、`formatShortMonthDay`。
- Produces：`class TimelineNode extends StatelessWidget`（建構子與參數照鳴潮 `fe269e9~1:lib/widgets/cards/timeline_node.dart`，含 `hollow`）；兩個時間軸的公開建構子參數**不變**（呼叫端 `overview_page.dart`、`banner_page.dart`、`share_card.dart` 不用改）。

- [ ] **Step 1: 先錄外觀數值（在改程式之前）**：新增兩個測試，用既有測試的資料（含跨年、多月份、「現在」節點）pump 時間軸，用 `tester.getRect` 記下所有節點圓、月份／年份標籤、分隔線、名稱文字的 `Rect`，把數值寫死成期望值：`horizontal timeline geometry is unchanged by the refactor`、`vertical timeline geometry is unchanged by the refactor`。直向的測試資料要有節點（Task 3 會改「沒節點時的圖例」與「圖例間距」，這兩個測試要避開圖例區域，或圖例的 Rect 不列入）。
- [ ] **Step 2: 跑測試確認在原程式上通過**：`fvm flutter test test/widgets/cards/` → 全過（錄下的就是現況）。
- [ ] **Step 3: 實作**：新增 `timeline_node.dart`（鳴潮 `fe269e9~1` 版換套件名）；`timeline_horizontal.dart`、`timeline_vertical.dart` 以鳴潮 `fe269e9~1` 版為底改寫結構，保留原神特有部分（`gachaType`、HoYoWiki 圖示、原神字串 key、歐非色稀有度參數）。直向的圖例間距與 `withLegend` 條件**先維持原神現狀**（Task 3 才改）。
- [ ] **Step 4: 跑測試確認通過**：`fvm flutter test test/widgets/cards/` → 既有斷言與 Step 1 的數值斷言全過；全套也過。
- [ ] **Step 5: 差異清單**：三檔換掉套件名、忽略 CRLF 後和鳴潮 `fe269e9~1` 比對，把剩下的差異逐項列進報告，每項標明是哪一種原神特有部分（或 Task 3 待改的兩處）。
- [ ] **Step 6: Commit**：`refactor(timeline): share the node widget and align timeline structure with the sister app`

### Task 3: 直向時間軸兩處外觀照鳴潮

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Test: `test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 寫測試**：`luck legend sits 12px below the timeline`（圖例頂端與上方內容的距離 == `AppSpacing.m`）；`luck legend is hidden when there are no entries`（`entries: []`、`showLuckLegend: true` → 找不到圖例）；`luck legend shows when there are entries`。
- [ ] **Step 2: 跑測試確認失敗**：前兩個失敗。
- [ ] **Step 3: 實作**：`AppSpacing.s` → `AppSpacing.m`；`withLegend: widget.showLuckLegend && entries.isNotEmpty`（照鳴潮）。
- [ ] **Step 4: 跑測試確認通過**：全套 `fvm flutter test`；之後 `timeline_vertical.dart` 和鳴潮 `fe269e9~1` 的差異只剩 Task 2 清單的原神特有部分。
- [ ] **Step 5: Commit**：`style(timeline): match the sister app's legend spacing and hide it without entries`

### Task 4: 呼吸動畫只在快保底時跑

鳴潮版 commit：`fe269e9`、`40a6a98`。

**Files:**
- Modify: `lib/widgets/cards/pity_card.dart`
- Test: `test/widgets/cards/pity_card_test.dart`

- [ ] **Step 1: 寫測試**：照搬 `fe269e9` 的 `normal phase does not keep scheduling frames`、`close phase keeps the breath animation running`、進出快保底啟停的那一個、`reduce motion keeps close phase still`，以及 `40a6a98` 的 `turning on reduce motion stops a running animation`。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/widgets/cards/pity_card_test.dart` → normal 仍排程畫面的測試失敗。
- [ ] **Step 3: 實作**：照 `fe269e9` 改 `pity_card.dart`（`initState` 不再無條件 `repeat()`；依 phase 與減少動態啟停；`didUpdateWidget`、`didChangeDependencies` 跟著更新；呼吸動畫外層 `RepaintBoundary`）。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`fix(perf): run the pity breath animation only when close to pity`

### Task 5: 捲出畫面的有狀態區塊保持存活

鳴潮版 commit：`819f3f4`、`595ee0e`。

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`、`lib/widgets/data/search_filter_bar.dart`、`lib/widgets/data/sortable_table.dart`、`lib/widgets/share/share_action_button.dart`
- Test: `test/widgets/cards/timeline_vertical_test.dart`、`test/widgets/data/sortable_table_test.dart`、`test/widgets/share/share_action_button_test.dart`

- [ ] **Step 1: 寫測試**：照搬 `loaded count survives being scrolled out of a lazy list`（直向時間軸）、`page survives being scrolled out of a lazy list`（表格）、`busy state survives being scrolled out of a lazy list`（分享按鈕）。測試裡用 `ListView` 包住元件，捲出再捲回。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：四個 State 加 `AutomaticKeepAliveClientMixin`（`wantKeepAlive => true`，`build` 開頭 `super.build(context)`），照鳴潮。
- [ ] **Step 4: 跑測試確認通過**：全套。
- [ ] **Step 5: Commit**：`fix(perf): keep stateful sections alive when scrolled out of lazy lists`（分享按鈕可另一個 `fix(share): keep the share button busy while scrolled out of lazy pages`）

### Task 6: 橫向時間軸逐欄按需建構

鳴潮版 commit：`5907e54`、`e002813`。

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`
- Test: `test/widgets/cards/timeline_horizontal_test.dart`

**Interfaces:**
- Consumes：Task 2 對齊後的 `timeline_horizontal.dart` 結構。

- [ ] **Step 1: 寫測試**：照搬 `only builds the columns near the viewport`、`scroll offset survives being scrolled out of a lazy list`、`drag cursor only shows over columns, not empty space`、`nodes with an icon above stay on the axis line`（圖示換成原神的 HoYoWiki 物品圖示 widget）。
- [ ] **Step 2: 跑測試確認失敗**。先單獨看 `nodes with an icon above stay on the axis line` 在原程式上是否失敗：失敗代表原神也有同樣的錯位，報告記下；通過也照搬程式（spec 4.2）。
- [ ] **Step 3: 實作**：照 `5907e54` 改成橫向 `ListView.builder`（「現在」欄、月份分隔線、左右漸層、箭頭、捲動指示、滑鼠拖曳維持）；再套 `e002813`。
- [ ] **Step 4: 跑測試確認通過**：全套；Task 2 的 `horizontal timeline geometry is unchanged by the refactor` 仍要通過（若 `e002813` 修了原神真實存在的錯位，更新該測試的期望值並在報告說明）。
- [ ] **Step 5: Commit**：兩個 commit，`perf(timeline): build horizontal timeline columns lazily`、`fix(timeline): align icon column nodes with the axis and limit the drag cursor to columns`

### Task 7: 綜合頁、卡池頁、頌願頁按需建構與量測腳本

鳴潮版 commit：`7b33b11`、`70d206a`、`93e63b8`（只取 `tool/measure_frame_pacing.sh`）、`9d6be8c`、`9317776`、`0cb1fff`（腳本）、`6ab24d1`。

**Files:**
- Modify: `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`、`lib/theme/layout.dart`、`lib/widgets/cards/five_star_overview.dart`、`.gitattributes`
- Create: `tool/measure_frame_pacing.sh`
- Test: `test/pages/phone_layout_pages_test.dart`、`test/widgets/cards/five_star_overview_test.dart`

**Interfaces:**
- Produces：`ScrollCacheExtent? pageScrollCacheExtent()`（`lib/theme/layout.dart`）；`five_star_overview.dart` 照 `6ab24d1` 新增的逐列建構 API（名稱照鳴潮）。

- [ ] **Step 1: 寫測試**：照搬 `overview builds bottom sections only when scrolled near`、`banner page builds the record table only when scrolled near`、`overview keeps its three stat cards in one row on desktop`、`banner page keeps pity and total cards in one row on desktop`、`9d6be8c` 的兩個電腦版整頁預建測試與 `android tablets still build the overview on demand`、`9317776` 的五星區塊出現時狀態不重置、`6ab24d1` 的 `$name builds the five-star overview row by row`、`lays chips out exactly like the wrap version`、`scrolling does not rebuild rows already on screen`、`builds rows on demand`。加上 Review Focus 的 `odes banner page keeps table page after scrolling out`、`narrow desktop window still builds the whole overview`、`odes section has no five-star overview rows`；綜合頁「按需建構」的測試要同時檢查頌願段（祈願段在畫面外時、頌願段的區塊沒被建構）。
- [ ] **Step 2: 跑測試確認失敗**。
- [ ] **Step 3: 實作**：照 Global Constraints 的頁面外層寫法改兩個頁面（祈願、頌願兩段都換成 slivers；五星一覽逐列只在祈願段）；`layout.dart` 加 `pageScrollCacheExtent()`；`five_star_overview.dart` 照 `6ab24d1`；`9317776` 的 `banner_page.dart` 修正。
- [ ] **Step 4: 量測腳本**：`tool/measure_frame_pacing.sh` 以鳴潮 `0cb1fff` 版為準，套件名換成 `tw.reh.genshin.gacha`；`.gitattributes` 加 `*.sh text eol=lf`。不執行。
- [ ] **Step 5: 跑測試確認通過**：全套；`fvm flutter build windows --debug` 成功。
- [ ] **Step 6: Commit**：依鳴潮分成 `perf(pages): build overview and banner sections lazily`、`chore: keep shell scripts on LF so bash can run them on Windows checkouts`（含腳本，或腳本另一個 `chore(tool): add the frame pacing script`）、`fix(perf): build whole pages on desktop so the scrollbar thumb stays stable`、`fix(banner): keep search and table state when the five-star section appears`、`perf(five-star): build the five-star overview row by row`。

### Task 8: 實機驗收與附錄

**需要使用者在場**：手機要使用者明講「接好了／可以測」才能動；Windows 實體輸入要當次授權。

- [ ] **Step 1: 手機（ROG Phone，debug 版，直向與橫向）**：綜合頁（祈願、頌願兩段）、角色活動、武器活動、頌願頁上下捲動，外觀和改動前相同；紀錄表翻頁、搜尋、時間軸橫捲後捲出再捲回，狀態都在；有快保底的卡池呼吸動畫照常。測完依記憶「手機測完要真的還原」收尾。
- [ ] **Step 2: Windows（debug 版）**：同樣幾頁外觀不變；捲動時捲軸滑塊大小固定、不跳；直向時間軸的兩處改動（Task 3）符合預期。
- [ ] **Step 3: 附錄**：spec 附錄 A 記各鳴潮 commit 在原神的落點與偏離（含 Task 2 差異清單、Task 6 是否有錯位）；附錄 B 記驗收結果；註明流暢度實測留到子專案 9 之後。狀態行改為已完成。
- [ ] **Step 4: Commit**：`docs(spec): record the scroll smoothness port and device check`
