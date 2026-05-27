# HoYoWiki Entry desc + tags 與外連按鈕 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 擴充 entry_page 抓取 `desc` 與 `filter_values` 攤平的 tags、per-lang 存儲；dialog 物品名稱下方顯示 desc + tags；actions 區新增「前往 HoYoWiki」外連按鈕。

**Architecture:** 新增 `HoYoWikiPageData { gallery, desc, tags }` 作為 per-lang 容器；`HoYoWikiEntry.galleryByLang` → `pageByLang`；storage schema bump 到 v3，v1/v2 載入時 `page_by_lang` reset 為空（圖檔 cache 保留，下次 update 重抓 entry_page API 自動補齊）；dialog title 區重構為 `Row(icon, Column(name, desc?, tags?))`，desc 用 `flutter_html` 渲染，tags 用 Material `Chip` + `Wrap`；actions 區新增 `TextButton.icon` 外連按鈕，連 `https://wiki.hoyolab.com/pc/genshin/entry/<id>`，共用 `openExternalUrl` helper。

**Tech Stack:** Flutter, Riverpod, `flutter_html` (已引入), `url_launcher` (透過 `openExternalUrl` helper @ `lib/widgets/app_link.dart`), `meta` (內建 `@visibleForTesting`)。

**Spec:** `docs/superpowers/specs/2026-05-26-hoyowiki-entry-desc-tags-design.md`

---

## File Structure

**Modified production files:**
- `lib/services/hoyowiki_index.dart` — 新增 `HoYoWikiPageData`；`HoYoWikiEntry.galleryByLang` 改為 `pageByLang`；storage v3 schema + v1/v2 → v3 載入規則
- `lib/services/hoyowiki_fetcher.dart` — 新增 `_parseTags` 私有 static + `@visibleForTesting` hook；`HoYoWikiEntryFetched.gallery` 改為 `page`；`fetchEntryPage` 解析 desc + tags 包成 `HoYoWikiPageData`
- `lib/state/hoyowiki_index.dart` — `mergeEntry` 簽名改用 `HoYoWikiEntryFetched.page`，merge 寫入 `pageByLang`
- `lib/state/gacha_repository.dart` — `needRefetchEntry` 改為 `pageByLang.containsKey`；`enqueueDownloadsForEntry` 走 `pageByLang.values` 跳過 `gallery == null`
- `lib/widgets/dialogs/gacha_item_detail_dialog.dart` — 取資料鏈從 `galleryByLang[lang]` 改為 `pageByLang[lang]?.gallery`；title 區重構為 `Row(icon, Column(name, desc, tags))`；actions 加「前往 HoYoWiki」按鈕
- `lib/l10n/app_zh.arb` — 新增 `actionViewOnHoYoWiki` key
- `lib/l10n/app_{en,es,fr,ja,pt_BR,th,vi,zh_Hans}.arb` — 新增翻譯（其他空殼不碰）

**Modified test files:**
- `test/services/hoyowiki_fetcher_test.dart` — `_parseTags` 案例 + `fetchEntryPage` 解 desc/tags 案例 + 既有 case 改用 `HoYoWikiEntryFetched.page`
- `test/services/hoyowiki_index_test.dart` — v3 schema round trip + v1/v2 → v3 migration 案例
- `test/state/hoyowiki_index_test.dart` — `mergeEntry` 寫入 `pageByLang` 案例
- `test/state/gacha_repository_hoyowiki_test.dart` / `gacha_repository_refetch_test.dart` / `gacha_repository_import_with_hoyowiki_test.dart` — 既有案例改用新 type；補 per-lang refetch / enqueue dedupe regression
- `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` — 既有案例改用新 type；新增 desc / tags / 「前往 HoYoWiki」按鈕案例

---

### Task 1: 加 `HoYoWikiPageData` class + `_parseTags` helper（純加值，不破壞既有）

**Files:**
- Modify: `lib/services/hoyowiki_index.dart` — 新增 `HoYoWikiPageData` class
- Modify: `lib/services/hoyowiki_fetcher.dart` — 新增 `_parseTags` 私有 static + `@visibleForTesting` hook
- Modify: `test/services/hoyowiki_fetcher_test.dart` — `_parseTags` 單元測試

- [ ] **Step 1: 在 `lib/services/hoyowiki_index.dart` 加 `HoYoWikiPageData` class**

加在 `HoYoWikiGalleryItem` class 之後（檔案末尾「跨 UID 共用的 HoYoWiki lookup index」class 前）：

```dart
/// 某一個 lang 抓到的整組 entry_page 資料（gallery + desc + tags）。
/// 三個欄位永遠來自同一次 entry_page API 呼叫，原子性寫入。
class HoYoWikiPageData {
  /// 建立 [HoYoWikiPageData]。
  const HoYoWikiPageData({
    required this.gallery,
    required this.desc,
    required this.tags,
  });

  /// 該 lang 的 gallery_character 整組（pic + list）；entry 無
  /// `gallery_character` module 時為 null（例：武器頁）。
  final HoYoWikiGalleryData? gallery;

  /// 該 lang 的 `data.page.desc`；可能為純文字或含 HTML，可能為空字串。
  final String desc;

  /// 該 lang 的 `data.page.filter_values.*.values[]` 全部攤平後去重、保留
  /// 首次出現順序的 tag list；可能為空 list。
  final List<String> tags;
}
```

- [ ] **Step 2: 在 `lib/services/hoyowiki_fetcher.dart` 加 `_parseTags` 私有 static + test hook**

在 `HoYoWikiFetcher` class 內、`_parseGalleryCharacterModule` static method 之前加：

```dart
  /// 從 entry_page response 的 `data.page.filter_values` 攤平所有 group 的
  /// `values[]`，保留首次出現順序去重後回傳。例：
  ///
  ///   {character_property: {values: ['生命之契']},
  ///    character_rarity: {values: ['4星']},
  ///    character_region: {values: ['蒙德']}}
  ///   → ['生命之契', '4星', '蒙德']
  ///
  /// Map 遍歷順序：Dart `Map` 保證 insertion order，`jsonDecode` 回傳的是
  /// `LinkedHashMap`，所以「filter_values 出現順序」對同一份 JSON 穩定。
  static List<String> _parseTags(Object? filterValues) {
    if (filterValues is! Map) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final v in filterValues.values) {
      if (v is! Map) continue;
      final values = v['values'];
      if (values is! List) continue;
      for (final s in values) {
        if (s is! String) continue;
        final t = s.trim();
        if (t.isEmpty) continue;
        if (seen.add(t)) out.add(t);
      }
    }
    return List.unmodifiable(out);
  }

  /// 測試用：暴露 [_parseTags] 給單元測試。生產勿用。
  @visibleForTesting
  static List<String> parseTagsDebug(Object? filterValues) =>
      _parseTags(filterValues);
```

並在檔案 import 區加：
```dart
import 'package:meta/meta.dart';
```

- [ ] **Step 3: 在 `test/services/hoyowiki_fetcher_test.dart` 加 `_parseTags` 測試 group**

在檔案末尾（最後一個 `group('HoYoWikiFetcher.downloadImage', ...)` 後）加入：

```dart
  group('HoYoWikiFetcher._parseTags', () {
    test('多 group 攤平、保留出現順序', () {
      final input = {
        'character_property': {
          'values': ['生命之契'],
        },
        'character_rarity': {
          'values': ['4星'],
        },
        'character_region': {
          'values': ['蒙德'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['生命之契', '4星', '蒙德']);
    });

    test('跨 group 重複 value 去重、保留首次出現位置', () {
      final input = {
        'g1': {
          'values': ['A', 'B'],
        },
        'g2': {
          'values': ['B', 'C'],
        },
        'g3': {
          'values': ['A'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B', 'C']);
    });

    test('filter_values 為 null → 空 list', () {
      expect(HoYoWikiFetcher.parseTagsDebug(null), const <String>[]);
    });

    test('filter_values 非 map → 空 list', () {
      expect(HoYoWikiFetcher.parseTagsDebug('not a map'), const <String>[]);
      expect(HoYoWikiFetcher.parseTagsDebug(123), const <String>[]);
      expect(HoYoWikiFetcher.parseTagsDebug([]), const <String>[]);
    });

    test('group 缺 values key → 該 group skip', () {
      final input = {
        'g1': {
          'values': ['A'],
        },
        'g2': {'something_else': 'x'},
        'g3': {
          'values': ['B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('group 的 values 非 list → 該 group skip', () {
      final input = {
        'g1': {
          'values': ['A'],
        },
        'g2': {'values': 'not a list'},
        'g3': {
          'values': ['B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('value 非 string → skip', () {
      final input = {
        'g1': {
          'values': ['A', 123, null, 'B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('value trim 後為空字串 → skip', () {
      final input = {
        'g1': {
          'values': ['A', '   ', '\t\n', 'B'],
        },
      };
      expect(HoYoWikiFetcher.parseTagsDebug(input), ['A', 'B']);
    });

    test('回傳 List.unmodifiable（不可變）', () {
      final out = HoYoWikiFetcher.parseTagsDebug({
        'g1': {
          'values': ['A'],
        },
      });
      expect(() => out.add('x'), throwsUnsupportedError);
    });
  });
```

- [ ] **Step 4: 跑測試確認綠**

```
flutter test test/services/hoyowiki_fetcher_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: 跑 analyzer 確認綠**

```
flutter analyze lib/services/hoyowiki_index.dart lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
```

Expected: `No issues found!`

- [ ] **Step 6: 格式化**

```
dart format lib/services/hoyowiki_index.dart lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
```

- [ ] **Step 7: Commit**

```
git add lib/services/hoyowiki_index.dart lib/services/hoyowiki_fetcher.dart test/services/hoyowiki_fetcher_test.dart
git commit -m "feat(hoyowiki): add HoYoWikiPageData + _parseTags helper for filter_values"
```

---

### Task 2: 大切換 — `pageByLang` 取代 `galleryByLang` + storage v3 + fetcher 解 desc/tags

> **這個 task 是 type-level atomic 重構**：一次性把 `HoYoWikiEntry`、`HoYoWikiEntryFetched`、storage、`mergeEntry`、`needRefetchEntry`、`enqueueDownloadsForEntry` 全部換到新 type，連同所有 callsites 與 tests，否則 lib 不 compile。完成後 dialog 顯示行為**暫不動**（用 `page?.gallery` 替代 `galleryByLang[lang]` 即可），desc / tags UI 留到 Task 3。

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`
- Modify: `lib/services/hoyowiki_fetcher.dart`
- Modify: `lib/state/hoyowiki_index.dart`
- Modify: `lib/state/gacha_repository.dart`
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Modify: `test/services/hoyowiki_fetcher_test.dart`
- Modify: `test/services/hoyowiki_index_test.dart`
- Modify: `test/state/hoyowiki_index_test.dart`
- Modify: `test/state/gacha_repository_hoyowiki_test.dart`
- Modify: `test/state/gacha_repository_refetch_test.dart`
- Modify: `test/state/gacha_repository_import_with_hoyowiki_test.dart`
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

- [ ] **Step 1: 改 `HoYoWikiEntry` 用 `pageByLang`**

`lib/services/hoyowiki_index.dart` 內 `HoYoWikiEntry` class 把 `galleryByLang` 換成 `pageByLang`：

```dart
class HoYoWikiEntry {
  /// 建立 [HoYoWikiEntry]；`iconUrl` 可能為空字串。
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.pageByLang,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。lang-agnostic。
  final String iconUrl;

  /// 各語言整組 page 資料；key 為 `record.lang`（zh-tw / en / ja / ...）。
  /// 某 lang 不在 map 內 = 該 lang 還沒抓過。`gallery` 可能為 null（entry 無
  /// `gallery_character` module，如武器頁），但 `desc` / `tags` 仍可能有值。
  final Map<String, HoYoWikiPageData> pageByLang;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}
```

- [ ] **Step 2: 改 storage save (v3 schema)**

`lib/services/hoyowiki_index.dart` 內 `HoYoWikiIndexStorage.save`：

```dart
  /// 將 [index] 寫回磁碟（atomic rename）。
  Future<void> save(HoYoWikiIndex index) async {
    final json = {
      'version': 3,
      'search': index.searchMap,
      'entries': index.entries.map(
        (k, v) => MapEntry(k, {
          'icon_url': v.iconUrl,
          'fetched_at': v.fetchedAt.toUtc().toIso8601String(),
          'page_by_lang': v.pageByLang.map(
            (lang, p) => MapEntry(lang, {
              if (p.gallery != null)
                'gallery': {
                  'pic_url': p.gallery!.picUrl,
                  'list': p.gallery!.list
                      .map(
                        (it) => {
                          'id': it.id,
                          'key': it.key,
                          'img_url': it.imgUrl,
                          'img_desc_html': it.imgDescHtml,
                        },
                      )
                      .toList(),
                },
              'desc': p.desc,
              'tags': p.tags,
            }),
          ),
        }),
      ),
      'menu_ids': index.menuIds,
    };
    await baseDir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(_file.path);
    _log.fine(
      'saved search=${index.searchMap.length} '
      'entries=${index.entries.length} '
      'menuIds=${index.menuIds.length}',
    );
  }
```

- [ ] **Step 3: 改 storage load（v1/v2/v3 migration）**

`lib/services/hoyowiki_index.dart` 內 `HoYoWikiIndexStorage.load` 內處理三條 version path：

```dart
  /// 讀取 index；檔案不存在或解析失敗回空 index。
  Future<HoYoWikiIndex> load() async {
    final f = _file;
    if (!await f.exists()) return const HoYoWikiIndex.empty();
    try {
      final text = await f.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      final version = json['version'] as int? ?? 1;
      final searchJson = (json['search'] as Map<String, dynamic>?) ?? const {};
      final entriesJson =
          (json['entries'] as Map<String, dynamic>?) ?? const {};
      final menuIdsJson =
          (json['menu_ids'] as Map<String, dynamic>?) ?? const {};

      final isV3 = version >= 3;
      var droppedLegacy = 0;
      final entries = entriesJson.map((k, v) {
        final m = v as Map<String, dynamic>;
        final iconUrl = (m['icon_url'] as String?) ?? '';
        final fetchedAt = DateTime.parse(m['fetched_at'] as String);
        Map<String, HoYoWikiPageData> pageByLang;
        if (isV3 && m['page_by_lang'] is Map) {
          final pJson = m['page_by_lang'] as Map<String, dynamic>;
          pageByLang = pJson.map((lang, raw) {
            final pm = raw as Map<String, dynamic>;
            HoYoWikiGalleryData? gallery;
            final gJson = pm['gallery'];
            if (gJson is Map) {
              final listJson = (gJson['list'] as List<dynamic>?) ?? const [];
              gallery = HoYoWikiGalleryData(
                picUrl: (gJson['pic_url'] as String?) ?? '',
                list: listJson
                    .map((e) {
                      final em = e as Map<String, dynamic>;
                      return HoYoWikiGalleryItem(
                        id: (em['id'] as String?) ?? '',
                        key: (em['key'] as String?) ?? '',
                        imgUrl: (em['img_url'] as String?) ?? '',
                        imgDescHtml: (em['img_desc_html'] as String?) ?? '',
                      );
                    })
                    .toList(growable: false),
              );
            }
            final tagsJson = (pm['tags'] as List<dynamic>?) ?? const [];
            return MapEntry(
              lang,
              HoYoWikiPageData(
                gallery: gallery,
                desc: (pm['desc'] as String?) ?? '',
                tags: tagsJson
                    .whereType<String>()
                    .toList(growable: false),
              ),
            );
          });
        } else {
          // v1 (header) / v2 (gallery_by_lang) → v3: reset page_by_lang，
          // 下次 update 由 needRefetchEntry 觸發 per-lang 重抓補齊。
          pageByLang = const {};
          droppedLegacy++;
        }
        return MapEntry(
          k,
          HoYoWikiEntry(
            iconUrl: iconUrl,
            pageByLang: pageByLang,
            fetchedAt: fetchedAt,
          ),
        );
      });

      if (!isV3 && droppedLegacy > 0) {
        _log.info(
          'migrate v$version → v3: $droppedLegacy entries reset '
          '(gallery_by_lang dropped)',
        );
      }

      return HoYoWikiIndex(
        searchMap: searchJson.map((k, v) => MapEntry(k, v as String)),
        entries: entries,
        menuIds: menuIdsJson.map((k, v) => MapEntry(k, v as int)),
      );
    } catch (e, st) {
      _log.warning('load failed, return empty index', e, st);
      return const HoYoWikiIndex.empty();
    }
  }
```

- [ ] **Step 4: 改 `HoYoWikiEntryFetched` 結構**

`lib/services/hoyowiki_fetcher.dart` 內 `HoYoWikiEntryFetched`：

```dart
/// HoYoWiki entry_page API 抓到的 icon URL 與該 lang 的整組 page 資料。
class HoYoWikiEntryFetched {
  /// 建立 [HoYoWikiEntryFetched]；icon 可能為空字串；`page.gallery` 可能為
  /// null（entry 無 `gallery_character` module），`page.desc` / `page.tags`
  /// 可能為空。
  const HoYoWikiEntryFetched({required this.iconUrl, required this.page});

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 該 lang 的整組 page 資料（gallery + desc + tags）。
  final HoYoWikiPageData page;
}
```

- [ ] **Step 5: 改 `fetchEntryPage` 解 desc + tags**

`lib/services/hoyowiki_fetcher.dart` 內 `fetchEntryPage` 末段：

```dart
    final page = body['data']?['page'] as Map<String, dynamic>?;
    final iconUrl = (page?['icon_url'] as String?) ?? '';
    final modules = (page?['modules'] as List<dynamic>?) ?? const [];
    final gallery = _parseGalleryCharacterModule(modules);
    final desc = (page?['desc'] as String?) ?? '';
    final tags = _parseTags(page?['filter_values']);
    _log.info(
      'entry id=$id lang=$lang icon=${iconUrl.isNotEmpty} '
      'gallery=${gallery != null} '
      'pic=${gallery?.picUrl.isNotEmpty == true} '
      'list=${gallery?.list.length ?? 0} '
      'desc=${desc.isNotEmpty} tags=${tags.length}',
    );
    return HoYoWikiEntryFetched(
      iconUrl: iconUrl,
      page: HoYoWikiPageData(gallery: gallery, desc: desc, tags: tags),
    );
```

- [ ] **Step 6: 改 `HoYoWikiIndexNotifier.mergeEntry`**

`lib/state/hoyowiki_index.dart` 內 `mergeEntry`：

```dart
  /// 把單一 lang 的 fetch 結果 merge 進既有 entry（不覆蓋其他 lang）。icon
  /// 採「非空覆寫」策略，避免某 lang 抓回空 icon 把既有好值清掉。
  Future<void> mergeEntry({
    required String id,
    required String lang,
    required HoYoWikiEntryFetched fetched,
  }) async {
    await _lock.synchronized(() async {
      final existing = state.entries[id];
      final mergedPage = <String, HoYoWikiPageData>{
        if (existing != null) ...existing.pageByLang,
        lang: fetched.page,
      };
      final iconUrl = fetched.iconUrl.isNotEmpty
          ? fetched.iconUrl
          : (existing?.iconUrl ?? '');
      final merged = HoYoWikiEntry(
        iconUrl: iconUrl,
        pageByLang: mergedPage,
        fetchedAt: DateTime.now().toUtc(),
      );
      final newEntries = Map<String, HoYoWikiEntry>.from(state.entries)
        ..[id] = merged;
      final next = HoYoWikiIndex(
        searchMap: state.searchMap,
        entries: newEntries,
        menuIds: state.menuIds,
      );
      await _saveAndEmit(next);
      _log.fine(
        'merge page id=$id lang=$lang gallery=${fetched.page.gallery != null} '
        'desc=${fetched.page.desc.isNotEmpty} tags=${fetched.page.tags.length}',
      );
    });
  }
```

- [ ] **Step 7: 改 `gacha_repository.dart` 內 `needRefetchEntry`**

`lib/state/gacha_repository.dart` 內 `_fetchHoYoWiki` 內 nested 的 `needRefetchEntry`：

```dart
    /// 重抓判定：entry 或 menuId 缺失，或該 lang 還沒有 page → true。
    bool needRefetchEntry(HoYoWikiEntry? entry, int? menuId, String lang) {
      if (entry == null) return true;
      if (menuId == null) return true;
      if (!entry.pageByLang.containsKey(lang)) return true;
      return false;
    }
```

- [ ] **Step 8: 改 `enqueueDownloadsForEntry`**

`lib/state/gacha_repository.dart` 內 `_fetchHoYoWiki` 內 `enqueueDownloadsForEntry` 的 gallery 段落：

```dart
      // gallery：迭代所有 lang 的 page，gallery 為 null 跳過（如武器頁）
      for (final page in entry.pageByLang.values) {
        final g = page.gallery;
        if (g == null) continue;
        void enqueue(String url) {
          if (url.isEmpty) return;
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: url,
          );
          if (f.existsSync()) return;
          if (!seenUrls.add('gallery::$id::$url')) return;
          downloadTodo.add(
            _HoYoWikiDownloadItem(id: id, url: url, isGallery: true),
          );
        }

        enqueue(g.picUrl);
        for (final it in g.list) {
          enqueue(it.imgUrl);
        }
      }
```

- [ ] **Step 9: 改 dialog 內取資料鏈（暫不改 UI）**

`lib/widgets/dialogs/gacha_item_detail_dialog.dart` 內 build 開頭附近：

```dart
    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final page = entry?.pageByLang[record.lang];
    final gallery = page?.gallery;
```

底下 chip 列邏輯維持 — 凡 reference `gallery` 的地方繼續 work（gallery 從 `entry.galleryByLang[record.lang]` 改成 `page?.gallery`，型別與行為一致）。

- [ ] **Step 10: 改 `test/services/hoyowiki_fetcher_test.dart` 既有案例 + 新增 desc/tags 案例**

把既有 `group('HoYoWikiFetcher.fetchEntryPage gallery', ...)` 內所有 `res.gallery` 改為 `res.page.gallery`、`res.gallery!.picUrl` 改為 `res.page.gallery!.picUrl` 等。例如：

```dart
      expect(res.iconUrl, 'https://x/icon.png');
      expect(res.page.gallery, isNotNull);
      expect(res.page.gallery!.picUrl, 'https://x/card.png');
      expect(res.page.gallery!.list, hasLength(2));
      expect(res.page.gallery!.list[0].key, '原畫');
      expect(res.page.gallery!.list[1].imgUrl, 'https://x/idle.gif');
      expect(res.page.gallery!.list[1].imgDescHtml, '');
```

並把「無 gallery_character module → gallery 為 null」改為 `expect(res.page.gallery, isNull)`、「data 非合法 JSON → gallery 為 null」改為 `expect(res.page.gallery, isNull)`、「pic 與 list 皆空 → gallery 為 null」改為 `expect(res.page.gallery, isNull)`。

再加新 group：

```dart
  group('HoYoWikiFetcher.fetchEntryPage desc + tags', () {
    http.Response entryWithDescAndTags({
      required String desc,
      required Map<String, dynamic>? filterValues,
    }) {
      final body = jsonEncode({
        'retcode': 0,
        'message': 'OK',
        'data': {
          'page': {
            'icon_url': '',
            'desc': desc,
            'filter_values': filterValues,
            'modules': const [],
          },
        },
      });
      return http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    test('正常解析 desc + tags', () async {
      final mock = MockClient(
        (req) async => entryWithDescAndTags(
          desc: '「往生堂」第七十七代堂主...',
          filterValues: {
            'character_property': {
              'values': ['生命之契'],
            },
            'character_rarity': {
              'values': ['4星'],
            },
            'character_region': {
              'values': ['蒙德'],
            },
          },
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.page.desc, '「往生堂」第七十七代堂主...');
      expect(res.page.tags, ['生命之契', '4星', '蒙德']);
      expect(res.page.gallery, isNull);
    });

    test('desc 缺 key → 空字串', () async {
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'retcode': 0,
            'message': 'OK',
            'data': {
              'page': {'icon_url': '', 'modules': []},
            },
          }),
          200,
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.page.desc, '');
    });

    test('desc 為非 string 型別 → 空字串', () async {
      final mock = MockClient(
        (req) async => entryWithDescAndTags(
          desc: '',
          filterValues: null,
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.page.desc, '');
    });

    test('filter_values 為 null → tags 空 list', () async {
      final mock = MockClient(
        (req) async => entryWithDescAndTags(
          desc: 'something',
          filterValues: null,
        ),
      );
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(res.page.tags, const <String>[]);
    });
  });
```

- [ ] **Step 11: 改 `test/services/hoyowiki_index_test.dart` 既有案例 + 新增 v3 / migration 案例**

先讀檔了解既有結構（用 `Read` tool 看 `test/services/hoyowiki_index_test.dart` 全文）。把所有 `galleryByLang` 改為 `pageByLang`、把 `HoYoWikiGalleryData(...)` 包裝為 `HoYoWikiPageData(gallery: HoYoWikiGalleryData(...), desc: '', tags: const [])`。

再新增 group：

```dart
  group('HoYoWikiIndexStorage v3 schema', () {
    test('round trip：page_by_lang 完整保存 gallery + desc + tags', () async {
      final storage = HoYoWikiIndexStorage(tempDir);
      final index = HoYoWikiIndex(
        searchMap: const {'zh-tw::胡桃': '5125428'},
        entries: {
          '5125428': HoYoWikiEntry(
            iconUrl: 'https://x/icon.png',
            pageByLang: {
              'zh-tw': const HoYoWikiPageData(
                gallery: HoYoWikiGalleryData(
                  picUrl: 'https://x/card.png',
                  list: [
                    HoYoWikiGalleryItem(
                      id: 'g1',
                      key: '原畫',
                      imgUrl: 'https://x/c.png',
                      imgDescHtml: '<p>x</p>',
                    ),
                  ],
                ),
                desc: '「往生堂」...',
                tags: ['生命之契', '4星', '蒙德'],
              ),
            },
            fetchedAt: DateTime.utc(2026, 5, 26),
          ),
        },
        menuIds: const {'5125428': 2},
      );
      await storage.save(index);
      final reloaded = await storage.load();
      final page = reloaded.lookupEntry('5125428')!.pageByLang['zh-tw']!;
      expect(page.gallery!.picUrl, 'https://x/card.png');
      expect(page.gallery!.list, hasLength(1));
      expect(page.desc, '「往生堂」...');
      expect(page.tags, ['生命之契', '4星', '蒙德']);
    });

    test('gallery 為 null 的 page（武器頁）也能 round trip', () async {
      final storage = HoYoWikiIndexStorage(tempDir);
      final index = HoYoWikiIndex(
        searchMap: const {'en-us::Sword': '9001'},
        entries: {
          '9001': HoYoWikiEntry(
            iconUrl: 'https://x/sword.png',
            pageByLang: const {
              'en-us': HoYoWikiPageData(
                gallery: null,
                desc: 'A sharp blade.',
                tags: ['4★', 'Sword'],
              ),
            },
            fetchedAt: DateTime.utc(2026, 5, 26),
          ),
        },
        menuIds: const {'9001': 4},
      );
      await storage.save(index);
      final reloaded = await storage.load();
      final page = reloaded.lookupEntry('9001')!.pageByLang['en-us']!;
      expect(page.gallery, isNull);
      expect(page.desc, 'A sharp blade.');
      expect(page.tags, ['4★', 'Sword']);
    });
  });

  group('HoYoWikiIndexStorage v1/v2 → v3 migration', () {
    test('v2 cache 載入：pageByLang reset 為空、icon_url / search / menu_ids '
        '保留', () async {
      // 直接寫一份 v2 schema 到磁碟
      final v2 = {
        'version': 2,
        'search': {'zh-tw::胡桃': '5125428'},
        'menu_ids': {'5125428': 2},
        'entries': {
          '5125428': {
            'icon_url': 'https://x/icon.png',
            'fetched_at': '2026-05-25T10:00:00.000Z',
            'gallery_by_lang': {
              'zh-tw': {
                'pic_url': 'https://x/card.png',
                'list': [],
              },
            },
          },
        },
      };
      final f = File('${tempDir.path}/hoyowiki_index.json');
      await f.writeAsString(jsonEncode(v2));
      final storage = HoYoWikiIndexStorage(tempDir);
      final loaded = await storage.load();
      final entry = loaded.lookupEntry('5125428')!;
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.pageByLang, isEmpty);
      expect(loaded.lookupId(name: '胡桃', lang: 'zh-tw'), '5125428');
      expect(loaded.lookupMenuId('5125428'), 2);
    });

    test('v1 cache 載入：pageByLang reset 為空、header_img_url 丟棄', () async {
      final v1 = {
        'version': 1,
        'search': {'en-us::Sword': '9001'},
        'menu_ids': {'9001': 4},
        'entries': {
          '9001': {
            'icon_url': 'https://x/sword.png',
            'header_img_url': 'https://x/header.png',
            'fetched_at': '2026-05-25T10:00:00.000Z',
          },
        },
      };
      final f = File('${tempDir.path}/hoyowiki_index.json');
      await f.writeAsString(jsonEncode(v1));
      final storage = HoYoWikiIndexStorage(tempDir);
      final loaded = await storage.load();
      final entry = loaded.lookupEntry('9001')!;
      expect(entry.iconUrl, 'https://x/sword.png');
      expect(entry.pageByLang, isEmpty);
    });
  });
```

import 區補：
```dart
import 'dart:convert';
import 'dart:io';
```
（若尚未引入）

- [ ] **Step 12: 改 `test/state/hoyowiki_index_test.dart` 既有案例 + 新增 mergeEntry page 案例**

先讀檔了解既有結構。把所有 `galleryByLang` 改為 `pageByLang`，把 fetched 的 `gallery:` 換成 `page: HoYoWikiPageData(gallery: ..., desc: '', tags: const [])`。

新增 case：

```dart
  test('mergeEntry 寫入完整 page（gallery + desc + tags）', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.mergeEntry(
      id: '5125428',
      lang: 'zh-tw',
      fetched: const HoYoWikiEntryFetched(
        iconUrl: 'https://x/icon.png',
        page: HoYoWikiPageData(
          gallery: HoYoWikiGalleryData(
            picUrl: 'https://x/card.png',
            list: [],
          ),
          desc: '「往生堂」...',
          tags: ['生命之契', '4星'],
        ),
      ),
    );
    final page = container
        .read(hoyowikiIndexProvider)
        .lookupEntry('5125428')!
        .pageByLang['zh-tw']!;
    expect(page.gallery!.picUrl, 'https://x/card.png');
    expect(page.desc, '「往生堂」...');
    expect(page.tags, ['生命之契', '4星']);
  });
```

- [ ] **Step 13: 改 `test/state/gacha_repository_hoyowiki_test.dart`**

先讀檔了解結構。把任何構造 `HoYoWikiEntry(galleryByLang: ...)` 改用 `pageByLang: {lang: HoYoWikiPageData(gallery: ..., desc: '', tags: const [])}`；任何構造 `HoYoWikiEntryFetched(iconUrl: ..., gallery: ...)` 改用 `page: HoYoWikiPageData(gallery: ..., desc: '', tags: const [])`。

- [ ] **Step 14: 改 `test/state/gacha_repository_refetch_test.dart` 與 `gacha_repository_import_with_hoyowiki_test.dart`**

同 Step 13 機械改寫所有 `galleryByLang` / `gallery:` 為新 type。

- [ ] **Step 15: 改 `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`**

把 `_entryWith` helper 改成構造 `pageByLang` 與 `HoYoWikiPageData`：

```dart
HoYoWikiEntry _entryWith({
  required String iconUrl,
  required String picUrl,
  required List<HoYoWikiGalleryItem> list,
  String lang = 'en-us',
  String desc = '',
  List<String> tags = const [],
}) => HoYoWikiEntry(
  iconUrl: iconUrl,
  pageByLang: {
    lang: HoYoWikiPageData(
      gallery: HoYoWikiGalleryData(picUrl: picUrl, list: list),
      desc: desc,
      tags: tags,
    ),
  },
  fetchedAt: DateTime.utc(2026, 5, 26),
);
```

其他 reference `galleryByLang` 的地方一併改為 `pageByLang`（讀檔後逐處改）。

- [ ] **Step 16: 全套品質檢查**

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: `No issues found!` + `All tests passed!`。若 fail，回到上面 step 修正後再跑。

- [ ] **Step 17: Commit**

```
git add -A
git commit -m "refactor(hoyowiki): introduce HoYoWikiPageData + storage v3 with desc/tags fields"
```

---

### Task 3: Dialog title 區顯示 desc + tags

> 不動 content 區（chip 列 + 圖 + imgDesc 保留）。也不動 actions 區（Task 5 才加按鈕）。

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

- [ ] **Step 1: 在 `gacha_item_detail_dialog.dart` build 內取 desc / tags**

build 開頭資料鏈處（Task 2 已改為從 `page` 取 gallery），補：

```dart
    final page = entry?.pageByLang[record.lang];
    final gallery = page?.gallery;
    final desc = page?.desc ?? '';
    final tags = page?.tags ?? const <String>[];
```

- [ ] **Step 2: 重構 title 為 Row(icon, Column(name, desc, tags))**

把現有的 `title:` 內容替換為：

```dart
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(
                iconFile,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, e, st) {
                  Logger(
                    'gacha.hoyowiki.detail',
                  ).warning('icon errorBuilder id=$id', e, st);
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: nameColor,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (desc.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(child: Html(data: desc)),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tags)
                        Chip(
                          label: Text(t),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
```

- [ ] **Step 3: 在 widget test 加 desc / tags 顯示案例**

既有 helper：`pumpDialog(tester, record)`（line 190）+ `seedIndex(tester, notifier, name, id, fetched)`（line 99）+ `_touchFile(dir, relative)`（line 33）。沿用、不另造輪子。

在 `'GachaItemDetailDialog 渲染'` group 內（既有 `'小視窗 (640x480) 不會 vertical overflow'` 之後）補：

```dart
    testWidgets('desc 為空字串 → title 區不渲染 desc Html', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      // gallery null + desc 空：整個 dialog 內無 Html widget。
      expect(find.byType(Html), findsNothing);
    });

    testWidgets('desc 帶 HTML → title 區渲染 Html 且文字可見', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(
            gallery: null,
            desc: '<p>Hello desc</p>',
            tags: [],
          ),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Html), findsOneWidget);
      expect(find.textContaining('Hello desc'), findsOneWidget);
    });

    testWidgets('tags 3 個 → Wrap 內 3 個 Chip 顯示 label 文字', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(
            gallery: null,
            desc: '',
            tags: ['Pyro', '4★', 'Polearm'],
          ),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Chip), findsNWidgets(3));
      expect(find.text('Pyro'), findsOneWidget);
      expect(find.text('4★'), findsOneWidget);
      expect(find.text('Polearm'), findsOneWidget);
    });

    testWidgets('tags 為空 list → Chip 不渲染', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      expect(find.byType(Chip), findsNothing);
    });
```

- [ ] **Step 4: 跑 widget tests + analyzer + format**

```
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
flutter analyze lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
dart format lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: `All tests passed!` + `No issues found!`

- [ ] **Step 5: Commit**

```
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
git commit -m "feat(hoyowiki): show desc + tags below item name in detail dialog"
```

---

### Task 4: i18n — 新增 `actionViewOnHoYoWiki` key + 翻譯

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_pt_BR.arb`
- Modify: `lib/l10n/app_th.arb`
- Modify: `lib/l10n/app_vi.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`

> **依 memory `feedback_i18n_starts_from_zh.md`**：先寫繁中，再以中文為基準翻其他語系，不從 `app_en.arb` 起手。
> **依 memory `feedback_i18n_skip_empty_arbs.md`**：只加在已有實體翻譯的 ARB（上列 9 個），其他空殼留給 Crowdin pipeline。
> **依 memory `feedback_ci_messages_english.md`** 不適用（這是 UI 文字非 CI）。
> **依 memory `project_terminology_glossary_authoritative.md`**：先查 `docs/術語表.md`，「HoYoWiki」為品牌名不翻譯。

- [ ] **Step 1: 在 `lib/l10n/app_zh.arb` 加 zh-Hant 翻譯**

在 `galleryIconLabel` block 之後（檔案末尾 `}` 之前）加 comma + 新 key：

```json
  "galleryIconLabel": "圖示",
  "@galleryIconLabel": {
    "description": "Item detail dialog gallery: chip label for the icon page placed last in the chip row. Lets items without a gallery_character module (e.g. weapons) still open the dialog and show the icon image."
  },

  "actionViewOnHoYoWiki": "前往 HoYoWiki",
  "@actionViewOnHoYoWiki": {
    "description": "Item detail dialog actions: button label that opens the HoYoLAB Wiki entry page for the current item in the default browser."
  }
}
```

> 依 memory `feedback_chinese_comments_fullwidth_punctuation.md`：繁中文字本身（「前往 HoYoWiki」）標點維持半形空白 + 品牌名，無中文標點需要全形化。description 用英文（既有 `galleryCardLabel` / `galleryIconLabel` 慣例）。

- [ ] **Step 2: 翻譯到其他 8 個有實體翻譯的 ARB**

每個檔案在最後一個 key（通常是 `galleryIconLabel`）後加 comma + 新 key（無 metadata，依既有規範）。

`lib/l10n/app_en.arb`：
```json
  "galleryIconLabel": "Icon",
  "actionViewOnHoYoWiki": "View on HoYoWiki"
}
```

`lib/l10n/app_es.arb`：
```json
  "galleryIconLabel": "Icono",
  "actionViewOnHoYoWiki": "Ver en HoYoWiki"
}
```

`lib/l10n/app_fr.arb`：
```json
  "galleryIconLabel": "Icône",
  "actionViewOnHoYoWiki": "Voir sur HoYoWiki"
}
```

`lib/l10n/app_ja.arb`：
```json
  "galleryIconLabel": "アイコン",
  "actionViewOnHoYoWiki": "HoYoWiki で開く"
}
```

`lib/l10n/app_pt_BR.arb`：
```json
  "galleryIconLabel": "Ícone",
  "actionViewOnHoYoWiki": "Ver no HoYoWiki"
}
```

`lib/l10n/app_th.arb`：
```json
  "galleryIconLabel": "ไอคอน",
  "actionViewOnHoYoWiki": "เปิดใน HoYoWiki"
}
```

`lib/l10n/app_vi.arb`：
```json
  "galleryIconLabel": "Biểu tượng",
  "actionViewOnHoYoWiki": "Xem trên HoYoWiki"
}
```

`lib/l10n/app_zh_Hans.arb`：
```json
  "galleryIconLabel": "图标",
  "actionViewOnHoYoWiki": "前往 HoYoWiki"
}
```

> 每個檔案在加入前先用 `Read` 工具看末尾，確認最後一個 key 與 brace 位置。

- [ ] **Step 3: 跑 codegen 並驗證**

```
flutter gen-l10n
flutter analyze lib/l10n/
```

Expected: `flutter gen-l10n` 無錯誤輸出；`flutter analyze` `No issues found!`。`lib/l10n/generated/app_localizations.dart` 與各 `app_localizations_*.dart` 應該已自動更新含 `actionViewOnHoYoWiki` getter。

- [ ] **Step 4: Commit**

```
git add lib/l10n/
git commit -m "i18n: add actionViewOnHoYoWiki key for HoYoWiki external link button"
```

---

### Task 5: Dialog actions 加「前往 HoYoWiki」按鈕

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

- [ ] **Step 1: 在 `gacha_item_detail_dialog.dart` 加 `openExternalUrl` import**

import 區補：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
```

- [ ] **Step 2: 改 `actions` 區加「前往 HoYoWiki」按鈕**

把現有 `actions: [FilledButton(...)]` 改為：

```dart
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.actionViewOnHoYoWiki),
          onPressed: id == null
              ? null
              : () {
                  Logger('gacha.hoyowiki.detail').info('open wiki id=$id');
                  openExternalUrl(
                    Uri.parse(
                      'https://wiki.hoyolab.com/pc/genshin/entry/$id',
                    ),
                  );
                },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
```

- [ ] **Step 3: 在 widget test 加按鈕案例**

在 `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` 加：

```dart
    testWidgets('actions 區顯示「前往 HoYoWiki」按鈕，label 與 icon 正確', (
      tester,
    ) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await seedIndex(
        tester,
        notifier,
        name: 'X',
        id: 'x1',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      await tester.runAsync(() async {
        await _touchFile(tempDir, 'x1_icon.png');
      });
      await pumpDialog(tester, _rec(name: 'X', gachaType: '301'));
      final l = AppLocalizations.of(
        tester.element(find.byType(GachaItemDetailDialog)),
      )!;
      expect(find.text(l.actionViewOnHoYoWiki), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final btn = tester.widget<TextButton>(
        find.ancestor(
          of: find.text(l.actionViewOnHoYoWiki),
          matching: find.byType(TextButton),
        ),
      );
      expect(btn.onPressed, isNotNull);
    });
```

> **不測 launch 實際行為**：`openExternalUrl` 內部呼 `url_launcher` 平台 channel，測試端 mock 成本高且 helper 已在 `app_link.dart` 處驗證過。只驗證「按鈕存在 + label + icon + onPressed 非 null」。

- [ ] **Step 4: 全套品質檢查**

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: `No issues found!` + `All tests passed!`。

- [ ] **Step 5: Commit**

```
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
git commit -m "feat(hoyowiki): add 'View on HoYoWiki' external link button to detail dialog"
```

---

## 完成判定

所有 task 完成後最終確認：

1. **品質檢查（CLAUDE.md 強制）**
   ```
   dart format lib/ test/
   flutter analyze
   flutter test
   ```
   Expected: 全綠。

2. **手動 sanity check（release 模式）**
   - 用既有有抽到資料的 UID 開啟 dialog；確認某角色物品 desc + tags 正常顯示。
   - 點「前往 HoYoWiki」按鈕應於預設瀏覽器開啟 `https://wiki.hoyolab.com/pc/genshin/entry/<id>`。
   - 開一個武器物品 dialog 應該也能看到 desc / tags（武器頁通常有 filter_values 但無 gallery_character）。
   - 切換 app UI 語言不影響 dialog 內 desc / tags 內容（仍跟著 record.lang）。

3. **不 push**（依 CLAUDE.md「不要主動 git push」）。
