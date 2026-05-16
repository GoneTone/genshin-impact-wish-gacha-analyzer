import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// 縮小版:用於「頁面內某個 section 的空位佔位」(icon 40px + 邊框框出範圍),
  /// 非滿屏置中。
  final bool compact;

  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: l.emptyNoSyncMessage,
      action: action,
    );
  }

  /// `title` 可選 override 既定 `l.emptyNoRecords`,讓不同 section 共用此 factory。
  /// `compact: true` 時改為縮小版邊框 placeholder,非滿屏。
  factory EmptyState.noRecords(
    BuildContext context, {
    String? title,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: title ?? l.emptyNoRecords,
      compact: compact,
    );
  }

  factory EmptyState.noFiltered(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: l.emptyNoFilterMatch,
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: AppSpacing.l,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.s),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.m),
              action!,
            ],
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: tokens.textMuted),
          const SizedBox(height: AppSpacing.l),
          Text(title, style: theme.textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.l),
            action!,
          ],
        ],
      ),
    );
  }
}
