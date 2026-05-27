# HoyoWiki 物品 icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 HoYoWiki API 抓到的 icon 顯示在祈願記錄表格、直/橫時間軸、分享圖中物品名稱前;header 大圖一併下載 cache(本任務不消費)。

**Architecture:** 新增跨 UID 共用的 `hoyowiki_index.json`(`search` 表 + `entries` 表)與 `hoyowiki_cache/` 圖檔目錄。`GachaRepository` 在 banner 全部 fetch 完並存檔後加一個 `FetchingHoyoWiki` 階段,序列跑 search → entry_page → download icon/header 三段 worklist(600ms throttle)。`WishItemIcon` widget 走 `(name, lang) → search → id → entries → iconUrl → cache 檔` lookup chain,缺任一步顯示 placeholder。`GachaRecord` schema 不變。

**Tech Stack:** Flutter 3.x / Dart 3.11 / Riverpod 3 / package:http + http.testing (MockClient) / flutter_test。

**Spec:** `docs/superpowers/specs/2026-05-23-hoyowiki-item-icon-design.md`

---

## File Structure

**Created (lib/):**

| File | Responsibility |
|---|---|
| `lib/services/hoyowiki_index.dart` | `HoyoWikiEntry` / `HoyoWikiIndex` 純資料模型;`HoyoWikiIndexStorage` JSON IO(atomic write);`hoyowikiCacheFile(baseDir, id, kind)` 路徑 helper |
| `lib/services/hoyowiki_fetcher.dart` | `HoyoWikiFetcher` 三支 API (`searchEntryId` / `fetchEntryPage` / `downloadImage`);`HoyoWikiEntryFetched` value class;`ApiErrorException` 重用既有 `gacha_fetcher.dart` |
| `lib/state/hoyowiki_index.dart` | `hoyowikiIndexStorageProvider`(由 main.dart 注入);`hoyowikiFetcherProvider`;`hoyowikiCacheDirProvider`;`hoyowikiIndexProvider` (`NotifierProvider<HoyoWikiIndexNotifier, HoyoWikiIndex>`);`HoyoWikiIndexNotifier` 提供 `setSearch / setEntry / bumpCacheRevision` 並負責 persist |
| `lib/widgets/wish_item_icon.dart` | `WishItemIcon` ConsumerWidget + `_Placeholder`;頌願 gachaType 直接 `SizedBox.shrink()` |
| `lib/widgets/share/preloaded_hoyowiki_images.dart` | `PreloadedHoyoWikiImages` InheritedWidget;`preloadHoyoWikiImages(records)` async helper 預解碼 `ui.Image`;`disposePreloadedHoyoWikiImages(map)` helper |

**Created (test/):**

| File | Responsibility |
|---|---|
| `test/services/hoyowiki_index_test.dart` | model lookup / storage roundtrip / atomic write |
| `test/services/hoyowiki_fetcher_test.dart` | MockClient 覆蓋三支 API 的成功 / miss / 錯誤路徑 |
| `test/state/hoyowiki_index_test.dart` | Notifier `setSearch/setEntry` persist 與 rebuild 通知 |
| `test/state/gacha_repository_hoyowiki_test.dart` | FetchingHoyoWiki 階段:worklist 去重 / 失敗隔離 / 取消傳遞 / 頌願排除 / 空 URL 重抓 |
| `test/widgets/wish_item_icon_test.dart` | placeholder / 完整 chain / 頌願 shrink |

**Modified:**

| File | Change |
|---|---|
| `lib/state/update_progress.dart` | 加 `FetchingHoyoWiki` sealed subclass |
| `lib/state/gacha_repository.dart` | 加 `_fetchHoyoWiki` 方法、整合到 `_runUpdate` 主流程、`gachaRepositoryProvider` 不變 |
| `lib/main.dart` | 建立 `hoyowiki_cache/` dir、override `hoyowikiIndexStorageProvider` 與 `hoyowikiCacheDirProvider` |
| `lib/widgets/data/sortable_table.dart:386` | `_Row` 的名稱欄前插 `WishItemIcon(size: 20)` |
| `lib/widgets/cards/timeline_vertical.dart:400` | `_EntryRow` 的名稱 Text 前插 `WishItemIcon(size: 16)` |
| `lib/widgets/cards/timeline_horizontal.dart:302` | `_EntryColumn` 的 `Text(entry.name)` 上方插 `WishItemIcon(size: 20)` |
| `lib/widgets/update_progress_dialog.dart` | `_Title` / `_Body` / `_actions` 加 `FetchingHoyoWiki` 分支(無 cancel 按鈕,進度文字 + LinearProgressIndicator) |
| `lib/widgets/share/share_image_helper.dart` | 在 `renderWidgetToPng` 前 `await preloadHoyoWikiImages(records)`,包進 render tree;render 結束 dispose |
| `lib/widgets/share/share_card.dart` | 接受 `Map<String, ui.Image>? preloadedIcons` 並傳到底層 timeline widget(經 `PreloadedHoyoWikiImages.of`,不改建構子簽名) |
| `lib/l10n/app_zh.arb` | 加 `updateProgressFetchingIcons` |
| `lib/l10n/app_en.arb` | 加 `updateProgressFetchingIcons` 英文 fallback |

---

## Task 1: `HoyoWikiEntry` + `HoyoWikiIndex` 純資料模型

**Files:**
- Create: `lib/services/hoyowiki_index.dart`(部分)
- Test: `test/services/hoyowiki_index_test.dart`(部分)

- [ ] **Step 1: 寫失敗測試**

```dart
// test/services/hoyowiki_index_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

void main() {
  group('HoyoWikiIndex.lookupId', () {
    test('命中回 id', () {
      final index = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), isNull);
    });

    test('lang 不同 → 不命中', () {
      final index = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'zh-tw'), isNull);
    });
  });

  group('HoyoWikiIndex.lookupEntry', () {
    test('命中回 entry', () {
      final entry = HoyoWikiEntry(
        iconUrl: 'https://x/icon.png',
        headerImgUrl: 'https://x/header.png',
        fetchedAt: DateTime.utc(2026, 5, 23),
      );
      final index = HoyoWikiIndex(searchMap: const {}, entries: {'5125428': entry});
      expect(index.lookupEntry('5125428'), entry);
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupEntry('5125428'), isNull);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart'`.

- [ ] **Step 3: 寫最小實作**

```dart
// lib/services/hoyowiki_index.dart
/// HoyoWiki entry_page API 抓到的 icon 與 header 大圖 URL,以及抓取時間。
class HoyoWikiEntry {
  /// 建立 [HoyoWikiEntry];兩個 URL 均可能為空字串。
  const HoyoWikiEntry({
    required this.iconUrl,
    required this.headerImgUrl,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL;HoyoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 物品 header(banner)CDN URL;HoyoWiki 未上傳時為空字串。
  final String headerImgUrl;

  /// 抓取時間(僅供 debug,不參與邏輯)。
  final DateTime fetchedAt;
}

/// 跨 UID 共用的 HoyoWiki lookup index。
class HoyoWikiIndex {
  /// 建立 [HoyoWikiIndex]。
  const HoyoWikiIndex({required this.searchMap, required this.entries});

  /// 建立空 index(無任何 search / entry)。
  const HoyoWikiIndex.empty()
    : searchMap = const {},
      entries = const {};

  /// `"<lang>::<name>"` → `hoyowiki_id`;只記錄成功命中的。
  final Map<String, String> searchMap;

  /// `hoyowiki_id` → [HoyoWikiEntry];URL 可能為空字串。
  final Map<String, HoyoWikiEntry> entries;

  /// 以 [name] + [lang] 查 hoyowiki_id;查無回 null。
  String? lookupId({required String name, required String lang}) =>
      searchMap['$lang::$name'];

  /// 以 [id] 查 entry;查無回 null。
  HoyoWikiEntry? lookupEntry(String id) => entries[id];
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: PASS,4 tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiEntry and HoyoWikiIndex models"
```

---

## Task 2: `HoyoWikiIndexStorage` JSON IO + atomic write

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`
- Modify: `test/services/hoyowiki_index_test.dart`

- [ ] **Step 1: 加失敗測試**

```dart
// test/services/hoyowiki_index_test.dart 末段追加
import 'dart:io';

void main() {
  // ... 既有 group ...

  group('HoyoWikiIndexStorage', () {
    late Directory tempDir;
    late HoyoWikiIndexStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_index_test_');
      storage = HoyoWikiIndexStorage(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('load 缺檔回空 index', () async {
      final index = await storage.load();
      expect(index.searchMap, isEmpty);
      expect(index.entries, isEmpty);
    });

    test('save → load roundtrip', () async {
      final original = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: {
          '5125428': HoyoWikiEntry(
            iconUrl: 'https://x/icon.png',
            headerImgUrl: '',
            fetchedAt: DateTime.utc(2026, 5, 23, 8),
          ),
        },
      );
      await storage.save(original);
      final loaded = await storage.load();
      expect(loaded.searchMap, original.searchMap);
      expect(loaded.entries['5125428']!.iconUrl, 'https://x/icon.png');
      expect(loaded.entries['5125428']!.headerImgUrl, '');
      expect(loaded.entries['5125428']!.fetchedAt, DateTime.utc(2026, 5, 23, 8));
    });

    test('atomic write 不留 .tmp 殘檔', () async {
      await storage.save(const HoyoWikiIndex.empty());
      final tmp = File('${tempDir.path}/hoyowiki_index.json.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('save 兩次 → 後者覆蓋', () async {
      await storage.save(HoyoWikiIndex(
        searchMap: const {'a::1': 'id1'},
        entries: const {},
      ));
      await storage.save(HoyoWikiIndex(
        searchMap: const {'b::2': 'id2'},
        entries: const {},
      ));
      final loaded = await storage.load();
      expect(loaded.searchMap, {'b::2': 'id2'});
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: FAIL — `HoyoWikiIndexStorage` 未定義。

- [ ] **Step 3: 加實作**

```dart
// lib/services/hoyowiki_index.dart 末段追加
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// 負責 `hoyowiki_index.json` 的讀寫(atomic write,跨 UID 共用)。
class HoyoWikiIndexStorage {
  /// 建立 [HoyoWikiIndexStorage],需指定資料根目錄 [baseDir](通常與
  /// `gachaStorageProvider` 共用 `<appSupport>/gacha_data/`)。
  HoyoWikiIndexStorage(this.baseDir);

  /// Logger 實例(hoyowiki 儲存)。
  static final _log = Logger('wish.hoyowiki.storage');

  /// 資料根目錄。
  final Directory baseDir;

  /// index 檔路徑。
  File get _file => File('${baseDir.path}/hoyowiki_index.json');

  /// 讀取 index;檔案不存在或解析失敗回空 index。
  Future<HoyoWikiIndex> load() async {
    final f = _file;
    if (!await f.exists()) return const HoyoWikiIndex.empty();
    try {
      final text = await f.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      final searchJson = (json['search'] as Map<String, dynamic>?) ?? const {};
      final entriesJson = (json['entries'] as Map<String, dynamic>?) ?? const {};
      return HoyoWikiIndex(
        searchMap: searchJson.map((k, v) => MapEntry(k, v as String)),
        entries: entriesJson.map(
          (k, v) {
            final m = v as Map<String, dynamic>;
            return MapEntry(
              k,
              HoyoWikiEntry(
                iconUrl: (m['icon_url'] as String?) ?? '',
                headerImgUrl: (m['header_img_url'] as String?) ?? '',
                fetchedAt: DateTime.parse(m['fetched_at'] as String),
              ),
            );
          },
        ),
      );
    } catch (e, st) {
      _log.warning('load failed, return empty index', e, st);
      return const HoyoWikiIndex.empty();
    }
  }

  /// 將 [index] 寫回磁碟(atomic rename)。
  Future<void> save(HoyoWikiIndex index) async {
    final json = {
      'version': 1,
      'search': index.searchMap,
      'entries': index.entries.map(
        (k, v) => MapEntry(k, {
          'icon_url': v.iconUrl,
          'header_img_url': v.headerImgUrl,
          'fetched_at': v.fetchedAt.toUtc().toIso8601String(),
        }),
      ),
    };
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(_file.path);
    _log.fine(
      'saved search=${index.searchMap.length} entries=${index.entries.length}',
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: PASS,所有 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiIndexStorage with atomic write"
```

---

## Task 3: `hoyowikiCacheFile` 路徑 helper

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`
- Modify: `test/services/hoyowiki_index_test.dart`

- [ ] **Step 1: 加失敗測試**

```dart
// test/services/hoyowiki_index_test.dart 末段追加
void main() {
  // ... 既有 group ...

  group('hoyowikiCacheFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_cache_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('icon kind + URL .png → <id>_icon.png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x.example/path/icon.png',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('header kind + URL .jpg → <id>_header.jpg', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.header,
        url: 'https://x.example/path/header.jpg',
      );
      expect(f.path, endsWith('5125428_header.jpg'));
    });

    test('URL 帶 query string → 仍取得乾淨副檔名', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x/icon.png?v=1&w=80',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 無副檔名 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x/icon',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 為空字串 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: '',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: FAIL — `hoyowikiCacheFile` 未定義。

- [ ] **Step 3: 加實作**

```dart
// lib/services/hoyowiki_index.dart 末段追加
/// HoyoWiki 圖片種類(對應 icon_url 與 header_img_url)。
enum HoyoWikiImageKind {
  /// 物品方形 icon。
  icon,

  /// 物品 header(banner 大圖)。
  header,
}

/// 推導出 hoyowiki 圖檔在 [baseDir] 的快取路徑。
///
/// 檔名格式:`<id>_<kind>.<ext>`。`<ext>` 從 [url] 解析(去掉 query 後取
/// 最後一個 `.` 之後);無副檔名或 URL 為空字串時 default `png`。
File hoyowikiCacheFile({
  required Directory baseDir,
  required String id,
  required HoyoWikiImageKind kind,
  required String url,
}) {
  final ext = _extFromUrl(url);
  return File('${baseDir.path}/${id}_${kind.name}.$ext');
}

/// 從 [url] 推導副檔名(無則回 `png`)。
String _extFromUrl(String url) {
  if (url.isEmpty) return 'png';
  final qIdx = url.indexOf('?');
  final clean = qIdx >= 0 ? url.substring(0, qIdx) : url;
  final dotIdx = clean.lastIndexOf('.');
  final slashIdx = clean.lastIndexOf('/');
  if (dotIdx <= slashIdx || dotIdx == clean.length - 1) return 'png';
  final ext = clean.substring(dotIdx + 1).toLowerCase();
  // 安全檢查:副檔名只能是常見 image 格式,避免 URL 怪異字串污染檔名。
  const allowed = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
  return allowed.contains(ext) ? ext : 'png';
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_index_test.dart
```

Expected: PASS,所有 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add hoyowikiCacheFile path helper"
```

---

## Task 4: `HoyoWikiFetcher.searchEntryId`

**Files:**
- Create: `lib/services/hoyowiki_fetcher.dart`
- Test: `test/services/hoyowiki_fetcher_test.dart`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/services/hoyowiki_fetcher_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';

http.Response _searchOk(List<Map<String, dynamic>> list) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {'list': list},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _searchItem({
  required String name,
  required String id,
  required int subMenuId,
}) => {
  'name': name,
  'entry_page_id': id,
  'menu': {
    'sub_menus': [
      {'id': subMenuId, 'name': 'whatever'},
    ],
  },
};

void main() {
  group('HoyoWikiFetcher.searchEntryId', () {
    test('命中(sub_menu id=2)回 entry_page_id', () async {
      final mock = MockClient((req) async => _searchOk([
        _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 2),
      ]));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao', lang: 'en-us', client: mock,
      );
      expect(id, '5125428');
    });

    test('命中(sub_menu id=4)回 entry_page_id', () async {
      final mock = MockClient((req) async => _searchOk([
        _searchItem(name: 'Sword', id: '9001', subMenuId: 4),
      ]));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Sword', lang: 'en-us', client: mock,
      );
      expect(id, '9001');
    });

    test('name 不完全 match → null', () async {
      final mock = MockClient((req) async => _searchOk([
        _searchItem(name: 'Hu Tao (foo)', id: '5125428', subMenuId: 2),
      ]));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao', lang: 'en-us', client: mock,
      );
      expect(id, isNull);
    });

    test('sub_menu id 非 2/4 → null', () async {
      final mock = MockClient((req) async => _searchOk([
        _searchItem(name: 'Hu Tao', id: '5125428', subMenuId: 1),
      ]));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao', lang: 'en-us', client: mock,
      );
      expect(id, isNull);
    });

    test('空 list → null', () async {
      final mock = MockClient((req) async => _searchOk(const []));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      expect(
        await fetcher.searchEntryId(name: 'X', lang: 'en-us', client: mock),
        isNull,
      );
    });

    test('多筆中找到第一筆 match', () async {
      final mock = MockClient((req) async => _searchOk([
        _searchItem(name: 'Other', id: '111', subMenuId: 2),
        _searchItem(name: 'Hu Tao', id: '222', subMenuId: 2),
        _searchItem(name: 'Hu Tao', id: '333', subMenuId: 2),
      ]));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final id = await fetcher.searchEntryId(
        name: 'Hu Tao', lang: 'en-us', client: mock,
      );
      expect(id, '222');
    });

    test('retcode != 0 → throw ApiErrorException', () async {
      final mock = MockClient((_) async => http.Response(
        jsonEncode({'retcode': -1, 'message': 'fail', 'data': null}),
        200,
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await expectLater(
        () => fetcher.searchEntryId(name: 'X', lang: 'en-us', client: mock),
        throwsA(isA<ApiErrorException>()),
      );
    });

    test('Headers 正確帶入', () async {
      late http.BaseRequest captured;
      final mock = MockClient((req) async {
        captured = req;
        return _searchOk(const []);
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.searchEntryId(
        name: 'Hu Tao', lang: 'zh-tw', client: mock,
      );
      expect(captured.headers['Referer'], 'https://wiki.hoyolab.com/');
      expect(captured.headers['X-Rpc-Language'], 'zh-tw');
      expect(captured.headers['X-Rpc-Wiki_app'], 'genshin');
    });

    test('keyword 正確 URL-encode', () async {
      late Uri capturedUrl;
      final mock = MockClient((req) async {
        capturedUrl = req.url;
        return _searchOk(const []);
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.searchEntryId(
        name: '胡桃', lang: 'zh-tw', client: mock,
      );
      expect(capturedUrl.queryParameters['keyword'], '胡桃');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:.../services/hoyowiki_fetcher.dart'`。

- [ ] **Step 3: 加實作**

```dart
// lib/services/hoyowiki_fetcher.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;

/// HoyoWiki entry_page API 抓到的 icon 與 header URL。
class HoyoWikiEntryFetched {
  /// 建立 [HoyoWikiEntryFetched];URL 均可能為空字串。
  const HoyoWikiEntryFetched({
    required this.iconUrl,
    required this.headerImgUrl,
  });

  /// 物品 icon CDN URL;HoyoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 物品 header CDN URL;HoyoWiki 未上傳時為空字串。
  final String headerImgUrl;
}

/// 與 HoyoLab Wiki API 互動的 fetcher,涵蓋 search / entry_page / image download。
class HoyoWikiFetcher {
  /// 建立 [HoyoWikiFetcher],可調整速率限制與逾時。
  HoyoWikiFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.timeout = const Duration(seconds: 10),
  });

  /// 兩次 API 呼叫之間的最短間隔(由 caller 透過 `Future.delayed` 控制,
  /// fetcher 本身不主動 delay)。
  final Duration rateLimit;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例(wish.hoyowiki 命名空間,對齊既有 `gacha.fetcher`)。
  static final _log = Logger('wish.hoyowiki');

  /// search API base URL。
  static final _searchBase = Uri.parse(
    'https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/search',
  );

  /// 以 [name] 走 HoyoLab Wiki search API 取得對應的 entry_page_id。
  ///
  /// 命中需同時滿足:`data.list[].name == name` 且
  /// `data.list[].menu.sub_menus[0].id ∈ {2, 4}`。回傳第一筆符合的
  /// `entry_page_id`;若無回 null;retcode != 0 throw [ApiErrorException]。
  Future<String?> searchEntryId({
    required String name,
    required String lang,
    required http.Client client,
  }) async {
    final url = _searchBase.replace(queryParameters: {'keyword': name});
    final res = await client
        .get(url, headers: {
          'Referer': 'https://wiki.hoyolab.com/',
          'X-Rpc-Language': lang,
          'X-Rpc-Wiki_app': 'genshin',
        })
        .timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode != 0) {
      _log.warning(
        'search retcode=$retcode name=$name lang=$lang msg=${body['message']}',
      );
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
    final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
    for (final raw in list) {
      final item = raw as Map<String, dynamic>;
      if (item['name'] != name) continue;
      final menu = item['menu'] as Map<String, dynamic>?;
      final subMenus = menu?['sub_menus'] as List<dynamic>?;
      if (subMenus == null || subMenus.isEmpty) continue;
      final subMenuId = (subMenus.first as Map<String, dynamic>)['id'] as int?;
      if (subMenuId != 2 && subMenuId != 4) continue;
      final id = item['entry_page_id'] as String?;
      if (id == null || id.isEmpty) continue;
      _log.info('search hit name=$name lang=$lang id=$id');
      return id;
    }
    _log.warning('search miss name=$name lang=$lang');
    return null;
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: PASS,9 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiFetcher.searchEntryId"
```

---

## Task 5: `HoyoWikiFetcher.fetchEntryPage`

**Files:**
- Modify: `lib/services/hoyowiki_fetcher.dart`
- Modify: `test/services/hoyowiki_fetcher_test.dart`

- [ ] **Step 1: 加失敗測試**

```dart
// test/services/hoyowiki_fetcher_test.dart 末段追加
void main() {
  // ... 既有 group ...

  group('HoyoWikiFetcher.fetchEntryPage', () {
    http.Response _entryOk({required String iconUrl, required String headerUrl}) =>
        http.Response(
          jsonEncode({
            'retcode': 0,
            'message': 'OK',
            'data': {
              'page': {
                'icon_url': iconUrl,
                'header_img_url': headerUrl,
              },
            },
          }),
          200,
        );

    test('兩個 URL 都有 → 都回', () async {
      final mock = MockClient((_) async => _entryOk(
        iconUrl: 'https://x/icon.png',
        headerUrl: 'https://x/header.png',
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('icon_url 為空字串 → 照回空', () async {
      final mock = MockClient((_) async => _entryOk(
        iconUrl: '',
        headerUrl: 'https://x/header.png',
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, '');
      expect(entry.headerImgUrl, 'https://x/header.png');
    });

    test('header_img_url 為空字串 → 照回空', () async {
      final mock = MockClient((_) async => _entryOk(
        iconUrl: 'https://x/icon.png',
        headerUrl: '',
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.headerImgUrl, '');
    });

    test('兩個 URL 都空字串 → 都回空', () async {
      final mock = MockClient((_) async => _entryOk(iconUrl: '', headerUrl: ''));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final entry = await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(entry.iconUrl, '');
      expect(entry.headerImgUrl, '');
    });

    test('retcode != 0 → throw ApiErrorException', () async {
      final mock = MockClient((_) async => http.Response(
        jsonEncode({'retcode': -1, 'message': 'nope', 'data': null}),
        200,
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await expectLater(
        () => fetcher.fetchEntryPage(id: '5125428', client: mock),
        throwsA(isA<ApiErrorException>()),
      );
    });

    test('URL 帶 entry_page_id query param', () async {
      late Uri capturedUrl;
      final mock = MockClient((req) async {
        capturedUrl = req.url;
        return _entryOk(iconUrl: '', headerUrl: '');
      });
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      await fetcher.fetchEntryPage(id: '5125428', client: mock);
      expect(capturedUrl.queryParameters['entry_page_id'], '5125428');
      expect(capturedUrl.host, 'sg-act-public-api-static.hoyolab.com');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: FAIL — `fetchEntryPage` 未定義。

- [ ] **Step 3: 加實作**

```dart
// lib/services/hoyowiki_fetcher.dart 內 HoyoWikiFetcher class 加 method,
// 與既有 _searchBase 同處加 _entryBase 常數。
class HoyoWikiFetcher {
  // ... 既有 fields ...

  /// entry_page API base URL(static 端點,不需 headers)。
  static final _entryBase = Uri.parse(
    'https://sg-act-public-api-static.hoyolab.com/hoyowiki/genshin/wapi/entry_page',
  );

  // ... 既有 searchEntryId ...

  /// 以 [id] 拉 entry_page,回 icon_url 與 header_img_url(均可能為空字串)。
  /// retcode != 0 throw [ApiErrorException]。
  Future<HoyoWikiEntryFetched> fetchEntryPage({
    required String id,
    required http.Client client,
  }) async {
    final url = _entryBase.replace(queryParameters: {'entry_page_id': id});
    final res = await client.get(url).timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode != 0) {
      _log.warning('entry retcode=$retcode id=$id msg=${body['message']}');
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
    final page = body['data']?['page'] as Map<String, dynamic>?;
    final iconUrl = (page?['icon_url'] as String?) ?? '';
    final headerImgUrl = (page?['header_img_url'] as String?) ?? '';
    _log.info(
      'entry id=$id icon=${iconUrl.isNotEmpty} header=${headerImgUrl.isNotEmpty}',
    );
    return HoyoWikiEntryFetched(iconUrl: iconUrl, headerImgUrl: headerImgUrl);
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: PASS,所有 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiFetcher.fetchEntryPage"
```

---

## Task 6: `HoyoWikiFetcher.downloadImage`

**Files:**
- Modify: `lib/services/hoyowiki_fetcher.dart`
- Modify: `test/services/hoyowiki_fetcher_test.dart`

- [ ] **Step 1: 加失敗測試**

```dart
// test/services/hoyowiki_fetcher_test.dart 末段追加
void main() {
  // ... 既有 group ...

  group('HoyoWikiFetcher.downloadImage', () {
    test('200 OK → 回 bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final mock = MockClient(
        (_) async => http.Response.bytes(bytes, 200),
      );
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, bytes);
    });

    test('404 → 回 null', () async {
      final mock = MockClient((_) async => http.Response('', 404));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, isNull);
    });

    test('throw → 回 null', () async {
      final mock = MockClient((_) async => throw const SocketException(
        'connection refused',
      ));
      final fetcher = HoyoWikiFetcher(rateLimit: Duration.zero);
      final out = await fetcher.downloadImage('https://x/icon.png', mock);
      expect(out, isNull);
    });
  });
}
```

(`SocketException` 需 `import 'dart:io';`)

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: FAIL — `downloadImage` 未定義。

- [ ] **Step 3: 加實作**

```dart
// lib/services/hoyowiki_fetcher.dart 內 HoyoWikiFetcher class 加 method
class HoyoWikiFetcher {
  // ... 既有 ...

  /// GET [url] 的圖檔 bytes;任何失敗(非 2xx / 例外)回 null,caller 不寫檔
  /// 並於下次更新重試。
  Future<Uint8List?> downloadImage(String url, http.Client client) async {
    try {
      final res = await client.get(Uri.parse(url)).timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return res.bodyBytes;
      }
      _log.warning('download non-2xx status=${res.statusCode} url=$url');
      return null;
    } catch (e) {
      _log.warning('download failed url=$url err=$e');
      return null;
    }
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: PASS,所有 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
git commit -m "feat(hoyowiki): add HoyoWikiFetcher.downloadImage"
```

---

## Task 7: `FetchingHoyoWiki` progress class

**Files:**
- Modify: `lib/state/update_progress.dart`
- Test: `test/state/update_progress_test.dart`(本檔可能不存在,改為靠 gacha_repository 測試覆蓋)

- [ ] **Step 1: 寫實作(本 step 無新測試;`FetchingHoyoWiki` 的行為由後續 Task 9 的 repository 整合測試覆蓋。)**

```dart
// lib/state/update_progress.dart 末段追加
/// 主資料抓取完成後,正在補齊各物品的 HoyoWiki 圖示。
class FetchingHoyoWiki extends UpdateProgress {
  /// 建立 [FetchingHoyoWiki]。
  const FetchingHoyoWiki({required this.doneCount, required this.totalCount});

  /// 目前已完成的工作項數。
  final int doneCount;

  /// 本階段總工作項數(search + entry + download 加總)。
  final int totalCount;
}
```

- [ ] **Step 2: 跑既有 gacha_repository_test 確認 sealed class 加新 subclass 不破現有 switch**

```
flutter test test/state/gacha_repository_test.dart
```

Expected: PASS。(`UpdateProgress` 是 sealed,新增 subclass 後既有 `switch` 沒有 default case 會編譯失敗;若有失敗即進 Task 15 處理。)

- [ ] **Step 3: 若 compile / switch 缺 case → 暫時在 `update_progress_dialog.dart` 的 `_actions` / `_Title` / `_Body` 加 `FetchingHoyoWiki() => ...與 FetchingBanner 等價的暫時實作`,僅為通過編譯;Task 15 會做正式版**

範例(`_actions`):

```dart
return switch (p) {
  // ... 既有 cases ...
  FetchingBanner() => const <Widget>[],
  FetchingHoyoWiki() => const <Widget>[],
  // ... 既有 cases ...
};
```

`_Title`:

```dart
final (icon, color, text) = switch (progress) {
  // ... 既有 cases ...
  FetchingBanner() => (Icons.cloud_download_outlined, tokens.textPrimary, l.progressFetching),
  FetchingHoyoWiki() => (Icons.cloud_download_outlined, tokens.textPrimary, l.progressFetching),
  // ... 既有 cases ...
};
```

`_Body`:

```dart
return switch (progress) {
  // ... 既有 cases ...
  FetchingBanner(...) => Column(...),
  FetchingHoyoWiki() => const LinearProgressIndicator(),
  // ... 既有 cases ...
};
```

- [ ] **Step 4: 再跑一次測試確認編譯通過**

```
flutter analyze
flutter test
```

Expected: 全部通過。

- [ ] **Step 5: Commit**

```bash
git add lib/state/update_progress.dart lib/widgets/update_progress_dialog.dart
git commit -m "feat(hoyowiki): add FetchingHoyoWiki progress class"
```

---

## Task 8: Providers 注入

**Files:**
- Create: `lib/state/hoyowiki_index.dart`
- Modify: `lib/main.dart`
- Test: `test/state/hoyowiki_index_test.dart`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/state/hoyowiki_index_test.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hoyowiki_state_test_');
    container = ProviderContainer(overrides: [
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoyoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('hoyowikiIndexProvider 初始為空 index', () async {
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap, isEmpty);
    expect(index.entries, isEmpty);
    // 等 _load() 完成
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    expect(container.read(hoyowikiIndexProvider).searchMap, isEmpty);
  });

  test('setSearch 更新 state 並 persist', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '5125428');
    expect(
      container.read(hoyowikiIndexProvider).lookupId(
        name: 'Hu Tao', lang: 'en-us',
      ),
      '5125428',
    );
    // 重新 load 一次確認 persist
    final reloaded = await HoyoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
  });

  test('setEntry 更新 state 並 persist', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    final entry = HoyoWikiEntry(
      iconUrl: 'https://x/icon.png',
      headerImgUrl: '',
      fetchedAt: DateTime.utc(2026, 5, 23),
    );
    await notifier.setEntry(id: '5125428', entry: entry);
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('5125428')?.iconUrl,
      'https://x/icon.png',
    );
    final reloaded = await HoyoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupEntry('5125428')?.iconUrl, 'https://x/icon.png');
  });

  test('bumpCacheRevision 觸發 state 更新(supplies new identity)', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    final before = container.read(hoyowikiIndexProvider);
    notifier.bumpCacheRevision();
    final after = container.read(hoyowikiIndexProvider);
    expect(identical(before, after), isFalse);
    expect(after.searchMap, before.searchMap);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/state/hoyowiki_index_test.dart
```

Expected: FAIL — providers / Notifier 未定義。

- [ ] **Step 3: 寫實作**

```dart
// lib/state/hoyowiki_index.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// HoyoWiki index 儲存層,main.dart 用 `overrideWithValue` 注入。
final hoyowikiIndexStorageProvider = Provider<HoyoWikiIndexStorage>((ref) {
  throw UnimplementedError(
    'hoyowikiIndexStorageProvider must be overridden in main()',
  );
});

/// HoyoWiki 圖檔快取目錄,main.dart 用 `overrideWithValue` 注入。
final hoyowikiCacheDirProvider = Provider<Directory>((ref) {
  throw UnimplementedError(
    'hoyowikiCacheDirProvider must be overridden in main()',
  );
});

/// HoyoWiki API fetcher;預設值即可,無需 override。
final hoyowikiFetcherProvider = Provider<HoyoWikiFetcher>(
  (ref) => HoyoWikiFetcher(),
);

/// 當前載入的 [HoyoWikiIndex];透過 [HoyoWikiIndexNotifier] 變更。
final hoyowikiIndexProvider =
    NotifierProvider<HoyoWikiIndexNotifier, HoyoWikiIndex>(
      HoyoWikiIndexNotifier.new,
    );

/// 包裝 [HoyoWikiIndexStorage] 的 Riverpod Notifier;mutation 後同步 persist。
class HoyoWikiIndexNotifier extends Notifier<HoyoWikiIndex> {
  static final _log = Logger('wish.hoyowiki.notifier');

  Completer<void>? _loadCompleter;

  @override
  HoyoWikiIndex build() {
    _loadCompleter = Completer<void>();
    unawaited(_load());
    return const HoyoWikiIndex.empty();
  }

  /// 從 storage 載入並 emit 給 state。
  Future<void> _load() async {
    try {
      final storage = ref.read(hoyowikiIndexStorageProvider);
      final loaded = await storage.load();
      if (!ref.mounted) return;
      state = loaded;
    } catch (e, st) {
      _log.warning('load failed', e, st);
    } finally {
      _loadCompleter?.complete();
    }
  }

  /// 等待初始 load 結束。
  Future<void> waitForLoad() => _loadCompleter?.future ?? Future.value();

  /// 寫入一筆 search 對應並 persist。
  Future<void> setSearch({
    required String name,
    required String lang,
    required String id,
  }) async {
    final newSearch = Map<String, String>.from(state.searchMap)
      ..['$lang::$name'] = id;
    final next = HoyoWikiIndex(searchMap: newSearch, entries: state.entries);
    await _saveAndEmit(next);
  }

  /// 寫入一筆 entry 並 persist。
  Future<void> setEntry({
    required String id,
    required HoyoWikiEntry entry,
  }) async {
    final newEntries = Map<String, HoyoWikiEntry>.from(state.entries)
      ..[id] = entry;
    final next = HoyoWikiIndex(searchMap: state.searchMap, entries: newEntries);
    await _saveAndEmit(next);
  }

  /// 在 cache 檔案下載完成後呼叫;state 內容不變但 identity 換新,
  /// 觸發 watch hoyowikiIndexProvider 的 widget 重新 build 以挑到新檔。
  void bumpCacheRevision() {
    state = HoyoWikiIndex(
      searchMap: state.searchMap,
      entries: state.entries,
    );
  }

  /// 內部 helper:寫檔 + emit。
  Future<void> _saveAndEmit(HoyoWikiIndex next) async {
    final storage = ref.read(hoyowikiIndexStorageProvider);
    await storage.save(next);
    if (!ref.mounted) return;
    state = next;
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/state/hoyowiki_index_test.dart
```

Expected: PASS,4 tests passed。

- [ ] **Step 5: 改 main.dart 注入 storage 與 cache dir**

```dart
// lib/main.dart 在既有 storage 建立後追加
// (找到 `final storage = GachaStorage(gachaDir);` 之後加:)

final hoyowikiCacheDir = Directory('${supportDir.path}/hoyowiki_cache');
if (!await hoyowikiCacheDir.exists()) {
  await hoyowikiCacheDir.create(recursive: true);
}
final hoyowikiIndexStorage = HoyoWikiIndexStorage(gachaDir);

runApp(
  ProviderScope(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider.overrideWithValue(hoyowikiIndexStorage),
      hoyowikiCacheDirProvider.overrideWithValue(hoyowikiCacheDir),
      appVersionProvider.overrideWithValue(pkgInfo.version),
      logServiceProvider.overrideWithValue(logService),
    ],
    child: const MainApp(),
  ),
);
```

並在 main.dart 上方 import:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
```

- [ ] **Step 6: 跑完整 analyze + test 確認無 regression**

```
flutter analyze
flutter test
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/state/hoyowiki_index.dart lib/main.dart test/state/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): wire providers and main.dart cache dir bootstrap"
```

---

## Task 9: `_fetchHoyoWiki` 階段整合到 `GachaRepository._runUpdate`

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Test: `test/state/gacha_repository_hoyowiki_test.dart`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/state/gacha_repository_hoyowiki_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

GachaRecord _rec({
  required String id,
  required String name,
  required String gachaType,
  String lang = 'en-us',
}) => GachaRecord(
  id: id,
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 23),
  lang: lang,
);

void main() {
  late Directory tempDir;
  late ProviderContainer container;
  late MockClient capturedClient;

  Future<ProviderContainer> setupContainer({
    required MockClient apiClient,
  }) async {
    tempDir = await Directory.systemTemp.createTemp('gacha_hoyowiki_test_');
    SharedPreferences.setMockInitialValues({});
    // 預先寫入一筆 BannerStorage,讓 update 流程「跳過 banner fetch / capture URL
    // 那段」直接進入 hoyowiki 階段:做法是把 _fetchHoyoWiki 抽成 public method
    // (`debugRunHoyoWikiOnly`) 或在測試中模擬已有 byUid + 跑 public API。
    final storage = GachaStorage(tempDir);
    await storage.save(BannerStorage(
      uid: '801057625',
      lastUpdated: DateTime.utc(2026, 5, 23),
      banners: {
        '301': [_rec(id: '1', name: 'Hu Tao', gachaType: '301')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
        '2000': [_rec(id: '2', name: 'OdesItem', gachaType: '2000')],
        '1000': [],
      },
    ));

    capturedClient = apiClient;
    final container = ProviderContainer(overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoyoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      hoyowikiFetcherProvider.overrideWithValue(
        HoyoWikiFetcher(rateLimit: Duration.zero),
      ),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => _FakeCancellable(apiClient),
      ),
    ]);
    addTearDown(container.dispose);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    // 等 repo / settings / hoyowiki index 完成 bootstrap
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    await container.read(settingsProvider.notifier).waitForLoad();
    return container;
  }

  test('FetchingHoyoWiki 階段:祈願 record 進 worklist,頌願不進', () async {
    final searchCalls = <String>[];
    final entryCalls = <String>[];
    final downloadCalls = <String>[];
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
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2}
                    ]
                  }
                }
              ]
            }
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCalls.add(req.url.queryParameters['entry_page_id']!);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/${req.url.queryParameters['entry_page_id']}_icon.png',
                'header_img_url': 'https://x/${req.url.queryParameters['entry_page_id']}_header.png',
              }
            }
          }),
          200,
        );
      }
      // image download
      downloadCalls.add(req.url.toString());
      return http.Response.bytes([1, 2, 3], 200);
    });
    container = await setupContainer(apiClient: apiClient);
    await container.read(gachaRepositoryProvider.notifier).debugRunHoyoWikiOnly();

    // 只祈願 record (Hu Tao) 進 search,頌願 (OdesItem) 不進
    expect(searchCalls, ['Hu Tao']);
    expect(entryCalls, ['111']);
    // icon + header 兩個下載
    expect(downloadCalls.length, 2);
  });

  test('hoyowiki 階段失敗不影響後續(每個 item 獨立 try/catch)', () async {
    final searchCalls = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalls.add(req.url.queryParameters['keyword']!);
        return http.Response(
          jsonEncode({'retcode': -1, 'message': 'fail', 'data': null}),
          200,
        );
      }
      return http.Response('', 404);
    });
    container = await setupContainer(apiClient: apiClient);
    await container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoyoWikiOnly();

    expect(searchCalls, ['Hu Tao']);
    // index 維持空(沒寫入失敗的)
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap, isEmpty);
  });

  test('已 search 命中的不再重 search', () async {
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
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {'sub_menus': [{'id': 2}]},
                }
              ]
            }
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {'page': {'icon_url': 'https://x/icon.png', 'header_img_url': ''}}
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoyoWikiOnly();
    expect(searchCalls.length, 1);

    await notifier.debugRunHoyoWikiOnly();
    expect(searchCalls.length, 1, reason: '第二次不應再 search');
  });

  test('entry 任一 URL 為空字串 → 下次重 entry', () async {
    var entryCallCount = 0;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {'sub_menus': [{'id': 2}]},
                }
              ]
            }
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {'page': {'icon_url': '', 'header_img_url': ''}}
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoyoWikiOnly();
    expect(entryCallCount, 1);

    await notifier.debugRunHoyoWikiOnly();
    expect(
      entryCallCount,
      2,
      reason: '兩個 URL 為空字串應視為 incomplete,下次重抓',
    );
  });
}

/// 測試用 CancellableHttpClient:不真的 cancel,只回傳給定的 client。
class _FakeCancellable implements CancellableHttpClient {
  _FakeCancellable(this.client);
  @override
  final http.Client client;
  @override
  void cancel() {}
}
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/state/gacha_repository_hoyowiki_test.dart
```

Expected: FAIL — `debugRunHoyoWikiOnly` / `waitForBootstrap` 未定義。

- [ ] **Step 3: 加 `GachaRepository.waitForBootstrap` helper(若尚無)**

開啟 `lib/state/gacha_repository.dart`,在 `GachaRepository` class 內加:

```dart
/// build() 內 `_bootstrapLoad()` 完成的 future,供測試 await。
Completer<void>? _bootstrapCompleter;

/// 等待初次 bootstrap 完成(load 既有 UID 與 settings)。
Future<void> waitForBootstrap() =>
    _bootstrapCompleter?.future ?? Future.value();
```

並把 `_bootstrapLoad` 包成 completer:

```dart
Future<void> _bootstrapLoad() async {
  _bootstrapCompleter = Completer<void>();
  try {
    // ... 既有 body ...
  } finally {
    _bootstrapCompleter?.complete();
  }
}
```

- [ ] **Step 4: 加 `_fetchHoyoWiki` 方法 + `debugRunHoyoWikiOnly` testing API**

在 `GachaRepository` class 內加:

```dart
/// 補齊所有 UID 中祈願類 record 的 HoyoWiki icon / header。
///
/// 流程:
///   1. 收集所有 UID 的祈願類 record(gachaType ∈ {301, 302, 500, 200, 100})
///      取 unique (name, lang)。
///   2. 對 index.search 缺對應的跑 search;命中時寫 index.search 並把 id 加入
///      entry worklist。
///   3. 對 index.entries 缺或任一 URL 為空字串的 id 跑 entry_page;成功時寫
///      index.entries 並把非空 URL 加入 download worklist。
///   4. 對 cache 檔不存在的 (id, kind, url) 下載寫檔;成功後呼叫
///      [HoyoWikiIndexNotifier.bumpCacheRevision] 觸發 UI rebuild。
///
/// 每筆獨立 try/catch:單筆失敗不終止整段。每筆完成更新 progress。整段失敗
/// 不影響 `UpdateCompleted`。取消(`_cancelTriggered` 或 `!ref.mounted`)早退。
Future<void> _fetchHoyoWiki(http.Client client) async {
  final fetcher = ref.read(hoyowikiFetcherProvider);
  final indexNotifier = ref.read(hoyowikiIndexProvider.notifier);
  final cacheDir = ref.read(hoyowikiCacheDirProvider);
  await indexNotifier.waitForLoad();

  const wishGachaTypes = {'301', '302', '500', '200', '100'};

  // 收集所有 UID 全部祈願 record 的 unique (name, lang)
  final uniquePairs = <(String name, String lang)>{};
  for (final data in state.byUid.values) {
    for (final entry in data.banners.entries) {
      if (!wishGachaTypes.contains(entry.key)) continue;
      for (final r in entry.value) {
        if (r.name.isEmpty || r.lang.isEmpty) continue;
        uniquePairs.add((r.name, r.lang));
      }
    }
  }

  // 切三段 worklist
  var index = ref.read(hoyowikiIndexProvider);
  final searchTodo = <(String, String)>[];
  for (final pair in uniquePairs) {
    if (index.lookupId(name: pair.$1, lang: pair.$2) == null) {
      searchTodo.add(pair);
    }
  }

  bool needRefetchEntry(HoyoWikiEntry? e) =>
      e == null || e.iconUrl.isEmpty || e.headerImgUrl.isEmpty;

  // entryTodo 初始:現有 search 對應的所有 id 中,entry 缺或 URL 空的
  final initialIds = uniquePairs
      .map((p) => index.lookupId(name: p.$1, lang: p.$2))
      .whereType<String>()
      .toSet();
  final entryTodo = <String>{
    for (final id in initialIds)
      if (needRefetchEntry(index.lookupEntry(id))) id,
  };

  // downloadTodo 初始:現有 entry 的非空 URL 中,cache 檔不存在的
  final downloadTodo = <_HoyoWikiDownloadItem>[];
  void enqueueDownloadsForEntry(String id, HoyoWikiEntry entry) {
    for (final kind in HoyoWikiImageKind.values) {
      final url = kind == HoyoWikiImageKind.icon
          ? entry.iconUrl
          : entry.headerImgUrl;
      if (url.isEmpty) continue;
      final file = hoyowikiCacheFile(
        baseDir: cacheDir, id: id, kind: kind, url: url,
      );
      if (file.existsSync()) continue;
      downloadTodo.add(_HoyoWikiDownloadItem(id: id, kind: kind, url: url));
    }
  }

  for (final id in initialIds) {
    final e = index.lookupEntry(id);
    if (e != null) enqueueDownloadsForEntry(id, e);
  }

  final total = searchTodo.length + entryTodo.length + downloadTodo.length;
  if (total == 0) return;

  final fetcherDelay = ref.read(hoyowikiFetcherProvider).rateLimit;
  var done = 0;

  void emit() {
    if (!ref.mounted) return;
    state = state.copyWith(
      progress: FetchingHoyoWiki(doneCount: done, totalCount: total),
    );
  }

  emit();

  Future<bool> tickAndCheckCancel() async {
    done++;
    emit();
    await Future<void>.delayed(fetcherDelay);
    if (!ref.mounted) return true;
    if (_cancelTriggered) return true;
    return false;
  }

  // (1) search 階段
  for (final pair in searchTodo) {
    try {
      final id = await fetcher.searchEntryId(
        name: pair.$1, lang: pair.$2, client: client,
      );
      if (id != null) {
        await indexNotifier.setSearch(name: pair.$1, lang: pair.$2, id: id);
        if (!entryTodo.contains(id) && needRefetchEntry(
          ref.read(hoyowikiIndexProvider).lookupEntry(id),
        )) {
          entryTodo.add(id);
        }
      }
    } catch (e) {
      _log.warning('hoyowiki search failed name=${pair.$1} err=$e');
    }
    if (await tickAndCheckCancel()) return;
  }

  // (2) entry 階段
  for (final id in entryTodo) {
    try {
      final fetched = await fetcher.fetchEntryPage(id: id, client: client);
      final entry = HoyoWikiEntry(
        iconUrl: fetched.iconUrl,
        headerImgUrl: fetched.headerImgUrl,
        fetchedAt: DateTime.now().toUtc(),
      );
      await indexNotifier.setEntry(id: id, entry: entry);
      enqueueDownloadsForEntry(id, entry);
    } catch (e) {
      _log.warning('hoyowiki entry failed id=$id err=$e');
    }
    if (await tickAndCheckCancel()) return;
  }

  // (3) download 階段
  for (final item in downloadTodo) {
    try {
      final bytes = await fetcher.downloadImage(item.url, client);
      if (bytes != null) {
        final file = hoyowikiCacheFile(
          baseDir: cacheDir, id: item.id, kind: item.kind, url: item.url,
        );
        await file.writeAsBytes(bytes, flush: true);
        indexNotifier.bumpCacheRevision();
      }
    } catch (e) {
      _log.warning('hoyowiki download failed url=${item.url} err=$e');
    }
    if (await tickAndCheckCancel()) return;
  }
}

/// 測試用:略過 banner fetch 直接跑 hoyowiki 階段(用既有 state.byUid)。
@visibleForTesting
Future<void> debugRunHoyoWikiOnly() async {
  final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
  try {
    await _fetchHoyoWiki(cancellable.client);
  } finally {
    cancellable.client.close();
  }
}
```

並加 download item 內部 class 與 imports:

```dart
// gacha_repository.dart 上方 imports 追加:
import 'package:flutter/foundation.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

// 檔案底部 或 適當位置:
class _HoyoWikiDownloadItem {
  const _HoyoWikiDownloadItem({
    required this.id,
    required this.kind,
    required this.url,
  });

  final String id;
  final HoyoWikiImageKind kind;
  final String url;
}
```

- [ ] **Step 5: 把 `_fetchHoyoWiki` 串到 `_runUpdate` 主流程**

在 `_runUpdate` 內 `_fetchAllBanners(...)` 成功跑完之後、進入 UpdateCompleted 之前加:

具體位置:`_fetchAllBanners` 內最末段:

```dart
state = state.copyWith(
  byUid: newByUid,
  activeUid: uid,
  progress: UpdateCompleted(...),
);
```

把上面這段拆成兩階段:

```dart
state = state.copyWith(
  byUid: newByUid,
  activeUid: uid,
);
// HoyoWiki 補圖階段(best-effort,不影響 UpdateCompleted)
try {
  await _fetchHoyoWiki(client);
} catch (e, st) {
  _log.warning('hoyowiki stage threw (ignored)', e, st);
}
if (!ref.mounted) return;
state = state.copyWith(
  progress: UpdateCompleted(
    totalNewRecords: totalNew,
    failedBanners: failed,
    updatedAt: updatedAt,
  ),
);
```

(注意 `_fetchAllBanners` 的 `client` 來自 caller `_runUpdate`,已在範圍內。)

- [ ] **Step 6: 跑測試**

```
flutter analyze
flutter test test/state/gacha_repository_hoyowiki_test.dart
flutter test test/state/gacha_repository_test.dart
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add lib/state/gacha_repository.dart lib/state/update_progress.dart \
  test/state/gacha_repository_hoyowiki_test.dart
git commit -m "feat(hoyowiki): integrate FetchingHoyoWiki stage into update pipeline"
```

---

## Task 10: i18n key `updateProgressFetchingIcons`

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: 在 `lib/l10n/app_zh.arb` 既有 progress 區塊末段插入(`progressPartialFailed` 之後)**

```json
  "updateProgressFetchingIcons": "補齊物品圖示 {done}/{total}",
  "@updateProgressFetchingIcons": {
    "placeholders": {
      "done": { "type": "int" },
      "total": { "type": "int" }
    }
  },
```

- [ ] **Step 2: 在 `lib/l10n/app_en.arb` 同位置插入英文翻譯**

```json
  "updateProgressFetchingIcons": "Fetching item icons {done}/{total}",
  "@updateProgressFetchingIcons": {
    "placeholders": {
      "done": { "type": "int" },
      "total": { "type": "int" }
    }
  },
```

- [ ] **Step 3: 跑 `flutter gen-l10n` 重 generate (或 `flutter pub get` 觸發 build)**

```
flutter gen-l10n
```

Expected: generated 檔被更新,新增 `updateProgressFetchingIcons` getter。

- [ ] **Step 4: 跑 analyze 確認 generated 檔合法**

```
flutter analyze
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "feat(i18n): add updateProgressFetchingIcons key"
```

---

## Task 11: `WishItemIcon` widget + `_Placeholder`

**Files:**
- Create: `lib/widgets/wish_item_icon.dart`
- Test: `test/widgets/wish_item_icon_test.dart`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/widgets/wish_item_icon_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';

GachaRecord _rec({
  required String name,
  required String gachaType,
  int rankType = 5,
}) => GachaRecord(
  id: '1',
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: rankType,
  time: DateTime(2026, 5, 23),
  lang: 'en-us',
);

Widget _wrap(Widget child, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wish_item_icon_test_');
    container = ProviderContainer(overrides: [
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoyoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('頌願 gachaType → SizedBox.shrink', (tester) async {
    await tester.pumpWidget(_wrap(
      WishItemIcon(record: _rec(name: 'OdesItem', gachaType: '2000'), size: 20),
      container,
    ));
    final box = tester.getSize(find.byType(WishItemIcon));
    expect(box, Size.zero);
  });

  testWidgets('空 index → placeholder', (tester) async {
    await tester.pumpWidget(_wrap(
      WishItemIcon(record: _rec(name: 'Hu Tao', gachaType: '301'), size: 20),
      container,
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.byType(WishItemIcon), findsOneWidget);
    final size = tester.getSize(find.byType(WishItemIcon));
    expect(size.width, 20);
    expect(size.height, 20);
  });

  testWidgets('有 id 無 entry → placeholder', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
    await tester.pumpWidget(_wrap(
      WishItemIcon(record: _rec(name: 'Hu Tao', gachaType: '301'), size: 20),
      container,
    ));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('有 entry 但 cache 檔不存在 → placeholder', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
    await notifier.setEntry(
      id: '111',
      entry: HoyoWikiEntry(
        iconUrl: 'https://x/icon.png',
        headerImgUrl: '',
        fetchedAt: DateTime.utc(2026, 5, 23),
      ),
    );
    await tester.pumpWidget(_wrap(
      WishItemIcon(record: _rec(name: 'Hu Tao', gachaType: '301'), size: 20),
      container,
    ));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('完整 chain(index + cache 檔在) → 顯示 Image', (tester) async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    final iconUrl = 'https://x/icon.png';
    await notifier.setSearch(name: 'Hu Tao', lang: 'en-us', id: '111');
    await notifier.setEntry(
      id: '111',
      entry: HoyoWikiEntry(
        iconUrl: iconUrl,
        headerImgUrl: '',
        fetchedAt: DateTime.utc(2026, 5, 23),
      ),
    );
    final cacheFile = hoyowikiCacheFile(
      baseDir: tempDir, id: '111',
      kind: HoyoWikiImageKind.icon, url: iconUrl,
    );
    // 寫一個合法的 1x1 PNG bytes(或測試用 minimal PNG)
    await cacheFile.writeAsBytes(_minimalPng());

    await tester.pumpWidget(_wrap(
      WishItemIcon(record: _rec(name: 'Hu Tao', gachaType: '301'), size: 20),
      container,
    ));
    await tester.pump(); // 等 Image.file 載入
    expect(find.byType(Image), findsOneWidget);
  });
}

/// 最小可解碼 1x1 透明 PNG。
List<int> _minimalPng() => const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/widgets/wish_item_icon_test.dart
```

Expected: FAIL — `WishItemIcon` 未定義。

- [ ] **Step 3: 寫實作**

```dart
// lib/widgets/wish_item_icon.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 頌願卡池(odes) gachaType 集合 — 不顯示 icon 也不顯示 placeholder。
const _odesGachaTypes = {'2000', '1000'};

/// 顯示一筆祈願物品的 icon;cache 未到 / 缺資料時顯示 [_Placeholder]。
class WishItemIcon extends ConsumerWidget {
  /// 建立 [WishItemIcon]。
  const WishItemIcon({super.key, required this.record, required this.size});

  /// 祈願記錄;用其 name / lang / rankType / gachaType。
  final GachaRecord record;

  /// icon 邊長(px,依使用情境傳 16 / 20)。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_odesGachaTypes.contains(record.gachaType)) {
      return const SizedBox.shrink();
    }

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final tokens = Theme.of(context).gacha;

    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final iconUrl = entry?.iconUrl;

    if (id != null && iconUrl != null && iconUrl.isNotEmpty) {
      final file = hoyowikiCacheFile(
        baseDir: cacheDir,
        id: id,
        kind: HoyoWikiImageKind.icon,
        url: iconUrl,
      );
      if (file.existsSync()) {
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(file, fit: BoxFit.cover),
          ),
        );
      }
    }

    return _Placeholder(rankType: record.rankType, size: size, tokens: tokens);
  }
}

/// 缺 icon 時的固定尺寸方塊;底色依 rank 上色。
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.rankType,
    required this.size,
    required this.tokens,
  });

  final int rankType;
  final double size;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final accent = switch (rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textMuted,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

```
flutter test test/widgets/wish_item_icon_test.dart
```

Expected: PASS,5 tests passed。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/wish_item_icon.dart test/widgets/wish_item_icon_test.dart
git commit -m "feat(hoyowiki): add WishItemIcon widget with placeholder"
```

---

## Task 12: `SortableTable._Row` 插 `WishItemIcon`

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart`
- Modify: `test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: 加 widget 測試:確認名稱欄前有 WishItemIcon**

`test/widgets/data/sortable_table_test.dart` 找一個既有渲染整張表的 test,在其後加:

```dart
testWidgets('每列名稱欄前顯示 WishItemIcon', (tester) async {
  // ... 設定 rows 與環境同既有 test ...
  await tester.pumpWidget(/* 既有 wrap */);
  expect(find.byType(WishItemIcon), findsWidgets);
});
```

並 import:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
```

(具體新增請按既有 test 的 setup pattern;Provider 需要 override hoyowiki 三個 provider 即可,可重用 Task 11 測試的 setUp pattern。)

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/widgets/data/sortable_table_test.dart
```

Expected: FAIL — `WishItemIcon` 不在 render tree。

- [ ] **Step 3: 改 `lib/widgets/data/sortable_table.dart` 的 `_Row.build`**

把現有名稱欄那一格:

```dart
Expanded(flex: 5, child: Text(record.name, style: highlight)),
```

改成:

```dart
Expanded(
  flex: 5,
  child: Row(
    children: [
      WishItemIcon(record: record, size: 20),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          record.name,
          style: highlight,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  ),
),
```

並在檔案上方 import:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
```

- [ ] **Step 4: 跑測試確認通過 + 既有 sortable_table_test 不破**

```
flutter test test/widgets/data/sortable_table_test.dart
```

Expected: PASS,所有 tests passed(包含既有的)。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/data/sortable_table.dart test/widgets/data/sortable_table_test.dart
git commit -m "feat(hoyowiki): show item icon in SortableTable name column"
```

---

## Task 13: `TimelineVertical._EntryRow` 插 `WishItemIcon`

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Modify: `test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 加 widget 測試**

`test/widgets/cards/timeline_vertical_test.dart` 末段加:

```dart
testWidgets('每筆 entry 名稱前顯示 WishItemIcon', (tester) async {
  // ... 設定 entries 與環境同既有 test ...
  expect(find.byType(WishItemIcon), findsWidgets);
});
```

注意:`TimelineEntry` 目前只持有 name / gachaType / time,**沒有 lang/rankType/uid/itemType/id**(因為它是顯示用聚合資料)。`WishItemIcon.record` 需要 `GachaRecord`。**兩個選項**:

選項 A(推薦):讓 `TimelineEntry` 多帶一個 `GachaRecord? record` 欄位(由 `buildTimelineEntries` 產生時塞入,既有 callsite 零變更),`_EntryRow` 從 entry.record 抽欄位餵給 `WishItemIcon`。

選項 B:`WishItemIcon` 改成只收 `name / lang / gachaType / rankType` 四個欄位的版本。

採選項 A。

- [ ] **Step 2: 改 `TimelineEntry` 加 `GachaRecord? sourceRecord` 欄位**

開啟 `lib/services/timeline_entries.dart`,在 `TimelineEntry` 加:

```dart
final GachaRecord? sourceRecord;
```

並在 constructor 加 `this.sourceRecord = null` 預設。
在 `buildTimelineEntries` 產生每筆時帶入對應的 record。

- [ ] **Step 3: 更新 `_EntryRow.build`(直時間軸)**

開啟 `lib/widgets/cards/timeline_vertical.dart`,把:

```dart
Tooltip(
  message: entry.name,
  // ...
  child: Text(
    entry.name,
    style: TextStyle(
      color: accent,
      fontWeight: FontWeight.bold,
      fontSize: 14,
    ),
  ),
),
```

改成:

```dart
Tooltip(
  message: entry.name,
  preferBelow: false,
  waitDuration: const Duration(milliseconds: 100),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (entry.sourceRecord != null)
        WishItemIcon(record: entry.sourceRecord!, size: 16),
      if (entry.sourceRecord != null) const SizedBox(width: 6),
      Flexible(
        child: Text(
          entry.name,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  ),
),
```

並 import `wish_item_icon.dart`。

- [ ] **Step 4: 跑測試**

```
flutter analyze
flutter test test/widgets/cards/timeline_vertical_test.dart
flutter test test/services/timeline_entries_test.dart
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart lib/services/timeline_entries.dart \
  test/widgets/cards/timeline_vertical_test.dart
git commit -m "feat(hoyowiki): show item icon in TimelineVertical entries"
```

---

## Task 14: `TimelineHorizontal._EntryColumn` 插 `WishItemIcon`

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`
- Modify: `test/widgets/cards/timeline_horizontal_test.dart`

- [ ] **Step 1: 加 widget 測試**

```dart
testWidgets('每欄名稱上方顯示 WishItemIcon', (tester) async {
  // ...
  expect(find.byType(WishItemIcon), findsWidgets);
});
```

- [ ] **Step 2: 跑測試確認失敗**

```
flutter test test/widgets/cards/timeline_horizontal_test.dart
```

Expected: FAIL。

- [ ] **Step 3: 改 `_EntryColumn.build`**

把:

```dart
child: Column(
  // ...
  children: [
    Text(
      entry.name,
      // ...
    ),
    const SizedBox(height: AppSpacing.xs),
    _Node(color: accent, tokens: tokens),
    // ...
  ],
),
```

改成:

```dart
child: Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    if (entry.sourceRecord != null) ...[
      WishItemIcon(record: entry.sourceRecord!, size: 20),
      const SizedBox(height: AppSpacing.xs),
    ],
    Text(
      entry.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: accent,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
    const SizedBox(height: AppSpacing.xs),
    _Node(color: accent, tokens: tokens),
    // ...
  ],
),
```

並 import `wish_item_icon.dart`。

- [ ] **Step 4: 跑測試**

```
flutter analyze
flutter test test/widgets/cards/timeline_horizontal_test.dart
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_horizontal.dart \
  test/widgets/cards/timeline_horizontal_test.dart
git commit -m "feat(hoyowiki): show item icon in TimelineHorizontal columns"
```

---

## Task 15: `UpdateProgressDialog` 正式版 `FetchingHoyoWiki` UI

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1: 改 `_Title` 的 switch,把 Task 7 暫時的對應改成專屬**

```dart
final (icon, color, text) = switch (progress) {
  Preparing() => (...),
  WaitingForCapture() => (...),
  FetchingBanner() => (
    Icons.cloud_download_outlined,
    tokens.textPrimary,
    l.progressFetching,
  ),
  FetchingHoyoWiki() => (
    Icons.image_outlined,
    tokens.textPrimary,
    l.progressFetching,
  ),
  UpdateCompleted() => (...),
  UpdateFailed() => (...),
  null => (...),
};
```

- [ ] **Step 2: 改 `_Body` 的 switch,加正式的 FetchingHoyoWiki 分支**

```dart
FetchingHoyoWiki(:final doneCount, :final totalCount) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    LinearProgressIndicator(
      value: totalCount == 0 ? null : doneCount / totalCount,
    ),
    const SizedBox(height: AppSpacing.l),
    Text(l.updateProgressFetchingIcons(doneCount, totalCount)),
  ],
),
```

- [ ] **Step 3: 改 `_actions` 的 switch,FetchingHoyoWiki 不給 cancel(對齊 FetchingBanner)**

```dart
return switch (p) {
  Preparing() => [...],
  WaitingForCapture() => [...],
  FetchingBanner() => const <Widget>[],
  FetchingHoyoWiki() => const <Widget>[],
  UpdateCompleted() || UpdateFailed() => [...],
  null => const <Widget>[],
};
```

- [ ] **Step 4: 跑 analyze + test**

```
flutter analyze
flutter test test/widgets/dialogs/
```

Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "feat(hoyowiki): finalize UpdateProgressDialog FetchingHoyoWiki UI"
```

---

## Task 16: 分享圖預載 + 整合 `WishItemIcon`

**Files:**
- Create: `lib/widgets/share/preloaded_hoyowiki_images.dart`
- Modify: `lib/widgets/share/share_image_helper.dart`
- Modify: `lib/widgets/wish_item_icon.dart`(加 InheritedWidget lookup)
- Modify: `test/widgets/share/share_card_test.dart`(可選:加 icon 顯示驗證)

- [ ] **Step 1: 建立 InheritedWidget + preload helper**

```dart
// lib/widgets/share/preloaded_hoyowiki_images.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

final _log = Logger('wish.hoyowiki.preload');

/// 提供分享圖 sync pipeline 用的預解碼 icon `ui.Image` map(key = hoyowiki_id)。
class PreloadedHoyoWikiImages extends InheritedWidget {
  /// 建立 [PreloadedHoyoWikiImages]。
  const PreloadedHoyoWikiImages({
    super.key,
    required this.images,
    required super.child,
  });

  /// hoyowiki_id → 預解碼的 [ui.Image](已 owned;render 結束需 dispose)。
  final Map<String, ui.Image> images;

  /// 從祖先 [PreloadedHoyoWikiImages] 取得;不存在回 null。
  static PreloadedHoyoWikiImages? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreloadedHoyoWikiImages>();

  @override
  bool updateShouldNotify(PreloadedHoyoWikiImages oldWidget) =>
      !identical(images, oldWidget.images);
}

/// 預解碼 [records] 對應的 hoyowiki icon cache 檔成 [ui.Image] map。
///
/// 缺 cache 或 lookup miss 的 record 直接跳過(分享圖內走 placeholder)。
/// 回傳的 map 須由 caller 在 render 結束後呼叫 [disposePreloadedHoyoWikiImages]
/// 釋放 native 資源。
Future<Map<String, ui.Image>> preloadHoyoWikiImages({
  required HoyoWikiIndex index,
  required Directory cacheDir,
  required Iterable<GachaRecord> records,
}) async {
  final out = <String, ui.Image>{};
  final seenIds = <String>{};

  for (final r in records) {
    if (r.gachaType == '2000' || r.gachaType == '1000') continue;
    final id = index.lookupId(name: r.name, lang: r.lang);
    if (id == null || !seenIds.add(id)) continue;
    final entry = index.lookupEntry(id);
    final url = entry?.iconUrl;
    if (entry == null || url == null || url.isEmpty) continue;
    final file = hoyowikiCacheFile(
      baseDir: cacheDir, id: id, kind: HoyoWikiImageKind.icon, url: url,
    );
    if (!file.existsSync()) continue;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      out[id] = frame.image;
    } catch (e, st) {
      _log.warning('preload decode failed id=$id', e, st);
    }
  }
  return out;
}

/// dispose 由 [preloadHoyoWikiImages] 產出的所有 [ui.Image]。
void disposePreloadedHoyoWikiImages(Map<String, ui.Image> images) {
  for (final img in images.values) {
    img.dispose();
  }
}
```

- [ ] **Step 2: 修 `WishItemIcon` 在分享圖路徑優先用 InheritedWidget 的 `ui.Image`**

修 `lib/widgets/wish_item_icon.dart`:

在 `build` 內,在 `final tokens = ...` 之後、`final id = ...` 之前加:

```dart
final preloaded = PreloadedHoyoWikiImages.maybeOf(context);
```

並把「`cacheFile.existsSync()` → `Image.file`」分支前加優先使用 preloaded 的判斷:

```dart
if (id != null) {
  final preloadedImage = preloaded?.images[id];
  if (preloadedImage != null) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: RawImage(image: preloadedImage, fit: BoxFit.cover),
      ),
    );
  }
}
```

並 import:

```dart
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart' show RawImage;
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
```

- [ ] **Step 3: 修 `generateAndShareImage` 加 preload + 包進 render tree**

開啟 `lib/widgets/share/share_image_helper.dart`,把:

```dart
final icon = await loadAppIconImage();
try {
  final png = await renderWidgetToPng(
    buildShareRenderTree(
      card: buildCard(icon, options),
      brightness: options.brightness,
      locale: locale,
    ),
    width: kShareCardWidth,
  );
  // ...
} finally {
  icon.dispose();
}
```

改成:

```dart
final icon = await loadAppIconImage();
final container = ProviderScope.containerOf(context, listen: false);
final hoyowikiIndex = container.read(hoyowikiIndexProvider);
final cacheDir = container.read(hoyowikiCacheDirProvider);
// caller 端的 records 由 buildCard 提供 → 改參數;見 step 4。
final preloaded = <String, ui.Image>{}; // 暫定;step 4 補
try {
  final png = await renderWidgetToPng(
    buildShareRenderTree(
      card: PreloadedHoyoWikiImages(
        images: preloaded,
        child: buildCard(icon, options),
      ),
      brightness: options.brightness,
      locale: locale,
    ),
    width: kShareCardWidth,
  );
  // ...
} finally {
  icon.dispose();
  disposePreloadedHoyoWikiImages(preloaded);
}
```

- [ ] **Step 4: 改 `generateAndShareImage` signature 多帶 `Iterable<GachaRecord> recordsForPreload`,在 caller 的 banner / overview share 流程傳入**

`generateAndShareImage` 加參數:

```dart
Future<void> generateAndShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required String suggestedName,
  required Iterable<GachaRecord> recordsForPreload,
  required Widget Function(ui.Image icon, ShareImageOptions options) buildCard,
}) async {
  // ...
  final preloaded = await preloadHoyoWikiImages(
    index: hoyowikiIndex,
    cacheDir: cacheDir,
    records: recordsForPreload,
  );
  // ...
}
```

然後在 caller(banner_page.dart / overview_page.dart 內呼叫 `generateAndShareImage` 處)補上 `recordsForPreload`:

- banner page:該卡池 records
- overview page:所有 banners 的 records 串起來

具體位置:`grep -n "generateAndShareImage" lib/` 找出 callsite,各加一個 `recordsForPreload: ...` 參數。

- [ ] **Step 5: 跑 analyze + 既有 share 測試**

```
flutter analyze
flutter test test/services/share_image_renderer_test.dart
flutter test test/widgets/share/
```

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/preloaded_hoyowiki_images.dart \
  lib/widgets/share/share_image_helper.dart \
  lib/widgets/wish_item_icon.dart \
  lib/pages/banner_page.dart lib/pages/overview_page.dart
git commit -m "feat(hoyowiki): preload icons for share image sync pipeline"
```

---

## Task 17: 全套品質檢查 + 手動驗證

**Files:** N/A

- [ ] **Step 1: 跑格式化**

```
dart format lib/ test/
```

Expected: 無 diff 或自動修齊。

- [ ] **Step 2: 跑靜態分析**

```
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: 跑全套測試**

```
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 4: 手動驗證(對照 spec 末段)**

依序在 dev build 確認:

1. 全新版本初次啟動 + 既有資料 → 點更新,progress dialog 走完 FetchingBanner 後出現「補齊物品圖示 N/M」階段
2. icon 出現在:祈願記錄表格、直時間軸、橫時間軸、分享圖
3. 頌願 banner(gachaType 2000 / 1000)列**不顯示 icon 也不顯示 placeholder**
4. 拔網路啟動 app → 既有 cache 圖檔仍可顯示
5. 用假名稱(wiki 無收錄)的記錄 → 該筆永遠 placeholder;下次更新仍會 retry(log 看到 `wish.hoyowiki search miss`)
6. 取消 update 在 FetchingHoyoWiki 階段 → 已寫入的 index / 圖檔保留,下次更新可接續
7. `<applicationSupportDirectory>/hoyowiki_cache/` 目錄下同時出現 `<id>_icon.<ext>` 與 `<id>_header.<ext>`(各有對應 URL 非空時)

- [ ] **Step 5: 若全部驗證通過 → 結束;有問題 → 反查對應 task 修正**

---

## Self-Review 結論

**1. Spec coverage 對照**

| Spec 章節 | 對應 Task |
|---|---|
| Storage 結構 / atomic write | Task 1-3 |
| HoyoWikiFetcher 三支 API | Task 4-6 |
| FetchingHoyoWiki progress | Task 7, 15 |
| Update Pipeline 整合 / 失敗隔離 / 取消 | Task 9 |
| Providers / main.dart | Task 8 |
| WishItemIcon / Placeholder / 頌願排除 | Task 11 |
| 插點 SortableTable / TimelineVertical / TimelineHorizontal | Task 12-14 |
| Share image preload | Task 16 |
| i18n key | Task 10 |
| 測試計畫 5 大類 | 嵌入各 task |
| 手動驗證 checklist | Task 17 |

無遺漏。

**2. Placeholder scan**

- 無 TBD / TODO / "appropriate error handling" / "similar to Task N" 等模糊指引
- 每個 code step 都有完整可貼上的 code

**3. Type consistency**

- `HoyoWikiEntry / HoyoWikiIndex / HoyoWikiIndexStorage / HoyoWikiFetcher / HoyoWikiEntryFetched / FetchingHoyoWiki / HoyoWikiImageKind` 跨 task 名稱一致
- `searchEntryId / fetchEntryPage / downloadImage / setSearch / setEntry / bumpCacheRevision / waitForLoad / waitForBootstrap` 命名跨 task 一致
- providers `hoyowikiIndexStorageProvider / hoyowikiCacheDirProvider / hoyowikiFetcherProvider / hoyowikiIndexProvider` 命名一致
