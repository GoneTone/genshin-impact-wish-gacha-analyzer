// lib/widgets/rarity_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

// 與 ItemTypePie 共用，確保兩個 Pie 視覺大小一致。
// 直徑 = (75 + 40) × 2 = 230px，可在 ChartCard 預設 chart slot (~244px) 內安全顯示。
const double _kRingRadius = 75;
const double _kCenterRadius = 40;

List<DistributionEntry> rarityDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
) {
  return [
    DistributionEntry(
      color: tokens.fiveStar,
      name: '5★',
      count: stats.fiveStarCount,
      rate: stats.fiveStarRate,
    ),
    DistributionEntry(
      color: tokens.fourStar,
      name: '4★',
      count: stats.fourStarCount,
      rate: stats.fourStarRate,
    ),
    DistributionEntry(
      color: tokens.threeStar,
      name: '3★',
      count: stats.threeStarCount + stats.twoStarCount,
      rate: stats.threeStarRate + stats.twoStarRate,
    ),
  ];
}

class RarityPie extends StatelessWidget {
  const RarityPie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData, style: TextStyle(color: tokens.textMuted)),
      );
    }
    final sections = <PieChartSectionData>[
      _section(stats.fiveStarCount, tokens.fiveStar),
      _section(stats.fourStarCount, tokens.fourStar),
      _section(stats.threeStarCount + stats.twoStarCount, tokens.threeStar),
    ].where((s) => s.value > 0).toList(growable: false);
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: _kCenterRadius,
        pieTouchData: PieTouchData(enabled: false),
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  PieChartSectionData _section(int value, Color color) => PieChartSectionData(
    showTitle: false,
    value: value.toDouble(),
    color: color,
    radius: _kRingRadius,
  );
}
