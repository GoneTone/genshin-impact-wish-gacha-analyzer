# HoYoWiki 圖片快取：gallery 改 lazy + 設定頁可見性與手動清除

**日期**:2026-05-27
**Branch**:`feat/hoyowiki-item-detail`（後續會切子 branch）

## 背景

朋友測試後回報「圖片快取太佔容量」。盤點現況：

| 路徑 | 內容 | 單檔規模 |
|---|---|---|
| `<appSupport>/hoyowiki_cache/<id>_icon.<ext>` | 32px 小圖示（祈願列表/直方圖用） | KB 級 |
| `<appSupport>/hoyowiki_cache/<id>_gallery_<sha1Hex12>.<ext>` | 物品詳情圖（gallery 主要是角色原畫、立繪、閒置動作 GIF；武器頁通常無 gallery） | 數 MB |

容量元兇是 **gallery**:`gacha_repository.dart` 的 `enqueueDownloadsForEntry`(L838-874) 在 update 階段就把所有 entry **所有語言** 的 `gallery.picUrl` + `gallery.list[i].imgUrl` 全部批次下載到本地，且永不淘汰。久了 + 物品多 + 多語言 + 動態 GIF，上 GB 不奇怪。目前唯一清除機制是「強制重抓所有物品圖片」這種砍掉整個目錄重抓的暴力選項。

## 目標

1. **治本**:gallery 大圖改 lazy — update 階段不再預下載 gallery，延到「使用者打開物品詳情對話框」時才抓
2. **治標**：設定頁顯示 cache 用量，提供「清除詳情圖快取」按鈕（保留 icon，只刪 gallery)
3. **既有「強制重抓所有物品圖片」按鈕** 搬到新「圖片快取」section，語意上屬於這裡

## Approach

兩條改動同 PR 上，合稱 A+B:

- **A** = 設定頁可見性（用量顯示）+ 手動清除（只清 gallery)
- **B** = gallery 改 lazy(update 不抓，dialog 開才抓）

未採用的方向：**C** = 容量上限 + LRU eviction。原因：A+B 已大幅壓縮容量；LRU 需要追每檔存取時間，複雜度高，YAGNI。

---

## §1 整體流程改動

### 改前

```
update flow
  └─ entry 階段抓回 entry_page metadata（含 gallery URL list)
       └─ 立刻把該 entry 的 icon + gallery picUrl + list[i].imgUrl
          全部跨語言批次下載到 cache  ← 容量元兇
```

### 改後

```
update flow
  └─ entry 階段抓 metadata（不變，gallery URL list 仍存在 index)
       └─ 只下載 icon                ← gallery 完全不在這裡下

open GachaItemDetailDialog(record)
  └─ initState:
       依 record.lang 取出 entry.pageByLang[lang].gallery
       對 picUrl + list[i].imgUrl 平行下載到 cache（已存在的檔跳過）
  └─ 下載過程 chip 列即時顯示，每個 chip 各自 loading / ready / failed
  └─ 完成後與目前體驗一致
```

**核心精神**:gallery URL metadata 仍在 update 時抓進 index（維持「chip 列要顯示哪些圖」的權威來源），但圖檔本身延到 dialog 開啟才取。

### chip 列規則改動

| 項目 | 改前 | 改後 |
|---|---|---|
| chip 列來源 | `existsSync()` 過濾掉本地沒檔的 chip | 列**全部** `gallery.list[i]` + `picUrl` + `iconFile`，本地沒檔的 chip 仍顯示，標籤後不加 loading dot 避免 UI 抖動 |
| 中央大圖 | 直接 `Image.file` | 依該 chip 的下載狀態顯示 `Image.file` / loading spinner / 失敗 placeholder + 重試 |

---

## §2 `GachaItemDetailDialog` 重構細節

### 新狀態欄位

```dart
class _GachaItemDetailDialogState extends ConsumerState<...> {
  int _selectedIndex = 0;
  // 每張 gallery 圖的下載狀態，key 為 cache 檔絕對路徑
  final Map<String, _GalleryLoadState> _loadStates = {};
}

sealed class _GalleryLoadState {}
class _LoadingState extends _GalleryLoadState {}
class _ReadyState extends _GalleryLoadState {
  const _ReadyState(this.file);
  final File file;
}
class _FailedState extends _GalleryLoadState {
  const _FailedState(this.error);
  final Object error;
}
```

### 載入流程

```
initState:
  // hasHoYoWikiContent 已保證 entry + iconFile 存在 → dialog 才會打開
  collect: gallery.picUrl + gallery.list[i].imgUrl  （依 record.lang)
  for each url:
    file := hoyowikiGalleryCacheFile(...)
    if file.existsSync():
      _loadStates[file.path] = _ReadyState(file)
    else:
      _loadStates[file.path] = _LoadingState()
      unawaited(_fetchAndCache(url, file))

_fetchAndCache(url, file):
  try:
    bytes := await fetcher.downloadImage(url, client)
    await file.writeAsBytes(bytes)
    if (mounted) setState: _loadStates[file.path] = _ReadyState(file)
  catch e:
    if (mounted) setState: _loadStates[file.path] = _FailedState(e)
    log.warning('gallery lazy fetch failed url=<sanitized> err=<msg>')

dispose:
  // 不需 cancel — http client 結束時 in-flight 自動斷
  // setState 用 mounted 守
```

### 中央大圖區域

```
依 _loadStates[currentFile.path]:
  _ReadyState  → Image.file(... gaplessPlayback) ← 與現狀一致
  _LoadingState → 等比例 placeholder + CircularProgressIndicator
  _FailedState  → 等比例 placeholder + 錯誤 icon + 「重試」TextButton
                   點重試： _loadStates[path] = _LoadingState; _fetchAndCache(...)
```

### ZoomableImageOverlay 互動

- 只有 `_ReadyState` 才可點開縮放；loading / failed 狀態關閉 `onTap`
- `ZoomableImageOverlay` 本身不需改動

### 並行與 race

- initState 觸發的批次：單一 dialog 僅 5~9 張，直接 `unawaited(_fetchAndCache(...))` 多次平行，讓 http client connection pool 自己管理併發
- dispose race:`if (!mounted) return;` 守 setState。**bytes 仍寫入 cache** — 網路成本已花，寫入幾乎免費，下次開即 ready

---

## §3 Cache 用量計算與設定頁 section

### 3.1 用量 model + provider

`lib/state/hoyowiki_cache_usage.dart`（新檔）:

```dart
@immutable
class HoYoWikiCacheUsage {
  const HoYoWikiCacheUsage({required this.iconBytes, required this.galleryBytes});
  final int iconBytes;
  final int galleryBytes;
  int get totalBytes => iconBytes + galleryBytes;
}

final hoyowikiCacheUsageProvider =
    FutureProvider.autoDispose<HoYoWikiCacheUsage>((ref) async {
  final dir = ref.watch(hoyowikiCacheDirProvider);
  if (!await dir.exists()) {
    return const HoYoWikiCacheUsage(iconBytes: 0, galleryBytes: 0);
  }
  var iconBytes = 0;
  var galleryBytes = 0;
  await for (final e in dir.list()) {
    if (e is! File) continue;
    final base = p.basename(e.path);
    final size = await e.length();
    if (base.contains('_gallery_')) {
      galleryBytes += size;
    } else if (base.contains('_icon.')) {
      iconBytes += size;
    }
  }
  return HoYoWikiCacheUsage(iconBytes: iconBytes, galleryBytes: galleryBytes);
});
```

`autoDispose` → 離開設定頁自動釋放，下次進設定頁重新計算。`await for` + `await length()` 不阻塞 main isolate。失敗（權限等）讓 `FutureProvider` 自然進 `AsyncError`,UI 顯示「無法讀取」。

### 3.2 bytes formatter

`lib/utils/format_bytes.dart`（新檔）— 共用 helper，三段顯示且都保留 1 位小數：

| bytes 範圍 | 顯示 |
|---|---|
| `< 1 MB`(< 1 048 576) | `XXX.X KB` |
| `< 1 GB`(< 1 073 741 824) | `XXX.X MB` |
| `>= 1 GB` | `XXX.X GB` |

（底數用 1024；與作業系統檔案總管習慣一致）

### 3.3 設定頁新 SectionCard

```
┌─ SectionCard(l.settingsImageCache, Icons.image_outlined)
│
│  總計      123.4 MB
│  ├ 小圖示    3.2 MB        ← textSecondary 顏色
│  └ 詳情圖  120.2 MB
│
│  [清除詳情圖快取]  [強制重抓所有物品圖片]   ← Wrap
└─
```

- 數字區用 `ref.watch(hoyowikiCacheUsageProvider).when(...)`:
  - `loading` → 三行都顯示 `l.settingsImageCacheCalculating`(「計算中…」)
  - `error` → 顯示 `l.settingsImageCacheFailed`(「無法讀取快取大小」)
  - `data` → 三行數字（透過 `formatBytes`）
- 「清除詳情圖快取」**新增**(`FilledButton.icon`,`theme.gacha.stateDanger` 紅底）
- 「強制重抓所有物品圖片」**從 `_DataManagement` 整段搬過來**(button + 對應 `_refetchHoYoWikiImages` method)

### 3.4 「清除詳情圖快取」邏輯

```dart
Future<void> _clearGalleryCache(BuildContext ctx, WidgetRef ref) async {
  final l = AppLocalizations.of(ctx)!;
  final usage = ref.read(hoyowikiCacheUsageProvider).valueOrNull;
  final sizeText = usage == null ? '' : formatBytes(usage.galleryBytes);

  // AppDialog 一次點按確認（無 type confirm）— 可逆操作（下次開物品詳情會自動補回），
  // type confirm 留給「重抓」這種會連 icon 都重抓的較重操作。
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (d) => AppDialog(
      title: Text(l.confirmClearGalleryCacheTitle),
      content: Text(l.confirmClearGalleryCacheBody(sizeText)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text(l.actionCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(d).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(d, true),
          child: Text(l.confirmClearGalleryCacheConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final storage = ref.read(hoyowikiIndexStorageProvider);
  await storage.deleteGalleryCacheFiles();
  if (!ctx.mounted) return;
  ref.invalidate(hoyowikiCacheUsageProvider);
  Logger('gacha.hoyowiki.storage').info('user cleared gallery cache');
}
```

新方法 `HoYoWikiIndexStorage.deleteGalleryCacheFiles()`:
- 遍歷 `baseDir`，刪所有 `basename.contains('_gallery_')` 的檔
- **不**動 index JSON — gallery URL metadata 仍在 index，下次開物品詳情可 lazy 重抓
- 失敗（權限等）拋給呼叫方；UI 以 SnackBar 顯示

### 3.5 invalidation 點

| 何時 | 動作 |
|---|---|
| 設定頁打開 | `FutureProvider.autoDispose` 自動初次計算 |
| 「清除詳情圖快取」完成 | `ref.invalidate(hoyowikiCacheUsageProvider)` |
| 「強制重抓所有物品圖片」完成 | 同上 |
| 一般 update / dialog lazy fetch 完成 | **不 invalidate** — autoDispose，使用者離開設定頁後再進必重算 |

### 3.6 「強制重抓所有物品圖片」按鈕在 lazy 後的行為

| 階段 | 改前 | 改後 |
|---|---|---|
| 砍 cache | 整個 `hoyowiki_cache/` 刪 | 不變 |
| search / entry | 全跑 | 不變 |
| download phase 範圍 | icon + 所有語言 gallery 全部下 | **僅 icon**(gallery 改 lazy) |
| `UpdateCompleted.hoYoWikiImagesDownloaded` | 數百~數千 | 僅 icon 張數 |
| 使用者第一次打開物品詳情 | 立即顯示 | 等 1~3 秒下載 gallery |

按鈕標籤 `settingsRefetchHoyoWikiImagesTitle`(「強制重抓所有物品圖片」)**保留不動** — 語意上仍是「丟掉本地全部圖片，從 HoYoWiki 重抓」，只是 gallery 部分採 lazy。`confirmRefetchHoyoWikiBody` 文字需要微調，加一句說明「物品詳情大圖會在你下次打開該物品時自動下載」，避免使用者按了之後覺得「為什麼還是有圖會 loading」。

---

## §4 檔案動線總表 + i18n 全清單 + 測試計畫

### 4.1 新增檔案

| 路徑 | 用途 |
|---|---|
| `lib/state/hoyowiki_cache_usage.dart` | `HoYoWikiCacheUsage` model + `hoyowikiCacheUsageProvider` |
| `lib/utils/format_bytes.dart` | 共用 bytes formatter(KB / MB / GB,1 位小數） |
| `test/state/hoyowiki_cache_usage_test.dart` | provider 測試 — 空目錄 / 只 icon / 只 gallery / 混合 / 不存在的目錄 |
| `test/utils/format_bytes_test.dart` | boundary case(0、1023 B、1024 B、1 MB - 1 B、1 MB、1 GB - 1 B、1 GB、大數） |
| `test/widgets/dialogs/gacha_item_detail_dialog_lazy_test.dart` | dialog lazy — initState 觸發 fetch、loading→ready、failed→retry、dispose race |

### 4.2 既有檔案修改

| 路徑 | 改什麼 |
|---|---|
| `lib/state/gacha_repository.dart` | `enqueueDownloadsForEntry` 移除 gallery enqueue，只留 icon。`_HoYoWikiDownloadItem.isGallery` 欄位若已無人寫入，連同 download phase 判斷一併拿掉 |
| `lib/services/hoyowiki_index.dart` | `HoYoWikiIndexStorage` 新增 `deleteGalleryCacheFiles()` — 遍歷 `baseDir`、刪 `basename.contains('_gallery_')` 的檔（**不**動 index JSON） |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart` | `_loadStates` map 管理。chip 列改成列**全部** known URL（不過濾 existsSync）。中央圖區依 state 顯示 loading / ready / failed-retry |
| `lib/services/hoyowiki_fetcher.dart` | 確認 `downloadImage` 可從 dialog 直接呼叫；若需要把它從 instance method 暴露為 public API |
| `lib/pages/settings_page.dart` | 拆出新 `_ImageCacheSection`（用量顯示 + 清大圖 + 重抓按鈕）。`_DataManagement` 移除「強制重抓」 button 與 `_refetchHoYoWikiImages` method（整段搬遷） |
| `test/state/gacha_repository_test.dart` 系列 | 移除「update flow 應下載 gallery 圖」斷言，改成「只下載 icon」 |
| `test/state/gacha_repository_refetch_test.dart` | `forceRefetchAllHoYoWikiImages` 測試的 `hoYoWikiImagesDownloaded` 期望值改成只 icon 計數 |
| `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` | 既有 sync 行為斷言改成 lazy 流程斷言（chip 列展示時機改變） |

### 4.3 i18n 改動

**規則重述**：無論新增 key 或修改既有 key，所有**非空殼 ARB**（已有實質翻譯內容）都要同步翻譯，空殼 ARB 留給 Crowdin pipeline。Phase 5 開始前用 grep 一個經典 key（如 `confirmRefetchHoyoWikiBody`）確認最終「非空殼」名單。

**新增 key**

| key | zh-TW |
|---|---|
| `settingsImageCache` | 圖片快取 |
| `settingsImageCacheTotal` | 總計 |
| `settingsImageCacheIcons` | 小圖示 |
| `settingsImageCacheGallery` | 詳情圖 |
| `settingsImageCacheCalculating` | 計算中… |
| `settingsImageCacheFailed` | 無法讀取快取大小 |
| `settingsImageCacheClearGallery` | 清除詳情圖快取 |
| `confirmClearGalleryCacheTitle` | 清除詳情圖快取？ |
| `confirmClearGalleryCacheBody`(placeholder `{size}`) | 將刪除約 {size} 的物品詳情圖檔，小圖示快取保留。下次打開物品詳情時會重新下載。 |
| `confirmClearGalleryCacheConfirm` | 清除 |
| `galleryLazyLoadFailed` | 圖片載入失敗 |
| `actionRetry`（若既有沒有就新增） | 重試 |

**修改既有 key 文字**
- `confirmRefetchHoyoWikiBody` — 加一句「物品詳情大圖會在你下次打開該物品時自動下載」(zh-TW 為基準，其他非空殼 ARB 同步翻譯）

### 4.4 測試計畫

**單元 / Provider 測試**
1. `format_bytes` — boundary(0、1023 B、1024 B、1 MB - 1 B、1 MB、1 GB - 1 B、1 GB、大數）
2. `hoyowikiCacheUsageProvider` — 空 / 只 icon / 只 gallery / 混合 / 不存在的目錄

**Widget 測試**
3. dialog initState 觸發 fetch:fake fetcher 驗 `downloadImage` 被呼叫 N 次，N = gallery list URL 數
4. dialog loading → ready 狀態轉換：fake fetcher 回 bytes 後驗 `_ReadyState` + UI 換成 `Image.file`
5. dialog failed → retry:fake fetcher 第一次拋，UI 顯示 retry button，點下後第二次回成功
6. dialog dispose race:fetch 還沒回就 unmount，驗不會 `setState after dispose`（注意 [[project_image_cache_cross_test_race]] — testWidgets 用 tempDir 圖檔時 `tearDown` 要清 `ImageCache`)
7. SettingsPage 新 section:`hoyowikiCacheUsageProvider` `overrideWith` 假資料，驗顯示「總計 / icon / gallery」三行數字
8. 「清除大圖快取」確認 dialog → 觸發 `deleteGalleryCacheFiles` → `invalidate(usageProvider)` → UI 重算

**整合測試 / 既有測試調整**
9. `gacha_repository_test` 系列：update flow 不再 enqueue gallery URL
10. `gacha_repository_refetch_test` 系列：`hoYoWikiImagesDownloaded` 期望值對齊新行為

### 4.5 實作順序

```
Phase 1 — 基礎工具
  ├ format_bytes + test
  └ hoyowikiCacheUsageProvider + test

Phase 2 — Storage layer
  └ HoYoWikiIndexStorage.deleteGalleryCacheFiles + test

Phase 3 — update flow 改動
  └ gacha_repository.dart 拿掉 gallery enqueue
    + 既有 update / refetch test 期望值調整

Phase 4 — Dialog lazy 載入
  └ GachaItemDetailDialog 重構 + 新 widget test
    + 既有 dialog test 期望值調整

Phase 5 — Settings UI + i18n
  ├ 新 _ImageCacheSection（含用量顯示 + 清大圖 + 重抓搬遷）
  ├ i18n 新 key（zh 為基準）
  ├ confirmRefetchHoyoWikiBody 文字改動
  └ 翻譯到所有非空殼 ARB（grep 確認名單）
```

Phase 3 與 Phase 4 **同 commit / 同 PR** 上 — Phase 3 上、Phase 4 沒上會讓 chip 列全消失。Phase 1、2、5 之間順序可換。

### 4.6 風險

| 風險 | 緩解 |
|---|---|
| Phase 3 上、Phase 4 沒上 — gallery chip 全消失 | 同 commit / 同 PR;Phase 4 widget test 守 |
| `Directory.list()` 在大量檔下 jank | `await for`(async stream）不阻塞 main isolate；上千張仍 < 100 ms |
| Lazy fetch 進 dispose race | `if (!mounted) return;` 守 setState;bytes 仍寫入 cache |
| 既有測試 `hoYoWikiImagesDownloaded` 期望值大幅調 | Phase 3 一併調 |
| 跨測試 ImageCache 殘留（testWidgets 載 tempDir 檔） | 比照 [[project_image_cache_cross_test_race]] memory 的 tearDown 清 `ImageCache` 模式 |

---

## 不在範圍內

- 容量上限 + LRU eviction(C 方向）:A+B 已大幅壓縮容量，不必預先做
- icon 本地壓縮 / WebP 重編：32px icon 已是 KB 級，不是元兇
- gallery URL metadata 也改 lazy：過度設計；metadata 屬於 entry_page 一次抓，跟圖檔分開
