import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 頁面頂部的標題區塊，含主標題、可選的副標題與前置圖示。
class PageHeader extends StatelessWidget {
  /// 建立 [PageHeader]。
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  /// 主標題文字。
  final String title;

  /// 副標題文字（可選）。
  final String? subtitle;

  /// 主標題前置圖示（可選）。
  final IconData? icon;

  /// 緊接在標題後方的小元件（可選）；同一行放不下時換到標題下一行。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final titleText = Text(title, style: theme.textTheme.headlineSmall);

    final heading = icon == null
        ? titleText
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: tokens.textPrimary),
              const SizedBox(width: AppSpacing.s),
              Flexible(child: titleText),
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing == null)
            heading
          else
            Wrap(
              spacing: AppSpacing.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [heading, trailing!],
            ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
