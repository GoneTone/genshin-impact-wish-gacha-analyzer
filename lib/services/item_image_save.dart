import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 圖片複製／儲存流程的 logger（命名空間 gacha.hoyowiki.save）。
final _log = Logger('gacha.hoyowiki.save');

/// 要複製／儲存的圖片輸出：GIF 保留原始 bytes（保留動畫），其餘一律轉成 PNG。
class OutputImage {
  /// 建立 [OutputImage]。
  const OutputImage({required this.bytes, required this.isGif});

  /// 實際要寫出／複製的 bytes。
  final Uint8List bytes;

  /// 是否為 GIF（true 時 [bytes] 為原始 GIF）。
  final bool isGif;

  /// 對應副檔名（不含點）：gif 或 png。
  String get ext => isGif ? 'gif' : 'png';
}

/// 判斷 [bytes] 開頭是否為 GIF magic（`GIF87a` / `GIF89a`）。用 magic bytes 而非
/// 副檔名判斷，較不受 URL／快取檔命名影響。
bool _isGifBytes(Uint8List bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0x47 && // G
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x38 && // 8
    (bytes[4] == 0x37 || bytes[4] == 0x39) && // 7 或 9
    bytes[5] == 0x61; // a

/// 把 [bytes]（任意格式）解碼後重新編碼成 PNG bytes；失敗回 null。
Future<Uint8List?> _encodeBytesToPng(
  Uint8List bytes, {
  required String debugPath,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) {
      _log.warning('encode png null path=${sanitizeFsPath(debugPath)}');
      return null;
    }
    return data.buffer.asUint8List();
  } catch (e, st) {
    _log.warning('encode png failed path=${sanitizeFsPath(debugPath)}', e, st);
    return null;
  }
}

/// 由本地圖檔 [file] 準備輸出 bytes：GIF 保留原始 bytes（保留動畫），其餘解碼重編
/// 成 PNG（icon／gallery 副檔名隨 URL 可能是 webp／jpg，轉 PNG 後存檔與貼上相容性
/// 最佳）。讀檔或解碼失敗回 null。測試可透過 [prepareOutputImageOverride] 替換實作。
Future<OutputImage?> prepareOutputImage(File file) async {
  if (prepareOutputImageOverride != null) {
    return prepareOutputImageOverride!(file);
  }
  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e, st) {
    _log.warning('read image failed path=${sanitizeFsPath(file.path)}', e, st);
    return null;
  }
  if (_isGifBytes(bytes)) {
    return OutputImage(bytes: bytes, isGif: true);
  }
  final png = await _encodeBytesToPng(bytes, debugPath: file.path);
  if (png == null) return null;
  return OutputImage(bytes: png, isGif: false);
}

/// 圖片準備 seam，讓 flutter test 跳過真實 codec 解碼。null 表示使用預設實作。
@visibleForTesting
Future<OutputImage?> Function(File file)? prepareOutputImageOverride;

/// 將 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetItemImageSaveSeams() {
  prepareOutputImageOverride = null;
}
