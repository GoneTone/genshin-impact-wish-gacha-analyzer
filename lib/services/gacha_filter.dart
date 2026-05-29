import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';

/// 稀有度篩選條件。
enum RarityFilter {
  /// 不限稀有度。
  all,

  /// 僅顯示 5★。
  fiveStar,

  /// 僅顯示 4★。
  fourStar,
}

/// 祈願紀錄篩選條件（稀有度、物品類型、關鍵字）。
@immutable
class RecordFilter {
  /// 建立 [RecordFilter]，預設不限稀有度、不限物品類型、無關鍵字。
  const RecordFilter({
    this.rarity = RarityFilter.all,
    this.itemType,
    this.query = '',
  });

  /// 稀有度篩選。
  final RarityFilter rarity;

  /// 物品類型篩選；null 表示不限。
  final String? itemType;

  /// 關鍵字搜尋字串。
  final String query;

  /// 是否有任何非預設的篩選條件。
  bool get hasAny =>
      rarity != RarityFilter.all || itemType != null || query.trim().isNotEmpty;

  /// 用 sentinel 區分「不改 itemType」與「把 itemType 設為 null」。
  RecordFilter copyWith({
    RarityFilter? rarity,
    Object? itemType = _sentinel,
    String? query,
  }) => RecordFilter(
    rarity: rarity ?? this.rarity,
    itemType: identical(itemType, _sentinel)
        ? this.itemType
        : itemType as String?,
    query: query ?? this.query,
  );

  /// [copyWith] 用以區分「不傳 itemType」與「設為 null」的哨兵值。
  static const _sentinel = Object();
}

/// 可排序的欄位。
enum SortColumn {
  /// 抽取時間。
  time,

  /// 物品名稱。
  name,

  /// 物品類型（武器/角色）。
  kind,

  /// 稀有度。
  rarity,

  /// 卡池累計抽數序號。
  totalIndex,

  /// 距上次主稀有度（含自己）的抽數。
  mainPity,
}

/// 排序方向。
enum SortDirection {
  /// 升冪排序。
  asc,

  /// 降冪排序。
  desc,
}

/// 表格排序條件（欄位 + 方向）。
@immutable
class TableSort {
  /// 建立 [TableSort]，需指定排序欄位與方向。
  const TableSort({required this.column, required this.direction});

  /// 排序欄位。
  final SortColumn column;

  /// 排序方向。
  final SortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is TableSort &&
      other.column == column &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(column, direction);
}

/// 依 [RecordFilter] 條件過濾 [rows]，回傳新列表。
List<RecordRow> filterRecordRows(List<RecordRow> rows, RecordFilter f) {
  final q = f.query.trim().toLowerCase();
  return rows
      .where((row) {
        final r = row.record;
        if (f.rarity == RarityFilter.fiveStar && r.rankType != 5) return false;
        if (f.rarity == RarityFilter.fourStar && r.rankType != 4) return false;
        if (f.itemType != null && row.itemTypeKey != f.itemType) return false;
        if (q.isNotEmpty && !r.name.toLowerCase().contains(q)) return false;
        return true;
      })
      .toList(growable: false);
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
      cmp = (a, b) => a.itemTypeKey.compareTo(b.itemTypeKey);
    case SortColumn.rarity:
      cmp = (a, b) => a.record.rankType.compareTo(b.record.rankType);
    case SortColumn.totalIndex:
      cmp = (a, b) => a.totalIndex.compareTo(b.totalIndex);
    case SortColumn.mainPity:
      cmp = (a, b) => a.mainPityIndex.compareTo(b.mainPityIndex);
  }
  out.sort((a, b) {
    final primary = sort.direction == SortDirection.asc ? cmp(a, b) : cmp(b, a);
    if (primary != 0) return primary;
    return b.record.time.compareTo(a.record.time);
  });
  return out;
}
