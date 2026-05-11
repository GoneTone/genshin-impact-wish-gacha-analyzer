// lib/widgets/distribution_legend.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class DistributionEntry {
  const DistributionEntry({
    required this.color,
    required this.name,
    required this.count,
    required this.rate,
  });

  final Color color;
  final String name;
  final int count;

  /// 0.0 ~ 1.0
  final double rate;
}

class DistributionLegend extends StatelessWidget {
  const DistributionLegend({
    super.key,
    required this.entries,
    this.showAllEntries = false,
  });

  final List<DistributionEntry> entries;

  /// false (預設):過濾 count == 0 的條目 — Pie 圖例的慣例
  /// true:全部顯示 — 適合純色彩說明(如時間軸卡池色票)
  final bool showAllEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final visible = showAllEntries
        ? entries
        : entries.where((e) => e.count > 0).toList(growable: false);

    final tabular = const [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    e.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${e.count}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${(e.rate * 100).toStringAsFixed(2)}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textMuted,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
