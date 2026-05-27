# HoYoWiki Gallery Character Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single `header_img_url` in 物品 dialog with per-language gallery (multiple images + GIF + descriptions) parsed from hoyowiki `entry_page` `modules[].components[]` where `component_id == "gallery_character"`.

**Architecture:** Layered changes from data → fetcher → state → repository → UI. Schema bumped v1 → v2; old v1 entries lose their `header_img_url` on load and naturally re-fetch via per-lang `needRefetchEntry`. Cache files named by SHA1 hash of URL so cross-lang identical URLs are reused, distinct URLs each get their own file. Dialog rewritten as `StatefulWidget` with `ChoiceChip` Wrap + `Image.file` + `flutter_html` description.

**Tech Stack:** Flutter 3.x, Riverpod, `http`, `logging`, `synchronized`, new deps `flutter_html` + `crypto`.

**Spec:** [`docs/superpowers/specs/2026-05-26-hoyowiki-gallery-character-design.md`](../specs/2026-05-26-hoyowiki-gallery-character-design.md)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | Modify | Add `flutter_html`, `crypto` |
| `lib/services/hoyowiki_index.dart` | Modify (big) | New types (`HoYoWikiGalleryData`, `HoYoWikiGalleryItem`); `HoYoWikiEntry` refactor (remove `headerImgUrl`, add `galleryByLang`); storage v2 + v1 migration; new helpers `hoyowikiIconCacheFile` / `hoyowikiGalleryCacheFile`; remove `HoYoWikiImageKind` + `hoyowikiCacheFile` |
| `lib/services/hoyowiki_fetcher.dart` | Modify | `HoYoWikiEntryFetched` struct change; `_parseGalleryCharacterModule` helper; `fetchEntryPage` adds `lang` param, sends `X-Rpc-Language` header |
| `lib/state/hoyowiki_index.dart` | Modify | `setEntry` → `mergeEntry` (per-lang merge + icon non-empty overwrite) |
| `lib/state/gacha_repository.dart` | Modify | `entryTodo: Set<({String id, String lang})>`; `needRefetchEntry` per-lang; download stage URL dedupe + icon/gallery split |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | Rewrite | `StatefulWidget` with `ChoiceChip` Wrap + `Image.file` + `flutter_html` desc; `hasHoYoWikiContent` rewrite |
| `lib/l10n/app_zh.arb` | Modify | Add `galleryCardLabel` (繁中：「卡片」) |
| `lib/l10n/app_*.arb` (others) | Modify | Add `galleryCardLabel` stub key (translations via Crowdin pipeline) |
| `test/services/hoyowiki_fetcher_test.dart` | Modify | Add gallery-character parse + lang header tests |
| `test/services/hoyowiki_index_test.dart` | Modify | v2 round trip, v1 migration, new cache helper tests |
| `test/state/hoyowiki_index_test.dart` | Modify | `mergeEntry` tests |
| `test/state/gacha_repository_hoyowiki_test.dart` | Modify | per-lang entryTodo + download dedupe tests |
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | Modify | chip + gallery + tearDown imageCache tests |

---

## Task 1: Add `flutter_html` + `crypto` deps

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Look up latest versions via context7**

Run:
```bash
npx ctx7@latest library flutter_html "Flutter 3.x compatibility"
```
Pick the result with `/org/project` ID, then:
```bash
npx ctx7@latest docs <libraryId> "current published version on pub.dev"
```
Repeat for `crypto`. Record the chosen versions (e.g., `flutter_html: ^3.0.0-beta.2`, `crypto: ^3.0.6`).

If context7 quota errors, fall back to checking https://pub.dev/packages/flutter_html and https://pub.dev/packages/crypto.

- [ ] **Step 2: Add deps to pubspec**

Edit `pubspec.yaml` `dependencies:` block, inserting alphabetically near `http: ^1.6.0`:

```yaml
  crypto: ^3.0.6
  ...
  flutter_html: ^3.0.0-beta.2
```

Use the actual versions from Step 1.

- [ ] **Step 3: Resolve and verify**

Run:
```powershell
flutter pub get
```
Expected: `Got dependencies!` (or `Changed N dependencies!`). No errors.

- [ ] **Step 4: Commit**

```powershell
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add flutter_html and crypto for hoyowiki gallery"
```

---

## Task 2: Add `HoYoWikiGalleryData` and `HoYoWikiGalleryItem` value types

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`

These are pure value classes added alongside existing types — no consumer breakage yet. JSON round-trip exercise comes in Task 5.

- [ ] **Step 1: Add the two classes after `HoYoWikiEntry`**

In `lib/services/hoyowiki_index.dart`, after the `HoYoWikiEntry` class block (currently ends ~line 24, before `/// 跨 UID 共用的 HoYoWiki lookup index。`), insert:

```dart
/// 單一 lang 的整組 gallery（pic 卡片 + list 圖文），對應 HoYoWiki entry_page
/// `gallery_character` component 解出的內容。
class HoYoWikiGalleryData {
  /// 建立 [HoYoWikiGalleryData]。
  const HoYoWikiGalleryData({required this.picUrl, required this.list});

  /// 卡片大圖 URL；可能為空字串（API 未提供）。
  final String picUrl;

  /// gallery 內所有圖片條目，依 API 順序。
  final List<HoYoWikiGalleryItem> list;
}

/// gallery 內單一圖片條目（對應 list[i]）。
class HoYoWikiGalleryItem {
  /// 建立 [HoYoWikiGalleryItem]。
  const HoYoWikiGalleryItem({
    required this.id,
    required this.key,
    required this.imgUrl,
    required this.imgDescHtml,
  });

  /// HoYoWiki 給的條目 ID（如 `gallery_character8511`）。
  final String id;

  /// chip 顯示標籤（lang-specific，如「原畫」/「閒置動作１」）。
  final String key;

  /// 圖片 URL（png/jpg/webp/gif；跨 lang 可能不同）。
  final String imgUrl;

  /// 圖片描述（HTML，含 `<p>` 段落；可能為空字串）。
  final String imgDescHtml;
}
```

- [ ] **Step 2: Verify analyze stays clean**

Run:
```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```powershell
git add lib/services/hoyowiki_index.dart
git commit -m "feat(hoyowiki): add HoYoWikiGalleryData and HoYoWikiGalleryItem types"
```

---

## Task 3: Add `hoyowikiIconCacheFile` and `hoyowikiGalleryCacheFile` helpers

**Files:**
- Modify: `lib/services/hoyowiki_index.dart`
- Test: `test/services/hoyowiki_index_test.dart`

Both new helpers coexist with the existing `hoyowikiCacheFile` + `HoYoWikiImageKind`; the old ones get removed in Task 5 after consumers migrate.

- [ ] **Step 1: Write failing tests**

Add to `test/services/hoyowiki_index_test.dart` at the bottom of `void main() { ... }` (after the last existing `group(...)`):

```dart
  group('hoyowikiIconCacheFile', () {
    final baseDir = Directory.systemTemp;

    test('組合為 <id>_icon.<ext>', () {
      final f = hoyowikiIconCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/icon.png',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('無副檔名時 fallback png', () {
      final f = hoyowikiIconCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/icon',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });
  });

  group('hoyowikiGalleryCacheFile', () {
    final baseDir = Directory.systemTemp;

    test('同 URL → 同檔名', () {
      final a = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      final b = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      expect(a.path, b.path);
    });

    test('不同 URL → 不同檔名', () {
      final a = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      final b = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/b.png',
      );
      expect(a.path, isNot(b.path));
    });

    test('檔名格式為 <id>_gallery_<hash12>.<ext>', () {
      final f = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.gif',
      );
      expect(
        RegExp(r'5125428_gallery_[0-9a-f]{12}\.gif$').hasMatch(f.path),
        isTrue,
      );
    });

    test('帶 query string 不影響 ext 推導', () {
      final f = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.webp?token=abc',
      );
      expect(f.path, endsWith('.webp'));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```powershell
flutter test test/services/hoyowiki_index_test.dart
```
Expected: compile error (`hoyowikiIconCacheFile` and `hoyowikiGalleryCacheFile` not defined).

- [ ] **Step 3: Add `package:crypto` import**

At top of `lib/services/hoyowiki_index.dart` (after existing imports), add:

```dart
import 'package:crypto/crypto.dart';
```

- [ ] **Step 4: Add the two helpers (and reuse `_extFromUrl`)**

At the bottom of `lib/services/hoyowiki_index.dart`, after the existing `hoyowikiCacheFile` function (around line 179) and before `_extFromUrl`, insert:

```dart
/// 推導 icon 的 cache 路徑：`<id>_icon.<ext>`。
File hoyowikiIconCacheFile({
  required Directory baseDir,
  required String id,
  required String url,
}) {
  return File('${baseDir.path}/${id}_icon.${_extFromUrl(url)}');
}

/// 推導 gallery 圖片（pic 或 list[].img）的 cache 路徑：
/// `<id>_gallery_<sha1Hex前12碼>.<ext>`。同 URL 自然同檔，跨 lang 同 URL 共用。
File hoyowikiGalleryCacheFile({
  required Directory baseDir,
  required String id,
  required String url,
}) {
  final hash = sha1.convert(utf8.encode(url)).toString().substring(0, 12);
  return File('${baseDir.path}/${id}_gallery_$hash.${_extFromUrl(url)}');
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:
```powershell
flutter test test/services/hoyowiki_index_test.dart
```
Expected: All tests in this file pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/services/hoyowiki_index.dart test/services/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): add icon/gallery cache file helpers"
```

---

## Task 4: Add `galleryCardLabel` ARB key + regen l10n

**Files:**
- Modify: `lib/l10n/app_zh.arb`, `lib/l10n/app_*.arb` (all other locales)

Per memory `feedback_i18n_starts_from_zh`: write 繁中 first, then propagate. Translations for non-zh locales should be filled with the zh value as placeholder for now (Crowdin pipeline picks them up later).

Per memory `project_terminology_glossary_authoritative`: check `docs/術語表.md` first — if「卡片」has an official rendering for any locale, use it.

- [ ] **Step 1: Check terminology glossary**

Read `docs/術語表.md` (search for「卡片」/ "card"). If a row exists, note the per-locale official value to use later.

- [ ] **Step 2: Add to `app_zh.arb`**

Open `lib/l10n/app_zh.arb`. Find a logical place (alphabetically near other `gallery*` or generic UI keys; if unsure, append before the closing `}`). Insert:

```json
  "galleryCardLabel": "卡片",
  "@galleryCardLabel": {
    "description": "Gallery 圖集中「卡片（pic）」chip 分頁的標籤。對應 hoyowiki entry_page gallery_character.pic 的 chip 標籤；非物品本身名稱。"
  },
```

Make sure preceding entry's `}` line ends with a trailing comma if you're appending after it.

- [ ] **Step 3: Add stub to all other `app_*.arb`**

For each `lib/l10n/app_*.arb` file (af, ar, ca, cs, da, de, el, en, es, fi, fr, he, hu, it, ja, ko, nl, no, pl, pt, … list via `Get-ChildItem lib/l10n/app_*.arb`), add the same key. For locales whose translations need polish later, use the best-effort English/zh fallback (Crowdin re-imports will fix). Suggested seed values (override with glossary entries if present):

| locale | value |
|---|---|
| en | `Card` |
| ja | `カード` |
| ko | `카드` |
| zh-cn (if file exists) | `卡片` |
| zh-hk (if file exists) | `卡片` |
| pt | `Cartão` |
| es | `Carta` |
| fr | `Carte` |
| de | `Karte` |
| it | `Carta` |
| ru | `Карта` |
| others | `Card` (Crowdin auto-fills) |

Each `app_*.arb` only needs the value entry (no `@galleryCardLabel` metadata — that lives in `app_zh.arb`).

- [ ] **Step 4: Regenerate l10n bindings**

Run:
```powershell
flutter gen-l10n
```
Expected: no errors. New `l.galleryCardLabel` accessor appears in `lib/l10n/generated/app_localizations.dart`.

- [ ] **Step 5: Verify analyze stays clean**

Run:
```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```powershell
git add lib/l10n/
git commit -m "feat(i18n): add galleryCardLabel for hoyowiki gallery pic chip"
```

---

## Task 5: Refactor `HoYoWikiEntry`, storage v2 + v1 migration, remove old helpers

**Files:**
- Modify: `lib/services/hoyowiki_index.dart` (HoYoWikiEntry struct, save/load, remove enum + old helper)
- Modify: `lib/services/hoyowiki_fetcher.dart` (compile-fix: stub `HoYoWikiEntryFetched` to keep building; full refactor in Task 6)
- Modify: `lib/state/gacha_repository.dart` (compile-fix only — update `enqueueDownloadsForEntry` to skip header path)
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart` (compile-fix only — remove header rendering; full rewrite in Task 10)
- Modify: `test/services/hoyowiki_index_test.dart` (storage round-trip + v1 migration tests; update existing `HoYoWikiEntry` constructors)
- Modify: `test/state/hoyowiki_index_test.dart` (update existing `HoYoWikiEntry` constructors)
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` (update existing `HoYoWikiEntry` constructors)
- Modify: `test/state/gacha_repository_hoyowiki_test.dart` and related (update `HoYoWikiEntry` constructors; stub mock responses)

This is the biggest task. The strategy: refactor the type, then propagate through all callers with minimal patches (no behavior changes outside types). Behavior changes land in Tasks 6–10.

- [ ] **Step 1: Write failing storage v2 round-trip + v1 migration tests**

Append to `test/services/hoyowiki_index_test.dart`:

```dart
  group('HoYoWikiIndexStorage v2', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_storage_v2_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('save+load round trip：含 galleryByLang', () async {
      final storage = HoYoWikiIndexStorage(tempDir);
      final entry = HoYoWikiEntry(
        iconUrl: 'https://x/icon.png',
        galleryByLang: const {
          'zh-tw': HoYoWikiGalleryData(
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'gallery_character8511',
                key: '原畫',
                imgUrl: 'https://x/orig.png',
                imgDescHtml: '<p>衣裝</p>',
              ),
            ],
          ),
        },
        fetchedAt: DateTime.utc(2026, 5, 26),
      );
      await storage.save(HoYoWikiIndex(
        searchMap: const {'zh-tw::布倫妮': '12345'},
        entries: {'12345': entry},
        menuIds: const {'12345': 2},
      ));

      final loaded = await storage.load();
      final got = loaded.lookupEntry('12345')!;
      expect(got.iconUrl, 'https://x/icon.png');
      expect(got.galleryByLang.keys.toList(), ['zh-tw']);
      expect(got.galleryByLang['zh-tw']!.picUrl, 'https://x/card.png');
      expect(got.galleryByLang['zh-tw']!.list.single.key, '原畫');
      expect(got.galleryByLang['zh-tw']!.list.single.imgDescHtml, '<p>衣裝</p>');
    });

    test('v1 載入：丟棄 header_img_url，galleryByLang 為空', () async {
      // 手寫 v1 JSON 模擬舊版資料
      final file = File('${tempDir.path}/hoyowiki_index.json');
      await file.writeAsString(jsonEncode({
        'version': 1,
        'search': {'zh-tw::布倫妮': '12345'},
        'menu_ids': {'12345': 2},
        'entries': {
          '12345': {
            'icon_url': 'https://x/icon.png',
            'header_img_url': 'https://x/header.png',  // v1-only field
            'fetched_at': '2026-05-20T00:00:00.000Z',
          },
        },
      }));

      final loaded = await HoYoWikiIndexStorage(tempDir).load();
      final got = loaded.lookupEntry('12345')!;
      expect(got.iconUrl, 'https://x/icon.png');
      expect(got.galleryByLang, isEmpty);
      // search 與 menuIds 必須保留
      expect(loaded.lookupId(name: '布倫妮', lang: 'zh-tw'), '12345');
      expect(loaded.lookupMenuId('12345'), 2);
    });

    test('檔案不存在 → 回空 index', () async {
      final loaded = await HoYoWikiIndexStorage(tempDir).load();
      expect(loaded.entries, isEmpty);
      expect(loaded.searchMap, isEmpty);
    });
  });
```

Add `import 'dart:convert';` near top of the test file if not already there.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```powershell
flutter test test/services/hoyowiki_index_test.dart
```
Expected: compile error (`HoYoWikiEntry` constructor still requires `headerImgUrl` named param, no `galleryByLang`).

- [ ] **Step 3: Refactor `HoYoWikiEntry`**

In `lib/services/hoyowiki_index.dart`, replace the `HoYoWikiEntry` class (currently lines ~7–24) with:

```dart
/// HoYoWiki entry_page API 抓到的 icon URL 與各語言 gallery 整組資料。
class HoYoWikiEntry {
  /// 建立 [HoYoWikiEntry]；`iconUrl` 可能為空字串。
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.galleryByLang,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。lang-agnostic。
  final String iconUrl;

  /// 各語言抓到的整組 gallery；key 為 record.lang（zh-tw / en / ja / ...）。
  /// 某 lang 不在 map = 該 lang 還沒抓過（或抓過但 entry 無 gallery_character）。
  final Map<String, HoYoWikiGalleryData> galleryByLang;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}
```

- [ ] **Step 4: Rewrite storage `save()` to v2 schema**

In `lib/services/hoyowiki_index.dart`, replace the body of `save()` (currently lines ~111–135) with:

```dart
  Future<void> save(HoYoWikiIndex index) async {
    final json = {
      'version': 2,
      'search': index.searchMap,
      'entries': index.entries.map(
        (k, v) => MapEntry(k, {
          'icon_url': v.iconUrl,
          'fetched_at': v.fetchedAt.toUtc().toIso8601String(),
          'gallery_by_lang': v.galleryByLang.map(
            (lang, g) => MapEntry(lang, {
              'pic_url': g.picUrl,
              'list': g.list
                  .map((it) => {
                        'id': it.id,
                        'key': it.key,
                        'img_url': it.imgUrl,
                        'img_desc_html': it.imgDescHtml,
                      })
                  .toList(),
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

- [ ] **Step 5: Rewrite storage `load()` to handle v2 + v1 migration**

In `lib/services/hoyowiki_index.dart`, replace the body of `load()` (currently lines ~77–108) with:

```dart
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

      var droppedV1 = 0;
      final entries = entriesJson.map((k, v) {
        final m = v as Map<String, dynamic>;
        final iconUrl = (m['icon_url'] as String?) ?? '';
        final fetchedAt = DateTime.parse(m['fetched_at'] as String);
        Map<String, HoYoWikiGalleryData> galleryByLang;
        if (version >= 2 && m['gallery_by_lang'] is Map) {
          final gJson = m['gallery_by_lang'] as Map<String, dynamic>;
          galleryByLang = gJson.map((lang, raw) {
            final gm = raw as Map<String, dynamic>;
            final listJson = (gm['list'] as List<dynamic>?) ?? const [];
            return MapEntry(
              lang,
              HoYoWikiGalleryData(
                picUrl: (gm['pic_url'] as String?) ?? '',
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
              ),
            );
          });
        } else {
          // v1 or missing: drop header_img_url, gallery starts empty -> will refetch
          galleryByLang = const {};
          droppedV1++;
        }
        return MapEntry(
          k,
          HoYoWikiEntry(
            iconUrl: iconUrl,
            galleryByLang: galleryByLang,
            fetchedAt: fetchedAt,
          ),
        );
      });

      if (droppedV1 > 0) {
        _log.info(
          'migrate v1 → v2: $droppedV1 entries reset (header_img_url dropped)',
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

- [ ] **Step 6: Remove `HoYoWikiImageKind` enum and old `hoyowikiCacheFile`**

In `lib/services/hoyowiki_index.dart`, delete the entire `HoYoWikiImageKind` enum block (around lines 158–165) and the entire `hoyowikiCacheFile` function (around lines 171–179). Keep `_extFromUrl` (still used by new helpers).

- [ ] **Step 7: Compile-fix `lib/services/hoyowiki_fetcher.dart`**

Replace the `HoYoWikiEntryFetched` class (currently around lines 23–36) with a transitional version that compiles but still uses old field names — full refactor in Task 6:

```dart
/// HoYoWiki entry_page API 抓到的 icon URL（過渡：gallery 在 Task 6 加入）。
class HoYoWikiEntryFetched {
  /// 建立 [HoYoWikiEntryFetched]；icon 可能為空字串。
  const HoYoWikiEntryFetched({required this.iconUrl});

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。
  final String iconUrl;
}
```

Then in `fetchEntryPage` (around lines 132–152), simplify the return to:

```dart
    final iconUrl = (page?['icon_url'] as String?) ?? '';
    _log.info('entry id=$id icon=${iconUrl.isNotEmpty}');
    return HoYoWikiEntryFetched(iconUrl: iconUrl);
```

(Drop the `headerImgUrl` extraction line.)

- [ ] **Step 8: Compile-fix `lib/state/gacha_repository.dart`**

Locate `enqueueDownloadsForEntry` (around lines 825–840). Replace its body with:

```dart
    void enqueueDownloadsForEntry(String id, HoYoWikiEntry entry) {
      final url = entry.iconUrl;
      if (url.isEmpty) return;
      final file = hoyowikiIconCacheFile(baseDir: cacheDir, id: id, url: url);
      if (file.existsSync()) return;
      downloadTodo.add(_HoYoWikiDownloadItem(id: id, url: url));
    }
```

Find `_HoYoWikiDownloadItem` class (around lines 1010+) and change it to:

```dart
/// HoYoWiki 下載佇列的單一工作項（過渡：gallery 在 Task 9 加入）。
class _HoYoWikiDownloadItem {
  /// 建立 [_HoYoWikiDownloadItem]。
  const _HoYoWikiDownloadItem({required this.id, required this.url});

  /// HoYoWiki entry_page_id。
  final String id;

  /// 圖片 URL。
  final String url;
}
```

Then in the download worker (around lines 941–971), update the file-resolution line. Replace:
```dart
              final file = hoyowikiCacheFile(
                baseDir: cacheDir,
                id: item.id,
                kind: item.kind,
                url: item.url,
              );
```
with:
```dart
              final file = hoyowikiIconCacheFile(
                baseDir: cacheDir,
                id: item.id,
                url: item.url,
              );
```

Also in entry worker (around lines 908–933) the call site updates:

Replace:
```dart
            final entry = HoYoWikiEntry(
              iconUrl: fetched.iconUrl,
              headerImgUrl: fetched.headerImgUrl,
              fetchedAt: DateTime.now().toUtc(),
            );
```
with:
```dart
            final entry = HoYoWikiEntry(
              iconUrl: fetched.iconUrl,
              galleryByLang: const {},
              fetchedAt: DateTime.now().toUtc(),
            );
```

- [ ] **Step 9: Compile-fix `lib/widgets/dialogs/gacha_item_detail_dialog.dart`**

In `hasHoYoWikiContent` (around lines 19–39), replace the `fileReady` closure block to only check icon:

```dart
bool hasHoYoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);
  return entry.iconUrl.isNotEmpty &&
      hoyowikiIconCacheFile(baseDir: cacheDir, id: id, url: entry.iconUrl)
          .existsSync();
}
```

In `build()`, replace the icon resolution block (around lines 62–82) with:

```dart
    File? iconFile;
    if (id != null && entry != null && entry.iconUrl.isNotEmpty) {
      final f = hoyowikiIconCacheFile(
        baseDir: cacheDir,
        id: id,
        url: entry.iconUrl,
      );
      if (f.existsSync()) iconFile = f;
    }
```

Delete the entire `headerFile` block. Then remove the `Flexible` block for header in `content:` (around lines 130–147). Leave content as:

```dart
      content: const SizedBox.shrink(),  // 過渡：gallery UI 在 Task 10 加入
```

This dialog is functionally degraded during the transition — full UI lands in Task 10.

- [ ] **Step 10: Update all `HoYoWikiEntry(...)` constructor calls in tests**

Search for `HoYoWikiEntry(` across `test/` and update every call site:
- Remove `headerImgUrl: ...` arg.
- Add `galleryByLang: const {}` if not present.

Specifically grep first:
```powershell
Select-String -Path test\**\*.dart -Pattern 'HoYoWikiEntry\('
```

Update each match. Files affected: at minimum `test/services/hoyowiki_index_test.dart`, `test/state/hoyowiki_index_test.dart`, `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`, and any repository tests.

For test helpers in `test/state/gacha_repository_hoyowiki_test.dart` or similar that mock entry-page HTTP responses (e.g., `_entryOk` helper in `test/services/hoyowiki_fetcher_test.dart` at line 36): drop the `header_img_url` field from the JSON body, leaving only `icon_url`:

```dart
http.Response _entryOk({required String iconUrl}) =>
    http.Response(
      jsonEncode({
        'retcode': 0,
        'message': 'OK',
        'data': {
          'page': {'icon_url': iconUrl},
        },
      }),
      200,
    );
```

Update all `_entryOk(...)` call sites to drop `headerUrl: ...` arg.

- [ ] **Step 11: Update existing fetcher tests that assert on `headerImgUrl`**

Grep:
```powershell
Select-String -Path test\services\hoyowiki_fetcher_test.dart -Pattern 'headerImgUrl|headerUrl'
```

Remove any `expect(result.headerImgUrl, ...)` line and `headerUrl: ...` named args. Any test that's solely about header behavior — delete it.

- [ ] **Step 12: Run all tests to verify pass**

Run:
```powershell
flutter test
```
Expected: `All tests passed!`. New v2 round-trip and v1 migration tests pass; old tests still pass after constructor updates.

- [ ] **Step 13: Run analyze**

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 14: Commit**

```powershell
git add lib/ test/
git commit -m "refactor(hoyowiki): switch HoYoWikiEntry to galleryByLang + storage v2"
```

---

## Task 6: Implement `_parseGalleryCharacterModule` + `fetchEntryPage` lang param

**Files:**
- Modify: `lib/services/hoyowiki_fetcher.dart`
- Modify: `lib/state/gacha_repository.dart` (caller site — add `lang:` arg)
- Modify: `test/services/hoyowiki_fetcher_test.dart`

- [ ] **Step 1: Write failing fetcher tests**

Append to `test/services/hoyowiki_fetcher_test.dart` inside `void main() { ... }`:

```dart
  group('HoYoWikiFetcher.fetchEntryPage gallery', () {
    http.Response entryWithGallery({
      required String iconUrl,
      required String galleryDataJson,
    }) => http.Response(
      jsonEncode({
        'retcode': 0,
        'message': 'OK',
        'data': {
          'page': {
            'icon_url': iconUrl,
            'modules': [
              {
                'components': [
                  {'component_id': 'something_else', 'data': '{}'},
                  {'component_id': 'gallery_character', 'data': galleryDataJson},
                ],
              },
            ],
          },
        },
      }),
      200,
    );

    test('帶 X-Rpc-Language header', () async {
      String? capturedLang;
      final mock = MockClient((req) async {
        capturedLang = req.headers['X-Rpc-Language'];
        return entryWithGallery(
          iconUrl: 'https://x/icon.png',
          galleryDataJson: '{"pic":"https://x/card.png","list":[]}',
        );
      });
      await HoYoWikiFetcher().fetchEntryPage(
        id: '12345',
        lang: 'zh-tw',
        client: mock,
      );
      expect(capturedLang, 'zh-tw');
    });

    test('正常解析 gallery_character', () async {
      final mock = MockClient((req) async => entryWithGallery(
        iconUrl: 'https://x/icon.png',
        galleryDataJson: jsonEncode({
          'pic': 'https://x/card.png',
          'list': [
            {
              'id': 'gallery_character8511',
              'key': '原畫',
              'img': 'https://x/orig.png',
              'imgDesc': '<p>衣裝「魔女獵裝」</p>',
            },
            {
              'id': 'gallery_character99418',
              'key': '閒置動作１',
              'img': 'https://x/idle.gif',
              'imgDesc': '',
            },
          ],
        }),
      ));
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345', lang: 'zh-tw', client: mock,
      );
      expect(res.iconUrl, 'https://x/icon.png');
      expect(res.gallery, isNotNull);
      expect(res.gallery!.picUrl, 'https://x/card.png');
      expect(res.gallery!.list, hasLength(2));
      expect(res.gallery!.list[0].key, '原畫');
      expect(res.gallery!.list[1].imgUrl, 'https://x/idle.gif');
      expect(res.gallery!.list[1].imgDescHtml, '');
    });

    test('無 gallery_character module → gallery 為 null', () async {
      final mock = MockClient((req) async => http.Response(
        jsonEncode({
          'retcode': 0,
          'message': 'OK',
          'data': {
            'page': {'icon_url': 'https://x/icon.png', 'modules': []},
          },
        }),
        200,
      ));
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345', lang: 'zh-tw', client: mock,
      );
      expect(res.gallery, isNull);
    });

    test('data 非合法 JSON → gallery 為 null（不 throw）', () async {
      final mock = MockClient((req) async => entryWithGallery(
        iconUrl: 'https://x/icon.png',
        galleryDataJson: '{not json',
      ));
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345', lang: 'zh-tw', client: mock,
      );
      expect(res.gallery, isNull);
    });

    test('list[i] 缺 img 整筆 skip，其餘照存', () async {
      final mock = MockClient((req) async => entryWithGallery(
        iconUrl: 'https://x/icon.png',
        galleryDataJson: jsonEncode({
          'pic': 'https://x/card.png',
          'list': [
            {'id': 'a', 'key': 'A', 'img': 'https://x/a.png', 'imgDesc': ''},
            {'id': 'b', 'key': 'B', 'img': '', 'imgDesc': ''},
            {'id': 'c', 'key': 'C', 'img': 'https://x/c.png', 'imgDesc': ''},
          ],
        }),
      ));
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345', lang: 'zh-tw', client: mock,
      );
      expect(res.gallery!.list.map((it) => it.id).toList(), ['a', 'c']);
    });

    test('pic 與 list 皆空 → gallery 為 null', () async {
      final mock = MockClient((req) async => entryWithGallery(
        iconUrl: 'https://x/icon.png',
        galleryDataJson: jsonEncode({'pic': '', 'list': []}),
      ));
      final res = await HoYoWikiFetcher().fetchEntryPage(
        id: '12345', lang: 'zh-tw', client: mock,
      );
      expect(res.gallery, isNull);
    });
  });
```

Add `import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';` to that test file if not already present (needed for the gallery types).

- [ ] **Step 2: Run tests to verify they fail**

Run:
```powershell
flutter test test/services/hoyowiki_fetcher_test.dart
```
Expected: compile errors (`fetchEntryPage` doesn't take `lang`; `gallery` field doesn't exist).

- [ ] **Step 3: Update `HoYoWikiEntryFetched` to include gallery**

In `lib/services/hoyowiki_fetcher.dart`, replace the transitional `HoYoWikiEntryFetched` from Task 5 with the final form:

```dart
/// HoYoWiki entry_page API 抓到的 icon URL 與（可能）gallery 整組資料。
class HoYoWikiEntryFetched {
  /// 建立 [HoYoWikiEntryFetched]；icon 可能為空字串；gallery 可能為 null（無
  /// `gallery_character` module 或 data 解析失敗）。
  const HoYoWikiEntryFetched({required this.iconUrl, required this.gallery});

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 該 lang 的 gallery 整組（pic + list）；無資料時為 null。
  final HoYoWikiGalleryData? gallery;
}
```

Add at top of file:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
```
(If already imported, skip.)

- [ ] **Step 4: Add `_parseGalleryCharacterModule` helper**

In `lib/services/hoyowiki_fetcher.dart`, inside the `HoYoWikiFetcher` class (above `downloadImage`), add:

```dart
  /// 從 entry_page response 的 `modules[]` 找出 `gallery_character`
  /// component 並 JSON 解析其 `data` 字串。失敗或空回 null。
  static HoYoWikiGalleryData? _parseGalleryCharacterModule(
    List<dynamic> modules,
  ) {
    for (final m in modules) {
      final components =
          (m as Map<String, dynamic>)['components'] as List<dynamic>?;
      if (components == null) continue;
      for (final c in components) {
        final comp = c as Map<String, dynamic>;
        if (comp['component_id'] != 'gallery_character') continue;
        final dataStr = comp['data'] as String?;
        if (dataStr == null || dataStr.isEmpty) return null;
        try {
          final data = jsonDecode(dataStr) as Map<String, dynamic>;
          final picUrl = (data['pic'] as String?) ?? '';
          final listJson = (data['list'] as List<dynamic>?) ?? const [];
          final list = <HoYoWikiGalleryItem>[];
          for (final item in listJson) {
            final mi = item as Map<String, dynamic>;
            final gid = mi['id'] as String?;
            final key = mi['key'] as String?;
            final img = mi['img'] as String?;
            if (gid == null || gid.isEmpty ||
                key == null || key.isEmpty ||
                img == null || img.isEmpty) {
              _log.warning(
                'gallery item missing fields id=$gid key=$key imgEmpty=${img == null || img.isEmpty}',
              );
              continue;
            }
            list.add(HoYoWikiGalleryItem(
              id: gid,
              key: key,
              imgUrl: img,
              imgDescHtml: (mi['imgDesc'] as String?) ?? '',
            ));
          }
          if (picUrl.isEmpty && list.isEmpty) return null;
          return HoYoWikiGalleryData(picUrl: picUrl, list: list);
        } catch (e, st) {
          _log.warning('gallery data parse failed', e, st);
          return null;
        }
      }
    }
    return null;
  }
```

- [ ] **Step 5: Refactor `fetchEntryPage` to take lang and parse gallery**

In `lib/services/hoyowiki_fetcher.dart`, replace the entire `fetchEntryPage` method (currently lines ~130–152, including transitional version from Task 5) with:

```dart
  /// 以 [id] 與 [lang] 拉 entry_page，回 icon_url 與該 lang 的 gallery 整組。
  /// 必送 `X-Rpc-Language: $lang` header 以拿到對應語言的 gallery 文字。
  /// retcode != 0 throw [ApiErrorException]。
  Future<HoYoWikiEntryFetched> fetchEntryPage({
    required String id,
    required String lang,
    required http.Client client,
  }) async {
    final url = _entryBase.replace(queryParameters: {'entry_page_id': id});
    _log.fine(
      'entry id=$id lang=$lang url=${sanitizeUrl(url.toString())}',
    );
    final res = await client.get(
      url,
      headers: {'X-Rpc-Language': lang},
    ).timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode != 0) {
      _log.warning(
        'entry retcode=$retcode id=$id lang=$lang msg=${body['message']}',
      );
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
    final page = body['data']?['page'] as Map<String, dynamic>?;
    final iconUrl = (page?['icon_url'] as String?) ?? '';
    final modules = (page?['modules'] as List<dynamic>?) ?? const [];
    final gallery = _parseGalleryCharacterModule(modules);
    _log.info(
      'entry id=$id lang=$lang icon=${iconUrl.isNotEmpty} '
      'gallery=${gallery != null} '
      'pic=${gallery?.picUrl.isNotEmpty == true} '
      'list=${gallery?.list.length ?? 0}',
    );
    return HoYoWikiEntryFetched(iconUrl: iconUrl, gallery: gallery);
  }
```

- [ ] **Step 6: Update the caller in `lib/state/gacha_repository.dart`**

In the entry worker (around lines 908–933), replace the `fetcher.fetchEntryPage(...)` call. Note this still uses the old `entryTodo: Set<String>` from Task 5 — that becomes per-lang in Task 8. For now pass a placeholder `lang: 'en-us'` to keep compile, but mark with TODO for Task 8:

```dart
            // TODO(Task 8): lang from per-lang entryTodo pair
            final fetched = await fetcher.fetchEntryPage(
              id: id,
              lang: 'en-us',
              client: client,
            );
```

This is intentional intermediate state — Task 8 wires the real lang.

- [ ] **Step 7: Run tests to verify pass**

Run:
```powershell
flutter test test/services/hoyowiki_fetcher_test.dart
```
Expected: All new and existing tests pass.

- [ ] **Step 8: Run full test suite + analyze**

Run:
```powershell
flutter analyze
flutter test
```
Expected: `No issues found!` and `All tests passed!`.

- [ ] **Step 9: Commit**

```powershell
git add lib/services/hoyowiki_fetcher.dart lib/state/gacha_repository.dart test/services/hoyowiki_fetcher_test.dart
git commit -m "feat(hoyowiki): parse gallery_character module and send lang header"
```

---

## Task 7: Replace `setEntry` with `mergeEntry` (per-lang merge + icon non-empty overwrite)

**Files:**
- Modify: `lib/state/hoyowiki_index.dart`
- Modify: `lib/state/gacha_repository.dart` (caller)
- Modify: `test/state/hoyowiki_index_test.dart`

- [ ] **Step 1: Write failing `mergeEntry` tests**

Append to `test/state/hoyowiki_index_test.dart` inside `void main() { ... }`:

```dart
  group('HoYoWikiIndexNotifier.mergeEntry', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mergeEntry_test_');
      container = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        ],
      );
      addTearDown(container.dispose);
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('首次寫入：lang gallery 寫進去', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          gallery: HoYoWikiGalleryData(
            picUrl: 'https://x/card.png',
            list: [
              HoYoWikiGalleryItem(
                id: 'a', key: '原畫', imgUrl: 'https://x/a.png', imgDescHtml: '',
              ),
            ],
          ),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.galleryByLang['zh-tw']!.list.single.key, '原畫');
    });

    test('第二次寫入不同 lang：既有 lang 保留', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          gallery: HoYoWikiGalleryData(picUrl: 'https://x/zh.png', list: []),
        ),
      );
      await notifier.mergeEntry(
        id: '12345',
        lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          gallery: HoYoWikiGalleryData(picUrl: 'https://x/en.png', list: []),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.galleryByLang.keys.toSet(), {'zh-tw', 'en-us'});
      expect(entry.galleryByLang['zh-tw']!.picUrl, 'https://x/zh.png');
      expect(entry.galleryByLang['en-us']!.picUrl, 'https://x/en.png');
    });

    test('icon 非空覆寫：空 icon 不會把既有好值清掉', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          gallery: HoYoWikiGalleryData(picUrl: 'https://x/zh.png', list: []),
        ),
      );
      await notifier.mergeEntry(
        id: '12345',
        lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: '',  // 模擬某 lang 空 icon
          gallery: HoYoWikiGalleryData(picUrl: 'https://x/en.png', list: []),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');  // 保留既有
    });

    test('gallery 為 null：不寫入該 lang，icon 仍可更新', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          gallery: null,
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.galleryByLang, isEmpty);
    });
  });
```

Add necessary imports at top:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```powershell
flutter test test/state/hoyowiki_index_test.dart
```
Expected: compile error (`mergeEntry` not defined).

- [ ] **Step 3: Replace `setEntry` with `mergeEntry`**

In `lib/state/hoyowiki_index.dart`, replace the `setEntry` method (lines 89–104) with:

```dart
  /// 把單一 lang 的 fetch 結果 merge 進既有 entry（不覆蓋其他 lang）。icon 採
  /// 「非空覆寫」策略，避免某 lang 抓回空 icon 把既有好值清掉。
  Future<void> mergeEntry({
    required String id,
    required String lang,
    required HoYoWikiEntryFetched fetched,
  }) async {
    await _lock.synchronized(() async {
      final existing = state.entries[id];
      final mergedGallery = <String, HoYoWikiGalleryData>{
        if (existing != null) ...existing.galleryByLang,
        if (fetched.gallery != null) lang: fetched.gallery!,
      };
      final iconUrl = fetched.iconUrl.isNotEmpty
          ? fetched.iconUrl
          : (existing?.iconUrl ?? '');
      final merged = HoYoWikiEntry(
        iconUrl: iconUrl,
        galleryByLang: mergedGallery,
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
        'merge gallery id=$id lang=$lang has=${fetched.gallery != null}',
      );
    });
  }
```

Add this import at top of `lib/state/hoyowiki_index.dart` if missing:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
```

- [ ] **Step 4: Update the caller in `lib/state/gacha_repository.dart`**

In the entry worker (around lines 908–933), replace:

```dart
            await indexNotifier.setEntry(id: id, entry: entry);
```

with:

```dart
            await indexNotifier.mergeEntry(
              id: id,
              lang: 'en-us',  // TODO(Task 8): from per-lang pair
              fetched: fetched,
            );
```

Remove the now-unused local `entry` construction (delete the `final entry = HoYoWikiEntry(...)` block since mergeEntry takes the fetched directly).

- [ ] **Step 5: Run tests to verify pass**

```powershell
flutter test test/state/hoyowiki_index_test.dart
flutter test
```
Expected: all pass.

- [ ] **Step 6: Run analyze**

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```powershell
git add lib/state/hoyowiki_index.dart lib/state/gacha_repository.dart test/state/hoyowiki_index_test.dart
git commit -m "feat(hoyowiki): mergeEntry per-lang with non-empty icon overwrite"
```

---

## Task 8: per-lang `entryTodo` + `needRefetchEntry` per-lang in repository

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Modify: `test/state/gacha_repository_hoyowiki_test.dart`

- [ ] **Step 1: Write failing per-lang test**

In `test/state/gacha_repository_hoyowiki_test.dart`, add a new group that verifies the same id under two different langs both get fetched:

```dart
  group('hoyowiki per-lang entry fetch', () {
    test('同 id 兩 lang 都會發 entry_page 請求', () async {
      final entryReqs = <String>[];  // (id, lang) tuples
      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(jsonEncode({
            'retcode': 0,
            'message': 'OK',
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '12345',
                  'menu': {
                    'sub_menus': [{'id': 2, 'name': 'Character'}],
                  },
                },
              ],
            },
          }), 200);
        }
        if (url.contains('/wapi/entry_page')) {
          final lang = req.headers['X-Rpc-Language'] ?? '';
          final id = Uri.parse(url).queryParameters['entry_page_id'] ?? '';
          entryReqs.add('$id::$lang');
          return http.Response(jsonEncode({
            'retcode': 0,
            'message': 'OK',
            'data': {
              'page': {
                'icon_url': 'https://x/icon.png',
                'modules': [
                  {
                    'components': [
                      {
                        'component_id': 'gallery_character',
                        'data': jsonEncode({
                          'pic': 'https://x/p.png',
                          'list': [
                            {
                              'id': 'a', 'key': 'k-$lang',
                              'img': 'https://x/a.png', 'imgDesc': '',
                            },
                          ],
                        }),
                      },
                    ],
                  },
                ],
              },
            },
          }), 200);
        }
        return http.Response('not mocked', 404);
      });

      // Setup: storage with 2 records same name, different lang
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_perlang_');
      SharedPreferences.setMockInitialValues({});
      final storage = GachaStorage(tempDir);
      await storage.save(BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 26),
        banners: {
          '301': [
            _rec(id: '1', name: 'Hu Tao', gachaType: '301', lang: 'zh-tw'),
            _rec(id: '2', name: 'Hu Tao', gachaType: '301', lang: 'en-us'),
          ],
          '302': [], '500': [], '200': [], '100': [],
          '2000': [], '1000': [],
        },
      ));
      final container = ProviderContainer(overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ]);
      addTearDown(container.dispose);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

      await container.read(gachaRepositoryProvider.notifier).debugRunHoYoWikiOnly();

      expect(entryReqs.toSet(), {'12345::zh-tw', '12345::en-us'});

      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.galleryByLang.keys.toSet(), {'zh-tw', 'en-us'});
      expect(entry.galleryByLang['zh-tw']!.list.single.key, 'k-zh-tw');
      expect(entry.galleryByLang['en-us']!.list.single.key, 'k-en-us');
    });
  });
```

(Adjust if existing setUp/_rec/`tempDir` patterns differ — read the existing test file for naming conventions before pasting.)

- [ ] **Step 2: Run test to verify fail**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart
```
Expected: fails because current entry worker only fetches each id once (hardcoded `lang: 'en-us'`).

- [ ] **Step 3: Change `entryTodo` to per-lang Set in repository**

In `lib/state/gacha_repository.dart`, locate `_fetchHoYoWiki` (around line 800+). Find where `entryTodo` is built. Replace the existing block (current logic builds `Set<String>` of ids):

```dart
    final entryTodo = <({String id, String lang})>{};
    // 走過所有 record lang+name，蒐集需要重抓的 (id, lang) pair
    for (final lang in allLangs) {
      for (final name in namesByLang[lang] ?? const <String>{}) {
        final id = index.lookupId(name: name, lang: lang);
        if (id == null) continue;
        if (needRefetchEntry(
          index.lookupEntry(id), index.lookupMenuId(id), lang,
        )) {
          entryTodo.add((id: id, lang: lang));
        }
      }
    }
```

The exact data sources for `allLangs` and `namesByLang` depend on what's already in the function — read it (around lines 770–820) and adapt. The key behavior change: enqueue per (id, lang) instead of per id.

- [ ] **Step 4: Update `needRefetchEntry` to take lang**

Find `needRefetchEntry(...)` (defined or used near line 815). Update its signature and body to:

```dart
    bool needRefetchEntry(HoYoWikiEntry? entry, int? menuId, String lang) {
      if (entry == null) return true;
      if (menuId == null) return true;
      if (!entry.galleryByLang.containsKey(lang)) return true;
      return false;
    }
```

If `needRefetchEntry` is a free function elsewhere, update its signature consistently and all call sites.

- [ ] **Step 5: Update entry worker to use pair lang**

In the entry worker (around lines 901–935), replace the TODO from Task 6/7 with real lang from the pair:

```dart
    if (entryTodo.isNotEmpty) {
      final entryList = entryTodo.toList();
      var doneEntry = 0;
      await runConcurrent<({String id, String lang})>(
        items: entryList,
        concurrency: fetcher.entryConcurrency,
        shouldAbort: isAborted,
        worker: (pair) async {
          try {
            final fetched = await fetcher.fetchEntryPage(
              id: pair.id, lang: pair.lang, client: client,
            );
            await indexNotifier.mergeEntry(
              id: pair.id, lang: pair.lang, fetched: fetched,
            );
            // download enqueue 拉到 Task 9，先用既有 icon-only 邏輯
            final entry = ref.read(hoyowikiIndexProvider).lookupEntry(pair.id);
            if (entry != null) enqueueDownloadsForEntry(pair.id, entry);
          } catch (e) {
            _log.warning(
              'hoyowiki entry failed id=${pair.id} lang=${pair.lang} err=$e',
            );
          }
          if (!ref.mounted) return;
          doneEntry++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.fetchingEntries,
              doneCount: doneEntry,
              totalCount: entryList.length,
            ),
          );
        },
      );
      if (isAborted()) return downloaded;
    }
```

- [ ] **Step 6: Run tests to verify pass**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart
flutter test
```
Expected: all pass.

- [ ] **Step 7: Run analyze**

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```powershell
git add lib/state/gacha_repository.dart test/state/gacha_repository_hoyowiki_test.dart
git commit -m "feat(hoyowiki): per-lang entryTodo with needRefetchEntry per-lang"
```

---

## Task 9: Download stage URL dedupe + icon/gallery split

**Files:**
- Modify: `lib/state/gacha_repository.dart`
- Modify: `test/state/gacha_repository_hoyowiki_test.dart`

- [ ] **Step 1: Write failing tests for gallery download + dedupe**

Append to `test/state/gacha_repository_hoyowiki_test.dart`:

```dart
  group('hoyowiki gallery download', () {
    test('gallery 圖檔下載到 <id>_gallery_<hash>.<ext>', () async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_dl_');
      SharedPreferences.setMockInitialValues({});

      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(jsonEncode({
            'retcode': 0, 'message': 'OK',
            'data': {'list': [{
              'name': 'Hu Tao', 'entry_page_id': '12345',
              'menu': {'sub_menus': [{'id': 2, 'name': 'c'}]},
            }]},
          }), 200);
        }
        if (url.contains('/wapi/entry_page')) {
          return http.Response(jsonEncode({
            'retcode': 0, 'message': 'OK',
            'data': {'page': {
              'icon_url': 'https://x/icon.png',
              'modules': [{'components': [{
                'component_id': 'gallery_character',
                'data': jsonEncode({
                  'pic': 'https://x/card.png',
                  'list': [{
                    'id': 'a', 'key': 'k',
                    'img': 'https://x/a.gif', 'imgDesc': '',
                  }],
                }),
              }]}],
            }},
          }), 200);
        }
        // 圖檔請求：回 4 bytes（PNG magic 樣式）
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47], 200,
          headers: {'content-type': 'image/png'},
        );
      });

      final storage = GachaStorage(tempDir);
      await storage.save(BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 26),
        banners: {
          '301': [_rec(id: '1', name: 'Hu Tao', gachaType: '301')],
          '302': [], '500': [], '200': [], '100': [], '2000': [], '1000': [],
        },
      ));
      final container = ProviderContainer(overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ]);
      addTearDown(container.dispose);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

      await container.read(gachaRepositoryProvider.notifier).debugRunHoYoWikiOnly();

      // icon + pic + 1 gallery item → 3 個檔
      final files = Directory(tempDir.path)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files.any((f) => f == '12345_icon.png'), isTrue);
      expect(files.any((f) => RegExp(r'^12345_gallery_[0-9a-f]{12}\.gif$').hasMatch(f)), isTrue);
      expect(files.any((f) => RegExp(r'^12345_gallery_[0-9a-f]{12}\.png$').hasMatch(f)), isTrue);
    });

    test('跨 lang 同 URL 只下載一次', () async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_dedupe_');
      SharedPreferences.setMockInitialValues({});

      var imageDownloadCount = 0;
      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(jsonEncode({
            'retcode': 0, 'message': 'OK',
            'data': {'list': [{
              'name': 'Hu Tao', 'entry_page_id': '12345',
              'menu': {'sub_menus': [{'id': 2, 'name': 'c'}]},
            }]},
          }), 200);
        }
        if (url.contains('/wapi/entry_page')) {
          // 兩個 lang 都回完全相同的圖 URL → 應該共用一份檔
          return http.Response(jsonEncode({
            'retcode': 0, 'message': 'OK',
            'data': {'page': {
              'icon_url': 'https://x/icon.png',
              'modules': [{'components': [{
                'component_id': 'gallery_character',
                'data': jsonEncode({
                  'pic': 'https://x/shared.png',
                  'list': [],
                }),
              }]}],
            }},
          }), 200);
        }
        // 圖檔下載：計次
        imageDownloadCount++;
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47], 200,
          headers: {'content-type': 'image/png'},
        );
      });

      final storage = GachaStorage(tempDir);
      await storage.save(BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 26),
        banners: {
          '301': [
            _rec(id: '1', name: 'Hu Tao', gachaType: '301', lang: 'zh-tw'),
            _rec(id: '2', name: 'Hu Tao', gachaType: '301', lang: 'en-us'),
          ],
          '302': [], '500': [], '200': [], '100': [], '2000': [], '1000': [],
        },
      ));
      final container = ProviderContainer(overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ]);
      addTearDown(container.dispose);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

      await container.read(gachaRepositoryProvider.notifier).debugRunHoYoWikiOnly();

      // icon (1) + shared.png (1, 跨 lang 共用) = 2 次 image download
      expect(imageDownloadCount, 2);
    });
  });
```

- [ ] **Step 2: Run tests to verify fail**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart
```
Expected: fails (gallery files not present; download stage only handles icon).

- [ ] **Step 3: Extend `_HoYoWikiDownloadItem` to carry kind**

In `lib/state/gacha_repository.dart` (around line 1010), update:

```dart
/// HoYoWiki 下載佇列的單一工作項。
class _HoYoWikiDownloadItem {
  const _HoYoWikiDownloadItem({
    required this.id,
    required this.url,
    required this.isGallery,
  });

  /// HoYoWiki entry_page_id。
  final String id;

  /// 圖片 URL。
  final String url;

  /// true → gallery 圖（用 hash 命名）；false → icon。
  final bool isGallery;
}
```

- [ ] **Step 4: Rewrite `enqueueDownloadsForEntry` to include gallery URLs with dedupe**

Replace the `enqueueDownloadsForEntry` from Task 5 with:

```dart
    final downloadTodo = <_HoYoWikiDownloadItem>[];
    final seenUrls = <String>{};  // 跨 entry/lang 去重，避免重複 enqueue

    void enqueueDownloadsForEntry(String id, HoYoWikiEntry entry) {
      // icon
      if (entry.iconUrl.isNotEmpty) {
        final iconFile = hoyowikiIconCacheFile(
          baseDir: cacheDir, id: id, url: entry.iconUrl,
        );
        if (!iconFile.existsSync() &&
            seenUrls.add('icon::${entry.iconUrl}')) {
          downloadTodo.add(_HoYoWikiDownloadItem(
            id: id, url: entry.iconUrl, isGallery: false,
          ));
        }
      }
      // gallery：迭代所有 lang 的 pic + list[].img，URL 去重
      for (final gallery in entry.galleryByLang.values) {
        void enqueue(String url) {
          if (url.isEmpty) return;
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir, id: id, url: url,
          );
          if (f.existsSync()) return;
          if (!seenUrls.add('gallery::$id::$url')) return;
          downloadTodo.add(_HoYoWikiDownloadItem(
            id: id, url: url, isGallery: true,
          ));
        }

        enqueue(gallery.picUrl);
        for (final it in gallery.list) {
          enqueue(it.imgUrl);
        }
      }
    }
```

- [ ] **Step 5: Update the download worker to dispatch by kind**

In the download worker (around lines 941–971), update file resolution:

```dart
        worker: (item) async {
          try {
            final bytes = await fetcher.downloadImage(item.url, client);
            if (bytes != null) {
              final file = item.isGallery
                  ? hoyowikiGalleryCacheFile(
                      baseDir: cacheDir, id: item.id, url: item.url,
                    )
                  : hoyowikiIconCacheFile(
                      baseDir: cacheDir, id: item.id, url: item.url,
                    );
              await file.writeAsBytes(bytes, flush: true);
              indexNotifier.bumpCacheRevision();
              downloaded++;
            }
          } catch (e) {
            _log.warning(
              'hoyowiki download failed url=${sanitizeUrl(item.url)} err=$e',
            );
          }
          ...
        },
```

(Keep the rest of the worker unchanged.)

- [ ] **Step 6: Run tests to verify pass**

```powershell
flutter test test/state/gacha_repository_hoyowiki_test.dart
flutter test
```
Expected: all pass.

- [ ] **Step 7: Run analyze**

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```powershell
git add lib/state/gacha_repository.dart test/state/gacha_repository_hoyowiki_test.dart
git commit -m "feat(hoyowiki): download gallery images with URL dedupe"
```

---

## Task 10: Rewrite `GachaItemDetailDialog` + `hasHoYoWikiContent`

**Files:**
- Rewrite: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

This is the user-facing payoff. After this task the feature is live end-to-end.

- [ ] **Step 1: Write failing widget tests**

Replace or extend `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`. Add helper for building entries with gallery:

```dart
HoYoWikiEntry _entryWith({
  required String iconUrl,
  required String picUrl,
  required List<HoYoWikiGalleryItem> list,
  String lang = 'en-us',
}) => HoYoWikiEntry(
  iconUrl: iconUrl,
  galleryByLang: {
    lang: HoYoWikiGalleryData(picUrl: picUrl, list: list),
  },
  fetchedAt: DateTime.utc(2026, 5, 26),
);
```

Then add tests inside `void main() { ... }`:

```dart
  group('GachaItemDetailDialog gallery', () {
    Future<void> seedEntry(
      String id,
      String name,
      String lang,
      HoYoWikiEntry entry,
    ) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: name, lang: lang, id: id, menuId: 2);
      await notifier.mergeEntry(
        id: id,
        lang: lang,
        fetched: HoYoWikiEntryFetched(
          iconUrl: entry.iconUrl,
          gallery: entry.galleryByLang[lang],
        ),
      );
    }

    Future<void> pumpDialog(WidgetTester tester, GachaRecord record) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showGachaItemDetailDialog(ctx, record),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('chip 列含 list 順序 + 最後是卡片', (tester) async {
      await _touchFile(tempDir, '12345_icon.png');
      // 假圖檔（hash 由 hoyowikiGalleryCacheFile 推導）
      final picFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir, id: '12345', url: 'https://x/card.png',
      );
      await _touchFile(tempDir, picFile.uri.pathSegments.last);
      final origFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir, id: '12345', url: 'https://x/orig.png',
      );
      await _touchFile(tempDir, origFile.uri.pathSegments.last);

      await seedEntry('12345', 'Hu Tao', 'en-us', _entryWith(
        iconUrl: 'https://x/icon.png',
        picUrl: 'https://x/card.png',
        list: [
          HoYoWikiGalleryItem(
            id: 'a', key: 'Original', imgUrl: 'https://x/orig.png',
            imgDescHtml: '<p>Outfit</p>',
          ),
        ],
      ));

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);  // app_en.arb galleryCardLabel
    });

    testWidgets('點切「卡片」chip → 圖片切到 pic', (tester) async {
      await _touchFile(tempDir, '12345_icon.png');
      final picFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir, id: '12345', url: 'https://x/card.png',
      );
      await _touchFile(tempDir, picFile.uri.pathSegments.last);
      final origFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir, id: '12345', url: 'https://x/orig.png',
      );
      await _touchFile(tempDir, origFile.uri.pathSegments.last);

      await seedEntry('12345', 'Hu Tao', 'en-us', _entryWith(
        iconUrl: 'https://x/icon.png',
        picUrl: 'https://x/card.png',
        list: [
          HoYoWikiGalleryItem(
            id: 'a', key: 'Original', imgUrl: 'https://x/orig.png',
            imgDescHtml: '<p>Outfit</p>',
          ),
        ],
      ));

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      // 預設第 0 張 = list[0] = orig
      var imgFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is FileImage &&
               (w.image as FileImage).file.path.endsWith(origFile.uri.pathSegments.last),
      );
      expect(imgFinder, findsOneWidget);

      // 切到「卡片」chip
      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();

      imgFinder = find.byWidgetPredicate(
        (w) => w is Image && w.image is FileImage &&
               (w.image as FileImage).file.path.endsWith(picFile.uri.pathSegments.last),
      );
      expect(imgFinder, findsOneWidget);
    });

    testWidgets('imgDesc 為空時整塊描述不繪', (tester) async {
      await _touchFile(tempDir, '12345_icon.png');
      final origFile = hoyowikiGalleryCacheFile(
        baseDir: tempDir, id: '12345', url: 'https://x/orig.gif',
      );
      await _touchFile(tempDir, origFile.uri.pathSegments.last);

      await seedEntry('12345', 'Hu Tao', 'en-us', _entryWith(
        iconUrl: 'https://x/icon.png',
        picUrl: '',
        list: [
          HoYoWikiGalleryItem(
            id: 'a', key: 'Idle', imgUrl: 'https://x/orig.gif', imgDescHtml: '',
          ),
        ],
      ));

      await pumpDialog(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      // 找不到 Html widget（flutter_html 的 Html 元件）
      expect(find.byType(Html), findsNothing);
    });

    testWidgets('hasHoYoWikiContent 在缺 gallery 時為 false', (tester) async {
      // icon 有檔但 gallery 完全沒抓
      await _touchFile(tempDir, '12345_icon.png');
      await container.read(hoyowikiIndexProvider.notifier).setSearch(
        name: 'Hu Tao', lang: 'en-us', id: '12345', menuId: 2,
      );
      await container.read(hoyowikiIndexProvider.notifier).mergeEntry(
        id: '12345', lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png', gallery: null,
        ),
      );

      final got = await checkContent(tester, _rec(name: 'Hu Tao', gachaType: '301'));
      expect(got, isFalse);
    });
  });
```

Add imports as needed at top of file:
```dart
import 'package:flutter_html/flutter_html.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
```

Update existing `tearDown` (around line 56) to also clear ImageCache:
```dart
  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });
```

Add `import 'package:flutter/painting.dart';` if not present.

- [ ] **Step 2: Run tests to verify fail**

```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```
Expected: compile errors (`Html` not imported into dialog, chip widget logic missing).

- [ ] **Step 3: Rewrite the dialog**

Replace the entire content of `lib/widgets/dialogs/gacha_item_detail_dialog.dart` with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 頌願卡池 gachaType 集合 — 永遠不可點。
const _odesGachaTypes = {'2000', '1000'};

/// 判斷 [record] 是否在 dialog 內有東西可顯示。需 icon 檔到位且
/// `record.lang` 的 gallery 有任一張 cache 檔到位。
bool hasHoYoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);

  if (entry.iconUrl.isEmpty) return false;
  if (!hoyowikiIconCacheFile(baseDir: cacheDir, id: id, url: entry.iconUrl)
      .existsSync()) {
    return false;
  }

  final gallery = entry.galleryByLang[record.lang];
  if (gallery == null) return false;

  bool ready(String url) =>
      url.isNotEmpty &&
      hoyowikiGalleryCacheFile(baseDir: cacheDir, id: id, url: url)
          .existsSync();

  if (ready(gallery.picUrl)) return true;
  return gallery.list.any((it) => ready(it.imgUrl));
}

/// 物品 dialog — title 為 icon + 名稱；content 為頂部 chip 列 +
/// 中央 gallery 圖（含 GIF）+ 下方 imgDesc HTML 描述。
class GachaItemDetailDialog extends ConsumerStatefulWidget {
  /// 建立 [GachaItemDetailDialog]。
  const GachaItemDetailDialog({super.key, required this.record});

  /// 要顯示的卡池 record。
  final GachaRecord record;

  @override
  ConsumerState<GachaItemDetailDialog> createState() =>
      _GachaItemDetailDialogState();
}

class _GachaItemDetailDialogState
    extends ConsumerState<GachaItemDetailDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final record = widget.record;

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final gallery = entry?.galleryByLang[record.lang];

    File? iconFile;
    if (id != null && entry != null && entry.iconUrl.isNotEmpty) {
      final f = hoyowikiIconCacheFile(
        baseDir: cacheDir, id: id, url: entry.iconUrl,
      );
      if (f.existsSync()) iconFile = f;
    }

    // chip 順序：list 全部 + pic（最後）
    final chipEntries = <_GalleryChipEntry>[];
    if (gallery != null) {
      for (final it in gallery.list) {
        chipEntries.add(_GalleryChipEntry(
          label: it.key,
          url: it.imgUrl,
          descHtml: it.imgDescHtml,
        ));
      }
      if (gallery.picUrl.isNotEmpty) {
        chipEntries.add(_GalleryChipEntry(
          label: l.galleryCardLabel,
          url: gallery.picUrl,
          descHtml: '',
        ));
      }
    }

    final clampedIndex = chipEntries.isEmpty
        ? -1
        : _selectedIndex.clamp(0, chipEntries.length - 1);
    final current = clampedIndex >= 0 ? chipEntries[clampedIndex] : null;

    File? currentFile;
    if (id != null && current != null) {
      final f = hoyowikiGalleryCacheFile(
        baseDir: cacheDir, id: id, url: current.url,
      );
      if (f.existsSync()) currentFile = f;
    }

    final nameColor = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textPrimary,
    };

    return AppDialog(
      size: AppDialogSize.md,
      title: Row(
        children: [
          if (iconFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(
                iconFile,
                width: 64, height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, e, st) {
                  Logger('gacha.hoyowiki.detail')
                      .warning('icon errorBuilder id=$id', e, st);
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              record.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: nameColor,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chipEntries.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < chipEntries.length; i++)
                  ChoiceChip(
                    label: Text(chipEntries[i].label),
                    selected: i == clampedIndex,
                    onSelected: (_) => setState(() => _selectedIndex = i),
                  ),
              ],
            ),
          if (chipEntries.length > 1) const SizedBox(height: 12),
          if (currentFile != null)
            Flexible(
              fit: FlexFit.loose,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  currentFile,
                  key: ValueKey(currentFile.path),
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, e, st) {
                    Logger('gacha.hoyowiki.detail').warning(
                      'gallery image errorBuilder id=$id url=${current?.url}',
                      e, st,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          if (current != null && current.descHtml.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Html(data: current.descHtml),
              ),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}

/// 內部：單一 chip 條目（chip 標籤 + 對應圖片 URL + 描述 HTML）。
class _GalleryChipEntry {
  /// 建立 [_GalleryChipEntry]。
  const _GalleryChipEntry({
    required this.label,
    required this.url,
    required this.descHtml,
  });

  /// chip 顯示的文字（list[i].key 或 app i18n galleryCardLabel）。
  final String label;

  /// 對應圖片 URL（用於推導 cache file path）。
  final String url;

  /// 描述 HTML；trim 後為空則不繪描述區。
  final String descHtml;
}

/// 顯示 [GachaItemDetailDialog]。
Future<void> showGachaItemDetailDialog(
  BuildContext context, GachaRecord record,
) {
  Logger('gacha.hoyowiki.detail').info(
    'open name=${record.name} lang=${record.lang} rank=${record.rankType}',
  );
  return showDialog<void>(
    context: context,
    builder: (_) => GachaItemDetailDialog(record: record),
  );
}

/// 把任意 [child] 包成可點區塊；[hasHoYoWikiContent] 為 false 時 passthrough。
class GachaItemTapTarget extends ConsumerWidget {
  /// 建立 [GachaItemTapTarget]。
  const GachaItemTapTarget({
    super.key, required this.record, required this.child,
  });

  /// 對應 record。
  final GachaRecord record;

  /// 子 widget。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasHoYoWikiContent(ref, record)) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showGachaItemDetailDialog(context, record),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```
Expected: all pass.

- [ ] **Step 5: Run full test suite + analyze**

```powershell
flutter analyze
flutter test
```
Expected: `No issues found!` and `All tests passed!`.

- [ ] **Step 6: Manual verification (依 CLAUDE.md：UI 改動需實機跑過)**

Run:
```powershell
flutter run -d windows
```

In the app:
1. Trigger an update so hoyowiki data is fetched fresh (or use existing cached state if v1 → v2 migration kicks in).
2. Click a 5-star or 4-star character record to open the dialog.
3. Verify:
   - Title shows icon + name.
   - Chip row shows list keys (e.g., 原畫 / 閒置動作１ / 閒置動作２ / 命之座 / 卡片).
   - Default chip 0 is selected; image is list[0].
   - Clicking each chip switches the image; GIF chips play animation.
   - Description appears below image only when imgDesc is non-empty.
   - Close button works.
4. Test edge case: a record whose entry has no gallery_character module → item should not show click affordance.

- [ ] **Step 7: Commit**

```powershell
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart test/widgets/dialogs/gacha_item_detail_dialog_test.dart
git commit -m "feat(hoyowiki): dialog gallery chips + GIF + flutter_html description"
```

---

## Task 11: Pre-commit quality check (CLAUDE.md 強制)

**Files:** none — verification only.

- [ ] **Step 1: Format**

```powershell
dart format lib/ test/
```
Expected: file count formatted; no errors. If any files reformat, that's expected — they get committed in Step 4.

- [ ] **Step 2: Analyze**

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 3: Full test suite**

```powershell
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 4: Commit any format-only changes (if any)**

If Step 1 modified files:
```powershell
git add lib/ test/
git commit -m "style: dart format after hoyowiki gallery feature"
```

If nothing changed, skip this step.

- [ ] **Step 5: Final state check**

```powershell
git status
git log --oneline -15
```
Expected: clean working tree; 10–11 new commits representing this feature.

---

## Self-Review

### Spec coverage check
- §1 Background / non-goals → handled across Tasks 1–10.
- §2 Data model → Tasks 2, 5.
- §3 Fetch pipeline (3-1 lang, 3-2 parse, 3-3 needRefetch, 3-4 worker, 3-5 mergeEntry, 3-6 download) → Tasks 6, 7, 8, 9.
- §4 Dialog UI + lang chain → Task 10.
- §5 i18n → Task 4.
- §6 Cache file naming & GC → Tasks 3, 5, 9. No GC task — by spec.
- §7 Edge cases & logging → covered in Tasks 6 (`_parseGalleryCharacterModule` warnings), 7 (`mergeEntry` log + icon non-empty overwrite + null gallery edge), 9 (download warnings), 10 (errorBuilder).
- §8 Tests → tests written in Tasks 3, 5, 6, 7, 8, 9, 10.
- §9 Package import → Task 1.
- §10 File-level changes → matches all task file lists.
- §11 Risks → mitigations live in Tasks 8 (concurrency), 9 (dedupe), 10 (parse fallback).
- §12 Out of scope → no tasks; not implemented.

### Placeholder scan
No "TBD" / "TODO later" / "fill in details" — searched. Two transient `TODO(Task 8)` markers in Tasks 6 and 7 are intentional intermediate state explicitly removed in Task 8.

### Type consistency
- `mergeEntry` signature: same in Task 7 definition, Task 7 callers, Task 8 entry worker, Task 10 widget test seed helper.
- `_HoYoWikiDownloadItem`: defined transiently in Task 5 with `(id, url)`; extended in Task 9 to add `isGallery`. Callers update in same task.
- `HoYoWikiEntryFetched`: transient form in Task 5 (`{iconUrl}` only); final form in Task 6 (`{iconUrl, gallery}`).
- Cache helpers: `hoyowikiIconCacheFile` / `hoyowikiGalleryCacheFile` — names stable from Task 3 onwards.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-26-hoyowiki-gallery-character.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
