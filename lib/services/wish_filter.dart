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
