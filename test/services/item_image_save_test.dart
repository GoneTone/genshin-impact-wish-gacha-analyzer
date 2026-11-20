import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_image_save.dart';

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
  tearDown(resetItemImageSaveSeams);

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
}
