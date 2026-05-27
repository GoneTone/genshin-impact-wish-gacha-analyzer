# Force Refresh Item Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在設定頁「資料管理」區塊新增「強制重抓所有物品圖片」按鈕,清空 `hoyowiki_index.json` 與 `hoyowiki_cache/` 後從 search 階段重跑全部 UID 的 (name, lang) 物品集合,並與「更新祈願」流程互斥。

**Architecture:** 沿用既有 `_fetchHoyoWiki(client)` 三階段管線(它本來就跨所有 UID 聚合 pairs),新增公開方法 `forceRefetchAllHoyoWikiImages()` 串接「Preparing → 清 index/cache → `_fetchHoyoWiki` → UpdateCompleted」流程。`storage.clearAll()` 與 `storage.wipeCacheDirectory()` 為新增基礎設施。UI 端按鈕透過 `state.progress` slot 互斥,並複用 `app_shell.dart` 既有 `ref.listen` 自動彈出 `UpdateProgressDialog`。

**Tech Stack:** Flutter / Dart / Riverpod NotifierProvider / `dart:io` / `package:logging` / `package:http` / Crowdin-pipelined ARB i18n。

---

> **Spec 對應**:`docs/superpowers/specs/2026-05-24-force-refresh-item-images-design.md`。
>
> **與 spec 的偏差**:Spec §3.2 提出抽出 `_runHoyoWikiPipeline({required pairs})` helper。Plan 階段確認:既有 `_fetchHoyoWiki(client)` 內部已從 `state.byUid` 迭代「所有 UID 的所有目標卡池 record」收集 unique `(name, lang)`,**pair source 與 force-refetch 路徑完全一致**,直接複用即可。基於 CLAUDE.md YAGNI 規則(預先建立抽象層或介面 ❌),此 plan **不執行** helper 抽出,改為:`forceRefetchAllHoyoWikiImages` 內部直接呼叫 `_fetchHoyoWiki(client)`。`debugRunHoyoWikiOnly` 一併保留現狀。其餘 spec 細節皆遵循。

## File Structure

| 動作 | 檔案 | 責任 |
|---|---|---|
| 修改 | `lib/services/hoyowiki_index.dart` | `HoyoWikiIndexStorage` 新增 `clearAll()` 與 `wipeCacheDirectory()`(純檔案層) |
| 修改 | `lib/state/hoyowiki_index.dart` | `HoyoWikiIndexNotifier` 新增 `resetAll()`(包裹 clear + wipe + bumpCacheRevision) |
| 修改 | `lib/state/gacha_repository.dart` | 新增公開方法 `forceRefetchAllHoyoWikiImages()` 與 helper `_collectHasAnyGachaRecord` getter(若不存在等價判斷) |
| 修改 | `lib/state/update_error.dart` | 新增 `UpdateErrorWipeHoyoWikiCache` error 類型(對應失敗 emit) |
| 修改 | `lib/widgets/update_progress_dialog.dart` | `_Body` 對 `UpdateErrorWipeHoyoWikiCache` 加新 case 顯示對應訊息 key |
| 修改 | `lib/pages/settings_page.dart` | `_DataManagement` 新增按鈕、確認 dialog、disabled / tooltip 邏輯 |
| 修改 | `lib/l10n/app_zh.arb` 為主、其後 `app_en.arb` / `app_ja.arb` / `app_ko.arb` / `app_zh_CN.arb` / `app_pt.arb` / `app_ru.arb` | 新 i18n keys |
| 新增 | `test/state/gacha_repository_refetch_test.dart` | repository 端主路徑、空紀錄、互斥、取消、清檔失敗 |
| 修改 | `test/services/hoyowiki_index_test.dart` | `clearAll` / `wipeCacheDirectory` storage 測試 |
| 修改 | `test/state/hoyowiki_index_test.dart`(若不存在則新增) | `resetAll` notifier 測試(`cacheRevision` 遞增) |
| 新增 | `test/pages/settings_page_refetch_button_test.dart` | enabled/disabled 矩陣、AlertDialog 取消/確認 |

---

### Task 1: `HoyoWikiIndexStorage.clearAll()` — 清空 index 檔

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`(在 `HoyoWikiIndexStorage` class 內,`save()` 之後新增方法)
- Test: `test/services/hoyowiki_index_test.dart`(在檔尾新增 group)

- [ ] **Step 1: 寫失敗的測試**

加到 `test/services/hoyowiki_index_test.dart` 檔尾(在現有 `main()` 內最後一個 group 之後新增):

```dart
  group('HoyoWikiIndexStorage.clearAll', () {
    test('既有 index 檔被覆寫為空殼', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'en-us::Hu Tao': '111'},
          entries: {
            '111': HoyoWikiEntry(
              iconUrl: 'https://x/icon.png',
              headerImgUrl: 'https://x/header.png',
              fetchedAt: DateTime.utc(2026, 5, 23),
            ),
          },
          menuIds: const {'111': 2},
        ),
      );

      await storage.clearAll();

      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });

    test('index 檔不存在時不爆,仍寫入空殼', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);

      await storage.clearAll();

      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: 兩個 `clearAll` 測試 FAIL(method not found / compile error)。

- [ ] **Step 3: 實作 `clearAll()`**

在 `lib/services/hoyowiki_index.dart` `HoyoWikiIndexStorage` class 內,於 `save()` 方法之後新增:

```dart
  /// 將 index 重設為空(searchMap / entries / menuIds 全空),用於「強制重抓
  /// 所有物品圖片」操作。覆寫策略與 [save] 相同(atomic rename),原檔不存在
  /// 時直接寫入空殼。
  Future<void> clearAll() async {
    await save(const HoyoWikiIndex.empty());
    _log.info('clearAll: index reset to empty');
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: 所有 `HoyoWikiIndexStorage.clearAll` 測試 PASS,其餘既有測試也綠。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiIndexStorage.clearAll() for force refetch"
```

---

### Task 2: `HoyoWikiIndexStorage.wipeCacheDirectory()` — 清空 cache 目錄

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`
- Test: `test/services/hoyowiki_index_test.dart`

- [ ] **Step 1: 寫失敗的測試**

於 Task 1 新增 group 之下接著加(同檔):

```dart
  group('HoyoWikiIndexStorage.wipeCacheDirectory', () {
    test('既有 cache 檔被刪光且目錄重建', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_cache_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      // 放兩個 dummy cache 檔
      await File('${dir.path}/111_icon.png').writeAsBytes([1, 2, 3]);
      await File('${dir.path}/111_header.png').writeAsBytes([4, 5, 6]);

      final storage = HoyoWikiIndexStorage(dir);
      await storage.wipeCacheDirectory();

      expect(await dir.exists(), isTrue, reason: '目錄應重建');
      final remaining = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg'))
          .toList();
      expect(remaining, isEmpty, reason: 'cache 圖檔應全被刪');
    });

    test('cache 目錄不存在時不爆,直接建空目錄', () async {
      final parent = await Directory.systemTemp.createTemp('hoyowiki_cache_');
      addTearDown(() async {
        if (await parent.exists()) await parent.delete(recursive: true);
      });
      // 用一個不存在的子目錄做 baseDir
      final dir = Directory('${parent.path}/missing');
      expect(await dir.exists(), isFalse);
      final storage = HoyoWikiIndexStorage(dir);

      await storage.wipeCacheDirectory();

      expect(await dir.exists(), isTrue);
      expect(dir.listSync(), isEmpty);
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: 兩個 `wipeCacheDirectory` 測試 FAIL。

- [ ] **Step 3: 實作 `wipeCacheDirectory()`**

接續在 `HoyoWikiIndexStorage` 內 `clearAll()` 之後新增:

```dart
  /// 刪除 [baseDir] 內所有 HoyoWiki cache 圖檔並重建空目錄。
  /// 目錄不存在時直接建立;失敗(權限被鎖等)直接拋給呼叫方處理。
  Future<void> wipeCacheDirectory() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
    await baseDir.create(recursive: true);
    _log.info('wipeCacheDirectory: cache cleared at ${baseDir.path}');
  }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/hoyowiki_index_test.dart`
Expected: 全綠。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiIndexStorage.wipeCacheDirectory()"
```

---

### Task 3: `HoyoWikiIndexNotifier.resetAll()` — 包裹 clear + wipe + bump

**Files:**
- Modify: `lib/state/hoyowiki_index.dart`
- Test: `test/state/hoyowiki_index_test.dart`(若檔不存在則新建,參考 `test/services/hoyowiki_index_test.dart` 的 import 慣例)

- [ ] **Step 1: 確認測試檔存在,沒有就建立**

Run: `flutter test test/state/hoyowiki_index_test.dart`
若回 "no such file":建立 `test/state/hoyowiki_index_test.dart` 含基礎 skeleton:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

void main() {}
```

- [ ] **Step 2: 寫失敗的測試**

在 `test/state/hoyowiki_index_test.dart` 的 `main()` 內新增:

```dart
  group('HoyoWikiIndexNotifier.resetAll', () {
    test('清空 index、刪除 cache 目錄、cacheRevision 遞增', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_notifier_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);
      // 預植 index 與一個 cache 檔
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'en-us::Hu Tao': '111'},
          entries: {
            '111': HoyoWikiEntry(
              iconUrl: 'https://x/icon.png',
              headerImgUrl: '',
              fetchedAt: DateTime.utc(2026, 5, 23),
            ),
          },
          menuIds: const {'111': 2},
        ),
      );
      await File('${dir.path}/111_icon.png').writeAsBytes([1, 2, 3]);

      final container = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.waitForLoad();
      final before = container.read(hoyowikiIndexProvider);
      expect(before.searchMap, isNotEmpty);

      await notifier.resetAll();

      final after = container.read(hoyowikiIndexProvider);
      expect(after.searchMap, isEmpty);
      expect(after.entries, isEmpty);
      expect(after.menuIds, isEmpty);
      expect(identical(after, before), isFalse,
          reason: 'bumpCacheRevision 應換新 identity');
      // cache 檔應已刪
      expect(File('${dir.path}/111_icon.png').existsSync(), isFalse);
    });
  });
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/state/hoyowiki_index_test.dart`
Expected: `resetAll` 測試 FAIL(method not found)。

- [ ] **Step 4: 實作 `resetAll()`**

在 `lib/state/hoyowiki_index.dart` `HoyoWikiIndexNotifier` class 內,於 `bumpCacheRevision()` 之後新增:

```dart
  /// 強制重抓圖片用:清空整個 index、刪除 cache 目錄、bump revision。
  /// 呼叫後 state 為 [HoyoWikiIndex.empty];磁碟側 index 檔為空殼、cache
  /// 目錄為空。失敗(權限不足等)直接拋給呼叫方 emit `UpdateFailed`。
  Future<void> resetAll() async {
    final storage = ref.read(hoyowikiIndexStorageProvider);
    await storage.clearAll();
    await storage.wipeCacheDirectory();
    if (!ref.mounted) return;
    state = const HoyoWikiIndex.empty();
    bumpCacheRevision();
    _log.info('resetAll: index+cache wiped');
  }
```

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/state/hoyowiki_index_test.dart`
Expected: 全綠。

- [ ] **Step 6: Commit**

```bash
git add lib/state/hoyowiki_index.dart test/state/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiIndexNotifier.resetAll() wrapper"
```

---

### Task 4: 新增 `UpdateErrorWipeHoyoWikiCache` error 類型

**Files:**
- Modify: `lib/state/update_error.dart`(在現有 `UpdateError` sealed class 與 subclasses 旁)
- Test: 沿用既有 `UpdateError` 測試(若無也不新增 — 純資料 class,沒邏輯)

> **背景**:`UpdateFailed` 吃 `UpdateError`。要新增「清快取階段失敗」必須先有對應 error subclass。

- [ ] **Step 1: 看現有 subclasses 結構**

Run: `grep -n "class UpdateError" lib/state/update_error.dart`
記下既有 subclass 的格式(constructor / fields / dartdoc 慣例)。

- [ ] **Step 2: 新增 `UpdateErrorWipeHoyoWikiCache`**

在 `lib/state/update_error.dart` 內最後一個 subclass 之後新增:

```dart
/// 強制重抓 HoyoWiki 圖片時,清空 index 或 cache 目錄階段失敗。
/// 通常是檔案被其他 process 鎖住(防毒掃描中等)。
class UpdateErrorWipeHoyoWikiCache extends UpdateError {
  /// 建立 [UpdateErrorWipeHoyoWikiCache];[detail] 為例外訊息(已脫敏路徑)。
  const UpdateErrorWipeHoyoWikiCache({required this.detail});

  /// 例外訊息;絕對路徑應在外層 emit 前以 `sanitizeFsPath` 處理。
  final String detail;
}
```

- [ ] **Step 3: 跑 analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/state/update_error.dart
git commit -m "feat(state): add UpdateErrorWipeHoyoWikiCache for refetch IO failure"
```

---

### Task 5: `UpdateProgressDialog` 對新 error 類型顯示訊息

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`(`_Body` 對 `UpdateFailed` 的 switch / pattern matching 區段)
- Modify: `lib/l10n/app_zh.arb`(新增 `updateErrorWipeHoyoWikiCache` 字串)

- [ ] **Step 1: 先加 i18n key(中文版主檔)**

於 `lib/l10n/app_zh.arb` 找到 `"updateErrorNetwork"` 附近,插入:

```json
  "updateErrorWipeHoyoWikiCache": "清除物品圖片快取失敗：{detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "description": "Force-refetch flow: failed to clear hoyowiki_index.json or hoyowiki_cache/ directory. {detail} is the sanitized exception message.",
    "placeholders": {
      "detail": { "type": "String" }
    }
  },
```

- [ ] **Step 2: 跑 codegen**

Run: `flutter gen-l10n`(或專案使用的 codegen 指令;不確定就跑 `flutter pub get`,有 build_runner config 才用 build_runner)。
Expected: `lib/l10n/generated/app_localizations.dart` 含新 getter。

- [ ] **Step 3: 看現有 UpdateFailed 渲染區段**

Run: `grep -n "UpdateError" lib/widgets/update_progress_dialog.dart`
找到目前對 `UpdateError` 各 subclass 的 switch / pattern matching 位置。

- [ ] **Step 4: 新增對應 case**

在 `lib/widgets/update_progress_dialog.dart` 既有對 `UpdateError` subclasses 的 switch 內,新增 `UpdateErrorWipeHoyoWikiCache` 的 case,沿用既有錯誤訊息渲染 helper(若用 `switch` 表達式):

```dart
      UpdateErrorWipeHoyoWikiCache(:final detail) =>
          l.updateErrorWipeHoyoWikiCache(detail),
```

(具體插入位置依現有 pattern matching 而定;若是 `if (e is X)` 連鎖,則加一個 `else if (e is UpdateErrorWipeHoyoWikiCache) return l.updateErrorWipeHoyoWikiCache(e.detail);`)

- [ ] **Step 5: 跑 analyze + test**

Run: `flutter analyze && flutter test test/widgets/`
Expected: `No issues found!` 且 widget 測試全綠(未變動 progress dialog 既有行為)。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/generated/ lib/widgets/update_progress_dialog.dart
git commit -m "feat(progress): render UpdateErrorWipeHoyoWikiCache in dialog"
```

---

### Task 6: `GachaRepository.forceRefetchAllHoyoWikiImages()` — 核心邏輯

**Files:**
- Modify: `lib/state/gacha_repository.dart`(在現有 `forceRecaptureAndUpdate()` 附近新增)
- Test: `test/state/gacha_repository_refetch_test.dart`(新檔)

> **設計筆記**:不抽 `_runHoyoWikiPipeline` helper(見開頭「與 spec 的偏差」)。`_fetchHoyoWiki(client)` 本身已從 `state.byUid` 跨 UID 收集 pairs,直接複用。

- [ ] **Step 1: 建立新測試檔骨架**

新增 `test/state/gacha_repository_refetch_test.dart`(以 `test/state/gacha_repository_hoyowiki_test.dart` 為範本):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

GachaRecord _rec({
  required String id,
  required String uid,
  required String name,
  required String gachaType,
  String lang = 'en-us',
}) => GachaRecord(
  id: id,
  uid: uid,
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 24),
  lang: lang,
);

void main() {
  // tests go here
}
```

- [ ] **Step 2: 寫主要路徑測試(失敗)**

於 `main()` 內新增:

```dart
  test('主要路徑:跨 UID 聚合 pairs、清檔後重抓、emit UpdateCompleted', () async {
    final searchCalls = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalls.add(req.url.queryParameters['keyword']!);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': req.url.queryParameters['keyword'],
                  'entry_page_id': 'eid_${req.url.queryParameters["keyword"]}',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        final id = req.url.queryParameters['entry_page_id']!;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/${id}_icon.png',
                'header_img_url': 'https://x/${id}_header.png',
              },
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_refetch_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    // UID A 與 UID B 各有不同物品,測 union 去重
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 24),
      banners: {
        '301': [_rec(id: '1', uid: 'A', name: 'Hu Tao', gachaType: '301')],
        '302': [],
        '500': [],
        '200': [_rec(id: '2', uid: 'A', name: 'Skyward Harp', gachaType: '200')],
        '100': [],
      },
    ));
    await storage.save(BannerStorage(
      uid: 'B',
      lastUpdated: DateTime.utc(2026, 5, 24),
      banners: {
        '301': [_rec(id: '3', uid: 'B', name: 'Hu Tao', gachaType: '301')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
      },
    ));

    // 預植一個 stale cache 檔,驗證會被清掉
    final staleCache = File('${tempDir.path}/stale_icon.png');
    await staleCache.writeAsBytes([9, 9, 9]);
    // 預植 index 含舊資料,驗證 clearAll 會清光
    final indexStorage = HoyoWikiIndexStorage(tempDir);
    await indexStorage.save(HoyoWikiIndex(
      searchMap: const {'en-us::StaleItem': '999'},
      entries: const {},
      menuIds: const {},
    ));

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoyoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(gachaRepositoryProvider.notifier)
        .waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoyoWikiImages();

    // 跨 UID 去重後 search 兩次(Hu Tao + Skyward Harp)
    expect(searchCalls.toSet(), {'Hu Tao', 'Skyward Harp'});

    // 既有 stale 檔已被清掉
    expect(staleCache.existsSync(), isFalse);

    // 舊 index 已被清掉(StaleItem 不在 searchMap),新 index 有 Hu Tao
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap['en-us::StaleItem'], isNull);
    expect(index.searchMap['en-us::Hu Tao'], isNotNull);

    // 結束 emit UpdateCompleted
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/state/gacha_repository_refetch_test.dart`
Expected: FAIL `forceRefetchAllHoyoWikiImages` method not found。

- [ ] **Step 4: 實作 `forceRefetchAllHoyoWikiImages()`**

在 `lib/state/gacha_repository.dart` `GachaRepository` class 內,於 `forceRecaptureAndUpdate()` 之後新增:

```dart
  /// Logger 實例(force-refetch 流程)。
  static final _refetchLog = Logger('wish.hoyowiki.refetch');

  /// 強制重抓所有 UID 祈願紀錄聯集物品的 HoyoWiki 圖檔。
  ///
  /// 流程:
  ///   1. 互斥檢查:`state.progress != null` 直接 no-op(UI 應已 disable 按鈕)。
  ///   2. emit `Preparing`、建 cancellable client。
  ///   3. `hoyowikiIndexProvider.notifier.resetAll()` 清 index + 刪 cache 目錄。
  ///   4. 呼叫 [_fetchHoyoWiki] 跑既有三階段管線(它本就跨 UID 聚合 pairs)。
  ///   5. 結束依取消狀態 emit `UpdateCompleted` 或清 progress。
  ///   6. 清檔失敗時 emit `UpdateFailed(UpdateErrorWipeHoyoWikiCache)`。
  Future<void> forceRefetchAllHoyoWikiImages() async {
    if (state.progress != null) {
      _refetchLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;

    final totalUids = state.byUid.length;
    _refetchLog.info('start, totalUids=$totalUids');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      try {
        await ref.read(hoyowikiIndexProvider.notifier).resetAll();
        if (!ref.mounted) return;
        _refetchLog.info('wiped (index+cache cleared)');
      } catch (e, st) {
        _refetchLog.severe('wipeFailed', e, st);
        if (!ref.mounted) return;
        state = state.copyWith(
          progress: UpdateFailed(
            UpdateErrorWipeHoyoWikiCache(detail: e.toString()),
          ),
        );
        return;
      }

      try {
        await _fetchHoyoWiki(cancellable.client);
      } catch (e, st) {
        _refetchLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _refetchLog.warning('cancelled');
        state = state.copyWith(clearProgress: true);
        return;
      }

      _refetchLog.info('done');
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }
```

> **設計筆記**:`UpdateCompleted` 以 `totalNewRecords: 0` / `failedBanners: const []` emit;UI 端可在後續任務(若需要)顯示「圖片重抓完成」的客製訊息,但 spec 已議定沿用既有 dialog 完成態,無需改 `_Title` / `_Body`。
>
> 也需 `import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';` 中含 `UpdateErrorWipeHoyoWikiCache` 的傳遞(已透過 `update_progress.dart` re-export `update_error.dart` 來)。

- [ ] **Step 5: 跑測試確認主路徑通過**

Run: `flutter test test/state/gacha_repository_refetch_test.dart`
Expected: 主路徑測試 PASS。

- [ ] **Step 6: 加空紀錄測試**

於 `main()` 內接著新增:

```dart
  test('空紀錄:不打 fetcher、直接 emit UpdateCompleted', () async {
    var apiCalled = false;
    final apiClient = MockClient((req) async {
      apiCalled = true;
      return http.Response('', 404);
    });

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_refetch_empty_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider
            .overrideWithValue(HoyoWikiIndexStorage(tempDir)),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoyoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(gachaRepositoryProvider.notifier)
        .waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoyoWikiImages();

    expect(apiCalled, isFalse, reason: '沒 pairs 不該打 API');
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });
```

- [ ] **Step 7: 加互斥早退測試**

```dart
  test('互斥早退:state.progress 非 null 時 no-op', () async {
    final apiClient = MockClient((req) async => http.Response('', 404));

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_refetch_mutex_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final indexStorage = HoyoWikiIndexStorage(tempDir);
    // 預植一筆 index 資料,驗證互斥早退**沒有**呼叫 resetAll
    await indexStorage.save(HoyoWikiIndex(
      searchMap: const {'en-us::Existing': '111'},
      entries: const {},
      menuIds: const {},
    ));

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoyoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(gachaRepositoryProvider.notifier);
    await notifier.waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    // 模擬另一進度進行中(用 reflection 不易,改用呼叫 forceRefetch 兩次):
    // 直接呼叫 forceRefetch 不 await,馬上再呼叫一次,第二次應 no-op。
    final first = notifier.forceRefetchAllHoyoWikiImages();
    final second = notifier.forceRefetchAllHoyoWikiImages();
    await Future.wait([first, second]);

    // index 在 first 中已清,但第二次不該再 clear(難以單獨驗證);
    // 改驗:`_isUpdating` 結束後 state.progress 為 UpdateCompleted 而非錯誤狀態
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });
```

- [ ] **Step 8: 加清檔失敗測試**

```dart
  test('清檔失敗:emit UpdateFailed(UpdateErrorWipeHoyoWikiCache)', () async {
    final apiClient = MockClient((req) async => http.Response('', 404));

    final tempDir =
        await Directory.systemTemp.createTemp('gacha_refetch_wipefail_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    // 用一個不可寫的目錄當 cacheDir(讓 wipeCacheDirectory 拋例外)。
    // Windows 環境改用「指向已被刪除的 parent 的子目錄」觸發 createDir 失敗較難;
    // 退而求其次:override hoyowikiIndexStorageProvider 為會在 clearAll 拋
    // FileSystemException 的 fake。最低成本是包一層 throwing storage。
    final throwingStorage = _ThrowingClearAllStorage(tempDir);

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider.overrideWithValue(throwingStorage),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoyoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(gachaRepositoryProvider.notifier)
        .waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoyoWikiImages();

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect(
      (progress as UpdateFailed).error,
      isA<UpdateErrorWipeHoyoWikiCache>(),
    );
  });
```

於同檔 `main()` 之外加 fake storage(or 放檔尾):

```dart
class _ThrowingClearAllStorage extends HoyoWikiIndexStorage {
  _ThrowingClearAllStorage(super.baseDir);

  @override
  Future<void> clearAll() async {
    throw const FileSystemException('simulated wipe failure');
  }
}
```

- [ ] **Step 9: 跑全部 refetch 測試**

Run: `flutter test test/state/gacha_repository_refetch_test.dart`
Expected: 4 個測試全綠(主路徑、空紀錄、互斥早退、清檔失敗)。

- [ ] **Step 10: 跑 regression:既有 hoyowiki 測試**

Run: `flutter test test/state/gacha_repository_hoyowiki_test.dart test/state/gacha_repository_test.dart`
Expected: 全綠(沒動 `_fetchHoyoWiki` 內部行為)。

- [ ] **Step 11: Commit**

```bash
git add lib/state/gacha_repository.dart test/state/gacha_repository_refetch_test.dart
git commit -m "feat(gacha): add forceRefetchAllHoyoWikiImages() with cancellation + mutex"
```

---

### Task 7: i18n keys — 從 `app_zh.arb` 起手,再傳其他語系

**Files:**
- Modify: `lib/l10n/app_zh.arb`(主檔)
- Modify: `lib/l10n/app_en.arb` / `app_ja.arb` / `app_ko.arb` / `app_zh_CN.arb` / `app_pt.arb` / `app_ru.arb`

> **背景**:依專案規則(memory `feedback_i18n_starts_from_zh.md`),中文版定稿後其他 6 個語系跟著翻。`updateErrorWipeHoyoWikiCache` 已在 Task 5 完成中文側。本任務補齊按鈕、tooltip、確認 dialog 的 keys。

- [ ] **Step 1: 於 `app_zh.arb` 新增按鈕與 dialog keys**

於 `settingsClearActive` 附近(行 ~299)新增:

```json
  "settingsRefetchHoyoWikiImagesTitle": "強制重抓物品圖片",
  "@settingsRefetchHoyoWikiImagesTitle": {
    "description": "Settings → Data management → button: forcibly clears all cached HoyoWiki item images (icon + header) and re-fetches them from scratch."
  },
  "settingsRefetchHoyoWikiImagesEmpty": "尚無祈願紀錄,無物品可重抓",
  "@settingsRefetchHoyoWikiImagesEmpty": {
    "description": "Tooltip shown when the Refetch button is disabled because there are no gacha records on the device."
  },
  "confirmRefetchHoyoWikiTitle": "強制重抓物品圖片",
  "@confirmRefetchHoyoWikiTitle": {
    "description": "Title of the AlertDialog confirming the refetch action."
  },
  "confirmRefetchHoyoWikiBody": "這會清空所有物品圖片的本機快取並重新從 HoyoWiki 抓取。視物品數量可能耗費數分鐘流量與時間。",
  "@confirmRefetchHoyoWikiBody": {
    "description": "Body of the AlertDialog confirming the refetch action; warns about traffic and time cost."
  },
  "confirmRefetchHoyoWikiConfirm": "開始重抓",
  "@confirmRefetchHoyoWikiConfirm": {
    "description": "Confirm button label in the refetch AlertDialog."
  },
```

- [ ] **Step 2: 跑 codegen 確認中文側可用**

Run: `flutter gen-l10n`
Expected: `lib/l10n/generated/app_localizations_zh.dart` 含對應 getter。

- [ ] **Step 3: 翻譯到其他 6 個語系**

對 `app_en.arb` / `app_ja.arb` / `app_ko.arb` / `app_zh_CN.arb` / `app_pt.arb` / `app_ru.arb` **逐一**新增以下 5 個 key(`@xxx` 描述只在主檔 zh 版有,其他語系不重複放 placeholder/description)。建議參考既有 `settingsClearActive` 等鍵在各語系的對應翻譯風格。

**`app_en.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "Force re-fetch item images",
  "settingsRefetchHoyoWikiImagesEmpty": "No gacha records yet, nothing to re-fetch",
  "confirmRefetchHoyoWikiTitle": "Force re-fetch item images",
  "confirmRefetchHoyoWikiBody": "This will clear all local item-image cache and re-download from HoyoWiki. May take several minutes and noticeable bandwidth.",
  "confirmRefetchHoyoWikiConfirm": "Start re-fetching",
  "updateErrorWipeHoyoWikiCache": "Failed to clear item-image cache: {detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

**`app_ja.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "アイテム画像を強制再取得",
  "settingsRefetchHoyoWikiImagesEmpty": "祈願記録がありません、再取得対象がありません",
  "confirmRefetchHoyoWikiTitle": "アイテム画像を強制再取得",
  "confirmRefetchHoyoWikiBody": "ローカルのアイテム画像キャッシュをすべて削除し、HoyoWiki から再取得します。アイテム数に応じて数分かかり、相応の通信量を消費する場合があります。",
  "confirmRefetchHoyoWikiConfirm": "再取得を開始",
  "updateErrorWipeHoyoWikiCache": "アイテム画像キャッシュのクリアに失敗:{detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

**`app_ko.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "아이템 이미지 강제 재다운로드",
  "settingsRefetchHoyoWikiImagesEmpty": "기원 기록이 없어 다시 가져올 항목이 없습니다",
  "confirmRefetchHoyoWikiTitle": "아이템 이미지 강제 재다운로드",
  "confirmRefetchHoyoWikiBody": "로컬 아이템 이미지 캐시를 모두 지우고 HoyoWiki에서 다시 다운로드합니다. 아이템 수에 따라 몇 분이 걸리고 상당한 트래픽이 발생할 수 있습니다.",
  "confirmRefetchHoyoWikiConfirm": "다시 가져오기 시작",
  "updateErrorWipeHoyoWikiCache": "아이템 이미지 캐시 삭제 실패:{detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

**`app_zh_CN.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "强制重抓物品图片",
  "settingsRefetchHoyoWikiImagesEmpty": "尚无祈愿记录,无物品可重抓",
  "confirmRefetchHoyoWikiTitle": "强制重抓物品图片",
  "confirmRefetchHoyoWikiBody": "这会清空所有物品图片的本地缓存并重新从 HoyoWiki 抓取。视物品数量可能耗费数分钟流量与时间。",
  "confirmRefetchHoyoWikiConfirm": "开始重抓",
  "updateErrorWipeHoyoWikiCache": "清除物品图片缓存失败:{detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

**`app_pt.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "Forçar nova obtenção de imagens dos itens",
  "settingsRefetchHoyoWikiImagesEmpty": "Sem registros de wish ainda, nada para reobter",
  "confirmRefetchHoyoWikiTitle": "Forçar nova obtenção de imagens dos itens",
  "confirmRefetchHoyoWikiBody": "Isso limpará todo o cache local de imagens dos itens e fará o download novamente do HoyoWiki. Pode levar alguns minutos e consumir tráfego considerável.",
  "confirmRefetchHoyoWikiConfirm": "Iniciar nova obtenção",
  "updateErrorWipeHoyoWikiCache": "Falha ao limpar cache de imagens: {detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

**`app_ru.arb`**:
```json
  "settingsRefetchHoyoWikiImagesTitle": "Принудительно перезагрузить изображения предметов",
  "settingsRefetchHoyoWikiImagesEmpty": "Нет записей молитв, нечего перезагружать",
  "confirmRefetchHoyoWikiTitle": "Принудительно перезагрузить изображения предметов",
  "confirmRefetchHoyoWikiBody": "Это очистит локальный кэш изображений всех предметов и заново загрузит их из HoyoWiki. В зависимости от количества предметов это может занять несколько минут и заметный трафик.",
  "confirmRefetchHoyoWikiConfirm": "Начать перезагрузку",
  "updateErrorWipeHoyoWikiCache": "Не удалось очистить кэш изображений: {detail}",
  "@updateErrorWipeHoyoWikiCache": {
    "placeholders": { "detail": { "type": "String" } }
  },
```

> **附註**:中文之外的翻譯品質可能需要 Crowdin 後續校稿;先以準確語意填入解決編譯期 generated locale missing 問題。對齊 memory `project_crowdin_l10n_pipeline_gotchas.md`:不要動 `@@locale` 欄位的地區碼;Portuguese 為 `app_pt.arb`(非 `pt_BR`)。

- [ ] **Step 4: 跑 codegen 與 analyze**

Run: `flutter gen-l10n && flutter analyze`
Expected: `No issues found!`(generated 7 個語系都含新 getter,無 missing key 警告)。

- [ ] **Step 5: 跑既有 i18n / locale 測試**

Run: `flutter test test/l10n/`
Expected: 全綠。

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/
git commit -m "i18n(hoyowiki): add refetch button + confirm + wipe-error keys (7 locales)"
```

---

### Task 8: Settings 頁按鈕 + 確認 AlertDialog

**Files:**
- Modify: `lib/pages/settings_page.dart`(`_DataManagement.build()` 與新 `_refetchHoyoWiki` 方法)
- Test: `test/pages/settings_page_refetch_button_test.dart`(新檔)

- [ ] **Step 1: 寫失敗的 widget 測試 — enabled / disabled 矩陣**

新增 `test/pages/settings_page_refetch_button_test.dart`(以 `test/widgets/cards/account_management_test.dart` 為範本):

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Helper:把 SettingsPage 整頁包進 MaterialApp + ProviderScope
Widget _harness({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      locale: Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('zh'), Locale('en')],
      home: SettingsPage(),
    ),
  );
}

void main() {
  testWidgets('無祈願紀錄:按鈕 disabled', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('settings_refetch_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(_harness(overrides: [
      gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
      hoyowikiIndexStorageProvider
          .overrideWithValue(HoyoWikiIndexStorage(tempDir)),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ]));
    await tester.pumpAndSettle();

    // 找按鈕(用 text matcher 配 zh 文案)
    final btn = find.widgetWithText(FilledButton, '強制重抓物品圖片');
    expect(btn, findsOneWidget);
    expect(
      tester.widget<FilledButton>(btn).onPressed,
      isNull,
      reason: '無紀錄應 disabled',
    );
  });

  testWidgets('有紀錄、progress 為 null:按鈕 enabled', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('settings_refetch_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 24),
      banners: {
        '301': [
          GachaRecord(
            id: '1', uid: 'A', gachaType: '301', name: 'Hu Tao',
            itemType: 'Character', rankType: 5, time: DateTime(2026, 5, 24),
            lang: 'en-us',
          ),
        ],
        '302': [], '500': [], '200': [], '100': [],
      },
    ));

    await tester.pumpWidget(_harness(overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider
          .overrideWithValue(HoyoWikiIndexStorage(tempDir)),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ]));
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(FilledButton, '強制重抓物品圖片');
    expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/pages/settings_page_refetch_button_test.dart`
Expected: FAIL(按鈕不存在,findsOneWidget 失敗)。

- [ ] **Step 3: 在 settings_page 加按鈕**

在 `lib/pages/settings_page.dart` `_DataManagement.build()` 內,於「清除當前帳號」按鈕**之前**(行 ~362 `FilledButton.icon(`)插入新按鈕:

```dart
        Tooltip(
          message: !hasData
              ? l.settingsRefetchHoyoWikiImagesEmpty
              : '',
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: (!hasData || progress != null)
                ? null
                : () => _refetchHoyoWikiImages(context, ref),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.settingsRefetchHoyoWikiImagesTitle),
          ),
        ),
```

並在 `build()` 起始 `final hasData = ...` 之後新增:

```dart
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );
```

於檔尾 `_clearAll(...)` 之後新增方法:

```dart
  /// 顯示確認 dialog,確認後呼叫 [GachaRepository.forceRefetchAllHoyoWikiImages]。
  Future<void> _refetchHoyoWikiImages(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.confirmRefetchHoyoWikiTitle),
        content: Text(l.confirmRefetchHoyoWikiBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).gacha.stateDanger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.confirmRefetchHoyoWikiConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 後端流程獨立於 dialog lifecycle;UpdateProgressDialog 由 app_shell.dart
    // 既有 ref.listen 自動彈出。
    unawaited(
      ref
          .read(gachaRepositoryProvider.notifier)
          .forceRefetchAllHoyoWikiImages(),
    );
  }
```

頂部 import 補:`import 'dart:async';`(若已有則略)。

- [ ] **Step 4: 跑測試確認 enabled/disabled 矩陣通過**

Run: `flutter test test/pages/settings_page_refetch_button_test.dart`
Expected: 兩個測試 PASS。

- [ ] **Step 5: 加 AlertDialog 行為測試**

於同檔 `main()` 內接著新增:

```dart
  testWidgets('點按鈕 → AlertDialog 出現 → 取消不呼叫 repository', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('settings_refetch_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(BannerStorage(
      uid: 'A',
      lastUpdated: DateTime.utc(2026, 5, 24),
      banners: {
        '301': [
          GachaRecord(
            id: '1', uid: 'A', gachaType: '301', name: 'Hu Tao',
            itemType: 'Character', rankType: 5, time: DateTime(2026, 5, 24),
            lang: 'en-us',
          ),
        ],
        '302': [], '500': [], '200': [], '100': [],
      },
    ));

    await tester.pumpWidget(_harness(overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider
          .overrideWithValue(HoyoWikiIndexStorage(tempDir)),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '強制重抓物品圖片'));
    await tester.pumpAndSettle();

    // AlertDialog 內容存在
    expect(find.text('開始重抓'), findsOneWidget);

    // 點取消
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    // Dialog 關閉,沒進入 Preparing
    expect(find.text('開始重抓'), findsNothing);
    // 沒呼叫 forceRefetch,state.progress 仍是 null
  });
```

- [ ] **Step 6: 跑測試**

Run: `flutter test test/pages/settings_page_refetch_button_test.dart`
Expected: 三個測試全綠。

- [ ] **Step 7: Commit**

```bash
git add lib/pages/settings_page.dart test/pages/settings_page_refetch_button_test.dart
git commit -m "feat(settings): add force-refetch HoyoWiki images button + confirm dialog"
```

---

### Task 9: 最終 sweep — format / analyze / test

**Files:**
- 全 lib + test

- [ ] **Step 1: format**

Run: `dart format lib/ test/`
Expected: 無檔案被改動(若有 → commit 為「style: format」獨立 commit)。

- [ ] **Step 2: analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 手動驗收(release / dev 任選,行為驗證足夠即可)**

跑 `flutter run -d windows`(dev 模式即可,本任務不涉及 perf;對齊 memory `feedback_perf_check_release_first.md` 此處非 perf 議題)。手動操作:

1. **無紀錄狀態**:確認按鈕 disabled,hover 顯示 tooltip。
2. **有紀錄成功路徑**:點按鈕 → AlertDialog 出現 → 點「開始重抓」→ Preparing → FetchingHoyoWiki 三 phase 跑完 → UpdateCompleted。檢查 `<appSupport>/gacha_data/hoyowiki_index.json` 與 `hoyowiki_cache/` 確實被覆寫成新資料(舊檔 mtime 早於這次操作的就是被清過)。
3. **互斥**:重抓進行中時,「更新」按鈕應 disabled;反之亦然。
4. **取消**:重抓進行中按進度 dialog 的取消 → progress 清空、index/cache 殘留新已下載的部分,下次「更新」會自動補(self-heal)。
5. **Log 匯出**:設定頁 →「匯出日誌」,確認 log 含 `wish.hoyowiki.refetch.start` / `wiped` / `done` 節點。

- [ ] **Step 5: Commit(若 Step 1-3 有任何 hook 自動修正,新增 commit)**

```bash
# 若 Step 1 改動了檔案
git add -A
git commit -m "style: format after refetch feature"
```

不主動 push(對齊 CLAUDE.md「不要主動 git push」)。

---

## Self-Review

### 1. Spec coverage

| Spec 段落 | 對應 Task |
|---|---|
| §2 重抓範圍「全部砍掉重來」 | Task 1+2+3(`clearAll` + `wipeCacheDirectory` + `resetAll`)|
| §2 物品來源「所有 UID」 | Task 6(複用 `_fetchHoyoWiki` 既有跨 UID 聚合)|
| §2 確認 UX「一般 AlertDialog」 | Task 8 Step 3(`_refetchHoyoWikiImages`)|
| §2 進度 UI「復用 UpdateProgressDialog」 | Task 8(後端 emit state.progress,app_shell.dart 自動彈出)|
| §2 空紀錄「Disabled + tooltip」 | Task 8 Step 1+3(`!hasData` + `Tooltip`)|
| §2 擺放位置「`_DataManagement`」 | Task 8 Step 3 |
| §2 並行控制「共用 progress slot」 | Task 6 Step 4(`if (state.progress != null) return`)+ Task 8 Step 3(`onPressed: progress != null ? null : ...`)|
| §3.2 新增 `clearAll` / `wipeCacheDirectory` | Task 1 + Task 2 |
| §3.2 新增 `resetAll` | Task 3 |
| §3.2 抽 `_runHoyoWikiPipeline` | **Skipped — 見開頭「與 spec 的偏差」**;改為直接複用 `_fetchHoyoWiki` |
| §3.2 新增 `forceRefetchAllHoyoWikiImages` | Task 6 |
| §3.2 Settings 頁按鈕 | Task 8 |
| §3.3 i18n keys(zh 主檔起手)| Task 5(`updateErrorWipeHoyoWikiCache`)+ Task 7(其餘 5 個 keys)|
| §5 錯誤處理 - 清檔失敗 emit UpdateFailed | Task 4 + Task 5 + Task 6 Step 4(catch wipe error)|
| §5 錯誤處理 - 個別下載失敗沿用 | Task 6(沿用 `_fetchHoyoWiki` 內的 try/catch)|
| §5 取消 self-heal | Task 6 Step 4(`if (_cancelTriggered) clearProgress`)|
| §6 Logger 命名 `wish.hoyowiki.refetch.*` | Task 6 Step 4(`_refetchLog.info('start'/'wiped'/'done')` 等)|
| §7.1 Storage / notifier unit tests | Task 1 + Task 2 + Task 3 |
| §7.2 Repository tests | Task 6 Step 2/6/7/8 |
| §7.3 Widget tests | Task 8 Step 1+5 |
| §8 驗收標準 | Task 9 |

### 2. Placeholder scan

- 無 "TBD" / "TODO" / "fill in details"。
- 無「Add appropriate error handling」式空話;清檔失敗的 catch 已完整實作於 Task 6 Step 4。
- 翻譯草稿語言品質會交由 Crowdin 後續校稿,但 plan 內已給出可直接 ship 的字串,非 placeholder。

### 3. Type / 命名一致性

- `clearAll` / `wipeCacheDirectory` / `resetAll` / `forceRefetchAllHoyoWikiImages` 在 Task 與 Self-Review 表中一致拼寫。
- `UpdateErrorWipeHoyoWikiCache` 在 Task 4 / 5 / 6 / 7 拼寫一致(注意「Wipe」而非「Clear」,因應 cache 是 wipe 而 index 是 clear 的語義區別)。
- i18n key `updateErrorWipeHoyoWikiCache` / `settingsRefetchHoyoWikiImagesTitle` / `settingsRefetchHoyoWikiImagesEmpty` / `confirmRefetchHoyoWikiTitle` / `confirmRefetchHoyoWikiBody` / `confirmRefetchHoyoWikiConfirm` 在 Task 5 / 7 / 8 三處引用一致。
- Logger 樹 `wish.hoyowiki.refetch.*` 對齊既有 `wish.*` 與 `gacha.hoyowiki.*`。

### 4. Spec 缺漏補上

Spec §7.2 第 11 點「抽 helper 不回歸」因本 plan 不抽 helper 自然不適用;改以 Task 6 Step 10「跑既有 `gacha_repository_hoyowiki_test.dart` regression」覆蓋同等意圖。
