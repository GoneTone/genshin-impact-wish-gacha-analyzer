import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 顯示一個要求使用者打字確認的 dialog。
/// 回傳值：true = 確認 / false = 取消 / null = 系統 dismiss。
Future<bool?> showConfirmTypeDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String expectedText,
  required String cancelLabel,
  required String confirmLabel,
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
    ),
  );
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.cancelLabel,
    required this.confirmLabel,
  });
  final String title;
  final String body;
  final String expectedText;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
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
    return AlertDialog(
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
