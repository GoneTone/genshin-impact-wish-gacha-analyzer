# BannerPage 紀錄表分頁、排序與新增欄位設計

- 日期：2026-05-10
- 範圍：`lib/widgets/data/sortable_table.dart`、`lib/widgets/data/pager.dart`、`lib/widgets/data/search_filter_bar.dart`、`lib/services/wish_filter.dart`、`lib/state/record_filter.dart`，新增 `lib/services/wish_row.dart`
- 不影響：`OverviewPage` 與 `FiveStarList`

## 目標

針對 `BannerPage` 上的紀錄表（5 個卡池共用 `SortableTable`）做三項調整：

1. 換頁元件 `Pager` 永遠顯示「下拉選擇頁數」（含 `totalPages == 1`），不再受目前 `> 20` 門檻限制。
2. 排序操作從 `SearchFilterBar` 的下拉選單改為**點擊表頭欄位**，採三態循環：第 1 次降序、第 2 次升序、第 3 次取消（回到原始時間 desc）。
3. 紀錄表新增兩個欄位：**總抽數**、**保底內抽數**。

## 非目標

- 不改 `OverviewPage` 的 `FiveStarList`。
- 不引入每頁筆數可調 / 多欄複合排序 / 排序狀態持久化（YAGNI）。
- 不改 `WishRecord` model；計算欄位放在新的 service 層 dataclass。

## 欄位語意

- **總抽數（`totalIndex`）**：該抽在「該卡池所有抽」中的累積序號（asc）；最早一筆 = `1`，最新一筆 = N。
- **保底內抽數（`fiveStarPityIndex`）**：以 5★ 為基準，到該抽為止距上一個 5★ 後的第幾抽（含自己）。
  - 5★ 那一抽 = 抵達該 5★ 的累積值（例如「第 67 抽出 5★」就是 `67`）。
  - 下一抽從 `1` 重新累計。
  - 若該卡池從未出現 5★，則持續累計，數值與 `totalIndex` 相同。
- 兩欄均依**原始未篩選 records** 計算：篩選後欄位值不會改變（`totalIndex = 237` 的那筆無論篩什麼仍顯示 `237`）。

## 架構

```
records (desc by time, 來自 wish_repository)
  ↓ buildRecordRows()                 ← 新 service：計算 totalIndex / fiveStarPityIndex
List<RecordRow>
  ↓ filterRecordRows(filter)          ← 既有 RecordFilter 條件下移到 row 層
List<RecordRow>
  ↓ sortRecordRows(TableSort?)        ← 取代舊 sortRecords + RecordSort
List<RecordRow>
  ↓
SortableTable                         ← 純展示，不再做 filter / sort，只負責表頭點擊與分頁
```

## 資料層

### `lib/services/wish_row.dart`（新檔）

```dart
@immutable
class RecordRow {
  const RecordRow({
    required this.record,
    required this.totalIndex,
    required this.fiveStarPityIndex,
  });
  final WishRecord record;
  final int totalIndex;
  final int fiveStarPityIndex;
}

/// records 必須以時間 desc 排序（與 wish_repository 一致）。
List<RecordRow> buildRecordRows(List<WishRecord> records);
```

實作：將 records 倒成 asc 走一遍，邊走邊累計 `totalIndex`（從 1）與 `pity`（每碰到 5★ 就把當下值寫入 row 後歸零，下一抽從 1 重新累計）；輸出再 reverse 成 desc，與輸入順序一致。空陣列回 `const []`。

### `lib/services/wish_filter.dart`（重做排序部分）

```dart
enum SortColumn { time, name, kind, rarity, totalIndex, fiveStarPity }
enum SortDirection { asc, desc }

@immutable
class TableSort {
  const TableSort({required this.column, required this.direction});
  final SortColumn column;
  final SortDirection direction;
}

List<RecordRow> filterRecordRows(List<RecordRow> rows, RecordFilter f);
List<RecordRow> sortRecordRows(List<RecordRow> rows, TableSort? sort);
```

- `RecordFilter` 結構與條件不變；`filterRecordRows` 把同一組條件套用在 `row.record` 上。
- 舊 `List<WishRecord> filterRecords(...)` 函式刪除（呼叫者僅 `BannerPage`，全部改用 `filterRecordRows`）。
- `enum RecordSort` 與舊 `List<WishRecord> sortRecords(...)` 函式刪除。
- `sortRecordRows`：
  - `sort == null` → 不排序，回傳 `[...rows]`（保留 records 原始 desc by time 順序）。
  - 主鍵：依 `SortColumn` 對應 `record.time` / `record.name` / `record.itemType` / `record.rankType` / `totalIndex` / `fiveStarPityIndex`。
  - 二級鍵（主鍵相等時）：`record.time` desc，與既有 `rarityDesc` 行為一致。

### `lib/state/record_filter.dart`（改）

```dart
class RecordFilterState {
  final RecordFilter filter;
  final TableSort? sort;   // null = 取消排序
}

class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() =>
      const RecordFilterState(filter: RecordFilter(), sort: null);

  void setFilter(RecordFilter f);

  /// 三態循環：null/其他欄 → desc → asc → null
  void cycleSort(SortColumn col);

  void clear();   // filter + sort 都歸零
}
```

`copyWith` 對 nullable 處理：直接以 `RecordFilterState(filter: ..., sort: ...)` 建構新值（不用 sentinel），呼叫端負責傳完整狀態。

## UI

### `SortableTable`（改寫）

- 屬性：`SortableTable({required List<RecordRow> rows, required TableSort? sort, required ValueChanged<SortColumn> onSortColumnTapped})`
  - 三態循環本身放在 notifier 端（`cycleSort`），UI 只回拋「使用者點了哪個欄位」。
- 欄位順序與 `Expanded` flex：
  - `時間 4`、`名稱 5`、`類型 2`、`稀有度 2`、`總抽數 2`、`保底內 2`
- 數字欄（總抽數、保底內）右對齊、`FontFeature.tabularFigures()`。
- 表頭每欄改為 `InkWell`（包整個 `Expanded` 內的 Row），右側放排序方向圖示：
  - 非當前排序欄、或 `sort == null` → `Icons.unfold_more`（淺灰）
  - 當前欄 + desc → `Icons.arrow_downward`
  - 當前欄 + asc → `Icons.arrow_upward`
- 點擊 → 呼叫 `onSortColumnTapped(column)`。
- 翻頁重置：沿用既有條件 `oldWidget.rows.length != widget.rows.length` 才 `_page = 0`。Filter 變化通常造成長度變化，會自然重置；Sort 變化長度不變、刻意不重置（保留使用者當前頁的瀏覽位置，符合一般表格操作直覺）。
- 空狀態仍走 `emptyNoFiltered`。

### `Pager`（簡化）

- 移除 `if (totalPages > 20) ... else ...` 分支，永遠渲染 `DropdownButton<int>`。
- `totalPages == 1` 時，dropdown 仍顯示，內容 `1 / 1`，左右翻頁鍵自然 disable。
- 保留首頁 / 上一頁 / 下一頁 / 末頁四顆 IconButton。

### `SearchFilterBar`（瘦身）

- 移除 `DropdownButton<RecordSort>` 整段。
- 屬性移除 `onSortChanged` 與 `state.sort` 相關引用（state 仍傳入但只用 `filter`）。
- 「Clear」按鈕只清 filter（`RecordFilter.hasAny`），不影響 sort。Sort 透過再次點擊到第三態歸 null。
- 其他（搜尋框 / 稀有度 / 類型 dropdown）不動。

### `BannerPage`（串接）

```dart
final filterState = ref.watch(recordFilterProvider(gachaType));
final rows = buildRecordRows(records);
final filtered = filterRecordRows(rows, filterState.filter);
final sorted = sortRecordRows(filtered, filterState.sort);

SortableTable(
  rows: sorted,
  sort: filterState.sort,
  onSortColumnTapped: (col) => ref
      .read(recordFilterProvider(gachaType).notifier)
      .cycleSort(col),
)
```

`SearchFilterBar` 移除 `onSortChanged` 對應呼叫。

## i18n

`lib/l10n/app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb` 同步更動，並執行 `flutter gen-l10n`。

**新增鍵：**
- `tableTotalIndex` → `總抽數` / `总抽数` / `Total`
- `tableFiveStarPity` → `保底內` / `保底内` / `Pity`
  - 用短字串作 header；完整描述放 `Tooltip`：`tableFiveStarPityTooltip` → `距上一次 5★ 的抽數` / `距上一次 5★ 的抽数` / `Pulls since the last 5★`
- `sortDirectionDesc` / `sortDirectionAsc` / `sortDirectionNone` → 表頭排序圖示的 `Tooltip` 文案：`降序` / `升序` / `點擊排序`（zh-Hans / en 同步）

**移除鍵：**
- `sortByTimeDesc`、`sortByTimeAsc`、`sortByRarityDesc`、`sortByRarityAsc`、`sortByName`

## 邊界與行為

- 空 records → `buildRecordRows` 回 `const []`；`SortableTable` 走 `emptyNoFiltered` 顯示空狀態。
- 篩選後為空但原始非空 → 同樣 `emptyNoFiltered`。
- 從未出現 5★ 的卡池 → 每筆 row 的 `fiveStarPityIndex == totalIndex`，UI 不需特別處理。
- `cycleSort` 換欄時：直接以新欄 `desc` 起步，不必先經 null（與一般表格直覺一致）。
- 排序 `null` 與「點到第三態回到 null」效果相同：UI 表頭圖示恢復 `unfold_more`，列表回到 records 原本 desc by time 順序。
- `pity` 計算只看 `rankType == 5`，不分定向 vs 常駐機率（與 `wish_pity.dart` 一致）。

## 測試

| 檔案 | 涵蓋 |
|------|------|
| `test/services/wish_row_test.dart`（新） | `buildRecordRows`：空陣列 / 全無 5★（pity = totalIndex）/ 多個 5★ 重置 / totalIndex 與 records 順序對齊 |
| `test/services/wish_filter_test.dart`（改） | 移除 `RecordSort` 用例；新增 `sortRecordRows` 6 欄 × asc/desc / `null` 不排序 / 二級鍵 fallback to time desc |
| `test/state/record_filter_test.dart`（新或改） | `cycleSort` 三態循環、跨欄重置為 desc、`clear` 同時清 filter 與 sort |
| `test/widgets/data/sortable_table_test.dart`（改） | 點擊表頭觸發 `onSortColumnTapped` 並顯示對應排序圖示；rows 變更後 `_page` 重置為 0；新欄位顯示正確 |
| `test/widgets/data/pager_test.dart`（如有則改，否則新增） | dropdown 永遠存在（`totalPages == 1` / `> 1` 都顯示）；翻頁鍵 disable 行為 |

## YAGNI 確認

- 不加每頁筆數調整。
- 不加多欄複合排序。
- 不加排序狀態持久化。
- 不動 `FiveStarList` / `OverviewPage`。
- 不引入新的 model 屬性到 `WishRecord`。
