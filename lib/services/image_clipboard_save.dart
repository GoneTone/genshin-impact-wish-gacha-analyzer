import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 圖片複製／儲存流程的 logger（命名空間 gacha.hoyowiki.save）。
final _log = Logger('gacha.hoyowiki.save');

/// 把任意格式的本地圖檔解碼後重新編碼成 PNG bytes；任何失敗（讀檔／解碼／編碼）
/// 回 null，呼叫端據此提示失敗。
///
/// 統一輸出 PNG：來源 icon／gallery 副檔名隨 URL 可能是 webp／jpg，轉 PNG 後
/// 存檔與複製到剪貼簿格式一致。
Future<Uint8List?> encodeImageFileToPng(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) {
      _log.warning('encode png null path=${sanitizeFsPath(file.path)}');
      return null;
    }
    return data.buffer.asUint8List();
  } catch (e, st) {
    _log.warning('encode png failed path=${sanitizeFsPath(file.path)}', e, st);
    return null;
  }
}

/// 預設存檔位置選擇器：開啟系統 save dialog，回傳使用者選擇的路徑（取消為 null）。
Future<FileSaveLocation?> _defaultSaveLocationPicker(String name) =>
    getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );

/// 預設剪貼簿寫入：寫 PNG 到系統剪貼簿，回傳是否成功（平台不支援回 false）。
Future<bool> _defaultClipboardWriter(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem();
  item.add(Formats.png(png));
  await clipboard.write([item]);
  return true;
}

/// 預設檔案寫入實作：直接寫入磁碟。
Future<void> _defaultFileWriter(String path, Uint8List png) =>
    File(path).writeAsBytes(png);

/// 存檔位置選擇器 seam，讓 flutter test 不開啟真實系統 dialog。
@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
imageSaveLocationPicker = _defaultSaveLocationPicker;

/// 剪貼簿寫入 seam，讓 flutter test 不碰真實剪貼簿（SystemClipboard.instance 為 null）。
@visibleForTesting
Future<bool> Function(Uint8List png) imageClipboardWriter =
    _defaultClipboardWriter;

/// 檔案寫入 seam，讓 flutter test 不碰真實 FS。
@visibleForTesting
Future<void> Function(String path, Uint8List png) imageFileWriter =
    _defaultFileWriter;

/// 將所有 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetImageClipboardSaveSeams() {
  imageSaveLocationPicker = _defaultSaveLocationPicker;
  imageClipboardWriter = _defaultClipboardWriter;
  imageFileWriter = _defaultFileWriter;
}

/// 把 PNG 寫入系統剪貼簿。成功回 true；平台不支援回 false；例外記 warning 後回 false。
Future<bool> copyImagePngToClipboard(Uint8List png) async {
  try {
    final ok = await imageClipboardWriter(png);
    _log.info('copy image clipboard=$ok bytes=${png.length}');
    return ok;
  } catch (e, st) {
    _log.warning('copy image failed', e, st);
    return false;
  }
}

/// 讓使用者選位置存 PNG。成功回**實際存檔路徑**（供呼叫端在提示顯示完整路徑）；
/// 使用者取消回 null（非錯誤）；已選路徑但寫檔失敗會記 severe log 後 rethrow。
Future<String?> saveImagePng(
  Uint8List png, {
  required String suggestedName,
}) async {
  final loc = await imageSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled');
    return null;
  }
  try {
    await imageFileWriter(loc.path, png);
  } catch (e, st) {
    _log.severe('save image failed ${sanitizeFsPath(loc.path)}', e, st);
    rethrow;
  }
  _log.info('save image ok ${sanitizeFsPath(loc.path)} bytes=${png.length}');
  return loc.path;
}
