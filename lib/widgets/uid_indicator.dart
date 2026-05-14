// lib/widgets/uid_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UidIndicator extends ConsumerWidget {
  const UidIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishRepositoryProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final activeUid = state.activeUid;
    final l = AppLocalizations.of(context)!;

    final orderedUids = state.byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: state.byUid.keys,
            customOrder: settings.uidOrder,
            lastUpdatedOf: (u) => state.byUid[u]!.lastUpdated,
          );

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
        for (final uid in orderedUids)
          PopupMenuItem<String>(
            value: uid,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  uid == activeUid ? Icons.check : Icons.radio_button_unchecked,
                  size: 16,
                  color: uid == activeUid
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
                const SizedBox(width: AppSpacing.s),
                AccountMenuLabel(
                  uid: uid,
                  alias: settings.uidAliases[uid],
                  isActive: uid == activeUid,
                ),
              ],
            ),
          ),
        if (orderedUids.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__recapture__',
          child: Row(
            children: [
              const Icon(Icons.person_add_alt, size: 16),
              const SizedBox(width: AppSpacing.s),
              Text(l.uidRecapture),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
        child: AccountTriggerLabel(
          activeUid: activeUid,
          alias: activeUid == null ? null : settings.uidAliases[activeUid],
        ),
      ),
    );
  }
}

/// AppBar 觸發鈕的單行顯示:alias (uid),alias 過長 ellipsis;
/// 無 alias 顯示 UID;activeUid==null 顯示「未同步」。
class AccountTriggerLabel extends StatelessWidget {
  const AccountTriggerLabel({super.key, this.activeUid, this.alias});

  final String? activeUid;
  final String? alias;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final uid = activeUid;
    if (uid == null) {
      return _row([
        const Icon(Icons.person_outline, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Text(l.uidNotSynced),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]);
    }
    final hasAlias = alias != null && alias!.isNotEmpty;
    return _row([
      const Icon(Icons.person_outline, size: 18),
      const SizedBox(width: AppSpacing.xs),
      if (hasAlias) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(alias!, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(' ($uid)'),
      ] else
        Text(uid),
      const Icon(Icons.arrow_drop_down, size: 18),
    ]);
  }

  Widget _row(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);
}

/// 選單項目顯示:alias 主標 + UID 副標。沒 alias 時退化為 UID 單行。
class AccountMenuLabel extends StatelessWidget {
  const AccountMenuLabel({
    super.key,
    required this.uid,
    required this.isActive,
    this.alias,
  });

  final String uid;
  final String? alias;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final l = AppLocalizations.of(context)!;
    final hasAlias = alias != null && alias!.isNotEmpty;
    final primary = hasAlias ? alias! : uid;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Text(
                  l.uidActiveSuffix,
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
            ],
          ),
          if (hasAlias)
            Text(uid, style: TextStyle(fontSize: 12, color: tokens.textMuted)),
        ],
      ),
    );
  }
}
