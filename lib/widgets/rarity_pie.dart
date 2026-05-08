import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class RarityPie extends StatelessWidget {
  const RarityPie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return const Center(child: Text('無資料'));
    }
    final sections = <PieChartSectionData>[
      _section('5★ ${stats.fiveStarCount}', stats.fiveStarCount, GachaColors.fiveStar),
      _section('4★ ${stats.fourStarCount}', stats.fourStarCount, GachaColors.fourStar),
      _section('3★ ${stats.threeStarOrBelowCount}', stats.threeStarOrBelowCount, GachaColors.threeStar),
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
