// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

// 與 RarityPie 共用，確保兩個 Pie 視覺大小一致。
// 直徑 = (75 + 40) × 2 = 230px，可在 ChartCard 預設 chart slot (~244px) 內安全顯示。
const double _kRingRadius = 75;
const double _kCenterRadius = 40;

List<Color> _itemTypePalette(GachaTokens t) => [
  t.character,
  t.weapon,
  t.accentPrimary,
  t.threeStar,
  t.fourStar,
  t.fiveStar,
  t.textMuted,
];

List<DistributionEntry> itemTypeDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
  AppLocalizations l,
) {
  final palette = _itemTypePalette(tokens);
  final sorted = stats.sortedItemTypes();
  return [
    for (final (i, e) in sorted.indexed)
      DistributionEntry(
        color: palette[i % palette.length],
        name: e.key.isEmpty ? l.kindUnknown : e.key,
        count: e.value,
        rate: stats.total == 0 ? 0.0 : e.value / stats.total,
      ),
  ];
}

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
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
    final palette = _itemTypePalette(tokens);
    final sections = <PieChartSectionData>[
      for (final (i, e) in stats.sortedItemTypes().indexed)
        PieChartSectionData(
          showTitle: false,
          value: e.value.toDouble(),
          color: palette[i % palette.length],
          radius: _kRingRadius,
        ),
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
}
