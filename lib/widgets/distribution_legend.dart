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
    this.compact = false,
  });

  /// 圖例條目列表。
  final List<DistributionEntry> entries;

  /// false (預設):過濾 count == 0 的條目 — Pie 圖例的慣例
  /// true:全部顯示 — 適合純色彩說明(如時間軸卡池色票)
  final bool showAllEntries;

  /// true：窄欄用的精簡版，件數與百分比欄寬縮小並隨字級縮放；名稱放不下時數字改排到下一行。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final scaler = MediaQuery.textScalerOf(context);
    // Roboto 14dp 下「12345」約 41dp、「100.00%」約 55dp，各留一點餘裕才不會斷行。
    // shortcut: 件數只量到五位數，六位數以上會斷行；真有帳號抽到十萬抽再改成依內容量寬。
    final countWidth = compact ? scaler.scale(44) : 60.0;
    final rateWidth = compact ? scaler.scale(58) : 70.0;
    final visible = showAllEntries
        ? entries
        : entries.where((e) => e.count > 0).toList(growable: false);

    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.textPrimary,
    );

    /// [e] 的色塊與名稱；名稱超過可用寬度時才換行。
    Widget swatchAndName(DistributionEntry e) => Row(
      mainAxisSize: MainAxisSize.min,
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
        Flexible(child: Text(e.name, style: nameStyle)),
      ],
    );

    /// [e] 的件數與百分比，各自靠右對齊在固定寬度欄內。
    Widget countAndRate(DistributionEntry e) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: countWidth,
          child: Text(
            '${e.count}',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: rateWidth,
          child: Text(
            '${(e.rate * 100).toStringAsFixed(2)}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textMuted,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            // 精簡版名稱欄很窄，放大字級時長名稱會逐字斷行；整列放不下就把數字移到名稱下一行。
            // 用 OverflowBar 而非 LayoutBuilder：橫向圓餅卡外層有 IntrinsicHeight。
            child: compact
                ? OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    children: [swatchAndName(e), countAndRate(e)],
                  )
                : Row(
                    children: [
                      Expanded(child: swatchAndName(e)),
                      countAndRate(e),
                    ],
                  ),
          ),
      ],
    );
  }
}
