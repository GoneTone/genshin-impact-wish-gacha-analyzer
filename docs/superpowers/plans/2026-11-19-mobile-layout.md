# 手機版面（子專案 3）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手機（短邊 < 600dp）與窄電腦視窗（寬 < 600dp）切成手機排版（抽屜導覽、精簡標題列與狀態列、紀錄卡片列、12dp 對話框），看圖等元件適合觸控；寬螢幕行為完全不變。

**Architecture:** 照搬鳴潮版子專案 3 在 `87da1c1` 時的程式：`lib/theme/layout.dart` 集中判斷，各元件原地依它或自身 `LayoutBuilder` 寬度切換。不另寫手機頁面、不新增依賴。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、go_router、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-19-mobile-layout-design.md`（必讀；第二節是範圍，第六節列出原神版差異）

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）在 **commit `87da1c1`** 時的檔案，**不是** master（master 已含子專案 9 的改動，不能用）。
- 看最終檔案：`git -C ../wuthering-waves-convene-gacha-analyzer show 87da1c1:<路徑>`。
- 看某個 commit 的改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`。
- 改動前的鳴潮版（`3c4f985^`）和原神版現有檔案大多只差套件名與術語（`window_state_keeper.dart` 完全相同；`app_dialog`、`sortable_table`、`search_filter_bar`、`uid_indicator`、`scroll_affordance`、`gallery_chip_bar`、`relative_time_text`、`accounts_picker_dialog` 差不到 65 行），可直接把鳴潮版的 diff 套到原神版。
- 差異大的檔案（`gacha_item_detail_dialog.dart`、`zoomable_image_overlay.dart`、`timeline_vertical.dart`、`overview_page.dart`、`banner_page.dart`、`app_shell.dart`）：以原神版現有結構為底，把鳴潮版 diff 的**行為**做進去，不要整檔覆蓋。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；術語依 `docs/術語表.md`（喚取 → 祈願、喚取記錄 → 祈願紀錄）。
- 其餘（結構、常數、門檻、測試案例）逐字一致。鳴潮版的移植筆記以 `87da1c1` 版為準（`git show 87da1c1:docs/Android移植筆記.md` 第七節）；和程式不同時以程式為準。不確定要不要偏離時回報 NEEDS_CONTEXT，不要自行改寫。

## Global Constraints

- 範圍只到鳴潮版 `87da1c1`。子專案 9 的東西（`pagePaddingOf`、`phoneOrientationOf`、返回鍵回總覽 `b2da785`、社群連結移進抽屜、橫向不建底部列、標題列捲動收起、對話框 ✕、`_ScrollHintBox`）一律不做。
- 手機排版判斷只用 Task 1 的 `isCompactLayout`；Android／iOS 看 `shortestSide < 600`，其他平台看 `width < 600`。
- 48dp 觸控目標只在手機排版套用；寬螢幕外觀不變。
- 對話框一律 `AppDialog`；所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；中文全形標點，省略號半形 `...`；log 英文、沿用既有 Logger 名稱。
- 新字串只有 `tableSortButton`、`tableSortDefault`、`tableSortSheetTitle`，加在 9 份已翻譯 ARB（zh、zh_Hans、en、ja、es、fr、pt_BR、th、vi），22 份空殼不動；改完 `fvm flutter gen-l10n`。
- 不新增依賴；不動 `rust_builder/`。Windows 拖拉下限 360×450；預設／保底視窗尺寸維持 800×450。
- 測試尺寸：直向 360×800、橫向 800×360、桌面 1280×800。平台用 `TargetPlatformVariant.only(TargetPlatform.android)`（不要直接設 `debugDefaultTargetPlatformOverride` 再 `addTearDown`，會在測試結束的檢查失敗，筆記 #25）。overflow 以 `tester.takeException()` 為 null 判定。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。commit 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。分支 `feat/android`，不開新分支、不 push。

## Review Focus

1. **在頌願頁開抽屜**：抽屜要標示頌願項目選中，點祈願項目能切過去 → Task 3 測試 `drawer marks the current odes page`。
2. **原神長名稱＋英文或日文＋字級 1.3 的紀錄卡片**（例如「Mistsplitter Reforged」「流浪大地的樂章」）：不溢出、有省略號 → Task 4 測試 `cards do not overflow with long names and large text`。
3. **HoYoWiki 圖片還在載入或載入失敗時開物品詳情（手機橫向）**：兩欄版仍不溢出，右欄顯示載入中／失敗狀態 → Task 5 測試 `landscape two columns while the gallery loads or fails`。
4. **頌願頁在手機尺寸**（和祈願頁共用 `BannerPage`，卡池較少）→ Task 8 測試 `odes banner page fits a phone`。
5. **設定頁讀取方式區塊、手動輸入網址對話框在手機橫向開鍵盤**（子專案 2 新增、鳴潮版當時沒有對應測試）→ Task 8 測試 `manual url dialog with keyboard in landscape does not overflow`。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `lib/theme/layout.dart`（新） | `kCompactBreakpoint`、`isCompactLayout`、`tapTooltipTrigger`、`appActions` | 1 |
| `lib/services/window_state_keeper.dart`、`lib/main.dart`（改） | 360×450 下限；`MaterialApp.actions: appActions` | 1 |
| `lib/widgets/dialogs/app_dialog.dart`（改） | 手機 12dp 邊距 | 2 |
| `lib/pages/app_shell.dart`、`lib/widgets/team_links_bar.dart`、`lib/widgets/uid_indicator.dart`（改） | 抽屜、標題列、狀態列、返回鍵、安全區 | 3 |
| `lib/widgets/data/search_filter_bar.dart`、`lib/widgets/data/sortable_table.dart`、9 份 ARB（改） | 卡片列、排序選單 | 4 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart`（改） | 橫向兩欄 | 5 |
| `lib/widgets/dialogs/zoomable_image_overlay.dart`（改） | 觸控手勢 | 6 |
| `scroll_affordance.dart`、`gallery_chip_bar.dart`、`timeline_vertical.dart`、`relative_time_text.dart`、`account_management.dart`、`accounts_picker_dialog.dart`（改） | 觸控目標與提示 | 7 |
| `overview_page.dart`、`banner_page.dart`、`banner_top_rarity_bars.dart`（改）、巡檢中溢出的頁面 | 各頁面手機尺寸 | 8 |

---

### Task 1: 手機排版判斷、視窗下限、點外部收焦點

鳴潮版 commit：`3c4f985`、`1da0866`、`85924d6`（只取 `layout.dart`）、`bf128f5`（只取 `window_state_keeper.dart`）。

**Files:**
- Create: `lib/theme/layout.dart`、`test/theme/layout_test.dart`
- Modify: `lib/services/window_state_keeper.dart`、`lib/main.dart`、`test/services/window_state_keeper_test.dart`

**Interfaces:**
- Produces（後續所有 Task 使用，名稱與簽名照 `87da1c1:lib/theme/layout.dart`）：
  - `const double kCompactBreakpoint = 600;`
  - `bool isCompactLayout(BuildContext context)`
  - `TooltipTriggerMode? tapTooltipTrigger(BuildContext context)`：手機排版回傳 `TooltipTriggerMode.tap`，否則 `null`。
  - `appActions`：覆寫 `EditableTextTapOutsideIntent` 讓任何裝置點外部都收焦點，由 `main.dart` 的 `MaterialApp.actions` 使用。
  - `window_state_keeper.dart`：`@visibleForTesting const Size kMinWindowSize = Size(360, 450)`，保底尺寸另一個常數維持 800×450。

- [ ] **Step 1: 寫失敗的測試**：照搬 `87da1c1:test/theme/layout_test.dart`（平台×尺寸表：Android 360×800／800×360 為 true、1280×800／600×1000 為 false；Windows 1093×560／600×450／1280×800 為 false、500×900 為 true；`tapTooltipTrigger` 與點外部收焦點的案例），以及 `window_state_keeper_test.dart` 的 `kMinWindowSize == Size(360, 450)`。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/theme/layout_test.dart test/services/window_state_keeper_test.dart`，預期編譯失敗（找不到 `layout.dart`）。
- [ ] **Step 3: 實作**：照搬三個檔案的鳴潮版改法。
- [ ] **Step 4: 跑測試確認通過**（同上指令），既有的 800×450 保底與 clamp 測試仍通過。
- [ ] **Step 5: Commit** `feat(layout): add a shared compact layout check and allow narrow windows`

---

### Task 2: `AppDialog` 手機邊距

鳴潮版 commit：`b55bc8c`、`9b0ab0b`（只取 `app_dialog.dart`）。

**Files:**
- Modify: `lib/widgets/dialogs/app_dialog.dart`、`test/widgets/dialogs/app_dialog_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`。
- Produces: 手機排版四周 12dp（360×800 下 `md` 寬 336；800×360 下高上限 336）；寬螢幕維持 40／120。`9b0ab0b` 對 `AppDialog` 加的參數（給物品詳情兩欄版用）一併照搬，Task 5 會用。

- [ ] **Step 1: 寫失敗的測試**：照搬 `87da1c1:test/widgets/dialogs/app_dialog_test.dart` 新增的案例（手機寬 336、手機高 336、桌面不變、長按鈕換行）。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/dialogs/app_dialog_test.dart`，手機寬度目前是 280。
- [ ] **Step 3: 實作**：照搬鳴潮版改法。
- [ ] **Step 4: 確認通過**，並跑 `fvm flutter test test/widgets/dialogs/`。
- [ ] **Step 5: Commit** `feat(layout): give dialogs 12dp margins on phones`

---

### Task 3: 外殼：抽屜、標題列、狀態列、返回鍵、安全區

鳴潮版 commit：`621969d`、`3a60a42`、`755dfbb`、`9f0772b`、`87da1c1`。

**Files:**
- Modify: `lib/pages/app_shell.dart`、`lib/widgets/team_links_bar.dart`、`lib/widgets/uid_indicator.dart`
- Create: `test/pages/app_shell_test.dart`
- Modify: `test/widgets/team_links_bar_test.dart`、`test/widgets/uid_indicator_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`。
- Produces: 照 `87da1c1` 的 `TeamLinksBar`（`compact` 參數）、`AccountTriggerLabel` 可縮、帳號選單寬度（至少按鈕寬、最多 336）、`AppShell` 手機排版用 `Scaffold.drawer`。

**原神版差異：**
- 抽屜照原神版 rail：總覽、`navSectionGacha`（gacha 分類）、`navSectionOdes`（odes 分類）、貢獻者、設定；選中狀態沿用 `_resolveRailSelection` 的 `gachaIndex`／`odesIndex`。路由是 `/banner/${gachaType}`。
- 原神版 `TeamLinksBar` 比鳴潮版多一個連結（多 13 行），`compact` 時一樣只顯示圖示、每個 48dp。
- 返回鍵只做 `PopScope(canPop: !(compact && _drawerOpen))`（關抽屜），**不做**回總覽。

- [ ] **Step 1: 寫失敗的測試**：照搬 `87da1c1:test/pages/app_shell_test.dart` 全部案例（抽屜取代 rail、項目 ≥ 48dp、點項目切頁並關抽屜、橫向也用抽屜、桌面保留 rail 與版本號、抽屜頂部有 App 名稱與版本、短抽屜時底部項目跟著捲、更新圖示按鈕、狀態列只剩圖示、抽屜開著按返回關抽屜、鍵盤開著隱藏狀態列、視窗拉寬再縮回抽屜不會自己開著、轉向不丟例外、安全區），把 12 個卡池換成原神版的 gacha／odes 清單。另加原神版案例：
  - `drawer marks the current odes page`：從頌願頁（`/banner/<第一個 odes 的 gachaType>`）開抽屜，該項目為選中；點第一個 gacha 項目後顯示對應頁、抽屜關閉。
  - `team_links_bar_test`、`uid_indicator_test` 照搬鳴潮版新增案例。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/pages/app_shell_test.dart test/widgets/team_links_bar_test.dart test/widgets/uid_indicator_test.dart`。
- [ ] **Step 3: 實作**：依五個 commit 的順序把行為做進原神版 `app_shell.dart`。
- [ ] **Step 4: 確認通過**，並跑 `fvm flutter test test/pages/ test/widgets/`。
- [ ] **Step 5: Commit** `feat(layout): navigate with a drawer and slim the app bar on phones`

---

### Task 4: 紀錄卡片列、排序選單、窄篩選列

鳴潮版 commit：`ac5c506`、`5655c96`、`2c86fa0`、`32fe567`。

**Files:**
- Modify: `lib/widgets/data/search_filter_bar.dart`、`lib/widgets/data/sortable_table.dart`、9 份 ARB
- Modify: `test/widgets/data/search_filter_bar_test.dart`、`test/widgets/data/sortable_table_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`、既有 `cycleSort`（`onSortColumnTapped`）。
- Produces: `SortableTable` 可用寬度 < 600 時畫排序按鈕＋`_RecordCard` 列表（照 `87da1c1`：卡片顯示類型、第二行單一 `Text.rich` 加省略號、保底數說明、排序選單 `useRootNavigator: true`），公開 API 不變。

**ARB（`app_en.arb` 的 `@` 描述照搬鳴潮版）：**

| 語系 | `tableSortButton` | `tableSortDefault` | `tableSortSheetTitle` |
|---|---|---|---|
| zh | `排序：{column}` | `排序：預設` | `排序方式` |
| zh_Hans | `排序：{column}` | `排序：默认` | `排序方式` |
| en | `Sort: {column}` | `Sort: default` | `Sort by` |
| ja | `並べ替え：{column}` | `並べ替え：既定` | `並べ替え` |
| es | `Ordenar: {column}` | `Ordenar: predeterminado` | `Ordenar por` |
| fr | `Tri : {column}` | `Tri : par défaut` | `Trier par` |
| pt_BR | `Ordenar: {column}` | `Ordenar: padrão` | `Ordenar por` |
| th | `เรียง: {column}` | `เรียง: ค่าเริ่มต้น` | `เรียงตาม` |
| vi | `Sắp xếp: {column}` | `Sắp xếp: mặc định` | `Sắp xếp theo` |

（取自鳴潮版 master 上同名 key 的現行譯文。）

- [ ] **Step 1: 寫失敗的測試**：照搬 `87da1c1` 兩個測試檔新增的案例（窄寬度卡片、寬度保留表格、排序選單呼叫 `cycleSort`、按鈕顯示欄位與方向、卡片可開詳情、卡片顯示類型、選單蓋在最上層、保底說明、卡片／表格切換保留頁碼、搜尋欄窄寬度佔滿一行）。另加：
  - `cards do not overflow with long names and large text`：`en` 與 `ja` 各一次，`textScaleFactorTestValue = 1.3`、寬 360，名稱用 `Mistsplitter Reforged`，`takeException()` 為 null，名稱 `Text` 的 `overflow == TextOverflow.ellipsis`。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/data/`。
- [ ] **Step 3: 實作**；改 ARB 後 `fvm flutter gen-l10n`。
- [ ] **Step 4: 確認通過**（同上指令）。
- [ ] **Step 5: Commit** `feat(layout): show records as cards with a sort sheet on phones`

---

### Task 5: 物品詳情橫向兩欄

鳴潮版 commit：`9b0ab0b`、`7fb31d1`（只取 `gacha_item_detail_dialog.dart`）。

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`、Task 2 的 `AppDialog` 參數。
- Produces: 對話框高度不夠時（門檻照鳴潮版）改左右兩欄：左欄圖示＋名稱、簡介、標籤、按鈕；右欄 `GalleryChipBar`＋圖片。直向與寬螢幕維持原神版現有結構。

**原神版差異：**沒有 `_buildSkinCaption`，`7fb31d1` 中搬移造型說明的部分不適用，只取「讓右欄圖片維持高度」的部分。原神版的 `_GalleryLoading`／`_GalleryReady`／`_GalleryFailed` 三種狀態都要在右欄正常顯示。

- [ ] **Step 1: 寫失敗的測試**：照搬鳴潮版兩個 commit 新增的案例（橫向左右並排、直向上下堆疊、橫向圖片高度不小於約 200dp），換成原神版既有的 pump 與 fixture。另加：
  - `landscape two columns while the gallery loads or fails`：800×360，圖庫分別停在載入中與失敗，`takeException()` 為 null，名稱在左欄、載入中指示或失敗訊息在右欄。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart`。
- [ ] **Step 3: 實作**。
- [ ] **Step 4: 確認通過**（同上指令）。
- [ ] **Step 5: Commit** `feat(layout): lay out item details in two columns on landscape phones`

---

### Task 6: 看圖元件觸控化

鳴潮版 commit：`1f404df`、`7fb31d1`（只取 `zoomable_image_overlay.dart`）、`ca2eee5`。

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`、`test/widgets/dialogs/zoomable_image_overlay_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`。
- Produces（行為，照 `87da1c1`）：雙指縮放（範圍沿用原神版既有最小／最大倍率）、`InteractiveViewer.scaleFactor: double.infinity`、觸控點兩下切換 1↔2 倍、觸控點一下無反應、滑鼠單擊立即縮放（依 `PointerDeviceKind` 分流）、長按（`supportedDevices` 只有觸控與觸控筆）開右鍵選單、未放大時往下滑關閉、手機排版外距 8、轉向重設縮放、在安全區內。

**原神版差異：**原神版這個檔比鳴潮版改動前短約 60 行，兩邊的選單項目與 log 不同。保留原神版既有選單與 log 名稱，只加上述行為。

- [ ] **Step 1: 寫失敗的測試**：照搬鳴潮版三個 commit 新增與修改的案例（雙指縮放、觸控單擊無反應、觸控點兩下、滑鼠單擊立即縮放、滑鼠長按不開選單、觸控長按開選單、往下滑關閉、放大時往下拖是平移、轉向重設、手機外距 8、安全區），選單文字換成原神版的 key。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`。
- [ ] **Step 3: 實作**。
- [ ] **Step 4: 確認通過**，既有的滾輪、右鍵、ESC 測試仍通過。
- [ ] **Step 5: Commit** `feat(layout): make the image viewer touch friendly`

---

### Task 7: 小元件的觸控目標與提示

鳴潮版 commit：`a68c896`、`a739f50`、`85924d6`（不含 `layout.dart`）、`bf128f5`（只取 `account_management.dart`）。

**Files:**
- Modify: `lib/widgets/scroll/scroll_affordance.dart`、`lib/widgets/dialogs/gallery_chip_bar.dart`、`lib/widgets/cards/timeline_vertical.dart`、`lib/widgets/relative_time_text.dart`、`lib/widgets/cards/account_management.dart`、`lib/widgets/dialogs/accounts_picker_dialog.dart`
- Test: `test/widgets/scroll/scroll_affordance_test.dart`、`test/widgets/dialogs/gallery_chip_bar_test.dart`、`test/widgets/cards/timeline_vertical_test.dart`、`test/widgets/cards/timeline_horizontal_test.dart`、`test/widgets/cards/five_star_overview_test.dart`、`test/widgets/cards/account_management_test.dart`、`test/widgets/dialogs/accounts_picker_dialog_test.dart`、Create `test/widgets/relative_time_text_test.dart`

**Interfaces:**
- Consumes: `isCompactLayout`、`tapTooltipTrigger`。
- Produces: 捲動箭頭手機 48dp；相對時間、垂直時間軸節點與日期在手機點一下顯示提示；帳號拖曳把手 48dp；帳號挑選對話框副標題可換行。

- [ ] **Step 1: 寫失敗的測試**：照搬鳴潮版四個 commit 在上列測試檔新增的案例。`timeline_horizontal_test.dart` 與 `timeline_vertical_test.dart` 兩邊差異大，案例要對著原神版的 fixture 改寫，斷言照鳴潮版。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/`。已經通過的案例（例如水平捲動本來就能用手指拖）照樣保留，不改程式。
- [ ] **Step 3: 實作**。
- [ ] **Step 4: 確認通過**（同上指令）。
- [ ] **Step 5: Commit** `feat(layout): touch targets and hints for small widgets on phones`

---

### Task 8: 各頁面在手機尺寸不溢出

鳴潮版 commit：`b04d531`。

**Files:**
- Modify: `lib/pages/overview_page.dart`、`lib/pages/banner_page.dart`、`lib/widgets/cards/banner_top_rarity_bars.dart`、`lib/widgets/cards/account_management.dart`，以及巡檢中溢出的頁面與元件
- Create: `test/pages/phone_layout_pages_test.dart`

**Interfaces:**
- Consumes: Task 1–7 的成果。

- [ ] **Step 1: 寫失敗的測試**：照搬 `87da1c1:test/pages/phone_layout_pages_test.dart`（總覽、卡池、設定、貢獻者在 360×800 與 800×360 捲到底都不溢出；手機頁面外距；開鍵盤的卡池頁），fake repository 換成原神版。另加原神版案例：
  - `odes banner page fits a phone`：頌願頁直向與橫向捲到底不溢出。
  - `log access setup page fits a phone`：`LogAccessSetupPage` 直向與橫向捲到底不溢出（pump 方式參考 `test/pages/settings_page_log_access_test.dart`）。
  - `settings page with the log access section fits a phone`：`isAndroidProvider` 覆寫為 true。
  - `manual url dialog with keyboard in landscape does not overflow`：800×360、`tester.view.viewInsets = FakeViewPadding(bottom: 180)`，用 `showManualUrlDialog(context)` 開啟。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/pages/phone_layout_pages_test.dart`。
- [ ] **Step 3: 實作**：照搬 `b04d531` 的改法，再逐一修掉測試抓到的溢出（橫排放不下改 `Wrap`）。
- [ ] **Step 4: 確認通過**，並跑完整 `fvm flutter test`。
- [ ] **Step 5: Commit** `feat(layout): fit every page on phone screens`

---

### Task 9: 實機與 Windows 驗收

**Files:**
- Modify: `docs/superpowers/specs/2026-11-19-mobile-layout-design.md`（新增附錄 B「實機驗收與實作坑」，比照子專案 2 的附錄寫法）

- [ ] **Step 1: 實機**（ASUS ROG Phone 9，`fvm flutter build apk --debug` 後 `adb install -r`；轉向用 `adb shell cmd window user-rotation lock 1`，測完 `user-rotation free` 並把 `accelerometer_rotation` 改回 1）：直向、橫向逐頁檢查總覽、各祈願頁與頌願頁（含空池）、紀錄卡片與排序選單、物品詳情（直向、橫向兩欄）、看圖（雙指、點兩下、長按、往下滑、轉向）、設定（含讀取方式區塊）、貢獻者、讀取方式設定頁、手動輸入、更新進度對話框；抽屜開著轉向與按返回；鍵盤開著搜尋。發現問題回到對應 Task 用 TDD 修正。
- [ ] **Step 2: Windows**：`fvm flutter run -d windows`，視窗寬度拉到 600 以下切成抽屜、精簡標題列、紀錄卡片；拉回恢復 rail；寬而矮的視窗維持 rail；抽屜開著拉寬再縮回不會自己開著；滑鼠單擊看圖仍立即縮放、滑鼠長按不開選單。
- [ ] **Step 3: 寫附錄 B 並 commit** `docs(spec): record the phone layout device check`
