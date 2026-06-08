# Item Detail Image Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `GachaItemDetailDialog` 中央圖片右上角加一個溢出選單（複製圖片 / 儲存圖片 / 重抓圖片），並支援在圖片上按右鍵叫出同一份選單。

**Architecture:** 把剪貼簿寫入、存檔選擇器、檔案寫入這三個原始操作抽到新共用模組 `image_clipboard_save.dart`（含可測 seam 與 `encodeImageFileToPng` / `copyImagePngToClipboard` / `saveImagePng`），既有 `share_image_export.dart` 改為複用同一份 seam。dialog 的 `_GalleryReady` 圖片區改為 `Stack`，疊上右上角 `PopupMenuButton`，並在底層 `GestureDetector` 加 `onSecondaryTapDown` 用 `showMenu` 叫出同一份選單；重抓依 chip 類別走既有 `_fetchAndCache`（gallery）或新增的 `_refetchIcon`（icon，含 `bumpCacheRevision`）。

**Tech Stack:** Flutter / Dart / Riverpod / `super_clipboard` / `file_selector` / `dart:ui` 圖片編碼 / `package:logging` / Crowdin-pipelined ARB i18n（template = `app_zh.arb`）。

> **Spec 對應**：`docs/superpowers/specs/2026-06-08-item-detail-image-menu-design.md`。
>
> **測試層次決策**：複製／儲存的剪貼簿與存檔 seam 在 **service 層**（`image_clipboard_save_test.dart`）完整覆蓋；dialog 層只驗證選單存在、右鍵叫出選單、重抓走 fetcher。原因：dialog 內圖片是測試用的假 PNG（4 bytes），`encodeImageFileToPng` 會解碼失敗回 null，無法在 widget 測試可靠驗證剪貼簿/存檔被呼叫；真實解碼放在 service 測試用一張合法 1×1 PNG 驗證。

---

## File Structure

| 動作 | 檔案 | 責任 |
|---|---|---|
| 新增 | `lib/services/image_clipboard_save.dart` | 共用剪貼簿/存檔/檔案寫入 seam + `encodeImageFileToPng` / `copyImagePngToClipboard` / `saveImagePng` |
| 修改 | `lib/services/share_image_export.dart` | 移除自身重複 primitive，`exportShareImage` 改用共用 seam；`resetShareImageExportSeams` 轉呼共用 reset |
| 修改 | `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | `_GalleryReady` 改 Stack + 右上角選單鈕 + 右鍵；新增選單/複製/儲存/重抓方法；失敗重試共用 `_refetchEntry` |
| 修改 | `lib/l10n/app_zh.arb`（template）、`lib/l10n/app_en.arb` | 新 i18n keys |
| 新增 | `test/services/image_clipboard_save_test.dart` | encode / copy / save 三組測試 |
| 修改 | `test/services/share_image_export_test.dart` | seam 名稱改用共用層 |
| 修改 | `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart` | 新增「圖片選單 + 重抓」group（重用既有 `_FakeFetcher` 基礎設施） |

---

### Task 1: 共用低階層 `image_clipboard_save.dart`

**Files:**
- Create: `lib/services/image_clipboard_save.dart`
- Test: `test/services/image_clipboard_save_test.dart`

- [ ] **Step 1: 寫失敗的測試**

Create `test/services/image_clipboard_save_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';

/// 合法的 1×1 透明 PNG，用來驗證 encodeImageFileToPng 真實解碼。
final _png1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, //
  0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, //
  0x0D, 0x0A, 0x2D, 0xB4, //
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  group('encodeImageFileToPng', () {
    testWidgets('合法 PNG 檔 → 非 null PNG bytes', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final f = File('${dir.path}/a.png')..writeAsBytesSync(_png1x1);
        final out = await encodeImageFileToPng(f);
        expect(out, isNotNull);
        expect(out!.isNotEmpty, isTrue);
      });
    });

    testWidgets('不存在的檔 → null', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final missing = File('${dir.path}/missing.png');
        expect(await encodeImageFileToPng(missing), isNull);
      });
    });

    testWidgets('壞檔（非圖片）→ null', (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('img_save_enc_');
        addTearDown(() async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
        final garbage = File('${dir.path}/g.png')..writeAsBytesSync([1, 2, 3, 4]);
        expect(await encodeImageFileToPng(garbage), isNull);
      });
    });
  });

  group('copyImagePngToClipboard', () {
    test('seam 回 true → true', () async {
      imageClipboardWriter = (b) async => true;
      expect(await copyImagePngToClipboard(png), isTrue);
    });

    test('seam 回 false → false', () async {
      imageClipboardWriter = (b) async => false;
      expect(await copyImagePngToClipboard(png), isFalse);
    });

    test('seam 拋例外 → false', () async {
      imageClipboardWriter = (b) async => throw Exception('boom');
      expect(await copyImagePngToClipboard(png), isFalse);
    });
  });

  group('saveImagePng', () {
    test('選了路徑並寫檔成功 → 回實際路徑', () async {
      final tmp = '${Directory.systemTemp.path}/img_save_out.png';
      imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
      final path = await saveImagePng(png, suggestedName: 'a.png');
      expect(path, tmp);
      expect(await File(tmp).readAsBytes(), png);
      await File(tmp).delete();
    });

    test('使用者取消 → null', () async {
      imageSaveLocationPicker = (name) async => null;
      expect(await saveImagePng(png, suggestedName: 'a.png'), isNull);
    });

    test('寫檔失敗 → rethrow', () async {
      imageSaveLocationPicker = (name) async => FileSaveLocation('/x/y.png');
      imageFileWriter = (p, b) async =>
          throw const FileSystemException('write fail');
      expect(
        () => saveImagePng(png, suggestedName: 'a.png'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/image_clipboard_save_test.dart`
Expected: 編譯失敗（`image_clipboard_save.dart` 不存在 / 符號未定義）。

- [ ] **Step 3: 寫實作**

Create `lib/services/image_clipboard_save.dart`:

```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 圖片複製／儲存流程的 logger（命名空間 gacha.hoyowiki.save）。
final _log = Logger('gacha.hoyowiki.save');

/// 把任意格式的本地圖檔解碼後重新編碼成 PNG bytes；任何失敗（讀檔／解碼／編碼）
/// 回 null，呼叫端據此提示失敗。
///
/// 統一輸出 PNG：來源 icon／gallery 副檔名隨 URL 可能是 webp／jpg，轉 PNG 後
/// 存檔與複製到剪貼簿格式一致。
Future<Uint8List?> encodeImageFileToPng(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) {
      _log.warning('encode png null path=${sanitizeFsPath(file.path)}');
      return null;
    }
    return data.buffer.asUint8List();
  } catch (e, st) {
    _log.warning('encode png failed path=${sanitizeFsPath(file.path)}', e, st);
    return null;
  }
}

/// 預設存檔位置選擇器：開啟系統 save dialog，回傳使用者選擇的路徑（取消為 null）。
Future<FileSaveLocation?> _defaultSaveLocationPicker(String name) =>
    getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );

/// 預設剪貼簿寫入：寫 PNG 到系統剪貼簿，回傳是否成功（平台不支援回 false）。
Future<bool> _defaultClipboardWriter(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem();
  item.add(Formats.png(png));
  await clipboard.write([item]);
  return true;
}

/// 預設檔案寫入實作：直接寫入磁碟。
Future<void> _defaultFileWriter(String path, Uint8List png) =>
    File(path).writeAsBytes(png);

/// 存檔位置選擇器 seam，讓 flutter test 不開啟真實系統 dialog。
@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
imageSaveLocationPicker = _defaultSaveLocationPicker;

/// 剪貼簿寫入 seam，讓 flutter test 不碰真實剪貼簿（SystemClipboard.instance 為 null）。
@visibleForTesting
Future<bool> Function(Uint8List png) imageClipboardWriter =
    _defaultClipboardWriter;

/// 檔案寫入 seam，讓 flutter test 不碰真實 FS。
@visibleForTesting
Future<void> Function(String path, Uint8List png) imageFileWriter =
    _defaultFileWriter;

/// 將所有 seam 重設為預設實作，供 tearDown 使用。
@visibleForTesting
void resetImageClipboardSaveSeams() {
  imageSaveLocationPicker = _defaultSaveLocationPicker;
  imageClipboardWriter = _defaultClipboardWriter;
  imageFileWriter = _defaultFileWriter;
}

/// 把 PNG 寫入系統剪貼簿。成功回 true；平台不支援回 false；例外記 warning 後回 false。
Future<bool> copyImagePngToClipboard(Uint8List png) async {
  try {
    final ok = await imageClipboardWriter(png);
    _log.info('copy image clipboard=$ok bytes=${png.length}');
    return ok;
  } catch (e, st) {
    _log.warning('copy image failed', e, st);
    return false;
  }
}

/// 讓使用者選位置存 PNG。成功回**實際存檔路徑**（供呼叫端在提示顯示完整路徑）；
/// 使用者取消回 null（非錯誤）；已選路徑但寫檔失敗會記 severe log 後 rethrow。
Future<String?> saveImagePng(
  Uint8List png, {
  required String suggestedName,
}) async {
  final loc = await imageSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled');
    return null;
  }
  try {
    await imageFileWriter(loc.path, png);
  } catch (e, st) {
    _log.severe('save image failed ${sanitizeFsPath(loc.path)}', e, st);
    rethrow;
  }
  _log.info('save image ok ${sanitizeFsPath(loc.path)} bytes=${png.length}');
  return loc.path;
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/services/image_clipboard_save_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/services/image_clipboard_save.dart test/services/image_clipboard_save_test.dart
git commit -m "feat(image-save): add shared clipboard/save service for item images"
```

---

### Task 2: 重構 `share_image_export.dart` 複用共用 seam

**Files:**
- Modify: `lib/services/share_image_export.dart`
- Test: `test/services/share_image_export_test.dart`

- [ ] **Step 1: 先改測試（改用共用 seam 名稱）**

把 `test/services/share_image_export_test.dart` 內所有 `shareSaveLocationPicker` 換成 `imageSaveLocationPicker`、`shareClipboardWriter` 換成 `imageClipboardWriter`，並新增 import。完整檔案：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetShareImageExportSeams);

  test('使用者選了路徑 + 剪貼簿成功 → saved', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_a.png';
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    imageClipboardWriter = (bytes) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.savedAndCopied);
    expect(r.path, tmp);
    expect(await File(tmp).readAsBytes(), png);
    await File(tmp).delete();
  });

  test('使用者取消存檔但剪貼簿成功 → copiedOnly', () async {
    imageSaveLocationPicker = (name) async => null;
    imageClipboardWriter = (bytes) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.copiedOnly);
    expect(r.path, isNull);
  });

  test('剪貼簿不支援但存檔成功 → savedOnly', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_b.png';
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    imageClipboardWriter = (bytes) async => false;

    final r = await exportShareImage(png, suggestedName: 'b.png');

    expect(r.status, ShareExportStatus.savedOnly);
    await File(tmp).delete();
  });

  test('剪貼簿失敗 + 使用者取消存檔 → copiedOnly', () async {
    imageSaveLocationPicker = (name) async => null;
    imageClipboardWriter = (bytes) async => false;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.copiedOnly);
    expect(r.path, isNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/services/share_image_export_test.dart`
Expected: 編譯失敗（`imageSaveLocationPicker` 等在 `share_image_export.dart` 重構前尚未被 share 流程使用；且 `resetShareImageExportSeams` 仍重設舊的私有 seam，與測試覆寫的共用 seam 不一致 → 行為錯）。實際會是編譯通過但測試失敗或型別不符；以「非全綠」為準。

- [ ] **Step 3: 重構實作**

把 `lib/services/share_image_export.dart` 改為：移除自身的 `_defaultClipboardWriter` / `_defaultSaveLocationPicker` / `_defaultFileWriter` 與 `shareClipboardWriter` / `shareSaveLocationPicker` / `shareFileWriter`，改用共用 seam。完整檔案：

```dart
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 分享圖匯出流程的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 分享圖匯出結果狀態：同時存檔+複製、僅存檔、僅複製三種情況。
enum ShareExportStatus {
  /// 同時存檔並複製到剪貼簿。
  savedAndCopied,

  /// 僅存檔（剪貼簿寫入失敗或平台不支援）。
  savedOnly,

  /// 僅複製到剪貼簿（使用者取消存檔）。
  copiedOnly,
}

/// 分享圖匯出結果，包含狀態與存檔路徑（僅存檔/同時存檔時不為 null）。
class ShareExportResult {
  /// 建立 [ShareExportResult]。
  const ShareExportResult({required this.status, this.path});

  /// 匯出結果狀態。
  final ShareExportStatus status;

  /// 存檔路徑；[ShareExportStatus.copiedOnly] 時為 null。
  final String? path;
}

/// 將所有 seam 重設為預設實作，供 tearDown 使用（轉呼共用層 reset）。
@visibleForTesting
void resetShareImageExportSeams() => resetImageClipboardSaveSeams();

/// 先寫剪貼簿（失敗不致命），再讓使用者選位置存檔（取消則只剩剪貼簿）。
///
/// 若使用者已選存檔路徑但寫入失敗，會記 severe log 後 rethrow `Exception`
/// （通常為 `FileSystemException`），由呼叫端負責處理（顯示錯誤）。
Future<ShareExportResult> exportShareImage(
  Uint8List png, {
  required String suggestedName,
}) async {
  bool copied;
  try {
    copied = await imageClipboardWriter(png);
  } catch (e, st) {
    _log.warning('clipboard write failed', e, st);
    copied = false;
  }

  final loc = await imageSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled; clipboard=$copied');
    return const ShareExportResult(status: ShareExportStatus.copiedOnly);
  }

  try {
    await imageFileWriter(loc.path, png);
  } catch (e, st) {
    _log.severe('share image write failed ${sanitizeFsPath(loc.path)}', e, st);
    rethrow;
  }
  _log.info(
    'share image saved ${sanitizeFsPath(loc.path)}; '
    'bytes=${png.length} clipboard=$copied',
  );
  return ShareExportResult(
    status: copied
        ? ShareExportStatus.savedAndCopied
        : ShareExportStatus.savedOnly,
    path: loc.path,
  );
}
```

- [ ] **Step 4: 確認沒有殘留呼叫舊 seam 名稱**

Run: `fvm flutter test test/services/share_image_export_test.dart`
Expected: All tests passed!

接著確認全專案無其他檔案還在用舊 seam 名稱（應只有測試與此檔）：
Run（用 Grep 工具或）: `git grep -n "shareClipboardWriter\|shareSaveLocationPicker\|shareFileWriter"`
Expected: 無輸出（或僅 plans 文件）。若有 lib 內呼叫，改為共用 seam。

- [ ] **Step 5: Commit**

```bash
git add lib/services/share_image_export.dart test/services/share_image_export_test.dart
git commit -m "refactor(share): reuse shared clipboard/save seams in share image export"
```

---

### Task 3: i18n keys

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template）
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: 在 `app_zh.arb` 加入新鍵**

在 `app_zh.arb` 最後一個鍵 `actionCloseImagePreview` 區塊之後、結尾 `}` 之前插入（注意前一個區塊結尾要補逗號）：

```json
,

  "actionCopyImage": "複製圖片",
  "@actionCopyImage": {
    "description": "Item detail dialog image menu: option that copies the currently shown image to the system clipboard as PNG."
  },

  "actionSaveImage": "儲存圖片",
  "@actionSaveImage": {
    "description": "Item detail dialog image menu: option that opens the system save dialog to save the currently shown image as PNG."
  },

  "actionRefetchImage": "重抓圖片",
  "@actionRefetchImage": {
    "description": "Item detail dialog image menu: option that re-downloads the currently shown image, overwriting the cached copy."
  },

  "imageCopied": "圖片已複製到剪貼簿",
  "@imageCopied": {
    "description": "Item detail dialog snackbar shown when the image is successfully copied to the clipboard."
  },

  "imageCopyFailed": "複製圖片失敗",
  "@imageCopyFailed": {
    "description": "Item detail dialog snackbar shown when copying the image to the clipboard fails."
  },

  "imageSaveFailed": "儲存圖片失敗",
  "@imageSaveFailed": {
    "description": "Item detail dialog snackbar shown when saving the image to disk fails."
  },

  "imageSavedTo": "已儲存至 {path}",
  "@imageSavedTo": {
    "description": "Item detail dialog snackbar shown after the image is saved, with the full save path.",
    "placeholders": {
      "path": {
        "type": "String"
      }
    }
  }
```

- [ ] **Step 2: 在 `app_en.arb` 加入對應英文鍵**

在 `app_en.arb` 對應位置（檔尾結構與 zh 一致，找到 `actionCloseImagePreview` 之後）插入。若該檔最後一鍵不同，插在最後一鍵之後、結尾 `}` 之前並補逗號：

```json
,

  "actionCopyImage": "Copy Image",
  "@actionCopyImage": {
    "description": "Item detail dialog image menu: option that copies the currently shown image to the system clipboard as PNG."
  },

  "actionSaveImage": "Save Image",
  "@actionSaveImage": {
    "description": "Item detail dialog image menu: option that opens the system save dialog to save the currently shown image as PNG."
  },

  "actionRefetchImage": "Re-fetch Image",
  "@actionRefetchImage": {
    "description": "Item detail dialog image menu: option that re-downloads the currently shown image, overwriting the cached copy."
  },

  "imageCopied": "Image copied to clipboard",
  "@imageCopied": {
    "description": "Item detail dialog snackbar shown when the image is successfully copied to the clipboard."
  },

  "imageCopyFailed": "Failed to copy image",
  "@imageCopyFailed": {
    "description": "Item detail dialog snackbar shown when copying the image to the clipboard fails."
  },

  "imageSaveFailed": "Failed to save image",
  "@imageSaveFailed": {
    "description": "Item detail dialog snackbar shown when saving the image to disk fails."
  },

  "imageSavedTo": "Saved to {path}",
  "@imageSavedTo": {
    "description": "Item detail dialog snackbar shown after the image is saved, with the full save path.",
    "placeholders": {
      "path": {
        "type": "String"
      }
    }
  }
```

> 其他語系 ARB 不在此 plan 手動翻譯（空殼留給 Crowdin pipeline；已翻譯語系由 Crowdin 後續補上）。

- [ ] **Step 3: 重新產生 localizations**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `actionCopyImage` / `actionSaveImage` / `actionRefetchImage` / `imageCopied` / `imageCopyFailed` / `imageSaveFailed` / `imageSavedTo(String path)` getter/method。

- [ ] **Step 4: 驗證 analyze 通過**

Run: `fvm flutter analyze`
Expected: No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "feat(l10n): add item image menu strings (copy/save/refetch)"
```

---

### Task 4: dialog 圖片選單 + 右鍵 + 重抓

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Test: `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`

- [ ] **Step 1: 先寫失敗的 widget 測試（新增 group）**

在 `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart` 檔案頂端 import 區，補上 `gestures`（for `kSecondaryButton`）：

```dart
import 'package:flutter/gestures.dart';
```

然後在 `main()` 內最後一個 `testWidgets(...)` 之後（仍在 `main` 的 `}` 之前）新增：

```dart
  group('圖片選單 + 右鍵 + 重抓', () {
    /// 在 dialog 內定位中央 gallery 主圖（list[0] 的 gif 檔）。
    Finder galleryMainImage() => find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is FileImage &&
          (w.image as FileImage).file.path.contains('_gallery_'),
    );

    testWidgets('ready 圖片右上角有溢出選單鈕', (tester) async {
      final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await setupContainer(fetcher, tempDir);
        addTearDown(c.dispose);
        await seedEntry(c);
        await _touchIcon(tempDir, 'x1');
      });

      await pumpDialogAndSettle(tester, c, _rec());

      expect(find.byIcon(Icons.more_vert), findsWidgets);
    });

    testWidgets('點選單鈕 → 顯示複製/儲存/重抓三項', (tester) async {
      final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await setupContainer(fetcher, tempDir);
        addTearDown(c.dispose);
        await seedEntry(c);
        await _touchIcon(tempDir, 'x1');
      });

      await pumpDialogAndSettle(tester, c, _rec());
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l.actionCopyImage), findsOneWidget);
      expect(find.text(l.actionSaveImage), findsOneWidget);
      expect(find.text(l.actionRefetchImage), findsOneWidget);
    });

    testWidgets('右鍵圖片 → 叫出選單', (tester) async {
      final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await setupContainer(fetcher, tempDir);
        addTearDown(c.dispose);
        await seedEntry(c);
        await _touchIcon(tempDir, 'x1');
      });

      await pumpDialogAndSettle(tester, c, _rec());
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;

      await tester.tap(galleryMainImage().first, buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(l.actionCopyImage), findsOneWidget);
      expect(find.text(l.actionRefetchImage), findsOneWidget);
    });

    testWidgets('選「重抓圖片」(gallery) → 對該圖 URL 再打一次 fetch', (tester) async {
      final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await setupContainer(fetcher, tempDir);
        addTearDown(c.dispose);
        await seedEntry(c);
        await _touchIcon(tempDir, 'x1');
      });

      await pumpDialogAndSettle(tester, c, _rec());
      // 預設選中 chip 0 = list[0] = x1_g1.gif，初次已打 1 次。
      expect(fetcher._calls['https://cdn/x1_g1.gif'], 1);

      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l.actionRefetchImage));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fetcher._calls['https://cdn/x1_g1.gif'], 2);
    });

    testWidgets('切到 Icon chip 後重抓 → 對 icon URL 打一次 fetch', (tester) async {
      final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
      late ProviderContainer c;
      await tester.runAsync(() async {
        c = await setupContainer(fetcher, tempDir);
        addTearDown(c.dispose);
        await seedEntry(c);
        await _touchIcon(tempDir, 'x1');
      });

      await pumpDialogAndSettle(tester, c, _rec());
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;

      // 切到最後一個 chip（Icon）
      await tester.tap(find.text(l.galleryIconLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // icon 初始不經 fetch（預先存在），重抓前 call 數為 null
      expect(fetcher._calls['https://cdn/x1_icon.png'], isNull);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l.actionRefetchImage));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fetcher._calls['https://cdn/x1_icon.png'], 1);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
Expected: 新 group 失敗（找不到 `Icons.more_vert` / 選單項文字 / refetch 未觸發）。既有測試仍應通過。

- [ ] **Step 3: 改 dialog import 與 `_GalleryReady` 為 Stack + 選單**

在 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` import 區（現有 import 之後）新增：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
```

把 `_buildCurrentImageArea` 內 `switch (state)` 的 `_GalleryReady(:final file) => MouseRegion(...)` 整個 arm 換成下列 `Stack` 版本（保留 loading / failed 兩個 arm，但 failed arm 的重試按鈕改呼叫 `_refetchEntry`，見 Step 4）：

```dart
        _GalleryReady(:final file) => Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _log.info('open zoom path=${sanitizeFsPath(file.path)}');
                    showZoomableImageOverlay(context, imageFile: file);
                  },
                  onSecondaryTapDown: (details) => unawaited(
                    _showImageContextMenu(
                      context,
                      details.globalPosition,
                      current,
                    ),
                  ),
                  child: Image.file(
                    file,
                    key: ValueKey(file.path),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (_, e, st) {
                      _log.warning(
                        'gallery image errorBuilder '
                        'path=${sanitizeFsPath(file.path)}',
                        e,
                        st,
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.s,
              right: AppSpacing.s,
              child: _buildImageMenu(context, current),
            ),
          ],
        ),
```

- [ ] **Step 4: 新增選單／複製／儲存／重抓方法，並讓 failed 重試共用 `_refetchEntry`**

把現有 `_GalleryFailed()` arm 內重試按鈕的 `onPressed` 由：

```dart
                onPressed: () => _retry(
                  id: _extractIdFromPath(current.file.path) ?? '',
                  url: current.url,
                  file: current.file,
                ),
```

改為：

```dart
                onPressed: () => _refetchEntry(current),
```

刪除已不再被使用的 `_retry` 方法（原 `void _retry({required String id, required String url, required File file})` 整段）。

在 `_buildCurrentImageArea` 方法之前（class `_GachaItemDetailDialogState` 內）新增以下方法：

```dart
  /// 重抓某 chip 的圖：先 evict 既有 ImageCache、切回 loading，再依類別重抓。
  ///
  /// 路徑不變的重抓必須 evict，否則 ready 圖重建後仍讀到舊快取。
  /// 同時供失敗狀態的「重試」按鈕與圖片選單的「重抓圖片」共用。
  void _refetchEntry(_GalleryChipEntry e) {
    PaintingBinding.instance.imageCache.evict(FileImage(e.file));
    _precachedPaths.remove(e.file.path);
    setState(() => _loadStates[e.file.path] = const _GalleryLoading());
    switch (e.kind) {
      case _ChipKind.galleryList:
      case _ChipKind.galleryPic:
        unawaited(
          _fetchAndCache(
            id: _extractIdFromPath(e.file.path) ?? '',
            url: e.url,
            file: e.file,
          ),
        );
      case _ChipKind.icon:
        unawaited(_refetchIcon(url: e.url, file: e.file));
    }
  }

  /// 重抓 icon：重新下載 [url] 覆蓋 [file]，成功後 evict + bumpCacheRevision，
  /// 讓 dialog 標題縮圖與記錄列表 [GachaItemIcon] 同步顯示新 icon。
  ///
  /// 失敗時保留磁碟既有 icon（writeHoYoWikiCacheImage 失敗不覆寫），
  /// chip 狀態轉 failed（沿用既有失敗 UI 的重試按鈕）。
  Future<void> _refetchIcon({required String url, required File file}) async {
    final fetcher = ref.read(hoyowikiFetcherProvider);
    try {
      final bytes = await fetcher.downloadImage(url, _client);
      if (bytes == null) {
        if (!mounted) return;
        setState(() {
          _loadStates[file.path] = _GalleryFailed(
            const FormatException('downloadImage returned null'),
          );
        });
        _log.warning('icon refetch null url=${sanitizeUrl(url)}');
        return;
      }
      await writeHoYoWikiCacheImage(file: file, bytes: bytes);
      if (!mounted) return;
      PaintingBinding.instance.imageCache.evict(FileImage(file));
      setState(() => _loadStates[file.path] = _GalleryReady(file));
      ref.read(hoyowikiIndexProvider.notifier).bumpCacheRevision();
      ref.invalidate(hoyowikiCacheUsageProvider);
      _log.info(
        'icon refetch ok bytes=${bytes.length} '
        'path=${sanitizeFsPath(file.path)}',
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadStates[file.path] = _GalleryFailed(e));
      _log.warning('icon refetch failed url=${sanitizeUrl(url)}', e, st);
    }
  }

  /// 圖片選單項目（複製圖片 / 儲存圖片 / --- / 重抓圖片）；右上角按鈕與右鍵選單共用。
  List<PopupMenuEntry<String>> _imageMenuItems(AppLocalizations l) => [
    PopupMenuItem(
      value: 'copy',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.copy, size: 20),
        title: Text(l.actionCopyImage),
      ),
    ),
    PopupMenuItem(
      value: 'save',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt, size: 20),
        title: Text(l.actionSaveImage),
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'refetch',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.refresh, size: 20),
        title: Text(l.actionRefetchImage),
      ),
    ),
  ];

  /// 分派圖片選單選擇（按鈕與右鍵選單共用）：複製 / 儲存 / 重抓。
  void _onImageMenuSelected(String value, _GalleryChipEntry current) {
    switch (value) {
      case 'copy':
        unawaited(_copyImage(current));
      case 'save':
        unawaited(_saveImage(current));
      case 'refetch':
        _refetchEntry(current);
    }
  }

  /// 圖片區右上角的溢出選單按鈕：複製圖片 / 儲存圖片 / --- / 重抓圖片。
  /// 沿用 lightbox X 鈕的半透明黑底圓鈕視覺；僅在圖片 ready 時疊在圖上顯示。
  Widget _buildImageMenu(BuildContext context, _GalleryChipEntry current) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        tooltip: '',
        onSelected: (value) => _onImageMenuSelected(value, current),
        itemBuilder: (_) => _imageMenuItems(l),
      ),
    );
  }

  /// 右鍵在圖片上叫出與右上角按鈕相同的選單，位置跟著游標。
  Future<void> _showImageContextMenu(
    BuildContext context,
    Offset globalPosition,
    _GalleryChipEntry current,
  ) async {
    final l = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: _imageMenuItems(l),
    );
    if (selected == null || !mounted) return;
    _onImageMenuSelected(selected, current);
  }

  /// 把 record 名稱與 chip 標籤組成存檔建議檔名，並去掉檔名非法字元。
  String _suggestedFileName(_GalleryChipEntry e) {
    final raw = '${widget.record.name}_${e.label}';
    // Windows 檔名非法字元（< > : " / \ | ? *）一律換 _，避免存檔對話框拒絕。
    final safe = raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$safe.png';
  }

  /// 複製目前圖片到剪貼簿：解碼成 PNG → 寫剪貼簿，結果以 SnackBar 回報。
  Future<void> _copyImage(_GalleryChipEntry e) async {
    final l = AppLocalizations.of(context)!;
    final png = await encodeImageFileToPng(e.file);
    if (!mounted) return;
    if (png == null) {
      _showSnack(l.imageCopyFailed);
      return;
    }
    final ok = await copyImagePngToClipboard(png);
    if (!mounted) return;
    _showSnack(ok ? l.imageCopied : l.imageCopyFailed);
  }

  /// 儲存目前圖片：解碼成 PNG → 系統存檔對話框，結果以 SnackBar 回報。
  /// 使用者取消不提示；寫檔失敗提示失敗。
  Future<void> _saveImage(_GalleryChipEntry e) async {
    final l = AppLocalizations.of(context)!;
    final png = await encodeImageFileToPng(e.file);
    if (!mounted) return;
    if (png == null) {
      _showSnack(l.imageSaveFailed);
      return;
    }
    try {
      final savedPath = await saveImagePng(
        png,
        suggestedName: _suggestedFileName(e),
      );
      if (!mounted || savedPath == null) return;
      _showSnack(l.imageSavedTo(savedPath));
    } catch (_) {
      if (!mounted) return;
      _showSnack(l.imageSaveFailed);
    }
  }

  /// 以 SnackBar 顯示 [message]（dialog 之上找最近的 ScaffoldMessenger）。
  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
```

- [ ] **Step 5: 跑 dialog 測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
Expected: All tests passed!（新 group + 既有測試全綠；既有「重試：第一次 null 第二次成功」因重試按鈕改走 `_refetchEntry` 仍應通過。）

- [ ] **Step 6: 跑主 dialog 測試確認沒回歸**

Run: `fvm flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart`
Expected: All tests passed!
（注意：「gallery 主圖 wrapper 有 click cursor」與「點 gallery 主圖 → 開啟 ZoomableImageOverlay」等仍應通過，因為 `_GalleryReady` 仍含 `MouseRegion(click)` 與 `onTap`。）

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart
git commit -m "feat(item-detail): add image overflow menu (copy/save/refetch) and right-click menu"
```

---

### Task 5: 全套品質檢查

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 數個檔案 formatted（或 unchanged）。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: No issues found!

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: All tests passed!

- [ ] **Step 4: Commit（若 format 有改動）**

```bash
git add -A
git commit -m "style: dart format after item image menu feature"
```

---

## Self-Review

**Spec coverage：**
- 右上角選單鈕 → Task 4 `_buildImageMenu` + Stack。✅
- 複製/儲存/重抓三項 → Task 4 `_imageMenuItems` + Task 1 service。✅
- 右鍵叫出選單 → Task 4 `onSecondaryTapDown` + `_showImageContextMenu`。✅
- 抽共用低階層 → Task 1 + Task 2。✅
- icon 重抓同步標題/列表 → Task 4 `_refetchIcon` + `bumpCacheRevision`。✅
- 失敗重試與選單重抓共用 → Task 4 `_refetchEntry`。✅
- SnackBar 回報 → Task 4 `_showSnack` + Task 3 i18n。✅
- i18n keys → Task 3。✅
- 測試（service + dialog + 既有 share）→ Task 1 / 2 / 4。✅
- 驗收（format / analyze / test）→ Task 5。✅

**Placeholder scan：** 無 TBD/TODO；每個 code step 都有完整程式碼。

**Type consistency：**
- 共用 seam 名稱 `imageClipboardWriter` / `imageSaveLocationPicker` / `imageFileWriter` 在 Task 1 定義、Task 2 重構、兩處測試一致使用。✅
- `encodeImageFileToPng(File)→Future<Uint8List?>`、`copyImagePngToClipboard(Uint8List)→Future<bool>`、`saveImagePng(Uint8List,{required String suggestedName})→Future<String?>` 在 Task 1 定義、Task 4 `_copyImage`/`_saveImage` 呼叫一致。✅
- `_refetchEntry(_GalleryChipEntry)`、`_refetchIcon({required String url, required File file})`、`_imageMenuItems(AppLocalizations)`、`_onImageMenuSelected(String,_GalleryChipEntry)`、`_buildImageMenu(BuildContext,_GalleryChipEntry)`、`_showImageContextMenu(BuildContext,Offset,_GalleryChipEntry)`、`_suggestedFileName(_GalleryChipEntry)`、`_showSnack(String)` 簽名與彼此呼叫一致。✅
- i18n getter：`actionCopyImage` / `actionSaveImage` / `actionRefetchImage` / `imageCopied` / `imageCopyFailed` / `imageSaveFailed` / `imageSavedTo(String)` 在 Task 3 定義、Task 4 使用一致。✅
- `_ChipKind` 既有值 `galleryList` / `galleryPic` / `icon` 在 `_refetchEntry` switch 完整涵蓋（無 default）。✅
