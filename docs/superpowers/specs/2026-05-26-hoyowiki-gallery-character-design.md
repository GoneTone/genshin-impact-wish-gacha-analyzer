# HoYoWiki Gallery Character 圖集整合

**日期**：2026-05-26
**範圍**：把物品 dialog 內單張 `header_img_url` 取代成從 `entry_page` 解出的 gallery（多張 + 多語言 + GIF），改 fetcher、storage schema、dialog UI。

---

## 1. 背景與動機

目前 `GachaItemDetailDialog` 顯示「icon（title）+ 單張 header（content）」，資料來自 `entry_page` 回應的 `data.page.icon_url` 與 `data.page.header_img_url`。HoYoLAB Wiki 同一個 entry 其實在 `data.page.modules[].components[]` 內含一個 `component_id == "gallery_character"` 的元件，其 `data` 欄位（**字串**型 JSON）內含：

```json
{
  "pic": "https://act-upload.hoyoverse.com/.../card.png",
  "list": [
    { "id": "gallery_characterXXXX", "key": "原畫", "img": "...png", "imgDesc": "<p>衣裝「魔女獵裝」</p>..." },
    { "id": "...", "key": "閒置動作１", "img": "....gif", "imgDesc": "" },
    ...
  ]
}
```

要改成把所有 `list[]` 圖加上 `pic`（卡片放最後）做成 chip 切換的多圖瀏覽，並顯示 `imgDesc`。

`key` 與 `imgDesc` 屬語言相依字串；`img` / `pic` URL 與圖檔本身也**可能跨 lang 不同**（同物品在不同語言版本可能取到不同 CDN URL／不同圖），不能假設「圖檔 lang-agnostic」。本設計把整組 `{pic, list}` 連同文字 per-lang 一起存。

### 非目標

- 不寫舊 `<id>_header.*` 快取的清理腳本（功能未發布、無 user impact）。
- 不做 fallback 鏈（記住：使用者切 app 語言與 dialog 顯示無關，dialog 字串永遠跟著 `record.lang`）。
- 不做 chip 鍵盤導航、左右箭頭、PageView swipe（YAGNI）。
- 不做 cache GC。

---

## 2. 資料模型

### 2-1. `lib/services/hoyowiki_index.dart`

```dart
class HoYoWikiEntry {
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.galleryByLang,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。lang-agnostic。
  final String iconUrl;

  /// 各語言抓到的整組 gallery；key 為 record.lang（zh-tw / en / ja / ...）。
  /// 某 lang 不在 map 內 = 該 lang 還沒抓過（或抓過但 entry 無 gallery_character module）。
  final Map<String, HoYoWikiGalleryData> galleryByLang;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}

class HoYoWikiGalleryData {
  const HoYoWikiGalleryData({required this.picUrl, required this.list});
  final String picUrl;
  final List<HoYoWikiGalleryItem> list;
}

class HoYoWikiGalleryItem {
  const HoYoWikiGalleryItem({
    required this.id,
    required this.key,
    required this.imgUrl,
    required this.imgDescHtml,
  });
  final String id;
  final String key;
  final String imgUrl;
  final String imgDescHtml;
}
```

移除：`HoYoWikiEntry.headerImgUrl`、`HoYoWikiEntryFetched.headerImgUrl`、`HoYoWikiImageKind.header`。

### 2-2. Storage schema（`hoyowiki_index.json` version: 2）

```json
{
  "version": 2,
  "search": { "zh-tw::布倫妮": "12345", ... },
  "menu_ids": { "12345": 2, ... },
  "entries": {
    "12345": {
      "icon_url": "https://...",
      "fetched_at": "2026-05-26T03:14:00.000Z",
      "gallery_by_lang": {
        "zh-tw": {
          "pic_url": "https://.../card.png",
          "list": [
            {
              "id": "gallery_character8511",
              "key": "原畫",
              "img_url": "https://.../character.png",
              "img_desc_html": "<p>衣裝「魔女獵裝」</p>..."
            }
          ]
        }
      }
    }
  }
}
```

**v1 → v2 載入規則**：
- 讀到 `version != 2` 或缺 `version`：丟棄 `entries[].header_img_url` 與舊 `header_img_url`；保留 `icon_url`、`fetched_at`；`galleryByLang` 設空 map。
- `search` / `menu_ids` 不變。
- 結果：v1 entries 自然會被 `needRefetchEntry` 判定為「該 lang 沒 gallery → 重抓」。

---

## 3. Fetch pipeline

### 3-1. `HoYoWikiFetcher.fetchEntryPage` 帶 lang

```dart
Future<HoYoWikiEntryFetched> fetchEntryPage({
  required String id,
  required String lang,
  required http.Client client,
}) async {
  final url = _entryBase.replace(queryParameters: {'entry_page_id': id});
  final res = await client.get(url, headers: {
    'X-Rpc-Language': lang,
  }).timeout(timeout);

  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final retcode = body['retcode'] as int;
  if (retcode != 0) {
    throw ApiErrorException(retcode, body['message'] as String? ?? '');
  }

  final page = body['data']?['page'] as Map<String, dynamic>?;
  final iconUrl = (page?['icon_url'] as String?) ?? '';
  final modules = (page?['modules'] as List<dynamic>?) ?? const [];
  final gallery = _parseGalleryCharacterModule(modules);  // 可能為 null

  _log.info(
    'entry id=$id lang=$lang icon=${iconUrl.isNotEmpty} '
    'gallery=${gallery != null} '
    'pic=${gallery?.picUrl.isNotEmpty == true} '
    'list=${gallery?.list.length ?? 0}',
  );
  return HoYoWikiEntryFetched(iconUrl: iconUrl, gallery: gallery);
}
```

`HoYoWikiEntryFetched` 改為：

```dart
class HoYoWikiEntryFetched {
  const HoYoWikiEntryFetched({required this.iconUrl, required this.gallery});
  final String iconUrl;
  final HoYoWikiGalleryData? gallery;
}
```

### 3-2. `_parseGalleryCharacterModule`

```dart
HoYoWikiGalleryData? _parseGalleryCharacterModule(List<dynamic> modules) {
  for (final m in modules) {
    final components = (m as Map<String, dynamic>)['components'] as List<dynamic>?;
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
            _log.warning('gallery item missing fields id=$gid key=$key img=$img');
            continue;
          }
          list.add(HoYoWikiGalleryItem(
            id: gid, key: key, imgUrl: img,
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

### 3-3. `needRefetchEntry` per-lang

`gacha_repository.dart` 內：

```dart
bool needRefetchEntry(HoYoWikiEntry? entry, int? menuId, String lang) {
  if (entry == null) return true;
  if (menuId == null) return true;             // 維持舊判定
  if (!entry.galleryByLang.containsKey(lang)) return true;
  return false;
}
```

`entryTodo` 從 `Set<String>` 改為 `Set<({String id, String lang})>`，search 階段命中 `lang::name → id` 後 enqueue 對應 `(id, lang)`。

### 3-4. entry 階段 worker

```dart
worker: (pair) async {
  try {
    final fetched = await fetcher.fetchEntryPage(
      id: pair.id, lang: pair.lang, client: client,
    );
    await indexNotifier.mergeEntry(
      id: pair.id, lang: pair.lang, fetched: fetched,
    );
    enqueueDownloadsForEntry(pair.id, lang: pair.lang);
  } catch (e) {
    _log.warning('hoyowiki entry failed id=${pair.id} lang=${pair.lang} err=$e');
  }
  ...
}
```

### 3-5. `HoYoWikiIndexNotifier.mergeEntry`

```dart
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
    // icon 採「非空覆寫」：避免某 lang 暫時抓回空 icon 時把既有好值清掉。
    final iconUrl = fetched.iconUrl.isNotEmpty
        ? fetched.iconUrl
        : (existing?.iconUrl ?? '');
    final merged = HoYoWikiEntry(
      iconUrl: iconUrl,
      galleryByLang: mergedGallery,
      fetchedAt: DateTime.now().toUtc(),
    );
    final newEntries = Map<String, HoYoWikiEntry>.from(state.entries)..[id] = merged;
    final next = HoYoWikiIndex(
      searchMap: state.searchMap, entries: newEntries, menuIds: state.menuIds,
    );
    await _saveAndEmit(next);
    _log.fine('merge gallery id=$id lang=$lang has=${fetched.gallery != null}');
  });
}
```

舊 `setEntry` 移除。

### 3-6. download 階段：URL hash 去重

`enqueueDownloadsForEntry(id, {String? lang})` 邏輯：
- icon：照舊 `<id>_icon.<ext>`。
- gallery：走 `entry.galleryByLang.values`（每次抓完新 lang 後跑），蒐集所有 `picUrl` + `list[].imgUrl`，**以 URL 為 key 去重**（不同 lang 若碰巧拿到同 URL 只下載一次；不同則各自下載），已存在則 skip，否則 enqueue。

新增 helper（取代 `hoyowikiCacheFile`）：

```dart
File hoyowikiIconCacheFile({
  required Directory baseDir, required String id, required String url,
}) => File('${baseDir.path}/${id}_icon.${_extFromUrl(url)}');

File hoyowikiGalleryCacheFile({
  required Directory baseDir, required String id, required String url,
}) {
  final hash = sha1.convert(utf8.encode(url)).toString().substring(0, 12);
  return File('${baseDir.path}/${id}_gallery_$hash.${_extFromUrl(url)}');
}
```

`HoYoWikiImageKind` enum 移除（無共用語意）。Download 階段在 repository 內維護兩個 todo list：`iconTodo: Set<({String id, String url})>` 與 `galleryTodo: Set<({String id, String url})>`，各自 worker 處理對應 helper 寫檔，兩者共用同一個 `runConcurrent` 池但分階段或合併皆可（建議合併 enqueue 到單一 worker，內部以 enum 分支寫對應 helper，介面比兩個 worker 簡潔）。

---

## 4. Dialog UI

### 4-1. 版型

```
┌─ AppDialog (size: md = 640) ─────────────────────────┐
│ Title:  [icon 64x64]  名稱                            │
├──────────────────────────────────────────────────────┤
│ Content:                                              │
│   Wrap(spacing: 8, runSpacing: 8)                     │
│     ChoiceChip(原畫) ChoiceChip(閒置動作１) ...       │
│     ChoiceChip(卡片)              ← pic, 永遠最後    │
│   --                                                  │
│   Flexible + Image.file(BoxFit.contain)               │
│     key: ValueKey(file.path)                          │
│   --                                                  │
│   if (imgDescHtml.trim().isNotEmpty)                  │
│     ConstrainedBox(maxHeight: 160)                    │
│       SingleChildScrollView                           │
│         Html(data: imgDescHtml)                       │
├──────────────────────────────────────────────────────┤
│ Actions: [關閉]                                       │
└──────────────────────────────────────────────────────┘
```

### 4-2. 元件決策

- **Stateful**：dialog 改成 `StatefulWidget` 維護 `int _selectedIndex`，預設 0。Chip 列項目 = list 順序 + (pic 非空時) 最後加「卡片」chip。
- **ChoiceChip**：`selected = (_selectedIndex == i)`、`onSelected: (_) => setState(...)`。內建 hover affordance，免另包 `InkWell` / `MouseRegion`。
- **GIF**：`Image.file(file)` Flutter 原生支援 GIF 播放。每次切 chip 透過 `ValueKey(file.path)` 強制重建以重啟 GIF 從第一幀。
- **`imgDesc`**：HTML 用 [`flutter_html`](https://pub.dev/packages/flutter_html) render。`trim().isEmpty` 則整塊不繪。
- **長描述**：`ConstrainedBox(maxHeight: 160) + SingleChildScrollView` 避免擠掉圖片。
- **缺檔 fallback**：`Image.file` 的 `errorBuilder` 顯示 `SizedBox.shrink()` 並 `Logger('gacha.hoyowiki.detail').warning(...)`。

### 4-3. `hasHoYoWikiContent` 改寫

```dart
bool hasHoYoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);

  // icon 必要
  if (entry.iconUrl.isEmpty) return false;
  if (!hoyowikiIconCacheFile(baseDir: cacheDir, id: id, url: entry.iconUrl)
      .existsSync()) return false;

  // 該 lang 的 gallery 必須有東西可顯示
  final gallery = entry.galleryByLang[record.lang];
  if (gallery == null) return false;

  bool ready(String url) =>
      url.isNotEmpty &&
      hoyowikiGalleryCacheFile(baseDir: cacheDir, id: id, url: url).existsSync();

  if (ready(gallery.picUrl)) return true;
  return gallery.list.any((it) => ready(it.imgUrl));
}
```

### 4-4. Lang 對應決策鏈

**核心原則**：dialog 顯示哪個語言版本的圖文，完全跟 `record.lang` 走，與 app UI 語言無關。

**查找流程**（從 record 到 gallery）：

```
GachaRecord
  └─ record.lang  (該筆抽卡 record 抓回來時的 API lang，例：zh-tw / en / ja)
       │
       ▼
hoyowikiIndex.lookupId(name: record.name, lang: record.lang)
  └─ 命中 → entry id   ← search 階段以 'lang::name' 為 key 建索引
       │
       ▼
hoyowikiIndex.lookupEntry(id)
  └─ HoYoWikiEntry { iconUrl, galleryByLang, fetchedAt }
       │
       ▼
entry.galleryByLang[record.lang]
  └─ HoYoWikiGalleryData { picUrl, list[] }   ← 該 lang 的整組圖+文字
       │
       ▼
dialog 渲染（chip 標籤、圖片、imgDesc 全部來自這一組）
```

**Fetch 時用同一條鏈**：search 階段命中 `record.lang::name → id` 後，entry 階段排隊 `(id, record.lang)`，呼叫 `fetchEntryPage(id, lang: record.lang, ...)` 並送 `X-Rpc-Language: record.lang` header，回應寫入 `galleryByLang[record.lang]`。因此 dialog 開啟時 `galleryByLang[record.lang]` 一定有值（除非 hoyowiki API 該 entry 真的無 `gallery_character` module，此時整筆物品在 `hasHoYoWikiContent` 即被判定為不可點）。

**為何不採 app UI lang**：
- `record.name`（dialog title）本身就是 `record.lang` 字串；chip/desc 必須跟它對齊，否則畫面會出現「title 繁中 + chip 英文」的混搭。
- 同一 record 任何時候打開都是同一語言版本，符合「dialog 是這筆 record 的詳細資料、不是 app 設定的鏡像」直覺。
- 切 app 語言不會觸發 dialog 重新 fetch、不影響可點性，邏輯穩定。

**多 UID／多 lang 共存**：同一物品（如「布倫妮」/「Brunhilde」）若 A 帳號用 `zh-tw` 抓、B 帳號用 `en` 抓，兩筆 record 共用同一 hoyowiki id；`entry.galleryByLang` 會同時長出 `zh-tw` 與 `en` 兩 key（per-lang lazy 補抓），A 開 dialog 看繁中版、B 開看英文版，互不干擾。

---

## 5. i18n

### 5-1. App UI（跟著 app 語言）

新增 1 條 ARB key（依 memory 規範：先寫繁中、再以中文為基準翻其他語系，**不從 `app_en.arb` 起手**）：

| key | zh-tw | 用途 |
|---|---|---|
| `galleryCardLabel` | `卡片` | pic 在 chip 列上的標籤 |

實作前先查 `docs/術語表.md`（依 memory：術語表為官方權威來源）；無對應條目則沿用上表字面。其他語系 (en/ja/ko/zh-cn/...) 走既有 Crowdin pipeline，注意 memory `project_crowdin_l10n_pipeline_gotchas` 的三地雷（locale code 帶地區碼、空殼、Portuguese 搬家）。

### 5-2. Entry gallery（跟著 record.lang）

`record.lang` 直接當 `X-Rpc-Language` header 值送（既有 `searchEntryId` 已驗證可吃 `zh-tw / zh-cn / en / ja / ko / ...`，**不做映射**）。

Dialog 內任何來自 entry 的字串都用 `entry.galleryByLang[record.lang]` 那一份，絕不混入 app UI 語言（避免 chip 標籤是繁中、描述是英文的混雜畫面）。

### 5-3. Fallback 不做

依釐清結論「抓到圖必抓到文字」、「切 app 語言與顯示無關」：`galleryByLang[record.lang]` 不存在 → `hasHoYoWikiContent` 為 false → 物品不可點。

---

## 6. Cache 檔案與清理

### 6-1. 檔名

| 種類 | 命名 | 範例 |
|---|---|---|
| icon | `<id>_icon.<ext>` | `12345_icon.png` |
| gallery | `<id>_gallery_<urlHash12>.<ext>` | `12345_gallery_a3f9bd1c4e72.gif` |

`urlHash12` = `sha1(url).hex.substring(0, 12)`。圖檔 URL 可能跨 lang 不同：不同 URL → 不同 hash → 各自一份檔案；同 URL（hoyowiki 沒做 lang 變體時）→ 自然共用，無重複下載。命名規則同時 cover 兩種情況。

### 6-2. 舊 dev 殘留

`<id>_header.*` 不主動掃描清理，由下次 `resetAll()` → `wipeCacheDirectory()` 自然清除。schema v1 → v2 載入時直接丟棄 `header_img_url` 欄位。

### 6-3. `bumpCacheRevision`

每張 gallery 圖寫完後同樣呼叫，dialog 開著也能 reactive 取到新檔。

### 6-4. GC 不做

URL hash 命名帶 id 前綴；hoyowiki 改版若導致某張舊圖孤兒化，不影響 UI、磁碟成本低。YAGNI。

---

## 7. 邊界與 Log

### 7-1. 邊界情況

| 情況 | 處理 |
|---|---|
| entry 無 `gallery_character` module | `_parseGalleryCharacterModule` 回 null → `galleryByLang[lang]` **不寫入**（避免「抓過但無資料」混淆） |
| `data` 字串非合法 JSON | 同上 + `Logger.warning` |
| `list` 為空、`pic` 為空、兩者皆空 | 視為無 gallery，不寫入 |
| `list[i]` 缺 `id` / `key` / `img` | 整筆 skip + `Logger.warning`，其餘照存 |
| 某張圖 cache 檔下載失敗 | `Image.file` `errorBuilder` 顯示 `SizedBox.shrink()` |
| 只有 `pic`、無 `list` | chip 只顯示「卡片」一個 |
| 只有 `list`、無 `pic` | chip 不顯示「卡片」 |
| 整 entry 在某 lang 完全抓失敗 | `hasHoYoWikiContent` false、物品不可點 |
| 某 lang 反覆抓不到 gallery | 每次 update 都會重抓一次（無 negative cache，YAGNI；觀察成本太高再加） |
| 某 lang 抓回空 icon | `mergeEntry` 採「非空覆寫」策略，保留既有 icon URL 避免可點性突然丟失 |

### 7-2. Logger 命名（依 CLAUDE.md「新功能要埋 log」規範）

| Logger | 等級 | 內容範例 |
|---|---|---|
| `gacha.hoyowiki` | warning | `'gallery data parse failed id=$id lang=$lang err=...'` |
| `gacha.hoyowiki` | warning | `'gallery item missing fields id=$gid key=$key img=$img'` |
| `gacha.hoyowiki` | info | `'entry id=$id lang=$lang icon=true gallery=true pic=true list=4'` |
| `gacha.hoyowiki.notifier` | fine | `'merge gallery id=$id lang=$lang has=true'` |
| `gacha.hoyowiki.detail` | warning | `'gallery image errorBuilder id=$id gid=$gid'` |
| `gacha.hoyowiki.storage` | info | `'migrate v1 → v2: $n entries reset (header_img_url dropped)'` |

URL 一律經 `sanitizeUrl(...)` 才寫入；uid/lang/id 本身非敏感原樣記錄。

### 7-3. Update 進度顯示

`FetchingHoYoWiki` 三階段（`searching` / `fetchingEntries` / `downloading`）**結構不變**：
- entry 階段 `totalCount` 變大（per-lang）。
- download 階段每 entry 圖檔數從 2 → 1 (icon) + N×gallery，數字明顯增大；既有 UI 顯示 `done/total` 沿用。
- 文案不需動。

---

## 8. 測試

### 8-1. Unit tests

| 對象 | 案例 |
|---|---|
| `_parseGalleryCharacterModule` | 正常 / 無 component / `data` 非合法 JSON / `list` 空 / `pic` 空 / `list[i]` 缺 `id`、`key`、`img` 各情境 / 多個 components 只一個是 gallery_character |
| `HoYoWikiIndexStorage` | v2 round trip；v1 載入後 `galleryByLang` 為空、舊 `header_img_url` 被丟棄、`icon_url` 與 `search` / `menu_ids` 保留 |
| `hoyowikiGalleryCacheFile` | 同 URL → 同檔名；不同 URL → 不同 hash；`.gif` / `.png` / 無副檔名 / 帶 query string 各情境 ext 推導 |
| `hoyowikiIconCacheFile` | 既有規則維持 |
| `HoYoWikiFetcher.fetchEntryPage` | mock http；`X-Rpc-Language` header 必送且值正確；retcode != 0 拋 `ApiErrorException`；gallery 解析正確、缺 module 時 `gallery == null` |

### 8-2. Widget tests（`GachaItemDetailDialog`）

| 案例 | 驗證點 |
|---|---|
| list 3 張 + pic | chip 列 4 個（順序：list 0/1/2、卡片）、預設選 chip 0、圖片為 list[0] |
| 點 chip 1 | 圖片切到 list[1]、imgDesc HTML render（含段落） |
| `imgDesc` 空字串 | 描述區整塊不繪 |
| pic 缺 | 卡片 chip 不繪 |
| list 缺 | 只顯示卡片 chip |
| 名稱超長 | 既有 `maxLines: 2 + ellipsis` 不破版 |
| tearDown | `imageCache.clear()` + `imageCache.clearLiveImages()`，依 memory `project_image_cache_cross_test_race` 避免 Linux CI 圖檔 codec race |

### 8-3. Repository / state tests

| 案例 | 驗證點 |
|---|---|
| 同 id 兩 lang 命中 | `entryTodo` 含兩筆 `(id, lang)`，分別發 `fetchEntryPage` |
| `mergeEntry` | 既有 lang gallery 不被覆蓋；新 lang 寫入；icon 從 fetched 取最新 |
| `needRefetchEntry` per-lang | `galleryByLang[lang]` 不存在 → true；存在 → false |
| download 階段去重 | 跨 lang 同 URL 只 enqueue 一次（透過 URL set） |

### 8-4. 提交前品質檢查（CLAUDE.md 強制）

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

任一失敗就先修，禁用 `--no-verify`。

---

## 9. 套件導入

依 user rules（context7），實作前先用 `ctx7` 查 `flutter_html` 最新版（與 Flutter 3.x 相容），再加進 `pubspec.yaml`。HTML entity decode（`&amp;` → `&`）若 `flutter_html` 已內建則不需另引 `html_unescape`。

新增 cache hash helper 需要 `crypto` 套件（sha1）。若 `pubspec.yaml` 尚未引入則一併加入。

---

## 10. 變更清單（檔案層級）

| 檔案 | 變更 |
|---|---|
| `pubspec.yaml` | 加 `flutter_html`、（必要時）`crypto` |
| `lib/l10n/app_zh.arb` | 加 `galleryCardLabel` |
| `lib/l10n/app_*.arb` | 翻譯（走 Crowdin） |
| `lib/services/hoyowiki_fetcher.dart` | `fetchEntryPage` 加 lang、解 gallery；`HoYoWikiEntryFetched` 結構改 |
| `lib/services/hoyowiki_index.dart` | `HoYoWikiEntry` 重構（移除 header、加 gallery）；新增 `HoYoWikiGalleryData` / `HoYoWikiGalleryItem`；新增 `hoyowikiIconCacheFile` / `hoyowikiGalleryCacheFile`；移除 `HoYoWikiImageKind` 與 `hoyowikiCacheFile`；storage save/load 改 v2 schema 並處理 v1 載入 |
| `lib/state/hoyowiki_index.dart` | `setEntry` → `mergeEntry`（per-lang merge） |
| `lib/state/gacha_repository.dart` | `entryTodo` 改 `Set<({String id, String lang})>`；worker 帶 lang 呼叫 fetchEntryPage；`needRefetchEntry` per-lang；`enqueueDownloadsForEntry` 改走 gallery URL set 去重 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | content 重寫為 chip + 圖 + flutter_html desc；`hasHoYoWikiContent` 改寫 |
| `test/services/hoyowiki_fetcher_test.dart` | 新增 fixture 與案例 |
| `test/services/hoyowiki_index_test.dart` | v1/v2 schema 案例 |
| `test/state/hoyowiki_index_test.dart` | mergeEntry 案例 |
| `test/state/gacha_repository_test.dart` | per-lang entryTodo / download dedupe 案例 |
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | chip + 描述 + tearDown ImageCache 案例 |

---

## 11. 風險與緩解

| 風險 | 緩解 |
|---|---|
| 多 lang fetch 讓 update 時間明顯變長 | 既有 `entryConcurrency = 8` worker pool 已涵蓋；download 階段以 URL 去重，碰巧跨 lang 相同的 URL 不會重抓 |
| 同 entry 多 lang 都下載一整組 gallery 圖（若 hoyowiki 對每個 lang 都生不同 URL） | 接受成本：圖檔 URL 是否跨 lang 不同由 hoyowiki 決定，我方無法判斷該 URL 是否「真的需要 lang 變體」，照單下載最安全；磁碟成本可接受、CDN 流量由使用者觸發 update 控制 |
| `flutter_html` 套件大 / 風格不一致 | 限制 dialog 內 desc render scope（單一 widget）；只用預設樣式，不暴露 css 客製化 |
| HoYoWiki 後續若改 `gallery_character` 結構 / id 字串 | parse 邏輯集中在 `_parseGalleryCharacterModule`，失敗回 null 不打斷整體 update；warning log 帶 id 方便定位 |
| 同 id 反覆抓不到 gallery（API 暫時 down 或 entry 真無此模組）每次 update 重抓 | 觀察後再決定是否加 negative cache（`galleryByLang[lang] = null` sentinel 或記 `fetchedAt` per-lang） |

---

## 12. 不在範圍內（已明確 out）

- 舊 `<id>_header.*` 快取的主動清理。
- Negative cache（「該 lang 真的沒 gallery」記號，避免每次 update 都重抓）。
- chip 鍵盤導航 / 左右箭頭 / PageView swipe。
- gallery 圖點擊放大 / lightbox。
- gallery cache GC（孤兒檔案清理）。
- 描述區字體 / 顏色客製化。
- `record.lang` 的正規化或映射（直接傳遞給 API header）。
