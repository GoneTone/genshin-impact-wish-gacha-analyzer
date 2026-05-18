import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renderWidgetToPng 寬固定、高隨內容自適應', (t) async {
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
        width: 300,
        pixelRatio: 2.0,
      );
      expect(png, isA<Uint8List>());
      expect(png.isNotEmpty, isTrue);

      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      // 寬 = 固定 width 300 × pixelRatio 2 = 600。
      expect(frame.image.width, 600);
      // 高 = 內容自然高 150 × pixelRatio 2 = 300（證明高度=內容而非固定畫布）。
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

  testWidgets('同寬不同內容高 → 輸出高度各自隨內容（自適應對照）', (t) async {
    await t.runAsync(() async {
      Future<int> renderHeight(double contentHeight) async {
        final png = await renderWidgetToPng(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 300,
              height: contentHeight,
              child: const ColoredBox(color: Color(0xFF112233)),
            ),
          ),
          width: 300,
          pixelRatio: 2.0,
        );
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        return frame.image.height;
      }

      final shortH = await renderHeight(150);
      final tallH = await renderHeight(400);

      // 各自 = 內容高 × pixelRatio，且兩次不同（證明高度純由內容決定）。
      expect(shortH, 300, reason: '150 × 2');
      expect(tallH, 800, reason: '400 × 2');
      expect(shortH, isNot(equals(tallH)));
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
