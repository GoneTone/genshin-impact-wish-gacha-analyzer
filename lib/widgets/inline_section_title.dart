// lib/widgets/inline_section_title.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 用在頁面內、不在卡片裡的區塊標題（titleLarge + 前置 icon）。
/// 視覺與 [SectionCard]、[ChartCard] 的標題列一致。
class InlineSectionTitle extends StatelessWidget {
  const InlineSectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
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
