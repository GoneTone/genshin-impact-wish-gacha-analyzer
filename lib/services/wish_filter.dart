import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';

enum RarityFilter { all, fiveStar, fourStar }

enum KindFilter { all, character, weapon }

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
