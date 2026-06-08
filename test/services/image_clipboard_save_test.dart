import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  group('encodeImageFileToPng', () {
    testWidgets('合法 PNG 檔 → 非 null PNG bytes', (tester) async {
      await tester.runAsync(() async {
        // 用引擎自身產生一張合法 PNG，避免硬編碼 byte array 不合法。
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const ui.Color(0xFFFF0000),
        );
        final image = await recorder.endRecording().toImage(2, 2);
        final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/a.png')
          ..writeAsBytesSync(pngData!.buffer.asUint8List());
        final out = await encodeImageFileToPng(f);
        expect(out, isNotNull);
        expect(out!.isNotEmpty, isTrue);
      });
    });

    testWidgets('不存在的檔 → null', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final missing = File('${dir.path}/missing.png');
        expect(await encodeImageFileToPng(missing), isNull);
      });
    });

    testWidgets('壞檔（非圖片）→ null', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final garbage = File('${dir.path}/g.png')
          ..writeAsBytesSync([1, 2, 3, 4]);
        expect(await encodeImageFileToPng(garbage), isNull);
      });
    });
  });

  group('copyImagePngToClipboard', () {
    test('seam 回 true → true', () async {
      imageClipboardWriter = (b) async => true;
      expect(await copyImagePngToClipboard(png), isTrue);
    });

    test('seam 回 false → false', () async {
      imageClipboardWriter = (b) async => false;
      expect(await copyImagePngToClipboard(png), isFalse);
    });

    test('seam 拋例外 → false', () async {
      imageClipboardWriter = (b) async => throw Exception('boom');
      expect(await copyImagePngToClipboard(png), isFalse);
    });
  });

  group('saveImagePng', () {
    test('選了路徑並寫檔成功 → 回實際路徑', () async {
      final tmp = '${Directory.systemTemp.path}/img_save_out.png';
      addTearDown(() async {
        final f = File(tmp);
        if (await f.exists()) await f.delete();
      });
      imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
      final path = await saveImagePng(png, suggestedName: 'a.png');
      expect(path, tmp);
      expect(await File(tmp).readAsBytes(), png);
    });

    test('使用者取消 → null', () async {
      imageSaveLocationPicker = (name) async => null;
      expect(await saveImagePng(png, suggestedName: 'a.png'), isNull);
    });

    test('寫檔失敗 → rethrow', () async {
      imageSaveLocationPicker = (name) async => FileSaveLocation('/x/y.png');
      imageFileWriter = (p, b) async =>
          throw const FileSystemException('write fail');
      await expectLater(
        saveImagePng(png, suggestedName: 'a.png'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
