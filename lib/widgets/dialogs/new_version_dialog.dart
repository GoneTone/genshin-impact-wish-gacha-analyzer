// lib/widgets/dialogs/new_version_dialog.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

class NewVersionDialog extends ConsumerWidget {
  const NewVersionDialog({super.key, required this.releases});
  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;
    final mq = MediaQuery.of(context);
    // AlertDialog 預設左右 insetPadding 共 80,先扣掉再卡 720 上限,避免窄視窗撐爆。
    final dialogWidth = math.min(720.0, mq.size.width - 80);
    final maxHeight = mq.size.height * 0.6;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < releases.length; i++) ...[
                  _ReleaseCard(release: releases[i], l: l),
                  if (i < releases.length - 1)
                    const SizedBox(height: AppSpacing.m),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appReleaseProvider.notifier)
                .skipVersion(latest.tagName);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l.updateButtonSkip),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.updateButtonLater),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l.updateButtonDownload),
          onPressed: () async {
            await openExternalUrl(Uri.parse(latest.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

MarkdownConfig _markdownConfig(ThemeData theme) {
  final base = theme.brightness == Brightness.dark
      ? MarkdownConfig.darkConfig
      : MarkdownConfig.defaultConfig;
  return base.copy(
    configs: [
      LinkConfig(
        style: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
      ),
    ],
  );
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.l});
  final AppRelease release;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                RelativeTimeText(
                  time: release.publishedAt,
                  templateBuilder: l.updateReleasedAt,
                  useDateOnly: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty)
              MarkdownBlock(data: release.body, config: _markdownConfig(theme)),
          ],
        ),
      ),
    );
  }
}
