// lib/services/share_image_export.dart
//
// PNG bytes → 系統剪貼簿 + 使用者選位置存檔。
// I/O 與剪貼簿經 @visibleForTesting seam 注入（仿 services/file_reveal.dart），
// 讓 flutter test 不碰真實 FS / 剪貼簿。
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

final _log = Logger('share.image');

enum ShareExportStatus { savedAndCopied, savedOnly, copiedOnly }

class ShareExportResult {
  const ShareExportResult({required this.status, this.path});
  final ShareExportStatus status;
  final String? path;
}

/// 預設剪貼簿寫入：寫 PNG 到系統剪貼簿，回傳是否成功
/// （平台不支援時回傳 false）。
Future<bool> _defaultClipboardWriter(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem();
  item.add(Formats.png(png));
  await clipboard.write([item]);
  return true;
}

@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
shareSaveLocationPicker = (name) => getSaveLocation(
  suggestedName: name,
  acceptedTypeGroups: const [
    XTypeGroup(label: 'PNG', extensions: ['png']),
  ],
);

@visibleForTesting
Future<bool> Function(Uint8List png) shareClipboardWriter =
    _defaultClipboardWriter;

@visibleForTesting
Future<void> Function(String path, Uint8List png) shareFileWriter =
    (path, png) => File(path).writeAsBytes(png);

@visibleForTesting
void resetShareImageExportSeams() {
  shareSaveLocationPicker = (name) => getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG', extensions: ['png']),
    ],
  );
  shareClipboardWriter = _defaultClipboardWriter;
  shareFileWriter = (path, png) => File(path).writeAsBytes(png);
}

/// 先寫剪貼簿（失敗不致命），再讓使用者選位置存檔（取消則只剩剪貼簿）。
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

  await shareFileWriter(loc.path, png);
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
