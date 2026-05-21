import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

/// 附帶計算後序號的祈願紀錄行（表格顯示用）。
@immutable
class RecordRow {
  /// 建立 [RecordRow]。
  const RecordRow({
    required this.record,
    required this.totalIndex,
    required this.mainPityIndex,
  });

  /// 原始祈願紀錄。
  final GachaRecord record;

  /// 該抽在該卡池所有抽中的累積序號（asc）；最舊 = 1，最新 = N。
  final int totalIndex;

  /// 距上一個「主稀有度」紀錄後的第幾抽（含自己）。「主稀有度」由
  /// [buildRecordRows.mainRank] 決定（卡池預設 5★、常駐頌願 4★）。
  /// 該主稀有度那一抽 = 抵達該主稀有度的累積值；下一抽從 1 重新累計。
  /// 若該卡池從未出現符合主稀有度的紀錄，則持續累計，與 totalIndex 相同。
  final int mainPityIndex;
}

/// records 必須以時間 desc 排序（與 gacha_repository 一致）。
/// 回傳順序與 records 相同（desc by time）。
/// [mainRank] 預設 5（卡池主稀有度）。常駐頌願須傳 4。
List<RecordRow> buildRecordRows(List<GachaRecord> records, {int mainRank = 5}) {
  if (records.isEmpty) return const [];
  // 以 asc 順序累計再 reverse，保持輸出順序與輸入一致。
  final asc = records.reversed.toList(growable: false);
  final out = <RecordRow>[];
  var total = 0;
  var pity = 0;
  for (final r in asc) {
    total++;
    pity++;
    out.add(RecordRow(record: r, totalIndex: total, mainPityIndex: pity));
    if (r.rankType == mainRank) {
      pity = 0;
    }
  }
  return out.reversed.toList(growable: false);
}
