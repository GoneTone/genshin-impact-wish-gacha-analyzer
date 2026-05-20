import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 包裹圖表的統一卡片容器，含標題列與可選圖例。
class ChartCard extends StatelessWidget {
  /// 建立 [ChartCard]。
  const ChartCard({
    super.key,
    required this.title,
    required this.chart,
    this.legend,
    this.height = 380,
    this.icon,
  });

  /// 卡片標題文字。
  final String title;

  /// 圖表 widget，[height] 有值時以 [Expanded] 填滿剩餘高度。
  final Widget chart;

  /// 可選圖例，顯示於圖表下方。
  final Widget? legend;

  /// 卡片固定高度；傳 `null` 則改為依內容 shrink-wrap，chart 不會被
  /// `Expanded` 撐滿（適合非圓形、自身有 intrinsic height 的圖表）。
  final double? height;

  /// 可選的標題前置圖示。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final fixedHeight = height != null;
    final titleText = Text(title, style: theme.textTheme.titleLarge);

    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon == null)
            titleText
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: tokens.textPrimary),
                const SizedBox(width: AppSpacing.s),
                Flexible(child: titleText),
              ],
            ),
          const SizedBox(height: AppSpacing.l),
          if (fixedHeight) Expanded(child: chart) else chart,
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.s),
            legend!,
          ],
        ],
      ),
    );
  }
}
