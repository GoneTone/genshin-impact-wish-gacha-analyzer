# 匯出結果改用 Dialog 設計

日期：2026-05-19
分支：flutter-rewrite

## 背景與問題

目前三個導出檔案流程在成功後都是「底部 SnackBar 訊息 + 自動呼叫 `revealInFileManager` 開檔案總管並選中檔案」：

1. **帳號資料匯出** — `lib/pages/settings_page.dart` 帳號匯出方法（約 L390-443，`genshin_gacha_backup_*.json`）
2. **Logs 匯出** — `lib/pages/settings_page.dart` `_export`（L681-714，`gwga_logs_*.log`）
3. **分享圖片匯出** — `lib/widgets/share/share_result_snackbar.dart` `showShareResultSnackBar`，由 `lib/widgets/share/share_image_helper.dart` 呼叫

自動開檔案總管打斷使用者、無法取消。需求：改成彈 `AppDialog` 顯示訊息，提供「開啟資料夾」與「關閉」按鈕，**不再自動開啟**。

額外發現：帳號匯出 / Logs 匯出目前**沒有任何失敗處理**，`File.writeAsString` 丟例外是未捕捉的 async exception，連 SnackBar 都沒有。本次一併補上 try/catch 失敗處理。

## 決策（已與使用者確認）

1. 「開啟資料夾」按鈕行為 = **沿用現行 `revealInFileManager`（開檔案總管並反白選中該檔案）**，非僅開父資料夾。
2. 分享圖片 `copiedOnly` 狀態（只複製到剪貼簿、無檔案路徑）**也彈 Dialog**，但隱藏「開啟資料夾」鈕。
3. 範圍 = 三個導出流程的**成功 + 失敗**訊息都改 Dialog。import 失敗、其他既有 SnackBar 不動。

## 方案

採單一共用 helper（方案 A）：一個函式統一彈 `AppDialog`，三流程共用，符合 CLAUDE.md「嚴禁重複造輪子」「Dialog 一律用 AppDialog」。`showShareResultSnackBar` 由其取代。否決：各流程 inline 寫（重複、樣式飄）、獨立 Widget class（過度設計，專案現況為函式風格）。

## 設計

### 1. 共用元件

新增 `lib/widgets/dialogs/export_result_dialog.dart`：

```dart
Future<void> showExportResultDialog(
  BuildContext context, {
  required bool success,
  required String message,
  String? revealPath,   // 有值才顯示「開啟資料夾」鈕
})
```

- 內部用 `AppDialog(size: AppDialogSize.sm)`。
- `title`：成功 → `l.exportDialogSuccessTitle`；失敗 → `l.exportDialogFailedTitle`。
- `content`：`Text(message)`。
- `actions`：
  - `revealPath != null` 時：`TextButton`「開啟資料夾」（`l.actionOpenFolder`）→ 先 `Navigator.pop` 關閉 dialog，再 `unawaited(revealInFileManager(revealPath))`。
  - `FilledButton`「關閉」（`l.actionClose`）→ `Navigator.pop`。
- 不含任何自動 reveal。

### 2. 三個呼叫端改動

| 流程 | 成功 | 失敗（新增 try/catch） |
|---|---|---|
| 帳號匯出（settings_page，約 L390-443） | `showExportResultDialog(success: true, message: l.settingsExportSuccess(path), revealPath: path)` | `success: false, message: l.settingsExportFailed(err)`, revealPath: null |
| Logs 匯出 `_export`（settings_page L681-714） | `message: l.settingsLogsExportSuccess(path)`, revealPath: path | `message: l.settingsLogsExportFailed(err)` |
| 分享圖片（share_image_helper / share_result_snackbar） | `savedAndCopied`/`savedOnly` 帶 path；`copiedOnly` 不帶 path（隱藏鈕） | `message: l.shareImageFailed`（既有 key） |

- 移除三處 `ScaffoldMessenger.showSnackBar(...)` + `unawaited(revealInFileManager(...))`。
- `share_result_snackbar.dart` 整支刪除。原本 `ShareExportResult.status` → 訊息/path 的 mapping（含 `copiedOnly` 不帶 path）改寫成 `share_image_helper.dart` 內一個 private 函式，算好 `message` 與 `revealPath` 後呼叫 `showExportResultDialog`。helper 本身不認識 `ShareExportResult`，保持單一職責。
- 帳號 / Logs 匯出在 `File(loc.path).writeAsString(...)` 外包 try/catch；mounted 檢查維持。

### 3. l10n（4 個 arb：app_en / app_ja / app_zh / app_zh_Hans）

新增 key：

- `exportDialogSuccessTitle` — 例：zh「匯出成功」
- `exportDialogFailedTitle` — 例：zh「匯出失敗」
- `actionOpenFolder` — 通用「開啟資料夾」（現有 `settingsLogsOpenFolder` 為 logs 專用，不沿用）
- `settingsExportFailed(error)` — 帶 placeholder
- `settingsLogsExportFailed(error)` — 帶 placeholder

沿用既有：`actionClose`、`shareImageFailed`、`settingsExportSuccess`、`settingsLogsExportSuccess`、`shareImageSavedAndCopied`、`shareImageSavedOnly`、`shareImageCopiedOnly`。

需 4 語系都加，並重新 gen localizations。

### 4. 埋 log

- 帳號 / Logs 匯出失敗分支：`Logger('accounts.io').severe('export failed ...', e, st)`，path 經 `sanitizeFsPath` 脫敏。
- reveal 既有 `Logger('ui.reveal')` 不動。

### 5. 測試

- 新增 `test/widgets/dialogs/export_result_dialog_test.dart`：
  - 成功且有 path → 顯示「開啟資料夾」+「關閉」兩鈕。
  - 失敗 → 只有「關閉」鈕。
  - `revealPath == null`（含 copiedOnly 情境）→ 無「開啟資料夾」鈕。
  - 點「開啟資料夾」→ 觸發 `revealInFileManager` seam（用 file_reveal 既有 `@visibleForTesting` seam fake），dialog 關閉。
  - 點「關閉」→ dialog 消失。
  - 開啟 dialog 期間不會自動觸發 reveal seam。
- 改寫或移除 `share_result_snackbar` 相關既有測試（改測新 helper / 呼叫端）。
- 若現有測試覆蓋帳號 / logs 匯出流程，補失敗路徑測試。

## 提交前檢查

`dart format lib/ test/` → `flutter analyze`（No issues found!）→ `flutter test`（All tests passed!）。
