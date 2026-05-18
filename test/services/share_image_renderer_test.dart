import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renderWidgetToPng 回傳可解碼且尺寸正確的 PNG', (t) async {
    // toImage / toByteData / instantiateImageCodec 走引擎真實事件迴圈，
    // testWidgets 的 fake-async zone 不會 pump，需放進 runAsync。
    await t.runAsync(() async {
      final png = await renderWidgetToPng(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 150,
            child: ColoredBox(color: Color(0xFF112233)),
          ),
        ),
        logicalSize: const Size(300, 150),
        pixelRatio: 2.0,
      );
      expect(png, isA<Uint8List>());
      expect(png.isNotEmpty, isTrue);

      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 600);
      expect(frame.image.height, 300);

      // 驗證像素內容非空白：取中心像素應為 ColoredBox 顏色 0xFF112233（不透明）。
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(byteData, isNotNull);
      final bytes = byteData!.buffer.asUint8List();
      final cx = frame.image.width ~/ 2;
      final cy = frame.image.height ~/ 2;
      final offset = (cy * frame.image.width + cx) * 4;
      expect(bytes[offset], 0x11, reason: 'R');
      expect(bytes[offset + 1], 0x22, reason: 'G');
      expect(bytes[offset + 2], 0x33, reason: 'B');
      expect(bytes[offset + 3], 0xFF, reason: 'A (fully opaque)');
    });
  });

  testWidgets('loadAppIconImage 回傳非空 ui.Image', (t) async {
    await t.runAsync(() async {
      final img = await loadAppIconImage();
      expect(img.width, greaterThan(0));
      expect(img.height, greaterThan(0));
      img.dispose();
    });
  });
}
