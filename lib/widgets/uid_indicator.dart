// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final knownUids = state.knownUids.toList(growable: false);

    return PopupMenuButton<String>(
      tooltip: '切換帳號',
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
            child: Row(children: [
              Icon(
                uid == activeUid
                    ? Icons.check
                    : Icons.radio_button_unchecked,
                size: 16,
                color: uid == activeUid
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Text(uid),
              if (uid == activeUid) ...[
                const SizedBox(width: 4),
                const Text('（活躍）',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ]),
          ),
        if (knownUids.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(children: [
            Icon(Icons.refresh, size: 16),
            SizedBox(width: 8),
            Text('重新攔截 / 切換帳號'),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 4),
            Text(activeUid ?? '未同步'),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}
