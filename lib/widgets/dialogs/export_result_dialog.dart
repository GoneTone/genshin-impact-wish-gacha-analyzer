import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 匯出結果統一彈窗：取代原本的 SnackBar + 自動開檔案總管。
///
/// - [success] 決定標題（成功／失敗）。
/// - [message] dialog 內文（呼叫端已在地化好的完整訊息）。
/// - [revealPath] 有值才顯示「開啟資料夾」鈕，點下去以
///   [revealInFileManager] 開檔案總管並選中該檔案；無值（如分享圖
///   copiedOnly、或失敗）則只有「關閉」鈕。
Future<void> showExportResultDialog(
  BuildContext context, {
  required bool success,
  required String message,
  String? revealPath,
}) {
  final l = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AppDialog(
      title: Text(
        success ? l.exportDialogSuccessTitle : l.exportDialogFailedTitle,
      ),
      content: Text(message),
      actions: [
        if (revealPath != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(revealInFileManager(revealPath));
            },
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(l.actionOpenFolder),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.actionClose),
        ),
      ],
    ),
  );
}
