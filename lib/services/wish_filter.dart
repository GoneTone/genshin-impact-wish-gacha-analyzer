import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';

enum RarityFilter { all, fiveStar, fourStar }

@immutable
class RecordFilter {
  const RecordFilter({
    this.rarity = RarityFilter.all,
    this.itemType,
    this.query = '',
  });

  final RarityFilter rarity;
  final String? itemType;
  final String query;

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

  static const _sentinel = Object();
}

enum SortColumn { time, name, kind, rarity, totalIndex, mainPity }

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
  return rows
      .where((row) {
        final r = row.record;
        if (f.rarity == RarityFilter.fiveStar && r.rankType != 5) return false;
        if (f.rarity == RarityFilter.fourStar && r.rankType != 4) return false;
        if (f.itemType != null && r.itemType != f.itemType) return false;
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
      cmp = (a, b) => a.record.itemType.compareTo(b.record.itemType);
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
