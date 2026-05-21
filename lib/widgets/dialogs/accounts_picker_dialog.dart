import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 帳號挑選對話框中單一帳號的資料模型。
class AccountPickerEntry {
  /// 建立 [AccountPickerEntry]。
  const AccountPickerEntry({
    required this.uid,
    this.alias,
    required this.lastUpdated,
    required this.recordCount,
    this.badge,
  });

  /// 帳號 UID。
  final String uid;

  /// 使用者自訂別名；null 表示未設定。
  final String? alias;

  /// 最後一次更新祈願資料的時間。
  final DateTime lastUpdated;

  /// 該帳號的祈願紀錄總筆數。
  final int recordCount;

  /// 可選的紅色警示徽章文字（如「有新資料」提示）。
  final String? badge;
}

/// 顯示帳號挑選對話框；回傳被勾選的 UID 清單（保持 entries 傳入順序）。
/// 使用者取消時回傳 null。
Future<List<String>?> showAccountsPickerDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required List<AccountPickerEntry> entries,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AccountsPickerDialog(
      title: title,
      confirmLabel: confirmLabel,
      entries: entries,
    ),
  );
}

/// 帳號複選 dialog 的實作 widget。
class _AccountsPickerDialog extends StatefulWidget {
  const _AccountsPickerDialog({
    required this.title,
    required this.confirmLabel,
    required this.entries,
  });

  /// dialog 標題文字。
  final String title;

  /// 確認按鈕的標籤文字。
  final String confirmLabel;

  /// 可挑選的帳號條目列表。
  final List<AccountPickerEntry> entries;

  @override
  State<_AccountsPickerDialog> createState() => _AccountsPickerDialogState();
}

/// State for [_AccountsPickerDialog]; 管理勾選狀態。
class _AccountsPickerDialogState extends State<_AccountsPickerDialog> {
  /// 目前已勾選的 UID 集合；初始值為全選。
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.entries.map((e) => e.uid).toSet();
  }

  /// 「全選」checkbox 的三態值：true = 全選、false = 全不選、null = 部分選。
  bool? get _selectAllValue {
    if (_selected.isEmpty) return false;
    if (_selected.length == widget.entries.length) return true;
    return null;
  }

  /// [checked] 為 true 時全選，false 時清空。
  void _setAll(bool checked) {
    setState(() {
      if (checked) {
        _selected
          ..clear()
          ..addAll(widget.entries.map((e) => e.uid));
      } else {
        _selected.clear();
      }
    });
  }

  /// 切換單一 [uid] 的勾選狀態。
  void _toggle(String uid, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(uid);
      } else {
        _selected.remove(uid);
      }
    });
  }

  /// 處理「全選」checkbox 被點擊；接管 tristate cycle。
  void _onSelectAllTap() {
    // 自己接管 tristate cycle：true → false；false / null → true。
    _setAll(_selectAllValue != true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.md,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            tristate: true,
            value: _selectAllValue,
            title: Text(l.accountsPickerSelectAll),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            onChanged: (_) => _onSelectAllTap(),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = widget.entries[i];
                return _PickerRow(
                  entry: e,
                  selected: _selected.contains(e.uid),
                  onChanged: (v) => _toggle(e.uid, v ?? false),
                );
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.actionCancel),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final ordered = [
                    for (final e in widget.entries)
                      if (_selected.contains(e.uid)) e.uid,
                  ];
                  Navigator.of(context).pop(ordered);
                },
          icon: const Icon(Icons.check, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 帳號挑選列表中單一帳號的 checkbox row。
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.entry,
    required this.selected,
    required this.onChanged,
  });

  /// 該 row 對應的帳號資料。
  final AccountPickerEntry entry;

  /// 目前是否已勾選。
  final bool selected;

  /// 勾選狀態變更時的回呼。
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final alias = entry.alias;
    final title = (alias != null && alias.isNotEmpty)
        ? '${entry.uid} ($alias)'
        : entry.uid;
    final badge = entry.badge;
    return CheckboxListTile(
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.stateDanger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: tokens.stateDanger,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: DefaultTextStyle.merge(
        style: TextStyle(color: tokens.textMuted, fontSize: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RelativeTimeText(
              time: entry.lastUpdated,
              templateBuilder: l.accountLastUpdated,
            ),
            const Text(' ・ '),
            Text(l.accountRecordCount(entry.recordCount)),
          ],
        ),
      ),
    );
  }
}
