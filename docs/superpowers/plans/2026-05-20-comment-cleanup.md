# Comment Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 依新版註解規則清理 `lib/` 與 `test/` 既有註解、為所有宣告（含 private）補上 dartdoc，並啟用 `public_member_api_docs` lint 鎖住未來新增的 public 漏 dartdoc。

**Architecture:** 9 個 sequential commit。Task 1 commit 已修好的 `CLAUDE.md` / `AGENTS.md` 規則更新；Task 2~8 按模組分批清理（資料/狀態 → services → widgets base → cards/dialogs → share 渲染樹 → pages → test）；Task 9 加 `public_member_api_docs` lint + `test/analysis_options.yaml` 覆寫。

**Tech Stack:** Flutter, Dart, dart analyzer, `flutter_lints` package。

**Spec:** `docs/superpowers/specs/2026-05-20-comment-cleanup-design.md`（必讀，含完整判斷準則）。

---

## 共同判斷準則（每個清理 task 都套用）

執行 Task 2~8 任一個之前，先重讀 spec「判斷準則」整節。摘要：

### 保留
1. 既有 dartdoc 已說明 WHAT 的（哪怕一行）
2. 真正的 WHY 註解：invariant、race condition、跨檔對齊、workaround、會讓讀者意外的行為
3. dartdoc 的前置/後置條件 / API 契約
4. 結構/段落導引型 `//`（標出較長函式內的段落意圖）
5. 連續多行的視覺隱喻說明

### 移除
1. 檔頭路徑 banner（`// lib/foo/bar.dart`）— 若混入 WHY/HOW 內容，挪到對應 class/方法 dartdoc 再移除整段 banner
2. 純粹重述名稱的行內 `//`（壞例：`// 設定 controller` 對應 `_controller = ...`）
3. 重述名稱意義的 dartdoc（壞例：`/// uid。` 對應 `final String uid;`）
4. 語意空泛的測試樣板註解（`// arrange/act/assert`、`// given/when/then`、`// === xxx ===`）
5. 被註解掉的舊程式碼

### 補齊
- 所有宣告寫一行 dartdoc（top-level function、class、constructor、method、field、typedef、enum；含 private `_xxx`）
- 例外不補：Flutter override（`build`、`createState`、`dispose`、`initState`、`didChangeDependencies`、`reassemble`、`debugFillProperties`、`==`、`hashCode`、`toString`）

### 通用判準
> 拿掉這條註解後，讀者是否需要多花時間理解程式碼？需要 → 留；不需要 → 刪。

---

## Task 1: Commit 規則更新

**Files:**
- Modify: `CLAUDE.md`（已修，未 commit）
- Modify: `AGENTS.md`（已修，未 commit）

`CLAUDE.md` 與 `AGENTS.md` 已在 brainstorming 階段更新完畢，目前在 working tree。這個 task 只是把它們 commit。

- [ ] **Step 1: 確認兩檔已修但未 commit**

Run: `git status --short`
Expected:
```
 M AGENTS.md
 M CLAUDE.md
```

若沒有這兩行 → 規則檔已經 committed 或被 reset 了。先 `git log --oneline -5` 看看，沒看到「split comment rule」字樣再對照 spec「規則改寫」段重做。

- [ ] **Step 2: 看一下 diff 內容確認措辭**

Run: `git diff CLAUDE.md AGENTS.md`
Expected：每檔把第 9 行單條「不要隨意加註解」替換成兩條：「註解節制使用」+「方法應該有 dartdoc」。

- [ ] **Step 3: 跑品質檢查（純 markdown 改動，理論上不影響）**

```bash
flutter analyze
flutter test
```
Expected：`No issues found!` 與 `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "$(cat <<'EOF'
docs(rules): split comment rule; require dartdoc on declarations

把舊條目「不要隨意加註解」拆成兩條：
- 註解節制使用：列出可寫情境（WHY、結構/段落導引）與反例
- 方法應該有 dartdoc：所有宣告（含 private）一行 dartdoc，Flutter
  override 例外

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: 確認 commit 完成**

Run: `git log --oneline -1`
Expected：HEAD 訊息開頭為 `docs(rules): split comment rule`。

---

## Task 2: 清理 lib/ 資料/狀態/主題層

**Files:** 24 個檔（在 working tree 直接編輯）
```
lib/app_info.dart
lib/main.dart
lib/data/app_repo.dart
lib/data/contributors.dart
lib/data/gacha_types.dart
lib/data/team_info.dart
lib/models/accounts_bundle.dart
lib/models/banner_storage.dart
lib/models/gacha_record.dart
lib/models/share_image_options.dart
lib/utils/relative_time.dart
lib/theme/app_theme.dart
lib/theme/tokens.dart
lib/routing/app_router.dart
lib/state/app_release.dart
lib/state/clock_tick.dart
lib/state/gacha_capture.dart
lib/state/gacha_repository.dart
lib/state/localization_metadata.dart
lib/state/log_service.dart
lib/state/record_filter.dart
lib/state/settings.dart
lib/state/update_error.dart
lib/state/update_progress.dart
```

這批以資料模型、狀態 provider、theme tokens 為主，邏輯依賴最少、清理風險最低，先做。

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

對每個檔案：
1. 用 `Read` 工具讀完整內容。
2. 識別所有 `//` 與 `///` 註解，依保留/移除/補齊三類分類。
3. 用 `Edit` 工具改。

**典型操作範例**：

範例 A — 移除檔頭路徑 banner：
```dart
// lib/state/update_error.dart      ← 移除

/// 更新流程的錯誤類型，dialog 端用 i18n 解析顯示。
sealed class UpdateError {
```
變成：
```dart
/// 更新流程的錯誤類型，dialog 端用 i18n 解析顯示。
sealed class UpdateError {
```

範例 B — 補齊 private constructor：
```dart
class _Foo {
  _Foo(this.x);                       ← 缺 dartdoc
  final int x;                        ← 缺 dartdoc
}
```
變成：
```dart
/// 內部 helper，封裝 X 的快取狀態。
class _Foo {
  /// 建構並設定初始 x。
  _Foo(this.x);
  /// 目前的 X 值。
  final int x;
}
```

範例 C — 保留結構導引、移除純重述：
```dart
// 讀取設定                            ← 移除（下一行 _readSettings() 已自明）
final settings = await _readSettings();

// 計算每個 visible entry 是否為月份分組首 row     ← 保留（段落導引）
for (var i = 0; i < visible.length; i++) {
  // ... 二十行邏輯
}
```

範例 D — banner 內混 WHY/HOW 的搬遷：
原 `lib/services/share_image_renderer.dart:1-5` 是檔頭 banner 但混了「為何用獨立 RenderView」這個 WHY。改法：刪除整段 banner、把 WHY 搬到 class dartdoc：
```dart
/// 把任意 widget 以固定邏輯尺寸 + pixelRatio 同步離屏渲染成 PNG。
///
/// 用獨立 RenderView + BuildOwner pipeline，不依賴 live Navigator/Overlay，
/// 全程同步 flush（無動畫、無 async image），輸出穩定可測。
class ShareImageRenderer { ... }
```

**已知必留 invariant**（這些檔不在此批，列出方便認識「真 WHY」長相）：見 spec 保留 #2 列出的 6 個範例。

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```
（不要對 `.` 跑，會動到 `rust_builder/` vendored code，依 CLAUDE.md）

Expected: 列出 0 ~ 數個被 reformat 的檔。

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

若紅：
- `Unused import` → Edit 時誤刪了用到的型別 dartdoc 中的 import？回頭看
- 其他 → 對照變更看是不是邏輯被改到（不該發生，只動註解）

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

若紅：
- 先 `flutter test test/path/that/failed.dart`（單檔重跑）排 memory `project_flaky_parallel_test_suite.md` 提到的 flaky
- 若仍紅 → 表示某條被刪的註解原本是測試依賴的行為標記。revert 該檔的清理 + 把該註解升格成 dartdoc 後重跑。

- [ ] **Step 5: Commit**

```bash
git add lib/app_info.dart lib/main.dart lib/data lib/models lib/utils lib/theme lib/routing lib/state
git commit -m "$(cat <<'EOF'
chore(comments): clean lib data/state/theme per new comment rule

依 docs/superpowers/specs/2026-05-20-comment-cleanup-design.md
判斷準則處理：
- 移除檔頭路徑 banner、純重述名稱的行內 // 與 dartdoc
- 為所有宣告（含 private）補一行 dartdoc
- 保留 WHY 與結構/段落導引型 //

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 清理 lib/services/（不含 share render 相關）

**Files:** 19 個檔
```
lib/services/accounts_export.dart
lib/services/accounts_import.dart
lib/services/app_release_checker.dart
lib/services/cancellable_http_client.dart
lib/services/file_reveal.dart
lib/services/gacha_fetcher.dart
lib/services/gacha_filter.dart
lib/services/gacha_pity.dart
lib/services/gacha_row.dart
lib/services/gacha_stats.dart
lib/services/gacha_storage.dart
lib/services/gacha_url.dart
lib/services/log_sanitize.dart
lib/services/log_service.dart
lib/services/settings_storage.dart
lib/services/share_uid_mask.dart
lib/services/timeline_entries.dart
lib/services/uid_ordering.dart
lib/services/window_state_keeper.dart
```

**排除**（留到 Task 6）：`lib/services/overview_sections.dart`、`lib/services/share_image_export.dart`、`lib/services/share_image_renderer.dart`。

這批註解密度高、有真正的 invariant，**特別小心**。

**已知必留 invariant**（spec 保留 #2 範例，在 `lib/services/log_service.dart`）：
- L49-52 broadcast listener 不能拋例外
- L87-88 時間戳 UTC 對齊分檔基準
- L111-114 `r.time.toUtc()` 取年月日避免 rollover race
- L133-136 sink 取走立即新開避免 `StreamSink is bound to a stream`

Edit 這個檔時務必逐行核對這四段保留。

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

對 19 個檔依 Task 2 Step 1 同方法處理。`log_service.dart` 因註解密度最高，建議單獨先做、做完用 `git diff lib/services/log_service.dart` 看清楚再做其他檔。

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

若 `log_service_test.dart` / `app_release_checker_test.dart` 失敗，先單檔重跑（memory `project_flaky_parallel_test_suite.md`）。

- [ ] **Step 5: Commit**

```bash
git add lib/services
git commit -m "$(cat <<'EOF'
chore(comments): clean lib/services per new comment rule

依 spec 判斷準則處理 services/ 非 share-render 部分：
- 移除檔頭 banner、純重述行內 // 與 dartdoc
- 為宣告補 dartdoc
- 保留 log_service.dart 內 broadcast / UTC rollover / sink race
  等 invariant 註解

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 清理 lib/widgets/ 基礎元件（不含 cards/dialogs/share）

**Files:** 19 個檔
```
lib/widgets/app_link.dart
lib/widgets/banner_colors.dart
lib/widgets/banner_link.dart
lib/widgets/distribution_legend.dart
lib/widgets/empty_state.dart
lib/widgets/inline_section_title.dart
lib/widgets/item_type_pie.dart
lib/widgets/loading_state.dart
lib/widgets/page_header.dart
lib/widgets/rank_palette.dart
lib/widgets/rarity_pie.dart
lib/widgets/relative_time_text.dart
lib/widgets/team_links_bar.dart
lib/widgets/translator_text.dart
lib/widgets/uid_indicator.dart
lib/widgets/update_progress_dialog.dart
lib/widgets/data/pager.dart
lib/widgets/data/search_filter_bar.dart
lib/widgets/data/sortable_table.dart
```

**已知必留 invariant**（spec 保留 #2）：
- `lib/widgets/rarity_pie.dart:10-11` — `_kRingRadius=75 + _kCenterRadius=40 = 230px` 對齊 ChartCard 244px slot

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/app_link.dart lib/widgets/banner_colors.dart \
        lib/widgets/banner_link.dart lib/widgets/distribution_legend.dart \
        lib/widgets/empty_state.dart lib/widgets/inline_section_title.dart \
        lib/widgets/item_type_pie.dart lib/widgets/loading_state.dart \
        lib/widgets/page_header.dart lib/widgets/rank_palette.dart \
        lib/widgets/rarity_pie.dart lib/widgets/relative_time_text.dart \
        lib/widgets/team_links_bar.dart lib/widgets/translator_text.dart \
        lib/widgets/uid_indicator.dart lib/widgets/update_progress_dialog.dart \
        lib/widgets/data
git commit -m "$(cat <<'EOF'
chore(comments): clean lib/widgets base per new comment rule

依 spec 判斷準則處理 widgets/ 根目錄與 widgets/data/：
- 移除檔頭 banner、純重述行內 //
- 為宣告補 dartdoc
- 保留 rarity_pie.dart 內 230px 對齊 ChartCard slot 的 invariant

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 清理 lib/widgets/cards/ + lib/widgets/dialogs/

**Files:** 14 個檔
```
lib/widgets/cards/account_management.dart
lib/widgets/cards/banner_top_rarity_bars.dart
lib/widgets/cards/chart_card.dart
lib/widgets/cards/pity_card.dart
lib/widgets/cards/section_card.dart
lib/widgets/cards/stat_card.dart
lib/widgets/cards/timeline_horizontal.dart
lib/widgets/cards/timeline_vertical.dart
lib/widgets/dialogs/accounts_picker_dialog.dart
lib/widgets/dialogs/app_dialog.dart
lib/widgets/dialogs/confirm_dialog.dart
lib/widgets/dialogs/export_result_dialog.dart
lib/widgets/dialogs/new_version_dialog.dart
lib/widgets/dialogs/share_image_dialog.dart
```

**已知必留**（spec 保留 #3 #4 #5，集中在 `timeline_vertical.dart`）：
- L14-17 視覺隱喻說明（上→下 = 新→舊）
- L34-52 dartdoc 對 `title` / `footerNote` / `fillHeight` 的 API 契約與前置條件
- L72-75 dartdoc 對 `_visibleCount` 的 invariant
- L88、L93 段落導引 `//`
- L122-123、L147-152 dartdoc 對 fillHeight 分支的渲染後置條件
- L205、L223、L233、L324、L345、L358 段落導引 `//`

`timeline_vertical.dart` 是這批最敏感的檔，建議單獨先做、用 `git diff` 仔細核對保留條目。

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

對 `timeline_vertical_test.dart`、`timeline_horizontal_test.dart`、`account_management_test.dart`、`pity_card_test.dart` 失敗特別敏感（這些 widget 視覺/渲染依賴重）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards lib/widgets/dialogs
git commit -m "$(cat <<'EOF'
chore(comments): clean lib/widgets cards/dialogs per new comment rule

依 spec 判斷準則處理 widgets/cards/ 與 widgets/dialogs/：
- 移除檔頭 banner、純重述行內 //
- 為宣告補 dartdoc
- 保留 timeline_vertical.dart 視覺隱喻、API 契約、段落導引註解

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 清理 lib/widgets/share/ 與分享圖渲染檔

**Files:** 7 個檔
```
lib/services/overview_sections.dart
lib/services/share_image_export.dart
lib/services/share_image_renderer.dart
lib/widgets/share/left_driven_equal_height.dart
lib/widgets/share/share_action_button.dart
lib/widgets/share/share_card.dart
lib/widgets/share/share_image_helper.dart
```

這批是註解密度最高、彼此跨檔對齊（同步圖視覺）靠 invariant 註解最多的部分，**最謹慎**。

**已知必留**（spec 保留 #2 #3 #4）：
- `share_card.dart:32-43`、`45`、`61-67`、`83`、`135` 等 dartdoc 描述常數語意 / factory 行為
- `share_card.dart:96-97` WHY 註解（threshold=0 為何只取 averageInterval）
- `share_card.dart:148-149` `firstWhere` 為何不需 `orElse`
- `share_card.dart:359-363` dartdoc 對右欄 timeline 的後置條件
- `share_card.dart:390 / 411 / 416 / 454` 段落導引
- `share_image_renderer.dart:1-5` 檔頭 banner → 把 WHY/HOW 內容搬到 `ShareImageRenderer` class dartdoc 後刪掉 banner（範例參考共同準則「典型操作 D」）

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

`share_image_renderer.dart` 與 `share_card.dart` 內容多、跨檔依賴緊，建議用以下順序：
1. `overview_sections.dart`（簡單）
2. `share_action_button.dart`、`left_driven_equal_height.dart`、`share_image_helper.dart`
3. `share_image_export.dart`
4. `share_image_renderer.dart`（注意 banner 內 WHY 搬遷）
5. `share_card.dart`（最後，且最慢做）

每個改完用 `git diff <file>` 看一下再進下個。

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

對 `share_card_test.dart`、`share_render_tree_test.dart`、`share_image_renderer_test.dart`、`left_driven_equal_height_test.dart` 失敗特別敏感（這些是離屏渲染、跨檔 size 對齊的 test）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/overview_sections.dart \
        lib/services/share_image_export.dart \
        lib/services/share_image_renderer.dart \
        lib/widgets/share
git commit -m "$(cat <<'EOF'
chore(comments): clean lib share render tree per new comment rule

依 spec 判斷準則處理 share render 全套：
- widgets/share/ 4 檔 + services/share_image_* 2 檔
  + services/overview_sections.dart
- 移除檔頭 banner、純重述 //；保留跨檔 size 對齊與
  factory 後置條件 dartdoc
- share_image_renderer.dart banner 內 WHY 搬到 class dartdoc

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 清理 lib/pages/

**Files:** 5 個檔
```
lib/pages/app_shell.dart
lib/pages/banner_page.dart
lib/pages/contributors_page.dart
lib/pages/overview_page.dart
lib/pages/settings_page.dart
```

頂層頁面，依賴前 5 批已穩定的 widget/service。

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/pages
git commit -m "$(cat <<'EOF'
chore(comments): clean lib/pages per new comment rule

依 spec 判斷準則處理 pages/：
- 移除檔頭 banner、純重述行內 //
- 為宣告補 dartdoc
- 保留段落導引型 //

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 清理 test/

**Files:** 69 個檔（全部 `test/**/*.dart`）

主要處理對象：
- `// arrange / // act / // assert` 樣板
- `// given / // when / // then` 樣板
- 純重述名稱的 `//`
- 結構/段落導引型 `//`（保留，例：`// 多分頁切換` `// 第一次 build`）

**不需**為 test 檔的 helper / Mock / Fake class 補 public dartdoc — 這批 test/ 不 enforce `public_member_api_docs`（Task 9 會加 `test/analysis_options.yaml` 覆寫）。已有的 dartdoc 留著就好。

- [ ] **Step 1: 逐檔讀完整內容，套判斷準則做 Edit**

對註解密度高的優先：
- `test/state/gacha_repository_test.dart`（48 處 `//`）
- `test/widgets/cards/timeline_vertical_test.dart`（20 處）
- `test/widgets/cards/banner_top_rarity_bars_test.dart`（20 處）
- `test/widgets/share/share_card_test.dart`（19 處）
- `test/widgets/dialogs/accounts_picker_dialog_test.dart`（13 處）
- `test/services/gacha_pity_test.dart`（13 處）
- `test/services/timeline_entries_test.dart`（12 處）
- `test/widgets/share/share_render_tree_test.dart`（10 處）

其他每檔 1~8 處，依序處理。

- [ ] **Step 2: 跑 `dart format`**

```bash
dart format lib/ test/
```

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

對結構導引型 `//` 誤刪 → 通常不會炸測試（測試碼語意不變）；但若誤刪了某個 group / test 之間的分隔提示性 `//`，後續維護會痛苦。判準仍是「拿掉後讀者更難看懂測試結構？」需要 → 留。

- [ ] **Step 5: Commit**

```bash
git add test
git commit -m "$(cat <<'EOF'
chore(comments): clean test per new comment rule

依 spec 判斷準則處理 test/：
- 移除 // arrange/act/assert 樣板與其他純重述
- 保留段落導引、邏輯分支說明、跨檔依賴提示
- test/ 不 enforce public_member_api_docs（Task 9 設定）

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: 啟用 `public_member_api_docs` lint

**Files:**
- Modify: `analysis_options.yaml`
- Create: `test/analysis_options.yaml`

最後一步：在 lib/ 啟用 `public_member_api_docs`，test/ 用子目錄覆寫關掉。

- [ ] **Step 1: 修改根 `analysis_options.yaml`**

讀 `analysis_options.yaml` 確認當前內容。預期：
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    # Vendored 第三方 build tool (irondash/cargokit)，自帶獨立 pubspec.yaml
    # 並由 Flutter Rust Bridge 在 build time 自行 dart pub get；不應由
    # 主專案 analyzer 檢視。
    - rust_builder/**
```

用 `Edit` 在尾端加入 `linter` 區塊。完整目標內容：
```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    # Vendored 第三方 build tool (irondash/cargokit)，自帶獨立 pubspec.yaml
    # 並由 Flutter Rust Bridge 在 build time 自行 dart pub get；不應由
    # 主專案 analyzer 檢視。
    - rust_builder/**

linter:
  rules:
    - public_member_api_docs
```

注意：`linter:` 區塊是 top-level、與 `include:` / `analyzer:` 同層；不能放在 `analyzer:` 底下。

- [ ] **Step 2: 建立 `test/analysis_options.yaml`**

用 `Write` 工具建立檔案，內容：
```yaml
include: ../analysis_options.yaml
linter:
  rules:
    public_member_api_docs: false
```

`include` 用相對路徑指向專案根的 `analysis_options.yaml`，繼承所有設定後在 `linter.rules` map 形式關掉這條 rule。Dart analyzer 會自動對 `test/` 採用此覆寫。

- [ ] **Step 3: 跑 `flutter analyze`**

```bash
flutter analyze
```
Expected: `No issues found!`

若紅，會看到一連串 `public_member_api_docs` warning，例如：
```
warning - lib/foo.dart:12:7 - Missing documentation for a public member. - public_member_api_docs
```

對每條：
1. 開檔到該行
2. 補一行 dartdoc（依共同準則「補齊」段）
3. 重跑 `flutter analyze`

直到 `No issues found!`。**這些補漏不要 commit 進 Task 9**（保持 Task 9 commit 純粹「啟用 lint」），跑下一步前先 stash 沒做完的補漏。

- [ ] **Step 4: 跑 `flutter test`**

```bash
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 5: Commit lint 啟用**

```bash
git add analysis_options.yaml test/analysis_options.yaml
git commit -m "$(cat <<'EOF'
chore(lint): enable public_member_api_docs for lib/

- 根 analysis_options.yaml 加入 linter.rules: [public_member_api_docs]
- 新增 test/analysis_options.yaml include 根設定 + 覆寫關閉該 rule

依 spec 啟用 lint 鎖住「未來新增 public 宣告漏 dartdoc」入口；
test/ 不 enforce 是因為 helper / Mock / Fake 名稱多半已自明，
enforce 反而是雜訊。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: 若 Step 3 有補漏，再 commit fixup**

若 Step 3 期間有補 dartdoc：
```bash
git add lib
git commit -m "$(cat <<'EOF'
chore(comments): fixup missed public dartdocs

Task 9 啟用 public_member_api_docs 後，補上 Commits 2~7 期間
漏補的 public 宣告 dartdoc。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: 最終確認**

```bash
git log --oneline -10
flutter analyze
flutter test
```

Expected:
- `git log` 顯示 9（或 10 含 fixup）個新 commit，依序 Task 1 → Task 9。
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

---

## 回滾策略（如清理某批弄壞）

若 Task N 完成 commit 後發現問題：

1. **保留前批，回滾本批**：`git reset --hard HEAD~1` 把本批 commit 退掉，重做。
2. **若本批已合多 commit 或有 fixup**：個別檔 revert，`git checkout HEAD~N -- lib/path/to/file.dart` 取舊版，重做該檔。
3. **不要** `--no-verify` 跳 hooks；不要為了 commit 而 stub。

---

## 完成標準

- 9（或 10）個 commit 都進入 `flutter-rewrite` 分支
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`
- `dart format lib/ test/` → 0 reformat（已是 formatted state）
- `lib/` 無檔頭路徑 banner（`grep "^// lib/" lib/**/*.dart` 應該 0 結果，可跳過 generated）
- `public_member_api_docs` 已在 `analysis_options.yaml` 啟用
- `test/analysis_options.yaml` 已建立並關閉該 rule
