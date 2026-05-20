import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// Pie 圖例或色票說明的單一條目資料。
class DistributionEntry {
  /// 建立 [DistributionEntry]。
  const DistributionEntry({
    required this.color,
    required this.name,
    required this.count,
    required this.rate,
  });

  /// 色塊顏色。
  final Color color;

  /// 條目名稱。
  final String name;

  /// 數量。
  final int count;

  /// 佔比，範圍 0.0 ~ 1.0。
  final double rate;
}

/// 以色塊、名稱、數量、百分比呈現分佈資料的圖例列表。
class DistributionLegend extends StatelessWidget {
  /// 建立 [DistributionLegend]。
  const DistributionLegend({
    super.key,
    required this.entries,
    this.showAllEntries = false,
  });

  /// 圖例條目列表。
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
