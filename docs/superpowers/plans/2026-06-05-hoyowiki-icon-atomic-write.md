# HoYoWiki 圖檔原子寫入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除「更新抓取物品圖片時列表 icon 出現破圖、需切換頁面才恢復」的 bug。

**Architecture:** 抽一個共用的原子圖檔寫入 helper（`tmp + rename`），讓所有 HoYoWiki cache 圖檔寫入都走它，使磁碟上的圖檔路徑只會是「不存在」或「內容完整」兩態，根除並發重繪時讀到截斷檔的成因；再給唯一還缺 fallback 的 `GachaItemIcon.Image.file` 補上 `errorBuilder`，讓任何殘留解碼失敗優雅退回既有 placeholder 而非破圖。

**Tech Stack:** Flutter / Dart、Riverpod、`flutter_test`、`logging`。

**設計來源：** `docs/superpowers/specs/2026-06-05-hoyowiki-icon-atomic-write-design.md`

---

## File Structure

| 檔案 | 責任 | 動作 |
|---|---|---|
| `lib/services/hoyowiki_index.dart` | HoYoWiki cache 路徑推導與 index 讀寫（純 service 層） | 新增 top-level `writeHoYoWikiCacheImage` |
| `lib/state/gacha_repository.dart` | 更新流程協調（含 icon 下載寫檔） | icon 下載改呼叫 helper |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | 物品詳情對話框（gallery／詳情圖 lazy 下載） | lazy 下載改呼叫 helper |
| `lib/widgets/gacha_item_icon.dart` | 列表物品 icon widget | `Image.file` 加 `errorBuilder` + log |
| `test/services/hoyowiki_index_test.dart` | service 層測試 | 新增 helper 原子性測試 group |
| `test/widgets/gacha_item_icon_test.dart` | icon widget 測試 | 新增「損壞檔 → placeholder」回歸測試 |

---

## Task 1: 新增原子圖檔寫入 helper

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`（檔頭 import 區、檔尾 top-level 函式區）
- Test: `test/services/hoyowiki_index_test.dart`

- [ ] **Step 1: 寫失敗測試**

在 `test/services/hoyowiki_index_test.dart` 檔頭 import 區，於 `import 'dart:io';` 下一行加入：

```dart
import 'dart:typed_data';
```

在 `void main() {` 內、最後一個 group（`HoYoWikiIndexStorage v1/v2 → v3 migration`）的**右大括號 `});` 之後、`main` 的收尾 `}` 之前**，插入新 group：

```dart
  group('writeHoYoWikiCacheImage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_write_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('寫入後檔案內容與輸入 bytes 完全一致', () async {
      final file = File('${tempDir.path}/abc_icon.png');
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await writeHoYoWikiCacheImage(file: file, bytes: bytes);
      expect(await file.readAsBytes(), bytes);
    });

    test('自動建立缺失的父目錄', () async {
      final file = File('${tempDir.path}/nested/dir/x_icon.png');
      await writeHoYoWikiCacheImage(
        file: file,
        bytes: Uint8List.fromList([9]),
      );
      expect(file.existsSync(), isTrue);
    });

    test('寫入後不留 .tmp 殘檔', () async {
      final file = File('${tempDir.path}/abc_icon.png');
      await writeHoYoWikiCacheImage(
        file: file,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final tmp = File('${file.path}.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('對既有檔可正確覆寫', () async {
      final file = File('${tempDir.path}/abc_icon.png');
      await file.writeAsBytes([0, 0, 0]);
      await writeHoYoWikiCacheImage(
        file: file,
        bytes: Uint8List.fromList([7, 8, 9]),
      );
      expect(await file.readAsBytes(), [7, 8, 9]);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: 編譯失敗，`The function 'writeHoYoWikiCacheImage' isn't defined`（helper 尚未存在）。

- [ ] **Step 3: 實作 helper**

在 `lib/services/hoyowiki_index.dart` 檔頭 import 區，於 `import 'dart:io';` 下一行加入：

```dart
import 'dart:typed_data';
```

在同檔**最末端**（`_extFromUrl` 函式之後）追加 top-level 函式：

```dart

/// 原子寫入 HoYoWiki cache 圖檔：先寫同目錄的 `<path>.tmp`（flush）再 rename 蓋到
/// 最終路徑。避免並發更新（多 worker 寫檔 + bumpCacheRevision 觸發全列表重繪）時，
/// 其他 widget 的 `Image.file` 讀到寫一半的截斷檔而出現破圖。對齊
/// [HoYoWikiIndexStorage.save] 既有的 tmp+rename 策略。
Future<void> writeHoYoWikiCacheImage({
  required File file,
  required Uint8List bytes,
}) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  await tmp.rename(file.path);
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: PASS（含新 group 4 個 test 全綠）。

- [ ] **Step 5: 品質閘門**

Run: `dart format lib/ test/ ; flutter analyze`
Expected: `flutter analyze` 輸出 `No issues found!`。

- [ ] **Step 6: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add atomic image cache write helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 兩個寫檔點改用 helper

純機械替換（行為不變，僅由非原子寫入改為原子寫入），由既有測試守住。

**Files:**
- Modify: `lib/state/gacha_repository.dart`（icon 下載 worker，約 968-973 行）
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`（`_fetchAndCache`，約 110-111 行）

- [ ] **Step 1: 改 gacha_repository.dart icon 下載**

找到下列片段（download 階段 worker 內）：

```dart
            if (bytes != null) {
              final file = hoyowikiIconCacheFile(
                baseDir: cacheDir,
                id: item.id,
                url: item.url,
              );
              await file.writeAsBytes(bytes, flush: true);
              indexNotifier.bumpCacheRevision();
              downloaded++;
            }
```

把 `await file.writeAsBytes(bytes, flush: true);` 替換為：

```dart
              await writeHoYoWikiCacheImage(file: file, bytes: bytes);
```

替換後該片段為：

```dart
            if (bytes != null) {
              final file = hoyowikiIconCacheFile(
                baseDir: cacheDir,
                id: item.id,
                url: item.url,
              );
              await writeHoYoWikiCacheImage(file: file, bytes: bytes);
              indexNotifier.bumpCacheRevision();
              downloaded++;
            }
```

> `gacha_repository.dart` 已 import `services/hoyowiki_index.dart`（使用 `hoyowikiIconCacheFile`），helper 直接可用，無需新增 import。`bytes` 型別為 `Uint8List`（`downloadImage` 回傳 `Uint8List?`，此處已通過 `!= null`）。

- [ ] **Step 2: 改 gacha_item_detail_dialog.dart lazy 下載**

找到 `_fetchAndCache` 內下列兩行：

```dart
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
```

替換為單行（helper 內已含 `parent.create`）：

```dart
      await writeHoYoWikiCacheImage(file: file, bytes: bytes);
```

> `gacha_item_detail_dialog.dart` 已 import `services/hoyowiki_index.dart`（使用 `hoyowikiIconCacheFile` / `hoyowikiGalleryCacheFile`），helper 直接可用。此處 `bytes` 在前面已 `if (bytes == null) { ...; return; }`，型別為 `Uint8List`。

- [ ] **Step 3: 跑相關既有測試確認行為不變**

Run: `flutter test test/state/gacha_repository_hoyowiki_test.dart test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
Expected: PASS（兩檔全綠，證明下載寫檔行為不變）。

- [ ] **Step 4: 品質閘門**

Run: `dart format lib/ test/ ; flutter analyze`
Expected: `No issues found!`。

- [ ] **Step 5: Commit**

```bash
git add lib/state/gacha_repository.dart lib/widgets/dialogs/gacha_item_detail_dialog.dart
git commit -m "fix(hoyowiki): write icon and gallery cache files atomically

Route both image-download write sites through the atomic helper so
concurrent bumpCacheRevision rebuilds can never read a half-written
cache file.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: GachaItemIcon 補 errorBuilder + log

**Files:**
- Modify: `lib/widgets/gacha_item_icon.dart`
- Test: `test/widgets/gacha_item_icon_test.dart`

- [ ] **Step 1: 寫失敗測試**

在 `test/widgets/gacha_item_icon_test.dart` 內，於既有 `testWidgets('完整 chain（index + cache 檔在） → 顯示 Image', ...)` 這個 test 的收尾 `});` 之後插入新 test：

```dart
  testWidgets('cache 檔損壞 → errorBuilder 退回 placeholder（不丟解碼錯誤）', (
    tester,
  ) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    final iconUrl = 'https://x/icon.png';
    await tester.runAsync(() async {
      await notifier.setSearch(
        name: 'Hu Tao',
        lang: 'en-us',
        id: '111',
        menuId: 2,
      );
      await notifier.mergeEntry(
        id: '111',
        lang: 'en-us',
        fetched: HoYoWikiEntryFetched(
          iconUrl: iconUrl,
          page: const HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      final cacheFile = hoyowikiIconCacheFile(
        baseDir: tempDir,
        id: '111',
        url: iconUrl,
      );
      // 寫入「不是合法圖片」的 bytes，模擬截斷／損壞檔。
      await cacheFile.writeAsBytes([1, 2, 3, 4]);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          GachaItemIcon(
            record: _rec(name: 'Hu Tao', gachaType: '301'),
            size: 20,
          ),
          container,
        ),
      );
      // 等 codec 解碼失敗、errorBuilder 觸發。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    expect(
      find.byIcon(Icons.question_mark),
      findsOneWidget,
      reason: '損壞檔應退回 _Placeholder（question_mark），而非破圖',
    );
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/gacha_item_icon_test.dart --plain-name "cache 檔損壞"`
Expected: FAIL — 目前 `Image.file` 無 `errorBuilder`，損壞檔解碼錯誤會被 `flutter_test` 捕捉為未處理的 image codec 例外（test 失敗），且找不到 `question_mark`。

- [ ] **Step 3: 加 logging import 與 logger 欄位**

在 `lib/widgets/gacha_item_icon.dart` 檔頭 import 區，於 `import 'package:flutter_riverpod/flutter_riverpod.dart';` 下一行加入：

```dart
import 'package:logging/logging.dart';
```

把 class 宣告與其第一個成員：

```dart
class GachaItemIcon extends ConsumerWidget {
  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({
```

改為（插入 static logger）：

```dart
class GachaItemIcon extends ConsumerWidget {
  /// 解碼失敗等情境的 logger（對齊 `gacha.hoyowiki.*` 樹）。
  static final _log = Logger('gacha.hoyowiki.icon');

  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({
```

- [ ] **Step 4: 給 Image.file 加 errorBuilder**

在同檔 `build` 內，把：

```dart
      if (file.existsSync()) {
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(Image.file(file, fit: BoxFit.cover)),
        );
      }
```

替換為：

```dart
      if (file.existsSync()) {
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(
            Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                _log.warning('icon decode failed id=$id', error, stackTrace);
                return _Placeholder(
                  rankType: record.rankType,
                  size: size,
                  tokens: tokens,
                  circular: circular,
                );
              },
            ),
          ),
        );
      }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/widgets/gacha_item_icon_test.dart`
Expected: PASS（含新 test 與所有既有 test 全綠）。

- [ ] **Step 6: 品質閘門 + 全套測試**

Run: `dart format lib/ test/ ; flutter analyze ; flutter test`
Expected: `flutter analyze` → `No issues found!`；`flutter test` → `All tests passed!`。

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/gacha_item_icon.dart test/widgets/gacha_item_icon_test.dart
git commit -m "fix(gacha): show placeholder when item icon fails to decode

Add an errorBuilder fallback to GachaItemIcon's Image.file so a residual
decode failure degrades to the existing rarity placeholder instead of a
broken-image error, matching the detail dialog and zoom overlay.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review（plan 對 spec 的覆蓋檢查）

- **共用原子寫入 helper（spec §做法 1）** → Task 1。✔
- **兩個寫檔點改用 helper（spec §做法 2）** → Task 2（gacha_repository.dart icon 下載 + gacha_item_detail_dialog.dart lazy 下載）。✔
- **GachaItemIcon 補 errorBuilder + log（spec §做法 3）** → Task 3。✔
- **明確不做（spec §做法 4）** → 計畫未觸碰 `bumpCacheRevision` 頻率、ImageCache eviction、share/preload，符合。✔
- **測試（spec §測試）** → helper 原子性（Task 1 Step 1）、損壞檔 → placeholder（Task 3 Step 1）。✔
- **驗收條件（spec §驗收）** → 各 Task 品質閘門 + Task 3 Step 6 全套 `flutter analyze` / `flutter test`。手動驗證（更新時不再破圖）列為實作後手動確認，不在自動測試涵蓋（半成品讀取競態無法穩定重現）。✔
- **型別／命名一致性**：helper 簽名 `writeHoYoWikiCacheImage({required File file, required Uint8List bytes})` 在 Task 1 定義，Task 2 兩處呼叫一致；`_log` 為 `GachaItemIcon` static，errorBuilder 內引用一致。✔
- **Placeholder 掃描**：無 TBD/TODO，每個 code step 均含完整程式碼。✔
