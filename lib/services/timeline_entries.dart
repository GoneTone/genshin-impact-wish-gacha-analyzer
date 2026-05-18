import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

/// 時間軸條目:一筆目標稀有度紀錄 + 距該卡池上一筆同稀有度的抽數。
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });

  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

/// 從單一卡池 desc-by-time 排序的 records 萃取 [targetRank] 條目,
/// 並計算每筆距該卡池上一筆 [targetRank] 的抽數。
/// 回傳結果依時間 desc(最新在前)。
List<TimelineEntry> buildTimelineEntries(
  List<GachaRecord> records, {
  int targetRank = 5,
}) {
  final asc = records.reversed.toList(growable: false);
  final out = <TimelineEntry>[];
  var pull = 0;
  for (final r in asc) {
    pull++;
    if (r.rankType == targetRank) {
      out.add(
        TimelineEntry(
          name: r.name,
          gachaType: r.gachaType,
          time: r.time,
          pullsSincePrev: pull,
        ),
      );
      pull = 0;
    }
  }
  return out.reversed.toList(growable: false);
}

/// 跨卡池:合併所有卡池的 entries,依時間 desc 排序。
/// 每個卡池用 [rankFor] 決定要萃取的稀有度。
/// 每筆 entry 的 pullsSincePrev 仍以「該 entry 所屬卡池的上一筆同稀有度」為基準,
/// 不是「跨卡池上一筆」 — 保底計算永遠 per-pool。
List<TimelineEntry> buildTimelineEntriesAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  final out = <TimelineEntry>[];
  for (final entry in banners.entries) {
    out.addAll(
      buildTimelineEntries(entry.value, targetRank: rankFor(entry.key)),
    );
  }
  out.sort((a, b) => b.time.compareTo(a.time));
  return out;
}

/// 從 desc 排序的 records 計算「最後一個 [rank] 之後又抽了多少抽」。
/// 若無任何符合的,回傳 records.length(視為從頭累計)。
int pullsSinceLastRanked(List<GachaRecord> records, {required int rank}) {
  var count = 0;
  for (final r in records) {
    if (r.rankType == rank) return count;
    count++;
  }
  return count;
}

/// 跨卡池:找跨卡池最新「該卡池主稀有度」記錄,計算其後跨全部卡池 record 總數。
/// 每個卡池用 [rankFor] 決定主稀有度。
/// 同一卡池內以 record id 比對識別「該筆」,正確處理 10 連抽中主稀有度位於中間
/// (其後同秒內仍有後續抽)的情況。
/// 若所有卡池皆無對應稀有度,回傳全部卡池 record 數總和。
int pullsSinceLastRankedAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  // Phase 1: find cross-pool latest target-rank — the actual record's id + pool + time
  String? latestId;
  String? latestPool;
  DateTime? latestTime;
  for (final entry in banners.entries) {
    final rank = rankFor(entry.key);
    for (final r in entry.value) {
      if (r.rankType == rank) {
        if (latestTime == null || r.time.isAfter(latestTime)) {
          latestTime = r.time;
          latestId = r.id;
          latestPool = entry.key;
        }
        break; // records 已 desc,該卡池第一筆目標稀有度即該池最新
      }
    }
  }
  // 沒有任何符合稀有度:回傳跨卡池 record 總數
  if (latestTime == null) {
    var total = 0;
    for (final records in banners.values) {
      total += records.length;
    }
    return total;
  }
  // Phase 2: 計數
  // - 該稀有度所在卡池:用 id 比對找到該筆,計算其之前(desc 排序中 = 抽得較晚)的 record 數
  // - 其他卡池:用 isAfter 嚴格比較(跨卡池同秒實務上不會發生)
  var count = 0;
  for (final entry in banners.entries) {
    final records = entry.value;
    if (entry.key == latestPool) {
      for (final r in records) {
        if (r.id == latestId) break;
        count++;
      }
    } else {
      for (final r in records) {
        if (r.time.isAfter(latestTime)) {
          count++;
        } else {
          break; // desc records,可以提早結束
        }
      }
    }
  }
  return count;
}
