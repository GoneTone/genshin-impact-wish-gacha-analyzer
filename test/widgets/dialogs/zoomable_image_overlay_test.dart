import 'dart:io';

import 'package:flutter/gestures.dart';
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
              onPressed: () => showZoomableImageOverlay(
                  ctx,
                  imageFile: imageFile,
                  suggestedBaseName: 'test',
                ),
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
    testWidgets(
      'uses InteractiveViewer with scaleEnabled=false, panEnabled=true',
      (tester) async {
        await openOverlay(tester);
        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(iv.scaleEnabled, isFalse);
        expect(iv.panEnabled, isTrue);
        expect(iv.minScale, 1.0);
        expect(iv.maxScale, 5.0);
      },
    );

    testWidgets('initial transform is identity (scale = 1)', (tester) async {
      await openOverlay(tester);
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.transformationController!.value.getMaxScaleOnAxis(), 1.0);
    });
  });

  group('ZoomableImageOverlay wheel zoom', () {
    /// 抓取當前 InteractiveViewer 的 scale。
    double currentScale(WidgetTester tester) {
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      return iv.transformationController!.value.getMaxScaleOnAxis();
    }

    /// 對 [position] 派發一次滾輪事件。[deltaY] 為 scrollDelta.dy；負值 = 向上 = 放大。
    Future<void> sendWheel(
      WidgetTester tester,
      Offset position,
      double deltaY,
    ) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(position));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: position, scrollDelta: Offset(0, deltaY)),
      );
      await tester.pump();
    }

    testWidgets('wheel up zooms in (scale > 1)', (tester) async {
      await openOverlay(tester);
      expect(currentScale(tester), 1.0);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await sendWheel(tester, center, -100);
      expect(currentScale(tester), greaterThan(1.0));
    });

    testWidgets('wheel down at fit stays at minScale', (tester) async {
      await openOverlay(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await sendWheel(tester, center, 100);
      expect(currentScale(tester), 1.0);
    });

    testWidgets('many wheel ups clamp at maxScale (5.0)', (tester) async {
      await openOverlay(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      // 1.1^20 ≈ 6.7 > 5.0；確保打到上限。
      for (var i = 0; i < 20; i++) {
        await sendWheel(tester, center, -100);
      }
      expect(currentScale(tester), closeTo(5.0, 1e-6));
    });

    testWidgets('cursor-centered: zoom at offset keeps scene point at cursor', (
      tester,
    ) async {
      await openOverlay(tester);
      final ivFinder = find.byType(InteractiveViewer);
      final ivCenter = tester.getCenter(ivFinder);
      final ivRect = tester.getRect(ivFinder);
      // 選一個離中心明顯偏右下的點。
      final focal = Offset(ivCenter.dx + 100, ivCenter.dy + 80);
      final focalLocal = focal - ivRect.topLeft;

      final iv = tester.widget<InteractiveViewer>(ivFinder);
      final ctrl = iv.transformationController!;

      // scale = 1 時，scene point 對應 cursor 局部座標的「圖內位置」= focalLocal
      // （恆等變換）。
      final beforeScene = ctrl.toScene(focalLocal);

      await sendWheel(tester, focal, -100);
      // 縮放後，同一 scene point 應該還是落在 focalLocal 附近（cursor-centered 不變）。
      final afterScene = ctrl.toScene(focalLocal);
      expect((afterScene - beforeScene).distance, lessThan(1.0));
    });

    testWidgets('horizontal wheel scroll does not zoom', (tester) async {
      await openOverlay(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(100, 0)),
      );
      await tester.pump();
      expect(currentScale(tester), 1.0);
    });
  });

  group('ZoomableImageOverlay double-tap toggle', () {
    double currentScale(WidgetTester tester) {
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      return iv.transformationController!.value.getMaxScaleOnAxis();
    }

    Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('from fit (scale=1), double-tap goes to 2x', (tester) async {
      await openOverlay(tester);
      expect(currentScale(tester), 1.0);
      await doubleTapAt(
        tester,
        tester.getCenter(find.byType(InteractiveViewer)),
      );
      expect(currentScale(tester), closeTo(2.0, 1e-6));
    });

    testWidgets('from non-fit, double-tap returns to fit (1x)', (tester) async {
      await openOverlay(tester);
      // 先用滾輪把它升到 3x 左右。
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(center));
      for (var i = 0; i < 12; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pump();
      }
      expect(currentScale(tester), greaterThan(2.5));
      await doubleTapAt(tester, center);
      expect(currentScale(tester), closeTo(1.0, 1e-6));
    });

    testWidgets(
      'double-tap back to fit at off-center clears translation (no out-of-frame residue)',
      (tester) async {
        await openOverlay(tester);
        // 在偏左上點雙擊放大到 2x — 會產生 focal-centered translation。
        final ivRect = tester.getRect(find.byType(InteractiveViewer));
        final offCenter = Offset(
          ivRect.left + ivRect.width * 0.25,
          ivRect.top + ivRect.height * 0.25,
        );
        await doubleTapAt(tester, offCenter);
        expect(currentScale(tester), closeTo(2.0, 1e-6));

        // 再雙擊回 fit — matrix 必須是 identity（scale=1 AND translation=0），
        // 否則圖片會偏離 viewport，要拖一下才會 snap 回來。
        await doubleTapAt(tester, offCenter);
        expect(currentScale(tester), closeTo(1.0, 1e-6));

        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final translation = iv.transformationController!.value.getTranslation();
        expect(translation.x, closeTo(0, 1e-6));
        expect(translation.y, closeTo(0, 1e-6));
      },
    );

    testWidgets(
      'wheel-zoom-out clamped to minScale also resets matrix to identity',
      (tester) async {
        await openOverlay(tester);
        final center = tester.getCenter(find.byType(InteractiveViewer));
        // 焦點刻意偏中心以製造非零 translation。
        final offCenter = Offset(center.dx + 80, center.dy + 60);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(offCenter));
        for (var i = 0; i < 6; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: offCenter,
              scrollDelta: const Offset(0, -100),
            ),
          );
          await tester.pump();
        }
        expect(currentScale(tester), greaterThan(1.5));

        // zoom out 大量格數確保 clamp 到 minScale。
        for (var i = 0; i < 20; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: offCenter,
              scrollDelta: const Offset(0, 100),
            ),
          );
          await tester.pump();
        }
        expect(currentScale(tester), closeTo(1.0, 1e-6));
        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final translation = iv.transformationController!.value.getTranslation();
        expect(translation.x, closeTo(0, 1e-6));
        expect(translation.y, closeTo(0, 1e-6));
      },
    );
  });

  group('ZoomableImageOverlay tap-to-close structure', () {
    // 行為層測試（dim 區 tap 真的關 / image 區 tap 真的不關）需要 image
    // 實際 decode 完成才能驗證 SizedBox 縮到 painted rect；testWidgets 沒有
    // 可靠的 file codec 同步路徑，因此這裡只測結構，行為由使用者 manual 驗證。

    testWidgets(
      'inner GD (image absorber) carries onTap (empty absorber) and onDoubleTapDown (zoom)',
      (tester) async {
        await openOverlay(tester);

        // Image 外那層 GestureDetector 同時負責：
        //   (1) 吸收 image 像素上的單擊（onTap 空），避免「想看細節點到圖片就關掉」。
        //   (2) 承擔雙擊縮放（onDoubleTapDown）。
        // 雙擊集中在此層才能讓外層 GD 維持單純 onTap、暗區 tap 立即關閉。
        final innerGd = tester.widget<GestureDetector>(
          find
              .ancestor(
                of: find.byType(Image),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(innerGd.behavior, HitTestBehavior.opaque);
        expect(innerGd.onTap, isNotNull);
        expect(innerGd.onDoubleTapDown, isNotNull);

        // 該 GestureDetector 要在 LayoutBuilder 出來的 SizedBox 內，這樣 hit-test
        // 範圍才會是 image painted rect 而非整個 viewer。
        expect(
          find.ancestor(
            of: find.byType(Image),
            matching: find.byType(SizedBox),
          ),
          findsWidgets,
        );
        expect(
          find.ancestor(
            of: find.byType(Image),
            matching: find.byType(LayoutBuilder),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'outer InteractiveViewer wrapper has onTap (no onDoubleTap) for instant dim-area close',
      (tester) async {
        await openOverlay(tester);

        // 包住 InteractiveViewer 的 GestureDetector 必須只有 onTap、不可掛
        // onDoubleTap*：與 DoubleTapGR 在同一 arena 競爭會讓 onTap 被
        // kDoubleTapTimeout（300ms）卡住才 fire，造成可感知延遲。
        final outerGd = tester.widget<GestureDetector>(
          find
              .ancestor(
                of: find.byType(InteractiveViewer),
                matching: find.byType(GestureDetector),
              )
              .first,
        );
        expect(outerGd.onTap, isNotNull);
        expect(outerGd.onDoubleTap, isNull);
        expect(outerGd.onDoubleTapDown, isNull);
      },
    );
  });
}
