import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/edit_alias_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 帳號管理卡片：顯示所有已知 UID 的清單，支援排序、切換、編輯別名與刪除。
class AccountManagement extends ConsumerWidget {
  /// 建立 [AccountManagement]。
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final byUid = ref.watch(gachaRepositoryProvider.select((s) => s.byUid));
    final activeUid = ref.watch(
      gachaRepositoryProvider.select((s) => s.activeUid),
    );
    final uidAliases = ref.watch(settingsProvider.select((s) => s.uidAliases));
    final uidOrder = ref.watch(settingsProvider.select((s) => s.uidOrder));
    final maskUid = ref.watch(settingsProvider.select((s) => s.maskUidInUi));
    final notifier = ref.read(gachaRepositoryProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final ordered = byUid.isEmpty
        ? const <String>[]
        : mergeUidOrder(
            knownUids: byUid.keys,
            customOrder: uidOrder,
            lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
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
            // onReorderItem 取代 deprecated 的 onReorder；其 newIndex 已針對
            // 移除 oldIndex 後的清單調整好，直接 insert 即可，不需再自行 -1。
            onReorderItem: (oldIndex, newIndex) {
              final next = [...ordered];
              final item = next.removeAt(oldIndex);
              next.insert(newIndex, item);
              unawaited(settingsNotifier.setUidOrder(next));
            },
            itemBuilder: (context, index) {
              final uid = ordered[index];
              return _Row(
                key: ValueKey(uid),
                uid: uid,
                index: index,
                lastUpdated: byUid[uid]!.lastUpdated,
                isActive: uid == activeUid,
                alias: uidAliases[uid] ?? '',
                maskUid: maskUid,
                onSetActive: () => notifier.setActiveUid(uid),
                onRemove: () => _remove(context, ref, uid),
                onEditAlias: () => _editAlias(
                  context,
                  settingsNotifier,
                  uid,
                  uidAliases[uid] ?? '',
                  maskUid,
                ),
              );
            },
          ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: Text(l.accountAdd),
          ),
        ),
      ],
    );
  }

  /// 彈出編輯別名 dialog，確認後寫入設定；取消時不變。
  Future<void> _editAlias(
    BuildContext ctx,
    SettingsNotifier settingsNotifier,
    String uid,
    String current,
    bool mask,
  ) async {
    final value = await showEditAliasDialog(
      context: ctx,
      uid: displayUid(uid, mask: mask),
      initial: current,
    );
    if (value != null) await settingsNotifier.setUidAlias(uid, value);
  }

  /// 彈出打字確認 dialog（已連結雲端時附「同時從雲端移除」勾選），
  /// 確認後刪除本機帳號，勾選時再把 UID 排入雲端移除佇列。
  Future<void> _remove(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final linked = ref.read(settingsProvider).cloudAccountEmail != null;

    if (!linked) {
      final ok = await showConfirmTypeDialog(
        context: ctx,
        title: l.confirmTitle,
        body: l.confirmClearActiveBody(uid),
        expectedText: uid,
        cancelLabel: l.actionCancel,
        confirmLabel: l.confirmDelete,
        confirmIcon: Icons.delete_outline,
      );
      if (ok != true) return;
      await ref.read(gachaRepositoryProvider.notifier).removeUid(uid);
      return;
    }

    final result = await showConfirmTypeDialogWithCheckbox(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
      checkboxLabel: l.cloudSyncRemoveFromCloud,
    );
    if (result == null || !result.confirmed) return;
    await ref.read(gachaRepositoryProvider.notifier).removeUid(uid);
    if (result.checkboxChecked) {
      await ref.read(cloudSyncProvider.notifier).queueCloudRemoval(uid);
    }
  }
}

/// ⋮ 選單的動作。
enum _RowAction {
  /// 開啟別名編輯對話框，修改此 UID 的別名。
  editAlias,

  /// 將此 UID 設為使用中的帳號。
  setActive,

  /// 移除此 UID 的帳號，會先跳出確認對話框。
  remove,
}

/// 帳號清單中單一 UID 的可拖排緊湊列：UID、別名、最後更新與 ⋮ 動作選單。
class _Row extends StatelessWidget {
  /// 建立 [_Row]。
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.alias,
    required this.maskUid,
    required this.onSetActive,
    required this.onRemove,
    required this.onEditAlias,
  });

  /// 該 row 代表的 UID。
  final String uid;

  /// 在 [ReorderableListView] 中的排序位置，用於拖拉 handle。
  final int index;

  /// 最後一次更新祈願資料的時間。
  final DateTime lastUpdated;

  /// 是否為當前啟用的帳號。
  final bool isActive;

  /// 使用者自訂別名；空字串表示未設定。
  final String alias;

  /// 是否套用介面隱私模式（前 3 碼搭配 `•` 遮蔽）。
  final bool maskUid;

  /// 選單選「設為活躍」後呼叫。
  final VoidCallback onSetActive;

  /// 選單選「移除」後呼叫（確認流程由呼叫端處理）。
  final VoidCallback onRemove;

  /// 選單選「編輯別名」後呼叫。
  final VoidCallback onEditAlias;

  /// 依選取的 [action] 分派到對應 callback。
  void _onSelected(_RowAction action) => switch (action) {
    _RowAction.editAlias => onEditAlias(),
    _RowAction.setActive => onSetActive(),
    _RowAction.remove => onRemove(),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final compact = isCompactLayout(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: l.accountDragHandleTooltip,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                // 手機排版時把手的觸控區放大到 48dp，圖示大小不變。
                child: SizedBox.square(
                  dimension: compact ? 48 : null,
                  child: Icon(
                    Icons.drag_handle,
                    color: tokens.textMuted,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayUid(uid, mask: maskUid),
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                    if (isActive)
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
                ),
                Text(
                  alias.isEmpty ? l.accountAliasNone : alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: alias.isEmpty
                        ? tokens.textMuted
                        : tokens.textPrimary,
                  ),
                ),
                RelativeTimeText(
                  time: lastUpdated,
                  templateBuilder: l.accountLastUpdated,
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<_RowAction>(
            onSelected: _onSelected,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _RowAction.editAlias,
                child: Text(l.accountActionEditAlias),
              ),
              if (!isActive)
                PopupMenuItem(
                  value: _RowAction.setActive,
                  child: Text(l.accountSetActive),
                ),
              PopupMenuItem(
                value: _RowAction.remove,
                child: Text(
                  l.accountRemove,
                  style: TextStyle(color: tokens.stateDanger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
