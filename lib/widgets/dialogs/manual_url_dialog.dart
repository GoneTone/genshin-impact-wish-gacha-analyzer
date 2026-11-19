import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url_extract.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/landscape_input_field.dart';

/// 本對話框的 logger。
final _log = Logger('capture.manual');

/// 顯示「手動輸入祈願紀錄網址」對話框：貼上網址或含網址的整段文字。
Future<void> showManualUrlDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ManualUrlDialog(),
);

/// 手動輸入對話框實作。
class _ManualUrlDialog extends ConsumerStatefulWidget {
  /// 建立 [_ManualUrlDialog]。
  const _ManualUrlDialog();

  @override
  ConsumerState<_ManualUrlDialog> createState() => _ManualUrlDialogState();
}

/// [_ManualUrlDialog] 的狀態：輸入內容與錯誤訊息。
class _ManualUrlDialogState extends ConsumerState<_ManualUrlDialog> {
  /// 網址輸入框的 controller。
  final _controller = TextEditingController();

  /// 目前顯示的錯誤訊息；沒有錯誤時為 null。
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 把剪貼簿文字填進輸入框。
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  /// 從輸入框文字找祈願網址，找到就送出並關閉。
  void _submit() {
    final url = latestApiUrlIn(_controller.text);
    if (url == null) {
      _log.info('manual input rejected: no wish url in pasted text');
      setState(() => _error = AppLocalizations.of(context)!.manualUrlNotFound);
      return;
    }
    Navigator.of(context).pop();
    unawaited(ref.read(gachaRepositoryProvider.notifier).submitManualUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AppDialog(
      size: AppDialogSize.md,
      scrollable: true,
      title: Text(l.manualUrlTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.manualUrlHint),
          const SizedBox(height: AppSpacing.s),
          LandscapeInputField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            // 輸入法的自動校正會改掉網址參數名稱的大小寫（`lang` → `Lang`）。
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l.manualUrlFieldHint,
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: AppSpacing.s),
          Align(
            child: OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste, size: 18),
              label: Text(l.manualUrlPaste),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            l.manualUrlWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.gacha.stateWarning,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.manualUrlSubmit)),
      ],
    );
  }
}
