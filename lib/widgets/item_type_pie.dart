// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return const Center(child: Text('無資料'));
    }
    final sections = <PieChartSectionData>[
      _section('角色 ${stats.characterCount}', stats.characterCount, GachaColors.character),
      _section('武器 ${stats.weaponCount}', stats.weaponCount, GachaColors.weapon),
      if (stats.unknownCount > 0)
        _section('未知 ${stats.unknownCount}', stats.unknownCount, GachaColors.unknown),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
    );
  }

  PieChartSectionData _section(String title, int value, Color color) =>
      PieChartSectionData(
        title: title,
        value: value.toDouble(),
        color: color,
        radius: 60,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
}
