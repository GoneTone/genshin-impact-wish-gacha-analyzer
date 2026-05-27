# HoYoWiki Entry desc + tags 與外連按鈕

**日期**：2026-05-26
**範圍**：擴充 entry_page 抓取，把 `data.page.desc` 與 `data.page.filter_values.*.values[]` 攤平的 tags 一起拉進來、做多語言儲存；dialog 物品名稱下方顯示 desc 與 tags；actions 區新增「前往 HoYoWiki」外連按鈕。

---

## 1. 背景與動機

目前 `entry_page` 只解 `icon_url` 與 `modules[].components[gallery_character]`，per-lang 存進 `HoYoWikiEntry.galleryByLang`。HoYoLab Wiki 同一個 entry 還包含：

- `data.page.desc`：物品描述文字（plain text 或含 HTML 標籤；跨 entry 不一致）。
- `data.page.filter_values`：一個 map，每個 key（例：`character_property`、`character_rarity`、`character_region`、`character_vision`、`character_weapon`）下有自己的 `values: List<String>`。

需求：

1. fetcher 同時抓回 desc 與所有 filter_values 攤平合併（**保留出現順序 + 去重**）的 tags，per-lang 存儲（與 gallery 走同一條 `record.lang` 鏈）。
2. dialog 在物品名稱下方顯示 desc（用 `flutter_html` render）與 tags（用 Material `Chip` + `Wrap`）。
3. dialog actions 區新增「前往 HoYoWiki」按鈕，連結 `https://wiki.hoyolab.com/pc/genshin/entry/<id>`。

### 非目標

- 不做 desc 內 HTML link 點擊、CSS 客製化、自訂字體。
- 不做 tags 點擊行為（過濾、跳轉等）、不做 tags 分組顯示、不做 tags 排序（保留 API 出現順序）。
- 不做 desc/tags 的 negative cache。
- 不做 cache GC。
- 不在外連 URL 上帶 lang query string（觀察後再決定）。

---

## 2. 資料模型

### 2-1 `lib/services/hoyowiki_index.dart`

新增「per-lang localized page」容器，把 gallery 收編並加 desc/tags：

```dart
/// 某一個 lang 抓到的整組 entry_page 資料（gallery + desc + tags）。
class HoYoWikiPageData {
  const HoYoWikiPageData({
    required this.gallery,
    required this.desc,
    required this.tags,
  });

  /// 該 lang 的 gallery_character 整組（pic + list）；entry 無 `gallery_character`
  /// module 時為 null（例：武器頁）。
  final HoYoWikiGalleryData? gallery;

  /// 該 lang 的 `data.page.desc`；可能為純文字或含 HTML，可能為空字串。
  final String desc;

  /// 該 lang 的 `data.page.filter_values.*.values[]` 全部攤平後去重、
  /// 保留首次出現順序的 tag list；可能為空 list。
  final List<String> tags;
}
```

`HoYoWikiEntry` 改為：

```dart
class HoYoWikiEntry {
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.pageByLang,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。lang-agnostic。
  final String iconUrl;

  /// 各語言整組 page 資料；key 為 `record.lang`。
  /// 某 lang 不在 map 內 = 該 lang 還沒抓過。
  final Map<String, HoYoWikiPageData> pageByLang;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}
```

`HoYoWikiGalleryData` / `HoYoWikiGalleryItem` 保留命名不動。

**關鍵語意變化**：原本 v2 設計「entry 無 `gallery_character` module → galleryByLang 該 lang 不寫入」；v3 改為「**pageByLang[lang] 一定寫入**」（即使 gallery null、desc 空、tags 空），因為現在 desc/tags 仍可能有值要保存。這影響 `needRefetchEntry`、`enqueueDownloadsForEntry` 與 `hasHoYoWikiContent` 的判斷（後述）。

### 2-2 Storage schema（`hoyowiki_index.json` version: 3）

```json
{
  "version": 3,
  "search": { "zh-tw::胡桃": "5125428", ... },
  "menu_ids": { "5125428": 2, ... },
  "entries": {
    "5125428": {
      "icon_url": "https://...",
      "fetched_at": "2026-05-26T03:14:00.000Z",
      "page_by_lang": {
        "zh-tw": {
          "gallery": {
            "pic_url": "https://.../card.png",
            "list": [
              {
                "id": "gallery_character8511",
                "key": "原畫",
                "img_url": "https://.../character.png",
                "img_desc_html": "<p>衣裝「魔女獵裝」</p>..."
              }
            ]
          },
          "desc": "「往生堂」第七十七代堂主...",
          "tags": ["生命之契", "4星", "蒙德"]
        }
      }
    }
  }
}
```

**v1 / v2 → v3 載入規則**：

- `version < 3`：丟棄 `gallery_by_lang` 與舊 `header_img_url`，`pageByLang` 設空 `{}`。
- `icon_url`、`fetched_at`、`search`、`menu_ids` 全保留。
- 結果：升級後 entries 自然被 `needRefetchEntry` 判定為「該 lang 沒 page → 重抓」，下次 update per-lang 重打 entry_page 一次補齊 gallery+desc+tags。

**真實成本**：圖檔 cache 檔在磁碟上保留，下載階段 `enqueueDownloadsForEntry` 發現檔已存在會自動 skip → **不重下圖**，流量主要在 entry_page API（每 entry-lang pair 一次 HTTP）。與 v1→v2 「reset」pattern 一致。

---

## 3. Fetch pipeline

### 3-1 `HoYoWikiEntryFetched` 改結構

```dart
class HoYoWikiEntryFetched {
  const HoYoWikiEntryFetched({required this.iconUrl, required this.page});
  final String iconUrl;
  final HoYoWikiPageData page;   // 必出，gallery 可能 null、desc/tags 可能空
}
```

### 3-2 `HoYoWikiFetcher.fetchEntryPage`

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

`_parseGalleryCharacterModule` 邏輯不動（已驗證）。

### 3-3 `_parseTags`

```dart
/// 從 entry_page response 的 `data.page.filter_values` 攤平所有 group 的 values，
/// 保留首次出現順序去重後回傳。例：
///   {character_property: {values: ['生命之契']},
///    character_rarity: {values: ['4星']},
///    character_region: {values: ['蒙德']}}
///   → ['生命之契', '4星', '蒙德']
///
/// Map 遍歷順序：Dart `Map` 保證 insertion order，`jsonDecode` 回傳的是
/// `LinkedHashMap`，所以「filter_values 出現順序」對同一份 JSON 是穩定的。
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
```

### 3-4 `HoYoWikiIndexNotifier.mergeEntry`

```dart
Future<void> mergeEntry({
  required String id,
  required String lang,
  required HoYoWikiEntryFetched fetched,
}) async {
  await _lock.synchronized(() async {
    final existing = state.entries[id];
    final mergedPage = <String, HoYoWikiPageData>{
      if (existing != null) ...existing.pageByLang,
      lang: fetched.page,            // 必寫入（即使 gallery null、desc/tags 空）
    };
    final iconUrl = fetched.iconUrl.isNotEmpty
        ? fetched.iconUrl
        : (existing?.iconUrl ?? '');  // 非空覆寫，沿用 v2 策略
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

### 3-5 `needRefetchEntry` per-lang

```dart
bool needRefetchEntry(HoYoWikiEntry? entry, int? menuId, String lang) {
  if (entry == null) return true;
  if (menuId == null) return true;
  if (!entry.pageByLang.containsKey(lang)) return true;
  return false;
}
```

`entryTodo` 依然是 `Set<({String id, String lang})>`（v2 已有）。

### 3-6 `enqueueDownloadsForEntry`

```dart
void enqueueDownloadsForEntry(String id, HoYoWikiEntry entry) {
  // icon
  if (entry.iconUrl.isNotEmpty) {
    final iconFile = hoyowikiIconCacheFile(
      baseDir: cacheDir, id: id, url: entry.iconUrl,
    );
    if (!iconFile.existsSync() && seenUrls.add('icon::${entry.iconUrl}')) {
      downloadTodo.add(
        _HoYoWikiDownloadItem(id: id, url: entry.iconUrl, isGallery: false),
      );
    }
  }
  // gallery：迭代所有 lang 的 page，gallery 為 null 跳過
  for (final page in entry.pageByLang.values) {
    final g = page.gallery;
    if (g == null) continue;
    void enqueue(String url) {
      if (url.isEmpty) return;
      final f = hoyowikiGalleryCacheFile(baseDir: cacheDir, id: id, url: url);
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
}
```

desc / tags 不參與下載階段（純文字資料）。

---

## 4. Dialog UI（`gacha_item_detail_dialog.dart`）

### 4-1 版型

```
┌─ AppDialog (size: md = 640) ───────────────────────────────┐
│ Title:                                                      │
│   Row(                                                      │
│     icon 64×64,                                             │
│     SizedBox(12),                                           │
│     Expanded(                                               │
│       Column(crossAxis: start, mainAxisSize: min) {         │
│         Text(record.name, headlineSmall, nameColor)         │
│         if (desc.trim().isNotEmpty) ...[                    │
│           SizedBox(8),                                      │
│           ConstrainedBox(maxHeight: 120,                    │
│             child: SingleChildScrollView(                   │
│               child: Html(data: desc))),                    │
│         ],                                                  │
│         if (tags.isNotEmpty) ...[                           │
│           SizedBox(8),                                      │
│           Wrap(spacing: 6, runSpacing: 6,                   │
│                children: tags.map((t) => Chip(              │
│                  label: Text(t),                            │
│                  visualDensity: VisualDensity.compact,      │
│                  materialTapTargetSize:                     │
│                    MaterialTapTargetSize.shrinkWrap,        │
│                ))),                                         │
│         ],                                                  │
│       },                                                    │
│     ),                                                      │
│   )                                                         │
├────────────────────────────────────────────────────────────┤
│ Content（不動）：chip 列 + 圖 + imgDesc                     │
├────────────────────────────────────────────────────────────┤
│ Actions:                                                    │
│   [↗ 前往 HoYoWiki]   [關閉]                                │
└────────────────────────────────────────────────────────────┘
```

### 4-2 元件決策

- **desc**：用 `flutter_html` 渲染（與既有 `imgDescHtml` 同 widget）。`trim().isEmpty` 整塊不繪。`ConstrainedBox(maxHeight: 120) + SingleChildScrollView` 包住，避免 desc 太長把 title 區撐爆。
- **tags**：Material `Chip`（不可點，不帶 `onPressed`）。套 `VisualDensity.compact` + `MaterialTapTargetSize.shrinkWrap` 縮緊高度。`Wrap(spacing: 6, runSpacing: 6)` 自動換行。`tags.isEmpty` 整塊不繪。
- **「前往 HoYoWiki」按鈕**：`TextButton.icon` + `Icons.open_in_new`，置於 `FilledButton(關閉)` 左邊（Material 慣例：dismiss action 在右）。共用 `openExternalUrl(uri)`（`lib/widgets/app_link.dart`），已含 `canLaunchUrl` 檢查 + warning log + 靜默 fallback。
- **URL 組裝**：`Uri.parse('https://wiki.hoyolab.com/pc/genshin/entry/$id')`，`<id>` = `hoyowikiIndex.lookupId(name: record.name, lang: record.lang)`（dialog 已在 build 取出）。
- **lang 不帶 URL**：HoYoLab Wiki 由 browser cookie / accept-language 決定語言。若未來反應「外連到的不是 record.lang 版本」再加 query string。
- **id null guard**：`hasHoYoWikiContent` 已保證 id 非 null 才開 dialog，但 `onPressed` 仍加 `id == null ? null : ...` 防線。

### 4-3 `hasHoYoWikiContent`

維持既有「icon 在 + cache 檔在 即可」判斷，**不動**。`fetchEntryPage` 是同一次呼叫補 icon + page，icon cache 在的情境下 `pageByLang[lang]` 一定也已寫入。

### 4-4 資料抓取鏈

```dart
final entry = id == null ? null : index.lookupEntry(id);
final page = entry?.pageByLang[record.lang];
final gallery = page?.gallery;
final desc = page?.desc ?? '';
final tags = page?.tags ?? const <String>[];
```

### 4-5 Log 點

| Logger | 等級 | 內容範例 |
|---|---|---|
| `gacha.hoyowiki.detail` | info | `'open wiki id=$id'` — 「前往 HoYoWiki」按鈕點擊時 |

既有 `'open name=... lang=... rank=...'` log 不動。

---

## 5. i18n

新增 1 條 ARB key（依 memory `feedback_i18n_starts_from_zh.md`：先寫繁中、再以中文為基準翻其他語系；依 memory `feedback_i18n_skip_empty_arbs.md`：只加在已有實體翻譯的 ARB 檔，空殼留給 Crowdin pipeline）：

| key | zh-tw | 用途 |
|---|---|---|
| `actionViewOnHoYoWiki` | `前往 HoYoWiki` | dialog actions 區外連按鈕標籤 |

- `description` metadata 用英文（依 memory `project_crowdin_l10n_pipeline_gotchas` 提到 `galleryCardLabel` / `galleryIconLabel` 的處理方式）。
- 翻譯前查 `docs/術語表.md`；「HoYoWiki」是品牌名稱不翻譯。
- 翻譯到已有實體翻譯的 ARB：`app_en.arb` / `app_es.arb` / `app_fr.arb` / `app_ja.arb` / `app_pt_BR.arb` / `app_th.arb` / `app_vi.arb` / `app_zh_Hans.arb`，其他空殼不碰。

desc / tags 內容本身跟著 `record.lang`（從 HoYoWiki API `X-Rpc-Language` header 取對應語言），與 app UI 語言無關。鏈路同 §3 既有設計。dialog 內 desc / tags 沒有 section heading（直接 render，無「介紹：」「標籤：」前綴文字），所以無其他新 key。

---

## 6. 邊界與 Log

### 6-1 邊界情況

| 情況 | 處理 |
|---|---|
| `page.desc` 缺 key / 非 string 型別 | `''`（空字串），dialog 不繪 desc 區 |
| `page.filter_values` 缺 key / 為 null | `tags = const []`，dialog 不繪 tags 區 |
| `filter_values[group]` 缺 `values` key / 非 list | 該 group 跳過 |
| `values[i]` 非 string / trim 後為空 | 單筆 skip |
| `values` 跨 group 重複 | 去重，保留首次出現位置 |
| entry 無 `gallery_character` module（如武器頁） | `page.gallery == null`，dialog content 區 chip 列仍可顯示 Icon chip |
| desc 含 HTML（`<p>`、`<br>` 等） | `flutter_html` 正常渲染 |
| desc 為純文字 | `flutter_html` 退化為 inline text |
| desc 超長 | title 區 maxHeight 120 + scroll，content 區仍可見 |
| tags 為空 list | tags Wrap 整塊不繪 |
| 「前往 HoYoWiki」按鈕：`canLaunchUrl` 失敗 | `openExternalUrl` 內部 warning log + 靜默 |
| 「前往 HoYoWiki」按鈕：id 為 null（防線） | `onPressed: null` 按鈕 disabled |

### 6-2 Logger 命名（依 CLAUDE.md「新功能要埋 log」規範）

| Logger | 等級 | 內容範例 |
|---|---|---|
| `gacha.hoyowiki` | info | `'entry id=$id lang=$lang icon=true gallery=true pic=true list=4 desc=true tags=5'` |
| `gacha.hoyowiki.notifier` | fine | `'merge page id=$id lang=$lang gallery=true desc=true tags=5'` |
| `gacha.hoyowiki.storage` | info | `'migrate v2 → v3: $n entries reset (gallery_by_lang dropped)'` |
| `gacha.hoyowiki.detail` | info | `'open wiki id=$id'`（「前往 HoYoWiki」按鈕點擊）|

URL 仍經 `sanitizeUrl(...)` 才寫入 log；lang / id 非敏感原樣記錄。

### 6-3 Update 進度顯示

`FetchingHoYoWiki` 三階段結構不變。entry / download 階段的 `totalCount` 邏輯不變（desc/tags 不影響 download todo 數）。文案不需動。

---

## 7. 測試

### 7-1 Unit tests

| 對象 | 案例 |
|---|---|
| `_parseTags` | 多 group 攤平 / 跨 group 重複 value 去重保留首次順序 / 空 map / 缺 `values` key / `values` 非 list / value 非 string skip / value trim 後為空字串 skip |
| `fetchEntryPage` 新增 | desc 帶值 / desc 缺 key → `''` / desc 為非 string → `''` / filter_values 為 null → `tags == []` / 完整 gallery+desc+tags |
| `HoYoWikiIndexStorage` | v3 round trip（page_by_lang 含 gallery+desc+tags 完整序列化）/ v2 載入 → page_by_lang 設空、其他欄位保留 / v1 載入同上 |

### 7-2 Widget tests（`GachaItemDetailDialog`）

| 案例 | 驗證點 |
|---|---|
| desc 帶 HTML（如 `<p>...</p>`） | title 區渲染 `Html` widget，文字節點可見 |
| desc 為空字串 | title 區無 desc 區塊（用 widget key 或精確 finder 區分 imgDescHtml 那塊）|
| tags 3 個 | Wrap 內 3 個 `Chip`、label 文字正確、無 `InkWell` 點擊 |
| tags 空 | tags Wrap 整塊不繪 |
| desc 過長 | title 區有 maxHeight + scroll，content 區仍可見 |
| 「前往 HoYoWiki」按鈕點擊 | `openExternalUrl` 被呼叫且 URL 為 `https://wiki.hoyolab.com/pc/genshin/entry/<id>`（用 dependency injection 或 mock helper）|
| 「前往 HoYoWiki」按鈕 + id null（理論不會發生）| `onPressed == null`（按鈕 disabled） |
| 既有 gallery chip + 圖 + imgDesc 區 | 維持原行為（regression check）|
| tearDown | `imageCache.clear()` + `imageCache.clearLiveImages()`（沿用 memory `project_image_cache_cross_test_race`）|

### 7-3 Repository / state tests

| 案例 | 驗證點 |
|---|---|
| `mergeEntry` 寫入 page | `entry.pageByLang[lang]` 含完整 gallery+desc+tags |
| `mergeEntry` 跨 lang 不互蓋 | A lang 已有 page，B lang fetch 後 A 仍存 |
| `mergeEntry` 同 lang 重覆 fetch | 後抓覆蓋前抓（最後寫入勝出）|
| `needRefetchEntry` per-lang | `pageByLang[lang]` 不存在 → true；存在（即使 gallery null）→ false |
| `enqueueDownloadsForEntry` | gallery 為 null 的 page 跳過；非 null 走 URL 去重 |

### 7-4 提交前品質檢查（CLAUDE.md 強制）

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

任一失敗就先修，禁用 `--no-verify`。

---

## 8. 套件導入

- **`flutter_html`**：已在 pubspec.yaml（v2 gallery_character feature 引入）。版本不需動。
- **`url_launcher`**：已在 pubspec.yaml（`openExternalUrl` 用）。共用 `lib/widgets/app_link.dart` 的 helper。
- **不新增任何套件**。

---

## 9. 變更清單（檔案層級）

| 檔案 | 變更 |
|---|---|
| `lib/services/hoyowiki_index.dart` | 新增 `HoYoWikiPageData`；`HoYoWikiEntry.galleryByLang` → `pageByLang`；storage save/load 改 v3 schema 並處理 v2→v3 載入 |
| `lib/services/hoyowiki_fetcher.dart` | `HoYoWikiEntryFetched` 結構改（gallery → page）；`fetchEntryPage` 解 desc + tags；新增 `_parseTags` |
| `lib/state/hoyowiki_index.dart` | `mergeEntry` 改寫 page（接收 `HoYoWikiPageData`）|
| `lib/state/gacha_repository.dart` | `needRefetchEntry` 改 `pageByLang.containsKey`；`enqueueDownloadsForEntry` 走 `pageByLang.values` 跳 gallery==null |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | title 區重構為 Row(icon, Column(name, desc, tags))；actions 區加「前往 HoYoWiki」TextButton.icon |
| `lib/l10n/app_zh.arb` | 加 `actionViewOnHoYoWiki` |
| `lib/l10n/app_{en,es,fr,ja,pt_BR,th,vi,zh_Hans}.arb` | 翻譯 |
| `test/services/hoyowiki_fetcher_test.dart` | desc/tags 解析案例 |
| `test/services/hoyowiki_index_test.dart` | v3 round trip / v2→v3 migration 案例 |
| `test/state/hoyowiki_index_test.dart` | mergeEntry page 案例 |
| `test/state/gacha_repository_*_test.dart` | per-lang refetch / enqueue 去重案例（如 regression 受影響）|
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | desc / tags / 外連按鈕案例 |

---

## 10. 風險與緩解

| 風險 | 緩解 |
|---|---|
| v2 → v3 migration reset 後第一次 update 變慢 | 圖檔 cache 不刪 → 下載階段自動 skip 既有檔；主要成本是 entry_page API per-lang 重打一次（可接受）|
| `flutter_html` 在 title 區 render 較重 | desc 多半短文字；ConstrainedBox + SingleChildScrollView 限高避免撐爆；既有 imgDesc 已驗證可用 |
| HoYoLab Wiki URL 樣板未來改版 | URL 在 dialog 內單點組裝，一處修改；點擊失敗時 `openExternalUrl` 已 warning log |
| 外連到的 HoYoLab Wiki 顯示語言與 record.lang 不同 | YAGNI 先不加 query string；觀察後再決定（如有報告再加 `lang=` query 或 URL path 變體）|
| filter_values 結構在未來 HoYoWiki 改版破壞 | `_parseTags` 為防禦性解析（多層 `is`/`isNotEmpty` 檢查），失敗回 `const []`；無 throw |

---

## 11. 不在範圍內（已明確 out）

- desc 內 HTML link 點擊（flutter_html 預設不 launch）。
- desc 自訂 CSS / 字體 / 顏色。
- tags 點擊行為（過濾、跳轉、複製等）。
- tags 分組顯示 / 群組排序 / 字母排序（已決定攤平去重、保留 API 順序）。
- desc / tags 的 negative cache（與 gallery 一致，無 sentinel）。
- v2 → v3 in-place migration 保留 gallery（已決定整個 `page_by_lang` reset，圖檔不刪）。
- 外連 URL 帶 lang query / path 變體。
- 「前往 HoYoWiki」按鈕的 hover preview / tooltip。
