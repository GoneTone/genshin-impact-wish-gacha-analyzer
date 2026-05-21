import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 用在頁面內、不在卡片裡的區塊標題（titleLarge + 前置 icon）。
/// 視覺與 [SectionCard]、[ChartCard] 的標題列一致。
class InlineSectionTitle extends StatelessWidget {
  /// 建立 [InlineSectionTitle]。
  const InlineSectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  /// 標題前置圖示。
  final IconData icon;

  /// 標題文字。
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: tokens.textPrimary),
        const SizedBox(width: AppSpacing.s),
        Flexible(child: Text(title, style: theme.textTheme.titleLarge)),
      ],
    );
  }
}
