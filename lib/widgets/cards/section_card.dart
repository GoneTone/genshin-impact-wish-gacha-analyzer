import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 帶標題的通用區塊卡片容器。
class SectionCard extends StatelessWidget {
  /// 建立 [SectionCard]。
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });

  /// 卡片標題文字。
  final String title;

  /// 卡片內容。
  final Widget child;

  /// 可選的標題前置圖示。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final titleText = Text(title, style: theme.textTheme.titleLarge);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}
