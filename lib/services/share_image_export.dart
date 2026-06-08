import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
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

/// 先寫剪貼簿（失敗不致命），再讓使用者選位置存檔（取消則只剩剪貼簿）。
///
/// 組合共用層的 [copyImagePngToClipboard]（永不拋、回是否成功）與
/// [saveImagePng]（取消回 null、成功回實際路徑、寫檔失敗 rethrow）。
/// 若使用者已選存檔路徑但寫入失敗，[saveImagePng] 會記 severe log 後 rethrow
/// `Exception`（通常為 `FileSystemException`），由呼叫端負責處理（顯示錯誤）。
Future<ShareExportResult> exportShareImage(
  Uint8List png, {
  required String suggestedName,
}) async {
  final copied = await copyImagePngToClipboard(png);

  final savedPath = await saveImagePng(png, suggestedName: suggestedName);
  if (savedPath == null) {
    _log.info('save cancelled; clipboard=$copied');
    return const ShareExportResult(status: ShareExportStatus.copiedOnly);
  }

  _log.info(
    'share image saved ${sanitizeFsPath(savedPath)}; '
    'bytes=${png.length} clipboard=$copied',
  );
  return ShareExportResult(
    status: copied
        ? ShareExportStatus.savedAndCopied
        : ShareExportStatus.savedOnly,
    path: savedPath,
  );
}
