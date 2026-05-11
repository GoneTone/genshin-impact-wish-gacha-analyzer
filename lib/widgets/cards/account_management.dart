import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

class AccountManagement extends ConsumerWidget {
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final ordered = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(
              l.accountListEmpty,
              style: TextStyle(color: tokens.textMuted),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: ordered.length,
            onReorder: (oldIndex, newIndex) async {
              final next = [...ordered];
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = next.removeAt(oldIndex);
              next.insert(adjusted, item);
              await settingsNotifier.setUidOrder(next);
            },
            itemBuilder: (context, index) {
              final uid = ordered[index];
              return _Row(
                key: ValueKey(uid),
                uid: uid,
                index: index,
                lastUpdated: state.byUid[uid]!.lastUpdated,
                isActive: uid == state.activeUid,
                onSetActive: () => notifier.setActiveUid(uid),
                onRemove: () => _remove(context, ref, uid),
              );
            },
          ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.onSetActive,
    required this.onRemove,
  });

  final String uid;
  final int index;
  final DateTime lastUpdated;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: l.accountDragHandleTooltip,
              child: Icon(Icons.drag_handle, color: tokens.textMuted, size: 20),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      uid,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: AppSpacing.s),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentPrimary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          l.accountActiveTag,
                          style: TextStyle(
                            color: tokens.accentPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  l.accountLastUpdated(
                    DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(lastUpdated.toLocal()),
                  ),
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isActive)
            TextButton(onPressed: onSetActive, child: Text(l.accountSetActive)),
          TextButton(
            onPressed: onRemove,
            child: Text(
              l.accountRemove,
              style: TextStyle(color: tokens.stateDanger),
            ),
          ),
        ],
      ),
    );
  }
}
