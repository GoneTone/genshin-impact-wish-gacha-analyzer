import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_ring_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';

/// [ChartCard] 的版面：標準（圖在上、圖例在下）與手機精簡（圖例在圓餅側邊）。
enum ChartCardLayout {
  /// 標準版：固定高度，圖表在上、圖例在下。
  standard(kDefaultRingDiameter),

  /// 精簡版：標題在上，下方為圓餅與右側圖例，高度依內容。
  compact(112),

  /// 手機橫向精簡版：圓餅在左，標題與圖例疊在右側欄。
  compactTitleBeside(96);

  const ChartCardLayout(this.chartDiameter);

  /// 此版面下圓餅的直徑（邏輯像素）。
  final double chartDiameter;

  /// 是否為精簡版（圖例在圓餅側邊）。
  bool get isCompact => this != standard;

  /// 依頁面內容寬 [width] 與裝置方向挑選圓餅卡版面：手機橫向優先，其次寬度小於 800。
  static ChartCardLayout of(BuildContext context, double width) {
    if (phoneOrientationOf(context) == PhoneOrientation.landscape) {
      return compactTitleBeside;
    }
    return width < 800 ? compact : standard;
  }
}

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
    this.layout = ChartCardLayout.standard,
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

  /// 卡片版面；非 [ChartCardLayout.standard] 時忽略 [height]，圖表固定為
  /// [ChartCardLayout.chartDiameter] 見方，圖例排在圖表右側。
  final ChartCardLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final fixedHeight = height != null;
    final titleText = icon == null
        ? Text(title, style: theme.textTheme.titleLarge)
        : InlineSectionTitle(icon: icon!, title: title);

    /// 精簡版用的固定尺寸圓餅。
    Widget chartBox() =>
        SizedBox.square(dimension: layout.chartDiameter, child: chart);

    final Widget body = switch (layout) {
      ChartCardLayout.standard => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          titleText,
          const SizedBox(height: AppSpacing.l),
          if (fixedHeight) Expanded(child: chart) else chart,
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.s),
            legend!,
          ],
        ],
      ),
      ChartCardLayout.compact => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          titleText,
          const SizedBox(height: AppSpacing.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chartBox(),
              const SizedBox(width: AppSpacing.m),
              Expanded(child: legend ?? const SizedBox.shrink()),
            ],
          ),
        ],
      ),
      ChartCardLayout.compactTitleBeside => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chartBox(),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleText,
                const SizedBox(height: AppSpacing.s),
                legend ?? const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    };

    return Container(
      height: layout.isCompact ? null : height,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: body,
    );
  }
}
