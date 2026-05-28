import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

/// 新版本通知 dialog，列出自上次版本以來的所有 release notes。
class NewVersionDialog extends ConsumerWidget {
  /// 建立 [NewVersionDialog]，需傳入要顯示的 release 列表。
  const NewVersionDialog({super.key, required this.releases});

  /// 需要顯示的 release 列表（最新版在前）。
  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final latest = releases.first;

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.system_update, color: tokens.stateSuccess),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.updateTitle(latest.tagName))),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < releases.length; i++) ...[
            ReleaseNotesContent(release: releases[i]),
            if (i < releases.length - 1) const SizedBox(height: AppSpacing.m),
          ],
        ],
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
