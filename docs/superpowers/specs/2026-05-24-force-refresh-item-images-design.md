# 設定頁 — 強制重新抓取所有物品圖片(Force Refetch HoyoWiki Images)

- 日期:2026-05-24
- 狀態:Spec(待 plan)
- 分支起點:`feat/hoyowiki-item-image`

## 1. 目標與動機

提供使用者在「設定頁 → 資料管理」區塊一個按鈕,可一次性把 HoyoWiki 物品圖片(角色 icon / header、武器 icon / header)的本機快取與索引清空,並重新從所有 UID 祈願紀錄的物品集合中重抓所有圖檔。

使用情境:HoyoWiki 換新版 icon / 本機 cache 檔損壞 / 索引髒掉 / 使用者單純想刷新。

## 2. 高階決策(設計階段確認)

| 項目 | 決定 |
|---|---|
| 重抓範圍 | 全部砍掉重來:清空 `hoyowiki_index.json` 與 `hoyowiki_cache/` 目錄,從 search 階段重跑 |
| 物品來源 | 所有 UID 祈願紀錄聯集後 `(name, lang)` 去重 |
| 確認 UX | 一般 `AlertDialog`(Cancel / Confirm)|
| 進度 UI | 復用 `UpdateProgressDialog` + `FetchingHoyoWiki` state,支援取消 |
| 空紀錄處理 | Button disabled + tooltip 顯示原因 |
| 擺放位置 | `settings_page.dart` 的 `_DataManagement` 區塊 |
| 並行控制 | 與「更新祈願」共用 `state.progress` slot,雙向互斥 |
| 實作方案 | 方案 A — 在 `GachaRepository` 新增方法,抽既有 `_fetchHoyoWiki()` 為 helper 複用 |
| i18n 起手語系 | `lib/l10n/app_zh.arb`(中文定稿後其他語系跟著翻)|

## 3. 架構與責任分配

### 3.1 不變的部分

- `gachaRepositoryProvider` 仍是 `state.progress` 的單一來源,UI 兩處按鈕(更新祈願、重抓圖片)同時靠它判斷 disabled。
- `hoyowikiIndexStorageProvider` / `hoyowikiCacheDirProvider` / `hoyowikiFetcherProvider` 不變。
- `FetchingHoyoWiki` state 與 `UpdateProgressDialog` 的三 phase 渲染(searching / fetchingEntries / downloading)沿用,UI 完全不改。
- `bumpCacheRevision()` 觸發 UI 重讀 cache 檔的機制不變,沿用每張下載完即 bump 的頻率。

### 3.2 變動點

**`lib/services/hoyowiki_index.dart`(`HoyoWikiIndexStorage`)— 新增**
- `Future<void> clearAll()`:清空記憶體 `searchMap` / `entries` / `menuIds` 三個 map,把 json 檔覆寫為空殼。
- `Future<void> wipeCacheDirectory()`:刪除 `hoyowiki_cache/` 目錄底下所有檔案並重建空目錄。

**`lib/state/hoyowiki_index.dart`(`HoyoWikiIndexNotifier`)— 新增**
- `Future<void> resetAll()`:序列呼叫 `storage.clearAll()` → `storage.wipeCacheDirectory()` → `bumpCacheRevision()`,作為對外的單一入口避免呼叫方拼錯順序。

**`lib/state/gacha_repository.dart`(`GachaRepository`)— 新增 + 重構**

- 抽 private helper:
  ```dart
  Future<void> _runHoyoWikiPipeline({
    required List<({String name, String lang})> pairs,
  });
  ```
  - 把現有 `_fetchHoyoWiki()` 內三階段(search / fetchEntries / downloadImages)邏輯搬入,**保留**現有的進度回報、`checkCancel` 檢查點、HTTP client 共享、rate-limit、單筆 try/catch 與 Logger 行為。
  - helper 內部從 `hoyowikiIndexStorageProvider` 讀當下 index 狀態判斷哪些 pair / entry 該 search / fetchEntry / download;不額外吃 `existingHoyowikiIds` 參數(讓 storage 自己當 single source of truth)。

- `_fetchHoyoWiki()` 改為「組 pairs from current update batch → 呼叫 helper」的薄殼。
- `debugRunHoyoWikiOnly()` 同步薄殼化(順手收乾,屬於服務當前 goal 的清理)。

- 新增公開方法:
  ```dart
  Future<void> forceRefetchAllHoyoWikiImages();
  ```
  流程見 §4 資料流。

**`lib/pages/settings_page.dart`(`_DataManagement`)— 新增按鈕**
- 沿用既有「危險紅 `FilledButton.icon`」風格(對齊「清除全部資料」按鈕)。
- 排序:匯出 → 匯入 → **強制重抓物品圖片** → 清除當前帳號 → 清除全部(放在較不可逆的清除操作之前)。
- `enabled = state.progress == null && hasAnyGachaRecord`。
- tooltip:
  - 進行中 → 沿用既有「正在更新中」訊息 key(plan 階段確認既有有哪一個 key 就用哪個,不新增)。
  - 無紀錄 → 新 key `settingsRefetchHoyoWikiImagesEmpty`。

**祈願紀錄存在性查詢**
- 沿用 `gacha_repository.dart` 或對應 DAO 既有「全帳號是否有任何 record」query;若無就抽 `Future<bool> hasAnyGachaRecord()` 放在同層,settings 頁不直接寫 SQL。

### 3.3 i18n 新增 keys(以 `lib/l10n/app_zh.arb` 為主檔)

- `settingsRefetchHoyoWikiImagesTitle`:按鈕標籤。
- `settingsRefetchHoyoWikiImagesEmpty`:無紀錄狀態的 tooltip。
- `confirmRefetchHoyoWikiTitle`:確認 dialog 標題。
- `confirmRefetchHoyoWikiBody`:確認 dialog 內容(說明會清空快取、會打 HoyoWiki API、可能耗流量)。
- 嚴重 IO 失敗訊息 key:`updateFailedWipeHoyoWikiCache`(對應 `UpdateFailed.messageKey`)。

中文版定稿後,翻其他 6 個語系(en、ja、ko、zh_CN、pt、ru),術語以 `docs/術語表.md` 為準。`updateProgressHoyoWikiSearching/FetchingEntries/Downloading` 沿用不動。

## 4. 資料流

### 4.1 正常完整路徑

```
[使用者] 點「強制重抓物品圖片」
  → [settings_page] 檢查 state.progress == null && hasAnyGachaRecord
  → showDialog(AlertDialog 確認) → 使用者按「確認」
  → unawaited(forceRefetchAllHoyoWikiImages())
    + showDialog(UpdateProgressDialog)  // 後端流程獨立於 dialog lifecycle

[GachaRepository.forceRefetchAllHoyoWikiImages]
  1. 防呆:if (state.progress != null) return
  2. _activeCancellable = HttpClient(); _cancelTriggered = false
  3. emit progress = Preparing
     Logger('wish.hoyowiki.refetch').info('start, totalUids=N')
  4. await hoyowikiIndexNotifier.resetAll()
     Logger.info('index+cache wiped')
  5. final pairs = await _collectAllPairsFromAllUids()
     Logger.info('aggregated pairs=N')
  6. await _runHoyoWikiPipeline(pairs: pairs)
     ├─ phase: searching        → emit FetchingHoyoWiki(searching, done/total)
     ├─ phase: fetchingEntries  → emit FetchingHoyoWiki(fetchingEntries, ...)
     └─ phase: downloading      → emit FetchingHoyoWiki(downloading, ...)
        每筆下載完 → storage.upsertCacheFile + bumpCacheRevision
  7. emit progress = UpdateCompleted
     Logger.info('refetch done, downloaded=M, skipped=K, failed=L')
  8. finally: _activeCancellable = null; _cancelTriggered = false

[UpdateProgressDialog] 監聽到 UpdateCompleted → 自動 close
[settings_page] showSnackBar(成功訊息)
```

### 4.2 取消路徑

```
使用者在進度 dialog 按「取消」
  → [GachaRepository.cancel] _cancelTriggered = true; _activeCancellable?.close()
  → [_runHoyoWikiPipeline] 下一個 checkCancel() 早退
  → [forceRefetchAllHoyoWikiImages] catch cancel
     → emit progress = null
     → Logger.warning('refetch cancelled at phase=X, done=Y/Z')
```

取消後 index 與 cache 已被清空無法復原,已下載部分保留;**不會出現新舊圖混雜**(舊已全清)。下次任意 wish update 觸發 `_fetchHoyoWiki` 時 `needRefetchEntry` 會自動補抓剩下缺的。Self-heal。

### 4.3 空紀錄路徑

UI 層 `hasAnyGachaRecord == false` 已 disable;repository 內 `if (pairs.isEmpty)` 直接 emit `UpdateCompleted` 並 return(雙重保護)。

### 4.4 並行衝突路徑

兩個按鈕都靠 `state.progress != null` disabled。Race 進入時 repository 入口 `if (state.progress != null) return` 早退。

## 5. 錯誤處理

| 階段 | 失敗類型 | 行為 |
|---|---|---|
| 清檔(`resetAll` / `wipeCacheDirectory`)| `FileSystemException`(防毒鎖檔等)| catch → emit `UpdateFailed(updateFailedWipeHoyoWikiCache)`、Logger.severe 帶**檔名**(脫敏絕對路徑)、**不嘗試半清** |
| Pairs 聚合 | DB 例外 | 沿用既有 DB 例外處理 emit `UpdateFailed` 訊息 key,不新增 |
| Search / Entry API | 401/403/5xx / 網路斷線 | 沿用 `_fetchHoyoWiki` 單筆 try/catch + Logger.warning,跳過繼續 |
| 全域 HTTP | client dispose、`SocketException` | 外層 catch → emit `UpdateFailed` 沿用既有訊息 key |
| 下載 / 寫檔 | 個別 GET 或寫檔失敗 | Logger.warning,該筆跳過,index 不寫入該檔 |
| Index 寫入 | json 寫失敗 | Logger.severe,當筆跳過,流程繼續 |
| 取消後重啟 app | 半完成狀態 | 下次 wish update 自動補(`needRefetchEntry` self-heal),不需 recovery |

**設計原則**:三階段中任一筆失敗,整個流程仍 emit `UpdateCompleted`(與既有「更新祈願」一致),靠 self-heal 補。只有「清檔」與「全域 HTTP」級的系統性失敗才 emit `UpdateFailed`。

## 6. Logger 命名

依專案規則對齊既有樹 `wish.hoyowiki.refetch.*`,URL 一律走 `sanitizeUrl`:

- `start` — `pairs=N, totalUids=M`
- `wiped` — `(index+cache cleared)`
- `phase` — `phase=searching|fetchingEntries|downloading, done=N/M`
- `itemFailed` — `phase=X, name=<name>, lang=Y, retcode=Z`(name 為公開角色名,不脫敏)
- `cancelled` — `phase=X, done=N/M`
- `done` — `pairs=N, downloaded=M, skipped=K, failed=L`
- `wipeFailed` — Logger.severe,帶檔名(脫敏路徑)

## 7. 測試策略

### 7.1 Unit — Index storage / notifier

於 `test/services/hoyowiki_index_test.dart`:
1. `clearAll()` 後三個 map 為空、json 為空殼。
2. `wipeCacheDirectory()` 刪光既有檔且重建空目錄。
3. `clearAll()` 在 json 不存在時不爆。
4. `wipeCacheDirectory()` 在目錄不存在時不爆。

於 `test/state/hoyowiki_index_test.dart`:
5. `resetAll()` 後 `cacheRevision` 必須遞增。

### 7.2 Repository — `forceRefetchAllHoyoWikiImages`

於 `test/state/gacha_repository_refetch_test.dart`(新檔):
6. **主要路徑**:塞兩個 UID records → 驗證 `clearAll` / `wipeCacheDirectory` 各呼叫一次、fetcher 收到的 pairs 為跨 UID 去重 set、結束 `state.progress == UpdateCompleted`。
7. **空紀錄**:0 records → 不打 fetcher 任一方法,直接 `UpdateCompleted`,無 exception。
8. **互斥早退**:預先 emit 假 progress → 呼叫 → 不動作、不清檔、立刻 return。
9. **取消**:第二張下載時 trigger cancel → `state.progress == null`、後續 fetcher call 未發生、Logger 有 `cancelled` 記錄。
10. **清檔失敗**:`wipeCacheDirectory` 拋 `FileSystemException` → emit `UpdateFailed(updateFailedWipeHoyoWikiCache)`、沒進管線、Logger.severe 有記錄。
11. **抽 helper 不回歸**:沿用既有 `_fetchHoyoWiki()` 相關測試做 regression。

### 7.3 Widget — Settings 按鈕

於 `test/pages/settings_page_refetch_button_test.dart`(新檔):
12. **enabled / disabled 矩陣**:
    | progress | hasAnyGachaRecord | 期望 |
    |---|---|---|
    | null | true | enabled |
    | null | false | disabled + tooltip = `settingsRefetchHoyoWikiImagesEmpty` |
    | 非 null | true | disabled |
    | 非 null | false | disabled |
13. **確認 dialog**:點按鈕 → 出現 AlertDialog → 點「取消」→ repository 方法**未被呼叫**;點「確認」→ repository 方法呼叫一次。
14. **Tooltip 文案**:disabled 狀態 hover 顯示對應 i18n 字串,en + zh 各驗一次。

### 7.4 規則對齊

- 不用 fake_async(本路徑不依賴 wall-clock)。
- DB / 檔案 IO 用真實 in-memory 或 tmp dir。
- `HoyoWikiFetcher`(HTTP boundary)mock。

### 7.5 不寫(YAGNI)

- 個別下載失敗的 widget 級測試(repository 級已覆蓋)。
- i18n key 存在性測試(generated `AppLocalizations` 編譯期會抓)。
- 進度 dialog 渲染測試(沿用既有元件,本功能未改)。

## 8. 驗收標準

- `dart format lib/ test/` 無變動。
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`(含 §7 新增 cases)
- 手動驗收:Settings 頁實際點按鈕走一次完整流程(成功 + 取消 + 空紀錄 disabled),log 匯出對得上 §6 預期節點。

## 9. 不在本 spec 範圍

- 「只清 cache 不重抓」(YAGNI,真要的話以後加)。
- 「重抓單一物品」(YAGNI)。
- 「計算 cache 大小顯示」(YAGNI)。
- 「重抓進度跑背景 + banner 顯示」(已決議:沿用 dialog 互斥)。
- HoyoWiki 以外的圖片(本 spec 僅針對 HoyoWiki `hoyowiki_cache/`)。
