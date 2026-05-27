# Spec：匯出資料 / log 後自動 reveal 檔案

- 日期：2026-05-15
- 分支：`flutter-rewrite`
- 來源：使用者反映匯出資料 / 匯出 log 完成後，只在底部閃一個 SnackBar 顯示路徑，使用者還要自己開檔案總管去找剛存的檔，UX 不佳。希望匯出完成自動開啟檔案總管並選中該檔案。

## 1. 背景

目前兩個匯出流程：

| 功能 | 位置 | 完成後行為 |
|---|---|---|
| 帳號資料匯出 (`.json`) | `lib/pages/settings_page.dart:345`（`_AccountsSection._export`） | `await File(loc.path).writeAsString(text)` → `Logger('accounts.io').info(...)` → `ScaffoldMessenger.showSnackBar(l.settingsExportSuccess(loc.path))` |
| Log 匯出 (`.log`) | `lib/pages/settings_page.dart:659`（`_LogsSection._export`） | `await File(loc.path).writeAsString(bundle)` → `Logger('accounts.io').info(...)` → `ScaffoldMessenger.showSnackBar(l.settingsLogsExportSuccess(loc.path))` |

另有一個既有「開啟 logs 資料夾」按鈕：

- `lib/pages/settings_page.dart:695`（`_LogsSection._openFolder`）：`await launchUrl(Uri.file(log.logsDir.path))`

問題：

1. 兩個匯出流程都只 toast 訊息，使用者要自己 Win+E 翻到剛剛選的位置才看得到檔。
2. SnackBar 顯示完整路徑，但長路徑常被截斷或一閃即逝。
3. 主流桌面 app（瀏覽器下載完成、Discord、VSCode export）都會在通知裡提供「在檔案總管中顯示」或直接彈出檔案總管 + 選中該檔，使用者期望一致。

## 2. 目標

1. 匯出資料 / 匯出 log 完成後，**自動開啟檔案總管並 select 該檔案**（reveal-and-select 行為）。
2. 失敗（platform 不支援、權限拒絕、`explorer` / `open` 沒裝等等）**不影響**「匯出已成功」的 SnackBar，純 UX 加分項，失敗只 log warning。
3. 抽出共用 helper `revealInFileManager(filePath)` / `openFolder(dirPath)`，順手把現有 `_openFolder`（line 695）改用新 helper，避免兩條 `launchUrl(Uri.file(...))` 各自維護（對齊 CLAUDE.md「嚴禁重複造輪子」）。

## 3. 非目標（YAGNI）

- **不加偏好設定開關**。使用者沒提，預設就自動 reveal；之後嫌煩再加。
- **不為 reveal 失敗 toast 額外錯誤訊息**。匯出本身已成功，不要 noise。
- **不做「最近匯出歷史」清單**。
- **不替 SnackBar 加 action button「開啟資料夾」**。直接 reveal 已足夠。
- **不引入新套件**（`open_filex` / `open_file_manager` 等）。`url_launcher` + `dart:io Process` 已足夠，避免無謂依賴。
- **不為 Linux 重寫一個跨 DE 的 reveal 實作**。Linux 沒有 `explorer /select,` 對等的標準 API；fallback 開父資料夾即可（見 §4.2）。

## 4. 設計

### 4.1 新檔案：`lib/services/file_reveal.dart`

平台分支封裝在這裡，呼叫端拿到的就是「成功 / 失敗」的單一 boolean。

```dart
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

final _log = Logger('ui.reveal');

/// 開檔案總管並選中指定檔案。失敗回傳 false，呼叫端通常忽略即可
/// （reveal 是 UX 加分項，匯出本身的成功訊息應由呼叫端維持）。
///
/// - Windows：`explorer /select,<path>`
/// - macOS：`open -R <path>`
/// - Linux：沒有跨 DE 的 reveal API，退化成 [openFolder]（開父資料夾）
Future<bool> revealInFileManager(String filePath) async {
  final f = File(filePath);
  if (!await f.exists()) {
    _log.warning('reveal: file not found ${sanitizeFsPath(filePath)}');
    return false;
  }
  try {
    if (Platform.isWindows) {
      // 注意 /select, 後緊接路徑，逗號是語法不是分隔
      final r = await Process.run('explorer', ['/select,${f.path}']);
      // explorer.exe 即使成功也常回傳非 0；只要沒 throw 視為成功
      _log.info('reveal: explorer exit=${r.exitCode} '
          '${sanitizeFsPath(f.path)}');
      return true;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('open', ['-R', f.path]);
      _log.info('reveal: open -R exit=${r.exitCode} '
          '${sanitizeFsPath(f.path)}');
      return r.exitCode == 0;
    }
    // Linux / 其他：fallback 到開資料夾
    return openFolder(f.parent.path);
  } catch (e, st) {
    _log.warning('reveal: failed ${sanitizeFsPath(filePath)}', e, st);
    return false;
  }
}

/// 純開資料夾，沿用現有 `launchUrl(Uri.file(...))`，跨平台。
Future<bool> openFolder(String dirPath) async {
  try {
    final ok = await launchUrl(Uri.file(dirPath));
    if (!ok) {
      _log.warning('openFolder: launchUrl returned false '
          '${sanitizeFsPath(dirPath)}');
    } else {
      _log.info('openFolder: ${sanitizeFsPath(dirPath)}');
    }
    return ok;
  } catch (e, st) {
    _log.warning('openFolder: failed ${sanitizeFsPath(dirPath)}', e, st);
    return false;
  }
}
```

#### 4.1.1 路徑脫敏 `sanitizeFsPath`

CLAUDE.md 規則要求 log 內容脫敏。檔案路徑會包含使用者名稱（Windows `C:\Users\<name>\...`、macOS `/Users/<name>/...`），新增一個輕量 helper：

- 位置：`lib/services/log_sanitize.dart`（既有檔，已有 `sanitizeUrl` / `sanitizeUid`，本 spec 加 `sanitizeFsPath`）
- 行為：
  - Windows：`C:\Users\Alice\Downloads\foo.json` → `C:\Users\***\Downloads\foo.json`
  - macOS / Linux：`/Users/Alice/...` → `/Users/***/...`、`/home/alice/...` → `/home/***/...`
  - 其他路徑原樣返回（例如 `C:\Tools\foo.json`、`/tmp/...`）
- 對應的 unit test 加在 `test/services/log_sanitize_test.dart`（如果該檔不存在，與既有測試慣例一致地新建一支）。

### 4.2 為什麼 Linux 退化成「開父資料夾」

- Linux 沒有 `explorer /select,` 或 `open -R` 的 freedesktop 標準。各 DE 各自實作（Nautilus 有 D-Bus `org.freedesktop.FileManager1.ShowItems`、KDE 用 `dolphin --select`、Thunar / Nemo 又不一樣）。
- 為了一個次要 UX 寫 D-Bus client + DE detect 太重，違反 YAGNI。
- 退化到開父資料夾，使用者「至少在對的資料夾裡」，比現狀（什麼都不開）好。

### 4.3 兩個匯出呼叫端的修改

`settings_page.dart:345`（資料匯出）、`settings_page.dart:659`（log 匯出）的 `_export` 方法在 `await File(loc.path).writeAsString(...)` 之後、`ScaffoldMessenger.showSnackBar(...)` 之後，追加：

```dart
unawaited(revealInFileManager(loc.path));
```

要點：

- **`unawaited`**：reveal 是 fire-and-forget，不阻塞 UI、不影響 SnackBar 顯示。
- **順序**：先 SnackBar 後 reveal。即使 reveal 卡 1～2 秒（Windows 冷啟 `explorer.exe`），SnackBar 也已經出現。
- **不檢查回傳值**：失敗 helper 自己 log warning，呼叫端不需處理。

### 4.4 順手重構 `_openFolder`（line 695）

原本：

```dart
Future<void> _openFolder(BuildContext ctx, WidgetRef ref) async {
  final log = ref.read(logServiceProvider);
  final uri = Uri.file(log.logsDir.path);
  if (!await launchUrl(uri)) {
    Logger('ui.link').warning('openLogsFolder: launchUrl returned false');
  }
}
```

改成：

```dart
Future<void> _openFolder(BuildContext ctx, WidgetRef ref) async {
  final log = ref.read(logServiceProvider);
  await openFolder(log.logsDir.path);
}
```

這是工作範圍內的清理，不是無關 refactor —— `openFolder` 就是把這段邏輯抽出來放進 `file_reveal.dart` 的，原地用回它本來就是它的 caller。

### 4.5 Logger 命名

對齊 CLAUDE.md「Logger 命名對齊既有樹」，新 logger 用 `ui.reveal`：

- `ui.link`：`launchUrl` 開外部 URL（既有，例如 GitHub Issues、`app_link`）
- `ui.reveal`：開 / reveal 本機檔案路徑（新增）

不沿用 `ui.link` 是因為「點 link 開瀏覽器」跟「reveal 本機檔案」是兩個語義域，分開較利於使用者匯出 log 時 grep。

### 4.6 順手修 i18n：zh_Hant 整個 Logs 區段統一 `logs`，三語言對齊

**規則**：zh_Hant 是基準。任何一個 `settingsLogs*` key，**zh_Hant 用 `log` → 三語言用 `log`；zh_Hant 用 `logs` → 三語言用 `logs`**。
audit 整個區段後，zh_Hant 統一改成 `logs`，只有 `settingsLogsHint` 例外保留 `log`（見下表）。

| line | key | zh_Hant 原 | zh_Hant 新 | en | zh_Hans |
|---|---|---|---|---|---|
| 392 | `settingsLogs` | `"Log 偵錯"` | **`"Logs 偵錯"`** | `"Debug logs"` ✓ | `"日志调试"` ✓ |
| 394 | `settingsLogsHint` | `"...可匯出 log..."` | **不動** | `"...the log..."` | `"...导出 log..."` |
| 398 | `settingsLogsExport` | `"匯出 log 檔"` | **`"匯出 logs"`**（去掉「檔」，「logs 檔」中文怪） | `"Export logs"` ✓ | `"导出日志文件"` ✓ |
| 400 | `settingsLogsOpenFolder` | `"開啟 log 資料夾"` | **`"開啟 logs 資料夾"`** | `"Open logs folder"` ✓ | `"打开日志文件夹"` ✓ |
| 402 | `settingsLogsClear` | `"清除所有 log"` | **`"清除所有 logs"`** | `"Clear all logs"` ✓ | `"清除所有日志"` ✓ |
| 404 | `settingsLogsExportSuccess` | `"已匯出 log：{path}"` | **`"已匯出 logs：{path}"`** | `"Logs exported: {path}"` ✓ | `"已导出日志：{path}"` ✓ |
| 410 | `settingsLogsClearConfirmBody` | `"...需要 log，請先匯出..."` | **`"...需要 logs，請先匯出..."`** | `"...Export them first..."`（代名詞回指 `logs/` 路徑，視為一致） | `"...需要日志..."` ✓ |

zh_Hant 共 6 行要改（line 392 / 398 / 400 / 402 / 404 / 410）。en / zh_Hans 完全不動：

- en：除 hint 外本來就是 `logs`，剛好對齊：
- zh_Hans：「日志」中文無單複數，本身就涵蓋 logs 概念：
- `settingsLogsHint` 例外原因：英文 `"the log"` 是描述「使用者匯出的單一 log 檔」，語意層級不同於 button label 的複數 `logs`；zh_Hant 跟著保留 `log` 才能與 en 對齊：

這幾個 key 都僅在 `en` / `zh_Hans` / `zh_Hant` 三檔有定義（其他 fallback 語系本來就沒寫，對齊 [debug logging spec](2026-05-15-debug-logging-design.md) 的 i18n 撰寫慣例）。

### 4.7 不需要動的東西

- `LogService.buildExportBundle`：純 builder，不知道也不需要知道下游怎麼處理檔案。
- `accounts_export.exportAccounts`：純 string builder，同上。
- 既有 `l.settingsExportSuccess` / `l.settingsLogsExportSuccess` i18n key：訊息不變。
- `pubspec.yaml`：不加 dependency。

## 5. 測試

| 測試 | 形式 |
|---|---|
| `revealInFileManager` 對不存在路徑回傳 false 並 log warning | unit test，用 `Directory.systemTemp` 造一個不存在的路徑 |
| `revealInFileManager` 對既存檔案在當前平台不丟例外 | unit test，跑 `Process.run` 真的呼叫 explorer / open（Linux CI 跑 fallback 路徑） |
| `sanitizeFsPath` Windows / macOS / Linux 三種 home 形狀 | pure unit test |
| reveal 失敗不影響「匯出成功」訊息流 | manual：把 helper monkey-patch 成永遠 throw，匯出仍走完 SnackBar |

不為 settings_page 的整合行為寫 widget test —— `_export` 已經摸 `getSaveLocation`（platform plugin）和真實檔案系統，現有測試也沒覆蓋；本次只追加一行 `unawaited(...)`，靠 helper 自己的 unit test + 手動驗證即可。

## 6. 實作步驟（給 writing-plans 參考）

1. 在 `lib/services/log_sanitize.dart` 補 `sanitizeFsPath` + test（既有檔已有 `sanitizeUrl` / `sanitizeUid`）。
2. 新增 `lib/services/file_reveal.dart`（`revealInFileManager` + `openFolder`）+ test。
3. `settings_page.dart:_AccountsSection._export`：在 SnackBar 後追加 `unawaited(revealInFileManager(loc.path));` + import。
4. `settings_page.dart:_LogsSection._export`：同步追加 `unawaited(revealInFileManager(loc.path));` + import。
5. `settings_page.dart:_LogsSection._openFolder`：改用 `openFolder(log.logsDir.path)`。
6. `lib/l10n/app_zh_Hant.arb` 6 處改 `log` → `logs`：line 392 / 398 / 400 / 402 / 404 / 410，細節見 §4.6 表格。en / zh_Hans 不動。
7. 提交前品質檢查（CLAUDE.md）：
   - `dart format lib/ test/`
   - `flutter analyze` → `No issues found!`
   - `flutter test` → `All tests passed!`
8. 手動驗證：
   - Windows：匯出 `.json` / `.log` → 檔案總管彈出，剛存的檔被選中。
   - 對既有「開啟 logs 資料夾」按鈕回歸測試。

## 7. 風險

| 風險 | 對策 |
|---|---|
| `explorer.exe /select,` 對含空白 / Unicode 路徑可能要 quote | 使用 `Process.run('explorer', [...])` 走 argv 陣列，不走 shell，Dart 會處理 escape；如果實作期發現特定字（例如 `,`）出問題再針對性修 |
| 使用者把檔案存在網路磁碟、reveal 等很久 | `unawaited`，UI 不卡；最多就是檔案總管慢慢開 |
| Linux 使用者抱怨「為什麼沒選中檔案」 | 文件層面說明，且現狀本來就什麼都不開，fallback 開父資料夾仍是淨提升 |
| `explorer.exe` 通常 exit code 1 即使成功 | 不靠 exit code 判斷成功，只 log；不 surface 成失敗訊息 |
