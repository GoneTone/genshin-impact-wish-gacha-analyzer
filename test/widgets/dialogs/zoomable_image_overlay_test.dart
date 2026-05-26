import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';

/// 1×1 透明 PNG，最小可被 Flutter decode 的 valid PNG。
const List<int> _onePxPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zoom_overlay_test_');
    imageFile = File('${tempDir.path}/test.png');
    await imageFile.writeAsBytes(_onePxPng);
  });

  tearDown(() async {
    // per memory project_image_cache_cross_test_race
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 把 [showZoomableImageOverlay] 開出來的 widget 在乾淨 MaterialApp 內呈現。
  Future<void> openOverlay(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showZoomableImageOverlay(ctx, imageFile: imageFile),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // pump a few frames — file image codec on tempDir may never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('ZoomableImageOverlay open/close', () {
    testWidgets('opens with Image.file rendering the given file', (
      tester,
    ) async {
      await openOverlay(tester);
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      final img = tester.widget<Image>(
        find.descendant(
          of: find.byType(ZoomableImageOverlay),
          matching: find.byType(Image),
        ),
      );
      expect(img.image, isA<FileImage>());
      expect((img.image as FileImage).file.path, imageFile.path);
    });

    testWidgets('ESC closes overlay', (tester) async {
      await openOverlay(tester);
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsNothing);
    });

    testWidgets('tap on backdrop area closes overlay', (tester) async {
      await openOverlay(tester);
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      // 點視窗左上角 (5,5) — 必定落在 InteractiveViewer 以外的 backdrop padding。
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsNothing);
    });

    testWidgets('tap X button closes overlay', (tester) async {
      await openOverlay(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ZoomableImageOverlay)),
      )!;
      // X 按鈕用 tooltip 識別（同時是 a11y label）。
      await tester.tap(find.byTooltip(l.actionCloseImagePreview));
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsNothing);
    });
  });

  group('ZoomableImageOverlay InteractiveViewer wiring', () {
    testWidgets('uses InteractiveViewer with scaleEnabled=false, panEnabled=true', (
      tester,
    ) async {
      await openOverlay(tester);
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.scaleEnabled, isFalse);
      expect(iv.panEnabled, isTrue);
      expect(iv.minScale, 1.0);
      expect(iv.maxScale, 5.0);
    });

    testWidgets('initial transform is identity (scale = 1)', (tester) async {
      await openOverlay(tester);
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(iv.transformationController!.value.getMaxScaleOnAxis(), 1.0);
    });
  });
}
