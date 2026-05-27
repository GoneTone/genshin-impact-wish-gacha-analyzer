# 匯出資料 / log 後自動 reveal 檔案 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 匯出資料 / 匯出 log 完成後自動開啟檔案總管並選中該檔（Windows `explorer /select,` / macOS `open -R` / Linux fallback 開父資料夾），順手把既有「開啟 logs 資料夾」按鈕重構成共用 helper，並把 zh_Hant 整個 Logs 區段 i18n 統一成 `logs`。

**Architecture:** 新增 `lib/services/file_reveal.dart` 封裝平台分支（單一檔案 + helper），呼叫端在 SnackBar 之後追加 `unawaited(revealInFileManager(loc.path));`，reveal 失敗只 log warning 不影響「匯出成功」訊息。`sanitizeFsPath` 補進既有 `lib/services/log_sanitize.dart` 做路徑脫敏。

**Tech Stack:** Dart / Flutter、`dart:io Process`、`url_launcher`（既有 dependency）、`package:logging`（既有 dependency）。**不引入新套件**。

Spec：`docs/superpowers/specs/2026-05-15-auto-reveal-after-export-design.md`。

---

## File Structure

| 路徑 | 動作 | 責任 |
|---|---|---|
| `lib/services/log_sanitize.dart` | Modify | 加 `sanitizeFsPath(String path) -> String`：把 home 段 username 換成 `***` |
| `test/services/log_sanitize_test.dart` | Modify | 加 `group('sanitizeFsPath', ...)` 測試 4 種 platform path 形狀 |
| `lib/services/file_reveal.dart` | Create | 平台分支封裝。對外暴露 `revealInFileManager(filePath)` / `openFolder(dirPath)`，回傳 `Future<bool>`，失敗只 log warning。 |
| `test/services/file_reveal_test.dart` | Create | 測 helper 對不存在路徑的 graceful 行為（不真的 spawn `explorer.exe`，避免 test 期間彈窗） |
| `lib/pages/settings_page.dart` | Modify (3 處) | 1) `_DataManagement._export` line 345 區段：SnackBar 後追加 reveal；2) `_LogsSection._export` line 659 區段：同樣追加；3) `_LogsSection._openFolder` line 695 區段：改用新 `openFolder` helper。需加 `import 'dart:async' show unawaited;` 跟 `import 'package:.../services/file_reveal.dart';` |
| `lib/l10n/app_zh_Hant.arb` | Modify (6 行) | line 392 / 398 / 400 / 402 / 404 / 410 把 `log` → `logs`。en / zh_Hans 完全不動。 |

依賴順序：**Task 1（sanitize）→ Task 2（reveal helper）→ Tasks 3-5（settings_page 三處改動）→ Task 6（i18n）→ Task 7（最終品檢 + 手動驗證）**。

---

## Task 1: 補 `sanitizeFsPath` 進 `lib/services/log_sanitize.dart`

**Files:**
- Modify: `lib/services/log_sanitize.dart` (append 一個新 fn 在檔尾)
- Test: `test/services/log_sanitize_test.dart` (append 一個新 group)

### Step 1: 寫 failing test

打開 `test/services/log_sanitize_test.dart`，在最後一個 `group('sanitizeUid', ...)` 區塊**之後、`}` 收尾之前**追加新 group：

```dart
  group('sanitizeFsPath', () {
    test('redacts Windows home directory username (backslash)', () {
      expect(
        sanitizeFsPath(r'C:\Users\Alice\Downloads\foo.json'),
        equals(r'C:\Users\***\Downloads\foo.json'),
      );
    });

    test('Windows home redaction is case-insensitive on drive letter', () {
      expect(
        sanitizeFsPath(r'd:\Users\Bob\file.log'),
        equals(r'd:\Users\***\file.log'),
      );
    });

    test('redacts macOS home directory username', () {
      expect(
        sanitizeFsPath('/Users/Alice/Downloads/foo.json'),
        equals('/Users/***/Downloads/foo.json'),
      );
    });

    test('redacts Linux home directory username', () {
      expect(
        sanitizeFsPath('/home/alice/Downloads/foo.json'),
        equals('/home/***/Downloads/foo.json'),
      );
    });

    test('passes through non-home Windows path unchanged', () {
      expect(
        sanitizeFsPath(r'C:\Tools\foo.json'),
        equals(r'C:\Tools\foo.json'),
      );
    });

    test('passes through non-home Unix path unchanged', () {
      expect(sanitizeFsPath('/tmp/foo.log'), equals('/tmp/foo.log'));
      expect(sanitizeFsPath('/var/log/x.log'), equals('/var/log/x.log'));
    });

    test('passes through empty string unchanged', () {
      expect(sanitizeFsPath(''), equals(''));
    });
  });
```

### Step 2: 跑 test 確認失敗

Run: `flutter test test/services/log_sanitize_test.dart`
Expected: FAIL — `Method not found: 'sanitizeFsPath'` 或編譯錯。

### Step 3: 實作 `sanitizeFsPath`

打開 `lib/services/log_sanitize.dart`，在 `sanitizeUid` 之後（檔尾 `}` 之前如果沒 closing scope 就直接接 top-level fn）追加：

```dart
/// 把檔案路徑內的 home 段 username 換成 `***`，避免 log 洩漏使用者名稱。
///
/// - Windows：`C:\Users\<name>\...` → `C:\Users\***\...`（drive letter 大小寫不敏感）
/// - macOS：`/Users/<name>/...` → `/Users/***/...`
/// - Linux：`/home/<name>/...` → `/home/***/...`
/// - 其他路徑（如 `C:\Tools\...`、`/tmp/...`）原樣返回。
String sanitizeFsPath(String raw) {
  // 三種 home prefix 各對一個 anchored regex；group(1) = prefix（保留），group(2) = username（換成 ***）
  for (final re in [
    RegExp(r'^([A-Za-z]:\\Users\\)([^\\]+)'),
    RegExp(r'^(/Users/)([^/]+)'),
    RegExp(r'^(/home/)([^/]+)'),
  ]) {
    if (re.hasMatch(raw)) {
      return raw.replaceFirstMapped(re, (m) => '${m.group(1)}***');
    }
  }
  return raw;
}
```

### Step 4: 跑 test 確認通過

Run: `flutter test test/services/log_sanitize_test.dart`
Expected: `All tests passed!`（含既有 `sanitizeUrl` / `sanitizeUid` + 新 7 個 `sanitizeFsPath` test）

### Step 5: 跑 analyze 確保沒 warning

Run: `flutter analyze lib/services/log_sanitize.dart test/services/log_sanitize_test.dart`
Expected: `No issues found!`

### Step 6: Commit

```bash
git add lib/services/log_sanitize.dart test/services/log_sanitize_test.dart
git commit -m "feat(log_sanitize): add sanitizeFsPath for username redaction in fs paths"
```

---

## Task 2: 新增 `lib/services/file_reveal.dart` + tests

**Files:**
- Create: `lib/services/file_reveal.dart`
- Create: `test/services/file_reveal_test.dart`

### Step 1: 寫 failing test

建立 `test/services/file_reveal_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';

void main() {
  group('revealInFileManager', () {
    test('returns false for non-existent file', () async {
      final fakePath =
          '${Directory.systemTemp.path}/__gwga_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.tmp';
      final ok = await revealInFileManager(fakePath);
      expect(ok, isFalse);
    });

    test('does not throw when file exists (smoke)', () async {
      // 故意不 assert 結果 true/false：在 test 環境
      // launchUrl 通常因為 platform plugin 不存在而失敗回傳 false，
      // 但呼叫本身不應丟例外。
      final f = await File(
        '${Directory.systemTemp.path}/__gwga_reveal_smoke_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ).create();
      try {
        await revealInFileManager(f.path);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });
  });

  group('openFolder', () {
    test('does not throw when dir exists (smoke)', () async {
      // 同上，test 環境多半 launchUrl 會 false / throw MissingPluginException，
      // helper 的責任是 graceful catch。
      final dir = await Directory(
        '${Directory.systemTemp.path}/__gwga_open_smoke_${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      try {
        await openFolder(dir.path);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}
```

### Step 2: 跑 test 確認失敗

Run: `flutter test test/services/file_reveal_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:.../services/file_reveal.dart'`

### Step 3: 建立 `lib/services/file_reveal.dart`

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
      // /select, 後緊接路徑，逗號是語法不是分隔
      final r = await Process.run('explorer', ['/select,${f.path}']);
      // explorer.exe 即使成功也常回傳非 0；只要沒 throw 視為成功
      _log.info(
        'reveal: explorer exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
      );
      return true;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('open', ['-R', f.path]);
      _log.info(
        'reveal: open -R exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
      );
      return r.exitCode == 0;
    }
    // Linux / 其他：fallback 到開資料夾
    return openFolder(f.parent.path);
  } catch (e, st) {
    _log.warning('reveal: failed ${sanitizeFsPath(filePath)}', e, st);
    return false;
  }
}

/// 純開資料夾，沿用 `launchUrl(Uri.file(...))`，跨平台。
Future<bool> openFolder(String dirPath) async {
  try {
    final ok = await launchUrl(Uri.file(dirPath));
    if (!ok) {
      _log.warning(
        'openFolder: launchUrl returned false ${sanitizeFsPath(dirPath)}',
      );
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

### Step 4: 跑 test 確認通過

Run: `flutter test test/services/file_reveal_test.dart`
Expected: `All tests passed!`

> Test 環境內 `launchUrl` 在 Windows 對 `Uri.file(dir)` 多半會走 `Process` 真的 spawn，但 `Directory.systemTemp` 內的暫存資料夾即使被開了也無傷。如果你的開發環境真的會彈出資料夾窗口，把 `openFolder` 那個 smoke test 改成 `expect(await openFolder('/__definitely_not_a_path__'), anyOf(isTrue, isFalse));`（即 just call, don't assert outcome）。Plan 維持原寫法，因為 helper 在不存在路徑的 graceful 行為是核心契約。

### Step 5: 跑 analyze

Run: `flutter analyze lib/services/file_reveal.dart test/services/file_reveal_test.dart`
Expected: `No issues found!`

### Step 6: Commit

```bash
git add lib/services/file_reveal.dart test/services/file_reveal_test.dart
git commit -m "feat(file_reveal): add cross-platform revealInFileManager / openFolder helpers"
```

---

## Task 3: `_DataManagement._export` 接上 reveal

**Files:**
- Modify: `lib/pages/settings_page.dart` （加 2 個 import + `_DataManagement._export` 內 1 行）

### Step 1: 加 imports

打開 `lib/pages/settings_page.dart`，找到既有 import 區塊（line 1-25 左右）。

在 `import 'dart:io';`（line 2）**下面**加：

```dart
import 'dart:async' show unawaited;
```

並在現有 services import 區塊（找到 `import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';` 那行附近）追加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
```

> Import 的字母順序對齊既有檔案慣例（同層的 `services/` 內按 file name 排序）。

### Step 2: 在 `_DataManagement._export` 的 SnackBar 後追加 reveal

定位 `lib/pages/settings_page.dart` 內 `_DataManagement._export` 方法。在原本的：

```dart
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(l.settingsExportSuccess(loc.path))));
  }
```

改成：

```dart
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(l.settingsExportSuccess(loc.path))));
    unawaited(revealInFileManager(loc.path));
  }
```

> 順序：先 SnackBar 再 reveal。reveal 即使在 Windows 冷啟動 `explorer.exe` 卡 1～2 秒，SnackBar 已經顯示。`unawaited` 讓 reveal 走 fire-and-forget，UI 不阻塞。

### Step 3: 跑 analyze

Run: `flutter analyze lib/pages/settings_page.dart`
Expected: `No issues found!`

### Step 4: 跑 test 確認沒回歸

Run: `flutter test`
Expected: `All tests passed!`

### Step 5: Commit

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): reveal exported accounts file in OS file manager"
```

---

## Task 4: `_LogsSection._export` 接上 reveal

**Files:**
- Modify: `lib/pages/settings_page.dart` （`_LogsSection._export` 內 1 行）

### Step 1: 在 `_LogsSection._export` 的 SnackBar 後追加 reveal

定位 `_LogsSection._export` 方法。原本：

```dart
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsLogsExportSuccess(loc.path))),
    );
  }
```

改成：

```dart
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsLogsExportSuccess(loc.path))),
    );
    unawaited(revealInFileManager(loc.path));
  }
```

> Imports 已在 Task 3 加好，本步驟不用再加。

### Step 2: 跑 analyze

Run: `flutter analyze lib/pages/settings_page.dart`
Expected: `No issues found!`

### Step 3: 跑 test 確認沒回歸

Run: `flutter test`
Expected: `All tests passed!`

### Step 4: Commit

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): reveal exported log bundle file in OS file manager"
```

---

## Task 5: 重構 `_LogsSection._openFolder` 改用共用 `openFolder` helper

**Files:**
- Modify: `lib/pages/settings_page.dart` （`_LogsSection._openFolder`）

### Step 1: 改寫 `_openFolder`

定位 `_LogsSection._openFolder` 方法。原本：

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

> `openFolder` helper 自己內部 log warning（用 `ui.reveal` logger，與 `ui.link` 區分），這裡不再重複處理。

### Step 2: 確認 `url_launcher` import 是否還有人用

Run: `flutter analyze lib/pages/settings_page.dart`

如果出現 `unused_import: package:url_launcher/url_launcher.dart` warning，**保留不刪** — `_reportIssue`（line 703 附近）仍在用 `launchUrl(Uri.parse(...), mode: LaunchMode.externalApplication)`。手動 grep 確認：

```bash
grep -n 'launchUrl' lib/pages/settings_page.dart
```

預期至少還有 `_reportIssue` 內 1 處（沒被本 spec 動到）。

> 如果 `flutter analyze` 抱怨 `Logger` import 變未使用，再個別處理；本檔還有別處用 `Logger('accounts.io')`，多半不會。

Expected analyze output: `No issues found!`

### Step 3: 跑 test 確認沒回歸

Run: `flutter test`
Expected: `All tests passed!`

### Step 4: Commit

```bash
git add lib/pages/settings_page.dart
git commit -m "refactor(settings): use shared openFolder helper for logs folder button"
```

---

## Task 6: zh_Hant i18n 6 行統一改成 `logs`

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb` （6 行）

### Step 1: 用 PowerShell + codepoint 顯式組裝改字

⚠️ **重要：** 全/半形標點靠 Edit 工具肉眼會被陰，務必走 PowerShell。改完用 codepoint 驗證一遍才 commit（見 [memory: feedback-fullwidth-punctuation-via-powershell]）。

執行（PowerShell）：

```powershell
$path = 'lib\l10n\app_zh_Hant.arb'
$raw = Get-Content $path -Encoding UTF8 -Raw

# 全形標點顯式組裝，避免靠視覺
$C = [char]0xFF1A  # 全形冒號 ：
$D = [char]0xFF0C  # 全形逗號 ，

# Line 392: settingsLogs
$raw = $raw.Replace('"settingsLogs": "Log 偵錯"', '"settingsLogs": "Logs 偵錯"')

# Line 398: settingsLogsExport（順手把「檔」拿掉，「logs 檔」中文怪）
$raw = $raw.Replace('"settingsLogsExport": "匯出 log 檔"', '"settingsLogsExport": "匯出 logs"')

# Line 400: settingsLogsOpenFolder
$raw = $raw.Replace('"settingsLogsOpenFolder": "開啟 log 資料夾"', '"settingsLogsOpenFolder": "開啟 logs 資料夾"')

# Line 402: settingsLogsClear
$raw = $raw.Replace('"settingsLogsClear": "清除所有 log"', '"settingsLogsClear": "清除所有 logs"')

# Line 404: settingsLogsExportSuccess（包含全形冒號 U+FF1A）
$old404 = '"settingsLogsExportSuccess": "已匯出 log' + $C + '{path}"'
$new404 = '"settingsLogsExportSuccess": "已匯出 logs' + $C + '{path}"'
$raw = $raw.Replace($old404, $new404)

# Line 410: settingsLogsClearConfirmBody（包含全形逗號 U+FF0C）
$old410 = '需要 log' + $D
$new410 = '需要 logs' + $D
$raw = $raw.Replace($old410, $new410)

Set-Content $path -Value $raw -Encoding UTF8 -NoNewline
Write-Output 'WROTE'
```

### Step 2: codepoint 驗證 6 行確實寫對

```powershell
$lines = Get-Content 'lib\l10n\app_zh_Hant.arb' -Encoding UTF8
foreach ($i in 391, 397, 399, 401, 403, 409) {  # 0-indexed = arb line - 1
  $line = $lines[$i]
  $cps = ($line.ToCharArray() | ForEach-Object { '{0}=U+{1:X4}' -f $_, [int]$_ }) -join ' '
  Write-Output ("L{0}: {1}" -f ($i+1), $cps)
}
```

預期輸出包含：
- L392: `Logs` 開頭，無冒號逗號
- L398: `匯出 logs`
- L400: `開啟 logs 資料夾`
- L402: `清除所有 logs`
- L404: 含 `已匯出 logs` + `:=U+FF1A`（**必須是 U+FF1A 全形**，不能是 U+003A）
- L410: 含 `需要 logs` + `,=U+FF0C`（**必須是 U+FF0C 全形**，不能是 U+002C）

如果 L404 的冒號是 U+003A 或 L410 的逗號是 U+002C，**回到 Step 1 重做**（代表 PowerShell 替換沒命中或被 normalize）。

### Step 3: 重新生成 i18n 跑 analyze

Flutter 會自動 regen `lib/l10n/generated/`（pubspec 設定 `generate: true`）。直接：

```bash
flutter analyze
```

Expected: `No issues found!`

如果出現 missing translation key 警告，跑 `flutter gen-l10n` 後重試。

### Step 4: 跑 test 確認沒回歸

```bash
flutter test
```

Expected: `All tests passed!`

### Step 5: Commit

```bash
git add lib/l10n/app_zh_Hant.arb
git commit -m "i18n(zh_Hant): unify Logs section to plural 'logs' for cross-locale consistency"
```

---

## Task 7: 提交前最終品質檢查 + 手動驗證

**Files:** 無新檔案改動，只跑驗證。

### Step 1: dart format

```bash
dart format lib/ test/
```

> ⚠️ 不要對 `.` 跑，會動到 `rust_builder/` 內 vendored 程式碼（CLAUDE.md 規則）。

如果有檔案被改動，commit 一個 format-only commit：

```bash
git status
# 若有改動：
git add -u
git commit -m "chore: dart format"
```

### Step 2: flutter analyze 全專案

```bash
flutter analyze
```

Expected: `No issues found!`

### Step 3: flutter test 全專案

```bash
flutter test
```

Expected: `All tests passed!`

### Step 4: 手動驗證 checklist（Windows，主要 target platform）

```bash
flutter run -d windows
```

進入「設定」頁，跑下列 4 項：

- [ ] **資料匯出 → reveal**：點「匯出帳號」→ 任意帳號 → 選個目的位置 → 完成。預期：底部 SnackBar 顯示路徑 + Windows 檔案總管彈出，剛存的 `.json` 檔被選中。
- [ ] **Log 匯出 → reveal**：點「匯出 logs」→ 選個目的位置 → 完成。預期：SnackBar + 檔案總管彈出 + `.log` 檔被選中。
- [ ] **「開啟 logs 資料夾」按鈕回歸**：點「開啟 logs 資料夾」→ 預期 `<applicationSupport>/logs/` 資料夾在檔案總管打開（不選中特定檔，因為這個按鈕本來就是只開資料夾）。
- [ ] **i18n 三語言對齊**：依序切換到 zh_Hant / zh_Hans / en，看設定頁 Log 區段所有 button label 跟 SnackBar 訊息：
  - zh_Hant: 「Logs 偵錯」/「匯出 logs」/「開啟 logs 資料夾」/「清除所有 logs」/匯出後 SnackBar「已匯出 logs：...」
  - en: 「Debug logs」/「Export logs」/「Open logs folder」/「Clear all logs」/匯出後 SnackBar「Logs exported: ...」
  - zh_Hans: 「日志调试」/「导出日志文件」/「打开日志文件夹」/「清除所有日志」/匯出後 SnackBar「已导出日志：...」

### Step 5: 邊角驗證（reveal 失敗不影響成功流）

無法在實機輕易模擬「`explorer.exe` 不存在」，spec 已接受用 `unawaited` + helper 內部 try-catch 為足夠保護。本步驟做 code review 自我檢查：

- [ ] `_DataManagement._export` 內 `unawaited(revealInFileManager(loc.path));` 在 SnackBar 後而非前
- [ ] `_LogsSection._export` 同上
- [ ] `revealInFileManager` 內 `try / catch (e, st) { _log.warning(...); return false; }` 涵蓋整個 platform branch

### Step 6: 完成回報

Plan 完成。本 spec 不進 git push（CLAUDE.md「設計 spec 留本地」規則）。Commit 已做完，等使用者決定是否 push 到 `flutter-rewrite` branch。

---

## Self-Review

對照 spec 跑一輪：

| Spec 章節 | 任務覆蓋 |
|---|---|
| §2.1 自動 reveal | Tasks 3 + 4 |
| §2.2 失敗不影響 SnackBar | Task 2 helper 內 try-catch + Task 7 Step 5 code review |
| §2.3 抽 helper + 重構 _openFolder | Task 2 + Task 5 |
| §3 非目標（YAGNI） | 計畫不加任何超出 spec 的東西 ✓ |
| §4.1 file_reveal.dart | Task 2 |
| §4.1.1 sanitizeFsPath | Task 1 |
| §4.2 Linux fallback | Task 2 helper 內 fallback to openFolder |
| §4.3 兩個呼叫端 | Tasks 3 + 4 |
| §4.4 重構 _openFolder | Task 5 |
| §4.5 Logger ui.reveal | Task 2 helper |
| §4.6 i18n 6 行 | Task 6 |
| §4.7 不動的東西 | 計畫沒動 ✓ |
| §5 測試 | Tasks 1 + 2 unit tests + Task 7 Step 4 manual |
| §6 spec 自列步驟 | Tasks 1-7 對齊 |
| §7 風險 | 風險 1（quote）已透過 `Process.run` argv 陣列方式覆蓋；風險 2（網路磁碟）`unawaited` 處理；風險 3（Linux）fallback；風險 4（exit code）helper 內不靠 exit code 判斷 |

**Type / signature consistency 檢查：**
- `revealInFileManager(String filePath) -> Future<bool>`：Tasks 2/3/4 一致
- `openFolder(String dirPath) -> Future<bool>`：Tasks 2/5 一致
- `sanitizeFsPath(String raw) -> String`：Task 1/2 一致
- Logger 名稱 `'ui.reveal'`：Task 2 一致

**Placeholder 掃描：** 無 TBD / TODO / "implement later"。Task 5 Step 2 的 url_launcher import 處理是條件式（grep 後決定），不是 placeholder，已給明確判斷指令。
