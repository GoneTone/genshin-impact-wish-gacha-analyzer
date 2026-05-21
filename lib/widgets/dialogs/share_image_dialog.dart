import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開啟分享圖選項 dialog。回傳 null 表示使用者取消。
Future<ShareImageOptions?> showShareImageDialog(
  BuildContext context, {
  required Brightness initialBrightness,
}) {
  return showDialog<ShareImageOptions>(
    context: context,
    builder: (_) => _ShareImageDialog(initialBrightness: initialBrightness),
  );
}

/// 分享圖選項 dialog 的實作 widget。
class _ShareImageDialog extends StatefulWidget {
  const _ShareImageDialog({required this.initialBrightness});

  /// 初始亮暗模式，通常取自目前 app 主題。
  final Brightness initialBrightness;

  @override
  State<_ShareImageDialog> createState() => _ShareImageDialogState();
}

/// State for [_ShareImageDialog]; 管理使用者選擇的分享圖選項。
class _ShareImageDialogState extends State<_ShareImageDialog> {
  /// 目前選擇的分享圖亮暗模式。
  late Brightness _brightness = widget.initialBrightness;

  /// 是否在分享圖中顯示完整 UID（預設遮蔽後四碼）。
  bool _showFullUid = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.sm,
      title: Text(l.shareImageDialogTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.shareImageThemeLabel),
          const SizedBox(height: AppSpacing.s),
          SegmentedButton<Brightness>(
            segments: [
              ButtonSegment(
                value: Brightness.dark,
                label: Text(l.shareImageThemeDark),
              ),
              ButtonSegment(
                value: Brightness.light,
                label: Text(l.shareImageThemeLight),
              ),
            ],
            selected: {_brightness},
            onSelectionChanged: (s) => setState(() => _brightness = s.first),
          ),
          const SizedBox(height: AppSpacing.l),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showFullUid,
            onChanged: (v) => setState(() => _showFullUid = v),
            title: Text(l.shareImageShowFullUid),
            subtitle: Text(l.shareImageShowFullUidHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ShareImageOptions(
              brightness: _brightness,
              showFullUid: _showFullUid,
            ),
          ),
          child: Text(l.shareImageGenerate),
        ),
      ],
    );
  }
}
