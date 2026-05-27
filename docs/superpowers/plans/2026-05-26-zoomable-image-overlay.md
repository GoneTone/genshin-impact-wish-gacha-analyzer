# Zoomable Image Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 點 `GachaItemDetailDialog` 內任一頁籤的 gallery 主圖，開啟全螢幕 lightbox `ZoomableImageOverlay`，支援滑鼠滾輪以游標為中心縮放、拖曳平移、雙擊 fit↔2x 切換、ESC / 點背景 / X 關閉。

**Architecture:** 新增獨立可重用的 `ZoomableImageOverlay` widget（不走 `AppDialog`，因 lightbox 語意 ≠ 卡片型 dialog），透過 `showDialog` + 透明 `Dialog` 撐成全螢幕。在 `GachaItemDetailDialog` 內把 `currentFile` 對應的 `Image.file` 包進 `MouseRegion(cursor: zoomIn) + GestureDetector(onTap: …)`。

**Tech Stack:** Flutter `InteractiveViewer`（pan-only，scale 我們自管）、`Listener` 接 `PointerScrollEvent`、`GestureDetector` 接 `onDoubleTapDown`、`flutter_riverpod`（既有 dialog 已用）、`logging`、`flutter_localizations` ARB i18n。

---

## 檔案總表

| 路徑 | 動作 | 職責 |
|---|---|---|
| `lib/widgets/dialogs/zoomable_image_overlay.dart` | 新增 | 公開 `ZoomableImageOverlay` widget + `showZoomableImageOverlay(...)` helper |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | 修改（line 291–313） | 將 `currentFile` 對應 `Image.file` 包成可點 tap target |
| `lib/l10n/app_zh.arb` 等 9 個 ARB | 修改 | 新增 `actionCloseImagePreview` key |
| `lib/l10n/generated/app_localizations*.dart` | 自動再生（不手動編輯） | l10n codegen 輸出 |
| `test/widgets/dialogs/zoomable_image_overlay_test.dart` | 新增 | 單元 + widget 測試 overlay 行為 |
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | 修改 | 增加 zoom 整合測試 group |

---

## Task 1: 加 i18n key `actionCloseImagePreview`

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template ARB，l10n.yaml 第 2 行）
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_pt_BR.arb`
- Modify: `lib/l10n/app_th.arb`
- Modify: `lib/l10n/app_vi.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`

> **為何 9 個都改：** 這 9 個 ARB 都已有 `actionViewOnHoYoWiki` 翻譯，是「已實體翻譯」ARB；其餘 ~30 個空殼 ARB 留給 Crowdin pipeline。（per memory `feedback_i18n_skip_empty_arbs`）

- [ ] **Step 1.1:** 在 `lib/l10n/app_zh.arb` 末尾 `actionViewOnHoYoWiki` 之後加入：

```json
,
  "actionCloseImagePreview": "關閉圖片預覽",
  "@actionCloseImagePreview": {
    "description": "Tooltip and semantic label for the close (X) button on the full-screen zoomable image overlay opened from the item detail dialog gallery."
  }
```

完成後檔案結尾應為：

```json
  "actionViewOnHoYoWiki": "前往 HoYoWiki",
  "@actionViewOnHoYoWiki": {
    "description": "Item detail dialog actions: button label that opens the HoYoLAB Wiki entry page for the current item in the default browser."
  },
  "actionCloseImagePreview": "關閉圖片預覽",
  "@actionCloseImagePreview": {
    "description": "Tooltip and semantic label for the close (X) button on the full-screen zoomable image overlay opened from the item detail dialog gallery."
  }
}
```

- [ ] **Step 1.2:** 在其餘 8 個 ARB 同位置（`actionViewOnHoYoWiki` 之後）加入對應翻譯 key（**不**附 `@...` description，那是 template ARB 專屬）：

| ARB | 翻譯 |
|---|---|
| `app_en.arb` | `"actionCloseImagePreview": "Close image preview"` |
| `app_ja.arb` | `"actionCloseImagePreview": "画像プレビューを閉じる"` |
| `app_fr.arb` | `"actionCloseImagePreview": "Fermer l'aperçu de l'image"` |
| `app_es.arb` | `"actionCloseImagePreview": "Cerrar vista previa de la imagen"` |
| `app_pt_BR.arb` | `"actionCloseImagePreview": "Fechar prévia da imagem"` |
| `app_th.arb` | `"actionCloseImagePreview": "ปิดตัวอย่างรูปภาพ"` |
| `app_vi.arb` | `"actionCloseImagePreview": "Đóng bản xem trước hình ảnh"` |
| `app_zh_Hans.arb` | `"actionCloseImagePreview": "关闭图片预览"` |

注意：前一行尾要加逗號（JSON 規定），新行不加（除非後面還有東西）。

- [ ] **Step 1.3:** 跑 l10n codegen：

```bash
flutter gen-l10n
```

Expected: 無錯誤、`lib/l10n/generated/app_localizations.dart` 內出現 `String get actionCloseImagePreview;`。

- [ ] **Step 1.4:** 驗證 generated 檔有新 key：

```bash
grep -n "actionCloseImagePreview" lib/l10n/generated/app_localizations.dart
```

Expected: 至少一行命中（abstract getter）。

- [ ] **Step 1.5:** Commit：

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_fr.arb lib/l10n/app_es.arb lib/l10n/app_pt_BR.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb lib/l10n/app_zh_Hans.arb lib/l10n/generated/
git commit -m "$(cat <<'EOF'
i18n: add actionCloseImagePreview key for zoomable image overlay close button

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `ZoomableImageOverlay` 骨架（render + close paths）

**Files:**
- Create: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Create: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

本 task 完成後 overlay 能顯示 Image.file 並透過三種途徑關閉：ESC（barrierDismissible）、X 按鈕、點 backdrop。**還沒有縮放/平移**——下一 task 才加。

- [ ] **Step 2.1:** 寫測試檔骨架 `test/widgets/dialogs/zoomable_image_overlay_test.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';

/// 1×1 透明 PNG，最小可被 Flutter decode 的 valid PNG。
const List<int> _onePxPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
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
              onPressed: () => showZoomableImageOverlay(ctx, imageFile: imageFile),
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
    testWidgets('opens with Image.file rendering the given file', (tester) async {
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
}
```

- [ ] **Step 2.2:** 跑測試應 fail（檔案還沒建）：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: 編譯失敗 `Error: Couldn't resolve the package 'genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart'.`

- [ ] **Step 2.3:** 建立 `lib/widgets/dialogs/zoomable_image_overlay.dart` 骨架：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 開啟全螢幕 lightbox 顯示 [imageFile]，可拖曳平移、滾輪 / 雙擊縮放、ESC / 點背景 / X 關閉。
Future<void> showZoomableImageOverlay(
  BuildContext context, {
  required File imageFile,
}) {
  Logger('gacha.hoyowiki.zoom').info('overlay open file=${imageFile.path}');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    // barrierDismissible: true 讓 Flutter Navigator 內建 ESC 關閉生效。
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ZoomableImageOverlay(imageFile: imageFile),
    ),
  );
}

/// 全螢幕 lightbox 圖片檢視器；獨立可重用，不耦合 caller。
class ZoomableImageOverlay extends StatefulWidget {
  /// 建立 [ZoomableImageOverlay]。
  const ZoomableImageOverlay({super.key, required this.imageFile});

  /// 要顯示的本地圖檔。
  final File imageFile;

  @override
  State<ZoomableImageOverlay> createState() => _ZoomableImageOverlayState();
}

/// [ZoomableImageOverlay] 的 state — 後續 task 會接入 `_ctrl` / wheel / double-tap。
class _ZoomableImageOverlayState extends State<ZoomableImageOverlay> {
  /// 關 overlay 並 log 來源。[reason] 走 `esc | backdrop | button` 三選一。
  void _close(BuildContext context, String reason) {
    Logger('gacha.hoyowiki.zoom').info('overlay close reason=$reason');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        // backdrop — 滿屏，點任一處（落在 InteractiveViewer 以外）即關閉。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _close(context, 'backdrop'),
          ),
        ),
        // 中央圖片區 — 留 48px padding 給 backdrop tap 區。
        Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Image.file(
              widget.imageFile,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) {
                Logger('gacha.hoyowiki.zoom').warning(
                  'image errorBuilder file=${widget.imageFile.path}',
                  e,
                  st,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        // X 按鈕 — 半透明黑底圓鈕，永遠最上層。
        Positioned(
          top: 16,
          right: 16,
          child: Material(
            color: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: l.actionCloseImagePreview,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => _close(context, 'button'),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2.4:** 跑測試應 pass：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: `All tests passed!`，4 個 test 全綠。

- [ ] **Step 2.5:** Commit：

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "$(cat <<'EOF'
feat(hoyowiki): add ZoomableImageOverlay skeleton with backdrop/ESC/X close paths

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 加 `InteractiveViewer`（pan-only，scale 我們自管）

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Modify: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

把 Image.file 套在 `InteractiveViewer(panEnabled: true, scaleEnabled: false)`，初始 scale = 1（identity matrix）。

- [ ] **Step 3.1:** 加測試到 `test/widgets/dialogs/zoomable_image_overlay_test.dart` 既有 `main()` 內：

```dart
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
```

- [ ] **Step 3.2:** 跑測試應 fail（InteractiveViewer 還沒裝）：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: 找不到 `InteractiveViewer` → `findsOneWidget` 不滿足。

- [ ] **Step 3.3:** 修改 `lib/widgets/dialogs/zoomable_image_overlay.dart`：

把 `_ZoomableImageOverlayState` 內加上 controller field 與 dispose：

```dart
class _ZoomableImageOverlayState extends State<ZoomableImageOverlay> {
  /// 縮放最小值（= fit，整圖可見）。
  static const double _minScale = 1.0;

  /// 縮放最大值。
  static const double _maxScale = 5.0;

  /// 控制 InteractiveViewer 的 Matrix4；我們手動設定 scale，InteractiveViewer 自動處理 pan。
  final TransformationController _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 關 overlay 並 log 來源。[reason] 走 `esc | backdrop | button` 三選一。
  void _close(BuildContext context, String reason) {
    Logger('gacha.hoyowiki.zoom').info('overlay close reason=$reason');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // ... (later)
  }
}
```

接著修改 `build` 內中央圖片區，把 Image.file 包進 InteractiveViewer：

```dart
        // 中央圖片區 — 留 48px padding 給 backdrop tap 區。
        Padding(
          padding: const EdgeInsets.all(48),
          child: InteractiveViewer(
            transformationController: _ctrl,
            panEnabled: true,
            scaleEnabled: false, // wheel/double-tap 自管，避免兩套 scale source 打架
            minScale: _minScale,
            maxScale: _maxScale,
            child: Center(
              child: Image.file(
                widget.imageFile,
                fit: BoxFit.contain,
                errorBuilder: (_, e, st) {
                  Logger('gacha.hoyowiki.zoom').warning(
                    'image errorBuilder file=${widget.imageFile.path}',
                    e,
                    st,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
```

- [ ] **Step 3.4:** 跑測試應 pass：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: `All tests passed!`

注意：Task 2 的 `tap on backdrop area closes overlay` 可能會受 InteractiveViewer 影響——InteractiveViewer 預設 `clipBehavior: Clip.hardEdge`，但其 widget 本身仍佔 padding 內整塊區。`(5, 5)` 在 padding 之外 ✓ 不變。

若該測試掛了，檢查 padding 是否被吃掉（不該）。

- [ ] **Step 3.5:** Commit：

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "$(cat <<'EOF'
feat(hoyowiki): wrap ZoomableImageOverlay image in pan-only InteractiveViewer

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 滑鼠滾輪以游標為中心縮放 + scale clamp

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Modify: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

加 `Listener` 接 `PointerScrollEvent`，用 `_zoomAt` 計算 cursor-centered 的 Matrix4。

- [ ] **Step 4.1:** 加測試到 `test/widgets/dialogs/zoomable_image_overlay_test.dart`：

```dart
  group('ZoomableImageOverlay wheel zoom', () {
    /// 抓取當前 InteractiveViewer 的 scale。
    double currentScale(WidgetTester tester) {
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      return iv.transformationController!.value.getMaxScaleOnAxis();
    }

    /// 對 [position] 派發一次滾輪事件。[delta] 為 Offset.dy；負值 = 向上 = 放大。
    Future<void> sendWheel(
      WidgetTester tester,
      Offset position,
      double deltaY,
    ) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(position));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, deltaY),
        ),
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
  });
```

- [ ] **Step 4.2:** 跑測試應 fail：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: scale 維持 1.0，wheel 沒效果。

- [ ] **Step 4.3:** 加 wheel 處理到 `lib/widgets/dialogs/zoomable_image_overlay.dart`：

`_ZoomableImageOverlayState` 內加常數與 `_zoomAt`：

```dart
  /// 滑鼠滾輪每一格的縮放係數（×1.1 in / ÷1.1 out）。
  static const double _wheelStep = 1.1;

  /// 以 [localFocal]（InteractiveViewer 內局部座標）為中心套用 [scaleDelta] 倍縮放。
  /// 公式：T(focal) · S(delta) · T(-focal) · M，確保焦點 scene 位置在縮放後不動。
  void _zoomAt({required Offset localFocal, required double scaleDelta}) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    final next = (current * scaleDelta).clamp(_minScale, _maxScale);
    final actual = next / current;
    if ((actual - 1).abs() < 1e-6) return;
    _ctrl.value = (Matrix4.identity()
          ..translate(localFocal.dx, localFocal.dy)
          ..scale(actual)
          ..translate(-localFocal.dx, -localFocal.dy)) *
        _ctrl.value;
  }

  /// 處理 mouse wheel：向上（scrollDelta.dy < 0）放大、向下縮小，以游標為中心。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy < 0 ? _wheelStep : 1 / _wheelStep;
    _zoomAt(localFocal: event.localPosition, scaleDelta: delta);
  }
```

在 `build` 內把 InteractiveViewer 包進 `Listener`：

```dart
        Padding(
          padding: const EdgeInsets.all(48),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: InteractiveViewer(
              transformationController: _ctrl,
              panEnabled: true,
              scaleEnabled: false,
              minScale: _minScale,
              maxScale: _maxScale,
              child: Center(
                child: Image.file(...),
              ),
            ),
          ),
        ),
```

加 import：

```dart
import 'package:flutter/gestures.dart'; // PointerSignalEvent, PointerScrollEvent
```

- [ ] **Step 4.4:** 跑測試應 pass：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: `All tests passed!` — wheel 4 個 test 全綠、Task 2/3 共 6 個 test 不破。

- [ ] **Step 4.5:** Commit：

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "$(cat <<'EOF'
feat(hoyowiki): add cursor-centered mouse wheel zoom with clamp to ZoomableImageOverlay

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 雙擊在 fit ↔ 2x 切換

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Modify: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

- [ ] **Step 5.1:** 加測試：

```dart
  group('ZoomableImageOverlay double-tap toggle', () {
    double currentScale(WidgetTester tester) {
      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
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
      await doubleTapAt(tester, tester.getCenter(find.byType(InteractiveViewer)));
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
          PointerScrollEvent(position: center, scrollDelta: const Offset(0, -100)),
        );
        await tester.pump();
      }
      expect(currentScale(tester), greaterThan(2.5));
      await doubleTapAt(tester, center);
      expect(currentScale(tester), closeTo(1.0, 1e-6));
    });
  });
```

- [ ] **Step 5.2:** 跑測試應 fail：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: 雙擊測試掛（沒處理 onDoubleTapDown）。

- [ ] **Step 5.3:** 加 double-tap 處理到 `lib/widgets/dialogs/zoomable_image_overlay.dart`：

`_ZoomableImageOverlayState` 內加：

```dart
  /// 雙擊時的目標 scale；fit ↔ 2x 切換。
  static const double _doubleTapScale = 2.0;

  /// 雙擊：當前接近 fit → 放到 [_doubleTapScale]；否則回 fit。以 tap 落點為焦點縮放。
  void _onDoubleTapDown(TapDownDetails details) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    final atFit = (current - _minScale).abs() < 0.05;
    final target = atFit ? _doubleTapScale : _minScale;
    _zoomAt(localFocal: details.localPosition, scaleDelta: target / current);
  }
```

把 InteractiveViewer 包進 `GestureDetector`（Listener 內、InteractiveViewer 外）：

```dart
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: GestureDetector(
              onDoubleTapDown: _onDoubleTapDown,
              child: InteractiveViewer(
                transformationController: _ctrl,
                panEnabled: true,
                scaleEnabled: false,
                minScale: _minScale,
                maxScale: _maxScale,
                child: Center(child: Image.file(...)),
              ),
            ),
          ),
```

- [ ] **Step 5.4:** 跑測試應 pass：

```bash
flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart
```

Expected: `All tests passed!` — 雙擊兩個 test 綠、既有 8 個 test 不破。

- [ ] **Step 5.5:** Commit：

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "$(cat <<'EOF'
feat(hoyowiki): add double-tap toggle (fit ↔ 2x) to ZoomableImageOverlay

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 整合到 `GachaItemDetailDialog`

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`（line 291–313）
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

把 `currentFile` 對應的 `Image.file` 區包成可點 tap target。

- [ ] **Step 6.1:** 加測試到 `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` 內 `group('GachaItemDetailDialog gallery', ...)` 末尾、`});` 之前：

```dart
    testWidgets('點 gallery 主圖 → 開啟 ZoomableImageOverlay', (tester) async {
      late File picFile;
      late File origFile;
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        picFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/card.png',
        );
        await _touchFile(tempDir, picFile.uri.pathSegments.last);
        origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      // 沿用既有 imgFinder 邏輯：當前主圖（list[0] = orig）落在 dialog 內。
      final mainImage = find.descendant(
        of: find.byType(GachaItemDetailDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is FileImage &&
              (w.image as FileImage).file.path.endsWith(
                origFile.uri.pathSegments.last,
              ),
        ),
      );
      expect(mainImage, findsOneWidget);

      // 點主圖開 overlay。
      await tester.tap(mainImage);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ZoomableImageOverlay), findsOneWidget);
      final overlayImg = tester.widget<Image>(
        find.descendant(
          of: find.byType(ZoomableImageOverlay),
          matching: find.byType(Image),
        ),
      );
      expect(overlayImg.image, isA<FileImage>());
      expect((overlayImg.image as FileImage).file.path, origFile.path);
    });

    testWidgets('切到「卡片」chip 後點主圖 → overlay 開的是 pic 檔', (tester) async {
      late File picFile;
      late File origFile;
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        picFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/card.png',
        );
        await _touchFile(tempDir, picFile.uri.pathSegments.last);
        origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      await tester.tap(find.text('Card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final mainImage = find.descendant(
        of: find.byType(GachaItemDetailDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is FileImage &&
              (w.image as FileImage).file.path.endsWith(
                picFile.uri.pathSegments.last,
              ),
        ),
      );
      await tester.tap(mainImage);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final overlayImg = tester.widget<Image>(
        find.descendant(
          of: find.byType(ZoomableImageOverlay),
          matching: find.byType(Image),
        ),
      );
      expect((overlayImg.image as FileImage).file.path, picFile.path);
    });

    testWidgets('gallery 主圖 wrapper 有 zoomIn cursor', (tester) async {
      await tester.runAsync(() async {
        await _touchFile(tempDir, '12345_icon.png');
        final origFile = hoyowikiGalleryCacheFile(
          baseDir: tempDir,
          id: '12345',
          url: 'https://x/orig.png',
        );
        await _touchFile(tempDir, origFile.uri.pathSegments.last);
        await seedEntry(
          '12345',
          'Hu Tao',
          'en-us',
          _entryWith(
            iconUrl: 'https://x/icon.png',
            picUrl: '',
            list: [
              HoYoWikiGalleryItem(
                id: 'a',
                key: 'Original',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '',
              ),
            ],
          ),
        );
      });

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      // 主圖外層應有 MouseRegion(cursor: zoomIn)。
      final mouseRegions = tester.widgetList<MouseRegion>(
        find.descendant(
          of: find.byType(GachaItemDetailDialog),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(
        mouseRegions.any((m) => m.cursor == SystemMouseCursors.zoomIn),
        isTrue,
      );
    });
```

並在檔頂 imports 加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';
```

- [ ] **Step 6.2:** 跑測試應 fail：

```bash
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: 三個新 test 都掛（沒 wrapper、點圖不會開 overlay）。

- [ ] **Step 6.3:** 修改 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` line 291–313 區塊：

加 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';
```

把原本：

```dart
          if (currentFile != null)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  currentFile,
                  key: ValueKey(currentFile.path),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                  errorBuilder: (_, e, st) {
                    Logger('gacha.hoyowiki.detail').warning(
                      'gallery image errorBuilder id=$id path=${currentFile.path}',
                      e,
                      st,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
```

改為：

```dart
          if (currentFile != null)
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Logger('gacha.hoyowiki.detail').info(
                      'open zoom id=$id path=${currentFile.path}',
                    );
                    showZoomableImageOverlay(context, imageFile: currentFile);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.file(
                      currentFile,
                      key: ValueKey(currentFile.path),
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      gaplessPlayback: true,
                      errorBuilder: (_, e, st) {
                        Logger('gacha.hoyowiki.detail').warning(
                          'gallery image errorBuilder id=$id path=${currentFile.path}',
                          e,
                          st,
                        );
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            ),
```

- [ ] **Step 6.4:** 跑測試應 pass：

```bash
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: `All tests passed!` — 新 3 個 test 綠、既有所有 test 不破。

- [ ] **Step 6.5:** Commit：

```bash
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(hoyowiki): open ZoomableImageOverlay when gallery main image is tapped

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 提交前品質檢查 + manual verify

按 CLAUDE.md「提交前品質檢查」：

- [ ] **Step 7.1:** 格式化（注意：勿對 `.` 跑，會動到 `rust_builder/`）：

```bash
dart format lib/ test/
```

Expected: 列出有調整的檔；理想情況 `0 changed`。若有改動，下面驗 analyze + test 仍綠後 amend 進前個 commit 或新增 format commit。

- [ ] **Step 7.2:** 靜態分析：

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 7.3:** 全套測試：

```bash
flutter test
```

Expected: `All tests passed!`

若 format 在 7.1 改了檔，補上一個 format commit：

```bash
git add lib/ test/
git commit -m "$(cat <<'EOF'
style: dart format zoomable image overlay code

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7.4:** Manual verify（per CLAUDE.md「UI 要實際測 release」+ memory `feedback_perf_check_release_first`）：

```bash
flutter run --release
```

開 app → 任一 5★ 角色 record → 開 detail dialog → 點立繪 chip → 點主圖。

Checklist：

- [ ] Overlay 出現、黑色半透背景蓋滿視窗
- [ ] 滑鼠輪向上 → 以游標位置為中心放大
- [ ] 滑鼠輪向下 → 縮小，到 1x 後不再縮
- [ ] 放大後拖曳 → 可平移看不同區域
- [ ] 雙擊 → 從 1x 跳到 2x
- [ ] 再雙擊 → 回 1x
- [ ] ESC → overlay 關閉
- [ ] 點黑底（角落 padding 區）→ overlay 關閉
- [ ] 點右上 X 按鈕 → overlay 關閉
- [ ] 切到「Card」chip 再點主圖 → overlay 顯示的是 pic 卡片
- [ ] 切到「Icon」chip 再點主圖 → overlay 顯示的是 icon 圖
- [ ] 若 chip 是 GIF（部分立繪 chip）→ overlay 內 GIF 仍會動

若 manual 驗證發現 bug，列為新 task 修，不要直接 force amend 既有 commit。

---

## 自審記錄

**Spec 覆蓋檢查：** Task 1 覆蓋 i18n、Task 2-5 覆蓋 overlay widget（skeleton → InteractiveViewer → wheel → double-tap）、Task 6 覆蓋整合、Task 7 覆蓋品質檢查與 manual verify。Spec 內所有條目均有對應 task。

**Placeholder 掃描：** 無「TBD」「TODO」「Similar to Task N」「fill in」等 placeholder；每個 code step 都有可執行的完整程式碼片段。i18n 翻譯依 best effort 提供，後續可在 Crowdin 流程內 polish。

**Type 一致性：** `TransformationController _ctrl`、`_minScale = 1.0`、`_maxScale = 5.0`、`_doubleTapScale = 2.0`、`_wheelStep = 1.1`、`_zoomAt(localFocal:, scaleDelta:)`、`_onPointerSignal`、`_onDoubleTapDown` 名稱全程一致。

**Scope：** 5 個 code task + 1 個 i18n task + 1 個品質檢查 task，單一 plan 可完成；不需拆分。
