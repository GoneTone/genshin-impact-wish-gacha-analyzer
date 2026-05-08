// lib/widgets/stats_panel.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('總抽數：${stats.total}',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            _row('5★ 中獎率', stats.fiveStarCount, stats.fiveStarRate, GachaColors.fiveStar, bold: true),
            _row('4★ 中獎率', stats.fourStarCount, stats.fourStarRate, GachaColors.fourStar),
            _row('3★ 中獎率', stats.threeStarOrBelowCount, stats.threeStarOrBelowRate, GachaColors.threeStar),
            const SizedBox(height: 8),
            _row('角色中獎率', stats.characterCount, stats.characterRate, GachaColors.character),
            _row('武器中獎率', stats.weaponCount, stats.weaponRate, GachaColors.weapon),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int count, double rate, Color color,
      {bool bold = false}) {
    final pct = (rate * 100).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text('$pct%  ($count)',
              style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
