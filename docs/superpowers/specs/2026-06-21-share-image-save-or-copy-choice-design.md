# 分享圖讓使用者選擇「儲存」或「複製」

## 背景與目標

目前點擊分享圖按鈕後，`exportShareImage` 會**先複製到剪貼簿、再跳存檔對話框**，把兩個動作綁在一起執行，使用者無法只做其中一件。本設計改為讓使用者在分享圖設定 dialog 內**明確選擇**要「複製圖片」或「儲存圖片」，對齊姐妹專案 PR（[wuthering-waves-convene-gacha-analyzer#40](https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer/pull/40)）的互動與回饋。

非目標：不更動分享圖的渲染內容、主題／UID 遮罩等既有選項，也不調整剪貼簿／存檔底層的圖片格式處理。

## 互動流程

```
點分享按鈕（ShareActionButton，_busy 鎖定防重入）
  → showShareImageDialog（選主題／完整 UID）
      ├─ 取消        → 結束
      ├─ 複製圖片    → action = copy
      └─ 儲存圖片    → action = save
  → 顯示 ShareProgressDialog（非可關閉，LinearProgressIndicator）
  → 渲染 PNG
  → 關閉 ShareProgressDialog
  → 依 action 執行並回饋（見下表）
```

## 元件設計

### 1. 三按鈕分享 dialog（`lib/widgets/dialogs/share_image_dialog.dart`）

footer 由單一「生成」鈕改為三顆：

- **取消**：`TextButton`，pop `null`。
- **複製圖片**：`TextButton`，pop（options + `ShareImageAction.copy`）。
- **儲存圖片**：`FilledButton`（主要動作），pop（options + `ShareImageAction.save`）。

主題、完整 UID 等選項區塊維持不變。沿用 `AppDialogSize.sm`；三鈕在窄視窗交由 Material `OverflowBar` 自動換行，不需手寫寬度限制。所有按鈕沿用既有樣式（無 `InkWell`，故不涉及顯式 `mouseCursor` 規則）。

### 2. 動作列舉與回傳型別（`lib/models/share_image_options.dart`）

- 新增 `enum ShareImageAction { copy, save }`。
- `ShareImageOptions` 本身不變（`brightness`、`showFullUid`）。
- `showShareImageDialog` 回傳型別由 `Future<ShareImageOptions?>` 改為 record `Future<({ShareImageOptions options, ShareImageAction action})?>`，`null` 代表使用者取消。

### 3. 服務層：直接重用既有方法，刪除組合層

`image_clipboard_save.dart` 已有各自獨立的 `copyImagePngToClipboard(png)` 與 `saveImagePng(png, suggestedName:)`，依「嚴禁重複造輪子」直接使用：

- `generateAndShareImage`（`lib/widgets/share/share_image_helper.dart`）依 `action` 直接呼叫上述兩個方法。
- **刪除** `lib/services/share_image_export.dart`（`exportShareImage` + `ShareExportResult` + `ShareExportStatus`）。
- **刪除** 對應測試 `test/services/share_image_export_test.dart`。
- 移除 helper 內已不需要的 `_shareResultToDialog`。

### 4. 渲染進度 dialog（新增 `lib/widgets/dialogs/share_progress_dialog.dart`）

- 非可關閉（`barrierDismissible: false`），內容為 `LinearProgressIndicator` 加訊息文字（`shareImageGenerating`）。
- **只覆蓋「渲染 PNG」這段**；render 完成（或拋例外）後即以 `Navigator.pop` 關閉，再進入存檔／複製，避免遮住系統存檔對話框。
- `ShareActionButton` 的 `_busy` spinner 仍保留作為按鈕鎖定（防重入），與 progress dialog 各司其職、不衝突。
- helper 須以 `try/finally` 確保 progress dialog 在 render 例外時也會被關閉，再交由外層 `catch` 顯示錯誤 dialog。

### 5. 結果回饋（沿用 `showExportResultDialog`，對齊姐妹 PR）

| 動作 | 結果 | 回饋 |
| --- | --- | --- |
| 複製 | 成功 | 結果 dialog：`shareImageCopiedOnly`（已複製到剪貼簿） |
| 複製 | 失敗 | 結果 dialog：`shareImageCopyFailed`（新增） |
| 儲存 | 成功 | 結果 dialog：`shareImageSaved(path)`，附「開啟資料夾」 |
| 儲存 | 取消（未選路徑） | 靜默，不跳 dialog |
| 渲染等例外 | — | 結果 dialog：`shareImageFailed` |

## 國際化

依專案規則：先寫 `app_zh.arb`，再以中文為基準補**已有實體翻譯**的 ARB；空殼 ARB 留給 Crowdin pipeline，不主動補。省略號一律半形。

- **新增**：
  - `shareImageActionCopy` =「複製圖片」
  - `shareImageActionSave` =「儲存圖片」
  - `shareImageCopyFailed` =「複製到剪貼簿失敗」
  - `shareImageGenerating` =「正在生成分享圖...」（省略號半形）
  - `shareImageSaved` =「已儲存：{path}」（`path` placeholder）
- **移除**：
  - `shareImageGenerate`（被兩顆動作鈕取代）
  - `shareImageSavedAndCopied`（不再同時存檔＋複製）
  - `shareImageSavedOnly`（存檔／複製已拆開，「剪貼簿不支援」語意消失）
- **保留**：`shareImageCopiedOnly`、`shareImageFailed`、`shareImageButton`、`shareImageDialogTitle`、`shareImageThemeLabel`、`shareImageThemeDark`、`shareImageThemeLight`、`shareImageShowFullUid`、`shareImageShowFullUidHint`、`shareImageUpdatedAt`。

儲存相關用詞統一為「儲存」（按鈕「儲存圖片」、訊息「已儲存」），既有「已存檔」用語隨 `shareImageSavedOnly` 一併移除。

## 記錄（log）

沿用 `share.image` 命名空間，於關鍵節點記錄：選定的 `action`、render 成功／失敗、複製成功與否（`clipboard=`）、存檔路徑（經 `sanitizeFsPath`）或取消。內容須帶足夠 context 供匯出 log 後定位問題。

## 測試

- 改 `test/widgets/dialogs/share_image_dialog_test.dart`：驗證三顆按鈕存在、各自 pop 出正確的 `(options, action)`，取消回 `null`。
- 刪 `test/services/share_image_export_test.dart`。
- 新增 helper 動作路由測試：`copy` 走剪貼簿 seam、`save` 走存檔 seam、`save` 取消時靜默不跳結果 dialog、render 例外跳 `shareImageFailed`。
- 新增 progress dialog 測試：render 期間顯示、完成後關閉。
- 利用 `image_clipboard_save.dart` 既有的 `imageClipboardWriter` / `imageSaveLocationPicker` / `imageFileWriter` seam 隔離真實剪貼簿與 FS。
- 提交前依序通過：`fvm dart format lib/ test/` → `fvm flutter analyze`（No issues found!）→ `fvm flutter test`（All tests passed!）。

## 受影響檔案一覽

| 檔案 | 變更 |
| --- | --- |
| `lib/models/share_image_options.dart` | 新增 `ShareImageAction` enum |
| `lib/widgets/dialogs/share_image_dialog.dart` | 三按鈕、回傳型別改 record |
| `lib/widgets/dialogs/share_progress_dialog.dart` | 新增 |
| `lib/widgets/share/share_image_helper.dart` | 依 action 路由、串接 progress dialog、移除 `_shareResultToDialog` |
| `lib/services/share_image_export.dart` | 刪除 |
| `lib/l10n/app_zh.arb`（及已翻譯 ARB） | 增／刪字串 |
| `test/services/share_image_export_test.dart` | 刪除 |
| `test/widgets/dialogs/share_image_dialog_test.dart` | 更新 |
| `test/widgets/dialogs/share_progress_dialog_test.dart` | 新增 |
| `test/widgets/share/share_image_helper_*` | 新增動作路由測試 |
