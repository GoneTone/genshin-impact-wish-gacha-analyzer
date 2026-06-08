import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';

/// GIF89a magic（_isGifBytes 只看開頭，後面補幾個 byte 即可）。
final _gifBytes = Uint8List.fromList([
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
  0x01, 0x00, 0x01, 0x00, 0x00, 0x3B,
]);

/// 用引擎產生一張合法 2×2 PNG bytes（需在 tester.runAsync 內呼叫）。
Future<Uint8List> _makePng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(2, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  group('prepareOutputImage', () {
    test('GIF → isGif=true 且保留原始 bytes', () async {
      final dir = await Directory.systemTemp.createTemp('img_prep_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final f = File('${dir.path}/a.gif')..writeAsBytesSync(_gifBytes);

      final out = await prepareOutputImage(f);

      expect(out, isNotNull);
      expect(out!.isGif, isTrue);
      expect(out.ext, 'gif');
      expect(out.bytes, _gifBytes);
    });

    testWidgets('非 GIF 合法圖 → isGif=false 且轉成 PNG', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_prep_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/a.png')..writeAsBytesSync(await _makePng());

        final out = await prepareOutputImage(f);

        expect(out, isNotNull);
        expect(out!.isGif, isFalse);
        expect(out.ext, 'png');
        expect(out.bytes.isNotEmpty, isTrue);
      });
    });

    testWidgets('壞檔（非 GIF 非圖片）→ null', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_prep_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/g.bin')..writeAsBytesSync([1, 2, 3, 4]);

        expect(await prepareOutputImage(f), isNull);
      });
    });

    test('不存在的檔 → null', () async {
      final dir = await Directory.systemTemp.createTemp('img_prep_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      expect(await prepareOutputImage(File('${dir.path}/missing.png')), isNull);
    });
  });

  group('copyImagePngToClipboard', () {
    test('seam 回 true → true（isGif=false）', () async {
      bool? capturedIsGif;
      imageClipboardWriter = (b, {required isGif}) async {
        capturedIsGif = isGif;
        return true;
      };
      expect(await copyImagePngToClipboard(png), isTrue);
      expect(capturedIsGif, isFalse);
    });

    test('seam 回 false → false', () async {
      imageClipboardWriter = (b, {required isGif}) async => false;
      expect(await copyImagePngToClipboard(png), isFalse);
    });

    test('seam 拋例外 → false', () async {
      imageClipboardWriter = (b, {required isGif}) async =>
          throw Exception('x');
      expect(await copyImagePngToClipboard(png), isFalse);
    });
  });

  group('copyImageFileToClipboard', () {
    test('GIF → 以 isGif=true、原始 bytes 寫剪貼簿', () async {
      bool? capturedIsGif;
      Uint8List? capturedBytes;
      imageClipboardWriter = (b, {required isGif}) async {
        capturedIsGif = isGif;
        capturedBytes = b;
        return true;
      };
      final dir = await Directory.systemTemp.createTemp('img_copy_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final f = File('${dir.path}/a.gif')..writeAsBytesSync(_gifBytes);

      expect(await copyImageFileToClipboard(f), isTrue);
      expect(capturedIsGif, isTrue);
      expect(capturedBytes, _gifBytes);
    });

    testWidgets('非 GIF → 以 isGif=false（PNG）寫剪貼簿', (tester) async {
      await tester.runAsync(() async {
        bool? capturedIsGif;
        imageClipboardWriter = (b, {required isGif}) async {
          capturedIsGif = isGif;
          return true;
        };
        final dir = await Directory.systemTemp.createTemp('img_copy_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/a.png')..writeAsBytesSync(await _makePng());

        expect(await copyImageFileToClipboard(f), isTrue);
        expect(capturedIsGif, isFalse);
      });
    });

    testWidgets('壞檔 → false（不呼叫 seam）', (tester) async {
      await tester.runAsync(() async {
        var called = false;
        imageClipboardWriter = (b, {required isGif}) async {
          called = true;
          return true;
        };
        final dir = await Directory.systemTemp.createTemp('img_copy_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/g.bin')..writeAsBytesSync([1, 2, 3, 4]);

        expect(await copyImageFileToClipboard(f), isFalse);
        expect(called, isFalse);
      });
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

  group('saveImageFile', () {
    test('GIF → 建議檔名 .gif 且寫入原始 bytes', () async {
      String? pickedName;
      String? writtenPath;
      Uint8List? writtenBytes;
      imageSaveLocationPicker = (name) async {
        pickedName = name;
        return FileSaveLocation('${Directory.systemTemp.path}/out.gif');
      };
      imageFileWriter = (p, b) async {
        writtenPath = p;
        writtenBytes = b;
      };
      final dir = await Directory.systemTemp.createTemp('img_savef_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final f = File('${dir.path}/a.gif')..writeAsBytesSync(_gifBytes);

      final path = await saveImageFile(f, suggestedBaseName: 'Hu Tao_Idle');

      expect(pickedName, 'Hu Tao_Idle.gif');
      expect(writtenBytes, _gifBytes);
      expect(path, writtenPath);
    });

    testWidgets('非 GIF → 建議檔名 .png', (tester) async {
      await tester.runAsync(() async {
        String? pickedName;
        imageSaveLocationPicker = (name) async {
          pickedName = name;
          return FileSaveLocation('${Directory.systemTemp.path}/out.png');
        };
        imageFileWriter = (p, b) async {};
        final dir = await Directory.systemTemp.createTemp('img_savef_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/a.png')..writeAsBytesSync(await _makePng());

        await saveImageFile(f, suggestedBaseName: 'X_Card');

        expect(pickedName, 'X_Card.png');
      });
    });

    testWidgets('壞檔 → throw（準備失敗）', (tester) async {
      await tester.runAsync(() async {
        imageSaveLocationPicker = (name) async =>
            FileSaveLocation('${Directory.systemTemp.path}/out.png');
        final dir = await Directory.systemTemp.createTemp('img_savef_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/g.bin')..writeAsBytesSync([1, 2, 3, 4]);

        await expectLater(
          saveImageFile(f, suggestedBaseName: 'X'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    test('使用者取消 → null', () async {
      imageSaveLocationPicker = (name) async => null;
      final dir = await Directory.systemTemp.createTemp('img_savef_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final f = File('${dir.path}/a.gif')..writeAsBytesSync(_gifBytes);

      expect(await saveImageFile(f, suggestedBaseName: 'X'), isNull);
    });
  });
}
