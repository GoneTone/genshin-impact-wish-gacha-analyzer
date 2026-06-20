import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

/// 單一卡池的保底狀態計算結果。
@immutable
class Pity {
  /// 建立 [Pity]。
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastRecordAt,
    required this.averageInterval,
    required this.hitCount,
    required this.completedPulls,
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

  /// 落在「已完成的精確（== rank）週期」內的抽數，即 records.length 減去距上次
  /// 精確命中的抽數。單卡池 [averageInterval] 由 completedPulls / hitCount 得出，
  /// 跨卡池 [averageIntervalAcrossBanners] 亦累加各卡池的 completedPulls 當分子。
  final int completedPulls;

  /// 保底進度（0.0–1.0），超過閾值時夾到 1.0。
  double get progress {
    if (threshold <= 0) return 0;
    final raw = current / threshold;
    return raw > 1 ? 1.0 : raw;
  }

  /// 距保底還剩幾抽；已超過閾值時為 0。
  int get distance {
    final d = threshold - current;
    return d < 0 ? 0 : d;
  }
}

/// 計算單一卡池對指定 [rank] 的保底狀態。預設 rank=5，4★ pity 傳 rank=4。
///
/// 保底計數（[Pity.current]／[Pity.lastRecordAt]）以「rankType ≥ rank」為重置點：
/// Genshin 的 4★ 保底保證的是「4★ 或以上」，故抽到 5★ 也會重置 4★ pity；3★ 保底
/// 同理被 4★／5★ 重置。對 rank=5 沒有更高稀有度，行為與精確比對相同。
///
/// 平均間隔（[Pity.averageInterval]／[Pity.hitCount]）則只計入「恰好等於 rank」的
/// 命中，維持「平均幾抽出一個該稀有度」的語意，不把更高稀有度算成一次週期結束。
Pity computePity(
  List<GachaRecord> records, {
  required int threshold,
  int rank = 5,
}) {
  // 保底計數：抽到「rank 或以上」即重置。
  var current = 0;
  DateTime? lastAt;
  // 平均間隔：只數「恰好等於 rank」的命中，sinceLastExact 為距上次精確命中的抽數。
  var sinceLastExact = 0;
  var hitCount = 0;
  var exactSeen = false;

  for (final r in records) {
    if (lastAt == null) {
      if (r.rankType >= rank) {
        lastAt = r.time; // 首個「rank 或以上」後鎖定保底計數
      } else {
        current++;
      }
    }
    if (r.rankType == rank) {
      hitCount++;
      exactSeen = true;
    } else if (!exactSeen) {
      sinceLastExact++;
    }
  }

  final completedPulls = records.length - sinceLastExact;
  final averageInterval = hitCount > 0 ? completedPulls / hitCount : null;
  return Pity(
    current: current,
    threshold: threshold,
    lastRecordAt: lastAt,
    averageInterval: averageInterval,
    hitCount: hitCount,
    completedPulls: completedPulls,
  );
}

/// 跨卡池合併平均：對每個卡池各自算 [Pity.completedPulls] 與 [Pity.hitCount]，
/// 把分子分母分別累加再相除。與單卡池 [Pity.averageInterval] 語意一致（只計入恰好
/// 等於目標 rank 的命中），每個卡池各算各的 completedPulls，不會把多個卡池的未命中
/// 抽數合計進分子。
double? averageIntervalAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  var sumCompleted = 0;
  var sumHits = 0;
  for (final entry in banners.entries) {
    // threshold: 0 — 跨卡池場景不需要 pity progress/distance，此參數被忽略。
    final p = computePity(entry.value, threshold: 0, rank: rankFor(entry.key));
    sumCompleted += p.completedPulls;
    sumHits += p.hitCount;
  }
  return sumHits > 0 ? sumCompleted / sumHits : null;
}
