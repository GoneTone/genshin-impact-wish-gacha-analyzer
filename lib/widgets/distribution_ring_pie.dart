import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

/// Pie 圓環外徑（邏輯像素）。RarityPie / ItemTypePie 共用此值，確保兩個 Pie 視覺
/// 大小一致。直徑 = (_kRingRadius + _kCenterRadius) × 2 = 230px，可在 ChartCard
/// 預設 chart slot (~244px) 內安全顯示。
const double _kRingRadius = 75;

/// Pie 中心圓半徑（邏輯像素）。與 [_kRingRadius] 配合決定圓環寬度。
const double _kCenterRadius = 40;

/// 預設圓環直徑（邏輯像素），即 [_kRingRadius] 與 [_kCenterRadius] 的總和乘二。
const double kDefaultRingDiameter = (_kRingRadius + _kCenterRadius) * 2;

/// 以圓環 Pie chart 呈現分佈資料的共用 widget（稀有度／物品類型共用）。
///
/// [entries] 提供每段的顏色與數量（count == 0 的段自動略過）；[total] 為整體抽數，
/// 為 0 時顯示「無資料」佔位文字而非空圓環。
class DistributionRingPie extends StatelessWidget {
  /// 建立 [DistributionRingPie]。
  const DistributionRingPie({
    super.key,
    required this.entries,
    required this.total,
    this.animationDuration = const Duration(milliseconds: 600),
    this.diameter = kDefaultRingDiameter,
  });

  /// 圓環直徑；小於預設時外徑與中心圓半徑等比縮小。
  final double diameter;

  /// 各分段資料（顏色 + 數量）。
  final List<DistributionEntry> entries;

  /// 整體抽數；為 0 時顯示無資料佔位。
  final int total;

  /// Pie chart 動畫時長。
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (total == 0) {
      return Center(
        child: Text(l.statsNoData, style: TextStyle(color: tokens.textMuted)),
      );
    }
    final scale = diameter / kDefaultRingDiameter;
    final sections = <PieChartSectionData>[
      for (final e in entries)
        if (e.count > 0)
          PieChartSectionData(
            showTitle: false,
            value: e.count.toDouble(),
            color: e.color,
            radius: _kRingRadius * scale,
          ),
    ];
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: _kCenterRadius * scale,
        pieTouchData: PieTouchData(enabled: false),
      ),
      duration: animationDuration,
      curve: Curves.easeOut,
    );
  }
}
