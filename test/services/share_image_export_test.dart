import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  test('使用者選了路徑 + 剪貼簿成功 → saved', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_a.png';
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.savedAndCopied);
    expect(r.path, tmp);
    expect(await File(tmp).readAsBytes(), png);
    await File(tmp).delete();
  });

  test('使用者取消存檔但剪貼簿成功 → copiedOnly', () async {
    imageSaveLocationPicker = (name) async => null;
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.copiedOnly);
    expect(r.path, isNull);
  });

  test('剪貼簿不支援但存檔成功 → savedOnly', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_b.png';
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => false;

    final r = await exportShareImage(png, suggestedName: 'b.png');

    expect(r.status, ShareExportStatus.savedOnly);
    await File(tmp).delete();
  });

  test('剪貼簿不支援 + 使用者取消存檔 → copiedOnly', () async {
    imageSaveLocationPicker = (name) async => null;
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => false;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.copiedOnly);
    expect(r.path, isNull);
  });

  test('存檔失敗 → rethrow', () async {
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => true;
    imageSaveLocationPicker = (name) async =>
        FileSaveLocation('${Directory.systemTemp.path}/share_fail.png');
    imageFileWriter = (path, png) async =>
        throw const FileSystemException('disk full');

    await expectLater(
      exportShareImage(png, suggestedName: 'a.png'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
