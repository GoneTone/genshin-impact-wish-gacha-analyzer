import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_image_save.dart';

/// 物品圖選單動作的 logger（命名空間 gacha.hoyowiki.save）。
final _log = Logger('gacha.hoyowiki.save');

/// 物品圖選單項目（複製圖片 / 儲存圖片 /（[share] 為 true 時）分享）；
/// 詳情對話框與看圖 overlay 共用。
List<PopupMenuEntry<String>> itemImageMenuItems(
  AppLocalizations l, {
  required bool share,
}) => [
  _menuItem('copy', Icons.copy, l.actionCopyImage),
  _menuItem('save', Icons.save_alt, l.actionSaveImage),
  if (share) _menuItem('share', Icons.share, l.actionShare),
];

/// 建立單一選單項目。
PopupMenuItem<String> _menuItem(String value, IconData icon, String title) =>
    PopupMenuItem(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20),
        title: Text(title),
      ),
    );

/// 執行 [itemImageMenuItems] 的選項（`copy`／`save`／`share`，其他值不處理）：
/// 把 [file] 準備成輸出圖（GIF 保留、其餘轉 PNG）後複製、存檔或分享，檔名為
/// [suggestedBaseName] 加上實際副檔名；結果以 [toast] 回報，並記一行 info log。
///
/// [toast] 會在非同步完成後才被呼叫，呼叫端需自行確認 widget 仍 mounted。
Future<void> runItemImageAction(
  String value, {
  required File file,
  required String suggestedBaseName,
  required AppLocalizations l,
  required void Function(String message) toast,
}) async {
  if (value != 'copy' && value != 'save' && value != 'share') return;
  final out = await prepareOutputImage(file);
  if (out == null) {
    _log.warning('$value prepare failed name=$suggestedBaseName');
    toast(switch (value) {
      'copy' => l.imageCopyFailed,
      'save' => l.imageSaveFailed,
      _ => l.shareFailed,
    });
    _log.info(
      'item image action=$value name=$suggestedBaseName outcome=failed',
    );
    return;
  }
  final name = '$suggestedBaseName.${out.ext}';
  final outcome = await _perform(
    value,
    out: out,
    file: file,
    name: name,
    l: l,
    toast: toast,
  );
  _log.info('item image action=$value name=$name outcome=$outcome');
}

/// 以已準備好的 [out] 執行 [runItemImageAction] 的動作，回傳結果
/// `ok`／`cancelled`／`failed`。
Future<String> _perform(
  String value, {
  required OutputImage out,
  required File file,
  required String name,
  required AppLocalizations l,
  required void Function(String message) toast,
}) async {
  final mimeType = out.isGif ? 'image/gif' : 'image/png';
  switch (value) {
    case 'copy':
      final ok = await copyImageToClipboard(
        out.bytes,
        isGif: out.isGif,
        filePath: out.isGif ? file.path : null,
      );
      toast(ok ? l.imageCopied : l.imageCopyFailed);
      return ok ? 'ok' : 'failed';
    case 'save':
      try {
        final saved = await saveBytes(
          out.bytes,
          suggestedName: name,
          extension: out.ext,
          mimeType: mimeType,
          dialogTitle: l.dialogSaveAsTitle,
        );
        if (saved == null) return 'cancelled';
        toast(l.imageSavedTo(saved.path ?? saved.displayName));
        return 'ok';
      } catch (_) {
        toast(l.imageSaveFailed);
        return 'failed';
      }
    default:
      final ok = await shareBytes(
        out.bytes,
        fileName: name,
        mimeType: mimeType,
      );
      if (!ok) toast(l.shareFailed);
      return ok ? 'ok' : 'failed';
  }
}
