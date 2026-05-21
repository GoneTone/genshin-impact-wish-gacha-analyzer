import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 分享圖匯出流程的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 分享圖匯出結果狀態：同時存檔+複製、僅存檔、僅複製三種情況。
enum ShareExportStatus {
  /// 同時存檔並複製到剪貼簿。
  savedAndCopied,

  /// 僅存檔（剪貼簿寫入失敗或平台不支援）。
  savedOnly,

  /// 僅複製到剪貼簿（使用者取消存檔）。
  copiedOnly,
}

/// 分享圖匯出結果，包含狀態與存檔路徑（僅存檔/同時存檔時不為 null）。
class ShareExportResult {
  /// 建立 [ShareExportResult]。
  const ShareExportResult({required this.status, this.path});

  /// 匯出結果狀態。
  final ShareExportStatus status;

  /// 存檔路徑；[ShareExportStatus.copiedOnly] 時為 null。
  final String? path;
}

/// 預設剪貼簿寫入：寫 PNG 到系統剪貼簿，回傳是否成功
/// （平台不支援時回傳 false）。
/// 平台原生路徑；unit test 以 [shareClipboardWriter] seam 取代覆蓋（flutter test 環境 SystemClipboard.instance 為 null）。
Future<bool> _defaultClipboardWriter(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem();
  item.add(Formats.png(png));
  await clipboard.write([item]);
  return true;
}

/// 預設存檔位置選擇器：開啟系統 save dialog，回傳使用者選擇的路徑（取消為 null）。
Future<FileSaveLocation?> _defaultSaveLocationPicker(String name) =>
    getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );

/// 存檔位置選擇器 seam，讓 flutter test 不開啟真實系統 dialog。
@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
shareSaveLocationPicker = _defaultSaveLocationPicker;

/// 剪貼簿寫入 seam，讓 flutter test 不碰真實剪貼簿（SystemClipboard.instance 為 null）。
@visibleForTesting
Future<bool> Function(Uint8List png) shareClipboardWriter =
    _defaultClipboardWriter;

/// 檔案寫入 seam，讓 flutter test 不碰真實 FS。
@visibleForTesting
Future<void> Function(String path, Uint8List png) shareFileWriter =
    (path, png) => File(path).writeAsBytes(png);

/// 將所有 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetShareImageExportSeams() {
  shareSaveLocationPicker = _defaultSaveLocationPicker;
  shareClipboardWriter = _defaultClipboardWriter;
  shareFileWriter = (path, png) => File(path).writeAsBytes(png);
}

/// 先寫剪貼簿（失敗不致命），再讓使用者選位置存檔（取消則只剩剪貼簿）。
///
/// 若使用者已選存檔路徑但寫入失敗，會記 severe log 後 rethrow `Exception`
/// （通常為 `FileSystemException`），由呼叫端負責處理（顯示錯誤）。
Future<ShareExportResult> exportShareImage(
  Uint8List png, {
  required String suggestedName,
}) async {
  bool copied;
  try {
    copied = await shareClipboardWriter(png);
  } catch (e, st) {
    _log.warning('clipboard write failed', e, st);
    copied = false;
  }

  final loc = await shareSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled; clipboard=$copied');
    return const ShareExportResult(status: ShareExportStatus.copiedOnly);
  }

  try {
    await shareFileWriter(loc.path, png);
  } catch (e, st) {
    _log.severe('share image write failed ${sanitizeFsPath(loc.path)}', e, st);
    rethrow;
  }
  _log.info(
    'share image saved ${sanitizeFsPath(loc.path)}; '
    'bytes=${png.length} clipboard=$copied',
  );
  return ShareExportResult(
    status: copied
        ? ShareExportStatus.savedAndCopied
        : ShareExportStatus.savedOnly,
    path: loc.path,
  );
}
