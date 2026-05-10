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
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: l.emptyNoSyncMessage,
      action: action,
    );
  }

  factory EmptyState.noRecords(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(icon: Icons.inbox_outlined, title: l.emptyNoRecords);
  }

  factory EmptyState.noFiltered(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: l.emptyNoFiltered,
      action: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
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
