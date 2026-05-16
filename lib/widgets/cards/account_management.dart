import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

class AccountManagement extends ConsumerWidget {
  const AccountManagement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final byUid = ref.watch(wishRepositoryProvider.select((s) => s.byUid));
    final activeUid = ref.watch(
      wishRepositoryProvider.select((s) => s.activeUid),
    );
    final uidAliases = ref.watch(settingsProvider.select((s) => s.uidAliases));
    final uidOrder = ref.watch(settingsProvider.select((s) => s.uidOrder));
    final notifier = ref.read(wishRepositoryProvider.notifier);
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
            onReorder: (oldIndex, newIndex) {
              final next = [...ordered];
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              final item = next.removeAt(oldIndex);
              next.insert(adjusted, item);
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
                onSetActive: () => notifier.setActiveUid(uid),
                onRemove: () => _remove(context, ref, uid),
                onAliasSubmit: (value) =>
                    settingsNotifier.setUidAlias(uid, value),
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
      cancelLabel: l.actionCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.uid,
    required this.index,
    required this.lastUpdated,
    required this.isActive,
    required this.alias,
    required this.onSetActive,
    required this.onRemove,
    required this.onAliasSubmit,
  });

  final String uid;
  final int index;
  final DateTime lastUpdated;
  final bool isActive;
  final String alias;
  final VoidCallback onSetActive;
  final VoidCallback onRemove;
  final ValueChanged<String> onAliasSubmit;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.alias);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部 alias 變了（例如其他 row 觸發 rebuild）才 sync
    if (widget.alias != oldWidget.alias && _ctrl.text != widget.alias) {
      _ctrl.text = widget.alias;
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      widget.onAliasSubmit(_ctrl.text);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Tooltip(
              message: l.accountDragHandleTooltip,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: Icon(
                  Icons.drag_handle,
                  color: tokens.textMuted,
                  size: 20,
                ),
              ),
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
                      widget.uid,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (widget.isActive) ...[
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
                RelativeTimeText(
                  time: widget.lastUpdated,
                  templateBuilder: l.accountLastUpdated,
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: widget.onAliasSubmit,
                    decoration: InputDecoration(
                      labelText: l.accountAliasLabel,
                      hintText: l.accountAliasHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isActive)
            TextButton.icon(
              onPressed: widget.onSetActive,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(l.accountSetActive),
            ),
          TextButton.icon(
            onPressed: widget.onRemove,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: tokens.stateDanger,
            ),
            label: Text(
              l.accountRemove,
              style: TextStyle(color: tokens.stateDanger),
            ),
          ),
        ],
      ),
    );
  }
}
