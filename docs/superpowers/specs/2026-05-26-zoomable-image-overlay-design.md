# Zoomable Image Overlay — Design Spec

- **Date**: 2026-05-26
- **Branch**: feat/hoyowiki-item-detail
- **Status**: Approved, ready for plan

## 背景與目標

`GachaItemDetailDialog`（`lib/widgets/dialogs/gacha_item_detail_dialog.dart`）已能顯示 HoYoWiki 來的物品資訊與一張可切 chip 的 gallery 主圖。但目前主圖受 dialog 最大高度（880px）限制，使用者想看角色立繪/卡片/Icon 的細節時無法放大。

本 spec 為「點頁籤的圖片 → 開啟 lightbox 全螢幕檢視器，可拖曳平移、滑鼠滾輪縮放、雙擊 fit↔2x 切換、ESC/點背景/X 關閉」設計實作方案。

## 範圍

**在範圍內**：
- 在 `GachaItemDetailDialog` 內，使用者選擇任一 chip 後顯示的 gallery 主圖（`currentFile`）成為可點 tap target，點擊開啟全螢幕 lightbox 檢視該圖
- 涵蓋所有 chip 來源：`gallery.list` 各項、`gallery.picUrl`（galleryCard）、icon chip
- Lightbox 支援：滑鼠滾輪以游標為中心縮放、拖曳平移、雙擊 fit↔2x、ESC / 點背景 / X 按鈕關閉

**不在範圍內**：
- `GachaItemDetailDialog` title 左上角的 64×64 icon（非 chip 元素）
- 多圖左右切換（lightbox 只負責單張圖；切 chip 仍走 detail dialog）
- 分享卡 / 其他頁面的圖片放大（未來如需可重用 `ZoomableImageOverlay`）

## 架構

**新檔**：`lib/widgets/dialogs/zoomable_image_overlay.dart`
- 公開 widget `ZoomableImageOverlay`、helper `showZoomableImageOverlay(BuildContext, {required File imageFile})`
- 自包含、不依賴特定 caller，便於未來其他畫面重用

**修改**：`lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- 將 line 291–313 的 `Image.file(currentFile, ...)` 包進 `MouseRegion(cursor: zoomIn) + GestureDetector(onTap)`，onTap 呼叫 `showZoomableImageOverlay(...)`
- 既有 `Expanded` / `ClipRRect` / `gaplessPlayback` / `errorBuilder` / `key: ValueKey(currentFile.path)` 行為全部保留

**i18n**：新增 1 個 key `actionCloseImagePreview`，從 `app_zh.arb` 起手再翻其他已有實體翻譯的 ARB

### 不走 AppDialog 的設計例外

專案規則「Dialog 一律用 `AppDialog`」（CLAUDE.md）原則上適用所有 dialog。本 lightbox 是**有意識的例外**：

- `AppDialog` 內部是 `AlertDialog`（白底、圓角、`title`/`content`/`actions` 三 slot、inset padding）
- 沉浸式 lightbox 需求 = 透明黑底、滿框、單一圖層、無 actions bar
- 兩種語意交集薄，硬包反而破壞 `AppDialog` 抽象本身的清晰度

Lightbox 改走：

```dart
showDialog<void>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.92),
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.zero,
    child: ZoomableImageOverlay(imageFile: imageFile),
  ),
);
```

## `ZoomableImageOverlay` 內部結構

**對外 API**

```dart
Future<void> showZoomableImageOverlay(
  BuildContext context, {
  required File imageFile,
});

class ZoomableImageOverlay extends StatefulWidget {
  const ZoomableImageOverlay({super.key, required this.imageFile});
  final File imageFile;
}
```

**Widget tree**

```
Focus(autofocus: true)
  Shortcuts(ESC → DismissIntent)
    Actions(DismissIntent → Navigator.pop)
      Stack
        ├─ Positioned.fill: GestureDetector(opaque, onTap: pop)  // backdrop
        ├─ Center
        │     Listener(onPointerSignal: wheel handler)
        │       GestureDetector(onDoubleTapDown: double-tap handler)
        │         InteractiveViewer(
        │           transformationController: _ctrl,
        │           panEnabled: true,
        │           scaleEnabled: false,        // 自管 scale
        │           minScale: 1.0, maxScale: 5.0,
        │         )
        │           Image.file(file, fit: BoxFit.contain, errorBuilder: ...)
        └─ Positioned(top: 16, right: 16): IconButton(close, tooltip: ...)
```

### 為什麼 `scaleEnabled: false`

InteractiveViewer 內建縮放走 pinch（雙指中心），桌面用不到；我們要 cursor-centered 滾輪縮放，邏輯比內建的雙指中心精準可控。停用內建縮放、只用 `InteractiveViewer` 處理 pan + Matrix4 容器，避免兩套縮放 source 打架。

### Scale 參數

```dart
static const double _minScale = 1.0;       // fit
static const double _maxScale = 5.0;
static const double _doubleTapScale = 2.0;
static const double _wheelStep = 1.1;      // 每 notch ×1.1 or ÷1.1
```

### Cursor-centered zoom 數學

關鍵公式：scene point 在縮放前後在螢幕上維持同位置。

```dart
void _zoomAt({required Offset localFocal, required double scaleDelta}) {
  final current = _ctrl.value.getMaxScaleOnAxis();
  final next = (current * scaleDelta).clamp(_minScale, _maxScale);
  final actual = next / current;
  if ((actual - 1).abs() < 1e-6) return;
  _ctrl.value = (Matrix4.identity()
        ..translate(localFocal.dx, localFocal.dy)
        ..scale(actual)
        ..translate(-localFocal.dx, -localFocal.dy))
      * _ctrl.value;
}
```

- Wheel：`scrollDelta.dy < 0` → `_zoomAt(localFocal: event.localPosition, scaleDelta: _wheelStep)`；`> 0` → `1 / _wheelStep`
- Double-tap：當前 ≈ `_minScale` → 放大到 `_doubleTapScale`；否則回 `_minScale`

## `GachaItemDetailDialog` 整合

把 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` line 291–313 改寫：

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
                e, st,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  ),
```

### 設計選擇

1. **`GestureDetector` 而非 `InkWell`**：圖片預覽不要 Material ripple 蓋在 game art 上。Memory `feedback_inkwell_explicit_mouse_cursor` 是針對 InkWell 用法的規範，這裡走 `GestureDetector + MouseRegion` 等效但更乾淨。
2. **`SystemMouseCursors.zoomIn`**：明確告知 hover 行為（IG / HoYoLab Wiki 本家也是 zoom-in cursor）。
3. **`Expanded` 在外、`ClipRRect` 在內**：保 layout 不變、tap region 對齊 ClipRRect 範圍。
4. **不抽 `hasZoomableImageContent`**：能進 detail dialog 就一定有 `currentFile`，YAGNI。

## i18n / a11y / logging

### i18n

新增 1 個 ARB key：

```json
"actionCloseImagePreview": "關閉圖片預覽",
"@actionCloseImagePreview": {
  "description": "Tooltip and semantic label for the close button on the zoomable image overlay."
}
```

- 從 `app_zh.arb` 起手（per memory `feedback_i18n_starts_from_zh`）
- 只加在已有實體翻譯的 ARB（per memory `feedback_i18n_skip_empty_arbs`），空殼留給 Crowdin pipeline

### a11y

- Gallery image tap target：`MouseRegion(cursor: zoomIn)` 已給視覺提示；不加 Tooltip（hover tooltip 在大圖瀏覽時干擾）
- Overlay X 按鈕：`IconButton(tooltip: l.actionCloseImagePreview)`，tooltip 同時擔任 semantic label
- ESC 關閉：`Focus(autofocus: true)` 確保 overlay 開啟即拿到焦點

### Logging

Logger 命名沿用既有 `gacha.hoyowiki.*` 樹：

| Logger | Level | When |
|---|---|---|
| `gacha.hoyowiki.detail` | info | `open zoom id=$id path=...`（detail dialog 觸發開啟） |
| `gacha.hoyowiki.zoom` | info | `overlay open file=...`（initState） |
| `gacha.hoyowiki.zoom` | info | `overlay close reason=esc\|backdrop\|button`（關閉時帶來源） |
| `gacha.hoyowiki.zoom` | warning | `image errorBuilder file=...`（Image.file 失敗） |

不 log wheel / double-tap / pan 細節（噪音大、無 debug 價值）。

## 測試計畫

### `test/widgets/dialogs/zoomable_image_overlay_test.dart`（新檔）

```dart
group('ZoomableImageOverlay', () {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zoom_test_');
    imageFile = File('${tempDir.path}/test.png')
      ..writeAsBytesSync(<bytes of a 1x1 valid PNG>);
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('open / ESC close', ...);
  testWidgets('tap backdrop close', ...);
  testWidgets('tap X button close', ...);
  testWidgets('double-tap toggles 1x ↔ 2x (assert controller scale)', ...);
  testWidgets('wheel zooms in/out (dispatch PointerScrollEvent, assert scale)', ...);
  testWidgets('scale clamps at _minScale / _maxScale', ...);
});
```

`tearDown` 內清 ImageCache 是必要的 — per memory `project_image_cache_cross_test_race`，testWidgets 用 tempDir 圖檔時不清會在 Linux CI 出 codec race。

### `test/widgets/dialogs/gacha_item_detail_dialog_zoom_test.dart`（新檔）

```dart
testWidgets('tap gallery main image opens ZoomableImageOverlay', ...);
testWidgets('switching chip then tapping opens overlay with new chip\'s file', ...);
```

走 `ProviderScope.overrides` 覆寫 `hoyowikiIndexProvider` + `hoyowikiCacheDirProvider` 餵假資料；驗證點 → overlay 出現 + 帶到的 File 對應預期。

### 既有測試衝擊

`gacha_item_detail_dialog_test.dart`（若存在）大概率不需改 — 主圖仍正常渲染，多包一層 `MouseRegion + GestureDetector` 不影響既有 find/expect。但 `flutter test` 跑全套時要確認無回歸。

### Wheel event 模擬

```dart
await tester.sendEventToBinding(PointerScrollEvent(
  position: viewerCenter,
  localPosition: viewerCenter,
  scrollDelta: const Offset(0, -100),  // 向上一格 = 放大
));
```

### Manual checklist

按 CLAUDE.md「UI 要實際測」+ memory `feedback_perf_check_release_first`：

- `flutter run --release` 進 app
- 開一張 5★ 角色 detail dialog → 點立繪 chip → 點主圖
- 驗證：
  - 滾輪以游標位置為中心放大、放大後拖曳平移有效
  - 雙擊在 fit / 2x 來回切換
  - ESC、點黑底、按 X 都能關閉
  - GIF 圖在 lightbox 下仍會動

## 提交前檢查

按 CLAUDE.md：
1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
3. `flutter test` → 必須 `All tests passed!`

## 檔案改動總表

| 檔案 | 改動類型 |
|---|---|
| `lib/widgets/dialogs/zoomable_image_overlay.dart` | 新增 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | 修改（line 291–313 包 tap target） |
| `lib/l10n/app_zh.arb` 等已翻譯 ARB | 新增 `actionCloseImagePreview` key |
| `test/widgets/dialogs/zoomable_image_overlay_test.dart` | 新增 |
| `test/widgets/dialogs/gacha_item_detail_dialog_zoom_test.dart` | 新增 |
