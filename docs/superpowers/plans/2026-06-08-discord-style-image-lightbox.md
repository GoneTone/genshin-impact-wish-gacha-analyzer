# Discord 式圖片 lightbox 升級 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ZoomableImageOverlay` 全螢幕圖片檢視器改成 Discord 式互動（單擊縮放、游標隨狀態切 zoomIn/zoomOut、右上角 `[⋮][🔍][✕]` 按鈕列、右鍵與 ⋮ 選單可複製／儲存），且 copy/save 提示不被 lightbox 黑幕蓋住。

**Architecture:** 改寫單一 widget `lib/widgets/dialogs/zoomable_image_overlay.dart`：沿用現有雙層 GestureDetector（外層暗區關閉、內層圖片像素區）與 `_zoomAt` focal 縮放矩陣，把內層手勢由「空吸收 + 雙擊縮放」改為「單擊 fit↔2x 切換」，新增 `_zoomed` 衍生狀態驅動游標與縮放鈕 icon。copy/save 直接呼叫既有 service（`copyImageFileToClipboard` / `saveImageFile`），結果用 `showDialogToast`（插到 navigator overlay，疊在 lightbox route 之上）回報。呼叫端 `gacha_item_detail_dialog.dart` 開 lightbox 時補傳建議檔名。

**Tech Stack:** Flutter / Dart、`flutter_localizations`（ARB + `fvm flutter gen-l10n`）、既有 `services/image_clipboard_save.dart`、`widgets/dialogs/dialog_toast.dart`、`flutter_test`、FVM。

---

## File Structure

- **Modify** `lib/widgets/dialogs/zoomable_image_overlay.dart` — 全部互動改寫、按鈕列、選單、copy/save、新 import。核心檔。
- **Modify** `lib/widgets/dialogs/gacha_item_detail_dialog.dart`（約 350-353 行）— 開 lightbox 時補傳 `suggestedBaseName`。
- **Modify** `lib/l10n/app_zh.arb`、`lib/l10n/app_en.arb` — 新增 `actionZoomIn` / `actionZoomOut`（含 `@` metadata）。
- **Modify** `lib/l10n/app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`、`app_zh_Hans.arb` — 補齊本功能 8 個 key（`actionCopyImage` / `actionSaveImage` / `imageCopied` / `imageCopyFailed` / `imageSaveFailed` / `imageSavedTo` / `actionZoomIn` / `actionZoomOut`）。空殼 ARB（22 個，僅 4 key）不動。
- **Generated（勿手改）** `lib/l10n/generated/app_localizations*.dart` — 由 `fvm flutter gen-l10n` 產出。
- **Modify** `test/widgets/dialogs/zoomable_image_overlay_test.dart` — 更新 helper 傳 `suggestedBaseName`、雙擊→單擊、新增按鈕／選單／游標／copy-save 測試。

---

## Task 1: l10n — 新增 zoom 字串並補齊已翻檔

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_es.arb`, `app_fr.arb`, `app_ja.arb`, `app_pt_BR.arb`, `app_th.arb`, `app_vi.arb`, `app_zh_Hans.arb`

> ⚠️ 已翻檔（es/fr/ja/pt_BR/th/vi/zh_Hans）**結尾沒有 newline**（最後一個 byte 是 `}` 不是 `}\n`），且最後一個 key 為 `@actionCloseImagePreview`。用 Edit 工具替換時，`new_string` 結尾也必須是 `}` 不加 newline。改完用 `git diff --stat` 與 `tail` 確認沒被加結尾換行。

- [ ] **Step 1: app_zh.arb 加 actionZoomIn / actionZoomOut**

在 `app_zh.arb` 的 `"@actionSaveImage": { ... },` 區塊**之後**插入（即 actionSaveImage 的 `@` 區塊收尾 `},` 後）：

```json
  "actionZoomIn": "放大",
  "@actionZoomIn": {
    "description": "Tooltip for the zoom-in toggle button on the full-screen zoomable image overlay; shown when the image is at fit (clicking zooms in)."
  },
  "actionZoomOut": "縮小",
  "@actionZoomOut": {
    "description": "Tooltip for the zoom-out toggle button on the full-screen zoomable image overlay; shown when the image is zoomed in (clicking returns to fit)."
  },
```

- [ ] **Step 2: app_en.arb 加 actionZoomIn / actionZoomOut**

在 `app_en.arb` 的 `"@actionSaveImage"` 區塊之後插入：

```json
  "actionZoomIn": "Zoom In",
  "@actionZoomIn": {
    "description": "Tooltip for the zoom-in toggle button on the full-screen zoomable image overlay; shown when the image is at fit (clicking zooms in)."
  },
  "actionZoomOut": "Zoom Out",
  "@actionZoomOut": {
    "description": "Tooltip for the zoom-out toggle button on the full-screen zoomable image overlay; shown when the image is zoomed in (clicking returns to fit)."
  },
```

- [ ] **Step 3: 7 個已翻檔各補 8 個 key（含 @ metadata）**

每個檔目前結尾為：

```json
  "actionCloseImagePreview": "<該語言既有翻譯>",
  "@actionCloseImagePreview": {
    "description": "Tooltip and semantic label for the close (X) button on the full-screen zoomable image overlay opened from the item detail dialog gallery."
  }
}
```

把最後的 `  }\n}` 改成 `  },` 後接下列各語言 8 key、再以 `}` 收尾（結尾不加 newline）。`@` description 一律沿用英文 master，`imageSavedTo` 需帶 `placeholders`。

**app_ja.arb** 追加：

```json
  },
  "actionCopyImage": "画像をコピー",
  "@actionCopyImage": {
    "description": "Item detail dialog image menu: option that copies the currently shown image to the system clipboard as PNG."
  },
  "actionSaveImage": "画像を保存",
  "@actionSaveImage": {
    "description": "Item detail dialog image menu: option that opens the system save dialog to save the currently shown image as PNG."
  },
  "imageCopied": "画像をクリップボードにコピーしました",
  "@imageCopied": {
    "description": "Item detail dialog snackbar shown when the image is successfully copied to the clipboard."
  },
  "imageCopyFailed": "画像のコピーに失敗しました",
  "@imageCopyFailed": {
    "description": "Item detail dialog snackbar shown when copying the image to the clipboard fails."
  },
  "imageSaveFailed": "画像の保存に失敗しました",
  "@imageSaveFailed": {
    "description": "Item detail dialog snackbar shown when saving the image to disk fails."
  },
  "imageSavedTo": "{path} に保存しました",
  "@imageSavedTo": {
    "description": "Item detail dialog snackbar shown after the image is saved, with the full save path.",
    "placeholders": {
      "path": {
        "type": "String"
      }
    }
  },
  "actionZoomIn": "拡大",
  "@actionZoomIn": {
    "description": "Tooltip for the zoom-in toggle button on the full-screen zoomable image overlay; shown when the image is at fit (clicking zooms in)."
  },
  "actionZoomOut": "縮小",
  "@actionZoomOut": {
    "description": "Tooltip for the zoom-out toggle button on the full-screen zoomable image overlay; shown when the image is zoomed in (clicking returns to fit)."
  }
}
```

**app_es.arb** 各值：`actionCopyImage`=`Copiar imagen`、`actionSaveImage`=`Guardar imagen`、`imageCopied`=`Imagen copiada al portapapeles`、`imageCopyFailed`=`Error al copiar la imagen`、`imageSaveFailed`=`Error al guardar la imagen`、`imageSavedTo`=`Guardado en {path}`、`actionZoomIn`=`Acercar`、`actionZoomOut`=`Alejar`（`@` 區塊與 ja 相同英文 description 與 placeholders 結構）。

**app_fr.arb** 各值：`Copier l'image`、`Enregistrer l'image`、`Image copiée dans le presse-papiers`、`Échec de la copie de l'image`、`Échec de l'enregistrement de l'image`、`Enregistré dans {path}`、`Zoom avant`、`Zoom arrière`。

**app_pt_BR.arb** 各值：`Copiar imagem`、`Salvar imagem`、`Imagem copiada para a área de transferência`、`Falha ao copiar a imagem`、`Falha ao salvar a imagem`、`Salvo em {path}`、`Ampliar`、`Reduzir`。

**app_th.arb** 各值：`คัดลอกรูปภาพ`、`บันทึกรูปภาพ`、`คัดลอกรูปภาพไปยังคลิปบอร์ดแล้ว`、`คัดลอกรูปภาพไม่สำเร็จ`、`บันทึกรูปภาพไม่สำเร็จ`、`บันทึกไปยัง {path} แล้ว`、`ขยาย`、`ย่อ`。

**app_vi.arb** 各值：`Sao chép hình ảnh`、`Lưu hình ảnh`、`Đã sao chép hình ảnh vào bảng nhớ tạm`、`Sao chép hình ảnh thất bại`、`Lưu hình ảnh thất bại`、`Đã lưu vào {path}`、`Phóng to`、`Thu nhỏ`。

**app_zh_Hans.arb** 各值：`复制图片`、`保存图片`、`图片已复制到剪贴板`、`复制图片失败`、`保存图片失败`、`已保存至 {path}`、`放大`、`缩小`。

每檔結構同上述 ja 範本（key-value + 對應英文 `@description`，`imageSavedTo` 帶 placeholders），只換 8 個 value。

- [ ] **Step 4: 產生 localizations**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `actionZoomIn` / `actionZoomOut` getter。

- [ ] **Step 5: 驗證 key 已就位、檔尾未被加 newline**

Run: `git -C E:/IdeaProjects/genshin_impact_wish_gacha_analyzer diff --stat lib/l10n`
Expected: 列出 9 個 `app_*.arb` + generated 變更；7 個已翻檔每檔 +約 33 行、zh/en 各 +約 9 行。

抽驗 `app_ja.arb` 最後一個 byte 仍為 `}`（非 `}\n`）：可用編輯器或 `tail -c1`。若被加了結尾 newline，移除之。

- [ ] **Step 6: analyze + 既有測試仍綠**

Run: `fvm flutter analyze`
Expected: `No issues found!`

Run: `fvm flutter test`
Expected: `All tests passed!`（此時尚未改程式，純加 l10n key 不影響）

- [ ] **Step 7: Commit**

```bash
git add lib/l10n
git commit -m "feat(l10n): add zoom-in/out strings, backfill image action keys for translated locales"
```

---

## Task 2: 為 overlay 新增 suggestedBaseName 參數並更新呼叫端

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart:350-353`
- Test: `test/widgets/dialogs/zoomable_image_overlay_test.dart:104-125`

- [ ] **Step 1: 更新測試 helper 傳新參數（先讓編譯需求成形）**

在 `zoomable_image_overlay_test.dart` 的 `openOverlay` 內呼叫改為：

```dart
onPressed: () => showZoomableImageOverlay(
  ctx,
  imageFile: imageFile,
  suggestedBaseName: 'test',
),
```

- [ ] **Step 2: 跑測試確認因缺參數而失敗**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`
Expected: 編譯錯誤 `No named parameter with the name 'suggestedBaseName'`。

- [ ] **Step 3: overlay 新增參數**

`showZoomableImageOverlay` 簽名加 `required String suggestedBaseName`，並傳入 widget：

```dart
Future<void> showZoomableImageOverlay(
  BuildContext context, {
  required File imageFile,
  required String suggestedBaseName,
}) {
  Logger('gacha.hoyowiki.zoom').info('overlay open file=${imageFile.path}');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ZoomableImageOverlay(
        imageFile: imageFile,
        suggestedBaseName: suggestedBaseName,
      ),
    ),
  );
}
```

`ZoomableImageOverlay` 加欄位：

```dart
const ZoomableImageOverlay({
  super.key,
  required this.imageFile,
  required this.suggestedBaseName,
});

/// 要顯示的本地圖檔。
final File imageFile;

/// copy/save「另存」對話框的建議檔名（不含副檔名）。
final String suggestedBaseName;
```

- [ ] **Step 4: 更新呼叫端傳入建議檔名**

`gacha_item_detail_dialog.dart` 內 `_buildCurrentImageArea` 的 `onTap`（約 350-353 行）改為：

```dart
onTap: () {
  _log.info('open zoom path=${sanitizeFsPath(file.path)}');
  showZoomableImageOverlay(
    context,
    imageFile: file,
    suggestedBaseName: _suggestedBaseName(current),
  );
},
```

- [ ] **Step 5: analyze + 測試（既有測試應全綠）**

Run: `fvm flutter analyze`
Expected: `No issues found!`

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "feat(lightbox): thread suggestedBaseName into zoomable image overlay"
```

---

## Task 3: 單擊縮放 + 游標隨狀態切換（取代雙擊）

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Test: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

- [ ] **Step 1: 改寫 double-tap 測試群為 single-tap zoom toggle**

把 `zoomable_image_overlay_test.dart` 內 `group('ZoomableImageOverlay double-tap toggle', ...)` 整段換成：

```dart
group('ZoomableImageOverlay single-tap zoom toggle', () {
  double currentScale(WidgetTester tester) {
    final iv = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    return iv.transformationController!.value.getMaxScaleOnAxis();
  }

  testWidgets('from fit (scale=1), single tap goes to 2x', (tester) async {
    await openOverlay(tester);
    expect(currentScale(tester), 1.0);
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(currentScale(tester), closeTo(2.0, 1e-6));
  });

  testWidgets('from 2x, single tap returns to fit (1x)', (tester) async {
    await openOverlay(tester);
    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(currentScale(tester), closeTo(2.0, 1e-6));
    await tester.tapAt(center);
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
    await tester.tapAt(offCenter);
    await tester.pump(const Duration(milliseconds: 50));
    expect(currentScale(tester), closeTo(2.0, 1e-6));
    await tester.tapAt(offCenter);
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
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ZoomableImageOverlay), findsOneWidget);
  });
});
```

- [ ] **Step 2: 改寫「tap-to-close structure」群的內層 GD 斷言**

把 `group('ZoomableImageOverlay tap-to-close structure', ...)` 內第一個 test（`inner GD ... onTap ... onDoubleTapDown`）的斷言改為驗證內層 GD 改用 `onTapUp`、不再有 `onDoubleTapDown`（`onSecondaryTapDown` 於 Task 4 才掛上，此處先不斷言）：

```dart
testWidgets(
  'inner GD (image) carries onTapUp (zoom) and no double-tap',
  (tester) async {
    await openOverlay(tester);
    final innerGd = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.byType(Image),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
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
  },
);
```

第二個 test（outer GD 只有 onTap、無 onDoubleTap）保留不動。

- [ ] **Step 3: 新增游標狀態測試**

在同檔尾端新增：

```dart
group('ZoomableImageOverlay cursor reflects zoom state', () {
  /// 取得包住 Image 的 MouseRegion 的 cursor。
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

  testWidgets('at fit shows zoomIn, after zoom shows zoomOut', (tester) async {
    await openOverlay(tester);
    expect(imageCursor(tester), SystemMouseCursors.zoomIn);
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(imageCursor(tester), SystemMouseCursors.zoomOut);
  });
});
```

- [ ] **Step 4: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`
Expected: FAIL（內層仍是 onTap/onDoubleTapDown、無 MouseRegion zoom cursor、單擊不縮放）。

- [ ] **Step 5: 改寫 overlay state — 常數、欄位、方法**

在 `_ZoomableImageOverlayState`：

把常數 `_doubleTapScale` 改名為 `_zoomedScale`：

```dart
/// 放大狀態的目標 scale；fit ↔ 此值切換。
static const double _zoomedScale = 2.0;
```

新增欄位（放在 `_imageSize` 附近）：

```dart
/// 目前是否已放大（scale > fit）；驅動圖片游標與縮放鈕 icon。
bool _zoomed = false;

/// 最近一次 layout 的 viewport 尺寸；供縮放鈕以 viewport 中心為焦點縮放。
Size? _viewportSize;
```

移除 `_onDoubleTapDown`，新增 `_syncZoomed` 與 `_toggleZoom`：

```dart
/// 由當前矩陣推導 [_zoomed]；有變才 setState（讓游標／icon 同步、避免多餘 rebuild）。
void _syncZoomed() {
  final z = (_ctrl.value.getMaxScaleOnAxis() - _minScale).abs() >= 0.05;
  if (z != _zoomed) setState(() => _zoomed = z);
}

/// 單擊圖片或按縮放鈕：在 fit ↔ [_zoomedScale] 間切換，以 [viewportFocal]
/// （viewport 局部座標）為焦點。
void _toggleZoom(Offset viewportFocal) {
  final current = _ctrl.value.getMaxScaleOnAxis();
  final atFit = (current - _minScale).abs() < 0.05;
  final target = atFit ? _zoomedScale : _minScale;
  _zoomAt(localFocal: viewportFocal, scaleDelta: target / current);
  _syncZoomed();
  Logger('gacha.hoyowiki.zoom').info('zoom toggle -> ${atFit ? 'in' : 'fit'}');
}
```

`_onPointerSignal` 末尾補 `_syncZoomed()`：

```dart
void _onPointerSignal(PointerSignalEvent event) {
  if (event is! PointerScrollEvent) return;
  if (event.scrollDelta.dy == 0) return;
  final delta = event.scrollDelta.dy < 0 ? _wheelStep : 1 / _wheelStep;
  _zoomAt(localFocal: event.localPosition, scaleDelta: delta);
  _syncZoomed();
}
```

- [ ] **Step 6: 改寫 build 內圖片區（LayoutBuilder → SizedBox → MouseRegion → GestureDetector）**

把現有 `LayoutBuilder` 的 builder 改為：

```dart
child: LayoutBuilder(
  builder: (_, constraints) {
    _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
    final imgSize = _imageSize;
    double w = constraints.maxWidth;
    double h = constraints.maxHeight;
    if (imgSize != null && imgSize.width > 0 && imgSize.height > 0) {
      final scale = (w / imgSize.width) < (h / imgSize.height)
          ? w / imgSize.width
          : h / imgSize.height;
      w = imgSize.width * scale;
      h = imgSize.height * scale;
    }
    // SizedBox 相對 viewport 置中的偏移；tap 落點（SizedBox 局部）加此偏移
    // 還原成 viewport 局部座標，與滾輪／縮放鈕同一座標空間。
    final dx = (constraints.maxWidth - w) / 2;
    final dy = (constraints.maxHeight - h) / 2;
    return SizedBox(
      width: w,
      height: h,
      child: MouseRegion(
        cursor: _zoomed
            ? SystemMouseCursors.zoomOut
            : SystemMouseCursors.zoomIn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 單擊圖片像素區 → fit↔2x 切換（焦點＝點擊落點還原成 viewport 座標）。
          // 圖片不再單擊關閉；暗區關閉由外層 GD 處理（對應 Discord）。
          onTapUp: (d) => _toggleZoom(d.localPosition + Offset(dx, dy)),
          child: Image(
            image: _imageProvider,
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
    );
  },
),
```

更新該 `LayoutBuilder` 上方註解（移除提及「雙擊縮放／onTap 空吸收」的舊敘述，改述「單擊縮放、暗區關閉」）。

- [ ] **Step 7: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`
Expected: 上述新群組 PASS（右鍵選單測試將於 Task 4 加入，尚未存在）。

- [ ] **Step 8: analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "feat(lightbox): single-click zoom toggle with state-aware cursor"
```

---

## Task 4: copy/save 選單 + 右鍵叫出

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Test: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

- [ ] **Step 1: 新增右鍵選單 + copy/save service 測試**

在測試檔頂部 import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
```

`tearDown` 內加（還原 service seam）：

```dart
resetImageClipboardSaveSeams();
```

新增測試群：

```dart
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

  testWidgets('copy menu item calls clipboard writer and toasts', (
    tester,
  ) async {
    var called = false;
    imageClipboardWriter = (bytes, {required isGif, filePath}) async {
      called = true;
      return true;
    };
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
    await tester.tap(find.text(l.actionCopyImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(called, isTrue);
    expect(find.text(l.imageCopied), findsOneWidget);
  });

  testWidgets('save menu item calls save picker and toasts path', (
    tester,
  ) async {
    imageSaveLocationPicker = (name) async =>
        FileSaveLocation('${tempDir.path}/out.png');
    imageFileWriter = (path, bytes) async {};
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
    await tester.tap(find.text(l.actionSaveImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(l.imageSavedTo('${tempDir.path}/out.png')), findsOneWidget);
  });
});
```

> `FileSaveLocation` 來自 `package:file_selector/file_selector.dart`；若 linter 需要，於測試檔 import。`kSecondaryMouseButton` / `PointerDeviceKind` 來自既有 `flutter/gestures.dart` import。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart -n "copy/save menu"`
Expected: FAIL（尚無右鍵選單／選單項）。

- [ ] **Step 3: overlay 加 import 與選單／copy/save 方法**

檔頂 import 補：

```dart
import 'dart:async';
```
（若尚未有）以及

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/dialog_toast.dart';
```

在 `_ZoomableImageOverlayState` 內新增：

```dart
/// copy/save 共用選單項目（複製圖片 / 儲存圖片）；⋮ 按鈕與右鍵選單共用。
List<PopupMenuEntry<String>> _menuItems(AppLocalizations l) => [
  PopupMenuItem(
    value: 'copy',
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.copy, size: 20),
      title: Text(l.actionCopyImage),
    ),
  ),
  PopupMenuItem(
    value: 'save',
    child: ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.save_alt, size: 20),
      title: Text(l.actionSaveImage),
    ),
  ),
];

/// 分派選單選擇：複製 / 儲存。
void _onMenuSelected(String value) {
  switch (value) {
    case 'copy':
      unawaited(_copy());
    case 'save':
      unawaited(_save());
  }
}

/// 複製目前圖片到剪貼簿（GIF 保留動畫、其餘轉 PNG），結果以 toast 回報。
Future<void> _copy() async {
  final l = AppLocalizations.of(context)!;
  Logger('gacha.hoyowiki.zoom').info('menu copy');
  final ok = await copyImageFileToClipboard(widget.imageFile);
  if (!mounted) return;
  showDialogToast(context, ok ? l.imageCopied : l.imageCopyFailed);
}

/// 儲存目前圖片（GIF 存 .gif、其餘轉 PNG）→ 系統存檔對話框，結果以 toast 回報。
Future<void> _save() async {
  final l = AppLocalizations.of(context)!;
  Logger('gacha.hoyowiki.zoom').info('menu save');
  try {
    final path = await saveImageFile(
      widget.imageFile,
      suggestedBaseName: widget.suggestedBaseName,
    );
    if (!mounted || path == null) return;
    showDialogToast(context, l.imageSavedTo(path));
  } catch (_) {
    if (!mounted) return;
    showDialogToast(context, l.imageSaveFailed);
  }
}

/// 右鍵在圖片上叫出與 ⋮ 相同的選單，位置跟著游標。
Future<void> _showContextMenu(Offset globalPosition) async {
  final l = AppLocalizations.of(context)!;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: _menuItems(l),
  );
  if (selected == null || !mounted) return;
  _onMenuSelected(selected);
}
```

- [ ] **Step 4: 內層圖片 GestureDetector 掛右鍵**

在 Task 3 的內層 `GestureDetector` 加 `onSecondaryTapDown`：

```dart
onTapUp: (d) => _toggleZoom(d.localPosition + Offset(dx, dy)),
onSecondaryTapDown: (d) => unawaited(_showContextMenu(d.globalPosition)),
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`
Expected: copy/save menu 群 PASS（含 Task 3 的結構測試斷言 onSecondaryTapDown != null）。

- [ ] **Step 6: analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "feat(lightbox): right-click copy/save menu via shared service"
```

---

## Task 5: 右上角按鈕列 `[⋮][🔍][✕]`

**Files:**
- Modify: `lib/widgets/dialogs/zoomable_image_overlay.dart`
- Test: `test/widgets/dialogs/zoomable_image_overlay_test.dart`

- [ ] **Step 1: 新增按鈕列測試**

新增測試群：

```dart
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
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart -n "button row"`
Expected: FAIL（目前只有單顆 X）。

- [ ] **Step 3: 新增圓鈕包裝 helper**

在 `_ZoomableImageOverlayState` 加：

```dart
/// 半透明黑底圓鈕包裝；右上角三顆按鈕共用，沿用既有 lightbox 視覺。
Widget _circleButton(Widget child) => Material(
  color: Colors.black.withValues(alpha: 0.4),
  shape: const CircleBorder(),
  child: child,
);
```

- [ ] **Step 4: 把單顆 X 的 Positioned 換成三顆 Row**

把 build 內現有的 `Positioned(top:16,right:16, child: Material(... close IconButton ...))` 整段換成：

```dart
Positioned(
  top: 16,
  right: 16,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _circleButton(
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: '',
            onSelected: _onMenuSelected,
            itemBuilder: (_) => _menuItems(l),
          ),
        ),
      ),
      const SizedBox(width: 8),
      _circleButton(
        IconButton(
          tooltip: _zoomed ? l.actionZoomOut : l.actionZoomIn,
          icon: Icon(
            _zoomed ? Icons.zoom_out : Icons.zoom_in,
            color: Colors.white,
          ),
          onPressed: () =>
              _toggleZoom(_viewportSize?.center(Offset.zero) ?? Offset.zero),
        ),
      ),
      const SizedBox(width: 8),
      _circleButton(
        IconButton(
          tooltip: l.actionCloseImagePreview,
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => _close('button'),
        ),
      ),
    ],
  ),
),
```

> `l` 已是 build 開頭 `final l = AppLocalizations.of(context)!;`，可直接用。

- [ ] **Step 5: 跑全檔測試**

Run: `fvm flutter test test/widgets/dialogs/zoomable_image_overlay_test.dart`
Expected: 全部 PASS（含 X 仍由 tooltip 找得到、按鈕列三顆、zoom 按鈕切 icon＋scale、⋮ 開選單）。

- [ ] **Step 6: analyze**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/dialogs/zoomable_image_overlay.dart test/widgets/dialogs/zoomable_image_overlay_test.dart
git commit -m "feat(lightbox): top-right [more][zoom][close] button row"
```

---

## Task 6: 全域品質閘 + 手動驗證提示

**Files:** （無新增）

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 格式化完成（勿對 `.` 跑）。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 若 format 有改動則補 commit**

```bash
git add -A
git commit -m "style(lightbox): apply dart format" || echo "nothing to format"
```

- [ ] **Step 5: 手動驗證清單（在真實 app 上 — 需 Windows + Rust toolchain）**

於 item detail dialog 點開圖片後確認：
1. 游標停在圖片上顯示放大鏡（fit 時 zoomIn、放大後 zoomOut）。
2. 單擊圖片即 fit↔2x 切換；滾輪仍可連續縮放；拖曳可平移。
3. 點圖片以外暗區 / ESC / X 皆可關閉；點圖片不關閉。
4. 右上角 `[⋮][🔍][✕]` 三顆；🔍 與單擊行為一致且 icon 隨狀態切換。
5. 右鍵圖片與 ⋮ 都叫出「複製圖片 / 儲存圖片」；複製後到 Discord 貼上、儲存可選路徑。
6. 複製／儲存的 toast 顯示在 lightbox 黑幕**之上**（不被蓋住）。
7. 切其他語系（如日文／簡中）確認 zoom tooltip 與 copy/save 字串有翻譯。

---

## Self-Review

**Spec coverage：**
- 單擊縮放（非雙擊）→ Task 3。
- 游標隨狀態 zoomIn/zoomOut → Task 3。
- 右鍵 copy/save 選單 → Task 4。
- 右上 `[⋮][🔍][✕]` 按鈕列 + zoom 鈕 → Task 5。
- copy/save 重用既有 service + `showDialogToast` 不被黑幕蓋 → Task 4（+ 手動驗證 Task 6）。
- suggestedBaseName 串接 → Task 2。
- l10n `actionZoomIn/Out` + 7 檔補齊舊缺 key → Task 1。
- 「和 wuthering 一樣」= 以本 repo 為基準的這套設計（spec 已記）。

**Placeholder scan：** 無 TBD／TODO；所有 code step 皆附完整程式碼與字串值。

**Type consistency：** `_zoomedScale`（取代 `_doubleTapScale`）、`_zoomed`、`_viewportSize`、`_syncZoomed`、`_toggleZoom(Offset)`、`_menuItems(AppLocalizations)`、`_onMenuSelected(String)`、`_copy()`、`_save()`、`_showContextMenu(Offset)`、`_circleButton(Widget)`、`showZoomableImageOverlay(..., required String suggestedBaseName)` 全程一致。
