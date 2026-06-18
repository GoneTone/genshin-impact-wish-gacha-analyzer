# 手動更新物品詳細資料 — 設計文件

- 日期：2026-06-18
- 狀態：已實作並驗證（含實作後演進：完成訊息語意化、殘留語言清理與統計）

> 本文件已更新為**最終出貨設計**。原始設計只涵蓋「非破壞性重抓 metadata」；實作驗收階段又依使用者回饋追加了兩項：(A) 完成訊息改用本流程專屬語意（不再沿用祈願記錄文案）、(B) 針對性清理「資料語言轉換後殘留的舊語言資料」並在完成訊息統計。姐妹專案可直接參考本文件的完整設計。

## 背景與問題

物品詳細資料（HoYoWiki 的 gallery 清單、描述、tags）由 `GachaRepository._fetchHoYoWiki` 的三階段管線（search → entry → download）抓取，存進 `hoyowiki_index.json`。

這條管線是**增量式**的：`needRefetchEntry` 判定「entry 已存在、menuId 有、該語言 page 也有」就回傳 `false`，不重抓。結果是——**若某物品在 HoYoWiki 後來新增了 gallery 圖（例如新增的立繪），正常更新永遠偵測不到**，因為該語言的 page 早已存在。

設定頁現有的「強制重抓物品圖片」按鈕雖能拿到新資料，但它走 `forceRefetchAllHoYoWikiImages()` → 先 `resetAll()` **清空整個 index 與所有快取圖**，再全部重抓並 eager 下載所有 icon。這是破壞性的、耗時且浪費頻寬。

使用者需要一個**非破壞性**的入口：只重抓 metadata，讓新增的 gallery 圖／頁籤被偵測到，但保留已下載的圖、不 eager 下載新圖；新圖一律維持 lazy，等使用者開啟該物品詳情時才補下載。

## 目標

1. 設定頁新增一顆「更新物品資料」按鈕，點擊後重抓所有物品的 HoYoWiki metadata（非破壞性）。
2. 重抓涵蓋：對先前**沒解析到**的物品重試 search；對**所有已解析**的條目強制重抓 entry 階段（更新 gallery 清單／描述／tags）。
3. 不重抓已下載的圖；icon 僅在本地缺檔時 eager 補下載；gallery 大圖一律維持 lazy。
4. 物品詳情頁的頁籤隨 index 更新自動反映新 gallery 條目；開啟詳情時補下載缺漏的圖。
5. 完成訊息使用**本流程專屬語意**（「已更新 M 個物品的資料」），不沿用祈願記錄流程的「新增 N 筆紀錄」。
6. **針對性清理殘留語言**：移除 index 中已不再被任何記錄使用的語言頁面（資料語言轉換後的殘留），維持非破壞性，並在完成訊息統計清理到的物品數。

## 非目標（YAGNI）

- 不做「只更新逾期條目（依 `fetchedAt` 門檻）」的選擇性更新——「全部已解析條目都重抓」。
- 不改 icon 快取的 key 策略（仍以 id 為 key）；不主動因 icon URL 字串變動而重下 icon。
- 不在詳情頁新增任何 per-item 重抓入口（既有圖片選單的「重抓圖片」已涵蓋單張需求）。
- 既有「破壞性強制重抓」按鈕原樣保留，與新按鈕職責區隔（破壞性 vs 非破壞性）。
- 殘留語言清理**只清 index 內的 `pageByLang` 資料**，不刪 `searchMap`（search hints 很小、保留可加速日後再轉回該語言）、不刪 orphan gallery 快取圖檔（殘留語言的 gallery 是 lazy，多半從未下載；少量 orphan 交給既有「清除詳情圖快取」）。

## 關鍵發現：詳情頁無需改動

`GachaItemDetailDialog.build()`（`lib/widgets/dialogs/gacha_item_detail_dialog.dart`）`watch(hoyowikiIndexProvider)`，且既有的 lazy backfill 對「不在 `_loadStates` 的 chip」逐一檢查：本地有檔 → `_GalleryReady`，缺檔 → `_GalleryLoading` 並排程背景下載。

每次開啟 dialog 都是全新的 `State`、`_loadStates` 為空，因此**每次開啟都會重新檢查所有 gallery chip（含卡片大圖）並補下載缺的**。metadata 更新後，`mergeEntry`（`lib/state/hoyowiki_index.dart`）以 `lang: fetched.page` 覆蓋該語言 page → 新 gallery 條目進入 index → 下次（或開著時）重建即多出新 chip → 缺檔自動 lazy 補下載。

icon 則由 `hasHoYoWikiContent` 把關：icon 檔不存在時物品不可點。故 icon 必須在更新時就補齊（見 icon 策略），與本設計一致；詳情頁本身不處理 icon lazy 下載。

**結論：「頁籤跟著更新」與「開啟詳情時補下載缺圖」由既有機制完整涵蓋，本功能在詳情頁零改動，前提僅是 index 要先被更新。**

## 設計

### 1. 參數化 `_fetchHoYoWiki`（重用既有管線，不造新輪子）

`lib/state/gacha_repository.dart`，最終簽名：

```dart
Future<({int imagesDownloaded, int itemsRefreshed, int staleLangItemsPruned})>
    _fetchHoYoWiki(
  http.Client client, {
  bool forceEntryRefetch = false,
  bool pruneStaleLangs = false,
})
```

- **回傳改為 record**：`imagesDownloaded`（本次成功寫檔的 icon 張數）、`itemsRefreshed`（本次成功重抓 metadata 的**相異物品數**）、`staleLangItemsPruned`（本次清掉殘留語言的相異物品數）。其餘呼叫端只讀 `.imagesDownloaded`，不受影響。
- **search 階段**：不變。`searchTodo` 本來就只收 `lookupId == null` 者，且無負快取——「對先前沒解析到的重試 search」現況已免費滿足。
- **entry 階段**：
  - `forceEntryRefetch == false`：維持現狀，由 `needRefetchEntry` 決定。
  - `forceEntryRefetch == true`：`entryTodo` 納入**所有已解析的 (id, lang)**，略過 `needRefetchEntry`。
  - 注意：search 階段內部「命中後 add 進 entryTodo」那段的 `needRefetchEntry` 守衛**未**特別加 `forceEntryRefetch`——剛 search 命中的 id 其 entry 為 null，`needRefetchEntry(null, ...)` 本就回 true，force 與非 force 行為一致（程式碼內留有 WHY 註解說明）。
  - `itemsRefreshed`：以 `Set<String> refreshedIds` 在每次成功 `mergeEntry` 後 `add(pair.id)`，回傳其 `length`（相異 id，2 個語言的同一物品只算 1）。
- **download 階段**：不變。`enqueueDownloadsForEntry` 只 enqueue icon、且只在 `iconFile.existsSync() == false` 時加入；gallery 完全不在此下載。→ 自動符合「缺 icon 才 eager 下載、gallery 維持 lazy」。
- **殘留語言清理**：`pruneStaleLangs == true` 時，在算出 `allLangs`（所有記錄語言集合）後、建 `entryTodo` 前，呼叫 `indexNotifier.pruneLanguages(allLangs)`，並**以 `allLangs.isNotEmpty` 守衛**避免無記錄時誤清全部；清完重讀 index 快照。`staleLangItemsPruned` = 該呼叫回傳值。
- **early return / 取消 / 互斥 / 進度**（`FetchingHoYoWiki` 三階段）全部沿用既有邏輯；所有 return 點都回傳完整 record（prune 之前的早退點 `staleLangItemsPruned` 自然為 0）。

### 2. 新增 `refreshAllHoYoWikiMetadata()`

`lib/state/gacha_repository.dart`，比照 `forceRefetchAllHoYoWikiImages` 的骨架，**但拿掉 `resetAll()`**（非破壞性）：

1. 互斥檢查（`state.progress != null` / `_isUpdating` → no-op）。
2. emit `Preparing`、建 cancellable client、設 `_activeCancellable`。
3. 呼叫 `_fetchHoYoWiki(cancellable.client, forceEntryRefetch: true, pruneStaleLangs: true)`（不清 index、不清 cache）。
4. 依取消狀態 emit `UpdateCompleted(hoYoWikiImagesDownloaded: result.imagesDownloaded, hoyoWikiEntriesRefreshed: result.itemsRefreshed, hoyoWikiStaleItemsPruned: result.staleLangItemsPruned)` 或 `clearProgress`。
5. `finally` 收尾關 client、清旗標。

專屬 logger `Logger('gacha.hoyowiki.refreshMetadata')`，在開始、各階段、完成／取消處埋 `info`（帶 images／items 計數）。

### 3. 設定頁：新增「物品資料」區

`lib/pages/settings_page.dart`：

- 在 `build` 的 section 清單，於「圖片快取」之前新增一張 `SectionCard`（圖示 `Icons.dataset_outlined`），把「物品資料更新」與「圖片快取管理」相鄰分組。
- 新增 `_ItemDataSection`（`ConsumerWidget`）：一行說明（`l.settingsRefreshItemDataDesc`）+ 一顆**一般** `FilledButton.icon`（非 danger 樣式，與破壞性按鈕區分）。
- disable 條件比照 `_refetchAll`：`!hasData || progress != null`；`!hasData` 時 `Tooltip` 顯示 `l.settingsRefreshItemDataEmpty`。
- 點擊 → `showConfirmDialog(isDanger: false)` 輕量確認 → `unawaited(refreshAllHoYoWikiMetadata())`。進度 dialog 由 `app_shell.dart` 既有 `ref.listen` 自動彈出。

### 4. 殘留語言清理（`pruneLanguages`）

**問題情境**：`_fetchHoYoWiki` 只從**目前記錄**收集 `(物品, lang)`。若使用者曾用「設定 → 資料語言 → 立即轉換」把記錄轉成別的語言再轉回（例如 en-us → zh-tw），index 裡那個 en-us 的 `pageByLang` 會殘留——`unifyDataLanguage` 只轉記錄、不清 index；後續更新也只抓當前語言，永遠不會碰到舊語言頁面。

**解法**（`lib/state/hoyowiki_index.dart`，`HoYoWikiIndexNotifier.pruneLanguages`）：

```dart
Future<int> pruneLanguages(Set<String> keepLangs)
```

- 移除所有 entry 中 `lang ∉ keepLangs` 的 `pageByLang` 條目；保留 `iconUrl`／`fetchedAt`／`searchMap`／`menuIds`。
- **空 `keepLangs` 直接 `return 0`**（防呆：空集合會清掉全部）——這是 method 內部的第二道防線，呼叫端另有 `allLangs.isNotEmpty` 守衛。
- 有實際縮減才 `_saveAndEmit`；無變動 `return 0`（不重建 index、不觸發 UI churn）。
- 回傳值 = `pageByLang` 真的有縮減的**相異物品數**，供完成訊息統計。

效果：更新只覆蓋「正在使用的語言」，舊語言殘留被清掉；當前語言的 icon／gallery 一律不動（非破壞性）。

### 5. 完成訊息設計（語意化）

「更新物品資料」**不可**沿用祈願記錄流程的「新增 N 筆紀錄」（對 metadata 刷新無意義）。改用本流程專屬摘要。

- `UpdateCompleted`（`lib/state/update_progress.dart`）新增兩個欄位：
  - `int? hoyoWikiEntriesRefreshed`（預設 null）——非 null 即代表「這是更新物品資料流程的完成」，UI 據此切換到物品資料摘要；值為本次成功刷新的物品數。
  - `int hoyoWikiStaleItemsPruned`（預設 0）——本次清理殘留語言的物品數。
- `UpdateProgressDialog._Body` 的 `UpdateCompleted` 分支改為**三路**（`lib/widgets/update_progress_dialog.dart`）：
  1. `importSummary != null` → 匯入摘要（既有，不變）。
  2. `hoyoWikiEntriesRefreshed != null` → 物品資料摘要：
     - 主行：`已更新 {M} 個物品的資料`（`l.progressDoneItemDataSummary`）。
     - 補圖行（僅 `hoYoWikiImagesDownloaded > 0`）：`補下載 {N} 張物品圖片`（`l.progressDoneItemDataImagesSummary`）。
     - 清理行（僅 `hoyoWikiStaleItemsPruned > 0`）：`已清理 {K} 個物品的殘留語言資料`（`l.progressDoneItemDataPrunedSummary`）。
  3. else → 一般更新摘要（既有「新增 N 筆紀錄」+「下載 N 張物品圖片」，不變）。
- 標題沿用「更新完成」。

### 6. i18n 字串

依專案慣例：先寫 `app_zh.arb`（template，含 `@` 描述），再以中文為基準翻**已有實體翻譯**的 ARB；不碰空殼（留給 Crowdin pipeline）；省略號半形。最終實際出貨的 key：

| key | 用途 | 繁中 |
|-----|------|------|
| `settingsItemData` | 區塊標題 | 物品資料 |
| `settingsRefreshItemDataDesc` | 區塊說明 | 從 HoYoWiki 重新抓取所有物品的最新詳細資料（描述、圖片清單等），保留已下載的圖片；新增的圖片會在你開啟該物品詳情時才下載。 |
| `settingsRefreshItemDataTitle` | 按鈕文字 | 更新物品資料 |
| `settingsRefreshItemDataEmpty` | 無資料 tooltip | 尚無卡池記錄，無法更新物品資料 |
| `confirmRefreshItemDataTitle` | 確認標題 | 更新物品資料？ |
| `confirmRefreshItemDataBody` | 確認內文 | 將連線 HoYoWiki 重新抓取所有物品的詳細資料，依物品數量可能需要一段時間。已下載的圖片會保留，不會被清除。 |
| `confirmRefreshItemDataConfirm` | 確認鈕 | 開始更新 |
| `progressDoneItemDataSummary` | 完成主行 | 已更新 {count} 個物品的資料 |
| `progressDoneItemDataImagesSummary` | 完成補圖行 | 補下載 {count} 張物品圖片 |
| `progressDoneItemDataPrunedSummary` | 完成清理行 | 已清理 {count} 個物品的殘留語言資料 |

## 資料流

```
設定頁「更新物品資料」→ refreshAllHoYoWikiMetadata()
  → _fetchHoYoWiki(forceEntryRefetch: true, pruneStaleLangs: true)
      pruneLanguages(allLangs)  ← 清掉殘留語言（allLangs 非空才執行）
      search（補未解析）→ entry（全部已解析條目重抓，含新 gallery 清單）→ download（只補缺 icon）
  → mergeEntry 覆蓋該 lang page + bumpCacheRevision → index 更新
  → UpdateCompleted(itemsRefreshed=M, imagesDownloaded=N, staleItemsPruned=K)
  → 進度 dialog 顯示「已更新 M…／補下載 N…（N>0）／已清理 K…（K>0）」，結束後刷新快取用量

之後使用者開某物品詳情：
  build() 讀最新 index → 新 gallery 條目變新 chip
  → _loadStates 缺該檔 → 背景 lazy 下載新圖（既有邏輯，零改動）
```

## 錯誤處理

- 單筆 search／entry／download 失敗：沿用 `_fetchHoYoWiki` 既有 per-item try/catch + `warning` log，不終止整段。
- 整段例外：`refreshAllHoYoWikiMetadata` 不像破壞性流程有 `resetAll` 失敗路徑，故不需要 `UpdateErrorWipeHoYoWikiCache`；最壞情況是部分條目沒更新到，使用者可再次點擊（非破壞性，重試安全）。
- 取消：使用者於進度 dialog 按取消 → `_cancelTriggered` → 各階段早退 → emit `clearProgress`。已寫入 index 的部分保留。
- 並發互斥：`progress != null` 或 `_isUpdating` 時按鈕已 disable，方法層再做 no-op 防呆。

## 已知次要行為

- **icon 快取 key**：以 id（與副檔名）為 key、不含 URL hash。若 icon URL 僅字串變動但副檔名不變 → 路徑相同 → 不重下（沿用舊 icon）。屬可接受行為。
- **只更新當前語言**：更新只抓記錄目前的語言。要更新／顯示某語言的物品資料，途徑是先「資料語言 → 立即轉換」統一記錄語言，再「更新物品資料」。
- **清理只動 index**：`pruneLanguages` 只移除 `pageByLang`，不清 `searchMap` hints、不刪 orphan gallery 圖檔（前者很小且利於日後再轉回；後者交既有「清除詳情圖快取」）。

## 測試

- **Repository（單元，`gacha_repository_hoyowiki_test.dart`）**：
  - `forceEntryRefetch: true` 時已解析 entry 仍進 worklist 並重抓；`false` 不進（守住增量行為）。
  - 第二次回傳「多一張 gallery 圖」→ index 該 lang gallery 變長，且 gallery 未被 eager 下載。
  - 本地已有 icon 時 force 重抓不重下 icon。
  - `refreshAllHoYoWikiMetadata` 完成後 `UpdateCompleted.hoyoWikiEntriesRefreshed`（1 物品 → 1；同物品 2 語言 → 仍 1，驗證相異 id 計數）、`hoyoWikiStaleItemsPruned`（注入殘留語言 → 對應數）。
  - 注入殘留語言 page → 執行 refresh → 該語言被清、當前語言保留。
- **Notifier（單元，`hoyowiki_index_test.dart`）**：`pruneLanguages` 清掉殘留語言、保留 keep 語言與 iconUrl／searchMap；無變動為 no-op（state identity 不變）；空 keepLangs 回 0 且不動 state；回傳值為清理物品數。
- **設定頁（widget）**：「物品資料」按鈕無資料 disable、有資料可點。
- **完成 dialog（widget，`update_progress_dialog_test.dart`）**：metadata 完成顯示「已更新 M…」；`hoYoWikiImagesDownloaded == 0` 時無補圖行、`> 0` 時有；`hoyoWikiStaleItemsPruned == 0` 時無清理行、`> 0` 時有；任何情況都不出現「新增」字樣。

## 驗收條件

1. `fvm flutter analyze` 輸出 `No issues found!`。
2. `fvm flutter test` 輸出 `All tests passed!`，含上述新增測試。
3. 設定頁出現獨立「物品資料」區與「更新物品資料」按鈕（輕量確認、進度 dialog、非破壞性）。
4. 實機：對已有 gallery 的物品，HoYoWiki 新增圖後執行更新 → 開啟詳情可見新頁籤且圖會補下載；已下載的圖未被清除；完成訊息顯示「已更新 M 個物品的資料」（不顯示「新增 N 筆紀錄」）。
5. 資料語言轉換情境：轉成他語言再轉回後執行更新 → 舊語言殘留被清、完成訊息顯示「已清理 K 個物品的殘留語言資料」。
