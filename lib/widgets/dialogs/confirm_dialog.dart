import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示一個要求使用者打字確認的 dialog。
/// 回傳值：true = 確認 / false = 取消 / null = 系統 dismiss。
Future<bool?> showConfirmTypeDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String expectedText,
  required String cancelLabel,
  required String confirmLabel,
  required IconData confirmIcon,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      body: body,
      expectedText: expectedText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      confirmIcon: confirmIcon,
    ),
  );
}

/// 打字確認 dialog 的實作 widget。
class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.confirmIcon,
  });

  /// dialog 標題文字。
  final String title;

  /// 說明文字，描述此操作的後果。
  final String body;

  /// 使用者必須完整打出的確認字串（通常為 UID）。
  final String expectedText;

  /// 取消按鈕標籤。
  final String cancelLabel;

  /// 確認按鈕標籤。
  final String confirmLabel;

  /// 確認按鈕前置圖示。
  final IconData confirmIcon;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

/// State for [_ConfirmDialog]; 管理打字確認 TextField 的 controller。
class _ConfirmDialogState extends State<_ConfirmDialog> {
  /// 確認字串輸入欄的 controller；內容與 [_ConfirmDialog.expectedText] 比對。
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final matches = _ctrl.text == widget.expectedText;
    return AppDialog(
      // size 預設 sm，符合短訊息語意，不必顯式傳。
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: AppSpacing.l),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 18),
          label: Text(widget.cancelLabel),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          icon: Icon(widget.confirmIcon, size: 18),
          label: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
