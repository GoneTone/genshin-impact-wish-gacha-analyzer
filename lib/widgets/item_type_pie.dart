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

const _unknownColor = Color(0xFF9E9E9E);

List<DistributionEntry> itemTypeDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
  AppLocalizations l,
) {
  return [
    DistributionEntry(
      color: tokens.character,
      name: l.kindCharacter,
      count: stats.characterCount,
      rate: stats.characterRate,
    ),
    DistributionEntry(
      color: tokens.weapon,
      name: l.kindWeapon,
      count: stats.weaponCount,
      rate: stats.weaponRate,
    ),
    if (stats.unknownCount > 0)
      DistributionEntry(
        color: _unknownColor,
        name: l.kindUnknown,
        count: stats.unknownCount,
        rate: stats.total == 0 ? 0.0 : stats.unknownCount / stats.total,
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
    final sections = <PieChartSectionData>[
      _section(stats.characterCount, tokens.character),
      _section(stats.weaponCount, tokens.weapon),
      if (stats.unknownCount > 0) _section(stats.unknownCount, _unknownColor),
    ].where((s) => s.value > 0).toList(growable: false);
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: _kCenterRadius,
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
