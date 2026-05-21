import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

/// Pie 圓環外徑（邏輯像素）。與 [RarityPie] 共用，確保兩個 Pie 視覺大小一致。
/// 直徑 = (_kRingRadius + _kCenterRadius) × 2 = 230px，可在 ChartCard 預設 chart slot (~244px) 內安全顯示。
const double _kRingRadius = 75;

/// Pie 中心圓半徑（邏輯像素）。與 [_kRingRadius] 配合決定圓環寬度。
const double _kCenterRadius = 40;

// 物品類型 chart 專屬配色：與 GachaTokens 內既有的 character/weapon/rarity 等
// token 視覺脫鉤，避免「綠色 = 角色 / 紅色 = 武器」這類隨資料順序變動的誤判。
// 6 色色相均勻分布、跟稀有度三色（金/紫/藍）也不會撞色。

/// Dark mode 物品類型圓餅色板（順序對應 sorted entries）。
const _paletteDark = <Color>[
  Color(0xFF6BC5E5), // 天藍
  Color(0xFFF2849A), // 珊瑚粉
  Color(0xFFF5B66B), // 杏橘
  Color(0xFF85D6A8), // 薄荷綠
  Color(0xFFB59FE5), // 薰衣草紫
  Color(0xFF5EB8B0), // 青綠
];

/// Light mode 物品類型圓餅色板（順序對應 sorted entries）。
const _paletteLight = <Color>[
  Color(0xFF1E6AA8), // 鋼藍
  Color(0xFFC2627A), // 玫瑰
  Color(0xFFB87742), // 焦橘
  Color(0xFF3A8A66), // 森林薄荷
  Color(0xFF6E5BAB), // 靛紫
  Color(0xFF3A7A75), // 深青
];

/// 依 [Brightness] 回傳對應的物品類型色板。
List<Color> _itemTypePalette(Brightness b) =>
    b == Brightness.dark ? _paletteDark : _paletteLight;

/// 將 [stats] 轉為 [DistributionEntry] 列表，供圖例或 Pie chart 使用。
List<DistributionEntry> itemTypeDistributionEntries(
  GachaStats stats,
  Brightness brightness,
  AppLocalizations l,
) {
  final palette = _itemTypePalette(brightness);
  final sorted = stats.sortedItemTypes();
  return [
    for (final (i, e) in sorted.indexed)
      DistributionEntry(
        color: palette[i % palette.length],
        name: e.key.isEmpty ? l.kindUnknown : e.key,
        count: e.value,
        rate: stats.total == 0 ? 0.0 : e.value / stats.total,
      ),
  ];
}

/// 以圓環 Pie chart 呈現物品類型分佈的 widget。
class ItemTypePie extends StatelessWidget {
  /// 建立 [ItemTypePie]。
  const ItemTypePie({
    super.key,
    required this.stats,
    this.animationDuration = const Duration(milliseconds: 600),
  });

  /// 用於計算各 Pie 區塊比例的統計資料。
  final GachaStats stats;

  /// Pie chart 動畫時長。
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData, style: TextStyle(color: tokens.textMuted)),
      );
    }
    final palette = _itemTypePalette(theme.brightness);
    final sections = <PieChartSectionData>[
      for (final (i, e) in stats.sortedItemTypes().indexed)
        PieChartSectionData(
          showTitle: false,
          value: e.value.toDouble(),
          color: palette[i % palette.length],
          radius: _kRingRadius,
        ),
    ].where((s) => s.value > 0).toList(growable: false);
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: _kCenterRadius,
        pieTouchData: PieTouchData(enabled: false),
      ),
      duration: animationDuration,
      curve: Curves.easeOut,
    );
  }
}
