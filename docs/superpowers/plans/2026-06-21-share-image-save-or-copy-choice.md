# Share Image Save-or-Copy Choice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users explicitly choose «複製圖片» or «儲存圖片» in the share-image dialog instead of forcing copy-then-save together.

**Architecture:** The share dialog returns both the render options and a chosen `ShareImageAction`. The helper renders the PNG behind a blocking progress dialog, then routes to the existing `copyImagePngToClipboard` / `saveImagePng` services via an isolated, unit-testable `exportRenderedShareImage` step. The old combined `exportShareImage` service is deleted.

**Tech Stack:** Flutter / Dart, flutter_riverpod, file_selector, super_clipboard, ARB l10n (gen-l10n).

## Global Constraints

- 指令一律優先用 `fvm`：`fvm flutter analyze`、`fvm flutter test`、`fvm flutter gen-l10n`、`fvm dart format lib/ test/`（找不到 `fvm` 才退回 `flutter`／`dart`）。
- 提交前依序通過：`fvm dart format lib/ test/` → `fvm flutter analyze`（必須 `No issues found!`）→ `fvm flutter test`（必須 `All tests passed!`）。
- 所有宣告（含 private `_xxx`）寫一行 `///` dartdoc；Flutter override（`build` 等簽名自明者）不寫。
- CJK 標點全形（註解、dartdoc、ARB UI 文字）；**省略號一律半形 `...`**（含 CJK）。
- Commit message 一律英文、conventional commits 格式、半形標點。
- i18n：模板為 `lib/l10n/app_zh.arb`；新字串只加在**已有實體翻譯**的 9 個 ARB（`app_zh`、`app_zh_Hans`、`app_en`、`app_ja`、`app_fr`、`app_es`、`app_pt_BR`、`app_th`、`app_vi`），空殼 ARB 留給 Crowdin pipeline，不主動補。
- 關鍵節點埋 `Logger('share.image')` log，敏感資料經 `sanitizeFsPath` 後寫入。
- Dialog 一律用 `AppDialog`；不要手寫 `AlertDialog` + `ConstrainedBox`。
- 不主動 `git push`。

---

## File Structure

| 檔案 | 責任 | 變更 |
| --- | --- | --- |
| `lib/models/share_image_options.dart` | 分享圖選項資料 | 新增 `ShareImageAction` enum |
| `lib/widgets/dialogs/share_image_dialog.dart` | 分享圖設定 dialog | 三按鈕、回傳 record |
| `lib/widgets/dialogs/share_progress_dialog.dart` | 渲染進度 dialog | 新增 |
| `lib/widgets/share/share_image_helper.dart` | 分享圖流程編排 | 加 `exportRenderedShareImage`、改 `generateAndShareImage`、移除 `_shareResultToDialog` |
| `lib/services/share_image_export.dart` | 舊組合層 | **刪除** |
| `lib/l10n/app_*.arb`（9 個翻譯檔） | UI 文字 | 加 5 字串、移除 3 字串 |
| `test/widgets/dialogs/share_image_dialog_test.dart` | dialog 測試 | 更新 |
| `test/widgets/dialogs/share_progress_dialog_test.dart` | 進度 dialog 測試 | 新增 |
| `test/widgets/share/share_image_export_routing_test.dart` | 動作路由測試 | 新增 |
| `test/services/share_image_export_test.dart` | 舊組合層測試 | **刪除** |

---

## Task 1: Add new ARB strings

**Files:**
- Modify: `lib/l10n/app_zh.arb`（模板，含 `@` placeholder metadata）
- Modify: `lib/l10n/app_zh_Hans.arb`, `app_en.arb`, `app_ja.arb`, `app_fr.arb`, `app_es.arb`, `app_pt_BR.arb`, `app_th.arb`, `app_vi.arb`

**Interfaces:**
- Produces: 新的 `AppLocalizations` getter：`shareImageActionCopy`、`shareImageActionSave`、`shareImageCopyFailed`、`shareImageGenerating`、`shareImageSaved(String path)`。

只新增、不移除（移除留到 Task 5，確保每個任務之間都能編譯通過）。

- [ ] **Step 1: 在 `app_zh.arb` 的 `"shareImageFailed"` 那一行之後插入新字串**

於 `"shareImageFailed": "分享圖生成失敗",`（約 line 486）下一行插入：

```json
  "shareImageActionCopy": "複製圖片",
  "shareImageActionSave": "儲存圖片",
  "shareImageCopyFailed": "複製到剪貼簿失敗",
  "shareImageGenerating": "正在生成分享圖...",
  "shareImageSaved": "已儲存：{path}",
  "@shareImageSaved": {
    "placeholders": { "path": { "type": "String" } }
  },
```

- [ ] **Step 2: 在其餘 8 個 ARB 的 `"shareImageFailed"` 之後插入相同 key（文字依下表，`shareImageSaved` 的 `@` metadata 區塊每檔都要帶）**

| 檔案 | shareImageActionCopy | shareImageActionSave | shareImageCopyFailed | shareImageGenerating | shareImageSaved |
| --- | --- | --- | --- | --- | --- |
| `app_zh_Hans` | 复制图片 | 保存图片 | 复制到剪贴板失败 | 正在生成分享图... | 已保存：{path} |
| `app_en` | Copy image | Save image | Failed to copy to clipboard | Generating share image... | Saved: {path} |
| `app_ja` | 画像をコピー | 画像を保存 | クリップボードへのコピーに失敗しました | シェア画像を生成中... | 保存しました：{path} |
| `app_fr` | Copier l'image | Enregistrer l'image | Échec de la copie dans le presse-papiers | Génération de l'image de partage... | Enregistré : {path} |
| `app_es` | Copiar imagen | Guardar imagen | Error al copiar al portapapeles | Generando imagen para compartir... | Guardado: {path} |
| `app_pt_BR` | Copiar imagem | Salvar imagem | Falha ao copiar para a área de transferência | Gerando imagem para compartilhar... | Salvo: {path} |
| `app_th` | คัดลอกภาพ | บันทึกภาพ | คัดลอกไปยังคลิปบอร์ดล้มเหลว | กำลังสร้างภาพแชร์... | บันทึกแล้ว: {path} |
| `app_vi` | Sao chép ảnh | Lưu ảnh | Sao chép vào clipboard thất bại | Đang tạo ảnh chia sẻ... | Đã lưu: {path} |

各檔插入格式範例（以 `app_en` 為例）：

```json
  "shareImageActionCopy": "Copy image",
  "shareImageActionSave": "Save image",
  "shareImageCopyFailed": "Failed to copy to clipboard",
  "shareImageGenerating": "Generating share image...",
  "shareImageSaved": "Saved: {path}",
  "@shareImageSaved": {
    "placeholders": { "path": { "type": "String" } }
  },
```

- [ ] **Step 3: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `shareImageActionCopy` / `shareImageSaved` 等 getter。

- [ ] **Step 4: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`（既有對舊 key 的引用仍在，仍可編譯）。

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "i18n(share): add save/copy action and progress strings"
```

---

## Task 2: `ShareImageAction` enum + three-button dialog

**Files:**
- Modify: `lib/models/share_image_options.dart`
- Modify: `lib/widgets/dialogs/share_image_dialog.dart`
- Test: `test/widgets/dialogs/share_image_dialog_test.dart`

**Interfaces:**
- Consumes: `shareImageActionCopy` / `shareImageActionSave`（Task 1）。
- Produces:
  - `enum ShareImageAction { copy, save }`（in `share_image_options.dart`）。
  - `Future<({ShareImageOptions options, ShareImageAction action})?> showShareImageDialog(BuildContext context, {required Brightness initialBrightness})`。

- [ ] **Step 1: 改測試 `share_image_dialog_test.dart` 為三按鈕版本（先讓它失敗）**

整檔替換為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';

void main() {
  Future<({ShareImageOptions options, ShareImageAction action})?>? captured;

  Widget host() => MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => captured = showShareImageDialog(
              ctx,
              initialBrightness: Brightness.dark,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('複製圖片回傳 copy + 預設選項', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.shareImageActionCopy));
    await t.pumpAndSettle();

    final r = await captured!;
    expect(r, isNotNull);
    expect(r!.action, ShareImageAction.copy);
    expect(r.options.brightness, Brightness.dark);
    expect(r.options.showFullUid, isFalse);
  });

  testWidgets('儲存圖片回傳 save', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.shareImageActionSave));
    await t.pumpAndSettle();

    final r = await captured!;
    expect(r, isNotNull);
    expect(r!.action, ShareImageAction.save);
  });

  testWidgets('取消回傳 null', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.actionCancel));
    await t.pumpAndSettle();

    expect(await captured!, isNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/share_image_dialog_test.dart`
Expected: FAIL（`ShareImageAction` 未定義、`showShareImageDialog` 回傳型別不符）。

- [ ] **Step 3: 在 `share_image_options.dart` 新增 enum**

於檔尾 `ShareImageOptions` class 之後加入：

```dart
/// 分享圖輸出動作：複製到剪貼簿或存檔。
enum ShareImageAction {
  /// 複製分享圖到系統剪貼簿。
  copy,

  /// 將分享圖存檔到使用者選擇的位置。
  save,
}
```

- [ ] **Step 4: 改寫 `share_image_dialog.dart`**

整檔替換為：

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開啟分享圖設定 dialog。回傳使用者選定的選項與動作；null 表示取消。
Future<({ShareImageOptions options, ShareImageAction action})?>
showShareImageDialog(
  BuildContext context, {
  required Brightness initialBrightness,
}) {
  return showDialog<({ShareImageOptions options, ShareImageAction action})>(
    context: context,
    builder: (_) => _ShareImageDialog(initialBrightness: initialBrightness),
  );
}

/// 分享圖設定 dialog 的實作 widget。
class _ShareImageDialog extends StatefulWidget {
  const _ShareImageDialog({required this.initialBrightness});

  /// 初始亮暗模式，通常取自目前 app 主題。
  final Brightness initialBrightness;

  @override
  State<_ShareImageDialog> createState() => _ShareImageDialogState();
}

/// State for [_ShareImageDialog]；管理使用者選擇的分享圖選項。
class _ShareImageDialogState extends State<_ShareImageDialog> {
  /// 目前選擇的分享圖亮暗模式。
  late Brightness _brightness = widget.initialBrightness;

  /// 是否在分享圖中顯示完整 UID（預設遮蔽後四碼）。
  bool _showFullUid = false;

  /// 以目前選項建立 [ShareImageOptions]。
  ShareImageOptions _currentOptions() =>
      ShareImageOptions(brightness: _brightness, showFullUid: _showFullUid);

  /// 帶著選定 [action] 與目前選項關閉 dialog。
  void _pop(ShareImageAction action) => Navigator.of(context).pop((
    options: _currentOptions(),
    action: action,
  ));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      size: AppDialogSize.sm,
      title: Text(l.shareImageDialogTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.shareImageThemeLabel),
          const SizedBox(height: AppSpacing.s),
          SegmentedButton<Brightness>(
            segments: [
              ButtonSegment(
                value: Brightness.dark,
                label: Text(l.shareImageThemeDark),
              ),
              ButtonSegment(
                value: Brightness.light,
                label: Text(l.shareImageThemeLight),
              ),
            ],
            selected: {_brightness},
            onSelectionChanged: (s) => setState(() => _brightness = s.first),
          ),
          const SizedBox(height: AppSpacing.l),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showFullUid,
            onChanged: (v) => setState(() => _showFullUid = v),
            title: Text(l.shareImageShowFullUid),
            subtitle: Text(l.shareImageShowFullUidHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        TextButton(
          onPressed: () => _pop(ShareImageAction.copy),
          child: Text(l.shareImageActionCopy),
        ),
        FilledButton(
          onPressed: () => _pop(ShareImageAction.save),
          child: Text(l.shareImageActionSave),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/share_image_dialog_test.dart`
Expected: PASS（注意：此時 `share_image_helper.dart` 仍用舊回傳型別，全專案 analyze 會紅 — Task 4 修。本步驟只跑此測試檔。）

- [ ] **Step 6: Commit**

```bash
git add lib/models/share_image_options.dart lib/widgets/dialogs/share_image_dialog.dart test/widgets/dialogs/share_image_dialog_test.dart
git commit -m "feat(share): add copy/save action choice to share dialog"
```

---

## Task 3: Render progress dialog

**Files:**
- Create: `lib/widgets/dialogs/share_progress_dialog.dart`
- Test: `test/widgets/dialogs/share_progress_dialog_test.dart`

**Interfaces:**
- Consumes: `shareImageGenerating`（Task 1）。
- Produces: `void showShareProgressDialog(BuildContext context)` — 顯示非可關閉進度 dialog；由呼叫端以 `Navigator.of(context, rootNavigator: true).pop()` 關閉。

- [ ] **Step 1: 寫失敗測試 `share_progress_dialog_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_progress_dialog.dart';

void main() {
  Widget host() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showShareProgressDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('顯示 LinearProgressIndicator 與進度文字', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l.shareImageGenerating), findsOneWidget);
  });

  testWidgets('可由呼叫端以 Navigator.pop 關閉', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final ctx = t.element(find.byType(LinearProgressIndicator));
    Navigator.of(ctx, rootNavigator: true).pop();
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/share_progress_dialog_test.dart`
Expected: FAIL（`showShareProgressDialog` 未定義）。

- [ ] **Step 3: 建立 `share_progress_dialog.dart`**

```dart
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示分享圖渲染進度的非可關閉 dialog（含 [LinearProgressIndicator]）。
///
/// 不 await；渲染只跑一次同步 pipeline，故由呼叫端在渲染完成或失敗後以
/// `Navigator.of(context, rootNavigator: true).pop()` 主動關閉。barrierDismissible
/// 與 [PopScope] 皆設為不可關閉，避免使用者在渲染中誤關。
void showShareProgressDialog(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AppDialog(
          title: Text(l.shareImageGenerating),
          content: const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: LinearProgressIndicator(),
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/share_progress_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dialogs/share_progress_dialog.dart test/widgets/dialogs/share_progress_dialog_test.dart
git commit -m "feat(share): add blocking render progress dialog"
```

---

## Task 4: Helper action routing + delete old export service

**Files:**
- Modify: `lib/widgets/share/share_image_helper.dart`
- Delete: `lib/services/share_image_export.dart`
- Delete: `test/services/share_image_export_test.dart`
- Test: `test/widgets/share/share_image_export_routing_test.dart`

**Interfaces:**
- Consumes: `ShareImageAction`、新 `showShareImageDialog` 回傳 record（Task 2）；`showShareProgressDialog`（Task 3）；既有 `copyImagePngToClipboard(Uint8List)` / `saveImagePng(Uint8List, {required String suggestedName})`（`image_clipboard_save.dart`）；`shareImageCopiedOnly` / `shareImageCopyFailed` / `shareImageSaved` / `shareImageFailed`。
- Produces: `Future<void> exportRenderedShareImage({required BuildContext context, required AppLocalizations l, required ShareImageAction action, required Uint8List png, required String suggestedName})`；`generateAndShareImage` 簽名不變（呼叫端 `overview_page` / `banner_page` 無需改）。

- [ ] **Step 1: 寫失敗測試 `share_image_export_routing_test.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  Widget host(ShareImageAction action) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => exportRenderedShareImage(
              context: ctx,
              l: AppLocalizations.of(ctx)!,
              action: action,
              png: png,
              suggestedName: 'a.png',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  testWidgets('copy 成功 → 跳已複製到剪貼簿', (t) async {
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => true;
    await t.pumpWidget(host(ShareImageAction.copy));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageCopiedOnly), findsOneWidget);
  });

  testWidgets('copy 失敗 → 跳複製失敗', (t) async {
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => false;
    await t.pumpWidget(host(ShareImageAction.copy));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageCopyFailed), findsOneWidget);
  });

  testWidgets('save 成功 → 跳已儲存且有開資料夾', (t) async {
    final tmp = '${Directory.systemTemp.path}/share_route_a.png';
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    await t.pumpWidget(host(ShareImageAction.save));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageSaved(tmp)), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsOneWidget);
    expect(await File(tmp).readAsBytes(), png);
    await File(tmp).delete();
  });

  testWidgets('save 取消 → 不跳任何結果 dialog', (t) async {
    imageSaveLocationPicker = (name) async => null;
    await t.pumpWidget(host(ShareImageAction.save));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.exportDialogSuccessTitle), findsNothing);
    expect(find.text(l.exportDialogFailedTitle), findsNothing);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/share/share_image_export_routing_test.dart`
Expected: FAIL（`exportRenderedShareImage` 未定義）。

- [ ] **Step 3: 改寫 `share_image_helper.dart`**

替換 import 區（移除 `share_image_export.dart`、`export_result_dialog.dart` 保留，新增 `image_clipboard_save.dart`、`share_progress_dialog.dart`）。整檔替換為：

```dart
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_progress_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

/// 分享圖流程的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 建構離屏渲染用的 widget 樹（含 Localizations，使重用的 RarityPie/ItemTypePie
/// 內部 AppLocalizations.of(context) 能在同步 flush 內解析）。
///
/// 只放同步載入的 delegate：AppLocalizations.delegate 透過 SynchronousFuture
/// 載入，Default*Localizations 也都同步；離屏渲染只跑一次同步 pipeline flush，
/// 用 AppLocalizations.localizationsDelegates（含 Global*，可能 async）會來不及
/// 解析而導致畫面空白。
///
/// [container] 為 Riverpod ProviderContainer；離屏 pipeline 是獨立樹，需透過
/// [UncontrolledProviderScope] 顯式傳入，否則 tree 內 [ConsumerWidget]（如
/// [GachaItemIcon]）無法查到 providers。生產端從呼叫 Widget 的 ref 取得，
/// 測試端自行建立並注入。
Widget buildShareRenderTree({
  required Widget card,
  required Brightness brightness,
  required Locale locale,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: locale,
        delegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Theme(
            data: brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
            child: Material(
              type: MaterialType.transparency,
              // Overlay 補齊 TimelineVertical 內 Tooltip 所需的 Overlay 祖先；
              // 離屏為 RenderView tight constraints，opaque entry 會填滿畫布。
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    opaque: true,
                    maintainState: true,
                    // 離屏渲染給 unbounded 高度約束以達高度自適應；此非定位
                    // entry 設 canSizeOverlay 後，Overlay 會以它（即 ShareCard）
                    // 的自然高決定自身高度（見 share_image_renderer.dart）。
                    canSizeOverlay: true,
                    builder: (_) => card,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 依 [action] 把已渲染的 [png] 複製或儲存，並顯示結果 dialog。
///
/// copy：成功與失敗皆跳結果 dialog（[shareImageCopiedOnly] / [shareImageCopyFailed]）。
/// save：成功跳結果 dialog（[shareImageSaved] 附開資料夾）；使用者取消選路徑則靜默；
/// 寫檔失敗由 [saveImagePng] rethrow，交由呼叫端（[generateAndShareImage]）處理。
Future<void> exportRenderedShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required ShareImageAction action,
  required Uint8List png,
  required String suggestedName,
}) async {
  switch (action) {
    case ShareImageAction.copy:
      final ok = await copyImagePngToClipboard(png);
      _log.info('share image copy clipboard=$ok bytes=${png.length}');
      if (!context.mounted) return;
      await showExportResultDialog(
        context,
        success: ok,
        message: ok ? l.shareImageCopiedOnly : l.shareImageCopyFailed,
      );
    case ShareImageAction.save:
      final path = await saveImagePng(png, suggestedName: suggestedName);
      if (path == null) {
        _log.info('share image save cancelled');
        return;
      }
      if (!context.mounted) return;
      await showExportResultDialog(
        context,
        success: true,
        message: l.shareImageSaved(path),
        revealPath: path,
      );
  }
}

/// 跑完整分享圖流程。[buildCard] 收已載入的 icon、選項，回傳 ShareCard。
/// 分享圖寬固定為 [kShareCardWidth]、高隨內容自適應（底部不留白、不裁切）；
/// [suggestedName] 完整建議檔名（含時間戳）。
/// [recordsForPreload] 用於 sync pipeline 前預解碼 hoyowiki icon。
/// overview 與 banner 兩頁共用，避免重複骨架。
Future<void> generateAndShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required String suggestedName,
  required Iterable<GachaRecord> recordsForPreload,
  required Widget Function(ui.Image icon, ShareImageOptions options) buildCard,
}) async {
  final brightness = Theme.of(context).brightness;
  final locale = Localizations.localeOf(context);
  final choice = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (choice == null) return;
  if (!context.mounted) return;

  final container = ProviderScope.containerOf(context);
  final hoyowikiIndex = container.read(hoyowikiIndexProvider);
  final cacheDir = container.read(hoyowikiCacheDirProvider);
  final icon = await loadAppIconImage();
  final preloaded = await preloadHoYoWikiImages(
    index: hoyowikiIndex,
    cacheDir: cacheDir,
    records: recordsForPreload,
  );

  if (!context.mounted) {
    icon.dispose();
    disposePreloadedHoYoWikiImages(preloaded);
    return;
  }
  // 進度 dialog 只覆蓋渲染這段；render 完成或失敗後即關閉，再進入複製／存檔，
  // 避免遮住系統存檔對話框。progressOpen 防止 catch 分支重複 pop。
  showShareProgressDialog(context);
  var progressOpen = true;
  try {
    final png = await renderWidgetToPng(
      buildShareRenderTree(
        card: PreloadedHoYoWikiImages(
          images: preloaded,
          child: buildCard(icon, choice.options),
        ),
        brightness: choice.options.brightness,
        locale: locale,
        container: container,
      ),
      width: kShareCardWidth,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
    if (!context.mounted) return;
    await exportRenderedShareImage(
      context: context,
      l: l,
      action: choice.action,
      png: png,
      suggestedName: suggestedName,
    );
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    if (progressOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    await showExportResultDialog(
      context,
      success: false,
      message: l.shareImageFailed,
    );
  } finally {
    icon.dispose();
    disposePreloadedHoYoWikiImages(preloaded);
  }
}
```

- [ ] **Step 4: 刪除舊組合層與其測試**

```bash
git rm lib/services/share_image_export.dart test/services/share_image_export_test.dart
```

- [ ] **Step 5: 跑路由測試與全專案分析**

Run: `fvm flutter test test/widgets/share/share_image_export_routing_test.dart`
Expected: PASS

Run: `fvm flutter analyze`
Expected: `No issues found!`（`shareImageGenerate` / `shareImageSavedAndCopied` / `shareImageSavedOnly` 已無人引用，但仍存在於 ARB，不影響編譯。）

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/share_image_helper.dart test/widgets/share/share_image_export_routing_test.dart
git commit -m "feat(share): route share image to copy or save by action"
```

---

## Task 5: Remove obsolete ARB strings

**Files:**
- Modify: 9 個翻譯 ARB（`app_zh`、`app_zh_Hans`、`app_en`、`app_ja`、`app_fr`、`app_es`、`app_pt_BR`、`app_th`、`app_vi`）

**Interfaces:**
- Consumes: 無（純清理）。確認 Task 2／4 後 `shareImageGenerate`、`shareImageSavedAndCopied`、`shareImageSavedOnly` 已無程式碼引用。

- [ ] **Step 1: 確認無殘留引用**

Run: `grep -rn "shareImageGenerate\b\|shareImageSavedAndCopied\|shareImageSavedOnly" lib/ test/`
Expected: 僅出現在 `lib/l10n/*.arb`（無 `.dart` 引用）。

- [ ] **Step 2: 從 9 個 ARB 移除以下 key（連同其 `@` metadata 區塊）**

每檔移除：
- `"shareImageGenerate": ...,`
- `"shareImageSavedAndCopied": ...,` 與 `"@shareImageSavedAndCopied": { ... },`
- `"shareImageSavedOnly": ...,` 與 `"@shareImageSavedOnly": { ... },`

保留 `shareImageCopiedOnly`、`shareImageFailed`、`shareImageButton`、`shareImageDialogTitle` 等其餘 `shareImage*`。

- [ ] **Step 3: 重新產生 l10n 並分析**

Run: `fvm flutter gen-l10n && fvm flutter analyze`
Expected: 無錯誤；`No issues found!`（generated 檔不再有 `shareImageGenerate` 等 getter，且無人引用）。

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "i18n(share): remove obsolete combined save-and-copy strings"
```

---

## Task 6: Full verification

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 無未格式化檔（或自動套用後無 diff 問題）。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: Commit（若 format 有變更）**

```bash
git add -A
git commit -m "style(share): apply dart format"
```

---

## Self-Review Notes

- **Spec coverage：** 三按鈕 dialog（Task 2）、ShareImageAction 與回傳 record（Task 2）、重用 `copyImagePngToClipboard`/`saveImagePng` 並刪 `exportShareImage`（Task 4）、進度 dialog（Task 3）、結果回饋表（Task 4 路由 + 測試）、i18n 增刪（Task 1／5）、測試（各 Task）、log（Task 4）。皆有對應任務。
- **儲存用詞：** 統一「儲存」— 按鈕 `shareImageActionSave`=「儲存圖片」、訊息 `shareImageSaved`=「已儲存」；舊「已存檔」隨 `shareImageSavedOnly` 移除。
- **型別一致：** `showShareImageDialog` 回傳 `({ShareImageOptions options, ShareImageAction action})?`（Task 2）↔ helper 以 `choice.options` / `choice.action` 取用（Task 4）；`exportRenderedShareImage` 簽名於 Task 4 介面與測試一致。
- **綠燈順序：** Task 1 只加字串、Task 5 才移除舊字串，確保任務間皆可編譯；單檔測試在 Task 2/3/4 之間先綠，全專案 analyze 於 Task 4 後綠。
