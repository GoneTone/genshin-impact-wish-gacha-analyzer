# HoyoWiki 物品 icon — Design Spec

**日期**：2026-05-23
**範圍**：祈願記錄表格、時間軸（直/橫）、分享圖在物品名稱前顯示對應 icon
**範圍排除**：頌願（odes，gachaType `2000`/`1000`）不顯示 icon、不顯示 placeholder

## 目標

抓取 HoyoLab Wiki API 取得物品的 `entry_page_id` 與圖片 URL，將 icon 嵌入既有顯示物品名稱的所有 UI 點。

## 非目標（YAGNI）

- 不在現階段 UI 顯示 `header_img_url` 大圖（已下載並 cache 起來，等後續 UI 任務再消費）
- 不提供 settings toggle 關閉本功能（之後有需求再加）
- 不做物品詳情頁／hover 預覽
- 不做圖檔 GC（cache 永久累積；之後若有人抱怨磁碟再加 cleanup 路徑）

## 資料儲存

### `<applicationSupportDirectory>/gacha_data/hoyowiki_index.json`

跨 UID 共用，避免多帳號重抓同一個物品。

```json
{
  "version": 1,
  "search": {
    "<lang>::<name>": "<hoyowiki_id>"
  },
  "entries": {
    "<hoyowiki_id>": {
      "icon_url": "https://...",
      "header_img_url": "https://...",
      "fetched_at": "2026-05-23T08:00:00Z"
    }
  }
}
```

**寫入規則**

| 場景 | 行為 |
|---|---|
| `search` 成功命中（name 完全 match + `sub_menus[0].id ∈ {2,4}`） | 寫 `search[lang::name] = id` |
| `search` 結果無 match / sub_menu 不對 / retcode != 0 / 網路錯 | 不寫；下次更新重試 |
| `entry_page` 成功（retcode == 0） | 寫 `entries[id] = {icon_url, header_img_url, fetched_at}`，URL 可能為空字串 |
| `entry_page` 失敗 / retcode != 0 / 網路錯 | 不寫；下次更新重試 |
| 任一 URL 為空字串 | 照寫，但下次更新仍會視為 incomplete 並重抓 |

**`fetched_at`** 僅供 debug，不參與邏輯。

### `<applicationSupportDirectory>/hoyowiki_cache/`

圖檔本地快取，檔名 `<hoyowiki_id>_icon.<ext>` 與 `<hoyowiki_id>_header.<ext>`。`<ext>` 從各自 URL extension 推導，失敗 default `.png`。下載失敗不寫檔，下次重試。icon 與 header 兩個下載彼此獨立，其中一個失敗不影響另一個。

### `<uid>.json` 與 `GachaRecord` schema

**零變更**。所有 hoyowiki 相關資料都在 `hoyowiki_index.json`，沿用既有 fetch / merge / save 流程。

## 服務層

### `lib/services/hoyowiki_index.dart`

```dart
class HoyoWikiIndex {
  HoyoWikiIndex({
    required this.searchMap,   // "<lang>::<name>" -> hoyowiki_id
    required this.entries,     // hoyowiki_id -> HoyoWikiEntry
  });

  /// "(name, lang)" -> hoyowiki_id；無對應回 null。
  String? lookupId(String name, String lang);

  /// hoyowiki_id -> HoyoWikiEntry；無對應回 null。
  HoyoWikiEntry? lookupEntry(String id);
}

class HoyoWikiEntry {
  final String iconUrl;
  final String headerImgUrl;
  final DateTime fetchedAt;
}

class HoyoWikiIndexStorage {
  HoyoWikiIndexStorage(this.baseDir);  // 同 GachaStorage.baseDir
  Future<HoyoWikiIndex> load();
  Future<void> save(HoyoWikiIndex index);
  // 沿用 GachaStorage._atomicWrite pattern
}
```

### `lib/services/hoyowiki_fetcher.dart`

```dart
class HoyoWikiFetcher {
  HoyoWikiFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.timeout = const Duration(seconds: 10),
  });

  /// keyword + lang 走 search API；命中且 sub_menu id ∈ {2,4} 回 id；
  /// 無 match 回 null；retcode != 0 或 HTTP error 走 throw。
  Future<String?> searchEntryId({
    required String name,
    required String lang,
    required http.Client client,
  });

  /// id 走 entry_page API；retcode != 0 或 HTTP error 走 throw。
  /// 兩個 URL 都可能空字串。
  Future<HoyoWikiEntryFetched> fetchEntryPage({
    required String id,
    required http.Client client,
  });

  /// GET 圖檔回 bytes；任何失敗回 null（caller 不寫檔）。
  Future<Uint8List?> downloadImage(String url, http.Client client);
}

class HoyoWikiEntryFetched {
  final String iconUrl;
  final String headerImgUrl;
}
```

**Headers**（search）：

```
Referer: https://wiki.hoyolab.com/
X-Rpc-Language: <lang from GachaRecord.lang，pass-through 不轉換>
X-Rpc-Wiki_app: genshin
```

**Endpoints**：

- search：`https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/search?keyword=<urlencoded name>`
- entry_page：`https://sg-act-public-api-static.hoyolab.com/hoyowiki/genshin/wapi/entry_page?entry_page_id=<id>`（static 端點不需 headers）

**search 命中規則**：走 `data.list[]`，找**第一筆** `name == 輸入 name` 且 `menu.sub_menus[0].id ∈ {2, 4}`。

**Logging**（命名空間 `wish.hoyowiki`）：

```dart
final _log = Logger('wish.hoyowiki');
_log.info('search name=$name lang=$lang hit=$id');
_log.warning('search miss name=$name lang=$lang');
_log.info('entry id=$id icon=${icon.isNotEmpty} header=${header.isNotEmpty}');
_log.warning('fetch failed name=$name lang=$lang err=$e');
```

uid 不出現於此 logger，name / lang 不視為敏感資料。

## Update Pipeline 整合

### 新 progress class（`lib/state/update_progress.dart`）

```dart
class FetchingHoyoWiki extends UpdateProgress {
  const FetchingHoyoWiki({required this.doneCount, required this.totalCount});
  final int doneCount;
  final int totalCount;
}
```

### `GachaRepository._runUpdate` 整合點

現有流程：

```
Preparing → WaitingForCapture → FetchingBanner(各 banner) → UpdateCompleted
```

新流程：

```
Preparing → WaitingForCapture → FetchingBanner(各 banner) 
  → FetchingHoyoWiki(N/M)  ← 新階段
  → UpdateCompleted
```

**FetchingHoyoWiki 階段邏輯**（位於 `_fetchAllBanners` 全部 banner 成功跑完並 `storage.save(newData)` 之後）：

```
1. index = await hoyowikiStorage.load()
2. 收集 unique work items：
   - searchTodo: ∀ UID ∀ 祈願類 record（gachaType ∈ {301,302,500,200,100}），
                 (name, lang) 在 index.search 沒對應的
   - entryTodo:  從 index.search 的 ids ∪ 本次 search 新得 id，
                 在 index.entries 沒對應或 icon_url / header_img_url 任一為空的
   - downloadTodo: ∀ entry.icon_url 非空 且 icon cache 檔不存在 → (id, kind=icon, url)
                   ∀ entry.header_img_url 非空 且 header cache 檔不存在 → (id, kind=header, url)
3. total = searchTodo.length + entryTodo.length + downloadTodo.length
4. done = 0
5. for item in [...searchTodo, ...entryTodo, ...downloadTodo]:
     try:
       run item（searchEntryId / fetchEntryPage / downloadImage）
       若 search 命中或 entry 抓到 → 更新 index 並 atomic save 一次
       若 download 成功 → 寫圖檔
     catch ApiErrorException / http.ClientException / 其他:
       log warning，繼續下一個
     done++
     state = state.copyWith(progress: FetchingHoyoWiki(done, total))
     await Future.delayed(rateLimit)  // 600ms throttle
     if (!ref.mounted) return
     if (_cancelTriggered) return
6. state = state.copyWith(progress: UpdateCompleted(...))
```

**順序保證**：searchTodo 跑完才知道哪些新 id 要加進 entryTodo；entryTodo 跑完才知道哪些 cache 要下載。實作時可動態 append（worklist 是 mutable queue）。

**失敗隔離**：FetchingHoyoWiki 整段包外層 try/catch，任何 exception 都被吞掉，UpdateCompleted 仍正常顯示。`failedBanners` 不受 hoyowiki 影響。

**取消**：複用既有 `_cancelTriggered` + `CancellableHttpClient`。取消後階段早退，已寫入的 index 與圖檔保留。

### Providers（`lib/state/gacha_repository.dart`）

新增：

```dart
final hoyowikiIndexStorageProvider = Provider<HoyoWikiIndexStorage>((ref) {
  throw UnimplementedError('hoyowikiIndexStorageProvider must be overridden in main()');
});

final hoyowikiFetcherProvider = Provider<HoyoWikiFetcher>(
  (ref) => HoyoWikiFetcher(),
);
```

`main.dart` 用 `overrideWithValue` 注入 storage（baseDir 與 `gachaStorageProvider` 共用 `<appSupport>/gacha_data/`）。

## 顯示層

### 新元件 `lib/widgets/wish_item_icon.dart`

```dart
class WishItemIcon extends ConsumerWidget {
  const WishItemIcon({
    super.key,
    required this.record,
    required this.size,
  });

  final GachaRecord record;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. 頌願（gachaType ∈ {2000, 1000}）直接 return SizedBox.shrink()
    // 2. lookup chain：
    //    index = ref.watch(hoyowikiIndexProvider)
    //    id = index.lookupId(record.name, record.lang)
    //    entry = id == null ? null : index.lookupEntry(id)
    //    iconUrl = entry?.iconUrl
    //    cacheFile = iconUrl != null && iconUrl.isNotEmpty
    //        ? hoyowikiCacheFile(id)
    //        : null
    // 3. cacheFile 存在 → Image.file(...)
    // 4. 任何一步 miss → _Placeholder(rank, size)
  }
}
```

### `_Placeholder`

- 固定 `size × size`，圓角 4
- 底色 `rankAccent.withValues(alpha: 0.18)`（5★ / 4★ / 3★ 對應 `tokens.fiveStar / fourStar / textMuted`）
- 邊框 1px solid 同色 40% alpha
- **不放 fallback icon**（簡潔；避免暗示「真實 icon 是這個」）

### 插點

| 元件 | 位置 | size |
|---|---|---|
| `SortableTable._Row` | 名稱欄 Text 前 | 20 |
| `TimelineVertical._EntryRow` | 名稱 Text 前內聯 | 16 |
| `TimelineHorizontal._EntryColumn` | `Text(entry.name)` 上方 | 20 |
| `ShareCard`（分享圖） | 對應名稱前 | 20（與表格一致） |

**對齊**：表格 / 時間軸用 `Row(crossAxisAlignment: CrossAxisAlignment.center)` + `SizedBox(width: 6)` 隔開 icon 與文字。

### Share image sync pipeline 處理

`share_image_renderer.dart` 是 sync flush pipeline，不能 `Image.file` async load。流程：

1. share 觸發時，caller 先 `await preloadHoyoWikiImages(records)`：
   - 收集所有要繪的 record 的 `(hoyowiki_id, cacheFile)`
   - 對每個檔 `await ui.instantiateImageCodec` 解成 `ui.Image`
   - 包成 `Map<String, ui.Image>` 透過 `InheritedWidget`（`PreloadedHoyoWikiImages`）注入 render tree
2. ShareCard 內 `WishItemIcon`（或專用 share 版）走 sync lookup：
   - 拿 record 的 hoyowiki_id → 從 InheritedWidget 拿 `ui.Image`
   - 用 `RawImage` 同步繪
   - 沒拿到 → 直接畫 `_Placeholder`
3. caller 在 render 結束後 dispose 所有 `ui.Image`

預載階段不發網路 IO，只 decode 已存在的 cache 檔；缺 cache 的就走 placeholder（不延誤 share）。

## i18n

新增 ARB key：

```
"updateProgressFetchingIcons": "補齊物品圖示 {done}/{total}"
```

`zh.arb`（繁中主來源）先填，其他語言 Crowdin pipeline 處理。

## 測試計畫

### 單元測試

**`test/services/hoyowiki_index_test.dart`**：

- load 缺檔 → 空 index
- save → load roundtrip 保留 search / entries / fetched_at
- lookupId 命中 / 未命中
- lookupEntry 命中 / 未命中
- atomic write 不留 `.tmp` 殘檔

**`test/services/hoyowiki_fetcher_test.dart`**（用 `http.MockClient`）：

- search 命中（name match + sub_menu id=2）→ 回 id
- search 命中（sub_menu id=4）→ 回 id
- search miss（name 不 match）→ 回 null
- search miss（sub_menu id 是其他值）→ 回 null
- search retcode != 0 → throw `ApiErrorException`
- search Headers 三個都正確帶入
- entry_page 兩個 URL 都有 → 都回
- entry_page icon_url 為空字串 → 照回空
- entry_page header_img_url 為空字串 → 照回空
- entry_page 兩個都空字串 → 都回空
- entry_page retcode != 0 → throw `ApiErrorException`
- downloadImage 200 OK → 回 bytes
- downloadImage 404 → 回 null

### 整合測試

**`test/state/gacha_repository_hoyowiki_test.dart`**：

- update 全跑完進入 FetchingHoyoWiki 階段（progress class 正確 emit）
- hoyowiki 階段 throw → UpdateCompleted 仍正常 emit、`failedBanners` 不變
- 跨 UID worklist 去重（兩個 UID 都有「胡桃 zh-tw」→ 只 search 一次）
- 已 search 過的不再重 search
- 已 entry 過且兩 URL 非空的不再重 entry
- entry 任一 URL 空字串 → 下次重 entry
- 取消傳遞（cancelPreparing 在 FetchingHoyoWiki 中 → 階段早退）
- 頌願 record 完全不進 worklist

### Widget 測試

**`test/widgets/wish_item_icon_test.dart`**：

- 空 index → `_Placeholder`
- 有 hoyowiki_id 但無 entry → `_Placeholder`
- 有 entry 但 cache 檔不存在 → `_Placeholder`
- 完整 chain（index + cache 檔在）→ `Image.file`
- 頌願 gachaType → `SizedBox.shrink`

### 不測

- 真實 HoyoLab API 連線（用 MockClient）
- 圖檔 byte 內容
- share image renderer 端到端（沿用既有測試覆蓋；新增的 `preloadHoyoWikiImages` 單獨單元測即可）

## 手動驗證 checklist

1. 全新版本初次安裝、既有資料存在 → 點更新，watch progress 出現「補齊物品圖示 N/M」階段
2. icon 出現在祈願記錄表格、直/橫時間軸、分享圖
3. 頌願 banner（gachaType 2000 / 1000）的列**不顯示 icon 也不顯示 placeholder**
4. 拔網路啟動 app → 既有 cache 仍可顯示 icon
5. 用假名稱（wiki 無收錄）測試 → 該筆永遠 placeholder，下次更新仍會 retry（log 看到 search miss）
6. 取消 update 在 FetchingHoyoWiki 階段時 → 已寫入 index / 圖檔保留，下次更新可接續
7. `hoyowiki_cache/` 目錄下同時出現 `<id>_icon.<ext>` 與 `<id>_header.<ext>`（除非該 entry 的對應 URL 為空）

## Out of scope（明確排除）

- HoyoWiki 物品詳情 hover / click 預覽
- 5★ / 4★ 物品的特殊樣式（除了既有顏色標示）
- 圖檔 GC / cleanup（cache 永久累積，未來有需求另案）
- header_img_url 對應大圖的顯示與下載
- HoyoLab API rate limit 動態退避（沿用既有 fetcher 模式即可，極端情況下 600ms throttle 已足）
- settings toggle 關閉本功能
- 任何消費 header 大圖的 UI（本任務只負責把它 cache 起來）
