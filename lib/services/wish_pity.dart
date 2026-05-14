import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

@immutable
class Pity {
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastRecordAt,
    required this.averageInterval,
    required this.hitCount,
  });

  /// 距上次符合 [computePity.rank] 的紀錄已抽幾抽。沒有則 = 總抽數。
  final int current;

  /// 該卡池的保底閾值。
  final int threshold;

  /// 上次符合 rank 的紀錄時間。
  final DateTime? lastRecordAt;

  /// 已落地週期的平均抽數，hitCount == 0 時為 null。
  final double? averageInterval;

  /// 該 rank 在 records 中的總命中次數。
  final int hitCount;

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
  var hitCount = 0;
  DateTime? lastAt;
  for (final r in records) {
    if (r.rankType == rank) {
      lastAt ??= r.time; // 首次命中後鎖定（等同原本 break 後不再賦值）
      hitCount++;
    } else if (lastAt == null) {
      current++; // 只在尚未命中之前累加（等同原本 break 前的行為）
    }
  }
  final averageInterval = hitCount > 0
      ? (records.length - current) / hitCount
      : null;
  return Pity(
    current: current,
    threshold: threshold,
    lastRecordAt: lastAt,
    averageInterval: averageInterval,
    hitCount: hitCount,
  );
}

/// 跨卡池合併平均:對每個卡池各自算 (records.length − current) 與 hitCount,
/// 把分子分母分別累加再相除。與單卡池 [Pity.averageInterval] 語意一致,
/// 每個卡池各算各的 `current`,不會把多個卡池「未命中當前 pity」合計進分子。
double? crossBannerAverageInterval(
  Map<String, List<WishRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  var sumCompleted = 0;
  var sumHits = 0;
  for (final entry in banners.entries) {
    // threshold: 0 — 跨卡池場景不需要 pity progress/distance,此參數被忽略。
    final p = computePity(entry.value, threshold: 0, rank: rankFor(entry.key));
    sumCompleted += entry.value.length - p.current;
    sumHits += p.hitCount;
  }
  return sumHits > 0 ? sumCompleted / sumHits : null;
}
