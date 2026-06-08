# 物品詳細圖片選單（複製／儲存／重抓 + 右鍵）設計

> 日期：2026-06-08
> 對照來源：`GoneTone/wuthering-waves-convene-gacha-analyzer`（同作者姊妹專案）的同名功能，做法一致。

## 目標

在 `GachaItemDetailDialog`（物品詳細 dialog）中央 gallery 圖片的右上角新增一個浮動溢出選單，選單提供三項操作：

1. **複製圖片** — 把目前顯示的圖片複製到系統剪貼簿（PNG）。
2. **儲存圖片** — 開啟系統存檔對話框，把目前圖片存成 PNG。
3. **重抓圖片** — 重新下載目前 chip 對應的圖片並覆寫快取。

同一份選單也要能透過**在圖片上按滑鼠右鍵**叫出（位置跟著游標）。

操作結果以 SnackBar 回報（複製成功／失敗、存檔成功顯示路徑／失敗；使用者取消存檔不提示）。

## 非目標（YAGNI）

- 不做批次匯出／全部圖片一次存檔（既有設定頁已有「強制重抓所有物品圖片」涵蓋全域重抓）。
- 不在 lightbox（`ZoomableImageOverlay`）內加選單；本次只動物品詳細 dialog 的圖片區。
- 不新增「複製圖片網址」「分享」等本次未要求的選項。
- 不為「未來可能的其他圖片來源」預先抽象 chip 類別以外的擴充點。

## 現況脈絡

- 物品詳細 dialog：`lib/widgets/dialogs/gacha_item_detail_dialog.dart`。中央圖片由 `_buildCurrentImageArea` 依 `_GalleryLoadState`（`_GalleryReady` / `_GalleryLoading` / `_GalleryFailed`）繪製；ready 時是單一可點開縮放的 `Image.file`。
- chip 類別 `_ChipKind`：`galleryList`、`galleryPic`、`icon`。gallery 圖走 lazy 下載（`_fetchAndCache`，一律重新下載並覆寫，無磁碟短路）；icon 由更新流程預抓、開 dialog 時永遠 `_GalleryReady`。
- 既有圖片寫檔：`writeHoYoWikiCacheImage(file:, bytes:)`；下載：`hoyowikiFetcherProvider` 的 `downloadImage(url, client)`。
- icon 同步機制：`GachaItemIcon` 與 dialog 標題縮圖都 `watch(hoyowikiIndexProvider)`；`HoYoWikiIndexNotifier.bumpCacheRevision()` 換 state identity 觸發重 build 以挑到新檔。快取用量由 `hoyowikiCacheUsageProvider` 提供，重抓後 `ref.invalidate` 之。
- 剪貼簿／存檔 primitive 已存在於 `lib/services/share_image_export.dart`，但其對外 API（`exportShareImage`）是「複製＋存檔合併成單一流程」，與本次需要的「分開複製／分開存檔／圖檔轉 PNG」不同。專案有 `super_clipboard`、`file_selector` 相依。
- SnackBar：全專案以 `ScaffoldMessenger.of(context)` 顯示；MaterialApp 提供 root ScaffoldMessenger，dialog context 內以 `ScaffoldMessenger.maybeOf(context)` 可取得。

## 架構決策

### 程式碼組織：抽共用低階層，再各自包裝

避免與 `share_image_export.dart` 重複造輪子（CLAUDE.md「嚴禁重複造輪子」）：把剪貼簿寫入、存檔位置選擇器、檔案寫入這三個原始操作抽到共用模組，`share_image_export` 與新的 item-image 流程都複用同一份 seam。

## 元件設計

### 1. 共用低階層 — 新增 `lib/services/image_clipboard_save.dart`

Logger：`Logger('gacha.hoyowiki.save')`。

可測 seam（`@visibleForTesting` 可覆寫的 function 指標）與預設實作：

| 成員 | 型別 / 預設 | 作用 |
|---|---|---|
| `imageClipboardWriter` | `Future<bool> Function(Uint8List png)` | 預設：`SystemClipboard.instance` 為 null 回 false；否則 `DataWriterItem` 加 `Formats.png(png)` 寫入回 true |
| `imageSaveLocationPicker` | `Future<FileSaveLocation?> Function(String suggestedName)` | 預設：`getSaveLocation` 帶 `XTypeGroup(label:'PNG', extensions:['png'])` |
| `imageFileWriter` | `Future<void> Function(String path, Uint8List png)` | 預設：`File(path).writeAsBytes(png)` |
| `resetImageClipboardSaveSeams()` | `void` | 把三個 seam 重設為預設（供 tearDown） |

公開函式：

- `Future<Uint8List?> encodeImageFileToPng(File file)`
  讀檔 → `ui.instantiateImageCodec` → `getNextFrame` → `toByteData(format: png)` → dispose frame。任何失敗（讀檔／解碼／編碼）記 warning（脫敏路徑）後回 null。統一輸出 PNG，因為來源 icon／gallery 副檔名隨 URL 可能是 webp／jpg。

- `Future<bool> copyImagePngToClipboard(Uint8List png)`
  呼叫 `imageClipboardWriter`，info log 結果與 bytes 數；例外記 warning 後回 false。

- `Future<String?> saveImagePng(Uint8List png, {required String suggestedName})`
  呼叫 `imageSaveLocationPicker`；null（取消）→ info log 後回 null。否則 `imageFileWriter` 寫入；寫入失敗記 severe log（脫敏路徑）後 rethrow。成功 info log 後回**實際存檔路徑**。

### 2. 重構 `lib/services/share_image_export.dart`

- 移除自身的 `_defaultClipboardWriter` / `_defaultSaveLocationPicker` / `_defaultFileWriter` 及 `shareClipboardWriter` / `shareSaveLocationPicker` / `shareFileWriter` 三個 seam。
- `exportShareImage` 改為呼叫共用層的 `imageClipboardWriter` / `imageSaveLocationPicker` / `imageFileWriter`。**對外行為、回傳型別（`ShareExportResult` / `ShareExportStatus`）皆不變**。
- `resetShareImageExportSeams()` 改為轉呼 `resetImageClipboardSaveSeams()`（保留函式名供既有測試呼叫）。
- 連帶更新 `test/services/share_image_export_test.dart`：把覆寫的 seam 名稱由 `shareSaveLocationPicker` / `shareClipboardWriter` 換成共用層的 `imageSaveLocationPicker` / `imageClipboardWriter`。

### 3. 改造 `lib/widgets/dialogs/gacha_item_detail_dialog.dart`

`_buildCurrentImageArea` 的 `_GalleryReady` 分支由單一 `Image.file` 改為 `Stack`：

- **底層** `Positioned.fill`：保留現有 `MouseRegion(cursor: click)` + `GestureDetector`（`onTap` 開 `showZoomableImageOverlay`），**新增** `onSecondaryTapDown: (d) => _showImageContextMenu(context, d.globalPosition, current)`。`Image.file` 設定（`ValueKey(file.path)`、`gaplessPlayback`、`errorBuilder`）維持不變。
- **疊層** `Positioned(top: AppSpacing.s, right: AppSpacing.s, child: _buildImageMenu(context, current))`。

新增方法（與 WW 同構）：

- `List<PopupMenuEntry<String>> _imageMenuItems(AppLocalizations l)`
  三項 `PopupMenuItem`（value `copy` / `save` / `refetch`），各為 `ListTile(dense, contentPadding: zero, leading: Icon(size:20), title: Text(...))`；`copy`（`Icons.copy`）與 `save`（`Icons.save_alt`）之後接 `PopupMenuDivider()`，再 `refetch`（`Icons.refresh`）。
- `void _onImageMenuSelected(String value, _GalleryChipEntry current)`
  `switch`：`copy` → `unawaited(_copyImage(current))`；`save` → `unawaited(_saveImage(current))`；`refetch` → `_refetchEntry(current)`。
- `Widget _buildImageMenu(BuildContext, _GalleryChipEntry current)`
  `Material(color: Colors.black.withValues(alpha:0.4), shape: CircleBorder())` 包 `PopupMenuButton<String>(icon: Icon(Icons.more_vert, color: white), tooltip: '', onSelected: ..., itemBuilder: (_) => _imageMenuItems(l))`。沿用 lightbox X 鈕視覺。
- `Future<void> _showImageContextMenu(BuildContext, Offset globalPosition, _GalleryChipEntry current)`
  以 `Overlay.of(context)` 的 RenderBox 算 `RelativeRect.fromRect(globalPosition & Size.zero, Offset.zero & overlay.size)`，`showMenu` 顯示 `_imageMenuItems`；選取後（非 null 且 mounted）`_onImageMenuSelected`。
- `String _suggestedFileName(_GalleryChipEntry e)`
  `'${record.name}_${e.label}'` 把 Windows 非法字元 `[<>:"/\\|?*]` 換成 `_`，加 `.png`。
- `Future<void> _copyImage(_GalleryChipEntry e)`
  `encodeImageFileToPng(e.file)` → null 則 SnackBar `imageCopyFailed`；否則 `copyImagePngToClipboard` → SnackBar `imageCopied`／`imageCopyFailed`。各 await 後檢查 `mounted`。
- `Future<void> _saveImage(_GalleryChipEntry e)`
  `encodeImageFileToPng` → null 則 `imageSaveFailed`；否則 `try { saveImagePng(png, suggestedName: _suggestedFileName(e)) }`，回傳 path 非 null 且 mounted → SnackBar `imageSavedTo(path)`；取消（null）不提示；catch → `imageSaveFailed`。
- `void _refetchEntry(_GalleryChipEntry e)`
  `PaintingBinding.instance.imageCache.evict(FileImage(e.file))` → `_precachedPaths.remove(e.file.path)` → `setState(() => _loadStates[e.file.path] = const _GalleryLoading())`，再依 `e.kind`：
  - `galleryList` / `galleryPic` → `unawaited(_fetchAndCache(id: <id>, url: e.url, file: e.file))`（既有方法，一律重新下載覆寫）。`id` 由 `_extractIdFromPath(e.file.path)` 取得（與既有 retry 路徑一致）。
  - `icon` → `unawaited(_refetchIcon(url: e.url, file: e.file))`。
- `Future<void> _refetchIcon({required String url, required File file})`
  `hoyowikiFetcherProvider.downloadImage(url, _client)` → null 則 setState `_GalleryFailed` + warning；否則 `writeHoYoWikiCacheImage(file:, bytes:)` 覆寫 → `imageCache.evict(FileImage(file))` → setState `_GalleryReady(file)` → `ref.read(hoyowikiIndexProvider.notifier).bumpCacheRevision()` → `ref.invalidate(hoyowikiCacheUsageProvider)` → info log。讓標題縮圖與記錄列表 `GachaItemIcon` 同步顯示新 icon。失敗保留磁碟既有 icon（`writeHoYoWikiCacheImage` 失敗不覆寫）。
- `void _showSnack(String message)`
  `ScaffoldMessenger.maybeOf(context)?..clearSnackBars()..showSnackBar(SnackBar(content: Text(message)))`。

**DRY**：`_GalleryFailed` 分支現有「重試」按鈕的 `onPressed` 改呼叫 `_refetchEntry(current)`（與選單「重抓」共用同一條路徑），取代原本內聯的 `_retry(...)`。原 `_retry` 若無其他呼叫端則移除。

選單與右鍵僅在 `_GalleryReady` 疊出；loading／failed 狀態維持原樣（failed 仍有重試按鈕）。

### 4. i18n（`lib/l10n/app_zh.arb` 起手，只加已有實體翻譯的 ARB）

新增鍵（繁中值）：

| key | zh 值 | 備註 |
|---|---|---|
| `actionCopyImage` | 複製圖片 | 選單標籤 |
| `actionSaveImage` | 儲存圖片 | 選單標籤 |
| `actionRefetchImage` | 重抓圖片 | 選單標籤 |
| `imageCopied` | 圖片已複製到剪貼簿 | SnackBar |
| `imageCopyFailed` | 複製圖片失敗 | SnackBar |
| `imageSaveFailed` | 儲存圖片失敗 | SnackBar |
| `imageSavedTo` | 已儲存至 {path} | SnackBar，`path` placeholder（type String）|

先寫 `app_zh.arb`，再以中文為基準翻已有實體翻譯的語系；空殼 ARB 留給 Crowdin pipeline。`gen-l10n` 重新產生。

## 資料流

```
使用者點右上角選單鈕 / 右鍵圖片
  → _imageMenuItems 顯示（PopupMenuButton / showMenu）
  → _onImageMenuSelected(value, current)
      copy   → encodeImageFileToPng → copyImagePngToClipboard(imageClipboardWriter) → SnackBar
      save   → encodeImageFileToPng → saveImagePng(imageSaveLocationPicker→imageFileWriter) → SnackBar
      refetch→ evict + loading → _fetchAndCache（gallery） / _refetchIcon（icon, +bumpCacheRevision）
```

## 錯誤處理

- 編碼失敗（壞檔／解碼失敗）：`encodeImageFileToPng` 回 null → 複製／儲存皆 SnackBar 失敗訊息。
- 剪貼簿平台不支援：`copyImagePngToClipboard` 回 false → SnackBar 失敗。
- 存檔使用者取消：`saveImagePng` 回 null → 不提示（非錯誤）。
- 存檔寫入失敗：`saveImagePng` rethrow → `_saveImage` catch → SnackBar 失敗。
- 重抓下載失敗：setState `_GalleryFailed`（沿用既有失敗 UI 的重試按鈕）；icon 重抓失敗保留磁碟舊 icon。
- 所有 I/O／下載節點都帶 context（id、bytes、脫敏 URL／路徑）寫 log（對齊 `gacha.hoyowiki.*` 樹）。

## 測試

- **新增** `test/services/image_clipboard_save_test.dart`：
  - `encodeImageFileToPng`：真實 PNG 檔 → 非 null；不存在／壞檔 → null。
  - `copyImagePngToClipboard`：seam 回 true / false / throw 三情境。
  - `saveImagePng`：選路徑寫檔成功（驗檔內容）/ 取消 → null / 寫入失敗 → rethrow。tearDown `resetImageClipboardSaveSeams`。
- **更新** `test/services/share_image_export_test.dart`：seam 名稱改用共用層。
- **擴充** `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`：
  - ready 圖片上存在選單鈕（`Icons.more_vert`）。
  - 點選單「複製」「儲存」分別觸發 `imageClipboardWriter` / `imageSaveLocationPicker` seam。
  - 右鍵（`onSecondaryTapDown`）能叫出選單。
  - 「重抓」走 fetcher（以既有測試的 fetcher 注入方式）並回到 ready。

## 驗收條件

1. `fvm dart format lib/ test/`
2. `fvm flutter analyze` → `No issues found!`
3. `fvm flutter test` → `All tests passed!`
