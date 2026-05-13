// lib/widgets/dialogs/new_version_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class NewVersionDialog extends ConsumerWidget {
  const NewVersionDialog({super.key, required this.releases});
  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;
    final maxHeight = MediaQuery.of(context).size.height * 0.6;

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
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in releases) ...[
                  _ReleaseCard(release: r, l: l),
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
            await launchUrl(
              Uri.parse(latest.htmlUrl),
              mode: LaunchMode.externalApplication,
            );
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.l});
  final AppRelease release;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final dateText = DateFormat(
      'yyyy-MM-dd',
    ).format(release.publishedAt.toLocal());

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Text(
                  l.updateReleasedAt(dateText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty) MarkdownBlock(data: release.body),
          ],
        ),
      ),
    );
  }
}
