import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

@immutable
class Pity {
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastRecordAt,
  });

  /// 距上次符合 [computePity.rank] 的紀錄已抽幾抽。沒有則 = 總抽數。
  final int current;

  /// 該卡池的保底閾值。
  final int threshold;

  /// 上次符合 rank 的紀錄時間。
  final DateTime? lastRecordAt;

  double get progress {
    if (threshold <= 0) return 0;
    final raw = current / threshold;
    return raw > 1 ? 1.0 : raw;
  }

  int get distance {
    final d = threshold - current;
    return d < 0 ? 0 : d;
  }
}

/// 計算單一卡池對指定 [rank] 的保底狀態。預設 rank=5，4★ pity 傳 rank=4。
Pity computePity(
  List<WishRecord> records, {
  required int threshold,
  int rank = 5,
}) {
  var current = 0;
  DateTime? lastAt;
  for (final r in records) {
    if (r.rankType == rank) {
      lastAt = r.time;
      break;
    }
    current++;
  }
  return Pity(current: current, threshold: threshold, lastRecordAt: lastAt);
}
