# file_reveal 注入式測試 seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `flutter test` 不再彈出檔案總管 — 把 `file_reveal.dart` 對 `Platform` / `Process.run` / `launchUrl` 的硬相依改成可注入 seam，並重寫測試用 fake 取代真實 I/O。

**Architecture:** 在 `lib/services/file_reveal.dart` 引入三個 library 層級、預設指向真實實作、`@visibleForTesting` 可覆寫的 seam（`revealPlatform` / `revealProcessRunner` / `revealUrlLauncher`）加一個 `resetFileRevealSeams()` 還原 helper。`revealInFileManager` / `openFolder` 內部改走 seam，公開簽名不變，caller 零改動。測試以 fake 記錄參數並驗證三平台分支。

**Tech Stack:** Dart / Flutter, `flutter_test`, `dart:io`, `url_launcher`。

**參考 spec:** `docs/superpowers/specs/2026-05-18-file-reveal-test-seam-design.md`

---

## File Structure

- Modify: `lib/services/file_reveal.dart` — 加 `RevealPlatform` enum + 三個 seam 變數 + `resetFileRevealSeams()`；`revealInFileManager` / `openFolder` 改走 seam。職責不變（仍是「開檔案總管 / 開資料夾」服務），只是把 I/O 出口變成可替換。
- Rewrite: `test/services/file_reveal_test.dart` — 用 fake runner / launcher 驗證三平台分支與錯誤處理，零真實副作用。

無新檔；caller（`lib/pages/settings_page.dart`）不動。

---

### Task 1: 引入 seam 並重構 file_reveal.dart，重寫測試

**Files:**
- Modify: `lib/services/file_reveal.dart`
- Rewrite: `test/services/file_reveal_test.dart`

> 說明：這是一個保行為重構，source 變更必須一次到位（半套無法通過 `flutter analyze`）。流程為「先寫新測試 → 跑 → 因 seam 未定義而編譯失敗 → 重構 source → 跑 → 全綠」。

- [ ] **Step 1: 重寫測試檔（先寫，會編譯失敗）**

完整覆蓋 `test/services/file_reveal_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';

void main() {
  // 記錄 fake 收到的呼叫
  String? capturedExe;
  List<String>? capturedArgs;
  Uri? capturedUri;

  setUp(() {
    capturedExe = null;
    capturedArgs = null;
    capturedUri = null;
  });

  tearDown(resetFileRevealSeams);

  Future<File> makeTempFile() => File(
    '${Directory.systemTemp.path}/__gwga_reveal_${DateTime.now().microsecondsSinceEpoch}.tmp',
  ).create();

  group('revealInFileManager', () {
    test('non-existent file returns false without touching seams', () async {
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 0, '', '');
      };
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };

      final fakePath =
          '${Directory.systemTemp.path}/__gwga_missing_${DateTime.now().microsecondsSinceEpoch}.tmp';
      final ok = await revealInFileManager(fakePath);

      expect(ok, isFalse);
      expect(capturedExe, isNull);
      expect(capturedArgs, isNull);
      expect(capturedUri, isNull);
    });

    test('windows branch calls explorer /select,<path>', () async {
      revealPlatform = () => RevealPlatform.windows;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 1, '', ''); // explorer 常回非 0
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, 'explorer');
        expect(capturedArgs, ['/select,${f.path}']);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('macos branch with exit 0 returns true', () async {
      revealPlatform = () => RevealPlatform.macos;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 0, '', '');
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, 'open');
        expect(capturedArgs, ['-R', f.path]);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('macos branch with non-zero exit returns false', () async {
      revealPlatform = () => RevealPlatform.macos;
      revealProcessRunner = (exe, args) async =>
          ProcessResult(0, 1, '', '');

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isFalse);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('other platform falls back to openFolder via launcher', () async {
      revealPlatform = () => RevealPlatform.other;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        return ProcessResult(0, 0, '', '');
      };
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, isNull); // runner 未被呼叫
        expect(capturedUri, Uri.file(f.parent.path));
      } finally {
        if (await f.exists()) await f.delete();
      }
    });
  });

  group('openFolder', () {
    test('calls launcher with Uri.file(dir) and returns its result', () async {
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };
      final dir = await Directory(
        '${Directory.systemTemp.path}/__gwga_open_${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      try {
        final ok = await openFolder(dir.path);
        expect(ok, isTrue);
        expect(capturedUri, Uri.file(dir.path));
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('launcher returning false yields false', () async {
      revealUrlLauncher = (uri) async => false;
      final ok = await openFolder(Directory.systemTemp.path);
      expect(ok, isFalse);
    });

    test('launcher throwing yields false without throwing', () async {
      revealUrlLauncher = (uri) async => throw Exception('boom');
      final ok = await openFolder(Directory.systemTemp.path);
      expect(ok, isFalse);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認因 seam 未定義而失敗**

Run: `flutter test test/services/file_reveal_test.dart`
Expected: 編譯失敗，類似 `Undefined name 'resetFileRevealSeams'` / `'revealProcessRunner'` / `RevealPlatform`。

- [ ] **Step 3: 重構 `lib/services/file_reveal.dart` 引入 seam**

完整覆蓋檔案內容：

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

final _log = Logger('ui.reveal');

/// reveal 的目標作業系統。把 [Platform] 判斷抽成 seam，讓三平台分支
/// 能在單一主機上被測試驗證。
enum RevealPlatform { windows, macos, other }

RevealPlatform _defaultPlatform() {
  if (Platform.isWindows) return RevealPlatform.windows;
  if (Platform.isMacOS) return RevealPlatform.macos;
  return RevealPlatform.other;
}

/// 以下三個 seam 預設指向真實實作；測試可覆寫成 fake 後用
/// [resetFileRevealSeams] 還原，避免測試間互相污染、也避免
/// `flutter test` 真的去開檔案總管。
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

/// 開檔案總管並選中指定檔案。失敗回傳 false，呼叫端通常忽略即可
/// （reveal 是 UX 加分項，匯出本身的成功訊息應由呼叫端維持）。
///
/// - Windows：`explorer /select,<path>`
/// - macOS：`open -R <path>`
/// - 其他：沒有跨 DE 的 reveal API，退化成 [openFolder]（開父資料夾）
Future<bool> revealInFileManager(String filePath) async {
  final f = File(filePath);
  if (!await f.exists()) {
    _log.warning('reveal: file not found ${sanitizeFsPath(filePath)}');
    return false;
  }
  try {
    switch (revealPlatform()) {
      case RevealPlatform.windows:
        // /select, 後緊接路徑，逗號是語法不是分隔
        final r = await revealProcessRunner('explorer', ['/select,${f.path}']);
        // explorer.exe 即使成功也常回傳非 0；只要沒 throw 視為成功
        _log.info(
          'reveal: explorer exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
        );
        return true;
      case RevealPlatform.macos:
        final r = await revealProcessRunner('open', ['-R', f.path]);
        _log.info(
          'reveal: open -R exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
        );
        return r.exitCode == 0;
      case RevealPlatform.other:
        return openFolder(f.parent.path);
    }
  } catch (e, st) {
    _log.warning('reveal: failed ${sanitizeFsPath(filePath)}', e, st);
    return false;
  }
}

/// 純開資料夾，沿用 `launchUrl(Uri.file(...))`，跨平台。
Future<bool> openFolder(String dirPath) async {
  try {
    final ok = await revealUrlLauncher(Uri.file(dirPath));
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

- [ ] **Step 4: 跑該檔測試確認全綠**

Run: `flutter test test/services/file_reveal_test.dart`
Expected: All tests passed!（過程中**不**彈出檔案總管）

- [ ] **Step 5: 提交前品質檢查（CLAUDE.md 規定，依序全過）**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`（過程中不彈出檔案總管）

任何一項失敗就先修，不要 `--no-verify`。

- [ ] **Step 6: Commit**

> 註：spec / plan 位於 `docs/superpowers/`，依使用者慣例不進版控，**不要** `git add docs/`。只提交 source 與測試。

```bash
git add lib/services/file_reveal.dart test/services/file_reveal_test.dart
git commit -m "test(reveal): inject Platform/Process/launchUrl seams so flutter test no longer opens File Explorer"
```

---

## Self-Review

**1. Spec coverage:**
- 目標「flutter test 零真實副作用」→ Step 1 全測試用 fake + tearDown reset；Step 4/5 驗證。✓
- 目標「三平台分支單一主機可測」→ `revealPlatform` seam + windows/macos/other 測試案例。✓
- 目標「公開 API 不變、caller 零改動」→ `revealInFileManager`/`openFolder` 簽名不變，未動 `settings_page.dart`。✓
- 架構三 seam + `RevealPlatform` enum + `resetFileRevealSeams` → Step 3 全實作。✓
- 錯誤處理維持 try/catch + log + bool、保留 `sanitizeFsPath` → Step 3 程式碼保留。✓
- 測試案例 1–5（含 macOS exitCode 兩種、openFolder false/throw）→ Step 1 全覆蓋。✓
- YAGNI（不抽存在性檢查、不建 class、不動 app_link）→ 計畫未引入這些。✓

**2. Placeholder scan:** 無 TBD / TODO / 「類似上面」；所有程式碼步驟皆附完整程式碼。✓

**3. Type consistency:** `RevealPlatform` enum 三值（windows/macos/other）、`revealPlatform` / `revealProcessRunner` / `revealUrlLauncher` / `resetFileRevealSeams` 在 source 與測試命名一致；`revealProcessRunner` 簽名 `(String, List<String>) -> Future<ProcessResult>` 與測試 fake 一致。✓

無遺漏，無需再 review。
