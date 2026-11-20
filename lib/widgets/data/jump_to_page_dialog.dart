import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開出「前往頁數」對話框；回傳使用者輸入的 0-based 頁碼，取消時回傳 null。
///
/// [currentPage] 為 0-based；[totalItems] 有值時另顯示目前頁與總筆數。
Future<int?> showJumpToPageDialog({
  required BuildContext context,
  required int currentPage,
  required int totalPages,
  int? totalItems,
}) => showDialog<int>(
  context: context,
  builder: (_) => _JumpToPageDialog(
    currentPage: currentPage,
    totalPages: totalPages,
    totalItems: totalItems,
  ),
);

/// [showJumpToPageDialog] 的對話框本體。
class _JumpToPageDialog extends StatefulWidget {
  /// 建立 [_JumpToPageDialog]。
  const _JumpToPageDialog({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
  });

  /// 目前頁碼（0-based）。
  final int currentPage;

  /// 總頁數。
  final int totalPages;

  /// 總筆數；null 時不顯示筆數提示。
  final int? totalItems;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

/// State for [_JumpToPageDialog]; 管理頁碼輸入欄。
class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  /// 頁碼輸入欄 controller，預填目前頁（1-based）並全選。
  late final _ctrl = TextEditingController(text: '${widget.currentPage + 1}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.currentPage + 1}'.length,
    );

  /// 輸入內容解析出的 1-based 頁碼；空白、非數字或超出範圍時為 null。
  int? get _target {
    final n = int.tryParse(_ctrl.text);
    return n != null && n >= 1 && n <= widget.totalPages ? n : null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 輸入合法時關閉對話框並回傳 0-based 頁碼。
  void _submit() {
    final n = _target;
    if (n != null) Navigator.of(context).pop(n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final max = widget.totalPages;
    final valid = _target != null;
    return AppDialog(
      title: Text(l.pagerJumpTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.totalItems != null) ...[
            Text(
              l.pagerJumpCurrent(widget.currentPage + 1, widget.totalItems!),
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.pagerJumpLabel(1, max),
              errorText: valid ? null : l.pagerJumpInvalid(1, max),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: valid ? _submit : null,
          child: Text(l.pagerJumpGo),
        ),
      ],
    );
  }
}
