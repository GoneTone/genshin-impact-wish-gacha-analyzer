# 匯出結果改用 Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 三個導出檔案流程（帳號匯出、Logs 匯出、分享圖片）的成功與失敗訊息，從「底部 SnackBar + 自動開檔案總管」改為彈出 `AppDialog`，提供「開啟資料夾」與「關閉」按鈕，不再自動開啟。

**Architecture:** 新增單一共用函式 `showExportResultDialog`，內部用專案統一的 `AppDialog`。三個呼叫端改呼叫它，並為帳號／Logs 匯出補上 try/catch 失敗處理。`share_result_snackbar.dart` 刪除，其 status→訊息 mapping 改為 `share_image_helper.dart` 內的 private 函式。

**Tech Stack:** Flutter / Dart、flutter gen-l10n（4 語系 arb，template = `app_zh.arb`）、`file_reveal.dart` 既有 `@visibleForTesting` seam、flutter_test。

設計來源：`docs/superpowers/specs/2026-05-19-export-result-dialog-design.md`

---

## File Structure

- **Create** `lib/widgets/dialogs/export_result_dialog.dart` — `showExportResultDialog`，唯一的匯出結果 dialog 入口。
- **Create** `test/widgets/dialogs/export_result_dialog_test.dart` — helper 行為測試。
- **Modify** `lib/l10n/app_zh.arb`（template，含 @metadata）、`app_en.arb`、`app_ja.arb`、`app_zh_Hans.arb` — 新增 5 個 key。
- **Modify** `lib/widgets/share/share_image_helper.dart` — 改呼叫新 helper，內含 status mapping private 函式。
- **Delete** `lib/widgets/share/share_result_snackbar.dart` — 由新 helper 取代。
- **Modify** `lib/pages/settings_page.dart` — 帳號匯出 `_export`（約 L368-443）、Logs 匯出 `_export`（約 L681-714）：補 try/catch、改呼叫 helper、移除 SnackBar/`unawaited(revealInFileManager)`、清掉變為未使用的 `import 'dart:async' show unawaited;`。

每個 task 結束前都跑 CLAUDE.md 提交前檢查：`dart format lib/ test/` → `flutter analyze`（須 `No issues found!`）→ `flutter test`（須 `All tests passed!`），再 commit。

---

### Task 1: 新增 l10n key（4 語系）

新增 key：`exportDialogSuccessTitle`、`exportDialogFailedTitle`、`actionOpenFolder`、`settingsExportFailed(error)`、`settingsLogsExportFailed(error)`。

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`

- [ ] **Step 1: 在 `app_zh.arb`（template）`shareImageFailed` 那一行後面插入**

於 `lib/l10n/app_zh.arb` 第 303 行 `"shareImageFailed": "分享圖生成失敗",` 之後插入：

```json
  "exportDialogSuccessTitle": "匯出成功",
  "exportDialogFailedTitle": "匯出失敗",
  "actionOpenFolder": "開啟資料夾",
  "settingsExportFailed": "匯出失敗：{error}",
  "@settingsExportFailed": {
    "placeholders": { "error": { "type": "String" } }
  },
  "settingsLogsExportFailed": "Logs 匯出失敗：{error}",
  "@settingsLogsExportFailed": {
    "placeholders": { "error": { "type": "String" } }
  },
```

- [ ] **Step 2: 在 `app_en.arb` 對應位置（`"shareImageFailed"` 行之後）插入**

```json
  "exportDialogSuccessTitle": "Export Successful",
  "exportDialogFailedTitle": "Export Failed",
  "actionOpenFolder": "Open Folder",
  "settingsExportFailed": "Export failed: {error}",
  "settingsLogsExportFailed": "Logs export failed: {error}",
```

- [ ] **Step 3: 在 `app_ja.arb` 對應位置（`"shareImageFailed"` 行之後）插入**

```json
  "exportDialogSuccessTitle": "エクスポート成功",
  "exportDialogFailedTitle": "エクスポート失敗",
  "actionOpenFolder": "フォルダーを開く",
  "settingsExportFailed": "エクスポートに失敗しました：{error}",
  "settingsLogsExportFailed": "ログのエクスポートに失敗しました：{error}",
```

- [ ] **Step 4: 在 `app_zh_Hans.arb` 對應位置（`"shareImageFailed"` 行之後）插入**

```json
  "exportDialogSuccessTitle": "导出成功",
  "exportDialogFailedTitle": "导出失败",
  "actionOpenFolder": "打开文件夹",
  "settingsExportFailed": "导出失败：{error}",
  "settingsLogsExportFailed": "日志导出失败：{error}",
```

> 註：只有 template（`app_zh.arb`）需要 `@key` placeholders metadata；其餘語系僅放 key:value，placeholder 由 template 推導。確認每個檔案插入後 JSON 仍合法（前一行尾端要有逗號）。

- [ ] **Step 5: 重新產生 localizations**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `exportDialogSuccessTitle`、`exportDialogFailedTitle`、`actionOpenFolder`、`settingsExportFailed`、`settingsLogsExportFailed` getter／方法。

- [ ] **Step 6: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_zh_Hans.arb lib/l10n/generated/app_localizations.dart
git commit -m "feat(i18n): add export result dialog l10n keys"
```

---

### Task 2: `showExportResultDialog` helper（TDD）

**Files:**
- Create: `lib/widgets/dialogs/export_result_dialog.dart`
- Test: `test/widgets/dialogs/export_result_dialog_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/dialogs/export_result_dialog_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';

void main() {
  String? capturedExe;
  List<String>? capturedArgs;

  setUp(() {
    capturedExe = null;
    capturedArgs = null;
  });
  tearDown(resetFileRevealSeams);

  Future<File> makeTempFile() => File(
    '${Directory.systemTemp.path}/__gwga_erd_${DateTime.now().microsecondsSinceEpoch}.tmp',
  ).create();

  Future<void> pumpHost(
    WidgetTester t, {
    required bool success,
    required String message,
    String? revealPath,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showExportResultDialog(
                  ctx,
                  success: success,
                  message: message,
                  revealPath: revealPath,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('成功且有路徑：顯示訊息＋開啟資料夾＋關閉，不自動 reveal', (t) async {
    revealPlatform = () => RevealPlatform.windows;
    revealProcessRunner = (exe, args) async {
      capturedExe = exe;
      capturedArgs = args;
      return ProcessResult(0, 1, '', '');
    };
    final f = await makeTempFile();
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    try {
      await pumpHost(t, success: true, message: '已匯出至 ${f.path}', revealPath: f.path);

      expect(find.text('已匯出至 ${f.path}'), findsOneWidget);
      expect(find.text(l.exportDialogSuccessTitle), findsOneWidget);
      expect(find.text(l.actionOpenFolder), findsOneWidget);
      expect(find.text(l.actionClose), findsOneWidget);
      expect(capturedExe, isNull); // 不自動 reveal

      await t.tap(find.text(l.actionOpenFolder));
      await t.pumpAndSettle();

      expect(capturedExe, 'explorer');
      expect(capturedArgs, ['/select,${f.path}']);
      expect(find.text(l.actionClose), findsNothing); // dialog 已關
    } finally {
      if (await f.exists()) await f.delete();
    }
  });

  testWidgets('失敗：只有關閉鈕，無開啟資料夾', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await pumpHost(t, success: false, message: '匯出失敗：boom', revealPath: null);

    expect(find.text(l.exportDialogFailedTitle), findsOneWidget);
    expect(find.text('匯出失敗：boom'), findsOneWidget);
    expect(find.text(l.actionClose), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsNothing);
  });

  testWidgets('成功但無路徑（copiedOnly）：無開啟資料夾鈕', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await pumpHost(t, success: true, message: '已複製到剪貼簿', revealPath: null);

    expect(find.text(l.actionOpenFolder), findsNothing);
    expect(find.text(l.actionClose), findsOneWidget);
  });

  testWidgets('點關閉：dialog 消失且未觸發 reveal', (t) async {
    revealPlatform = () => RevealPlatform.windows;
    revealProcessRunner = (exe, args) async {
      capturedExe = exe;
      return ProcessResult(0, 1, '', '');
    };
    final f = await makeTempFile();
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    try {
      await pumpHost(t, success: true, message: '已匯出至 ${f.path}', revealPath: f.path);
      await t.tap(find.text(l.actionClose));
      await t.pumpAndSettle();

      expect(find.text(l.actionClose), findsNothing);
      expect(capturedExe, isNull);
    } finally {
      if (await f.exists()) await f.delete();
    }
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/dialogs/export_result_dialog_test.dart`
Expected: 編譯失敗 — `export_result_dialog.dart` 不存在 / `showExportResultDialog` 未定義。

- [ ] **Step 3: 寫最小實作**

建立 `lib/widgets/dialogs/export_result_dialog.dart`：

```dart
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 匯出結果統一彈窗：取代原本的 SnackBar + 自動開檔案總管。
///
/// - [success] 決定標題（成功／失敗）。
/// - [message] dialog 內文（呼叫端已在地化好的完整訊息）。
/// - [revealPath] 有值才顯示「開啟資料夾」鈕，點下去以
///   [revealInFileManager] 開檔案總管並選中該檔案；無值（如分享圖
///   copiedOnly、或失敗）則只有「關閉」鈕。
Future<void> showExportResultDialog(
  BuildContext context, {
  required bool success,
  required String message,
  String? revealPath,
}) {
  final l = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AppDialog(
      title: Text(
        success ? l.exportDialogSuccessTitle : l.exportDialogFailedTitle,
      ),
      content: Text(message),
      actions: [
        if (revealPath != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(revealInFileManager(revealPath));
            },
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(l.actionOpenFolder),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.actionClose),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/dialogs/export_result_dialog_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交前檢查**

Run: `dart format lib/ test/` 然後 `flutter analyze`
Expected: `flutter analyze` → `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/dialogs/export_result_dialog.dart test/widgets/dialogs/export_result_dialog_test.dart
git commit -m "feat(dialog): add showExportResultDialog shared helper"
```

---

### Task 3: 分享圖片流程改用 helper、刪除 share_result_snackbar

**Files:**
- Modify: `lib/widgets/share/share_image_helper.dart`
- Delete: `lib/widgets/share/share_result_snackbar.dart`

- [ ] **Step 1: 改寫 `share_image_helper.dart`**

把 import 區塊裡這行：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_result_snackbar.dart';
```

改為：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
```

在 `final _log = Logger('share.image');` 之後、`Widget buildShareRenderTree(` 之前，新增 status→dialog 參數的 private mapping（沿用原 `share_result_snackbar.dart` 的 switch；`copiedOnly` 不帶 path）：

```dart
/// 把 [ShareExportResult] 攤平成 dialog 需要的訊息與 reveal 路徑。
/// copiedOnly 只進剪貼簿、無檔案，故 revealPath 為 null。
({String message, String? revealPath}) _shareResultToDialog(
  AppLocalizations l,
  ShareExportResult r,
) {
  switch (r.status) {
    case ShareExportStatus.savedAndCopied:
      return (message: l.shareImageSavedAndCopied(r.path ?? ''), revealPath: r.path);
    case ShareExportStatus.savedOnly:
      return (message: l.shareImageSavedOnly(r.path ?? ''), revealPath: r.path);
    case ShareExportStatus.copiedOnly:
      return (message: l.shareImageCopiedOnly, revealPath: null);
  }
}
```

把 `generateAndShareImage` 內這段：

```dart
  final messenger = ScaffoldMessenger.of(context);
  final brightness = Theme.of(context).brightness;
```

改為（移除不再需要的 `messenger`）：

```dart
  final brightness = Theme.of(context).brightness;
```

把 try/catch 區塊：

```dart
  try {
    final png = await renderWidgetToPng(
      buildShareRenderTree(
        card: buildCard(icon, options),
        brightness: options.brightness,
        locale: locale,
      ),
      width: kShareCardWidth,
    );
    final result = await exportShareImage(png, suggestedName: suggestedName);
    showShareResultSnackBar(messenger, l, result);
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    messenger.showSnackBar(SnackBar(content: Text(l.shareImageFailed)));
  } finally {
    icon.dispose();
  }
```

改為：

```dart
  try {
    final png = await renderWidgetToPng(
      buildShareRenderTree(
        card: buildCard(icon, options),
        brightness: options.brightness,
        locale: locale,
      ),
      width: kShareCardWidth,
    );
    final result = await exportShareImage(png, suggestedName: suggestedName);
    if (!context.mounted) return;
    final m = _shareResultToDialog(l, result);
    await showExportResultDialog(
      context,
      success: true,
      message: m.message,
      revealPath: m.revealPath,
    );
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    if (!context.mounted) return;
    await showExportResultDialog(
      context,
      success: false,
      message: l.shareImageFailed,
    );
  } finally {
    icon.dispose();
  }
```

> `_shareResultToDialog` 用到 `ShareExportResult` / `ShareExportStatus`，這兩個型別來自既有 import `share_image_export.dart`（檔案已 import，勿重複）。

- [ ] **Step 2: 刪除 `share_result_snackbar.dart`**

```bash
git rm lib/widgets/share/share_result_snackbar.dart
```

- [ ] **Step 3: 確認無其他引用殘留**

Run: `flutter analyze`
Expected: `No issues found!`（若報 `share_result_snackbar` 找不到，表示還有別處 import 未清，需修正後再跑）

- [ ] **Step 4: 跑測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: 提交前檢查**

Run: `dart format lib/ test/` 然後 `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/share_image_helper.dart
git commit -m "feat(share): show export result dialog instead of snackbar+reveal"
```

---

### Task 4: 帳號匯出補 try/catch 並改用 helper

**Files:**
- Modify: `lib/pages/settings_page.dart`（帳號匯出 `_export`，約 L368-443；寫檔在約 L433-442）

- [ ] **Step 1: 新增 import**

於 `lib/pages/settings_page.dart` import 區塊，加入兩行（與既有 import 同區、依字母序大致就近放）：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
```

- [ ] **Step 2: 改寫帳號匯出寫檔與成功／失敗處理**

把帳號匯出 `_export` 內這段（約 L433-442，`exportAccounts(...)` 之後）：

```dart
    await File(loc.path).writeAsString(text);
    Logger('accounts.io').info(
      'export: uids=${pickedSet.length} '
      'records=${filteredByUid.values.fold<int>(0, (a, b) => a + b.allRecords.length)}',
    );
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(l.settingsExportSuccess(loc.path))));
    unawaited(revealInFileManager(loc.path));
```

改為：

```dart
    try {
      await File(loc.path).writeAsString(text);
    } catch (e, st) {
      Logger('accounts.io').severe(
        'export failed ${sanitizeFsPath(loc.path)}',
        e,
        st,
      );
      if (!ctx.mounted) return;
      await showExportResultDialog(
        ctx,
        success: false,
        message: l.settingsExportFailed(e.toString()),
      );
      return;
    }
    Logger('accounts.io').info(
      'export: uids=${pickedSet.length} '
      'records=${filteredByUid.values.fold<int>(0, (a, b) => a + b.allRecords.length)}',
    );
    if (!ctx.mounted) return;
    await showExportResultDialog(
      ctx,
      success: true,
      message: l.settingsExportSuccess(loc.path),
      revealPath: loc.path,
    );
```

- [ ] **Step 3: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`
（此時 Logs 匯出仍用 `unawaited(revealInFileManager(...))`，故 `dart:async show unawaited` 尚未變未使用；Task 5 才移除該 import。）

- [ ] **Step 4: 跑測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: 提交前檢查**

Run: `dart format lib/ test/` 然後 `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): account export uses result dialog with failure handling"
```

---

### Task 5: Logs 匯出補 try/catch 並改用 helper、清理未使用 import

**Files:**
- Modify: `lib/pages/settings_page.dart`（Logs 匯出 `_export`，約 L681-714；寫檔在約 L705-713）

- [ ] **Step 1: 改寫 Logs 匯出寫檔與成功／失敗處理**

把 Logs 匯出 `_export` 內這段（約 L705-713）：

```dart
    await File(loc.path).writeAsString(bundle);
    Logger(
      'accounts.io',
    ).info('logs exported: ${loc.path} (${bundle.length} bytes)');
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsLogsExportSuccess(loc.path))),
    );
    unawaited(revealInFileManager(loc.path));
```

改為：

```dart
    try {
      await File(loc.path).writeAsString(bundle);
    } catch (e, st) {
      Logger('accounts.io').severe(
        'logs export failed ${sanitizeFsPath(loc.path)}',
        e,
        st,
      );
      if (!ctx.mounted) return;
      await showExportResultDialog(
        ctx,
        success: false,
        message: l.settingsLogsExportFailed(e.toString()),
      );
      return;
    }
    Logger(
      'accounts.io',
    ).info('logs exported: ${loc.path} (${bundle.length} bytes)');
    if (!ctx.mounted) return;
    await showExportResultDialog(
      ctx,
      success: true,
      message: l.settingsLogsExportSuccess(loc.path),
      revealPath: loc.path,
    );
```

- [ ] **Step 2: 移除已不再使用的 `unawaited` import**

`revealInFileManager` 已不再由 settings_page 直接呼叫（兩處都已移除），`unawaited` 無其他使用。刪除 `lib/pages/settings_page.dart` 第 2 行：

```dart
import 'dart:async' show unawaited;
```

> 注意：`import file_reveal.dart` 仍要保留 — `_openFolder` 還在用 `openFolder`。

- [ ] **Step 3: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`（不得有 unused import 警告）

- [ ] **Step 4: 跑測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: 提交前檢查**

Run: `dart format lib/ test/` 然後 `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): logs export uses result dialog with failure handling"
```

---

### Task 6: 全套驗證

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 無待格式化變更（或自動套用後 git diff 乾淨）

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`
（若 `log_service` / `app_release_checker` 平行偶發失敗，單獨重跑該檔確認綠即非回歸。）

- [ ] **Step 4: 確認三流程無殘留舊行為**

Run: `grep -rn "showShareResultSnackBar\|share_result_snackbar" lib test`
Expected: 無輸出（已全部移除）。

---

## Self-Review 紀錄

- **Spec 覆蓋**：共用 helper（Task 2）、reveal 沿用 `revealInFileManager`（helper Step 3）、`copiedOnly` 無路徑隱藏鈕（Task 3 mapping + Task 2 測試）、成功+失敗皆 dialog（Task 3/4/5）、l10n 4 語系新 key（Task 1）、失敗埋 `severe` log 經 `sanitizeFsPath`（Task 4/5）、測試（Task 2）。皆有對應 task。
- **Placeholder 掃描**：無 TBD／TODO，所有 code step 附完整程式碼。
- **型別一致**：`showExportResultDialog(context, {required bool success, required String message, String? revealPath})` 在 Task 2 定義，Task 3/4/5 呼叫簽章一致；`_shareResultToDialog` 回傳 record `({String message, String? revealPath})` 與呼叫端解構一致。
