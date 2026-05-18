// lib/services/overview_sections.dart
//
// 綜合頁的「祈願/頌願分組 + 統計 + 平均間隔 + timeline」純資料計算。
// OverviewPage 與 ShareCard 共用，避免兩處複製分組邏輯。
import 'package:flutter/foundation.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

/// 祈願段（角色/武器/常駐/新手…）的彙整結果。
@immutable
class GachaSectionData {
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

  final List<GachaType> types;
  final Map<String, List<GachaRecord>> banners;
  final GachaStats stats;
  final List<TimelineEntry> timeline;
  final int timelineRank;
  final int timelineNowPulls;
  final double? fiveStarAvg;
  final double? fourStarAvg;
}

/// 頌願段沿用既有 odes 統計組成（總抽數、事件 5★、常駐 4★），
/// 不套「佔比 + 平均幾抽出」（odes 無對應保底語意）。
@immutable
class OdesSectionData {
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

  final List<GachaType> types;
  final Map<String, List<GachaRecord>> banners;
  final GachaStats stats;
  final int eventFiveCount;
  final int standardFourCount;
  final List<TimelineEntry> timeline;
  final int timelineRank;
  final int timelineNowPulls;
}

@immutable
class OverviewSections {
  const OverviewSections({required this.gacha, required this.odes});
  final GachaSectionData gacha;
  final OdesSectionData odes;
}

OverviewSections buildOverviewSections(
  Map<String, List<GachaRecord>> activeBanners,
) {
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
      stats: computeGachaStats(gachaAll),
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
      stats: computeGachaStats(odesAll),
      eventFiveCount: eventFive,
      standardFourCount: standardFour,
      timeline: odesTimeline,
      timelineRank: odesTimelineRank,
      timelineNowPulls: odesTimelineNowPulls,
    ),
  );
}
