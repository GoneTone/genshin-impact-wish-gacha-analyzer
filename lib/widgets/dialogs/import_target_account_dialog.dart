import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/uid_display.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示「匯入到哪個帳號？」對話框（匯出檔沒有 UID 的平台用），回傳選定的 UID；
/// 取消回 null。
///
/// [accounts] 為本機帳號，預選第一個；最後一項「其他 UID」附輸入框。空清單時
/// 只顯示輸入框。UID 不符合 [isValidUid] 時「繼續」不能按。
Future<String?> showImportTargetAccountDialog({
  required BuildContext context,
  required List<AccountPickerEntry> accounts,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportTargetAccountDialog(accounts: accounts),
  );
}

/// 選匯入目標帳號 dialog 的實作 widget。
class _ImportTargetAccountDialog extends StatefulWidget {
  /// 建立 [_ImportTargetAccountDialog]。
  const _ImportTargetAccountDialog({required this.accounts});

  /// 本機帳號。
  final List<AccountPickerEntry> accounts;

  @override
  State<_ImportTargetAccountDialog> createState() =>
      _ImportTargetAccountDialogState();
}

/// State for [_ImportTargetAccountDialog]；管理單選與 UID 輸入框。
class _ImportTargetAccountDialogState
    extends State<_ImportTargetAccountDialog> {
  /// 「其他 UID」選項的值；UID 不會是空字串，所以不會跟帳號撞。
  static const _other = '';

  /// UID 輸入框的 controller。
  final _ctrl = TextEditingController();

  /// 目前選的 UID；[_other] 表示用輸入框的值。
  late String _selected = widget.accounts.firstOrNull?.uid ?? _other;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 目前選定、可以送出的 UID；輸入框的值格式不對時回 null。
  String? get _target {
    if (_selected != _other) return _selected;
    final typed = _ctrl.text.trim();
    return isValidUid(typed) ? typed : null;
  }

  /// 以 [_target] 關閉對話框；沒有合法 UID 時不動作。
  void _confirm() {
    if (_target case final uid?) Navigator.of(context).pop(uid);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final compact = isCompactLayout(context);
    final field = TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      // 手機橫向會改在全螢幕輸入頁打字，看不到對話框的說明，提示要輸入的內容。
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: l.importTargetAccountUidHint,
      ),
      onTap: () => setState(() => _selected = _other),
      onChanged: (_) => setState(() => _selected = _other),
      onSubmitted: (_) => _confirm(),
    );
    return AppDialog(
      scrollable: true,
      title: Text(l.importTargetAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.importTargetAccountBody),
          const SizedBox(height: AppSpacing.m),
          if (widget.accounts.isEmpty)
            field
          else
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) {
                if (v != null) setState(() => _selected = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in widget.accounts)
                    RadioListTile<String>(
                      value: a.uid,
                      contentPadding: EdgeInsets.zero,
                      title: _AccountLabel(
                        entry: a,
                        compact: compact,
                        countStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  RadioListTile<String>(
                    value: _other,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.importTargetAccountOtherUid),
                  ),
                  field,
                ],
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
          onPressed: _target == null ? null : _confirm,
          icon: const Icon(Icons.check, size: 18),
          label: Text(l.confirmContinue),
        ),
      ],
    );
  }
}

/// 帳號列的文字：別名＋UID 與本機筆數；[compact] 時筆數換到第二行。
class _AccountLabel extends ConsumerWidget {
  /// 建立 [_AccountLabel]。
  const _AccountLabel({
    required this.entry,
    required this.compact,
    required this.countStyle,
  });

  /// 該列的帳號。
  final AccountPickerEntry entry;

  /// 是否為手機排版（筆數換行）。
  final bool compact;

  /// 筆數文字的樣式。
  final TextStyle countStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final mask = ref.watch(settingsProvider.select((s) => s.maskUidInUi));
    final uid = displayUid(entry.uid, mask: mask);
    final alias = entry.alias;
    final name = Text(alias == null || alias.isEmpty ? uid : '$alias ($uid)');
    final count = Text(
      l.importTargetAccountRecordCount(entry.recordCount),
      style: countStyle,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [name, count],
      );
    }
    return Row(
      children: [
        Expanded(child: name),
        const SizedBox(width: AppSpacing.m),
        count,
      ],
    );
  }
}
