import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開出「編輯別名」對話框；回傳去頭尾空白後的別名，空字串代表移除別名，取消時回傳 null。
///
/// [uid] 為顯示用 UID（已依隱私設定遮蔽），[initial] 為目前別名。
Future<String?> showEditAliasDialog({
  required BuildContext context,
  required String uid,
  required String initial,
}) => showDialog<String>(
  context: context,
  builder: (_) => _EditAliasDialog(uid: uid, initial: initial),
);

/// [showEditAliasDialog] 的對話框本體。
class _EditAliasDialog extends StatefulWidget {
  /// 建立 [_EditAliasDialog]。
  const _EditAliasDialog({required this.uid, required this.initial});

  /// 顯示在標題下方的 UID。
  final String uid;

  /// 輸入欄預填的目前別名。
  final String initial;

  @override
  State<_EditAliasDialog> createState() => _EditAliasDialogState();
}

/// State for [_EditAliasDialog]; 管理別名輸入欄。
class _EditAliasDialogState extends State<_EditAliasDialog> {
  /// 別名輸入欄 controller，預填目前別名。
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 關閉對話框並回傳去頭尾空白後的輸入值。
  void _submit() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.sm,
      title: Text(l.accountEditAliasTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.uid,
            style: const TextStyle(fontFeatures: kTabularFigures),
          ),
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.accountAliasLabel,
              hintText: l.accountAliasHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.actionSave)),
      ],
    );
  }
}
