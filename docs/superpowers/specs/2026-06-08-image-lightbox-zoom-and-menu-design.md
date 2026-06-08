# 圖片 lightbox 互動升級

## 背景與目標

目前 `ZoomableImageOverlay`（`lib/widgets/dialogs/zoomable_image_overlay.dart`）的全螢幕圖片檢視器互動為：

- 單擊圖片像素區 → 空吸收（不做事，避免誤關）。
- 雙擊圖片 → fit ↔ 2x 縮放切換。
- 單擊暗區／backdrop → 關閉。
- 滾輪 → 以游標為中心縮放；拖曳 → InteractiveViewer pan；ESC／右上角 X → 關閉。

要把互動體驗改成像常見圖片檢視器（單擊縮放、右上角按鈕、右鍵選單）那樣，並補上圖片操作選單：

1. **單擊**（非雙擊）即可在 fit ↔ 2x 之間切換縮放。
2. 滑鼠游標停在圖片上時，依當前縮放狀態顯示 `zoomIn` 或 `zoomOut` 鼠標。
3. 開啟的圖片可**右鍵**叫出選單，只放「複製圖片 / 儲存圖片」。
4. 右上角按鈕列除了原本的 X，再加一顆 more_vert 與一顆縮放鈕，變成 `[ ⋮ ] [ 🔍 ] [ ✕ ]`。
5. 從 lightbox 觸發 copy/save 的提示（toast）不可被 lightbox 黑幕蓋住。

設計與姊妹專案 `wuthering-waves-convene-gacha-analyzer` 收斂到同一套，以本 repo 為基準先實作。

## 範圍

- 主檔：`lib/widgets/dialogs/zoomable_image_overlay.dart`（互動改寫 + 按鈕列 + 選單 + copy/save）。
- 呼叫端：`lib/widgets/dialogs/gacha_item_detail_dialog.dart`，於開啟 lightbox 時補傳建議檔名。
- l10n：新增縮放鈕 tooltip 字串。
- 測試：`test/widgets/dialogs/zoomable_image_overlay_test.dart` 更新與擴充。

不在範圍內：dialog 內小預覽的 more_vert 選單（維持現有 copy/save/refetch 不動）。

## 互動模型

維持現有雙層 `GestureDetector` 結構（外層蓋整個 padding 暗區、內層僅蓋 `BoxFit.contain` 後的 painted rect），改變內層的手勢職責：

| 動作 | 現在 | 改成 |
|---|---|---|
| 單擊圖片像素區 | 空吸收 | **fit ↔ 2x 切換**（以點擊落點為焦點） |
| 雙擊圖片 | fit ↔ 2x | 移除 |
| 單擊暗區 / backdrop | 關閉 | 關閉（不變） |
| 滾輪 | 以游標為中心縮放 | 保留 |
| 拖曳 | InteractiveViewer pan | 保留 |
| ESC / X | 關閉 | 保留 |

- 內層 `GestureDetector` 由「`onTap: () {}` 空吸收 + `onDoubleTapDown: _onDoubleTapDown`」改為「`onTap: _toggleZoomAtCenterOrFocal`」。沿用既有 `_zoomAt(...)`、`_doubleTapScale = 2.0`、`_minScale`／`_maxScale`、回 fit 時強制 `Matrix4.identity()` 的邏輯。
- 移除雙擊後，外層 backdrop 的 `onTap`（關閉）不再與 `DoubleTapGestureRecognizer` 在同一 arena 競技，單擊關閉維持即時。
- 圖片像素區不再單擊關閉：點圖＝縮放、點暗區＝關閉，對應常見圖片檢視器的習慣。放大且圖片填滿時，以 X／ESC／縮放鈕回 fit。
- pan 與 tap 競技由 GestureDetector arbitration 處理：移動 > slop → pan 贏；無移動 → tap fire（單擊縮放）。

### 游標狀態

圖片像素區外包一層 `MouseRegion`，`cursor` 依當前 scale 決定：

- 接近 fit（`scale - _minScale` 在容差內）→ `SystemMouseCursors.zoomIn`。
- 已放大 → `SystemMouseCursors.zoomOut`。

scale 改變（單擊、滾輪、回 fit）時 `setState` 觸發 rebuild 讓游標與縮放鈕 icon 同步。為此，state 需在 `_zoomAt` 變更矩陣後反映目前 scale（可於縮放後讀 `_ctrl.value.getMaxScaleOnAxis()` 推導，或以一個 `bool _zoomed` 衍生狀態於每次縮放後更新並 `setState`）。

## 右上角按鈕列：`[ ⋮ ] [ 🔍 ] [ ✕ ]`

把現有單顆 X 圓鈕換成一列三顆半透明黑底圓鈕（沿用現有 `Material(color: Colors.black.withValues(alpha: 0.4), shape: CircleBorder())` + 白色 icon 視覺），以 `Row(mainAxisSize: MainAxisSize.min)` 排列：

- **⋮ more_vert**：`PopupMenuButton<String>`，選單項目＝複製圖片 / 儲存圖片（**無「重抓」**——重抓需 chip／url 等 dialog 端 context，lightbox 拿不到，且需求只要 copy/save）。
- **🔍 縮放**：`IconButton`，icon 依 state 切 `Icons.zoom_in` / `Icons.zoom_out`，tooltip 對應 `actionZoomIn` / `actionZoomOut`；按下＝與單擊圖片相同的 fit ↔ 2x 切換（以圖片中心為焦點，使用 viewer 中心點呼叫 `_zoomAt`）。
- **✕ close**：維持現有 `_close('button')`，tooltip `actionCloseImagePreview`。

## 右鍵選單

圖片像素區的 `GestureDetector` 加 `onSecondaryTapDown`，以 `showMenu<String>`（位置跟游標，沿用 `gacha_item_detail_dialog._showImageContextMenu` 的 `RelativeRect` 寫法）顯示與 ⋮ 相同的 copy/save 選單。

## copy / save 串接（重用既有 service）

- 複製 → `copyImageFileToClipboard(widget.imageFile)`（只需 `File`，GIF 保留動畫、其餘轉 PNG，已實作於 `services/image_clipboard_save.dart`）。
- 儲存 → `saveImageFile(widget.imageFile, suggestedBaseName: widget.suggestedBaseName)`。
- `showZoomableImageOverlay` 與 `ZoomableImageOverlay` 新增 `required String suggestedBaseName`；呼叫端（`gacha_item_detail_dialog`）開 lightbox 時傳入既有 `_suggestedBaseName(current)`（`角色名_標籤`，已去非法字元）。
- 選單分派與結果回報集中在 overlay 內的小 helper（例如 `_onMenuSelected(String)` → `_copy()` / `_save()`），與 dialog 端對應方法行為一致但不共用其 `PopupMenu` builder（dialog 版與 `_GalleryChipEntry`／refetch 耦合過深，硬抽反而髒；真正共用的底層 service 已共用，符合 YAGNI）。
- 結果以 `showDialogToast(context, ...)` 回報：它插到 `Overlay.of(context)`（navigator overlay），疊在 lightbox route **之上**，因此 toast 天生在 lightbox 黑幕之上 —— 即「lightbox 不要蓋住 SnackBar」的解法；訊息沿用既有 `imageCopied` / `imageCopyFailed` / `imageSavedTo(path)` / `imageSaveFailed`。

## l10n

- 新增 `actionZoomIn` / `actionZoomOut`（縮放鈕 tooltip）。
- copy/save 相關字串（`actionCopyImage`、`actionSaveImage`、`imageCopied`、`imageCopyFailed`、`imageSavedTo`、`imageSaveFailed`）已存在，重用。
- 從 `app_zh.arb` 起手，再以中文為基準補已有實體翻譯的 ARB（空殼留給 Crowdin pipeline）；跑 `fvm flutter gen-l10n`。

## 記錄（Logger）

沿用既有 `Logger('gacha.hoyowiki.zoom')`：

- 縮放切換：`info('zoom toggle scale=...')`（節制，避免每次滾輪刷屏 —— 滾輪維持現狀不額外 log）。
- copy/save：交給 `image_clipboard_save` 既有 log；overlay 端在開啟選單／按下項目時 `info('menu copy|save')`。
- 關閉 reason 維持 `backdrop | outside-image | button`（`outside-image` 仍對應外層暗區 tap）。

## 測試（`zoomable_image_overlay_test.dart`）

測試需提供新參數 `suggestedBaseName`（helper 補一個固定值）。

- **single-tap zoom toggle**（取代 double-tap group）：單擊 fit→2x、再單擊→fit；off-center 單擊回 fit 後 translation 歸零（沿用既有 identity 斷言）。
- 保留 wheel zoom group、ESC／暗區 tap／X 關閉。
- **按鈕列**：⋮、縮放、X 三顆都在；縮放鈕 icon 隨 state 切 `zoom_in` ↔ `zoom_out`。
- **選單**：⋮ 開出選單含 copy/save；圖片上右鍵叫出相同選單。
- **游標**：圖片像素區 `MouseRegion.cursor` 隨 state 切 `zoomIn` ↔ `zoomOut`。
- **copy/save 行為**：以既有 service seam（`imageClipboardWriter` / `imageSaveLocationPicker` / `imageFileWriter`）mock，驗證點選後呼叫到對應 service、成功／失敗各自顯示對應 toast（`showDialogToast` 出現的訊息）。
- per memory `project_image_cache_cross_test_race`：tearDown 清 ImageCache（既有 test 已做）。

## 提交前品質檢查

1. `fvm dart format lib/ test/`
2. `fvm flutter analyze` → `No issues found!`
3. `fvm flutter test` → `All tests passed!`
