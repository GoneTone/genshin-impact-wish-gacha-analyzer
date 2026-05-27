# file_reveal 注入式測試 seam — 設計

## 問題

`flutter test` 在 Windows 上會彈出檔案總管視窗。

根因：`test/services/file_reveal_test.dart` 的 `does not throw when file exists (smoke)`
測試會建立真實暫存檔，呼叫 `revealInFileManager(f.path)`。`lib/services/file_reveal.dart`
的 `revealInFileManager` 在 Windows 分支直接執行 `Process.run('explorer', ['/select,<path>'])`，
測試跑到這條時就真的開了一個檔案總管。`revealInFileManager` / `openFolder` 對
`Platform`、`Process.run`、`launchUrl` 是硬相依，沒有測試接縫。

## 目標

- `flutter test` 全程不產生任何真實的 `Process.run` / `launchUrl` 副作用（不彈檔案總管 / Finder）。
- 三個平台分支（Windows / macOS / 其他）都能在單一主機上被測試驗證。
- 公開 API（`revealInFileManager(String)`、`openFolder(String)`）簽名不變，caller 零改動。

## 架構

在 `lib/services/file_reveal.dart` 引入三個 library 層級、預設指向真實實作、
`@visibleForTesting` 可覆寫的 seam：

```dart
enum RevealPlatform { windows, macos, other }

@visibleForTesting
RevealPlatform Function() revealPlatform = _defaultPlatform;

@visibleForTesting
Future<ProcessResult> Function(String exe, List<String> args)
    revealProcessRunner = Process.run;

@visibleForTesting
Future<bool> Function(Uri uri) revealUrlLauncher = launchUrl;

@visibleForTesting
void resetFileRevealSeams() {
  revealPlatform = _defaultPlatform;
  revealProcessRunner = Process.run;
  revealUrlLauncher = launchUrl;
}
```

`_defaultPlatform()` 依序判斷 `Platform.isWindows` → `RevealPlatform.windows`、
`Platform.isMacOS` → `RevealPlatform.macos`、其餘 → `RevealPlatform.other`。

`revealInFileManager` / `openFolder` 內部改用這三個 seam，不再直接碰
`Platform` / `Process.run` / `launchUrl`。檔案存在性檢查維持真實 FS（不抽，
測試用真實 temp 檔即可）。

## 資料流

```
revealInFileManager(path)
  → File(path).exists()  (真實 FS)
  → 不存在: log warning, return false
  → switch revealPlatform():
      windows → revealProcessRunner('explorer', ['/select,<path>']) → return true
      macos   → revealProcessRunner('open', ['-R', <path>]) → return exitCode == 0
      other   → openFolder(parentDir)

openFolder(dir)
  → revealUrlLauncher(Uri.file(dir))
  → 回傳 launcher 結果；false / throw 都 log warning 後回 false
```

## 錯誤處理

維持現狀：try/catch、`Logger('ui.reveal')` warning/info、回傳 bool。
seam 只替換 I/O 出口，不改變錯誤語意，既有 log 內容（含 `sanitizeFsPath`）保留。

## 測試

重寫 `test/services/file_reveal_test.dart`。fake runner / launcher 記錄收到的參數，
每個 test 自行設定所需 seam，`tearDown(resetFileRevealSeams)` 防測試間污染。

測試案例：

1. **non-existent file** → 回 `false`，runner 與 launcher 皆未被呼叫。
2. **Windows 分支**：`revealPlatform = () => RevealPlatform.windows`，傳入存在的
   temp 檔 → 斷言 runner 收到 `('explorer', ['/select,<path>'])`，回傳 `true`。
3. **macOS 分支**：`revealPlatform = () => RevealPlatform.macos`，fake runner 回
   exitCode 0 → 斷言 runner 收到 `('open', ['-R', <path>])`，回傳 `true`；
   另一案例 exitCode 非 0 → 回傳 `false`。
4. **其他平台分支**：`revealPlatform = () => RevealPlatform.other` → runner 未被
   呼叫，改呼叫 launcher 收到 `Uri.file(<parentDir>)`。
5. **openFolder**：launcher 收到 `Uri.file(<dir>)`；launcher 回 `false` → openFolder
   回 `false`；launcher `throw` → 回 `false` 且不丟例外。

全程零真實 `Process.run` / `launchUrl`，`flutter test` 不再彈出檔案總管。

## 不做（YAGNI）

- 不抽檔案存在性檢查（真實 temp 檔已足夠，抽象無收益）。
- 不為 seam 建立 class / DI 容器，library 層級可覆寫變數已足夠且符合既有
  `@visibleForTesting` 慣例。
- 不動 `lib/widgets/app_link.dart` 的 `openExternalUrl`（不同語意，非重複造輪子）。
