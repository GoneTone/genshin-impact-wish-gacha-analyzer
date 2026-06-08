import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

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
/// 最佳）。讀檔或解碼失敗回 null。
Future<OutputImage?> prepareOutputImage(File file) async {
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

/// 預設存檔位置選擇器：開啟系統 save dialog，type group 依 [name] 副檔名（gif/png）
/// 設定；回傳使用者選擇的路徑（取消為 null）。
Future<FileSaveLocation?> _defaultSaveLocationPicker(String name) {
  final ext = name.toLowerCase().endsWith('.gif') ? 'gif' : 'png';
  return getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
    ],
  );
}

/// 預設剪貼簿寫入：寫圖片 [bytes] 到系統剪貼簿，[isGif] 決定用 GIF 或 PNG 格式；
/// 回傳是否成功（平台不支援回 false）。
Future<bool> _defaultClipboardWriter(
  Uint8List bytes, {
  required bool isGif,
}) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem(suggestedName: isGif ? 'image.gif' : 'image.png');
  item.add(isGif ? Formats.gif(bytes) : Formats.png(bytes));
  // GIF 額外掛一份 virtual file：讓「貼上檔案」的目標（Discord、檔案總管、聊天
  // 軟體）拿到真正的 .gif 檔以保留動畫。純圖片貼上的目標（小畫家等）仍只會拿到
  // 系統合成的靜態點陣圖 — 這是 Windows 剪貼簿圖片模型的限制，無法避免。
  if (isGif && item.virtualFileSupported) {
    item.addVirtualFile(
      format: Formats.gif,
      storageSuggestion: VirtualFileStorage.memory,
      provider: (sinkProvider, progress) {
        final sink = sinkProvider(fileSize: bytes.length);
        sink.add(bytes);
        sink.close();
      },
    );
  }
  await clipboard.write([item]);
  return true;
}

/// 預設檔案寫入實作：直接寫入磁碟。
Future<void> _defaultFileWriter(String path, Uint8List bytes) =>
    File(path).writeAsBytes(bytes);

/// 存檔位置選擇器 seam，讓 flutter test 不開啟真實系統 dialog。
@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
imageSaveLocationPicker = _defaultSaveLocationPicker;

/// 剪貼簿寫入 seam，讓 flutter test 不碰真實剪貼簿（SystemClipboard.instance 為 null）。
@visibleForTesting
Future<bool> Function(Uint8List bytes, {required bool isGif})
imageClipboardWriter = _defaultClipboardWriter;

/// 檔案寫入 seam，讓 flutter test 不碰真實 FS。
@visibleForTesting
Future<void> Function(String path, Uint8List bytes) imageFileWriter =
    _defaultFileWriter;

/// 將所有 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetImageClipboardSaveSeams() {
  imageSaveLocationPicker = _defaultSaveLocationPicker;
  imageClipboardWriter = _defaultClipboardWriter;
  imageFileWriter = _defaultFileWriter;
}

/// 把圖片 [bytes] 寫入系統剪貼簿（[isGif] 選 GIF／PNG 格式）。成功回 true；
/// 平台不支援或例外回 false。
Future<bool> _copyBytesToClipboard(
  Uint8List bytes, {
  required bool isGif,
}) async {
  try {
    final ok = await imageClipboardWriter(bytes, isGif: isGif);
    _log.info('copy image clipboard=$ok gif=$isGif bytes=${bytes.length}');
    return ok;
  } catch (e, st) {
    _log.warning('copy image failed', e, st);
    return false;
  }
}

/// 把 PNG [png] 複製到系統剪貼簿（分享圖匯出用）。成功回 true。
Future<bool> copyImagePngToClipboard(Uint8List png) =>
    _copyBytesToClipboard(png, isGif: false);

/// 把本地圖檔 [file] 複製到系統剪貼簿：GIF 保留原始（保留動畫），其餘轉 PNG。
/// 讀檔／解碼失敗或平台不支援回 false。
Future<bool> copyImageFileToClipboard(File file) async {
  final out = await prepareOutputImage(file);
  if (out == null) return false;
  return _copyBytesToClipboard(out.bytes, isGif: out.isGif);
}

/// 讓使用者選位置存 [bytes]。成功回實際路徑、取消回 null、寫檔失敗記 severe 後 rethrow。
Future<String?> _saveBytes(
  Uint8List bytes, {
  required String suggestedName,
}) async {
  final loc = await imageSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled');
    return null;
  }
  try {
    await imageFileWriter(loc.path, bytes);
  } catch (e, st) {
    _log.severe('save image failed ${sanitizeFsPath(loc.path)}', e, st);
    rethrow;
  }
  _log.info('save image ok ${sanitizeFsPath(loc.path)} bytes=${bytes.length}');
  return loc.path;
}

/// 讓使用者選位置存 PNG（分享圖匯出用）。成功回**實際存檔路徑**；取消回 null；
/// 寫檔失敗 rethrow。
Future<String?> saveImagePng(Uint8List png, {required String suggestedName}) =>
    _saveBytes(png, suggestedName: suggestedName);

/// 讓使用者選位置存本地圖檔：GIF 保留原始 bytes 與 `.gif`；其餘轉 PNG 與 `.png`。
/// [suggestedBaseName] 為**不含副檔名**的建議檔名（副檔名依實際格式自動補上）。
/// 成功回實際路徑；取消回 null；準備（讀檔／解碼）失敗 throw；寫檔失敗 rethrow。
Future<String?> saveImageFile(
  File file, {
  required String suggestedBaseName,
}) async {
  final out = await prepareOutputImage(file);
  if (out == null) {
    throw const FormatException('prepare output image failed');
  }
  return _saveBytes(out.bytes, suggestedName: '$suggestedBaseName.${out.ext}');
}
