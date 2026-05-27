# HoYoWiki 圖片快取 lazy load 與快取控制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 HoYoWiki gallery 大圖從「update 階段全量預下載」改為「打開物品詳情對話框時 lazy 抓」，並在設定頁加上快取用量顯示與「清除詳情圖快取」按鈕，大幅壓縮本地容量。

**Architecture:** update flow 階段只下載小圖示（icon）;gallery 大圖留 URL metadata 在 index，延到 `GachaItemDetailDialog.initState` 才平行下載到 cache。設定頁新增「圖片快取」section，顯示 icon / gallery / 總計三段用量，並提供「清除詳情圖快取」（只刪 gallery 留 icon）按鈕；既有「強制重抓物品圖片」按鈕從「資料管理」section 整段搬到「圖片快取」section。

**Tech Stack:** Flutter 3.x + Dart 3 / flutter_riverpod 3.3 / logging / http / 既有 `HoYoWikiFetcher`、`HoYoWikiIndexStorage`、`AppDialog`、`SectionCard` 共用元件。

**Reference:** `docs/superpowers/specs/2026-05-27-hoyowiki-image-cache-lazy-load-design.md`

---

## File Structure

**新增**

| 路徑 | 責任 |
|---|---|
| `lib/utils/format_bytes.dart` | bytes → 「XXX.X KB / MB / GB」字串（單一 top-level function） |
| `lib/state/hoyowiki_cache_usage.dart` | `HoYoWikiCacheUsage` model + `hoyowikiCacheUsageProvider`（`FutureProvider.autoDispose`） |
| `test/utils/format_bytes_test.dart` | format_bytes boundary 測試 |
| `test/state/hoyowiki_cache_usage_test.dart` | cache usage provider 測試 |
| `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart` | dialog lazy 載入專屬測試 |

**修改**

| 路徑 | 改動範圍 |
|---|---|
| `lib/services/hoyowiki_index.dart` | `HoYoWikiIndexStorage` 新增 `deleteGalleryCacheFiles()` |
| `lib/state/gacha_repository.dart` | `enqueueDownloadsForEntry` 移除 gallery enqueue（只留 icon);`_HoYoWikiDownloadItem.isGallery` 若已無人寫入連同 download phase 判斷一併拿掉 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | 新增 `_GalleryLoadState` sealed family + `_loadStates` map;chip 列列**全部** known URL（不過濾 existsSync）；中央圖區依 state 顯示 loading / ready / failed-retry |
| `lib/pages/settings_page.dart` | 新增 `_ImageCacheSection`（用量顯示 + 清大圖 + 重抓）;`_DataManagement` 移除「強制重抓」button 與 `_refetchHoYoWikiImages` method |
| `lib/l10n/app_zh.arb` 等 9 個非空殼 ARB | 新 keys 加翻譯 + `confirmRefetchHoyoWikiBody` 文字微調 |
| `test/state/gacha_repository_test.dart` | 移除「update 應下載 gallery」斷言 |
| `test/state/gacha_repository_refetch_test.dart` | `hoYoWikiImagesDownloaded` 期望值從「icon + header(gallery 替身）」改為「僅 icon」 |
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | 既有 chip 過濾邏輯斷言改為 lazy 流程斷言 |

---

## Phase 1 — 基礎工具

### Task 1.1: `format_bytes` 共用 helper

**Files:**
- Create: `lib/utils/format_bytes.dart`
- Create: `test/utils/format_bytes_test.dart`

- [ ] **Step 1: Write the failing test**

寫入 `test/utils/format_bytes_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/format_bytes.dart';

void main() {
  group('formatBytes', () {
    test('0 bytes → 0.0 KB', () {
      expect(formatBytes(0), '0.0 KB');
    });

    test('1023 bytes 仍顯示 KB（1024 為 1 KB 閾值）', () {
      expect(formatBytes(1023), '1.0 KB');
    });

    test('1024 bytes → 1.0 KB', () {
      expect(formatBytes(1024), '1.0 KB');
    });

    test('1 MB - 1 byte → 1024.0 KB（未跨進 MB）', () {
      expect(formatBytes(1024 * 1024 - 1), '1024.0 KB');
    });

    test('1 MB → 1.0 MB', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });

    test('123.4 MB（驗 1 位小數四捨五入）', () {
      expect(formatBytes((123.4 * 1024 * 1024).round()), '123.4 MB');
    });

    test('1 GB - 1 byte 仍顯示 MB', () {
      expect(formatBytes(1024 * 1024 * 1024 - 1), '1024.0 MB');
    });

    test('1 GB → 1.0 GB', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('2.5 GB', () {
      expect(formatBytes((2.5 * 1024 * 1024 * 1024).round()), '2.5 GB');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/utils/format_bytes_test.dart`
Expected: FAIL — 找不到 `formatBytes` import。

- [ ] **Step 3: Write implementation**

寫入 `lib/utils/format_bytes.dart`:

```dart
/// 將 bytes 數值轉成易讀字串，依大小自動選 KB / MB / GB，皆保留 1 位小數。
///
/// 規則（底數 1024，對齊 Windows 檔案總管）:
///   - `< 1 MB`           → `XXX.X KB`
///   - `1 MB ~ < 1 GB`    → `XXX.X MB`
///   - `>= 1 GB`          → `XXX.X GB`
///
/// 注意：1023 B 顯示為 `1.0 KB`（無條件先除 1024 後保留 1 位小數）;
/// 邊界以「除完是否 >= 1024.0」判定是否進位。
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes < mb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
  if (bytes < gb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/utils/format_bytes_test.dart`
Expected: All tests pass。

- [ ] **Step 5: Commit**

```powershell
git add lib/utils/format_bytes.dart test/utils/format_bytes_test.dart
git commit -m "feat(utils): add formatBytes helper for KB/MB/GB display"
```

---

### Task 1.2: `hoyowikiCacheUsageProvider`

**Files:**
- Create: `lib/state/hoyowiki_cache_usage.dart`
- Create: `test/state/hoyowiki_cache_usage_test.dart`

- [ ] **Step 1: Write the failing test**

寫入 `test/state/hoyowiki_cache_usage_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hoyowiki_cache_usage_');
    container = ProviderContainer(
      overrides: [
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> touch(String name, int size) async {
    final f = File('${tempDir.path}/$name');
    await f.writeAsBytes(List<int>.filled(size, 0));
  }

  test('空目錄 → 0 / 0', () async {
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 0);
    expect(usage.totalBytes, 0);
  });

  test('只 icon', () async {
    await touch('abc_icon.png', 1234);
    await touch('def_icon.jpg', 4321);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 1234 + 4321);
    expect(usage.galleryBytes, 0);
  });

  test('只 gallery', () async {
    await touch('abc_gallery_aaaaaaaaaaaa.png', 5000);
    await touch('def_gallery_bbbbbbbbbbbb.jpg', 6000);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 5000 + 6000);
  });

  test('混合 + 其他檔案被忽略', () async {
    await touch('abc_icon.png', 100);
    await touch('abc_gallery_xxxxxxxxxxxx.webp', 200);
    await touch('hoyowiki_index.json', 999); // index JSON 不算
    await touch('readme.txt', 50); // 其他檔不算
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 100);
    expect(usage.galleryBytes, 200);
    expect(usage.totalBytes, 300);
  });

  test('cache 目錄不存在 → 0 / 0（不拋例外）', () async {
    await tempDir.delete(recursive: true);
    final usage = await container.read(hoyowikiCacheUsageProvider.future);
    expect(usage.iconBytes, 0);
    expect(usage.galleryBytes, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/hoyowiki_cache_usage_test.dart`
Expected: FAIL — `hoyowikiCacheUsageProvider` 未定義。

- [ ] **Step 3: Write implementation**

寫入 `lib/state/hoyowiki_cache_usage.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// HoYoWiki 圖片快取用量分項。
@immutable
class HoYoWikiCacheUsage {
  /// 建立 [HoYoWikiCacheUsage]。
  const HoYoWikiCacheUsage({
    required this.iconBytes,
    required this.galleryBytes,
  });

  /// 物品 icon 圖檔總大小（bytes)。
  final int iconBytes;

  /// 物品 gallery 圖檔總大小（bytes)。
  final int galleryBytes;

  /// icon + gallery 總和。
  int get totalBytes => iconBytes + galleryBytes;
}

/// 掃描 [hoyowikiCacheDirProvider] 目錄，分項計算 icon 與 gallery 圖檔總大小。
///
/// `autoDispose` → 離開設定頁自動釋放，下次進設定頁重新計算。
/// 失敗（權限等）讓 `FutureProvider` 自然進 `AsyncError` 狀態。
final hoyowikiCacheUsageProvider =
    FutureProvider.autoDispose<HoYoWikiCacheUsage>((ref) async {
  final log = Logger('gacha.hoyowiki.usage');
  final dir = ref.watch(hoyowikiCacheDirProvider);
  if (!await dir.exists()) {
    log.fine('cache dir not exist → zero');
    return const HoYoWikiCacheUsage(iconBytes: 0, galleryBytes: 0);
  }
  var iconBytes = 0;
  var galleryBytes = 0;
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final base = p.basename(entity.path);
    final size = await entity.length();
    if (base.contains('_gallery_')) {
      galleryBytes += size;
    } else if (base.contains('_icon.')) {
      iconBytes += size;
    }
  }
  log.fine('scan done icon=$iconBytes gallery=$galleryBytes');
  return HoYoWikiCacheUsage(iconBytes: iconBytes, galleryBytes: galleryBytes);
});
```

確認 `package:path` 已在 transitive deps(flutter_test 引）。若 `flutter pub deps` 顯示沒有，直接加 `path: ^1.9.0` 到 `pubspec.yaml` 的 dependencies。

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/state/hoyowiki_cache_usage_test.dart`
Expected: All tests pass。

- [ ] **Step 5: Commit**

```powershell
git add lib/state/hoyowiki_cache_usage.dart test/state/hoyowiki_cache_usage_test.dart
git commit -m "feat(hoyowiki): add cache usage provider (icon + gallery breakdown)"
```

---

## Phase 2 — Storage layer

### Task 2.1: `HoYoWikiIndexStorage.deleteGalleryCacheFiles`

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`（在 `HoYoWikiIndexStorage` 內加新 method)
- Modify: 找一個 storage 既有測試檔（若無，新建 `test/services/hoyowiki_index_storage_test.dart`)

- [ ] **Step 1: Write the failing test**

先確認既有測試檔位置：

```powershell
Get-ChildItem -Recurse -Path test -Filter "*hoyowiki_index*"
```

若有 `test/services/hoyowiki_index_test.dart`，在內部 group 加新 test；若無，新建 `test/services/hoyowiki_index_storage_test.dart`（下方範例假設新建）:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

void main() {
  group('HoYoWikiIndexStorage.deleteGalleryCacheFiles', () {
    late Directory tempDir;
    late HoYoWikiIndexStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_storage_test_');
      storage = HoYoWikiIndexStorage(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Future<File> touch(String name) async {
      final f = File('${tempDir.path}/$name');
      await f.writeAsBytes([0]);
      return f;
    }

    test('只刪 *_gallery_* 檔，icon 與 index JSON 保留', () async {
      final icon = await touch('abc_icon.png');
      final gal1 = await touch('abc_gallery_aaaaaaaaaaaa.png');
      final gal2 = await touch('def_gallery_bbbbbbbbbbbb.jpg');
      final idx = await touch('hoyowiki_index.json');

      await storage.deleteGalleryCacheFiles();

      expect(icon.existsSync(), isTrue);
      expect(gal1.existsSync(), isFalse);
      expect(gal2.existsSync(), isFalse);
      expect(idx.existsSync(), isTrue);
    });

    test('目錄不存在 → 不拋例外', () async {
      await tempDir.delete(recursive: true);
      await storage.deleteGalleryCacheFiles();
      // 沒拋就算過
    });

    test('沒有任何 gallery 檔 → no-op', () async {
      await touch('abc_icon.png');
      await storage.deleteGalleryCacheFiles();
      expect(File('${tempDir.path}/abc_icon.png').existsSync(), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/hoyowiki_index_storage_test.dart`（或既有檔路徑）
Expected: FAIL — `deleteGalleryCacheFiles` 不存在。

- [ ] **Step 3: Write implementation**

在 `lib/services/hoyowiki_index.dart` 的 `HoYoWikiIndexStorage` class 內，`wipeCacheDirectory()` 後面新增：

```dart
  /// 刪除 [baseDir] 內所有 `*_gallery_*` 圖檔。Icon 檔與 `hoyowiki_index.json`
  /// 保留 — gallery URL metadata 仍在 index，下次打開物品詳情可 lazy 重抓。
  /// 目錄不存在直接 no-op。失敗（權限被鎖等）直接拋給呼叫方處理。
  Future<void> deleteGalleryCacheFiles() async {
    if (!await baseDir.exists()) {
      _log.fine('deleteGalleryCacheFiles: dir not exist, no-op');
      return;
    }
    var deleted = 0;
    await for (final entity in baseDir.list()) {
      if (entity is! File) continue;
      final base = entity.path.split(Platform.pathSeparator).last;
      if (!base.contains('_gallery_')) continue;
      try {
        await entity.delete();
        deleted++;
      } catch (e, st) {
        _log.warning(
          'deleteGalleryCacheFiles: delete failed path=${sanitizeFsPath(entity.path)}',
          e,
          st,
        );
        rethrow;
      }
    }
    _log.info('deleteGalleryCacheFiles: removed $deleted gallery file(s)');
  }
```

(`sanitizeFsPath` 已在 import,`Platform` 已在 dart:io import 內）

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/hoyowiki_index_storage_test.dart`
Expected: All tests pass。

- [ ] **Step 5: Commit**

```powershell
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_storage_test.dart
git commit -m "feat(hoyowiki): add HoYoWikiIndexStorage.deleteGalleryCacheFiles"
```

---

## Phase 3 — update flow 改動

### Task 3.1: 移除 gallery enqueue

**Files:**
- Modify: `lib/state/gacha_repository.dart`(`enqueueDownloadsForEntry` ~ L838-874)

- [ ] **Step 1: 先讀現況**

Read `lib/state/gacha_repository.dart:830-900` 確認當前 `enqueueDownloadsForEntry` 結構。

- [ ] **Step 2: 修改 `enqueueDownloadsForEntry` — 只留 icon**

把該函式內「gallery」for-loop(`for (final page in entry.pageByLang.values)` 區塊）整段移除。預期結果只剩 icon enqueue:

```dart
void enqueueDownloadsForEntry(String id, HoYoWikiEntry entry) {
  // gallery 大圖改 lazy: 由 GachaItemDetailDialog 打開時下載。
  // 此處僅 enqueue icon — icon 在祈願列表常駐顯示，維持預下載。
  if (entry.iconUrl.isEmpty) return;
  final iconFile = hoyowikiIconCacheFile(
    baseDir: cacheDir,
    id: id,
    url: entry.iconUrl,
  );
  if (!iconFile.existsSync() && seenUrls.add('icon::${entry.iconUrl}')) {
    downloadTodo.add(
      _HoYoWikiDownloadItem(id: id, url: entry.iconUrl, isGallery: false),
    );
  }
}
```

- [ ] **Step 3: 檢查 `_HoYoWikiDownloadItem.isGallery` 是否仍有 reader**

Grep:

```powershell
```

Run via Grep tool: `pattern: "isGallery", path: "lib/state/gacha_repository.dart", output_mode: "content"`

若 download phase(worker）還在用 `isGallery` 三元式選 `hoyowikiGalleryCacheFile` 或 `hoyowikiIconCacheFile`(spec §4.2 提及），把該三元式簡化為直接 `hoyowikiIconCacheFile(...)`，並移除 `_HoYoWikiDownloadItem.isGallery` 欄位與 constructor 參數。若有測試或其他生產碼引用，一併調整。

- [ ] **Step 4: 跑既有單測，觀察哪些失敗**

Run: `flutter test test/state/gacha_repository_test.dart test/state/gacha_repository_refetch_test.dart`
Expected: 既有「gallery 圖應下載」斷言失敗（這是預期的，下個 task 處理）。

- [ ] **Step 5: Commit**

```powershell
git add lib/state/gacha_repository.dart
git commit -m "refactor(hoyowiki): drop gallery enqueue from update flow (lazy load)"
```

---

### Task 3.2: 調整既有 refetch / update 測試期望值

**Files:**
- Modify: `test/state/gacha_repository_refetch_test.dart`
- Modify: 若有 `test/state/gacha_repository_test.dart`，同步調整

- [ ] **Step 1: 修改 refetch test 主要路徑斷言**

開 `test/state/gacha_repository_refetch_test.dart` L166-170 附近（原斷言：icon + header，各 2 物品共 4 張）:

```dart
// 結束 emit UpdateCompleted，並驗證圖片下載數（Hu Tao + Skyward Harp，各只 icon 1 張 = 2 張）
final progress = container.read(gachaRepositoryProvider).progress;
expect(progress, isA<UpdateCompleted>());
expect((progress as UpdateCompleted).hoYoWikiImagesDownloaded, 2);
```

（原 mock entry_page 回 `icon_url` + `header_img_url`,header_img_url 已不在新流程使用 — 因 gallery enqueue 已拿掉。下載數從 4 變 2。)

- [ ] **Step 2: 跑 refetch test**

Run: `flutter test test/state/gacha_repository_refetch_test.dart`
Expected: 主要路徑 test pass。其他 cases（空 / 互斥 / 清檔失敗）不受影響。

- [ ] **Step 3: 順手檢查 gacha_repository 系列其他測試**

Run: `flutter test test/state/`
Expected: All tests pass；若有其他斷言依賴 gallery 下載數，同步以「僅 icon」邏輯調整（每處改動寫一句 comment 帶 `lazy gallery` 關鍵字便於日後追溯）。

- [ ] **Step 4: Commit**

```powershell
git add test/state/
git commit -m "test(hoyowiki): align refetch test expectations with lazy gallery"
```

---

## Phase 4 — Dialog lazy 載入

> **重要**:Phase 4 必須與 Phase 3 在**同一個 PR** 內 merge。Phase 3 上線而 Phase 4 沒上，chip 列會因 `existsSync()` 過濾掉全部沒檔的 chip（下次 update 後 gallery 永遠不存在）→ 使用者看不到任何 gallery 圖。

### Task 4.1: 新增 `_GalleryLoadState` sealed family 與骨架

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`

- [ ] **Step 1: 在檔案底部（`_GalleryChipEntry` class 後）加入 sealed family**

```dart
/// gallery 圖檔的下載/載入狀態，由 [_GachaItemDetailDialogState._loadStates] 管理。
sealed class _GalleryLoadState {
  const _GalleryLoadState();
}

/// 下載中（initState 觸發後尚未完成，或使用者按下重試後）。
class _GalleryLoading extends _GalleryLoadState {
  const _GalleryLoading();
}

/// 本地已有 cache 檔，可直接 `Image.file` 顯示。
class _GalleryReady extends _GalleryLoadState {
  const _GalleryReady(this.file);

  /// 對應的本地 cache 檔（已保證 existsSync)。
  final File file;
}

/// 下載失敗，UI 顯示 placeholder + 重試按鈕。
class _GalleryFailed extends _GalleryLoadState {
  const _GalleryFailed(this.error);

  /// 失敗原因，用於 log;UI 不顯示。
  final Object error;
}
```

- [ ] **Step 2: 確認 dart analyze 通過**

Run: `flutter analyze lib/widgets/dialogs/gacha_item_detail_dialog.dart`
Expected: 0 issues（類別存在但尚未被用 → 會有 `unused_element` warning,Step 3 之後會用到。先繼續 Task 4.2，合併兩個 commit 在 Task 4.4 一起。)

> **暫不 commit** — Task 4.1/4.2/4.3 為連續重構，合在一個 commit。

---

### Task 4.2: `_loadStates` 重構 — chip 列改為列全部 URL + lazy fetch

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`

- [ ] **Step 1: 替換 `_GachaItemDetailDialogState` 欄位與 lifecycle**

把 class 的欄位區塊改為：

```dart
class _GachaItemDetailDialogState extends ConsumerState<GachaItemDetailDialog> {
  /// 當前選中 chip 的 index；點 chip 時 setState 更新；超出範圍由 `clampedIndex` 收斂。
  int _selectedIndex = 0;

  /// 已排程 precacheImage 的本地圖檔路徑；避免每次 setState 重新呼叫。
  final Set<String> _precachedPaths = {};

  /// 每張 gallery 圖的下載/載入狀態，key 為「該圖的本地 cache 檔絕對路徑」。
  /// 同 URL 撞同 hash → 自然共用同一 entry，跨 chip 自然 dedup。
  final Map<String, _GalleryLoadState> _loadStates = {};

  /// initState 後使用的 http client(dispose 時 close 中斷 in-flight 請求）。
  late final http.Client _client;

  /// 該 dialog 的 logger。
  static final _log = Logger('gacha.hoyowiki.detail');

  @override
  void initState() {
    super.initState();
    _client = http.Client();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
```

確認檔案頂部 import 已包含 `http`:

```dart
import 'package:http/http.dart' as http;
```

若無就加入 import。

- [ ] **Step 2: 新增 lazy fetch helper method**

在 state class 內（`build` 之前）新增：

```dart
  /// 對 [url] 做 lazy 下載；成功寫入 cache 並 setState 為 [_GalleryReady];
  /// 失敗 setState 為 [_GalleryFailed]。重複呼叫（例如重試）安全。
  Future<void> _fetchAndCache({
    required String id,
    required String url,
    required File file,
  }) async {
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
        _log.warning(
          'lazy fetch returned null id=$id url=${sanitizeUrl(url)}',
        );
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _loadStates[file.path] = _GalleryReady(file);
      });
      _log.info(
        'lazy fetch ok id=$id bytes=${bytes.length} '
        'path=${sanitizeFsPath(file.path)}',
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadStates[file.path] = _GalleryFailed(e);
      });
      _log.warning(
        'lazy fetch failed id=$id url=${sanitizeUrl(url)}',
        e,
        st,
      );
    }
  }

  /// 對某張圖檔由 [_GalleryFailed] 重試，改回 [_GalleryLoading] 並再次呼叫
  /// [_fetchAndCache]。
  void _retry({required String id, required String url, required File file}) {
    setState(() {
      _loadStates[file.path] = const _GalleryLoading();
    });
    unawaited(_fetchAndCache(id: id, url: url, file: file));
  }
```

確認檔案頂部 import 已包含：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
```

(`unawaited` 來自 `dart:async`，確認有 import。)

- [ ] **Step 3: 替換 `build` 內 `chipEntries` 計算邏輯**

把目前 `chipEntries` 計算區塊（L100-147）改為「列全部 known URL」+「同步觸發 lazy fetch」。`_GalleryChipEntry` 也擴充：

```dart
/// 內部：單一 chip 條目。
class _GalleryChipEntry {
  /// 建立 [_GalleryChipEntry]。
  const _GalleryChipEntry({
    required this.label,
    required this.url,
    required this.file,
    required this.descHtml,
    required this.kind,
  });

  /// chip 顯示文字。
  final String label;

  /// 該 chip 對應的遠端 URL(icon chip 為 entry.iconUrl,gallery chip 為對應 gallery URL)。
  final String url;

  /// 該 chip 對應的本地 cache 檔（可能尚未存在，由 [_loadStates] 追蹤狀態）。
  final File file;

  /// 描述 HTML;trim 後為空則不繪描述區。
  final String descHtml;

  /// chip 類別 — icon 永遠 ready（已由 hasHoYoWikiContent 把關）,gallery 走 lazy。
  final _ChipKind kind;
}

enum _ChipKind {
  /// gallery list[i].imgUrl。
  galleryList,

  /// gallery picUrl。
  galleryPic,

  /// entry.iconUrl（已預下載，永遠 ready)。
  icon,
}
```

接著在 `build` 內改寫（取代既有 chipEntries 區塊）:

```dart
    // chip 順序：gallery list → pic 卡片 → Icon。Icon chip 永遠最後一個。
    final chipEntries = <_GalleryChipEntry>[];
    if (id != null) {
      if (gallery != null) {
        for (final it in gallery.list) {
          if (it.imgUrl.isEmpty) continue;
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: it.imgUrl,
          );
          chipEntries.add(
            _GalleryChipEntry(
              label: it.key,
              url: it.imgUrl,
              file: f,
              descHtml: it.imgDescHtml,
              kind: _ChipKind.galleryList,
            ),
          );
        }
        if (gallery.picUrl.isNotEmpty) {
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: gallery.picUrl,
          );
          chipEntries.add(
            _GalleryChipEntry(
              label: l.galleryCardLabel,
              url: gallery.picUrl,
              file: f,
              descHtml: '',
              kind: _ChipKind.galleryPic,
            ),
          );
        }
      }
      if (iconFile != null) {
        chipEntries.add(
          _GalleryChipEntry(
            label: l.galleryIconLabel,
            url: entry?.iconUrl ?? '',
            file: iconFile,
            descHtml: '',
            kind: _ChipKind.icon,
          ),
        );
      }
    }

    // 同步同步 _loadStates：首次出現的 gallery chip 若本地已有檔 → _GalleryReady;
    // 否則 → _GalleryLoading 並觸發背景下載。Icon chip 永遠 _GalleryReady。
    for (final ce in chipEntries) {
      if (_loadStates.containsKey(ce.file.path)) continue;
      switch (ce.kind) {
        case _ChipKind.icon:
          _loadStates[ce.file.path] = _GalleryReady(ce.file);
        case _ChipKind.galleryList:
        case _ChipKind.galleryPic:
          if (ce.file.existsSync()) {
            _loadStates[ce.file.path] = _GalleryReady(ce.file);
          } else {
            _loadStates[ce.file.path] = const _GalleryLoading();
            final theId = id!;
            final theUrl = ce.url;
            final theFile = ce.file;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(
                _fetchAndCache(id: theId, url: theUrl, file: theFile),
              );
            });
          }
      }
    }
```

- [ ] **Step 4: 不 commit**(Task 4.3 接著改 UI 部分）

---

### Task 4.3: 中央大圖區 — 依 state 顯示 loading / ready / failed

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`

- [ ] **Step 1: 改寫 `_precacheChipImages` — 只 precache `_GalleryReady` 的檔**

```dart
  void _precacheChipImages(
    BuildContext context,
    List<_GalleryChipEntry> entries,
  ) {
    for (final e in entries) {
      final st = _loadStates[e.file.path];
      if (st is! _GalleryReady) continue;
      if (_precachedPaths.add(e.file.path)) {
        precacheImage(FileImage(e.file), context);
      }
    }
  }
```

- [ ] **Step 2: 改寫 `build` 內中央圖區**

把 `if (currentFile != null) Expanded(...)` 整段（約 L292-326）替換為：

```dart
          if (current != null) ...[
            Expanded(
              child: _buildCurrentImageArea(context, current),
            ),
          ],
```

並在 state class 內新增 helper:

```dart
  /// 依當前 chip 的 [_GalleryLoadState] 顯示對應內容：
  ///   - Ready → Image.file（可點開縮放）
  ///   - Loading → CircularProgressIndicator
  ///   - Failed → Icon + 重試按鈕
  Widget _buildCurrentImageArea(BuildContext context, _GalleryChipEntry current) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final state = _loadStates[current.file.path] ?? const _GalleryLoading();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: switch (state) {
        _GalleryReady(:final file) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _log.info('open zoom path=${sanitizeFsPath(file.path)}');
                showZoomableImageOverlay(context, imageFile: file);
              },
              child: Image.file(
                file,
                key: ValueKey(file.path),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                gaplessPlayback: true,
                errorBuilder: (_, e, st) {
                  _log.warning(
                    'gallery image errorBuilder path=${sanitizeFsPath(file.path)}',
                    e,
                    st,
                  );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        _GalleryLoading() => Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: tokens.textSecondary,
              ),
            ),
          ),
        _GalleryFailed() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: tokens.textMuted,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  l.galleryLazyLoadFailed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                TextButton.icon(
                  onPressed: () => _retry(
                    id: current.url.isEmpty ? '' : (_extractIdFromPath(current.file.path) ?? ''),
                    url: current.url,
                    file: current.file,
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.actionRetry),
                ),
              ],
            ),
          ),
      },
    );
  }

  /// 從 cache 檔路徑反推 hoyowiki id（僅用於 retry log 標籤，失敗回 null)。
  /// 路徑樣式： `.../<id>_gallery_<hash>.<ext>` 或 `.../<id>_icon.<ext>`。
  String? _extractIdFromPath(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final underscoreIdx = base.indexOf('_');
    if (underscoreIdx <= 0) return null;
    return base.substring(0, underscoreIdx);
  }
```

`dart:io` 已 import。確認 `Platform` 可用。

- [ ] **Step 3: 跑 analyze**

Run: `flutter analyze lib/widgets/dialogs/gacha_item_detail_dialog.dart`
Expected: 0 issues。

- [ ] **Step 4: 暫不 commit**(Task 4.4 補完測試一起 commit)

---

### Task 4.4: 新增 lazy widget 測試 + 調整既有 dialog 測試

**Files:**
- Create: `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`（若既有斷言依賴「沒檔 chip 不顯示」需調整）

- [ ] **Step 1: 寫 lazy 測試 — 使用 fake fetcher**

寫入 `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';

/// 假 fetcher：可注入「永遠成功」「永遠失敗」「第一次失敗第二次成功」三種模式。
class _FakeFetcher extends HoYoWikiFetcher {
  _FakeFetcher({required this.behaviorFor}) : super();

  /// url → 該 url 該如何回應。回 null = downloadImage 回 null；回 bytes = 成功。
  final Future<Uint8List?> Function(String url, int callCount) behaviorFor;

  final Map<String, int> _calls = {};

  @override
  Future<Uint8List?> downloadImage(String url, http.Client client) {
    final n = (_calls[url] = (_calls[url] ?? 0) + 1);
    return behaviorFor(url, n);
  }
}

GachaRecord _rec({String name = 'X'}) => GachaRecord(
      id: '1',
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: 'Character',
      rankType: 5,
      time: DateTime(2026, 5, 27),
      lang: 'en-us',
    );

Future<File> _touchIcon(Directory dir, String id) async {
  final f = File('${dir.path}/${id}_icon.png');
  await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);
  return f;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dialog_lazy_test_');
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<ProviderContainer> setupContainer(_FakeFetcher fetcher) async {
    final c = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(fetcher),
      ],
    );
    addTearDown(c.dispose);
    await c.read(hoyowikiIndexProvider.notifier).waitForLoad();
    return c;
  }

  Future<void> seedEntry(WidgetTester tester, ProviderContainer c) =>
      tester.runAsync(() async {
        final n = c.read(hoyowikiIndexProvider.notifier);
        await n.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
        await n.mergeEntry(
          id: 'x1',
          lang: 'en-us',
          fetched: HoYoWikiEntryFetched(
            iconUrl: 'https://cdn/x1_icon.png',
            page: HoYoWikiPageData(
              gallery: const HoYoWikiGalleryData(
                picUrl: 'https://cdn/x1_pic.png',
                list: [
                  HoYoWikiGalleryItem(
                    id: 'g1',
                    key: 'Idle',
                    imgUrl: 'https://cdn/x1_g1.gif',
                    imgDescHtml: '',
                  ),
                ],
              ),
              desc: '',
              tags: [],
            ),
          ),
        );
      });

  Future<void> pumpDialog(
    WidgetTester tester,
    ProviderContainer c,
    GachaRecord r,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: nav.context,
        builder: (_) => GachaItemDetailDialog(record: r),
      ),
    );
    await tester.pump();
  }

  testWidgets('initState 為每個 gallery URL 觸發 fetch', (tester) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
    final c = await setupContainer(fetcher);
    await seedEntry(tester, c);
    await tester.runAsync(() async {
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialog(tester, c, _rec());
    await tester.pumpAndSettle();

    // 2 個 gallery URL(picUrl + list[0]）應各被打一次
    expect(fetcher._calls['https://cdn/x1_pic.png'], 1);
    expect(fetcher._calls['https://cdn/x1_g1.gif'], 1);
  });

  testWidgets('loading → ready:bytes 回來後寫入 cache 並顯示 Image.file', (tester) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => fakeBytes);
    final c = await setupContainer(fetcher);
    await seedEntry(tester, c);
    await tester.runAsync(() async {
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialog(tester, c, _rec());
    await tester.pumpAndSettle();

    // cache 檔已寫入
    final dir = tempDir.listSync().whereType<File>().toList();
    expect(
      dir.any((f) => f.path.contains('_gallery_')),
      isTrue,
      reason: 'lazy fetch 後 gallery cache 檔應存在',
    );
  });

  testWidgets('downloadImage 回 null → UI 顯示重試按鈕', (tester) async {
    final fetcher = _FakeFetcher(behaviorFor: (url, n) async => null);
    final c = await setupContainer(fetcher);
    await seedEntry(tester, c);
    await tester.runAsync(() async {
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialog(tester, c, _rec());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.refresh), findsWidgets);
  });

  testWidgets('重試：第一次 null 第二次成功', (tester) async {
    final fakeBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final fetcher = _FakeFetcher(
      behaviorFor: (url, n) async => n == 1 ? null : fakeBytes,
    );
    final c = await setupContainer(fetcher);
    await seedEntry(tester, c);
    await tester.runAsync(() async {
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialog(tester, c, _rec());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.refresh), findsWidgets);

    // 按下重試
    await tester.tap(find.byIcon(Icons.refresh).first);
    await tester.pumpAndSettle();

    // 第二次成功 → 重試按鈕應消失
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('dispose race:close dialog 期間 fetch 未完成，不拋例外', (tester) async {
    final completer = Completer<Uint8List?>();
    final fetcher = _FakeFetcher(behaviorFor: (url, n) => completer.future);
    final c = await setupContainer(fetcher);
    await seedEntry(tester, c);
    await tester.runAsync(() async {
      await _touchIcon(tempDir, 'x1');
    });

    await pumpDialog(tester, c, _rec());
    await tester.pump();

    // 關 dialog
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();

    // 然後讓 fetch 完成 — 不應拋
    completer.complete(Uint8List.fromList([1, 2, 3]));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: 跑 lazy 測試**

Run: `flutter test test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart`
Expected: All tests pass。若有 fail，通常是 chip 找不到 / pump 順序問題，debug 後修。

- [ ] **Step 3: 跑既有 dialog test 檢查回歸**

Run: `flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart`
Expected:
- 若有「existsSync 過濾掉 chip」相關斷言失敗 → 改為「chip 列展示全部 known URL，本地沒檔則顯示 loading/placeholder」斷言
- 「icon 不存在 → 無 Image」這類測試不受影響（`hasHoYoWikiContent` 邏輯不變）

調整失敗 case 後再跑一次直到 pass。

- [ ] **Step 4: 跑全套單測**

Run: `flutter test`
Expected: All tests pass。

- [ ] **Step 5: Commit(Task 4.1 ~ 4.4 一次 commit)**

```powershell
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/
git commit -m "feat(hoyowiki): lazy-load gallery images on dialog open"
```

---

## Phase 5 — Settings UI + i18n

### Task 5.1: 新增 i18n keys(`app_zh.arb` 為基準）

**Files:**
- Modify: `lib/l10n/app_zh.arb`

- [ ] **Step 1: 找到既有 `settingsRefetchHoyoWikiImagesTitle` 區塊（L322 附近）後加入新 keys**

於該 block 之後插入（注意逗號收尾）:

```json
  "settingsImageCache": "圖片快取",
  "@settingsImageCache": {
    "description": "Settings page section title for image cache controls."
  },
  "settingsImageCacheTotal": "總計",
  "@settingsImageCacheTotal": {
    "description": "Label for total cache size (icon + gallery)."
  },
  "settingsImageCacheIcons": "小圖示",
  "@settingsImageCacheIcons": {
    "description": "Label for icon cache size (small thumbnails shown in wish list)."
  },
  "settingsImageCacheGallery": "詳情圖",
  "@settingsImageCacheGallery": {
    "description": "Label for gallery cache size (large detail images shown in item dialog)."
  },
  "settingsImageCacheCalculating": "計算中…",
  "@settingsImageCacheCalculating": {
    "description": "Loading placeholder while scanning cache size."
  },
  "settingsImageCacheFailed": "無法讀取快取大小",
  "@settingsImageCacheFailed": {
    "description": "Shown when scanning cache size fails (e.g. permission denied)."
  },
  "settingsImageCacheClearGallery": "清除詳情圖快取",
  "@settingsImageCacheClearGallery": {
    "description": "Button label: clear gallery cache (keeps icons)."
  },
  "confirmClearGalleryCacheTitle": "清除詳情圖快取?",
  "@confirmClearGalleryCacheTitle": {
    "description": "Confirmation dialog title for clearing gallery cache."
  },
  "confirmClearGalleryCacheBody": "將刪除約 {size} 的物品詳情圖檔，小圖示快取保留。下次打開物品詳情時會重新下載。",
  "@confirmClearGalleryCacheBody": {
    "description": "Confirmation dialog body for clearing gallery cache; {size} is formatted bytes string (e.g. '123.4 MB').",
    "placeholders": {
      "size": { "type": "String" }
    }
  },
  "confirmClearGalleryCacheConfirm": "清除",
  "@confirmClearGalleryCacheConfirm": {
    "description": "Confirm button label for clearing gallery cache."
  },
  "galleryLazyLoadFailed": "圖片載入失敗",
  "@galleryLazyLoadFailed": {
    "description": "Placeholder text shown in item dialog when a gallery image fails to download."
  },
  "actionRetry": "重試",
  "@actionRetry": {
    "description": "Generic retry button label."
  },
```

確認 JSON 整體仍合法（逗號、結尾大括號）。

- [ ] **Step 2: 跑 codegen**

Run: `flutter gen-l10n`
Expected: 0 errors,`lib/l10n/generated/app_localizations*.dart` 重新生成。

- [ ] **Step 3: 跑 analyze**

Run: `flutter analyze`
Expected: 0 issues（尚未有使用點，但 generated key 已存在不會 warning)。

- [ ] **Step 4: 不 commit**(Task 5.2 / 5.3 一起 commit i18n)

---

### Task 5.2: 修改 `confirmRefetchHoyoWikiBody`(`app_zh.arb`)

**Files:**
- Modify: `lib/l10n/app_zh.arb`(L334 附近）

- [ ] **Step 1: 替換 value 文字**

把：

```json
"confirmRefetchHoyoWikiBody": "這會清空所有物品圖片的本機快取並重新從 HoYoWiki 抓取。視物品數量可能耗費數分鐘流量與時間。",
```

改為：

```json
"confirmRefetchHoyoWikiBody": "這會清空所有物品圖片的本機快取並重新從 HoYoWiki 抓取小圖示。物品詳情大圖會在你下次打開該物品時自動下載。視物品數量可能耗費數分鐘流量與時間。",
```

- [ ] **Step 2: 跑 codegen 與 analyze**

Run: `flutter gen-l10n && flutter analyze`
Expected: 0 errors。

- [ ] **Step 3: 不 commit**(Task 5.3 一起）

---

### Task 5.3: 翻譯到其他 8 個非空殼 ARB

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_pt_BR.arb`
- Modify: `lib/l10n/app_th.arb`
- Modify: `lib/l10n/app_vi.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`

> **規則重述**(memory `feedback_i18n_skip_empty_arbs` + `feedback_i18n_starts_from_zh`)：空殼 ARB 不碰，留給 Crowdin pipeline。新增 key 與修改既有 key 文字，所有「非空殼 ARB」都要同步翻譯。

- [ ] **Step 1: 對每個非空殼 ARB，於既有 `confirmRefetchHoyoWikiBody` 位置後加入相同 12 個新 keys 翻譯**

為避免 plan 過長，翻譯內容請依以下參考表填入（語意對齊，各語言用該語言的自然慣用語）:

| key | en | ja | fr | es | pt-BR | th | vi | zh-Hans |
|---|---|---|---|---|---|---|---|---|
| `settingsImageCache` | Image cache | 画像キャッシュ | Cache d'images | Caché de imágenes | Cache de imagens | แคชรูปภาพ | Bộ nhớ đệm hình ảnh | 图片缓存 |
| `settingsImageCacheTotal` | Total | 合計 | Total | Total | Total | รวม | Tổng | 总计 |
| `settingsImageCacheIcons` | Icons | アイコン | Icônes | Iconos | Ícones | ไอคอน | Biểu tượng | 小图标 |
| `settingsImageCacheGallery` | Detail images | 詳細画像 | Images détaillées | Imágenes detalladas | Imagens detalhadas | รูปรายละเอียด | Ảnh chi tiết | 详情图 |
| `settingsImageCacheCalculating` | Calculating… | 計算中… | Calcul… | Calculando… | Calculando… | กำลังคำนวณ… | Đang tính… | 计算中… |
| `settingsImageCacheFailed` | Unable to read cache size | キャッシュサイズを読み取れません | Impossible de lire la taille du cache | No se puede leer el tamaño del caché | Não foi possível ler o tamanho do cache | ไม่สามารถอ่านขนาดแคชได้ | Không thể đọc kích thước bộ nhớ đệm | 无法读取缓存大小 |
| `settingsImageCacheClearGallery` | Clear detail images | 詳細画像をクリア | Effacer les images détaillées | Borrar imágenes detalladas | Limpar imagens detalhadas | ล้างรูปรายละเอียด | Xoá ảnh chi tiết | 清除详情图 |
| `confirmClearGalleryCacheTitle` | Clear detail images? | 詳細画像をクリアしますか? | Effacer les images détaillées ? | ¿Borrar imágenes detalladas? | Limpar imagens detalhadas? | ล้างรูปรายละเอียดหรือไม่? | Xoá ảnh chi tiết? | 清除详情图? |
| `confirmClearGalleryCacheBody` | About {size} of item detail images will be deleted; icon cache is kept. They will re-download next time you open the item detail. | アイテム詳細画像 約 {size} を削除します。小アイコンキャッシュは保持されます。次回アイテム詳細を開いたときに再ダウンロードされます。 | Environ {size} d'images de détail seront supprimées ; le cache des icônes est conservé. Elles seront re-téléchargées la prochaine fois que vous ouvrirez le détail. | Se eliminarán aproximadamente {size} de imágenes detalladas; el caché de iconos se conserva. Se volverán a descargar la próxima vez que abras el detalle del objeto. | Cerca de {size} de imagens detalhadas serão excluídas; o cache de ícones é preservado. Serão baixadas novamente na próxima vez que você abrir os detalhes do item. | จะลบรูปรายละเอียดประมาณ {size} แคชไอคอนจะถูกเก็บไว้ จะดาวน์โหลดใหม่เมื่อเปิดรายละเอียดครั้งถัดไป | Khoảng {size} ảnh chi tiết sẽ bị xoá; bộ nhớ đệm biểu tượng được giữ lại. Sẽ tải lại lần tới khi bạn mở chi tiết vật phẩm. | 将删除约 {size} 的物品详情图，小图标缓存保留。下次打开物品详情时会重新下载。 |
| `confirmClearGalleryCacheConfirm` | Clear | クリア | Effacer | Borrar | Limpar | ล้าง | Xoá | 清除 |
| `galleryLazyLoadFailed` | Image failed to load | 画像の読み込みに失敗しました | Échec du chargement de l'image | Error al cargar la imagen | Falha ao carregar a imagem | โหลดรูปภาพไม่สำเร็จ | Tải ảnh thất bại | 图片加载失败 |
| `actionRetry` | Retry | 再試行 | Réessayer | Reintentar | Tentar novamente | ลองอีกครั้ง | Thử lại | 重试 |

每個 ARB 都加上對應翻譯與 `@key` 的 description metadata（可從 `app_zh.arb` 複製 description 區塊，description 用英文寫即可，沿用 zh ARB 的 metadata)。

- [ ] **Step 2: 每個 ARB 也修改 `confirmRefetchHoyoWikiBody`**

各語言對應（模板：「icon 立即抓，gallery 開物品詳情再抓」):

| lang | confirmRefetchHoyoWikiBody |
|---|---|
| en | This will clear all local item image cache and re-download icons from HoYoWiki. Item detail images will be downloaded on demand next time you open the item. Depending on item count, this may take several minutes of bandwidth and time. |
| ja | すべての物品画像のローカルキャッシュを消去し、HoYoWiki から小アイコンを再ダウンロードします。物品詳細の大きな画像は次回開いた際に自動的にダウンロードされます。物品数によっては数分かかる場合があります。 |
| fr | Ceci effacera le cache local de toutes les images d'objets et re-téléchargera les icônes depuis HoYoWiki. Les images de détail seront téléchargées à la demande lors de la prochaine ouverture de l'objet. Selon le nombre d'objets, cela peut prendre plusieurs minutes. |
| es | Esto borrará el caché local de todas las imágenes de objetos y volverá a descargar los iconos desde HoYoWiki. Las imágenes detalladas se descargarán a demanda la próxima vez que abras el objeto. Según la cantidad de objetos, puede tardar varios minutos. |
| pt-BR | Isto limpará o cache local de todas as imagens de itens e baixará novamente os ícones do HoYoWiki. As imagens detalhadas serão baixadas sob demanda na próxima vez que você abrir o item. Dependendo da quantidade de itens, pode levar vários minutos. |
| th | จะล้างแคชรูปภาพไอเทมทั้งหมดในเครื่องและดาวน์โหลดไอคอนใหม่จาก HoYoWiki รูปรายละเอียดจะถูกดาวน์โหลดเมื่อเปิดไอเทมครั้งถัดไป อาจใช้เวลาหลายนาทีขึ้นอยู่กับจำนวนไอเทม |
| vi | Thao tác này sẽ xoá bộ nhớ đệm hình ảnh vật phẩm cục bộ và tải lại biểu tượng từ HoYoWiki. Ảnh chi tiết sẽ được tải khi bạn mở vật phẩm lần tới. Tuỳ vào số lượng vật phẩm, có thể mất vài phút. |
| zh-Hans | 这会清空所有物品图片的本机缓存并重新从 HoYoWiki 抓取小图标。物品详情大图会在你下次打开该物品时自动下载。视物品数量可能耗费数分钟流量与时间。 |

- [ ] **Step 3: 跑 codegen 確認所有 ARB 都解析成功**

Run: `flutter gen-l10n`
Expected: 0 errors；若 JSON 有逗號/引號錯，gen-l10n 會明確指出哪個 ARB 哪一行，修。

- [ ] **Step 4: 跑 analyze + 全套 test**

Run: `flutter analyze; flutter test`
Expected: 0 issues + All tests pass。

- [ ] **Step 5: Commit i18n 變動**

```powershell
git add lib/l10n/
git commit -m "i18n: add image-cache section keys and clarify refetch body (lazy gallery)"
```

---

### Task 5.4: 新增 `_ImageCacheSection` widget

**Files:**
- Modify: `lib/pages/settings_page.dart`（在 `_DataManagement` 後新增 `_ImageCacheSection`；暫時不動 `_DataManagement` 內既有 refetch 按鈕，Task 5.5 一起搬遷）

- [ ] **Step 1: 在 `settings_page.dart` 檔案末尾（`_LogsSection` 之前或 `_DataManagement` 之後）新增 `_ImageCacheSection`**

```dart
/// 圖片快取區塊：顯示用量（icon / gallery / 總計），提供「清除詳情圖快取」
/// 與「強制重抓物品圖片」按鈕。
class _ImageCacheSection extends ConsumerWidget {
  const _ImageCacheSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final usageAsync = ref.watch(hoyowikiCacheUsageProvider);
    final hasData = ref.watch(
      gachaRepositoryProvider.select((s) => s.byUid.isNotEmpty),
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        usageAsync.when(
          loading: () => _UsageRows(
            total: l.settingsImageCacheCalculating,
            icons: l.settingsImageCacheCalculating,
            gallery: l.settingsImageCacheCalculating,
            muted: true,
            tokens: tokens,
            theme: theme,
            l: l,
          ),
          error: (e, st) => Text(
            l.settingsImageCacheFailed,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.stateDanger,
            ),
          ),
          data: (u) => _UsageRows(
            total: formatBytes(u.totalBytes),
            icons: formatBytes(u.iconBytes),
            gallery: formatBytes(u.galleryBytes),
            muted: false,
            tokens: tokens,
            theme: theme,
            l: l,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: tokens.stateDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: usageAsync.valueOrNull == null
                  ? null
                  : () => _clearGallery(context, ref),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text(l.settingsImageCacheClearGallery),
            ),
            Tooltip(
              message: !hasData ? l.settingsRefetchHoyoWikiImagesEmpty : '',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.stateDanger,
                  foregroundColor: Colors.white,
                ),
                onPressed: (!hasData || progress != null)
                    ? null
                    : () => _refetchAll(context, ref),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.settingsRefetchHoyoWikiImagesTitle),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 顯示「清除詳情圖快取」確認 dialog，確認後呼叫 `deleteGalleryCacheFiles`。
  Future<void> _clearGallery(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final usage = ref.read(hoyowikiCacheUsageProvider).valueOrNull;
    final sizeText = usage == null ? '' : formatBytes(usage.galleryBytes);
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AppDialog(
        title: Text(l.confirmClearGalleryCacheTitle),
        content: Text(l.confirmClearGalleryCacheBody(sizeText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(d).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l.confirmClearGalleryCacheConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final storage = ref.read(hoyowikiIndexStorageProvider);
      await storage.deleteGalleryCacheFiles();
      if (!ctx.mounted) return;
      ref.invalidate(hoyowikiCacheUsageProvider);
      Logger('gacha.hoyowiki.storage').info('user cleared gallery cache');
    } catch (e, st) {
      Logger('gacha.hoyowiki.storage').warning('clear gallery failed', e, st);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImageCacheFailed)),
      );
    }
  }

  /// 顯示確認 dialog，確認後呼叫 [GachaRepository.forceRefetchAllHoYoWikiImages]。
  Future<void> _refetchAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AppDialog(
        title: Text(l.confirmRefetchHoyoWikiTitle),
        content: Text(l.confirmRefetchHoyoWikiBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(d).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l.confirmRefetchHoyoWikiConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(
      ref
          .read(gachaRepositoryProvider.notifier)
          .forceRefetchAllHoYoWikiImages(),
    );
  }
}

/// 「總計 / 小圖示 / 詳情圖」三行用量顯示。
class _UsageRows extends StatelessWidget {
  const _UsageRows({
    required this.total,
    required this.icons,
    required this.gallery,
    required this.muted,
    required this.tokens,
    required this.theme,
    required this.l,
  });

  final String total;
  final String icons;
  final String gallery;
  final bool muted;
  final GachaTokens tokens;
  final ThemeData theme;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: muted ? tokens.textMuted : tokens.textPrimary,
    );
    final secondaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: muted ? tokens.textMuted : tokens.textSecondary,
    );
    Widget row(String label, String value, TextStyle? style) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text(value, style: style),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(l.settingsImageCacheTotal, total, labelStyle),
        row(l.settingsImageCacheIcons, icons, secondaryStyle),
        row(l.settingsImageCacheGallery, gallery, secondaryStyle),
      ],
    );
  }
}
```

確認新加 import:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/format_bytes.dart';
```

(`AppDialog` / `AppLocalizations` / `Logger` 等已 import)

- [ ] **Step 2: 跑 analyze**

Run: `flutter analyze`
Expected: 0 issues。可能會有 `_ImageCacheSection unused` warning（尚未掛上 `SettingsPage`),Task 5.5 處理。

- [ ] **Step 3: 不 commit**

---

### Task 5.5: 把 `_ImageCacheSection` 掛上 `SettingsPage` 並從 `_DataManagement` 移除重抓按鈕

**Files:**
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: 在 `SettingsPage.build` 的 children 內，於「資料管理」section 之後、「帳號管理」之前插入新 section**

```dart
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsImageCache,
                icon: Icons.image_outlined,
                child: const _ImageCacheSection(),
              ),
```

- [ ] **Step 2: 從 `_DataManagement.build` 的 Wrap children 移除「強制重抓物品圖片」 button**

刪除整個 `Tooltip(... FilledButton.icon(... settingsRefetchHoyoWikiImagesTitle ...))` 區塊。

- [ ] **Step 3: 從 `_DataManagement` class 移除 `_refetchHoYoWikiImages` private method**

整段 `Future<void> _refetchHoYoWikiImages(BuildContext ctx, WidgetRef ref) async { ... }`(L658-690）刪除。

- [ ] **Step 4: 跑 analyze**

Run: `flutter analyze`
Expected: 0 issues（若有 unused import 警告，例如某 import 只給 `_refetchHoYoWikiImages` 用過，移除）。

- [ ] **Step 5: 寫 widget 測試 — `_ImageCacheSection` 顯示用量**

寫入 `test/pages/settings_image_cache_section_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_img_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> touch(String name, int size) async {
    await File('${tempDir.path}/$name').writeAsBytes(List<int>.filled(size, 0));
  }

  testWidgets('用量顯示三行（總計 / 小圖示 / 詳情圖）', (tester) async {
    await touch('a_icon.png', 1024 * 100);  // 100 KB icon
    await touch('a_gallery_xxxxxxxxxxxx.png', 1024 * 1024 * 2);  // 2 MB gallery

    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('100.0 KB'), findsOneWidget);  // icon
    expect(find.text('2.0 MB'), findsOneWidget);    // gallery
    // 總計 = 100 KB + 2048 KB = 2148 KB → 2.1 MB (rounded)
    expect(find.text('2.1 MB'), findsOneWidget);
  });
}
```

- [ ] **Step 6: 跑測試**

Run: `flutter test test/pages/settings_image_cache_section_test.dart`
Expected: All tests pass。

- [ ] **Step 7: 跑全套品質檢查（對齊 CLAUDE.md 提交前 checklist)**

```powershell
dart format lib/ test/
flutter analyze
flutter test
```

Expected:
- format 無 diff（若有，git add)
- analyze:`No issues found!`
- test:`All tests passed!`

- [ ] **Step 8: Commit**

```powershell
git add lib/pages/settings_page.dart test/pages/
git commit -m "feat(settings): add image cache section (usage + clear gallery, refetch moved here)"
```

---

## 最終驗收 checklist

- [ ] **跑 `flutter analyze`** → `No issues found!`
- [ ] **跑 `flutter test`** → `All tests passed!`
- [ ] **手測**:
  - 啟動 app → 進設定頁 → 看到「圖片快取」 section + 三行用量
  - 「清除詳情圖快取」→ 確認 dialog → 點清除 → 用量降低 → 打開角色 dialog → 看到 loading → 載完顯示
  - 中斷網路 → 打開新角色 dialog → 看到失敗 placeholder → 重試
  - 「強制重抓物品圖片」 → 確認 dialog 文字含「物品詳情大圖會在你下次打開該物品時自動下載」
- [ ] **memory 注意事項驗證**:
  - 既有 InkWell 顯式 cursor 規則：本次無 InkWell 新增，跳過
  - testWidgets 用 tempDir 圖檔 → `tearDown` 清 `ImageCache`（已在 Task 4.4 / 5.5 test 模板中）
  - PR 不主動推：**不 git push**

---

## Self-Review

**1. Spec coverage**

| spec 章節 | 對應 task |
|---|---|
| §1 整體流程改動 | Phase 3 （移除 gallery enqueue) + Phase 4 (dialog lazy) |
| §2 dialog 重構（`_loadStates`、`_GalleryLoadState`、fetch/dispose race) | Task 4.1 + 4.2 + 4.3 |
| §3.1 cache usage model + provider | Task 1.2 |
| §3.2 format_bytes 三段 | Task 1.1 |
| §3.3 設定頁 SectionCard | Task 5.4 + 5.5 |
| §3.4 「清除詳情圖快取」邏輯 + `deleteGalleryCacheFiles` | Task 2.1 + Task 5.4 `_clearGallery` |
| §3.5 invalidation 點 | Task 5.4 `_clearGallery` 內 `ref.invalidate(...)` |
| §3.6 「強制重抓」搬遷 + body 文字更新 | Task 5.2 + 5.3 + 5.5 |
| §4.4 測試計畫 1~10 項 | Task 1.1 / 1.2 / 2.1 / 4.4 / 5.5 涵蓋（refetch test 調整在 Task 3.2) |

無 spec gap。

**2. Placeholder scan**

- 「無 TBD / TODO / fill in details」 — pass
- 「translation 給了實際字串而非 placeholder」 — pass(Task 5.3 有完整表）
- 「測試 / 程式碼皆 inline code block 完整」 — pass

**3. Type consistency**

- `_GalleryLoadState` / `_GalleryLoading` / `_GalleryReady` / `_GalleryFailed`:Task 4.1 定義，Task 4.2 / 4.3 使用，名稱一致
- `formatBytes` 簽名 `String formatBytes(int bytes)`:Task 1.1 定義，Task 5.4 使用，簽名一致
- `HoYoWikiCacheUsage` 三 field `iconBytes` / `galleryBytes` / `totalBytes`:Task 1.2 定義，Task 5.4 使用，一致
- `deleteGalleryCacheFiles()`:Task 2.1 定義（無參數，`Future<void>`),Task 5.4 使用，一致
- `hoyowikiCacheUsageProvider`:Task 1.2 是 `FutureProvider.autoDispose`,Task 5.4 用 `.when(...)` / `.valueOrNull`，一致

無不一致。
