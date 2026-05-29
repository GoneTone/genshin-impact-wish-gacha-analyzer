import 'package:flutter/foundation.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

/// 祈願段（角色/武器/常駐/新手…）的彙整結果。
@immutable
class GachaSectionData {
  /// 建立 [GachaSectionData]。
  const GachaSectionData({
    required this.types,
    required this.banners,
    required this.stats,
    required this.timeline,
    required this.timelineRank,
    required this.timelineNowPulls,
    required this.fiveStarAvg,
    required this.fourStarAvg,
  });

  /// 此段包含的祈願類型清單。
  final List<GachaType> types;

  /// 各卡池的抽卡記錄，key 為 gachaType。
  final Map<String, List<GachaRecord>> banners;

  /// 此段所有卡池合計統計。
  final GachaStats stats;

  /// 跨卡池合併的時間軸條目。
  final List<TimelineEntry> timeline;

  /// 時間軸目標星級（primaryPity.rank）。
  final int timelineRank;

  /// 距上次 timelineRank 出貨的累積抽數（供 TimelineVertical「現在」row 顯示）。
  final int timelineNowPulls;

  /// 5★ 平均間隔抽數；無出貨記錄時為 null。
  final double? fiveStarAvg;

  /// 4★ 平均間隔抽數；無出貨記錄時為 null。
  final double? fourStarAvg;
}

/// 頌願段沿用既有 odes 統計組成（總抽數、事件 5★、常駐 4★），
/// 不套「佔比 + 平均幾抽出」（odes 無對應保底語意）。
@immutable
class OdesSectionData {
  /// 建立 [OdesSectionData]。
  const OdesSectionData({
    required this.types,
    required this.banners,
    required this.stats,
    required this.eventFiveCount,
    required this.standardFourCount,
    required this.timeline,
    required this.timelineRank,
    required this.timelineNowPulls,
  });

  /// 此段包含的頌願類型清單。
  final List<GachaType> types;

  /// 各卡池的抽卡記錄，key 為 gachaType。
  final Map<String, List<GachaRecord>> banners;

  /// 此段所有卡池合計統計。
  final GachaStats stats;

  /// 頌願活動卡池（gachaType '2000'）的 5★ 出貨數。
  final int eventFiveCount;

  /// 頌願常駐卡池（gachaType '1000'）的 4★ 出貨數。
  final int standardFourCount;

  /// 跨卡池合併的時間軸條目。
  final List<TimelineEntry> timeline;

  /// 時間軸目標星級（primaryPity.rank）。
  final int timelineRank;

  /// 距上次 timelineRank 出貨的累積抽數（供 TimelineVertical「現在」row 顯示）。
  final int timelineNowPulls;
}

/// OverviewPage 與 ShareCard 共用的祈願＋頌願兩段彙整結果。
@immutable
class OverviewSections {
  /// 建立 [OverviewSections]。
  const OverviewSections({required this.gacha, required this.odes});

  /// 祈願段（角色/武器/常駐/新手）彙整。
  final GachaSectionData gacha;

  /// 頌願段彙整。
  final OdesSectionData odes;
}

/// 從 [activeBanners] 建構 [OverviewSections]，供 OverviewPage 與 ShareCard 共用，
/// 避免兩處複製分組邏輯。[index] 傳入 [computeGachaStats] 以消除跨語系類型分裂。
OverviewSections buildOverviewSections(
  Map<String, List<GachaRecord>> activeBanners, {
  required HoYoWikiIndex index,
}) {
  final gachaList = gachaTypes
      .where((t) => t.category == GachaCategory.gacha)
      .toList(growable: false);
  final odesList = gachaTypes
      .where((t) => t.category == GachaCategory.odes)
      .toList(growable: false);

  final gachaBanners = <String, List<GachaRecord>>{
    for (final t in gachaList)
      t.gachaType: activeBanners[t.gachaType] ?? const <GachaRecord>[],
  };
  final odesBanners = <String, List<GachaRecord>>{
    for (final t in odesList)
      t.gachaType: activeBanners[t.gachaType] ?? const <GachaRecord>[],
  };

  final gachaAll = gachaBanners.values.expand((r) => r).toList(growable: false);
  final odesAll = odesBanners.values.expand((r) => r).toList(growable: false);

  final gachaTypesByGt = <String, GachaType>{
    for (final t in gachaList) t.gachaType: t,
  };
  final odesTypesByGt = <String, GachaType>{
    for (final t in odesList) t.gachaType: t,
  };

  final gachaTimelineRank = gachaList.first.primaryPity.rank;
  final odesTimelineRank = odesList.first.primaryPity.rank;

  final eventFive = (odesBanners['2000'] ?? const <GachaRecord>[])
      .where((r) => r.rankType == 5)
      .length;
  final standardFour = (odesBanners['1000'] ?? const <GachaRecord>[])
      .where((r) => r.rankType == 4)
      .length;

  final gachaTimeline = buildTimelineEntriesAcrossBanners(
    gachaBanners,
    rankFor: (gt) => gachaTypesByGt[gt]!.primaryPity.rank,
  );
  final gachaTimelineNowPulls = pullsSinceLastRankedAcrossBanners(
    gachaBanners,
    rankFor: (gt) => gachaTypesByGt[gt]!.primaryPity.rank,
  );

  final odesTimeline = buildTimelineEntriesAcrossBanners(
    odesBanners,
    rankFor: (gt) => odesTypesByGt[gt]!.primaryPity.rank,
  );
  final odesTimelineNowPulls = pullsSinceLastRankedAcrossBanners(
    odesBanners,
    rankFor: (gt) => odesTypesByGt[gt]!.primaryPity.rank,
  );

  return OverviewSections(
    gacha: GachaSectionData(
      types: gachaList,
      banners: gachaBanners,
      stats: computeGachaStats(gachaAll, index: index),
      timeline: gachaTimeline,
      timelineRank: gachaTimelineRank,
      timelineNowPulls: gachaTimelineNowPulls,
      fiveStarAvg: averageIntervalAcrossBanners(
        gachaBanners,
        rankFor: (_) => 5,
      ),
      fourStarAvg: averageIntervalAcrossBanners(
        gachaBanners,
        rankFor: (_) => 4,
      ),
    ),
    odes: OdesSectionData(
      types: odesList,
      banners: odesBanners,
      stats: computeGachaStats(odesAll, index: index),
      eventFiveCount: eventFive,
      standardFourCount: standardFour,
      timeline: odesTimeline,
      timelineRank: odesTimelineRank,
      timelineNowPulls: odesTimelineNowPulls,
    ),
  );
}
