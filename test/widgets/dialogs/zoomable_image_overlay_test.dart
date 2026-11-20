import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_image_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
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
    resetItemImageSaveSeams();
    resetFileAccessSeams();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 把 [showZoomableImageOverlay] 開出來的 widget 在乾淨 MaterialApp 內呈現。
  Future<void> openOverlay(WidgetTester tester, {bool android = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isAndroidProvider.overrideWithValue(android)],
        child: MaterialApp(
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
      ),
    );
    await tester.tap(find.text('open'));
    // pump a few frames — file image codec on tempDir may never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 抓取當前 InteractiveViewer 的 scale。
  double currentScale(WidgetTester tester) {
    final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    return iv.transformationController!.value.getMaxScaleOnAxis();
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
    testWidgets('uses InteractiveViewer with pinch zoom and pan enabled', (
      tester,
    ) async {
      await openOverlay(tester);
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.scaleEnabled, isTrue);
      expect(iv.panEnabled, isTrue);
      expect(iv.minScale, 1.0);
      expect(iv.maxScale, 5.0);
    });

    testWidgets('initial transform is identity (scale = 1)', (tester) async {
      await openOverlay(tester);
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(iv.transformationController!.value.getMaxScaleOnAxis(), 1.0);
    });
  });

  group('ZoomableImageOverlay wheel zoom', () {
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

    testWidgets('one wheel step zooms exactly 1.1x', (tester) async {
      // 開了雙指縮放後 InteractiveViewer 也會自己處理滾輪；不能和這裡的縮放疊加。
      await openOverlay(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await sendWheel(tester, center, -100);
      expect(currentScale(tester), closeTo(1.1, 1e-6));
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

  group('ZoomableImageOverlay single-tap zoom toggle', () {
    testWidgets('from fit (scale=1), single tap goes to 2x', (tester) async {
      await openOverlay(tester);
      expect(currentScale(tester), 1.0);
      await tester.tapAt(
        tester.getCenter(find.byType(InteractiveViewer)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(currentScale(tester), closeTo(2.0, 1e-6));
    });

    testWidgets('from 2x, single tap returns to fit (1x)', (tester) async {
      await openOverlay(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(currentScale(tester), closeTo(2.0, 1e-6));
      await tester.tapAt(center, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(currentScale(tester), closeTo(1.0, 1e-6));
    });

    testWidgets('single tap at off-center back to fit clears translation', (
      tester,
    ) async {
      await openOverlay(tester);
      final ivRect = tester.getRect(find.byType(InteractiveViewer));
      final offCenter = Offset(
        ivRect.left + ivRect.width * 0.25,
        ivRect.top + ivRect.height * 0.25,
      );
      await tester.tapAt(offCenter, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(currentScale(tester), closeTo(2.0, 1e-6));
      await tester.tapAt(offCenter, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      expect(currentScale(tester), closeTo(1.0, 1e-6));
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final translation = iv.transformationController!.value.getTranslation();
      expect(translation.x, closeTo(0, 1e-6));
      expect(translation.y, closeTo(0, 1e-6));
    });

    testWidgets('tapping image does not close overlay', (tester) async {
      await openOverlay(tester);
      await tester.tapAt(
        tester.getCenter(find.byType(InteractiveViewer)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
    });
  });

  group('ZoomableImageOverlay wheel-zoom-out identity reset', () {
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
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1.5),
        );

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
        final iv = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(
          iv.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1.0, 1e-6),
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

    testWidgets('inner GD (image) carries onTapUp (zoom) and no double-tap', (
      tester,
    ) async {
      await openOverlay(tester);
      // 最內層另有一個只處理觸控長按的 GestureDetector；這裡找負責單擊縮放的那一層。
      final innerGd = tester
          .widgetList<GestureDetector>(
            find.ancestor(
              of: find.byType(Image),
              matching: find.byType(GestureDetector),
            ),
          )
          .firstWhere((g) => g.onTapUp != null);
      expect(innerGd.behavior, HitTestBehavior.opaque);
      expect(innerGd.onTapUp, isNotNull);
      expect(innerGd.onDoubleTapDown, isNull);

      expect(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(LayoutBuilder),
        ),
        findsOneWidget,
      );
    });

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

  group('ZoomableImageOverlay cursor reflects zoom state', () {
    MouseCursor imageCursor(WidgetTester tester) {
      final region = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: find.byType(Image),
              matching: find.byType(MouseRegion),
            )
            .first,
      );
      return region.cursor;
    }

    testWidgets('at fit shows zoomIn, after zoom shows zoomOut', (
      tester,
    ) async {
      await openOverlay(tester);
      expect(imageCursor(tester), SystemMouseCursors.zoomIn);
      await tester.tapAt(
        tester.getCenter(find.byType(InteractiveViewer)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(imageCursor(tester), SystemMouseCursors.zoomOut);
    });
  });

  group('ZoomableImageOverlay top-right button row', () {
    testWidgets('shows more_vert, zoom, and close buttons', (tester) async {
      await openOverlay(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ZoomableImageOverlay)),
      )!;
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byTooltip(l.actionCloseImagePreview), findsOneWidget);
    });

    testWidgets('zoom button toggles icon and scale', (tester) async {
      await openOverlay(tester);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsNothing);
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump(const Duration(milliseconds: 50));
      final iv = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(
        iv.transformationController!.value.getMaxScaleOnAxis(),
        closeTo(2.0, 1e-6),
      );
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    });

    testWidgets('more_vert button opens copy + save menu', (tester) async {
      await openOverlay(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ZoomableImageOverlay)),
      )!;
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(l.actionCopyImage), findsOneWidget);
      expect(find.text(l.actionSaveImage), findsOneWidget);
    });
  });

  group('ZoomableImageOverlay copy/save menu', () {
    testWidgets('right-click on image shows copy + save menu', (tester) async {
      await openOverlay(tester);
      final l = AppLocalizations.of(
        tester.element(find.byType(ZoomableImageOverlay)),
      )!;
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text(l.actionCopyImage), findsOneWidget);
      expect(find.text(l.actionSaveImage), findsOneWidget);
    });

    /// 取 overlay 所在 context 的 [AppLocalizations]。
    AppLocalizations loc(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(ZoomableImageOverlay)))!;

    /// 開 ⋮ 選單並點選 [itemText]；圖片準備已換成立即回傳，pumpAndSettle 即可
    /// 讓所有 future 完成。
    Future<void> pickMenu(WidgetTester tester, String itemText) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(itemText));
      await tester.pumpAndSettle();
    }

    /// 讓圖片準備直接回傳假 bytes（[isGif] 決定當成 GIF 或 PNG）。
    void stubPrepared({bool isGif = false}) =>
        prepareOutputImageOverride = (_) async =>
            OutputImage(bytes: Uint8List(4), isGif: isGif);

    testWidgets('copy menu item calls clipboard writer and toasts', (
      tester,
    ) async {
      var called = false;
      bool? capturedIsGif;
      String? capturedPath = 'unset';
      stubPrepared();
      imageClipboardWriter = (bytes, {required isGif, filePath}) async {
        called = true;
        capturedIsGif = isGif;
        capturedPath = filePath;
        return true;
      };
      await openOverlay(tester);
      final l = loc(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.actionCopyImage));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(called, isTrue);
      expect(capturedIsGif, isFalse);
      expect(capturedPath, isNull);
      expect(find.text(l.imageCopied), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('copying a gif on Android sends no file path', (tester) async {
      bool? capturedIsGif;
      String? capturedPath = 'unset';
      stubPrepared(isGif: true);
      imageClipboardWriter = (bytes, {required isGif, filePath}) async {
        capturedIsGif = isGif;
        capturedPath = filePath;
        return true;
      };
      await openOverlay(tester, android: true);
      await pickMenu(tester, loc(tester).actionCopyImage);
      expect(capturedIsGif, isTrue);
      expect(capturedPath, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('copying a gif on desktop attaches the file path', (
      tester,
    ) async {
      String? capturedPath;
      stubPrepared(isGif: true);
      imageClipboardWriter = (bytes, {required isGif, filePath}) async {
        capturedPath = filePath;
        return true;
      };
      await openOverlay(tester);
      await pickMenu(tester, loc(tester).actionCopyImage);
      expect(capturedPath, imageFile.path);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
      'save calls picker with suggestedBaseName and shows saved toast',
      (tester) async {
        String? capturedName;
        String? capturedTitle;
        final tmp = '${tempDir.path}/out.png';
        stubPrepared();
        fileSaveDialog = (bytes, name, extension, mimeType, title) async {
          capturedName = name;
          capturedTitle = title;
          return tmp;
        };
        await openOverlay(tester);
        final l = loc(tester);
        await pickMenu(tester, l.actionSaveImage);
        expect(capturedName, 'test.png');
        expect(capturedTitle, l.dialogSaveAsTitle);
        expect(find.text(l.imageSavedTo(tmp)), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('save on Android shows the file name instead of a path', (
      tester,
    ) async {
      stubPrepared();
      fileSaveDialog = (bytes, name, extension, mimeType, title) async =>
          '/document/primary:Download/test.png';
      await openOverlay(tester, android: true);
      final l = loc(tester);
      await pickMenu(tester, l.actionSaveImage);
      expect(find.text(l.imageSavedTo('test.png')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('item image menu offers share only on Android', (tester) async {
      await openOverlay(tester, android: true);
      final l = loc(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(l.actionShare), findsOneWidget);
    });

    testWidgets('item image menu hides share on desktop', (tester) async {
      await openOverlay(tester);
      final l = loc(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(l.actionShare), findsNothing);
    });

    testWidgets('sharing an item image sends a png named after the item', (
      tester,
    ) async {
      String? name;
      String? mime;
      stubPrepared();
      fileSharer = (bytes, fileName, mimeType) async {
        name = fileName;
        mime = mimeType;
      };
      await openOverlay(tester, android: true);
      await pickMenu(tester, loc(tester).actionShare);
      expect(name, 'test.png');
      expect(mime, 'image/png');
    });

    testWidgets('item image share failure shows shareFailed', (tester) async {
      stubPrepared();
      fileSharer = (_, _, _) async => throw Exception('boom');
      await openOverlay(tester, android: true);
      final l = loc(tester);
      await pickMenu(tester, l.actionShare);
      expect(find.text(l.shareFailed), findsOneWidget);
    });

    testWidgets('a failed image preparation on save never opens the dialog', (
      tester,
    ) async {
      var asked = false;
      prepareOutputImageOverride = (_) async => null;
      fileSaveDialog = (bytes, name, extension, mimeType, title) async {
        asked = true;
        return null;
      };
      await openOverlay(tester);
      final l = loc(tester);
      await pickMenu(tester, l.actionSaveImage);
      expect(asked, isFalse);
      expect(find.text(l.imageSaveFailed), findsOneWidget);
    });

    testWidgets('a failed image preparation on share never shares', (
      tester,
    ) async {
      var shared = false;
      prepareOutputImageOverride = (_) async => null;
      fileSharer = (_, _, _) async {
        shared = true;
      };
      await openOverlay(tester, android: true);
      final l = loc(tester);
      await pickMenu(tester, l.actionShare);
      expect(shared, isFalse);
      expect(find.text(l.shareFailed), findsOneWidget);
    });

    testWidgets('save cancelled shows no toast', (tester) async {
      var asked = false;
      stubPrepared();
      fileSaveDialog = (bytes, name, extension, mimeType, title) async {
        asked = true;
        return null;
      };
      await openOverlay(tester);
      final l = loc(tester);
      await pickMenu(tester, l.actionSaveImage);
      expect(asked, isTrue);
      expect(find.textContaining(l.imageSavedTo('')), findsNothing);
      expect(find.text(l.imageSaveFailed), findsNothing);
    });
  });

  group('ZoomableImageOverlay touch', () {
    /// 取 overlay 所在 context 的 [AppLocalizations]。
    AppLocalizations loc(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(ZoomableImageOverlay)))!;

    /// InteractiveViewer（圖片區）的中心點。
    Offset center(WidgetTester tester) =>
        tester.getCenter(find.byType(InteractiveViewer));

    /// 以兩指在 viewport 中心向外拉開，模擬雙指放大。
    Future<void> pinchOut(WidgetTester tester) async {
      final c = center(tester);
      final g1 = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
      final g2 = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      for (var i = 0; i < 5; i++) {
        await g1.moveBy(const Offset(-20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();
    }

    testWidgets('pinch zooms in', (tester) async {
      await openOverlay(tester);
      await pinchOut(tester);
      expect(currentScale(tester), greaterThan(1.0));
    });

    testWidgets('pinch zoom updates the zoom button icon', (tester) async {
      // 原神版以 _zoomed 快取縮放狀態；雙指縮放也要同步到縮放鈕與游標。
      await openOverlay(tester);
      await pinchOut(tester);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    });

    testWidgets('swipe down after a pinch zoom pans instead of closing', (
      tester,
    ) async {
      await openOverlay(tester);
      await pinchOut(tester);
      await tester.dragFrom(center(tester), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
    });

    testWidgets('single touch tap does nothing', (tester) async {
      await openOverlay(tester);
      await tester.tapAt(center(tester));
      await tester.pump(const Duration(milliseconds: 400));
      expect(currentScale(tester), 1.0);
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
    });

    testWidgets('double touch tap toggles zoom', (tester) async {
      await openOverlay(tester);
      final c = center(tester);
      await tester.tapAt(c);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(c);
      await tester.pump();
      expect(currentScale(tester), closeTo(2.0, 1e-6));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(c);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(c);
      await tester.pump();
      expect(currentScale(tester), closeTo(1.0, 1e-6));
    });

    testWidgets('mouse click zooms immediately', (tester) async {
      await openOverlay(tester);
      await tester.tapAt(center(tester), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(currentScale(tester), closeTo(2.0, 1e-6));
    });

    testWidgets('long press opens the image menu', (tester) async {
      await openOverlay(tester);
      final l = loc(tester);
      await tester.longPressAt(center(tester));
      await tester.pumpAndSettle();
      expect(find.text(l.actionCopyImage), findsOneWidget);
      expect(find.text(l.actionSaveImage), findsOneWidget);
    });

    testWidgets('mouse long press still zooms instead of opening the menu', (
      tester,
    ) async {
      // 桌面行為不變：滑鼠按久一點放開仍是單擊縮放，不會跳出選單。
      await openOverlay(tester);
      final l = loc(tester);
      await tester.longPressAt(center(tester), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text(l.actionCopyImage), findsNothing);
      expect(currentScale(tester), closeTo(2.0, 1e-6));
    });

    testWidgets('swipe down closes when not zoomed', (tester) async {
      await openOverlay(tester);
      await tester.dragFrom(center(tester), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsNothing);
    });

    testWidgets('swipe down pans when zoomed', (tester) async {
      await openOverlay(tester);
      await tester.tapAt(center(tester), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.dragFrom(center(tester), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
    });

    testWidgets('mouse drag down does not close', (tester) async {
      await openOverlay(tester);
      await tester.dragFrom(
        center(tester),
        const Offset(0, 200),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
    });

    testWidgets('rotating resets the zoom', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openOverlay(tester);
      await tester.tapAt(center(tester), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(currentScale(tester), closeTo(2.0, 1e-6));
      tester.view.physicalSize = const Size(800, 360);
      await tester.pump();
      await tester.pump();
      expect(currentScale(tester), 1.0);
    });

    testWidgets('landscape notch keeps the image out of the cutout', (
      tester,
    ) async {
      // showDialog 預設 useSafeArea，瀏海那一側的邊距要算在 8dp 之外。
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(left: 44);
      tester.view.viewPadding = const FakeViewPadding(left: 44);
      addTearDown(tester.view.reset);
      await openOverlay(tester);
      expect(tester.getRect(find.byType(InteractiveViewer)).left, 44 + 8);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('phone padding is 8', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openOverlay(tester);
      expect(tester.getRect(find.byType(InteractiveViewer)).left, 8);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
