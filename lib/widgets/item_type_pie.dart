// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

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
    return LayoutBuilder(
      builder: (context, c) {
        final available = _available(c);
        final outer = available / 2;
        final centerRadius = outer * 0.36;
        final ringRadius = outer - centerRadius;
        final sections = <PieChartSectionData>[
          _section(stats.characterCount, tokens.character, ringRadius),
          _section(stats.weaponCount, tokens.weapon, ringRadius),
          if (stats.unknownCount > 0)
            _section(stats.unknownCount, _unknownColor, ringRadius),
        ].where((s) => s.value > 0).toList(growable: false);
        return PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: 2,
            centerSpaceRadius: centerRadius,
          ),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      },
    );
  }

  double _available(BoxConstraints c) {
    final w = c.maxWidth.isFinite ? c.maxWidth : 140.0;
    final h = c.maxHeight.isFinite ? c.maxHeight : 140.0;
    return w < h ? w : h;
  }

  PieChartSectionData _section(int value, Color color, double radius) =>
      PieChartSectionData(
        showTitle: false,
        value: value.toDouble(),
        color: color,
        radius: radius,
      );
}
