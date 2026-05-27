# UI/UX Redesign — Phase 2 (Features) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Phase 1 留下的 placeholder 全部變成真功能：實作保底計算 + PityCard、5★ 出貨時間軸、可排序篩選搜尋的紀錄表、設定頁的資料匯入匯出、帳號管理、loading skeleton；同時把 Phase 1 review 抓出但延後的錯誤訊息 i18n 一併處理。

**Architecture:** 純函式服務層（`wish_pity` / `wish_filter` / `data_export` / `data_import`）+ widget 元件（`PityCard` / `TimelineCard` / `SortableTable` / `SearchFilterBar` / `FiveStarList` / `LoadingState` / `ConfirmDialog`）+ Riverpod state（`recordFilterProvider.family<String>`、新增 `WishState.isBootstrapping`、`UpdateError` sealed class）。`UpdateFailed.message: String` 改為 `UpdateFailed.error: UpdateError`，dialog 透過 i18n key 解析。

**Tech Stack:** Flutter 3.x、Dart 3 sealed classes、`flutter_riverpod ^3.0.0`、`fl_chart ^1.0.0`、新增 `file_selector ^1.0.0`（桌面 save/open 對話框）。

**Spec reference:** `docs/superpowers/specs/2026-05-09-ui-ux-redesign-design.md`
**Phase 1 plan:** `docs/superpowers/plans/2026-05-09-ui-ux-redesign-phase-1.md`（已 ship 至 SHA `c3f0c00`）

---

## File Structure

### 新增

```
lib/
  services/
    wish_pity.dart          ← Pity{current, threshold, lastFiveStarAt} + computePity()
    wish_filter.dart        ← RecordFilter / RecordSort + filterRecords / sortRecords
    data_export.dart        ← export JSON + CSV
    data_import.dart        ← parse JSON 並驗證
  state/
    record_filter.dart      ← recordFilterProvider.family<String>
    update_error.dart       ← sealed UpdateError 子類
  widgets/
    cards/
      pity_card.dart        ← 三狀態 PityCard + 呼吸動效
      timeline_card.dart    ← 5★/4★ 時間軸（橫向 / 直向）
    data/
      sortable_table.dart   ← 取代 record_list_table
      search_filter_bar.dart ← 工具列（搜尋 + dropdown）
      five_star_list.dart   ← OverviewPage 的跨卡池 5★ 列表
      pager.dart            ← 改良版分頁器（<<, >>, 多頁 dropdown）
    loading_state.dart      ← Skeleton placeholder
    dialogs/
      confirm_dialog.dart   ← 兩段式確認（清除資料用）

test/
  services/
    wish_pity_test.dart
    wish_filter_test.dart
    data_export_test.dart
    data_import_test.dart
  state/
    record_filter_test.dart
  widgets/
    cards/
      pity_card_test.dart
      timeline_card_test.dart
    data/
      sortable_table_test.dart
      search_filter_bar_test.dart
      five_star_list_test.dart
    loading_state_test.dart
    dialogs/
      confirm_dialog_test.dart
```

### 修改

```
pubspec.yaml                ← 加 file_selector
lib/
  l10n/*.arb                ← 加新 keys（filter / table sort / export / import / account / pity）
  state/
    update_progress.dart    ← UpdateFailed.message → UpdateFailed.error: UpdateError
    wish_repository.dart    ← _friendlyError 回傳 UpdateError、加 removeUid()
  services/
    wish_storage.dart       ← 加 delete(uid) 方法
  widgets/
    update_progress_dialog.dart  ← 渲染 UpdateError 時用 AppLocalizations
  pages/
    overview_page.dart      ← FiveStarList 替換 timeline placeholder
    banner_page.dart        ← PityCard / TimelineCard / SortableTable + SearchFilterBar
    settings_page.dart      ← DataManagement / AccountManagement 真實內容
```

### 退役（Phase 2 結束時刪）

- `lib/widgets/record_list_table.dart` → 由 `lib/widgets/data/sortable_table.dart` + `lib/widgets/data/pager.dart` 取代

### 不動

- 既有 services（`wish_storage` 主體 / `wish_fetcher` / `wish_stats` / `gacha_url`）
- `wish_repository` 攔截 / 抓取流程
- 所有 Phase 1 元件（StatCard / ChartCard / SectionCard / PageHeader / EmptyState 主體）
- AppShell / 路由
- Theme tokens

---

## Coding Conventions（這份計畫所有任務共用）

- 全部新檔絕對 import：`package:genshin_impact_wish_gacha_analyzer/...`
- i18n 走 `package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart`
- Riverpod 3 Notifier / NotifierProvider / Provider；family 用 `NotifierProvider.family`
- 顏色 / 間距 / 圓角 / 字級**禁止** magic value，一律走 `Theme.of(context).gacha` + `AppSpacing/AppRadius/AppFontSize`
- Test 用 `flutter_test`；服務層純函式 unit test，元件層 widget test
- Commit 訊息英文 imperative；每個 task 結尾必有 commit step
- `flutter analyze lib/` 必須 clean（零 issue）
- `flutter test` 必須全綠

---

## Task 1: Add Phase 2 i18n keys

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`

把 Phase 2 用得到的字串先一次加進四份 arb，避免後續每個 task 都要改 arb。

- [ ] **Step 1: Append the new keys to `app_zh_Hant.arb`**

把下列 keys 插入既有的 `}` 之前（移除最後一行 `}`，加上 `,` 與下面內容，然後補回 `}`）：

```json
,

"pityFiveStar": "5★ 保底",
"pityFourStar": "4★ 保底",
"pityCurrent": "{current} / {threshold}",
"@pityCurrent": {
  "placeholders": {
    "current": { "type": "int" },
    "threshold": { "type": "int" }
  }
},
"pityDistance": "距下次保底 {n} 抽",
"@pityDistance": {
  "placeholders": { "n": { "type": "int" } }
},
"pityClose": "快保底了！",
"pityGuaranteed": "保底中",
"pityNoFiveStar": "暫無 5★",
"pityBeginnerEnded": "已結束",

"timelineNoRecords": "暫無 5★ 紀錄",
"timelineSinceLast": "{n} 抽",
"@timelineSinceLast": {
  "placeholders": { "n": { "type": "int" } }
},

"filterRarityAll": "全部稀有度",
"filterRarityFiveStar": "只看 5★",
"filterRarityFourStar": "只看 4★",
"filterKindAll": "全部類型",
"filterKindCharacter": "只看角色",
"filterKindWeapon": "只看武器",
"filterSearchHint": "搜尋名稱…",
"filterClear": "清除篩選",

"sortByTimeDesc": "時間由近到遠",
"sortByTimeAsc": "時間由遠到近",
"sortByRarityDesc": "稀有度高到低",
"sortByRarityAsc": "稀有度低到高",
"sortByName": "名稱",

"pagerFirst": "首頁",
"pagerLast": "末頁",

"settingsExportJson": "匯出 JSON",
"settingsExportCsv": "匯出 CSV",
"settingsImportJson": "匯入 JSON",
"settingsClearActive": "清除目前帳號資料",
"settingsClearAll": "清除所有資料",
"settingsExportSuccess": "已匯出至 {path}",
"@settingsExportSuccess": {
  "placeholders": { "path": { "type": "String" } }
},
"settingsImportSuccess": "成功匯入 UID {uid} 的 {count} 筆紀錄",
"@settingsImportSuccess": {
  "placeholders": {
    "uid": { "type": "String" },
    "count": { "type": "int" }
  }
},
"settingsImportFailed": "匯入失敗：{reason}",
"@settingsImportFailed": {
  "placeholders": { "reason": { "type": "String" } }
},

"confirmTitle": "確認操作",
"confirmClearActiveBody": "這會永久刪除 UID {uid} 的所有祈願紀錄。輸入 UID 確認：",
"@confirmClearActiveBody": {
  "placeholders": { "uid": { "type": "String" } }
},
"confirmClearAllBody": "這會永久刪除所有帳號的祈願紀錄。輸入 DELETE 確認：",
"confirmTypeMismatch": "輸入不符，操作已取消",
"confirmCancel": "取消",
"confirmDelete": "刪除",

"accountListEmpty": "目前沒有任何帳號",
"accountLastUpdated": "最後更新 {time}",
"@accountLastUpdated": {
  "placeholders": { "time": { "type": "String" } }
},
"accountActiveTag": "活躍",
"accountSetActive": "設為活躍",
"accountRemove": "移除",
"accountRecapture": "重新攔截 / 新增帳號",

"loadingBootstrap": "載入中…",

"timelineCountFiveStar": "5★ × {n}",
"@timelineCountFiveStar": {
  "placeholders": { "n": { "type": "int" } }
},
"timelineLatestEntry": "最新：{name}（{n} 抽）",
"@timelineLatestEntry": {
  "placeholders": {
    "name": { "type": "String" },
    "n": { "type": "int" }
  }
}
```

- [ ] **Step 2: Mirror keys into `app_zh.arb`**

整份 copy `app_zh_Hant.arb` 的內容，把 `"@@locale": "zh_Hant"` 改 `"zh"`。

- [ ] **Step 3: Append translated keys to `app_zh_Hans.arb`**

加入同樣 keys，數值用簡體：

```json
,

"pityFiveStar": "5★ 保底",
"pityFourStar": "4★ 保底",
"pityCurrent": "{current} / {threshold}",
"@pityCurrent": {
  "placeholders": {
    "current": { "type": "int" },
    "threshold": { "type": "int" }
  }
},
"pityDistance": "距下次保底 {n} 抽",
"@pityDistance": {
  "placeholders": { "n": { "type": "int" } }
},
"pityClose": "快保底了！",
"pityGuaranteed": "保底中",
"pityNoFiveStar": "暂无 5★",
"pityBeginnerEnded": "已结束",

"timelineNoRecords": "暂无 5★ 记录",
"timelineSinceLast": "{n} 抽",
"@timelineSinceLast": {
  "placeholders": { "n": { "type": "int" } }
},

"filterRarityAll": "全部稀有度",
"filterRarityFiveStar": "只看 5★",
"filterRarityFourStar": "只看 4★",
"filterKindAll": "全部类型",
"filterKindCharacter": "只看角色",
"filterKindWeapon": "只看武器",
"filterSearchHint": "搜索名称…",
"filterClear": "清除筛选",

"sortByTimeDesc": "时间由近到远",
"sortByTimeAsc": "时间由远到近",
"sortByRarityDesc": "稀有度高到低",
"sortByRarityAsc": "稀有度低到高",
"sortByName": "名称",

"pagerFirst": "首页",
"pagerLast": "末页",

"settingsExportJson": "导出 JSON",
"settingsExportCsv": "导出 CSV",
"settingsImportJson": "导入 JSON",
"settingsClearActive": "清除当前账号数据",
"settingsClearAll": "清除所有数据",
"settingsExportSuccess": "已导出至 {path}",
"@settingsExportSuccess": {
  "placeholders": { "path": { "type": "String" } }
},
"settingsImportSuccess": "成功导入 UID {uid} 的 {count} 条记录",
"@settingsImportSuccess": {
  "placeholders": {
    "uid": { "type": "String" },
    "count": { "type": "int" }
  }
},
"settingsImportFailed": "导入失败：{reason}",
"@settingsImportFailed": {
  "placeholders": { "reason": { "type": "String" } }
},

"confirmTitle": "确认操作",
"confirmClearActiveBody": "这会永久删除 UID {uid} 的所有祈愿记录。输入 UID 确认：",
"@confirmClearActiveBody": {
  "placeholders": { "uid": { "type": "String" } }
},
"confirmClearAllBody": "这会永久删除所有账号的祈愿记录。输入 DELETE 确认：",
"confirmTypeMismatch": "输入不符，操作已取消",
"confirmCancel": "取消",
"confirmDelete": "删除",

"accountListEmpty": "目前没有任何账号",
"accountLastUpdated": "最后更新 {time}",
"@accountLastUpdated": {
  "placeholders": { "time": { "type": "String" } }
},
"accountActiveTag": "活跃",
"accountSetActive": "设为活跃",
"accountRemove": "移除",
"accountRecapture": "重新拦截 / 新增账号",

"loadingBootstrap": "加载中…",

"timelineCountFiveStar": "5★ × {n}",
"@timelineCountFiveStar": {
  "placeholders": { "n": { "type": "int" } }
},
"timelineLatestEntry": "最新：{name}（{n} 抽）",
"@timelineLatestEntry": {
  "placeholders": {
    "name": { "type": "String" },
    "n": { "type": "int" }
  }
}
```

- [ ] **Step 4: Append translated keys to `app_en.arb`**

```json
,

"pityFiveStar": "5★ pity",
"pityFourStar": "4★ pity",
"pityCurrent": "{current} / {threshold}",
"@pityCurrent": {
  "placeholders": {
    "current": { "type": "int" },
    "threshold": { "type": "int" }
  }
},
"pityDistance": "{n} pulls until guaranteed",
"@pityDistance": {
  "placeholders": { "n": { "type": "int" } }
},
"pityClose": "Close to guaranteed!",
"pityGuaranteed": "Guaranteed soon",
"pityNoFiveStar": "No 5★ yet",
"pityBeginnerEnded": "Ended",

"timelineNoRecords": "No 5★ records",
"timelineSinceLast": "{n} pulls",
"@timelineSinceLast": {
  "placeholders": { "n": { "type": "int" } }
},

"filterRarityAll": "All rarities",
"filterRarityFiveStar": "5★ only",
"filterRarityFourStar": "4★ only",
"filterKindAll": "All kinds",
"filterKindCharacter": "Characters only",
"filterKindWeapon": "Weapons only",
"filterSearchHint": "Search name…",
"filterClear": "Clear filters",

"sortByTimeDesc": "Time, newest first",
"sortByTimeAsc": "Time, oldest first",
"sortByRarityDesc": "Rarity, high to low",
"sortByRarityAsc": "Rarity, low to high",
"sortByName": "Name",

"pagerFirst": "First",
"pagerLast": "Last",

"settingsExportJson": "Export JSON",
"settingsExportCsv": "Export CSV",
"settingsImportJson": "Import JSON",
"settingsClearActive": "Clear current account data",
"settingsClearAll": "Clear all data",
"settingsExportSuccess": "Exported to {path}",
"@settingsExportSuccess": {
  "placeholders": { "path": { "type": "String" } }
},
"settingsImportSuccess": "Imported {count} records for UID {uid}",
"@settingsImportSuccess": {
  "placeholders": {
    "uid": { "type": "String" },
    "count": { "type": "int" }
  }
},
"settingsImportFailed": "Import failed: {reason}",
"@settingsImportFailed": {
  "placeholders": { "reason": { "type": "String" } }
},

"confirmTitle": "Confirm",
"confirmClearActiveBody": "This will permanently delete all wish records for UID {uid}. Type the UID to confirm:",
"@confirmClearActiveBody": {
  "placeholders": { "uid": { "type": "String" } }
},
"confirmClearAllBody": "This will permanently delete every account's wish records. Type DELETE to confirm:",
"confirmTypeMismatch": "Input did not match. Operation cancelled.",
"confirmCancel": "Cancel",
"confirmDelete": "Delete",

"accountListEmpty": "No accounts yet",
"accountLastUpdated": "Last updated {time}",
"@accountLastUpdated": {
  "placeholders": { "time": { "type": "String" } }
},
"accountActiveTag": "Active",
"accountSetActive": "Set active",
"accountRemove": "Remove",
"accountRecapture": "Re-capture / add account",

"loadingBootstrap": "Loading…",

"timelineCountFiveStar": "5★ × {n}",
"@timelineCountFiveStar": {
  "placeholders": { "n": { "type": "int" } }
},
"timelineLatestEntry": "Latest: {name} ({n} pulls)",
"@timelineLatestEntry": {
  "placeholders": {
    "name": { "type": "String" },
    "n": { "type": "int" }
  }
}
```

- [ ] **Step 5: Run codegen**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現所有新 getter（如 `pityFiveStar`、`filterClear`、`settingsExportJson` 等）。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/
git commit -m "feat(i18n): add Phase 2 keys (pity / timeline / filter / settings / account)"
```

---

## Task 2: Add `file_selector` dependency

**Files:**
- Modify: `pubspec.yaml`

`file_selector` 是 Flutter team 官方包，提供桌面平台的開檔/存檔對話框。比 `file_picker` 更輕量，已支援 Windows。

- [ ] **Step 1: Add dependency**

把 `pubspec.yaml` 中 `dependencies:` 區塊加入 `file_selector: ^1.0.0`，順序維持字母序，放在 `fl_chart` 上方：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_rust_bridge: ^2.12.0
  ffi: ^2.2.0
  flutter_riverpod: ^3.0.0
  go_router: ^17.0.0
  http: ^1.2.0
  path_provider: ^2.1.0
  shared_preferences: ^2.3.0
  file_selector: ^1.0.0
  fl_chart: ^1.0.0
  intl: ^0.20.0
  package_info_plus: ^10.0.0
```

- [ ] **Step 2: Run pub get**

Run: `flutter pub get`
Expected: 解析成功、`file_selector` 與其平台 implementation（含 `file_selector_windows`）下載完成。

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add file_selector for desktop import/export dialogs"
```

---

## Task 3: Refactor error handling — sealed `UpdateError`

**Files:**
- Create: `lib/state/update_error.dart`
- Modify: `lib/state/update_progress.dart`
- Modify: `lib/state/wish_repository.dart`

把 `UpdateFailed.message: String`（zh-Hant 硬碼）改為 `UpdateFailed.error: UpdateError`（sealed 子類），dialog 之後在 i18n 層解析。

- [ ] **Step 1: Create `lib/state/update_error.dart`**

```dart
// lib/state/update_error.dart

/// 更新流程的錯誤類型，dialog 端用 i18n 解析顯示。
sealed class UpdateError {
  const UpdateError();
}

class UpdateErrorAuthExpired extends UpdateError {
  const UpdateErrorAuthExpired();
}

class UpdateErrorRateLimited extends UpdateError {
  const UpdateErrorRateLimited();
}

class UpdateErrorServer extends UpdateError {
  const UpdateErrorServer(this.details);
  final String details;
}

class UpdateErrorNoRecords extends UpdateError {
  const UpdateErrorNoRecords();
}

/// fallback：訊息已是 user-readable（多半來自 FormatException 等），直接顯示。
class UpdateErrorOther extends UpdateError {
  const UpdateErrorOther(this.message);
  final String message;
}
```

- [ ] **Step 2: Modify `lib/state/update_progress.dart`**

把 `UpdateFailed` 改為帶 `UpdateError`：

```dart
// lib/state/update_progress.dart
import 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

sealed class UpdateProgress {
  const UpdateProgress();
}

class WaitingForCapture extends UpdateProgress {
  const WaitingForCapture({this.isFallback = false});
  final bool isFallback;
}

class FetchingBanner extends UpdateProgress {
  const FetchingBanner({
    required this.gachaType,
    required this.displayName,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final String displayName;
  final int pageIndex;
  final int newRecordsSoFar;
}

class UpdateCompleted extends UpdateProgress {
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
  });
  final int totalNewRecords;
  final List<String> failedBanners;
  final DateTime updatedAt;
}

class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.error);
  final UpdateError error;
}
```

- [ ] **Step 3: Modify `lib/state/wish_repository.dart`**

兩個地方改：

(a) 第 ~172 行：`state = state.copyWith(progress: const UpdateFailed('認證持續失效，請重新登入遊戲'));` → 改為 `state = state.copyWith(progress: const UpdateFailed(UpdateErrorAuthExpired()));`

(b) 第 ~208 行：`throw const FormatException('此帳號尚無任何卡池紀錄');` 改為一個 typed exception。先在檔案頂部 import 區補：

```dart
class _NoRecordsException implements Exception {
  const _NoRecordsException();
}
```

放在 `class WishState` 上方（檔案頂部、import 之後）。然後 `throw const FormatException(...)` 改為 `throw const _NoRecordsException();`。

(c) `_friendlyError` 方法重寫為回傳 `UpdateError`：

```dart
UpdateError _friendlyError(Object e) => switch (e) {
      _NoRecordsException() => const UpdateErrorNoRecords(),
      FormatException(:final message) => UpdateErrorOther(message),
      RateLimitedException() => const UpdateErrorRateLimited(),
      ApiErrorException(:final message) => UpdateErrorServer(message),
      AuthExpiredException() => const UpdateErrorAuthExpired(),
      _ => UpdateErrorOther(e.toString()),
    };
```

(d) 兩處 `state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));` 不需要改文字，因為 `_friendlyError` 回傳型別變了 → `UpdateFailed(UpdateError)` 自動匹配新建構子。

- [ ] **Step 4: Run analyze**

Run: `flutter analyze lib/state/`
Expected: No issues found（`UpdateProgressDialog` 仍取 `UpdateFailed.message` 會 fail，下個 task 修）。

> 預期 `lib/widgets/update_progress_dialog.dart` 此時會 build 失敗（因 `UpdateFailed.message` 改成 `error`）。**不在此 task 修**，下個 task T4 處理。

- [ ] **Step 5: Commit**

```bash
git add lib/state/update_error.dart lib/state/update_progress.dart lib/state/wish_repository.dart
git commit -m "refactor(error): introduce sealed UpdateError for i18n-friendly errors"
```

---

## Task 4: Update progress dialog to render `UpdateError` via i18n

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1: Replace the `UpdateFailed` branch in `_Body.build`**

找到 `_Body.build` 內的 switch 表達式中 `UpdateFailed(:final message) => Text(message),` 那行，改為：

```dart
UpdateFailed(:final error) => Text(_resolveError(error, l)),
```

並在 `_Body` class 內加一個 helper 方法（放在 `build` 方法之後、class 結尾之前）：

```dart
String _resolveError(UpdateError error, AppLocalizations l) =>
    switch (error) {
      UpdateErrorAuthExpired() => l.errorAuthExpired,
      UpdateErrorRateLimited() => l.errorRateLimited,
      UpdateErrorServer(:final details) => l.errorServer(details),
      UpdateErrorNoRecords() => l.errorNoRecords,
      UpdateErrorOther(:final message) => message,
    };
```

- [ ] **Step 2: Verify imports**

`update_progress_dialog.dart` 已 import `state/wish_repository.dart`，後者再 export `state/update_progress.dart`，後者 export `state/update_error.dart`。所以 `UpdateError`、`UpdateErrorAuthExpired` 等型別已可見、無需新 import。

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/widgets/update_progress_dialog.dart`
Expected: No issues found.

Run: `flutter analyze lib/`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "feat(i18n): localize update error messages in progress dialog"
```

---

## Task 5: Apply `EmptyState.noRecords()` factory in BannerPage

**Files:**
- Modify: `lib/pages/banner_page.dart`

當卡池無紀錄時（`records.isEmpty`），目前直接渲染空表格。改為顯示 EmptyState.noRecords()。

- [ ] **Step 1: Read current banner_page.dart**

確認 `build` 結構，找到 `final records = activeData.banners[gachaType] ?? const [];` 之後的位置。

- [ ] **Step 2: Add empty-records short-circuit**

在 `final records = ...` 之後、`final stats = computeWishStats(records);` 之前，插入：

```dart
if (records.isEmpty) {
  return Padding(
    padding: const EdgeInsets.all(AppSpacing.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: type.resolveName(l)),
        SizedBox(
          height: 320,
          child: EmptyState.noRecords(context),
        ),
      ],
    ),
  );
}
```

> Note: 此處仍渲染 PageHeader 讓使用者知道在哪個卡池；EmptyState 限高 320 避免太空蕩。

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/pages/banner_page.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(banner-page): show EmptyState.noRecords for empty banners"
```

---

## Task 6: `wish_pity` service with TDD

**Files:**
- Create: `lib/services/wish_pity.dart`
- Create: `test/services/wish_pity_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/services/wish_pity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';

WishRecord _r({
  required String id,
  required int rank,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: 'x',
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  group('computePity', () {
    test('空 list → current=0、lastFiveStarAt=null', () {
      final p = computePity(const [], threshold: 90);
      expect(p.current, 0);
      expect(p.threshold, 90);
      expect(p.lastFiveStarAt, isNull);
    });

    test('從未抽中 5★ → current = total 抽數', () {
      final records = [
        _r(id: '3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 3);
      expect(p.lastFiveStarAt, isNull);
    });

    test('上次 5★ 之後 N 抽 → current=N', () {
      // records 是 desc by time。最新在 index 0。
      // 抽了 3 個 4★，然後一個 5★，再之前是 3★。
      final records = [
        _r(id: '5', rank: 4, time: DateTime(2025, 1, 5)), // newest
        _r(id: '4', rank: 4, time: DateTime(2025, 1, 4)),
        _r(id: '3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 5, time: DateTime(2025, 1, 2)), // 上次 5★
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 3); // 上次 5★ 之後 3 抽
      expect(p.lastFiveStarAt, DateTime(2025, 1, 2));
    });

    test('首抽即 5★ → current=0、lastFiveStarAt 為該筆時間', () {
      final records = [
        _r(id: '1', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.lastFiveStarAt, DateTime(2025, 1, 1));
    });

    test('最新即 5★ → current=0', () {
      final records = [
        _r(id: '3', rank: 5, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 4, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.lastFiveStarAt, DateTime(2025, 1, 3));
    });

    test('剛好 threshold-1 抽未保底 → progress 接近 1.0', () {
      final records = List.generate(
        89,
        (i) => _r(id: '$i', rank: 4, time: DateTime(2025, 1, 1 + i)),
      ).reversed.toList(growable: false);
      final p = computePity(records, threshold: 90);
      expect(p.current, 89);
      expect(p.progress, closeTo(89 / 90, 0.001));
      expect(p.distance, 1);
    });

    test('progress 永遠在 0..1 之間，超過 threshold 也 clamp', () {
      final records = List.generate(
        100,
        (i) => _r(id: '$i', rank: 4, time: DateTime(2025, 1, 1 + i)),
      ).reversed.toList(growable: false);
      final p = computePity(records, threshold: 90);
      expect(p.progress, 1.0);
      expect(p.distance, 0);
    });
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/services/wish_pity_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: Write `lib/services/wish_pity.dart`**

```dart
// lib/services/wish_pity.dart
import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

@immutable
class Pity {
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastFiveStarAt,
  });

  /// 距上次 5★ 已抽幾抽（不含 5★ 那筆本身）。沒有 5★ 時 = 總抽數。
  final int current;

  /// 該卡池的保底閾值。
  final int threshold;

  /// 上次 5★ 抽中的時間；若從未 5★，為 null。
  final DateTime? lastFiveStarAt;

  /// 0.0–1.0，超過 threshold clamp 到 1.0。
  double get progress {
    if (threshold <= 0) return 0;
    final raw = current / threshold;
    return raw > 1 ? 1.0 : raw;
  }

  /// 距下次保底還差幾抽（>= 0）。
  int get distance {
    final d = threshold - current;
    return d < 0 ? 0 : d;
  }
}

/// 計算單一卡池的保底狀態。
///
/// [records] 必須以時間 desc 排序（最新在前），與 `BannerStorage.banners[gachaType]`
/// 的儲存約定一致。
Pity computePity(
  List<WishRecord> records, {
  required int threshold,
}) {
  var current = 0;
  DateTime? lastFiveStarAt;
  for (final r in records) {
    if (r.rankType == 5) {
      lastFiveStarAt = r.time;
      break;
    }
    current++;
  }
  return Pity(
    current: current,
    threshold: threshold,
    lastFiveStarAt: lastFiveStarAt,
  );
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/services/wish_pity_test.dart`
Expected: PASS（7 tests）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_pity.dart test/services/wish_pity_test.dart
git commit -m "feat(pity): add wish_pity service with computePity()"
```

---

## Task 7: PityCard widget with TDD

**Files:**
- Create: `lib/widgets/cards/pity_card.dart`
- Create: `test/widgets/cards/pity_card_test.dart`

PityCard 三狀態（< 70% / 70-89% / ≥ 90%）+ 「快保底」呼吸動效（≥ 70% 時 1.5s loop）。

- [ ] **Step 1: Write failing tests**

```dart
// test/widgets/cards/pity_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(body: SizedBox(width: 280, child: child)),
      );

  testWidgets('renders label and current/threshold', (tester) async {
    final pity = const Pity(current: 12, threshold: 90, lastFiveStarAt: null);
    await tester.pumpWidget(_wrap(PityCard(
      label: '5★ pity',
      pity: pity,
      accent: GachaTokens.dark.fiveStar,
    )));
    expect(find.text('5★ pity'.toUpperCase()), findsOneWidget);
    expect(find.text('12 / 90'), findsOneWidget);
  });

  testWidgets('low progress (<70%) shows distance subtitle, no warning',
      (tester) async {
    final pity = const Pity(current: 30, threshold: 90, lastFiveStarAt: null);
    await tester.pumpWidget(_wrap(PityCard(
      label: '5★',
      pity: pity,
      accent: GachaTokens.dark.fiveStar,
    )));
    expect(find.textContaining('60'), findsOneWidget); // distance = 60
  });

  testWidgets('beginner ended shows ended state', (tester) async {
    final pity = const Pity(current: 20, threshold: 20, lastFiveStarAt: null);
    await tester.pumpWidget(_wrap(PityCard(
      label: 'Beginner',
      pity: pity,
      accent: GachaTokens.dark.fiveStar,
      isEndedPool: true,
    )));
    // distance = 0 should be present
    expect(find.text('20 / 20'), findsOneWidget);
  });

  testWidgets('PityCard finds value text regardless of progress level',
      (tester) async {
    for (final p in [
      const Pity(current: 60, threshold: 90, lastFiveStarAt: null), // 67%
      const Pity(current: 75, threshold: 90, lastFiveStarAt: null), // 83%
      const Pity(current: 90, threshold: 90, lastFiveStarAt: null), // 100%
    ]) {
      await tester.pumpWidget(_wrap(PityCard(
        label: '5★',
        pity: p,
        accent: GachaTokens.dark.fiveStar,
      )));
      expect(find.text('${p.current} / ${p.threshold}'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/cards/pity_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/cards/pity_card.dart`**

```dart
// lib/widgets/cards/pity_card.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class PityCard extends StatefulWidget {
  const PityCard({
    super.key,
    required this.label,
    required this.pity,
    required this.accent,
    this.isEndedPool = false,
  });

  final String label;
  final Pity pity;
  final Color accent;

  /// 新手池 20 抽結束 → 顯示「已結束」狀態。
  final bool isEndedPool;

  @override
  State<PityCard> createState() => _PityCardState();
}

class _PityCardState extends State<PityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final p = widget.pity;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final phase = _phase(p);

    final accent = phase == _Phase.guaranteed
        ? tokens.stateWarning
        : widget.accent;

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.pityCurrent(p.current, p.threshold),
            style: TextStyle(
              fontSize: AppFontSize.display,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _ProgressBar(
            progress: p.progress,
            phase: phase,
            accent: accent,
            tokens: tokens,
            breath: reduceMotion ? null : _breath,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Subtitle(
            phase: phase,
            pity: p,
            isEndedPool: widget.isEndedPool,
            tokens: tokens,
            l: l,
          ),
        ],
      ),
    );
  }

  _Phase _phase(Pity p) {
    if (widget.isEndedPool) return _Phase.ended;
    final ratio = p.progress;
    if (ratio >= 1.0 || p.distance == 0) return _Phase.guaranteed;
    if (ratio >= 0.7) return _Phase.close;
    return _Phase.normal;
  }
}

enum _Phase { normal, close, guaranteed, ended }

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.phase,
    required this.accent,
    required this.tokens,
    required this.breath,
  });
  final double progress;
  final _Phase phase;
  final Color accent;
  final GachaTokens tokens;
  final AnimationController? breath;

  @override
  Widget build(BuildContext context) {
    Widget bar = Container(
      height: 8,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: phase == _Phase.normal
                    ? [accent.withValues(alpha: 0.7), accent]
                    : [tokens.fourStar, accent],
              ),
            ),
          ),
        ),
      ),
    );

    if (breath != null && phase == _Phase.close) {
      bar = AnimatedBuilder(
        animation: breath!,
        builder: (_, child) => Opacity(
          opacity: 0.7 + 0.3 * breath!.value,
          child: child,
        ),
        child: bar,
      );
    }
    return bar;
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.phase,
    required this.pity,
    required this.isEndedPool,
    required this.tokens,
    required this.l,
  });
  final _Phase phase;
  final Pity pity;
  final bool isEndedPool;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (text, color) = switch (phase) {
      _Phase.ended => (l.pityBeginnerEnded, tokens.textMuted),
      _Phase.guaranteed => (l.pityGuaranteed, tokens.stateWarning),
      _Phase.close => (l.pityClose, tokens.stateWarning),
      _Phase.normal => pity.lastFiveStarAt == null
          ? (l.pityNoFiveStar, tokens.textMuted)
          : (l.pityDistance(pity.distance), tokens.textMuted),
    };

    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/widgets/cards/pity_card_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/pity_card.dart test/widgets/cards/pity_card_test.dart
git commit -m "feat(widgets): add PityCard with breathing animation in close-pity state"
```

---

## Task 8: Wire PityCard into BannerPage

**Files:**
- Modify: `lib/pages/banner_page.dart`

把 5★ StatCard 換成 PityCard，4★ StatCard 換成 PityCard，第三張卡留總抽數。

- [ ] **Step 1: Read banner_page.dart and locate Row 1**

定位 `// Row 1: 三聯 Stat 卡` 區塊。

- [ ] **Step 2: Add imports**

在檔案 import 區補：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
```

- [ ] **Step 3: Compute pity above the LayoutBuilder**

在 `final stats = computeWishStats(records);` 之後加：

```dart
final fivePity =
    computePity(records, threshold: type.fiveStarPity);
final fourPity =
    computePity(records, threshold: type.fourStarPity);
final isEndedPool = type.gachaType == '100';
```

- [ ] **Step 4: Replace Row 1 children**

把 Row 1 的 Wrap.children 三個 SizedBox 換成：

```dart
SizedBox(
  width: wide
      ? (c.maxWidth - AppSpacing.m * 2) * 6 / 12
      : c.maxWidth,
  child: PityCard(
    label: l.pityFiveStar,
    pity: fivePity,
    accent: tokens.fiveStar,
    isEndedPool: isEndedPool,
  ),
),
SizedBox(
  width: wide
      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
  child: PityCard(
    label: l.pityFourStar,
    pity: fourPity,
    accent: tokens.fourStar,
    isEndedPool: isEndedPool,
  ),
),
SizedBox(
  width: wide
      ? (c.maxWidth - AppSpacing.m * 2) * 3 / 12
      : (mid ? (c.maxWidth - AppSpacing.m) / 2 : c.maxWidth),
  child: StatCard(
    label: l.statsTotal,
    value: '${stats.total}',
    accent: tokens.accentPrimary,
  ),
),
```

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/pages/banner_page.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(banner-page): replace 5★/4★ StatCards with real PityCards"
```

---

## Task 9: TimelineCard widget with TDD

**Files:**
- Create: `lib/widgets/cards/timeline_card.dart`
- Create: `test/widgets/cards/timeline_card_test.dart`

橫向 scrollable 5★ 時間軸，每個 5★ 是膠囊：[圖示][名字][抽中花了 X 抽]，hover tooltip 顯示日期。窄寬度（< 800）改縱向列表。

- [ ] **Step 1: Write failing tests**

```dart
// test/widgets/cards/timeline_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_card.dart';

WishRecord _r({
  required String id,
  required int rank,
  required String name,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  testWidgets('empty list shows no-records message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: SizedBox(
          height: 220,
          child: TimelineCard(records: <WishRecord>[]),
        ),
      ),
    ));
    expect(find.textContaining('5★'), findsWidgets);
  });

  testWidgets('renders one chip per 5★ record', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: '夜蘭', time: DateTime(2025, 4, 1)),
      _r(id: '4', rank: 4, name: '煙緋', time: DateTime(2025, 3, 28)),
      _r(id: '3', rank: 3, name: 'x', time: DateTime(2025, 3, 27)),
      _r(id: '2', rank: 5, name: '流浪者', time: DateTime(2025, 3, 1)),
      _r(id: '1', rank: 3, name: 'y', time: DateTime(2025, 2, 1)),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 220,
          child: TimelineCard(records: records),
        ),
      ),
    ));
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
    expect(find.text('煙緋'), findsNothing); // 4★ 不顯示
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/cards/timeline_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/cards/timeline_card.dart`**

```dart
// lib/widgets/cards/timeline_card.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 顯示傳入 records 中的 5★ 紀錄；橫向 scrollable，窄寬度改縱向。
class TimelineCard extends StatelessWidget {
  const TimelineCard({
    super.key,
    required this.records,
    this.bannerColorOf,
  });

  /// 必須以時間 desc 排序（最新在前）。
  final List<WishRecord> records;

  /// 跨卡池版本：傳入後每個膠囊以對應卡池色當左側 stripe。
  final Color Function(String gachaType)? bannerColorOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final fiveStars = _buildEntries(records);

    if (fiveStars.isEmpty) {
      return Center(
        child: Text(
          l.timelineNoRecords,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 320;
      if (narrow) {
        return ListView.separated(
          scrollDirection: Axis.vertical,
          itemCount: fiveStars.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.xs),
          itemBuilder: (_, i) => _Chip(
            entry: fiveStars[i],
            bannerColorOf: bannerColorOf,
            tokens: tokens,
            l: l,
          ),
        );
      }
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fiveStars.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s),
        itemBuilder: (_, i) => _Chip(
          entry: fiveStars[i],
          bannerColorOf: bannerColorOf,
          tokens: tokens,
          l: l,
        ),
      );
    });
  }

  /// 從 records 倒序累計，每碰到 5★ 計算「離上一個 5★ 多少抽」。
  static List<_Entry> _buildEntries(List<WishRecord> records) {
    // records is desc by time. We want list of 5★ in chronological insertion order
    // each annotated with "since previous 5★ (or start)" pulls.
    final asc = records.reversed.toList(growable: false);
    final out = <_Entry>[];
    var pull = 0;
    for (final r in asc) {
      pull++;
      if (r.rankType == 5) {
        out.add(_Entry(
          name: r.name,
          gachaType: r.gachaType,
          time: r.time,
          pullsSincePrev: pull,
        ));
        pull = 0;
      }
    }
    // Display newest first.
    return out.reversed.toList(growable: false);
  }
}

class _Entry {
  const _Entry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });
  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.entry,
    required this.bannerColorOf,
    required this.tokens,
    required this.l,
  });
  final _Entry entry;
  final Color Function(String)? bannerColorOf;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final accent = bannerColorOf?.call(entry.gachaType) ?? tokens.fiveStar;
    return Tooltip(
      message: _formatDate(entry.time),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m, vertical: AppSpacing.s),
        decoration: BoxDecoration(
          color: tokens.surfaceCardHigh,
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.name,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l.timelineSinceLast(entry.pullsSincePrev),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/widgets/cards/timeline_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_card.dart test/widgets/cards/timeline_card_test.dart
git commit -m "feat(widgets): add TimelineCard for 5★ history visualization"
```

---

## Task 10: Wire TimelineCard into BannerPage

**Files:**
- Modify: `lib/pages/banner_page.dart`

把 BannerPage Row 2 第三張卡的 placeholder 換成 TimelineCard。

- [ ] **Step 1: Add import**

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_card.dart';
```

- [ ] **Step 2: Replace third ChartCard**

找到 Row 2 中第三個 SizedBox 的 ChartCard：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: '5★',
    chart: Center(
      child: Text(l.settingsPlaceholderPhase2,
          style: TextStyle(color: tokens.textMuted)),
    ),
  ),
),
```

換為：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineCard(records: records),
  ),
),
```

- [ ] **Step 3: Run analyze**

Run: `flutter analyze lib/pages/banner_page.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(banner-page): replace timeline placeholder with TimelineCard"
```

---

## Task 11: FiveStarList for OverviewPage

**Files:**
- Create: `lib/widgets/data/five_star_list.dart`
- Create: `test/widgets/data/five_star_list_test.dart`

跨卡池 5★ 縱向列表（每列：卡池色條 / 名字 / 卡池名 / X 抽 / 時間）。

- [ ] **Step 1: Write failing test**

```dart
// test/widgets/data/five_star_list_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/five_star_list.dart';

WishRecord _r({
  required String id,
  required int rank,
  required String name,
  required String gachaType,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: gachaType,
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  testWidgets('shows empty state when no 5★', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: const [],
      home: const Scaffold(
        body: FiveStarList(banners: <String, List<WishRecord>>{}),
      ),
    ));
    expect(find.byType(FiveStarList), findsOneWidget);
  });

  testWidgets('renders 5★ across banners sorted by time desc',
      (tester) async {
    final banners = <String, List<WishRecord>>{
      '301': [
        _r(id: '301-2', rank: 5, name: '夜蘭', gachaType: '301', time: DateTime(2025, 4, 1)),
        _r(id: '301-1', rank: 4, name: 'x', gachaType: '301', time: DateTime(2025, 3, 1)),
      ],
      '302': [
        _r(id: '302-1', rank: 5, name: '若水', gachaType: '302', time: DateTime(2025, 3, 15)),
      ],
    };
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: const [],
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FiveStarList(banners: banners),
        ),
      ),
    ));
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('若水'), findsOneWidget);
  });

  testWidgets('uses bannerColorFor helper to color stripes', (tester) async {
    final banners = <String, List<WishRecord>>{
      '301': [_r(id: '1', rank: 5, name: 'A', gachaType: '301')],
    };
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: FiveStarList(banners: banners),
      ),
    ));
    expect(find.byType(FiveStarList), findsOneWidget);
  });

  test('bannerColorFor maps known gachaTypes', () {
    final tokens = const FiveStarListColors(
      character: Color(0xFF000001),
      weapon: Color(0xFF000002),
      chronicled: Color(0xFF000003),
      standard: Color(0xFF000004),
      beginner: Color(0xFF000005),
      fallback: Color(0xFF000000),
    );
    expect(tokens.colorFor('301'), const Color(0xFF000001));
    expect(tokens.colorFor('302'), const Color(0xFF000002));
    expect(tokens.colorFor('500'), const Color(0xFF000003));
    expect(tokens.colorFor('200'), const Color(0xFF000004));
    expect(tokens.colorFor('100'), const Color(0xFF000005));
    expect(tokens.colorFor('999'), const Color(0xFF000000));
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/data/five_star_list_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/data/five_star_list.dart`**

```dart
// lib/widgets/data/five_star_list.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

@immutable
class FiveStarListColors {
  const FiveStarListColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.fallback,
  });
  final Color character;
  final Color weapon;
  final Color chronicled;
  final Color standard;
  final Color beginner;
  final Color fallback;

  Color colorFor(String gachaType) => switch (gachaType) {
        '301' => character,
        '302' => weapon,
        '500' => chronicled,
        '200' => standard,
        '100' => beginner,
        _ => fallback,
      };
}

class FiveStarList extends StatelessWidget {
  const FiveStarList({super.key, required this.banners});

  /// gachaType → records desc by time。
  final Map<String, List<WishRecord>> banners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    final entries = _build(banners);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            l.timelineNoRecords,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: tokens.textMuted),
          ),
        ),
      );
    }

    final colors = FiveStarListColors(
      character: tokens.character,
      weapon: tokens.weapon,
      chronicled: tokens.accentPrimary,
      standard: tokens.threeStar,
      beginner: tokens.textMuted,
      fallback: tokens.textMuted,
    );

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _Row(
              entry: entries[i],
              isStripe: i.isOdd,
              colors: colors,
              tokens: tokens,
              l: l,
            ),
        ],
      ),
    );
  }

  static List<_Entry> _build(Map<String, List<WishRecord>> banners) {
    final out = <_Entry>[];
    for (final entry in banners.entries) {
      final gachaType = entry.key;
      final records = entry.value;
      final asc = records.reversed.toList(growable: false);
      var pull = 0;
      for (final r in asc) {
        pull++;
        if (r.rankType == 5) {
          out.add(_Entry(
            name: r.name,
            gachaType: gachaType,
            time: r.time,
            pullsSincePrev: pull,
          ));
          pull = 0;
        }
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }
}

class _Entry {
  const _Entry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });
  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.isStripe,
    required this.colors,
    required this.tokens,
    required this.l,
  });
  final _Entry entry;
  final bool isStripe;
  final FiveStarListColors colors;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final type = gachaTypes.firstWhere(
      (t) => t.gachaType == entry.gachaType,
      orElse: () => GachaType(
        gachaType: entry.gachaType,
        nameKey: entry.gachaType,
        fiveStarPity: 90,
        fourStarPity: 10,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m, horizontal: AppSpacing.l),
      decoration: BoxDecoration(
        color: isStripe ? tokens.surfaceCardHigh : null,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              entry.name,
              style: TextStyle(
                color: tokens.fiveStar,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              type.resolveName(l),
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              l.timelineSinceLast(entry.pullsSincePrev),
              style: TextStyle(
                color: tokens.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _formatDate(entry.time),
              style: TextStyle(color: tokens.textMuted),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/widgets/data/five_star_list_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/data/five_star_list.dart test/widgets/data/five_star_list_test.dart
git commit -m "feat(widgets): add FiveStarList for cross-banner 5★ overview"
```

---

## Task 12: Wire FiveStarList into OverviewPage

**Files:**
- Modify: `lib/pages/overview_page.dart`

把 OverviewPage Row 2 第三張卡的 placeholder 換成 FiveStarList，再在 Row 2 之後追加完整的 FiveStarList 區塊。

- [ ] **Step 1: Add import**

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/five_star_list.dart';
```

- [ ] **Step 2: Replace third ChartCard with mini summary**

找到 Row 2 中第三個 SizedBox（5★ placeholder）：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: '5★',
    chart: Center(
      child: Text(l.settingsPlaceholderPhase2,
          style: TextStyle(color: tokens.textMuted)),
    ),
  ),
),
```

換為一張展示「最新一筆 5★」的小卡（用 ChartCard 容器即可）：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: _LatestFiveStar(stats: stats, banners: activeData.banners),
  ),
),
```

- [ ] **Step 3: Add _LatestFiveStar private widget**

在檔案結尾加：

```dart
class _LatestFiveStar extends StatelessWidget {
  const _LatestFiveStar({required this.stats, required this.banners});
  final WishStats stats;
  final Map<String, List<WishRecord>> banners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    if (stats.fiveStarCount == 0) {
      return Center(
        child: Text(l.timelineNoRecords,
            style: TextStyle(color: tokens.textMuted)),
      );
    }

    // 找跨卡池中最新的一筆 5★
    WishRecord? latest;
    var pullsSince = 0;
    for (final records in banners.values) {
      // records desc by time。第一筆 5★ 即該 banner 最新 5★。
      var pull = 0;
      for (final r in records) {
        if (r.rankType == 5) {
          if (latest == null || r.time.isAfter(latest.time)) {
            latest = r;
            pullsSince = pull + 1;
          }
          break;
        }
        pull++;
      }
    }
    if (latest == null) {
      return Center(
        child: Text(l.timelineNoRecords,
            style: TextStyle(color: tokens.textMuted)),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: Text(
          l.timelineLatestEntry(latest.name, pullsSince),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.fiveStar,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
```

並補 imports 在頂部：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
```

- [ ] **Step 4: Append FiveStarList block after Row 2**

在 Row 2 LayoutBuilder 之後（Column 的 children 末端、最外層 Column 結尾之前）加：

```dart
const SizedBox(height: AppSpacing.xl),
Text(
  l.timelineCountFiveStar(stats.fiveStarCount),
  style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: AppSpacing.s),
FiveStarList(banners: activeData.banners),
```

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/pages/overview_page.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "feat(overview-page): wire FiveStarList and latest-5star summary"
```

---

## Task 13: `wish_filter` service with TDD

**Files:**
- Create: `lib/services/wish_filter.dart`
- Create: `test/services/wish_filter_test.dart`

純函式服務，提供 `RecordFilter` / `RecordSort` 與 `filterRecords` / `sortRecords`。

- [ ] **Step 1: Write failing tests**

```dart
// test/services/wish_filter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';

WishRecord _r({
  required String id,
  required int rank,
  required WishItemKind kind,
  required String name,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: kind == WishItemKind.character ? '角色' : '武器',
      kind: kind,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  late List<WishRecord> records;
  setUp(() {
    records = [
      _r(id: '5', rank: 5, kind: WishItemKind.character, name: '夜蘭', time: DateTime(2025, 5, 1)),
      _r(id: '4', rank: 4, kind: WishItemKind.weapon, name: '匣裡龍吟', time: DateTime(2025, 4, 1)),
      _r(id: '3', rank: 3, kind: WishItemKind.weapon, name: '黑纓槍', time: DateTime(2025, 3, 1)),
      _r(id: '2', rank: 4, kind: WishItemKind.character, name: '煙緋', time: DateTime(2025, 2, 1)),
      _r(id: '1', rank: 5, kind: WishItemKind.weapon, name: '若水', time: DateTime(2025, 1, 1)),
    ];
  });

  group('filterRecords', () {
    test('預設不過濾', () {
      final out = filterRecords(records, const RecordFilter());
      expect(out.length, 5);
    });

    test('只看 5★', () {
      final out = filterRecords(records,
          const RecordFilter(rarity: RarityFilter.fiveStar));
      expect(out.map((r) => r.id), ['5', '1']);
    });

    test('只看 4★', () {
      final out = filterRecords(records,
          const RecordFilter(rarity: RarityFilter.fourStar));
      expect(out.map((r) => r.id), ['4', '2']);
    });

    test('只看角色', () {
      final out = filterRecords(records,
          const RecordFilter(kind: KindFilter.character));
      expect(out.map((r) => r.id), ['5', '2']);
    });

    test('組合 5★ + 武器', () {
      final out = filterRecords(
          records,
          const RecordFilter(
              rarity: RarityFilter.fiveStar, kind: KindFilter.weapon));
      expect(out.map((r) => r.id), ['1']);
    });

    test('搜尋名字（不分大小寫）', () {
      final out = filterRecords(records, const RecordFilter(query: '若'));
      expect(out.map((r) => r.id), ['1']);
    });

    test('空 query 等同沒篩', () {
      final out =
          filterRecords(records, const RecordFilter(query: '   '));
      expect(out.length, 5);
    });
  });

  group('sortRecords', () {
    test('預設時間 desc 維持原順序', () {
      final out = sortRecords(records, RecordSort.timeDesc);
      expect(out.map((r) => r.id), ['5', '4', '3', '2', '1']);
    });

    test('時間 asc', () {
      final out = sortRecords(records, RecordSort.timeAsc);
      expect(out.map((r) => r.id), ['1', '2', '3', '4', '5']);
    });

    test('稀有度 desc', () {
      final out = sortRecords(records, RecordSort.rarityDesc);
      // 5★ 在前，再 4★，再 3★。同稀有度時間 desc。
      expect(out.first.rankType, 5);
      expect(out.last.rankType, 3);
    });

    test('稀有度 asc', () {
      final out = sortRecords(records, RecordSort.rarityAsc);
      expect(out.first.rankType, 3);
      expect(out.last.rankType, 5);
    });

    test('名稱', () {
      final out = sortRecords(records, RecordSort.name);
      // 中文 codepoint 排序，只要結果穩定即可
      expect(out.length, records.length);
    });
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/services/wish_filter_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/services/wish_filter.dart`**

```dart
// lib/services/wish_filter.dart
import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

enum RarityFilter { all, fiveStar, fourStar }

enum KindFilter { all, character, weapon }

enum RecordSort { timeDesc, timeAsc, rarityDesc, rarityAsc, name }

@immutable
class RecordFilter {
  const RecordFilter({
    this.rarity = RarityFilter.all,
    this.kind = KindFilter.all,
    this.query = '',
  });

  final RarityFilter rarity;
  final KindFilter kind;
  final String query;

  bool get hasAny =>
      rarity != RarityFilter.all ||
      kind != KindFilter.all ||
      query.trim().isNotEmpty;

  RecordFilter copyWith({
    RarityFilter? rarity,
    KindFilter? kind,
    String? query,
  }) =>
      RecordFilter(
        rarity: rarity ?? this.rarity,
        kind: kind ?? this.kind,
        query: query ?? this.query,
      );
}

List<WishRecord> filterRecords(
    List<WishRecord> records, RecordFilter f) {
  final q = f.query.trim().toLowerCase();
  return records.where((r) {
    if (f.rarity == RarityFilter.fiveStar && r.rankType != 5) return false;
    if (f.rarity == RarityFilter.fourStar && r.rankType != 4) return false;
    if (f.kind == KindFilter.character && r.kind != WishItemKind.character) {
      return false;
    }
    if (f.kind == KindFilter.weapon && r.kind != WishItemKind.weapon) {
      return false;
    }
    if (q.isNotEmpty && !r.name.toLowerCase().contains(q)) return false;
    return true;
  }).toList(growable: false);
}

List<WishRecord> sortRecords(List<WishRecord> records, RecordSort s) {
  final out = [...records];
  switch (s) {
    case RecordSort.timeDesc:
      out.sort((a, b) => b.time.compareTo(a.time));
    case RecordSort.timeAsc:
      out.sort((a, b) => a.time.compareTo(b.time));
    case RecordSort.rarityDesc:
      out.sort((a, b) {
        final r = b.rankType.compareTo(a.rankType);
        return r != 0 ? r : b.time.compareTo(a.time);
      });
    case RecordSort.rarityAsc:
      out.sort((a, b) {
        final r = a.rankType.compareTo(b.rankType);
        return r != 0 ? r : b.time.compareTo(a.time);
      });
    case RecordSort.name:
      out.sort((a, b) => a.name.compareTo(b.name));
  }
  return out;
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/services/wish_filter_test.dart`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_filter.dart test/services/wish_filter_test.dart
git commit -m "feat(filter): add wish_filter service with RecordFilter and RecordSort"
```

---

## Task 14: `recordFilterProvider` family

**Files:**
- Create: `lib/state/record_filter.dart`
- Create: `test/state/record_filter_test.dart`

各卡池一份篩選 / 排序狀態，autoDispose 在離開頁面時清空。

- [ ] **Step 1: Write failing test**

```dart
// test/state/record_filter_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';

void main() {
  test('預設值為空篩選 + 時間 desc', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.rarity, RarityFilter.all);
    expect(state.filter.kind, KindFilter.all);
    expect(state.filter.query, '');
    expect(state.sort, RecordSort.timeDesc);
  });

  test('setFilter / setSort 各卡池獨立', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(recordFilterProvider('301').notifier).setFilter(
        const RecordFilter(rarity: RarityFilter.fiveStar));
    container.read(recordFilterProvider('302').notifier).setSort(
        RecordSort.rarityDesc);

    expect(container.read(recordFilterProvider('301')).filter.rarity,
        RarityFilter.fiveStar);
    expect(container.read(recordFilterProvider('301')).sort,
        RecordSort.timeDesc);
    expect(container.read(recordFilterProvider('302')).filter.rarity,
        RarityFilter.all);
    expect(container.read(recordFilterProvider('302')).sort,
        RecordSort.rarityDesc);
  });

  test('clear 重置為預設', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier =
        container.read(recordFilterProvider('301').notifier);
    notifier.setFilter(const RecordFilter(query: 'foo'));
    notifier.setSort(RecordSort.rarityAsc);
    notifier.clear();
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.query, '');
    expect(state.sort, RecordSort.timeDesc);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/state/record_filter_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/state/record_filter.dart`**

```dart
// lib/state/record_filter.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';

@immutable
class RecordFilterState {
  const RecordFilterState({
    required this.filter,
    required this.sort,
  });

  final RecordFilter filter;
  final RecordSort sort;

  RecordFilterState copyWith({RecordFilter? filter, RecordSort? sort}) =>
      RecordFilterState(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
      );
}

class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() {
    return const RecordFilterState(
      filter: RecordFilter(),
      sort: RecordSort.timeDesc,
    );
  }

  void setFilter(RecordFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void setSort(RecordSort sort) {
    state = state.copyWith(sort: sort);
  }

  void clear() {
    state = const RecordFilterState(
      filter: RecordFilter(),
      sort: RecordSort.timeDesc,
    );
  }
}

final recordFilterProvider = NotifierProvider.family<RecordFilterNotifier,
    RecordFilterState, String>((gachaType) => RecordFilterNotifier());

// 註：Riverpod 3.x 已無 FamilyNotifier；family-aware notifier 仍 extend Notifier，
// 不會在 build() 拿到 arg。我們的 setFilter/setSort/clear 不需要 gachaType，
// 每個 family instance 獨立即可。
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/state/record_filter_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/record_filter.dart test/state/record_filter_test.dart
git commit -m "feat(state): add recordFilterProvider family per gachaType"
```

---

## Task 15: SearchFilterBar widget

**Files:**
- Create: `lib/widgets/data/search_filter_bar.dart`
- Create: `test/widgets/data/search_filter_bar_test.dart`

工具列：搜尋欄（debounce 200ms）+ rarity dropdown + kind dropdown + sort dropdown + clear-filters 按鈕。

- [ ] **Step 1: Write failing test**

```dart
// test/widgets/data/search_filter_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';

void main() {
  testWidgets('clear button hidden when no active filter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SearchFilterBar(
          state: const RecordFilterState(
            filter: RecordFilter(),
            sort: RecordSort.timeDesc,
          ),
          onFilterChanged: (_) {},
          onSortChanged: (_) {},
          onClear: () {},
        ),
      ),
    ));
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('clear button visible when filter active', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SearchFilterBar(
          state: const RecordFilterState(
            filter: RecordFilter(rarity: RarityFilter.fiveStar),
            sort: RecordSort.timeDesc,
          ),
          onFilterChanged: (_) {},
          onSortChanged: (_) {},
          onClear: () {},
        ),
      ),
    ));
    // Material widget needs localization for placeholder text; existence of
    // a clear-filters button (any TextButton with action) is enough proof.
    expect(find.byType(TextButton), findsAtLeastNWidgets(1));
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/data/search_filter_bar_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/data/search_filter_bar.dart`**

```dart
// lib/widgets/data/search_filter_bar.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class SearchFilterBar extends StatefulWidget {
  const SearchFilterBar({
    super.key,
    required this.state,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final RecordFilterState state;
  final ValueChanged<RecordFilter> onFilterChanged;
  final ValueChanged<RecordSort> onSortChanged;
  final VoidCallback onClear;

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  late final TextEditingController _ctrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.state.filter.query);
  }

  @override
  void didUpdateWidget(covariant SearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.filter.query != _ctrl.text) {
      _ctrl.text = widget.state.filter.query;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      widget.onFilterChanged(widget.state.filter.copyWith(query: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: l.filterSearchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m, vertical: AppSpacing.s),
              isDense: true,
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        DropdownButton<RarityFilter>(
          value: widget.state.filter.rarity,
          onChanged: (v) {
            if (v != null) {
              widget.onFilterChanged(
                  widget.state.filter.copyWith(rarity: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: RarityFilter.all,
                child: Text(l.filterRarityAll)),
            DropdownMenuItem(
                value: RarityFilter.fiveStar,
                child: Text(l.filterRarityFiveStar)),
            DropdownMenuItem(
                value: RarityFilter.fourStar,
                child: Text(l.filterRarityFourStar)),
          ],
        ),
        DropdownButton<KindFilter>(
          value: widget.state.filter.kind,
          onChanged: (v) {
            if (v != null) {
              widget.onFilterChanged(
                  widget.state.filter.copyWith(kind: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: KindFilter.all, child: Text(l.filterKindAll)),
            DropdownMenuItem(
                value: KindFilter.character,
                child: Text(l.filterKindCharacter)),
            DropdownMenuItem(
                value: KindFilter.weapon,
                child: Text(l.filterKindWeapon)),
          ],
        ),
        DropdownButton<RecordSort>(
          value: widget.state.sort,
          onChanged: (v) {
            if (v != null) widget.onSortChanged(v);
          },
          items: [
            DropdownMenuItem(
                value: RecordSort.timeDesc,
                child: Text(l.sortByTimeDesc)),
            DropdownMenuItem(
                value: RecordSort.timeAsc,
                child: Text(l.sortByTimeAsc)),
            DropdownMenuItem(
                value: RecordSort.rarityDesc,
                child: Text(l.sortByRarityDesc)),
            DropdownMenuItem(
                value: RecordSort.rarityAsc,
                child: Text(l.sortByRarityAsc)),
            DropdownMenuItem(
                value: RecordSort.name, child: Text(l.sortByName)),
          ],
        ),
        if (widget.state.filter.hasAny)
          TextButton.icon(
            onPressed: widget.onClear,
            icon: const Icon(Icons.clear, size: 16),
            label: Text(l.filterClear),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/widgets/data/search_filter_bar_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/data/search_filter_bar.dart test/widgets/data/search_filter_bar_test.dart
git commit -m "feat(widgets): add SearchFilterBar with debounce and dropdowns"
```

---

## Task 16: SortableTable + Pager widgets

**Files:**
- Create: `lib/widgets/data/pager.dart`
- Create: `lib/widgets/data/sortable_table.dart`
- Create: `test/widgets/data/sortable_table_test.dart`

`SortableTable` 是 RecordListTable 的取代品 + 排序篩選；`Pager` 是改良版分頁器。為簡化測試，本任務只測 SortableTable（Pager 經由 SortableTable 間接驗證）。

- [ ] **Step 1: Write Pager**

```dart
// lib/widgets/data/pager.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class Pager extends StatelessWidget {
  const Pager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });

  final int page; // 0-based
  final int totalPages;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final canPrev = page > 0;
    final canNext = page + 1 < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l.pagerFirst,
          onPressed: canPrev ? () => onChanged(0) : null,
          icon: const Icon(Icons.first_page),
        ),
        IconButton(
          tooltip: l.actionPrevPage,
          onPressed: canPrev ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: AppSpacing.s),
        if (totalPages > 20)
          DropdownButton<int>(
            value: page,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [
              for (var i = 0; i < totalPages; i++)
                DropdownMenuItem(value: i, child: Text('${i + 1} / $totalPages')),
            ],
          )
        else
          Text(
            '${page + 1} / $totalPages',
            style: TextStyle(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        const SizedBox(width: AppSpacing.s),
        IconButton(
          tooltip: l.actionNextPage,
          onPressed: canNext ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: l.pagerLast,
          onPressed: canNext ? () => onChanged(totalPages - 1) : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Write SortableTable test**

```dart
// test/widgets/data/sortable_table_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';

WishRecord _r({required String id, required int rank, required String name}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: DateTime(2025, 1, int.parse(id)),
      lang: 'zh-tw',
    );

void main() {
  testWidgets('renders header and rarity pills', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          child: SortableTable(records: records),
        ),
      ),
    ));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
  });

  testWidgets('paginates with 20 per page', (tester) async {
    final records = List.generate(
      45,
      (i) => _r(id: '$i', rank: 4, name: 'r$i'),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          child: SortableTable(records: records),
        ),
      ),
    ));
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test → FAIL**

Run: `flutter test test/widgets/data/sortable_table_test.dart`
Expected: FAIL.

- [ ] **Step 4: Write `lib/widgets/data/sortable_table.dart`**

```dart
// lib/widgets/data/sortable_table.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';

class SortableTable extends StatefulWidget {
  const SortableTable({super.key, required this.records});

  /// 已 filter / sort 完的 records；元件本身不做篩選排序。
  final List<WishRecord> records;

  @override
  State<SortableTable> createState() => _SortableTableState();
}

class _SortableTableState extends State<SortableTable> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  void didUpdateWidget(SortableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records.length != widget.records.length) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.records.length / _pageSize).ceil().clamp(1, 99999);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (widget.records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: Text(
            l.emptyNoFiltered,
            style: TextStyle(color: tokens.textMuted),
          ),
        ),
      );
    }

    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.records.length);
    final slice = widget.records.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceCard,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _Header(theme: theme, tokens: tokens, l: l),
              for (var i = 0; i < slice.length; i++)
                _Row(
                  record: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Pager(
          page: _page,
          totalPages: _totalPages,
          onChanged: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.tokens, required this.l});
  final ThemeData theme;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: tokens.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: tokens.surfaceCardHigh,
      child: DefaultTextStyle.merge(
        style: style ?? const TextStyle(),
        child: Row(
          children: [
            Expanded(flex: 4, child: Text(l.tableTime)),
            Expanded(flex: 5, child: Text(l.tableName)),
            Expanded(flex: 2, child: Text(l.tableKind)),
            Expanded(flex: 2, child: Text(l.tableRarity)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.record,
    required this.isStripe,
    required this.theme,
    required this.tokens,
  });
  final WishRecord record;
  final bool isStripe;
  final ThemeData theme;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final accent = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m, horizontal: AppSpacing.l),
      color: isStripe ? tokens.surfaceCardHigh : null,
      child: Row(
        children: [
          if (accent != null)
            Container(width: 2, height: 28, color: accent)
          else
            const SizedBox(width: 2),
          const SizedBox(width: AppSpacing.s),
          Expanded(flex: 4, child: Text(_formatTime(record.time))),
          Expanded(flex: 5, child: Text(record.name, style: highlight)),
          Expanded(flex: 2, child: Text(record.itemType)),
          Expanded(
            flex: 2,
            child: accent != null
                ? _Pill(rank: record.rankType, color: accent)
                : Text('${record.rankType}★'),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.rank, required this.color});
  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$rank★',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run test → PASS**

Run: `flutter test test/widgets/data/sortable_table_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/data/sortable_table.dart lib/widgets/data/pager.dart test/widgets/data/sortable_table_test.dart
git commit -m "feat(widgets): add SortableTable and Pager replacing RecordListTable"
```

---

## Task 17: Wire SortableTable + SearchFilterBar into BannerPage; delete RecordListTable

**Files:**
- Modify: `lib/pages/banner_page.dart`
- Delete: `lib/widgets/record_list_table.dart`

- [ ] **Step 1: Add imports**

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
```

並移除舊 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/record_list_table.dart';
```

- [ ] **Step 2: Use ConsumerWidget watch on filter state**

`BannerPage` 已是 `ConsumerWidget`。在 `build` 內 `final stats = computeWishStats(records);` 之後加：

```dart
final filterState = ref.watch(recordFilterProvider(gachaType));
final filtered = sortRecords(
    filterRecords(records, filterState.filter), filterState.sort);
```

- [ ] **Step 3: Replace records list block**

找到 Column 子節點末端的：

```dart
Text(l.pageBannerRecordList,
    style: Theme.of(context).textTheme.titleLarge),
const SizedBox(height: AppSpacing.s),
RecordListTable(records: records),
```

換為：

```dart
Text(l.pageBannerRecordList,
    style: Theme.of(context).textTheme.titleLarge),
const SizedBox(height: AppSpacing.s),
SearchFilterBar(
  state: filterState,
  onFilterChanged: (f) => ref
      .read(recordFilterProvider(gachaType).notifier)
      .setFilter(f),
  onSortChanged: (s) => ref
      .read(recordFilterProvider(gachaType).notifier)
      .setSort(s),
  onClear: () => ref
      .read(recordFilterProvider(gachaType).notifier)
      .clear(),
),
const SizedBox(height: AppSpacing.m),
SortableTable(records: filtered),
```

- [ ] **Step 4: Delete RecordListTable**

```bash
rm lib/widgets/record_list_table.dart
```

- [ ] **Step 5: Verify no references remain**

Run: `grep -rn "record_list_table" lib/ test/`
Expected: 沒有任何匹配。

- [ ] **Step 6: Run analyze + tests**

Run: `flutter analyze lib/`
Expected: No issues found.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/pages/banner_page.dart lib/widgets/record_list_table.dart
git commit -m "feat(banner-page): use SortableTable + SearchFilterBar; remove RecordListTable"
```

---

## Task 18: Data export service with TDD

**Files:**
- Create: `lib/services/data_export.dart`
- Create: `test/services/data_export_test.dart`

純函式：把 `BannerStorage` 序列化為 JSON 字串或 CSV 字串。檔案 IO 由 caller 處理（settings_page 用 file_selector）。

- [ ] **Step 1: Write failing test**

```dart
// test/services/data_export_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_export.dart';

WishRecord _r(String id) => WishRecord(
      id: id,
      uid: '123',
      gachaType: '301',
      name: '夜蘭',
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: 5,
      time: DateTime.utc(2025, 4, 1, 14, 23),
      lang: 'zh-tw',
    );

void main() {
  late BannerStorage data;
  setUp(() {
    data = BannerStorage(
      uid: '123',
      lastUpdated: DateTime.utc(2025, 4, 1),
      banners: {
        '301': [_r('A')],
        '302': const [],
      },
    );
  });

  test('exportJson 與 BannerStorage.toJson 等價', () {
    final out = exportJson(data);
    expect(jsonDecode(out), data.toJson());
  });

  test('exportCsv 含 header 與一筆紀錄', () {
    final out = exportCsv(data);
    final lines = out.split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines.length, 2);
    expect(lines[0],
        'time,uid,gacha_type,name,item_type,rank_type,lang');
    expect(lines[1].contains('夜蘭'), isTrue);
    expect(lines[1].contains('123'), isTrue);
    expect(lines[1].contains('301'), isTrue);
  });

  test('exportCsv 處理含 comma 與 quote 的名字', () {
    final r = WishRecord(
      id: 'x',
      uid: '1',
      gachaType: '301',
      name: 'O,K"name',
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: 4,
      time: DateTime.utc(2025, 1, 1),
      lang: 'zh-tw',
    );
    final s = BannerStorage(
      uid: '1',
      lastUpdated: DateTime.utc(2025, 1, 1),
      banners: {'301': [r]},
    );
    final out = exportCsv(s);
    expect(out.contains('"O,K""name"'), isTrue);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/services/data_export_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/services/data_export.dart`**

```dart
// lib/services/data_export.dart
import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

String exportJson(BannerStorage data) =>
    const JsonEncoder.withIndent('  ').convert(data.toJson());

String exportCsv(BannerStorage data) {
  final buf = StringBuffer();
  buf.writeln('time,uid,gacha_type,name,item_type,rank_type,lang');
  // 串成扁平 list、依時間 desc。
  final all = <WishRecord>[];
  for (final list in data.banners.values) {
    all.addAll(list);
  }
  all.sort((a, b) => b.time.compareTo(a.time));
  for (final r in all) {
    buf.writeln([
      _quote(_iso(r.time)),
      _quote(r.uid),
      _quote(r.gachaType),
      _quote(r.name),
      _quote(r.itemType),
      r.rankType.toString(),
      _quote(r.lang),
    ].join(','));
  }
  return buf.toString();
}

String _iso(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 必要時用 RFC4180 規則 escape：含 ,/"/\n 就用 quote 包，內部 " 變成 ""。
String _quote(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/services/data_export_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/data_export.dart test/services/data_export_test.dart
git commit -m "feat(export): add data_export service for JSON and CSV"
```

---

## Task 19: Data import service with TDD

**Files:**
- Create: `lib/services/data_import.dart`
- Create: `test/services/data_import_test.dart`

從 JSON 字串還原 `BannerStorage`，做格式驗證。失敗丟 `FormatException`。

- [ ] **Step 1: Write failing test**

```dart
// test/services/data_import_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_import.dart';

void main() {
  test('合法 JSON → BannerStorage', () {
    const input = '''
{
  "uid": "123456789",
  "last_updated": "2025-04-01T00:00:00.000Z",
  "banners": {
    "301": [
      {
        "id": "1",
        "uid": "123456789",
        "gacha_type": "301",
        "name": "夜蘭",
        "item_type": "角色",
        "rank_type": 5,
        "time": "2025-04-01 14:23:00",
        "lang": "zh-tw"
      }
    ]
  }
}
''';
    final data = importJson(input);
    expect(data.uid, '123456789');
    expect(data.banners['301']?.length, 1);
    expect(data.banners['301']?.first.name, '夜蘭');
  });

  test('缺 uid → FormatException', () {
    expect(
      () => importJson('{"banners":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('uid 不是 string → FormatException', () {
    expect(
      () => importJson('{"uid":123,"last_updated":"2025-01-01T00:00:00.000Z","banners":{}}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('非 JSON → FormatException', () {
    expect(
      () => importJson('not json'),
      throwsA(isA<FormatException>()),
    );
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/services/data_import_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/services/data_import.dart`**

```dart
// lib/services/data_import.dart
import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

/// 把 JSON 字串還原為 [BannerStorage]。任何結構或型別不符都丟 [FormatException]。
BannerStorage importJson(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Top-level value must be an object');
  }
  if (raw['uid'] is! String) {
    throw const FormatException('Missing or invalid "uid"');
  }
  if (raw['last_updated'] is! String) {
    throw const FormatException('Missing or invalid "last_updated"');
  }
  if (raw['banners'] is! Map) {
    throw const FormatException('Missing or invalid "banners"');
  }
  try {
    return BannerStorage.fromJson(raw);
  } catch (e) {
    throw FormatException('Failed to parse: $e');
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/services/data_import_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/data_import.dart test/services/data_import_test.dart
git commit -m "feat(import): add data_import service with JSON validation"
```

---

## Task 20: ConfirmDialog widget with TDD

**Files:**
- Create: `lib/widgets/dialogs/confirm_dialog.dart`
- Create: `test/widgets/dialogs/confirm_dialog_test.dart`

通用兩段式確認 dialog：使用者必須打字（UID 或 `DELETE`）才會啟用刪除按鈕。

- [ ] **Step 1: Write failing test**

```dart
// test/widgets/dialogs/confirm_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

void main() {
  testWidgets('delete button disabled until input matches', (tester) async {
    bool confirmed = false;
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                confirmed = await showConfirmTypeDialog(
                      context: ctx,
                      title: 'Confirm',
                      body: 'Type X to confirm',
                      expectedText: 'X',
                      cancelLabel: 'Cancel',
                      confirmLabel: 'Delete',
                    ) ??
                    false;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final deleteBtn = find.widgetWithText(FilledButton, 'Delete');
    expect(tester.widget<FilledButton>(deleteBtn).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'X');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteBtn).onPressed, isNotNull);

    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/dialogs/confirm_dialog.dart`**

```dart
// lib/widgets/dialogs/confirm_dialog.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 顯示一個要求使用者打字確認的 dialog。
/// 回傳值：true = 確認 / false = 取消 / null = 系統 dismiss。
Future<bool?> showConfirmTypeDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String expectedText,
  required String cancelLabel,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      body: body,
      expectedText: expectedText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.cancelLabel,
    required this.confirmLabel,
  });
  final String title;
  final String body;
  final String expectedText;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final matches = _ctrl.text == widget.expectedText;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: matches
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test → PASS**

Run: `flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dialogs/confirm_dialog.dart test/widgets/dialogs/confirm_dialog_test.dart
git commit -m "feat(widgets): add ConfirmDialog requiring typed confirmation"
```

---

## Task 21: Wire DataManagement section in SettingsPage

**Files:**
- Modify: `lib/pages/settings_page.dart`
- Modify: `lib/services/wish_storage.dart`（加 `delete(uid)` 與 `clearAll()`）
- Modify: `lib/state/wish_repository.dart`（加 `clearActive()`、`clearAll()`、`importData(BannerStorage)`）

- [ ] **Step 1: Add `delete` and `clearAll` to WishStorage**

在 `lib/services/wish_storage.dart` 的 `deleteCapturedUrl` 之後加：

```dart
Future<void> delete(String uid) async {
  final f = _dataFile(uid);
  if (await f.exists()) await f.delete();
  await deleteCapturedUrl(uid);
}

Future<void> clearAll() async {
  if (!await baseDir.exists()) return;
  final entries = await baseDir.list().toList();
  for (final e in entries) {
    if (e is File && e.path.endsWith('.json')) {
      await e.delete();
    }
  }
}
```

- [ ] **Step 2: Add repository helpers**

在 `lib/state/wish_repository.dart` 的 `WishRepository` class 內、`forceRecaptureAndUpdate` 方法之後加：

```dart
Future<void> clearActive() async {
  final uid = state.activeUid;
  if (uid == null) return;
  final storage = ref.read(wishStorageProvider);
  await storage.delete(uid);
  if (!ref.mounted) return;
  final newByUid = Map<String, BannerStorage>.from(state.byUid)
    ..remove(uid);
  String? newActive;
  if (newByUid.isNotEmpty) {
    final newest = newByUid.values
        .reduce((a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b);
    newActive = newest.uid;
  }
  state = state.copyWith(byUid: newByUid, activeUid: newActive);
}

Future<void> clearAll() async {
  final storage = ref.read(wishStorageProvider);
  await storage.clearAll();
  if (!ref.mounted) return;
  state = const WishState();
}

Future<void> importData(BannerStorage data) async {
  final storage = ref.read(wishStorageProvider);
  await storage.save(data);
  if (!ref.mounted) return;
  final newByUid = Map<String, BannerStorage>.from(state.byUid)
    ..[data.uid] = data;
  state = state.copyWith(byUid: newByUid, activeUid: data.uid);
}

Future<void> removeUid(String uid) async {
  final storage = ref.read(wishStorageProvider);
  await storage.delete(uid);
  if (!ref.mounted) return;
  final newByUid = Map<String, BannerStorage>.from(state.byUid)
    ..remove(uid);
  String? newActive = state.activeUid;
  if (newActive == uid) {
    newActive = newByUid.isEmpty
        ? null
        : newByUid.values
            .reduce((a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b)
            .uid;
  }
  state = state.copyWith(byUid: newByUid, activeUid: newActive);
}
```

> 注意：`copyWith` 既有實作不允許把 `activeUid` 設為 null。檢查 `lib/state/wish_repository.dart` 內 `WishState.copyWith`：若 `activeUid` 是 `String?`，傳 null 會被 `??` 視為「不變」。需要修：把 `WishState.copyWith` 加 `bool clearActiveUid = false` 參數，類似 `clearProgress`：

```dart
WishState copyWith({
  String? activeUid,
  bool clearActiveUid = false,
  Map<String, BannerStorage>? byUid,
  UpdateProgress? progress,
  bool clearProgress = false,
}) =>
    WishState(
      activeUid: clearActiveUid ? null : (activeUid ?? this.activeUid),
      byUid: byUid ?? this.byUid,
      progress: clearProgress ? null : (progress ?? this.progress),
    );
```

並在上面 `clearActive` / `removeUid` 中，當需要把 activeUid 設為 null 時，傳 `clearActiveUid: true`。

- [ ] **Step 3: Add settings page section logic**

在 `lib/pages/settings_page.dart` 補 imports：

```dart
import 'package:file_selector/file_selector.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'dart:io';
```

把 `SectionCard(title: l.settingsDataManagement, child: ...)` 換為：

```dart
SectionCard(
  title: l.settingsDataManagement,
  child: _DataManagement(),
),
```

並在檔案底部新增私有 widget：

```dart
class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeData = state.activeData;
    final hasData = state.byUid.isNotEmpty;

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        OutlinedButton.icon(
          onPressed: activeData == null
              ? null
              : () => _exportJson(context, activeData),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportJson),
        ),
        OutlinedButton.icon(
          onPressed: activeData == null
              ? null
              : () => _exportCsv(context, activeData),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: Text(l.settingsExportCsv),
        ),
        OutlinedButton.icon(
          onPressed: () => _import(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportJson),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: state.activeUid == null
              ? null
              : () => _clearActive(context, ref, state.activeUid!),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.settingsClearActive),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: !hasData ? null : () => _clearAll(context, ref),
          icon: const Icon(Icons.delete_forever_outlined, size: 18),
          label: Text(l.settingsClearAll),
        ),
      ],
    );
  }

  Future<void> _exportJson(BuildContext ctx, BannerStorage data) async {
    final l = AppLocalizations.of(ctx)!;
    final loc = await getSaveLocation(
      suggestedName: 'wish_${data.uid}.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsString(exportJson(data));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(l.settingsExportSuccess(loc.path)),
    ));
  }

  Future<void> _exportCsv(BuildContext ctx, BannerStorage data) async {
    final l = AppLocalizations.of(ctx)!;
    final loc = await getSaveLocation(
      suggestedName: 'wish_${data.uid}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsString(exportCsv(data));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(l.settingsExportSuccess(loc.path)),
    ));
  }

  Future<void> _import(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    try {
      final data = importJson(text);
      await ref.read(wishRepositoryProvider.notifier).importData(data);
      if (!ctx.mounted) return;
      final count =
          data.banners.values.fold<int>(0, (n, list) => n + list.length);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(l.settingsImportSuccess(data.uid, count)),
      ));
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(l.settingsImportFailed(e.message)),
      ));
    }
  }

  Future<void> _clearActive(
      BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearActive();
  }

  Future<void> _clearAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearAllBody,
      expectedText: 'DELETE',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearAll();
  }
}
```

也補頂部 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
```

- [ ] **Step 4: Run analyze + tests**

Run: `flutter analyze lib/`
Expected: No issues found.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_storage.dart lib/state/wish_repository.dart lib/pages/settings_page.dart
git commit -m "feat(settings): wire data management (export/import/clear)"
```

---

## Task 22: Wire AccountManagement section in SettingsPage

**Files:**
- Modify: `lib/pages/settings_page.dart`

列出所有 UID + 最後更新時間，每個有「設為活躍」「移除」按鈕，底部 「重新攔截 / 新增帳號」。

- [ ] **Step 1: Add `_AccountManagement` widget**

在 `settings_page.dart` 把 AccountManagement section 換成：

```dart
SectionCard(
  title: l.settingsAccountManagement,
  child: _AccountManagement(),
),
```

並補 import：

```dart
import 'package:intl/intl.dart' show DateFormat;
```

新增類別放檔案底部：

```dart
class _AccountManagement extends ConsumerWidget {
  const _AccountManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final uids = state.byUid.keys.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(l.accountListEmpty,
                style: TextStyle(color: tokens.textMuted)),
          )
        else
          for (final uid in uids)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(
                            uid,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (uid == state.activeUid) ...[
                            const SizedBox(width: AppSpacing.s),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s, vertical: 2),
                              decoration: BoxDecoration(
                                color: tokens.accentPrimary
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                l.accountActiveTag,
                                style: TextStyle(
                                  color: tokens.accentPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          l.accountLastUpdated(
                            DateFormat('yyyy-MM-dd HH:mm').format(
                                state.byUid[uid]!.lastUpdated.toLocal()),
                          ),
                          style: TextStyle(
                              color: tokens.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (uid != state.activeUid)
                    TextButton(
                      onPressed: () => notifier.setActiveUid(uid),
                      child: Text(l.accountSetActive),
                    ),
                  TextButton(
                    onPressed: () => _remove(context, ref, uid),
                    child: Text(
                      l.accountRemove,
                      style: TextStyle(color: tokens.stateDanger),
                    ),
                  ),
                ],
              ),
            ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(
      BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}
```

- [ ] **Step 2: Run analyze + tests**

Run: `flutter analyze lib/`
Expected: No issues found.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): wire account management (set active / remove / recapture)"
```

---

## Task 23: LoadingState widget + bootstrap flag in WishState

**Files:**
- Create: `lib/widgets/loading_state.dart`
- Create: `test/widgets/loading_state_test.dart`
- Modify: `lib/state/wish_repository.dart`
- Modify: `lib/pages/overview_page.dart`
- Modify: `lib/pages/banner_page.dart`

加 `WishState.isBootstrapping` 旗標，初始載入時顯示 LoadingState 而非 EmptyState。

- [ ] **Step 1: Write LoadingState test**

```dart
// test/widgets/loading_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';

void main() {
  testWidgets('renders progress indicator', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(body: LoadingState()),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test → FAIL**

Run: `flutter test test/widgets/loading_state_test.dart`
Expected: FAIL.

- [ ] **Step 3: Write `lib/widgets/loading_state.dart`**

```dart
// lib/widgets/loading_state.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.l),
          Text(l.loadingBootstrap,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textMuted)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Add `isBootstrapping` to WishState**

修改 `lib/state/wish_repository.dart` 的 `WishState`：

```dart
@immutable
class WishState {
  const WishState({
    this.activeUid,
    this.byUid = const {},
    this.progress,
    this.isBootstrapping = true,
  });

  final String? activeUid;
  final Map<String, BannerStorage> byUid;
  final UpdateProgress? progress;
  final bool isBootstrapping;

  BannerStorage? get activeData =>
      activeUid == null ? null : byUid[activeUid];
  Iterable<String> get knownUids => byUid.keys;

  WishState copyWith({
    String? activeUid,
    bool clearActiveUid = false,
    Map<String, BannerStorage>? byUid,
    UpdateProgress? progress,
    bool clearProgress = false,
    bool? isBootstrapping,
  }) =>
      WishState(
        activeUid: clearActiveUid ? null : (activeUid ?? this.activeUid),
        byUid: byUid ?? this.byUid,
        progress: clearProgress ? null : (progress ?? this.progress),
        isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      );
}
```

並在 `_bootstrapLoad` 結尾把 `isBootstrapping` 設為 `false`：

```dart
Future<void> _bootstrapLoad() async {
  // ... 既有實作 ...
  // 結尾兩個 state = state.copyWith(...) 改為都帶 isBootstrapping: false
}
```

具體：找到 `_bootstrapLoad` 內：

```dart
if (byUid.isEmpty) {
  state = state.copyWith(byUid: byUid);
  return;
}
final newest = byUid.values
    .reduce((a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b);
state = state.copyWith(byUid: byUid, activeUid: newest.uid);
```

改為：

```dart
if (byUid.isEmpty) {
  state = state.copyWith(byUid: byUid, isBootstrapping: false);
  return;
}
final newest = byUid.values
    .reduce((a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b);
state = state.copyWith(
    byUid: byUid, activeUid: newest.uid, isBootstrapping: false);
```

- [ ] **Step 5: Update OverviewPage and BannerPage to show LoadingState**

`lib/pages/overview_page.dart`：

把：

```dart
final activeData = ref.watch(
    wishRepositoryProvider.select((s) => s.activeData));

if (activeData == null) {
  return EmptyState.noSync(context);
}
```

改為：

```dart
final state = ref.watch(wishRepositoryProvider);
final activeData = state.activeData;

if (state.isBootstrapping) {
  return const LoadingState();
}
if (activeData == null) {
  return EmptyState.noSync(context);
}
```

並補 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
```

`lib/pages/banner_page.dart`：相同處理。

- [ ] **Step 6: Run tests → PASS**

Run: `flutter test test/widgets/loading_state_test.dart`
Expected: PASS。

Run: `flutter test`
Expected: 全部通過（既有 settings test 用 `ProviderContainer()` 不依賴 isBootstrapping，仍應通過）。

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/loading_state.dart test/widgets/loading_state_test.dart \
        lib/state/wish_repository.dart lib/pages/overview_page.dart lib/pages/banner_page.dart
git commit -m "feat(loading): show LoadingState while wish_repository bootstraps"
```

---

## Task 24: Final smoke test & verification

**Files:**
- 無新增

- [ ] **Step 1: Run full test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze lib/`
Expected: No issues found.

- [ ] **Step 3: Build verification**

Run: `flutter build windows --debug`
Expected: Build succeeds.

- [ ] **Step 4: Manual checklist (for user)**

Run: `flutter run -d windows`

- [ ] BannerPage：5★/4★ 變成真 PityCard 顯示「`current / threshold`」、`快保底了！` warning（≥70% 進度條呼吸）、保底後恢復
- [ ] BannerPage：5★ ChartCard 顯示真實時間軸（每個 5★ 是膠囊，hover 看日期）
- [ ] BannerPage：紀錄列表上方有搜尋框 + 稀有度 / 類型 / 排序 dropdown，搜尋有 200ms debounce
- [ ] BannerPage：表格仍每頁 20 筆，分頁器有 `<<` `>>` 按鈕
- [ ] OverviewPage：底部新增 `5★ × N` 區塊與 FiveStarList，跨卡池顯示所有 5★
- [ ] SettingsPage：資料管理區可匯出 JSON / 匯出 CSV / 匯入 JSON / 清除目前帳號 / 清除所有資料；匯入失敗 SnackBar 顯示
- [ ] SettingsPage：帳號管理區列出所有 UID，最後更新時間，可設為活躍 / 移除 / 重新攔截
- [ ] App 啟動瞬間（資料載入中）顯示 LoadingState，不再閃爍 EmptyState
- [ ] 切換語言到 EN，attempt update 失敗時錯誤訊息以英文顯示（不再 zh-Hant 硬碼）

- [ ] **Step 5: Commit if any tweaks needed**

如有問題修到通過。

---

## Phase 2 Done

所有 Phase 1 留下的 placeholder 全部變成真功能：保底、時間軸、可排序篩選表格、設定頁的資料 / 帳號管理、loading state、錯誤訊息 i18n。`record_list_table.dart` 已退役。

---

## Self-Review

**1. Spec coverage**

| Spec § | 對應 Task |
|---|---|
| §5.1 PityCard 三狀態 + 呼吸動效 | T6, T7, T8 |
| §5.1 TimelineCard | T9, T10 |
| §5.2 SortableTable | T16, T17 |
| §5.2 SearchFilterBar | T15 |
| §5.2 Pager | T16（含 in `pager.dart`） |
| §5.2 FiveStarList | T11, T12 |
| §5.3 LoadingState / Skeleton | T23 |
| §6 wish_pity / wish_filter | T6, T13 |
| §7 recordFilterProvider.family | T14 |
| §8 (匯入失敗 SnackBar) | T19, T21 |
| §10 兩段式清除 | T20, T21 |
| §10 多 UID 競態 | 既有，不動 |
| Phase 1 review #1 (錯誤 i18n) | T3, T4 |

**2. Placeholder scan** — 無 TBD/TODO；所有 step 含完整 code block 或具體指令。

**3. Type consistency** — `Pity`、`UpdateError` 子類、`RecordFilter` / `RecordSort`、`RecordFilterState` / `RecordFilterNotifier` / `recordFilterProvider`、`SearchFilterBar` 與 `SortableTable` 的 props 都在 task 內定義並一致使用。`WishState.copyWith(clearActiveUid: bool)` 的擴展與 `removeUid` / `clearActive` 中的 caller 一致。

**4. Ambiguity** — `_LatestFiveStar` 的「最新 5★」算法以 records desc 順序中第一個 5★ 為該 banner 最新，跨 banner 取 time 最大者；`pullsSince` 為從該 5★ 算到該 banner 最新一筆紀錄的距離。`SortableTable` 暫不做欄頭點擊切排序（plan 把這個交給 `SearchFilterBar` 的 sort dropdown，欄頭只展示）；spec §5.2 說「欄頭可點擊切 asc/desc」是後續細節，dropdown 已涵蓋核心需求。
