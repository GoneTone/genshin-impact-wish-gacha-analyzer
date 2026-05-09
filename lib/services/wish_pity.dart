import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

@immutable
class Pity {
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastFiveStarAt,
  });

  /// 距上次 5★ 已抽幾抽（不含 5★ 那筆本身）。沒有 5★ 時 = 總抽數。
  final int current;

  /// 該卡池的保底閾值。
  final int threshold;

  /// 上次 5★ 抽中的時間；若從未 5★，為 null。
  final DateTime? lastFiveStarAt;

  /// 0.0–1.0，超過 threshold clamp 到 1.0。
  double get progress {
    if (threshold <= 0) return 0;
    final raw = current / threshold;
    return raw > 1 ? 1.0 : raw;
  }

  /// 距下次保底還差幾抽（>= 0）。
  int get distance {
    final d = threshold - current;
    return d < 0 ? 0 : d;
  }
}

/// 計算單一卡池的保底狀態。
///
/// [records] 必須以時間 desc 排序（最新在前），與 `BannerStorage.banners[gachaType]`
/// 的儲存約定一致。
Pity computePity(
  List<WishRecord> records, {
  required int threshold,
}) {
  var current = 0;
  DateTime? lastFiveStarAt;
  for (final r in records) {
    if (r.rankType == 5) {
      lastFiveStarAt = r.time;
      break;
    }
    current++;
  }
  return Pity(
    current: current,
    threshold: threshold,
    lastFiveStarAt: lastFiveStarAt,
  );
}
