// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final knownUids = state.knownUids.toList(growable: false);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    return PopupMenuButton<String>(
      tooltip: l.uidSwitchTooltip,
      onSelected: (key) async {
        if (key == '__recapture__') {
          await notifier.forceRecaptureAndUpdate();
        } else {
          await notifier.setActiveUid(key);
        }
      },
      itemBuilder: (context) => [
        for (final uid in knownUids)
          PopupMenuItem<String>(
            value: uid,
            child: Row(
              children: [
                Icon(
                  uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
                  size: 16,
                  color: uid == activeUid
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
                const SizedBox(width: AppSpacing.s),
                Text(uid),
                if (uid == activeUid) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l.uidActiveSuffix,
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
        if (knownUids.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 16),
              const SizedBox(width: AppSpacing.s),
              Text(l.uidRecapture),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(activeUid ?? l.uidNotSynced),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
