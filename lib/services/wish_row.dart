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
    out.add(RecordRow(record: r, totalIndex: total, fiveStarPityIndex: pity));
    if (r.rankType == 5) {
      pity = 0;
    }
  }
  return out.reversed.toList(growable: false);
}
