# BannerPage 紀錄表分頁、排序與新增欄位 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `BannerPage` 的 `SortableTable` 改成「永遠下拉換頁、表頭點擊三態排序、新增『總抽數』與『保底內抽數』欄位」三項調整。

**Architecture:** 在 `services/wish_row.dart` 新增純函式 `buildRecordRows`，把每筆紀錄包成 `RecordRow`（內含 totalIndex 與 fiveStarPityIndex，依「未篩選 records」累計）。`wish_filter.dart` 引入 `SortColumn` / `SortDirection` / `TableSort` 模型，重做為 row 級的 filter / sort。`record_filter` 把排序狀態改成 `TableSort?`（null = 取消排序），並提供 `cycleSort` 三態循環。`SortableTable` 改收 `List<RecordRow>` 與 `sort` + 點擊 callback；`Pager` 永遠顯示 dropdown；`SearchFilterBar` 移除排序 dropdown。

**Tech Stack:** Flutter 3.11+ / Dart / flutter_riverpod 3.0 / flutter_test、Flutter 內建 `flutter gen-l10n`（設定見 `l10n.yaml`）。

**規範：** 所有 commit 訊息採用既有風格（`feat:` / `chore:` / `test:` 開頭），一律用 HEREDOC 結尾附 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`。每個 Task 結束 commit。

---

## Task 1: 新增 `services/wish_row.dart`（RecordRow + buildRecordRows）

**Files:**
- Create: `lib/services/wish_row.dart`
- Test: `test/services/wish_row_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/wish_row_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';

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
      time: time ?? DateTime(2025, 1, int.parse(id)),
      lang: 'zh-tw',
    );

void main() {
  group('buildRecordRows', () {
    test('空 list → const []', () {
      expect(buildRecordRows(const []), isEmpty);
    });

    test('totalIndex 從 1 開始累計，最舊=1、最新=N，且輸出順序與輸入一致 (desc by time)', () {
      // input desc by time: id 5,4,3,2,1（time 2025-01-05 ... 01-01）
      final records = [
        _r(id: '5', rank: 3),
        _r(id: '4', rank: 3),
        _r(id: '3', rank: 3),
        _r(id: '2', rank: 3),
        _r(id: '1', rank: 3),
      ];
      final rows = buildRecordRows(records);
      expect(rows.map((r) => r.record.id).toList(), ['5', '4', '3', '2', '1']);
      expect(rows.map((r) => r.totalIndex).toList(), [5, 4, 3, 2, 1]);
    });

    test('全無 5★ → fiveStarPityIndex == totalIndex', () {
      final records = [
        _r(id: '3', rank: 4),
        _r(id: '2', rank: 3),
        _r(id: '1', rank: 4),
      ];
      final rows = buildRecordRows(records);
      expect(rows.map((r) => r.fiveStarPityIndex).toList(), [3, 2, 1]);
    });

    test('5★ 那一抽 = 抵達該 5★ 的累積值，下一抽從 1 重新累計', () {
      // asc 順序視角：1(3★) 2(3★) 3(5★) 4(3★) 5(5★)
      // pity asc:        1    2    3    1    2
      // input desc by time: id 5..1
      final records = [
        _r(id: '5', rank: 5), // pity = 2 (距上一個 5★ 後第 2 抽)
        _r(id: '4', rank: 3), // pity = 1
        _r(id: '3', rank: 5), // pity = 3 (前面 1,2 是 3★，這一抽是 5★)
        _r(id: '2', rank: 3), // pity = 2
        _r(id: '1', rank: 3), // pity = 1
      ];
      final rows = buildRecordRows(records);
      // 以 id 對應驗證 pity
      final byId = {for (final r in rows) r.record.id: r};
      expect(byId['1']!.fiveStarPityIndex, 1);
      expect(byId['2']!.fiveStarPityIndex, 2);
      expect(byId['3']!.fiveStarPityIndex, 3);
      expect(byId['4']!.fiveStarPityIndex, 1);
      expect(byId['5']!.fiveStarPityIndex, 2);
    });

    test('首抽即 5★ → 該抽 pity = 1', () {
      final records = [_r(id: '1', rank: 5)];
      final rows = buildRecordRows(records);
      expect(rows.first.totalIndex, 1);
      expect(rows.first.fiveStarPityIndex, 1);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `flutter test test/services/wish_row_test.dart`
Expected: FAIL（`Target of URI doesn't exist: '...wish_row.dart'`）

- [ ] **Step 3: 實作 `lib/services/wish_row.dart`**

```dart
import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

@immutable
class RecordRow {
  const RecordRow({
    required this.record,
    required this.totalIndex,
    required this.fiveStarPityIndex,
  });

  final WishRecord record;

  /// 該抽在該卡池所有抽中的累積序號（asc）；最舊 = 1，最新 = N。
  final int totalIndex;

  /// 距上一個 5★ 後的第幾抽（含自己）。
  /// 5★ 那一抽 = 抵達該 5★ 的累積值；下一抽從 1 重新累計。
  /// 若該卡池從未出現 5★，則持續累計，與 totalIndex 相同。
  final int fiveStarPityIndex;
}

/// records 必須以時間 desc 排序（與 wish_repository 一致）。
/// 回傳順序與 records 相同（desc by time）。
List<RecordRow> buildRecordRows(List<WishRecord> records) {
  if (records.isEmpty) return const [];
  // 以 asc 順序累計再 reverse，保持輸出順序與輸入一致。
  final asc = records.reversed.toList(growable: false);
  final out = <RecordRow>[];
  var total = 0;
  var pity = 0;
  for (final r in asc) {
    total++;
    pity++;
    out.add(RecordRow(
      record: r,
      totalIndex: total,
      fiveStarPityIndex: pity,
    ));
    if (r.rankType == 5) {
      pity = 0;
    }
  }
  return out.reversed.toList(growable: false);
}
```

- [ ] **Step 4: 跑測試確認 pass**

Run: `flutter test test/services/wish_row_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_row.dart test/services/wish_row_test.dart
git commit -m "$(cat <<'EOF'
feat(services): add RecordRow + buildRecordRows for table metadata

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 在 `services/wish_filter.dart` 新增 `SortColumn` / `SortDirection` / `TableSort` / `filterRecordRows` / `sortRecordRows`（保留舊代碼不刪）

**Files:**
- Modify: `lib/services/wish_filter.dart`
- Test: `test/services/wish_filter_test.dart`

- [ ] **Step 1: 寫失敗測試（追加到 `wish_filter_test.dart` 末尾）**

在現有 `wish_filter_test.dart` 的 `void main()` 內新增 group（保留既有 `filterRecords` / `sortRecords` 測試）。先在檔案頂部 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
```

接著在 `main()` 末加上：

```dart
  group('filterRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records);
    });

    test('5★ + 武器 → 只剩 1 row，且 totalIndex / pity 不變', () {
      final out = filterRecordRows(
          rows,
          const RecordFilter(
              rarity: RarityFilter.fiveStar, kind: KindFilter.weapon));
      expect(out.length, 1);
      expect(out.first.record.id, '1');
      // id '1' 是最舊一筆 → totalIndex = 1
      expect(out.first.totalIndex, 1);
    });

    test('搜尋 query 過濾 row 集', () {
      final out = filterRecordRows(rows, const RecordFilter(query: '夜'));
      expect(out.map((r) => r.record.id), ['5']);
    });
  });

  group('sortRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records);
    });

    test('null → 不排序，保持輸入順序', () {
      final out = sortRecordRows(rows, null);
      expect(out.map((r) => r.record.id), ['5', '4', '3', '2', '1']);
    });

    test('time desc / asc', () {
      final desc = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.time, direction: SortDirection.desc));
      expect(desc.map((r) => r.record.id), ['5', '4', '3', '2', '1']);

      final asc = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.time, direction: SortDirection.asc));
      expect(asc.map((r) => r.record.id), ['1', '2', '3', '4', '5']);
    });

    test('rarity desc：5★ 在前，二級鍵以 time desc', () {
      final out = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.rarity, direction: SortDirection.desc));
      expect(out.first.record.rankType, 5);
      expect(out.last.record.rankType, 3);
      // 兩個 5★（id 5 time 2025-05-01、id 1 time 2025-01-01）→ id 5 在前
      final fives = out.where((r) => r.record.rankType == 5).toList();
      expect(fives.map((r) => r.record.id), ['5', '1']);
    });

    test('rarity asc', () {
      final out = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.rarity, direction: SortDirection.asc));
      expect(out.first.record.rankType, 3);
      expect(out.last.record.rankType, 5);
    });

    test('totalIndex asc / desc', () {
      final asc = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.totalIndex,
              direction: SortDirection.asc));
      expect(asc.map((r) => r.totalIndex), [1, 2, 3, 4, 5]);
      final desc = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.totalIndex,
              direction: SortDirection.desc));
      expect(desc.map((r) => r.totalIndex), [5, 4, 3, 2, 1]);
    });

    test('fiveStarPity asc', () {
      final out = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.fiveStarPity,
              direction: SortDirection.asc));
      // buildRecordRows 由 asc 視角 (id 1..5) 累計，ranks = 5,4,3,4,5：
      //   id 1 pity=1 (寫後重置 0), id 2 pity=1, id 3 pity=2, id 4 pity=3, id 5 pity=4
      // asc by pity → [pity=1 兩個, 2, 3, 4]
      // 二級鍵 time desc → 兩個 pity=1 中 id 2 (02-01) 比 id 1 (01-01) 新
      // 最終：[2, 1, 3, 4, 5]
      expect(out.map((r) => r.record.id), ['2', '1', '3', '4', '5']);
    });

    test('name 排序', () {
      final out = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.name, direction: SortDirection.asc));
      expect(out.length, rows.length);
    });

    test('kind 排序（按 itemType）', () {
      final out = sortRecordRows(
          rows,
          const TableSort(
              column: SortColumn.kind, direction: SortDirection.asc));
      expect(out.length, rows.length);
    });
  });
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `flutter test test/services/wish_filter_test.dart`
Expected: FAIL（`SortColumn` / `TableSort` / `filterRecordRows` / `sortRecordRows` 未定義）

- [ ] **Step 3: 在 `lib/services/wish_filter.dart` 末尾追加新類型與函式（保留舊 `RecordSort`、`filterRecords`、`sortRecords` 不動）**

在檔案頂部加入 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
```

在檔案末尾追加：

```dart
enum SortColumn { time, name, kind, rarity, totalIndex, fiveStarPity }

enum SortDirection { asc, desc }

@immutable
class TableSort {
  const TableSort({required this.column, required this.direction});

  final SortColumn column;
  final SortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is TableSort &&
      other.column == column &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(column, direction);
}

List<RecordRow> filterRecordRows(List<RecordRow> rows, RecordFilter f) {
  final q = f.query.trim().toLowerCase();
  return rows.where((row) {
    final r = row.record;
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

/// sort == null → 不排序，回傳 [...rows]（保留 records 原 desc by time 順序）。
/// 主鍵相同時，二級鍵一律以 record.time desc fallback。
List<RecordRow> sortRecordRows(List<RecordRow> rows, TableSort? sort) {
  final out = [...rows];
  if (sort == null) return out;
  int Function(RecordRow, RecordRow) cmp;
  switch (sort.column) {
    case SortColumn.time:
      cmp = (a, b) => a.record.time.compareTo(b.record.time);
    case SortColumn.name:
      cmp = (a, b) => a.record.name.compareTo(b.record.name);
    case SortColumn.kind:
      cmp = (a, b) => a.record.itemType.compareTo(b.record.itemType);
    case SortColumn.rarity:
      cmp = (a, b) => a.record.rankType.compareTo(b.record.rankType);
    case SortColumn.totalIndex:
      cmp = (a, b) => a.totalIndex.compareTo(b.totalIndex);
    case SortColumn.fiveStarPity:
      cmp = (a, b) => a.fiveStarPityIndex.compareTo(b.fiveStarPityIndex);
  }
  out.sort((a, b) {
    final primary = sort.direction == SortDirection.asc ? cmp(a, b) : cmp(b, a);
    if (primary != 0) return primary;
    return b.record.time.compareTo(a.record.time);
  });
  return out;
}
```

注意 `@immutable` 已存在於檔頂 import（`package:flutter/foundation.dart`）。如果還沒 import，加上。

- [ ] **Step 4: 跑測試確認 pass（包含舊 + 新測試都過）**

Run: `flutter test test/services/wish_filter_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/wish_filter.dart test/services/wish_filter_test.dart
git commit -m "$(cat <<'EOF'
feat(services): add row-level filter/sort and TableSort model

Introduces SortColumn / SortDirection / TableSort and
filterRecordRows / sortRecordRows operating on RecordRow.
Legacy RecordSort / filterRecords / sortRecords kept for now,
to be removed once callers migrate.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `Pager` 永遠顯示 dropdown，新增 pager test，修 sortable_table_test 既有「`1 / 3`」斷言

**Files:**
- Modify: `lib/widgets/data/pager.dart`
- Modify: `test/widgets/data/sortable_table_test.dart`
- Create: `test/widgets/data/pager_test.dart`

- [ ] **Step 1: 寫 `pager_test.dart` 失敗測試**

建立 `test/widgets/data/pager_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 800, child: child),
        ),
      ),
    );

void main() {
  testWidgets('totalPages == 1 也顯示 dropdown', (tester) async {
    await tester.pumpWidget(_wrap(
      Pager(page: 0, totalPages: 1, onChanged: (_) {}),
    ));
    expect(find.byType(DropdownButton<int>), findsOneWidget);
    // 純文字 fallback 不應出現
    expect(find.text('1 / 1'), findsNothing); // text 是 dropdown item，非獨立 Text widget
  });

  testWidgets('totalPages == 5 也顯示 dropdown（不再走 >20 條件）', (tester) async {
    await tester.pumpWidget(_wrap(
      Pager(page: 1, totalPages: 5, onChanged: (_) {}),
    ));
    expect(find.byType(DropdownButton<int>), findsOneWidget);
  });

  testWidgets('首頁 / 上一頁 在第 0 頁 disable', (tester) async {
    await tester.pumpWidget(_wrap(
      Pager(page: 0, totalPages: 3, onChanged: (_) {}),
    ));
    final first = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.first_page),
    );
    final prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(first.onPressed, isNull);
    expect(prev.onPressed, isNull);
  });

  testWidgets('末頁 / 下一頁 在最後一頁 disable', (tester) async {
    await tester.pumpWidget(_wrap(
      Pager(page: 2, totalPages: 3, onChanged: (_) {}),
    ));
    final last = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.last_page),
    );
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(last.onPressed, isNull);
    expect(next.onPressed, isNull);
  });
}
```

- [ ] **Step 2: 跑 pager_test 確認 fail**

Run: `flutter test test/widgets/data/pager_test.dart`
Expected: FAIL（`totalPages == 5 也顯示 dropdown`、`totalPages == 1` 都會 fail，因為現行 `> 20` 條件下走 Text 而非 Dropdown）

- [ ] **Step 3: 改 `lib/widgets/data/pager.dart`**

把第 39–57 行（包含 `if (totalPages > 20)` … `else` … `Text(...)`）整段替換為單一 dropdown：

```dart
        DropdownButton<int>(
          value: page,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (var i = 0; i < totalPages; i++)
              DropdownMenuItem(value: i, child: Text('${i + 1} / $totalPages')),
          ],
        ),
```

刪掉現行 `if/else` 分支。同時可移除 `tokens` 區域變數（若已不再被 build 內其他段使用，跑 `flutter analyze` 會提示，順便清掉 unused import / variable）。

清理後 build 內保留 `final l = AppLocalizations.of(context)!;`，因 IconButton tooltip 仍需 `l.actionPrevPage` 等。

- [ ] **Step 4: 跑 pager_test 確認 pass**

Run: `flutter test test/widgets/data/pager_test.dart`
Expected: All tests PASS

- [ ] **Step 5: 修 `test/widgets/data/sortable_table_test.dart` 中既有「paginates with 20 per page」斷言**

該測試斷言 `expect(find.text('1 / 3'), findsOneWidget);`，現在 dropdown 沒有獨立 `Text('1 / 3')`，會 fail。改為：

```dart
  testWidgets('paginates with 20 per page', (tester) async {
    final records = List.generate(
      45,
      (i) => _r(id: '$i', rank: 4, name: 'r$i'),
    );
    await tester.pumpWidget(_wrap(SortableTable(records: records)));
    // 改為驗證 dropdown 存在且 items 數 = totalPages
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdown.items, hasLength(3));
    expect(dropdown.value, 0);
  });
```

別忘記把 import 補上（如尚未 import `material.dart` 中的 `DropdownButton`，已在 `package:flutter/material.dart` 內，原檔已 import，所以 OK）。

- [ ] **Step 6: 跑兩支測試確認 pass**

Run: `flutter test test/widgets/data/pager_test.dart test/widgets/data/sortable_table_test.dart`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/data/pager.dart test/widgets/data/pager_test.dart test/widgets/data/sortable_table_test.dart
git commit -m "$(cat <<'EOF'
feat(pager): always show page dropdown regardless of total pages

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 新增 i18n keys（保留舊 `sortBy*` 不刪），跑 `flutter gen-l10n`

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Auto-generated: `lib/l10n/generated/*.dart`

- [ ] **Step 1: 在 `app_zh_Hant.arb` 中於 `"tableRarity": "稀有度",` 那一行下方追加**

```json
  "tableTotalIndex": "總抽數",
  "tableFiveStarPity": "保底內",
  "tableFiveStarPityTooltip": "距上一次 5★ 的抽數",
  "sortDirectionDesc": "降序",
  "sortDirectionAsc": "升序",
  "sortDirectionNone": "點擊排序",
```

- [ ] **Step 2: 同樣於 `app_zh_Hans.arb` 中於 `"tableRarity": "稀有度",` 那一行下方追加**

```json
  "tableTotalIndex": "总抽数",
  "tableFiveStarPity": "保底内",
  "tableFiveStarPityTooltip": "距上一次 5★ 的抽数",
  "sortDirectionDesc": "降序",
  "sortDirectionAsc": "升序",
  "sortDirectionNone": "点击排序",
```

- [ ] **Step 3: 同樣於 `app_en.arb` 中於 `"tableRarity": "Rarity",` 那一行下方追加**

```json
  "tableTotalIndex": "Total",
  "tableFiveStarPity": "Pity",
  "tableFiveStarPityTooltip": "Pulls since the last 5★",
  "sortDirectionDesc": "Descending",
  "sortDirectionAsc": "Ascending",
  "sortDirectionNone": "Click to sort",
```

- [ ] **Step 4: 重新生成 i18n**

Run: `flutter gen-l10n`
Expected: 無錯誤輸出；`lib/l10n/generated/app_localizations*.dart` 被更新（含新 getter）。

- [ ] **Step 5: 跑全套測試確認沒壞**

Run: `flutter test`
Expected: All tests PASS（純新增，不影響任何引用既有 keys 的程式碼）

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
feat(l10n): add table totalIndex/pity column labels and sort tooltips

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 一次性切換主流程（record_filter / search_filter_bar / sortable_table / banner_page）

這個 task 內 4 個檔案的修改互相耦合（型別 / 屬性互相依賴），必須一起改才能編譯通過。中間步驟僅在 task 結尾要求測試全綠；step-by-step 跑單檔測試做迭代。

**Files:**
- Modify: `lib/state/record_filter.dart`
- Modify: `lib/widgets/data/search_filter_bar.dart`
- Modify: `lib/widgets/data/sortable_table.dart`
- Modify: `lib/pages/banner_page.dart`
- Modify: `test/state/record_filter_test.dart`
- Modify: `test/widgets/data/search_filter_bar_test.dart`
- Modify: `test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: 改 `lib/state/record_filter.dart`**

完整替換為：

```dart
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
  final TableSort? sort;

  RecordFilterState copyWith({RecordFilter? filter}) =>
      RecordFilterState(filter: filter ?? this.filter, sort: sort);
}

class RecordFilterNotifier extends Notifier<RecordFilterState> {
  @override
  RecordFilterState build() {
    return const RecordFilterState(filter: RecordFilter(), sort: null);
  }

  void setFilter(RecordFilter filter) {
    state = RecordFilterState(filter: filter, sort: state.sort);
  }

  /// 三態循環：null 或其他欄 → desc → asc → null。
  void cycleSort(SortColumn column) {
    final cur = state.sort;
    final next = switch (cur) {
      null => TableSort(column: column, direction: SortDirection.desc),
      TableSort(column: final c, direction: SortDirection.desc)
          when c == column =>
        TableSort(column: column, direction: SortDirection.asc),
      TableSort(column: final c, direction: SortDirection.asc) when c == column
        => null,
      _ => TableSort(column: column, direction: SortDirection.desc),
    };
    state = RecordFilterState(filter: state.filter, sort: next);
  }

  void clear() {
    state = const RecordFilterState(filter: RecordFilter(), sort: null);
  }
}

final recordFilterProvider = NotifierProvider.autoDispose.family<
    RecordFilterNotifier, RecordFilterState, String>(
        (gachaType) => RecordFilterNotifier());
```

- [ ] **Step 2: 改 `test/state/record_filter_test.dart`**

完整替換為：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';

void main() {
  test('預設值為空篩選 + sort=null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.rarity, RarityFilter.all);
    expect(state.filter.kind, KindFilter.all);
    expect(state.filter.query, '');
    expect(state.sort, isNull);
  });

  test('cycleSort：三態循環 null → desc → asc → null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);

    notifier.cycleSort(SortColumn.time);
    expect(container.read(recordFilterProvider('301')).sort,
        const TableSort(column: SortColumn.time, direction: SortDirection.desc));

    notifier.cycleSort(SortColumn.time);
    expect(container.read(recordFilterProvider('301')).sort,
        const TableSort(column: SortColumn.time, direction: SortDirection.asc));

    notifier.cycleSort(SortColumn.time);
    expect(container.read(recordFilterProvider('301')).sort, isNull);
  });

  test('cycleSort：換欄重置為 desc', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);

    notifier.cycleSort(SortColumn.time);          // time desc
    notifier.cycleSort(SortColumn.time);          // time asc
    notifier.cycleSort(SortColumn.totalIndex);    // 換欄 → totalIndex desc
    expect(container.read(recordFilterProvider('301')).sort,
        const TableSort(
            column: SortColumn.totalIndex, direction: SortDirection.desc));
  });

  test('setFilter / cycleSort 各卡池獨立', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(recordFilterProvider('301').notifier)
        .setFilter(const RecordFilter(rarity: RarityFilter.fiveStar));
    container
        .read(recordFilterProvider('302').notifier)
        .cycleSort(SortColumn.rarity);

    expect(container.read(recordFilterProvider('301')).filter.rarity,
        RarityFilter.fiveStar);
    expect(container.read(recordFilterProvider('301')).sort, isNull);
    expect(container.read(recordFilterProvider('302')).filter.rarity,
        RarityFilter.all);
    expect(container.read(recordFilterProvider('302')).sort,
        const TableSort(
            column: SortColumn.rarity, direction: SortDirection.desc));
  });

  test('clear 同時清 filter 與 sort', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recordFilterProvider('301').notifier);
    notifier.setFilter(const RecordFilter(query: 'foo'));
    notifier.cycleSort(SortColumn.name);
    notifier.clear();
    final state = container.read(recordFilterProvider('301'));
    expect(state.filter.query, '');
    expect(state.sort, isNull);
  });
}
```

- [ ] **Step 3: 改 `lib/widgets/data/search_filter_bar.dart`**

完整替換為：

```dart
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
    required this.onClear,
  });

  final RecordFilterState state;
  final ValueChanged<RecordFilter> onFilterChanged;
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
              widget.onFilterChanged(widget.state.filter.copyWith(rarity: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: RarityFilter.all, child: Text(l.filterRarityAll)),
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
              widget.onFilterChanged(widget.state.filter.copyWith(kind: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: KindFilter.all, child: Text(l.filterKindAll)),
            DropdownMenuItem(
                value: KindFilter.character,
                child: Text(l.filterKindCharacter)),
            DropdownMenuItem(
                value: KindFilter.weapon, child: Text(l.filterKindWeapon)),
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

注意：`RecordFilterState` 仍會傳入（含 `sort`），但本元件只讀 `filter`。

- [ ] **Step 4: 改 `test/widgets/data/search_filter_bar_test.dart`**

完整替換為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('clear button hidden when no active filter', (tester) async {
    await tester.pumpWidget(_wrap(SearchFilterBar(
      state: const RecordFilterState(filter: RecordFilter(), sort: null),
      onFilterChanged: (_) {},
      onClear: () {},
    )));
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsNothing);
  });

  testWidgets('clear button visible when filter active', (tester) async {
    await tester.pumpWidget(_wrap(SearchFilterBar(
      state: const RecordFilterState(
        filter: RecordFilter(rarity: RarityFilter.fiveStar),
        sort: null,
      ),
      onFilterChanged: (_) {},
      onClear: () {},
    )));
    final clearBtn = find.widgetWithIcon(TextButton, Icons.clear);
    expect(clearBtn, findsOneWidget);
  });

  testWidgets('排序 dropdown 已不存在', (tester) async {
    await tester.pumpWidget(_wrap(SearchFilterBar(
      state: const RecordFilterState(filter: RecordFilter(), sort: null),
      onFilterChanged: (_) {},
      onClear: () {},
    )));
    // 只有兩個 dropdown：rarity / kind
    expect(find.byType(DropdownButton<RarityFilter>), findsOneWidget);
    expect(find.byType(DropdownButton<KindFilter>), findsOneWidget);
  });
}
```

- [ ] **Step 5: 改 `lib/widgets/data/sortable_table.dart`**

完整替換為（含 6 欄 header、表頭 InkWell + 排序圖示、`rows` 屬性、`onSortColumnTapped`）：

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';

class SortableTable extends StatefulWidget {
  const SortableTable({
    super.key,
    required this.rows,
    required this.sort,
    required this.onSortColumnTapped,
  });

  /// 已 filter / sort 完的 rows；元件本身不做篩選排序。
  final List<RecordRow> rows;
  final TableSort? sort;
  final ValueChanged<SortColumn> onSortColumnTapped;

  @override
  State<SortableTable> createState() => _SortableTableState();
}

class _SortableTableState extends State<SortableTable> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  void didUpdateWidget(SortableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 僅在 rows 數量變化時重置頁碼（filter 變化會影響長度）。
    // sort 變化長度不變，刻意保留使用者當前頁。
    if (oldWidget.rows.length != widget.rows.length) {
      _page = 0;
    }
  }

  int get _totalPages =>
      (widget.rows.length / _pageSize).ceil().clamp(1, 99999);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (widget.rows.isEmpty) {
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
    final end = (start + _pageSize).clamp(0, widget.rows.length);
    final slice = widget.rows.sublist(start, end);

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
              _Header(
                theme: theme,
                tokens: tokens,
                l: l,
                sort: widget.sort,
                onTap: widget.onSortColumnTapped,
              ),
              for (var i = 0; i < slice.length; i++)
                _Row(
                  row: slice[i],
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
  const _Header({
    required this.theme,
    required this.tokens,
    required this.l,
    required this.sort,
    required this.onTap,
  });
  final ThemeData theme;
  final GachaTokens tokens;
  final AppLocalizations l;
  final TableSort? sort;
  final ValueChanged<SortColumn> onTap;

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
            // 與 _Row 內部最左側 stripe 對齊
            const SizedBox(width: 2 + AppSpacing.s),
            _HeaderCell(
              flex: 4,
              label: l.tableTime,
              column: SortColumn.time,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 5,
              label: l.tableName,
              column: SortColumn.name,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableKind,
              column: SortColumn.kind,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableRarity,
              column: SortColumn.rarity,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableTotalIndex,
              column: SortColumn.totalIndex,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
              alignEnd: true,
            ),
            _HeaderCell(
              flex: 2,
              label: l.tableFiveStarPity,
              tooltip: l.tableFiveStarPityTooltip,
              column: SortColumn.fiveStarPity,
              sort: sort,
              tokens: tokens,
              l: l,
              onTap: onTap,
              alignEnd: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.flex,
    required this.label,
    required this.column,
    required this.sort,
    required this.tokens,
    required this.l,
    required this.onTap,
    this.tooltip,
    this.alignEnd = false,
  });
  final int flex;
  final String label;
  final String? tooltip;
  final SortColumn column;
  final TableSort? sort;
  final GachaTokens tokens;
  final AppLocalizations l;
  final ValueChanged<SortColumn> onTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final isActive = sort?.column == column;
    final IconData icon;
    final Color iconColor;
    final String tip;
    if (!isActive || sort == null) {
      icon = Icons.unfold_more;
      iconColor = tokens.textMuted;
      tip = l.sortDirectionNone;
    } else if (sort!.direction == SortDirection.desc) {
      icon = Icons.arrow_downward;
      iconColor = tokens.textSecondary;
      tip = l.sortDirectionDesc;
    } else {
      icon = Icons.arrow_upward;
      iconColor = tokens.textSecondary;
      tip = l.sortDirectionAsc;
    }
    final children = <Widget>[
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 4),
      Icon(icon, size: 14, color: iconColor),
    ];
    final cell = InkWell(
      onTap: () => onTap(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: children,
        ),
      ),
    );
    return Expanded(
      flex: flex,
      child: tooltip == null
          ? Tooltip(message: tip, child: cell)
          : Tooltip(message: '${tooltip!} · $tip', child: cell),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.isStripe,
    required this.theme,
    required this.tokens,
  });
  final RecordRow row;
  final bool isStripe;
  final ThemeData theme;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final record = row.record;
    final accent = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => null,
    };
    final highlight = accent == null
        ? null
        : TextStyle(color: accent, fontWeight: FontWeight.bold);
    final mutedNum = TextStyle(
      color: tokens.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
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
          Expanded(
            flex: 2,
            child: Text(
              '${row.totalIndex}',
              textAlign: TextAlign.end,
              style: mutedNum,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${row.fiveStarPityIndex}',
              textAlign: TextAlign.end,
              style: mutedNum,
            ),
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

- [ ] **Step 6: 改 `test/widgets/data/sortable_table_test.dart`**

完整替換為（改用 `RecordRow` 與新屬性；保留 dropdown 斷言）：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
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

Widget _wrap(Widget child) => MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 1200, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders rows, rarity pills, totalIndex/pity columns', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    final rows = buildRecordRows(records);
    await tester.pumpWidget(_wrap(SortableTable(
      rows: rows,
      sort: null,
      onSortColumnTapped: (_) {},
    )));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    // totalIndex 顯示（rows desc by time → id 5 是最新 → totalIndex=3）
    expect(find.text('3'), findsWidgets); // totalIndex of A
    expect(find.text('1'), findsWidgets); // totalIndex of C
  });

  testWidgets('paginates with 20 per page (always shows dropdown)', (tester) async {
    final records = List.generate(
      45,
      (i) => _r(id: '${i + 1}', rank: 4, name: 'r$i'),
    );
    final rows = buildRecordRows(records);
    await tester.pumpWidget(_wrap(SortableTable(
      rows: rows,
      sort: null,
      onSortColumnTapped: (_) {},
    )));
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdown.items, hasLength(3));
    expect(dropdown.value, 0);
  });

  testWidgets('表頭點擊呼叫 onSortColumnTapped(對應欄)', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records);
    SortColumn? tapped;
    await tester.pumpWidget(_wrap(SortableTable(
      rows: rows,
      sort: null,
      onSortColumnTapped: (c) => tapped = c,
    )));
    await tester.tap(find.text('時間'));
    expect(tapped, SortColumn.time);

    await tester.tap(find.text('名稱'));
    expect(tapped, SortColumn.name);

    await tester.tap(find.text('總抽數'));
    expect(tapped, SortColumn.totalIndex);

    await tester.tap(find.text('保底內'));
    expect(tapped, SortColumn.fiveStarPity);
  });

  testWidgets('當前排序欄顯示 arrow_downward；其他欄維持 unfold_more', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records);
    await tester.pumpWidget(_wrap(SortableTable(
      rows: rows,
      sort: const TableSort(
          column: SortColumn.rarity, direction: SortDirection.desc),
      onSortColumnTapped: (_) {},
    )));
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    // 其餘 5 個欄位都顯示 unfold_more
    expect(find.byIcon(Icons.unfold_more), findsNWidgets(5));
  });
}
```

- [ ] **Step 7: 改 `lib/pages/banner_page.dart`**

替換 import 區塊中加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
```

把第 80–82 行（`final filterState = ref.watch(...) ; final filtered = sortRecords(filterRecords(...), filterState.sort);`）改為：

```dart
    final filterState = ref.watch(recordFilterProvider(gachaType));
    final allRows = buildRecordRows(records);
    final filtered = filterRecordRows(allRows, filterState.filter);
    final sorted = sortRecordRows(filtered, filterState.sort);
```

把 207–218 行的 `SearchFilterBar(...)` 改為（移除 `onSortChanged`）：

```dart
          SearchFilterBar(
            state: filterState,
            onFilterChanged: (f) => ref
                .read(recordFilterProvider(gachaType).notifier)
                .setFilter(f),
            onClear: () =>
                ref.read(recordFilterProvider(gachaType).notifier).clear(),
          ),
```

把 220 行的 `SortableTable(records: filtered),` 改為：

```dart
          SortableTable(
            rows: sorted,
            sort: filterState.sort,
            onSortColumnTapped: (col) => ref
                .read(recordFilterProvider(gachaType).notifier)
                .cycleSort(col),
          ),
```

- [ ] **Step 8: 跑 4 個受影響測試確認 pass**

Run: `flutter test test/state/record_filter_test.dart test/widgets/data/search_filter_bar_test.dart test/widgets/data/sortable_table_test.dart test/services/wish_filter_test.dart`
Expected: All tests PASS（注意 `wish_filter_test.dart` 中既有 `RecordSort` 相關測試此時仍跑，因為 RecordSort 還未刪——也應通過）

- [ ] **Step 9: 跑 `flutter analyze`**

Run: `flutter analyze`
Expected: 沒有 ERROR；可能會有 INFO 提示舊 `RecordSort` / `filterRecords` / `sortRecords` 變成「目前沒人用」（unused_element_in_library 之類），這在下個 task 清理。

- [ ] **Step 10: 跑 `flutter test`（全套）**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 11: Commit**

```bash
git add lib/state/record_filter.dart lib/widgets/data/search_filter_bar.dart lib/widgets/data/sortable_table.dart lib/pages/banner_page.dart test/state/record_filter_test.dart test/widgets/data/search_filter_bar_test.dart test/widgets/data/sortable_table_test.dart
git commit -m "$(cat <<'EOF'
feat(banner): header-click tristate sort + totalIndex/pity columns

Switches BannerPage record table to row-level pipeline:
- record_filter state.sort becomes TableSort? with cycleSort()
- SearchFilterBar drops sort dropdown (header click is the sole sort UI)
- SortableTable consumes List<RecordRow>, six clickable header cells
  with desc/asc/none indicators
- BannerPage wires buildRecordRows -> filterRecordRows -> sortRecordRows

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 清理舊代碼（移除 `RecordSort` / `filterRecords` / `sortRecords` + 舊 `sortBy*` i18n keys）

**Files:**
- Modify: `lib/services/wish_filter.dart`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `test/services/wish_filter_test.dart`
- Auto-regenerate: `lib/l10n/generated/*.dart`

- [ ] **Step 1: 在 `lib/services/wish_filter.dart` 中刪除舊 enum / 函式**

- 刪掉 `enum RecordSort { timeDesc, timeAsc, rarityDesc, rarityAsc, name }`
- 刪掉 `List<WishRecord> filterRecords(List<WishRecord> records, RecordFilter f) { ... }` 整段
- 刪掉 `List<WishRecord> sortRecords(List<WishRecord> records, RecordSort s) { ... }` 整段
- 保留：`enum RarityFilter`、`enum KindFilter`、`class RecordFilter`、新的 `enum SortColumn` / `SortDirection` / `class TableSort` / `filterRecordRows` / `sortRecordRows`
- 保留檔頂 import（仍需 `WishItemKind`、`RecordRow`）

- [ ] **Step 2: 在 `test/services/wish_filter_test.dart` 中刪除舊測試**

- 刪除整個 `group('filterRecords', () { ... });` block
- 刪除整個 `group('sortRecords', () { ... });` block
- 保留：`records` setUp、`group('filterRecordRows')`、`group('sortRecordRows')`

- [ ] **Step 3: 在 3 份 arb 中刪除 `sortBy*` 五個 keys**

對 `app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb` 都刪除：

```json
  "sortByTimeDesc": "...",
  "sortByTimeAsc": "...",
  "sortByRarityDesc": "...",
  "sortByRarityAsc": "...",
  "sortByName": "...",
```

- [ ] **Step 4: 重新生成 i18n**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/*.dart` 中對應的 5 個 getter 一併消失。

- [ ] **Step 5: 跑 `flutter analyze`**

Run: `flutter analyze`
Expected: 沒有任何 ERROR / WARNING。如果出現「未使用 import」之類的提示，順手清掉。

- [ ] **Step 6: 跑 `flutter test`（全套）**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add lib/services/wish_filter.dart test/services/wish_filter_test.dart lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
chore: remove obsolete RecordSort/filterRecords/sortRecords and sortBy* l10n keys

Replaced by row-level pipeline + TableSort introduced in
banner table header-sort change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 完成驗收

執行最後一輪驗收：

- [ ] `flutter analyze` 全綠
- [ ] `flutter test` 全綠
- [ ] 啟動 app（`flutter run -d windows` 或 IDE 跑）：
  - 進入任一卡池頁
  - 表頭點擊「時間」→ 圖示變降序、再點變升序、再點消失（回原始順序）
  - 點擊「總抽數」、「保底內」確認可排序
  - 確認 dropdown 換頁元件存在（即使只有 1 頁）
  - 確認新欄位「總抽數」、「保底內」顯示正確值
  - 確認 `SearchFilterBar` 上沒有排序 dropdown
  - 切到綜合頁確認 `FiveStarList` 不受影響
