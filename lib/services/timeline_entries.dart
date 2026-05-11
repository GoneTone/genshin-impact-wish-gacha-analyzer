import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

/// 時間軸條目:一筆 5★ 紀錄 + 距該卡池上一筆 5★ 的抽數。
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

/// 從單一卡池 desc-by-time 排序的 records,萃取 5★ 條目並計算每筆的 pullsSincePrev。
/// 回傳結果依時間 desc(最新在前)。
List<TimelineEntry> buildTimelineEntries(List<WishRecord> records) {
  final asc = records.reversed.toList(growable: false);
  final out = <TimelineEntry>[];
  var pull = 0;
  for (final r in asc) {
    pull++;
    if (r.rankType == 5) {
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
/// 每筆 entry 的 pullsSincePrev 仍以「該 entry 所屬卡池的上一筆 5★」為基準,
/// 不是「跨卡池上一筆」 — 保底計算永遠 per-pool。
List<TimelineEntry> buildTimelineEntriesAcrossBanners(
  Map<String, List<WishRecord>> banners,
) {
  final out = <TimelineEntry>[];
  for (final records in banners.values) {
    out.addAll(buildTimelineEntries(records));
  }
  out.sort((a, b) => b.time.compareTo(a.time));
  return out;
}

/// 從 desc 排序的 records 計算「最後一個 5★ 之後又抽了多少抽」。
/// 若無任何 5★,回傳 records.length(視為從頭累計)。
int pullsSinceLastFiveStar(List<WishRecord> records) {
  var count = 0;
  for (final r in records) {
    if (r.rankType == 5) return count;
    count++;
  }
  return count;
}

/// 跨卡池:從 banners map 找到跨卡池最新 5★,計算其後跨全部卡池 record 總數。
/// 若所有卡池皆無 5★,回傳全部卡池 record 數總和。
int pullsSinceLastFiveStarAcrossBanners(Map<String, List<WishRecord>> banners) {
  DateTime? latest;
  for (final records in banners.values) {
    for (final r in records) {
      if (r.rankType == 5) {
        if (latest == null || r.time.isAfter(latest)) {
          latest = r.time;
        }
        break; // records 已 desc,該卡池的第一筆 5★ 就是該池最新 5★
      }
    }
  }
  if (latest == null) {
    var total = 0;
    for (final records in banners.values) {
      total += records.length;
    }
    return total;
  }
  var count = 0;
  for (final records in banners.values) {
    for (final r in records) {
      if (r.time.isAfter(latest)) count++;
    }
  }
  return count;
}
