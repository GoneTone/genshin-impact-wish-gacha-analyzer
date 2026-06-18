# 手動更新物品詳細資料 — 設計文件

- 日期：2026-06-18
- 狀態：設計已確認，待寫實作計畫

## 背景與問題

物品詳細資料（HoYoWiki 的 gallery 清單、描述、tags）由 `GachaRepository._fetchHoYoWiki` 的三階段管線（search → entry → download）抓取，存進 `hoyowiki_index.json`。

這條管線是**增量式**的：`needRefetchEntry`（`lib/state/gacha_repository.dart:1010`）判定「entry 已存在、menuId 有、該語言 page 也有」就回傳 `false`，不重抓。結果是——**若某物品在 HoYoWiki 後來新增了 gallery 圖（例如新增的立繪），正常更新永遠偵測不到**，因為該語言的 page 早已存在。

設定頁現有的「強制重抓物品圖片」按鈕雖能拿到新資料，但它走 `forceRefetchAllHoYoWikiImages()` → 先 `resetAll()` **清空整個 index 與所有快取圖**，再全部重抓並 eager 下載所有 icon。這是破壞性的、耗時且浪費頻寬。

使用者需要一個**非破壞性**的入口：只重抓 metadata，讓新增的 gallery 圖／頁籤被偵測到，但保留已下載的圖、不 eager 下載新圖；新圖一律維持 lazy，等使用者開啟該物品詳情時才補下載。

## 目標

1. 設定頁新增一顆「更新物品資料」按鈕，點擊後重抓所有物品的 HoYoWiki metadata（非破壞性）。
2. 重抓涵蓋：對先前**沒解析到**的物品重試 search；對**所有已解析**的條目強制重抓 entry 階段（更新 gallery 清單／描述／tags）。
3. 不重抓已下載的圖；icon 僅在本地缺檔時 eager 補下載；gallery 大圖一律維持 lazy。
4. 物品詳情頁的頁籤隨 index 更新自動反映新 gallery 條目；開啟詳情時補下載缺漏的圖。

## 非目標（YAGNI）

- 不做「只更新逾期條目（依 `fetchedAt` 門檻）」的選擇性更新——使用者選擇「全部已解析條目都重抓」。
- 不改 icon 快取的 key 策略（仍以 id 為 key）；不主動因 icon URL 字串變動而重下 icon。
- 不在詳情頁新增任何 per-item 重抓入口（既有圖片選單的「重抓圖片」已涵蓋單張需求）。
- 不保留「破壞性強制重抓」以外的相容路徑——既有按鈕原樣保留。

## 關鍵發現：詳情頁無需改動

`GachaItemDetailDialog.build()`（`lib/widgets/dialogs/gacha_item_detail_dialog.dart:449`）`watch(hoyowikiIndexProvider)`，且既有的 lazy backfill（同檔 519-541 行）對「不在 `_loadStates` 的 chip」逐一檢查：本地有檔 → `_GalleryReady`，缺檔 → `_GalleryLoading` 並排程背景下載。

每次開啟 dialog 都是全新的 `State`、`_loadStates` 為空，因此**每次開啟都會重新檢查所有 gallery chip（含卡片大圖）並補下載缺的**。metadata 更新後，`mergeEntry`（`lib/state/hoyowiki_index.dart:117`）以 `lang: fetched.page` 覆蓋該語言 page → 新 gallery 條目進入 index → 下次（或開著時）重建即多出新 chip → 缺檔自動 lazy 補下載。

icon 則由 `hasHoYoWikiContent`（同檔 30 行）把關：icon 檔不存在時物品不可點。故 icon 必須在更新時就補齊（見下方 icon 策略），與本設計一致；詳情頁本身不處理 icon lazy 下載。

**結論：「頁籤跟著更新」與「開啟詳情時補下載缺圖」由既有機制完整涵蓋，本功能在詳情頁零改動，前提僅是 index 要先被更新。**

## 設計

### 1. 參數化 `_fetchHoYoWiki`（重用既有管線，不造新輪子）

`lib/state/gacha_repository.dart`：

```
Future<int> _fetchHoYoWiki(http.Client client, {bool forceEntryRefetch = false})
```

- **search 階段**：不變。`searchTodo` 本來就只收 `lookupId == null` 者，且無負快取——「對先前沒解析到的重試 search」現況已免費滿足。
- **entry 階段（唯一行為變更）**：
  - `forceEntryRefetch == false`：維持現狀，由 `needRefetchEntry` 決定。
  - `forceEntryRefetch == true`：`entryTodo` 納入**所有已解析的 (id, lang)**，略過 `needRefetchEntry` 的「已有就跳過」。search 階段內部那段「命中後 add 進 entryTodo」的 `needRefetchEntry` 守衛在 force 模式下也改為無條件 add。
- **download 階段**：不變。`enqueueDownloadsForEntry`（同檔 1042 行）本來就只 enqueue icon、且只在 `iconFile.existsSync() == false` 時加入；gallery 完全不在此下載。→ 自動符合「缺 icon 才 eager 下載、gallery 維持 lazy」。
- **early return**：`totalInitial == 0` 的早退在 force 模式下因 `entryTodo` 非空（有已解析條目時）不會誤觸；無任何記錄時仍正確回 0。
- 取消／互斥／進度（`FetchingHoYoWiki` 三階段）全部沿用既有邏輯。

### 2. 新增 `refreshAllHoYoWikiMetadata()`

`lib/state/gacha_repository.dart`，比照 `forceRefetchAllHoYoWikiImages`（534-604 行）的骨架，**但拿掉 `resetAll()`**：

1. 互斥檢查（`state.progress != null` / `_isUpdating` → no-op）。
2. emit `Preparing`、建 cancellable client、設 `_activeCancellable`。
3. 直接呼叫 `_fetchHoYoWiki(cancellable.client, forceEntryRefetch: true)`（不清 index、不清 cache）。
4. 依取消狀態 emit `UpdateCompleted(hoYoWikiImagesDownloaded: ...)` 或 `clearProgress`。
5. `finally` 收尾關 client、清旗標。

新增專屬 logger（對齊既有樹，如 `Logger('gacha.hoyowiki.refreshMetadata')`），在開始（總條目數）、各階段結束、完成／取消處埋 `info`，單筆失敗沿用 `_fetchHoYoWiki` 內既有 `warning`。

### 3. 設定頁：新增「物品資料」區

`lib/pages/settings_page.dart`：

- 在 `build` 的 section 清單（66-126 行）新增一張 `SectionCard`，建議插在「圖片快取」（110 行）之前，視覺上把「物品資料更新」與「圖片快取管理」相鄰分組。圖示建議 `Icons.dataset_outlined`（或 `Icons.inventory_2_outlined`）。
- 新增 `_ItemDataSection`（`ConsumerWidget`），內含：
  - 一行簡短說明文字（`l.settingsRefreshItemDataDesc`）：說明此操作會連線 HoYoWiki 重抓最新詳細資料、保留已下載的圖、新圖於開啟詳情時補下載。
  - 一顆 `FilledButton.icon`（**非** danger 樣式，用一般 FilledButton 與破壞性按鈕區分），label `l.settingsRefreshItemDataTitle`，icon `Icons.refresh`（或 `Icons.sync`）。
  - disable 條件比照 `_refetchAll`：`!hasData || progress != null`；`!hasData` 時用 `Tooltip` 顯示 `l.settingsRefreshItemDataEmpty`。
- 點擊 → `_refreshItemData(ctx)`：以 `showConfirmDialog`（`isDanger: false`）跳輕量確認（title／body／confirm 用新 key），確認後 `unawaited(ref.read(gachaRepositoryProvider.notifier).refreshAllHoYoWikiMetadata())`。進度 dialog 由 `app_shell.dart` 既有 `ref.listen` 自動彈出，無需額外處理。

### 4. i18n 字串

依專案慣例：先寫 `app_zh.arb`，再以中文為基準翻已有實體翻譯的 ARB；**不碰空殼 ARB**（留給 Crowdin pipeline）；省略號一律半形。新增 key（命名對齊既有 `settingsRefetchHoyoWiki*` / `confirmRefetchHoyoWiki*` 範式）：

| key | 用途 | 繁中草案 |
|-----|------|---------|
| `settingsItemData` | 區塊標題 | 物品資料 |
| `settingsRefreshItemDataDesc` | 區塊說明 | 從 HoYoWiki 重新抓取所有物品的最新詳細資料（描述、圖片清單等），保留已下載的圖片；新增的圖片會在你開啟該物品詳情時才下載。 |
| `settingsRefreshItemDataTitle` | 按鈕文字 | 更新物品資料 |
| `settingsRefreshItemDataEmpty` | 無資料 tooltip | 尚無卡池記錄，無法更新物品資料 |
| `confirmRefreshItemDataTitle` | 確認標題 | 更新物品資料？ |
| `confirmRefreshItemDataBody` | 確認內文 | 將連線 HoYoWiki 重新抓取所有物品的詳細資料，依物品數量可能需要一段時間。已下載的圖片會保留，不會被清除。 |
| `confirmRefreshItemDataConfirm` | 確認鈕 | 開始更新 |

文案最終以實作時 `app_zh.arb` 為準。

## 資料流

```
設定頁「更新物品資料」→ refreshAllHoYoWikiMetadata()
  → _fetchHoYoWiki(forceEntryRefetch: true)
      search（補未解析）→ entry（全部已解析條目重抓，含新 gallery 清單）→ download（只補缺 icon）
  → mergeEntry 覆蓋該 lang page + bumpCacheRevision → index 更新
  → UpdateCompleted（進度 dialog 自動顯示，結束後刷新快取用量）

之後使用者開某物品詳情：
  build() 讀最新 index → 新 gallery 條目變新 chip
  → _loadStates 缺該檔 → 背景 lazy 下載新圖（既有邏輯，零改動）
```

## 錯誤處理

- 單筆 search／entry／download 失敗：沿用 `_fetchHoYoWiki` 既有 per-item try/catch + `warning` log，不終止整段。
- 整段例外：`refreshAllHoYoWikiMetadata` 不像破壞性流程有 `resetAll` 失敗路徑，故不需要 `UpdateErrorWipeHoYoWikiCache`；最壞情況是部分條目沒更新到，使用者可再次點擊。
- 取消：使用者於進度 dialog 按取消 → `_cancelTriggered` → 各階段 `isAborted()` 早退 → emit `clearProgress`。已寫入 index 的部分保留（非破壞性，安全）。
- 並發互斥：`progress != null` 或 `_isUpdating` 時按鈕已 disable，方法層再做 no-op 防呆。

## 已知次要行為

- icon 快取檔以 id（與副檔名）為 key、不含 URL hash。若某條目 icon URL 僅字串變動但副檔名不變 → 路徑相同 → `existsSync()` 為真 → **不重下**（沿用舊 icon）。此與使用者選擇的「缺 icon 才下、URL 變不重下」一致；屬可接受行為，不在本次處理。

## 測試

- **Repository（單元）**：擴充既有 HoYoWiki 抓取測試（參考 `debugRunHoYoWikiOnly` 與既有 fake fetcher 模式），新增案例：
  - 給定一個「已解析、該 lang page 已存在」的 entry，`forceEntryRefetch: true` 時該 (id, lang) 仍進入 entry worklist 並被重抓；`false` 時不進入（守住既有增量行為）。
  - fake fetcher 第二次回傳「多一張 gallery 圖」的 page → 斷言 `mergeEntry` 後 index 的該 lang gallery 清單變長，且 **download 階段未** eager 下載該 gallery 圖（只可能下 icon）。
  - 本地已有 icon 檔時，force 重抓不重複下載 icon。
- **設定頁（widget）**：新「物品資料」區按鈕在無資料時 disable、有資料時可點；點擊跳確認 dialog，確認後呼叫 `refreshAllHoYoWikiMetadata`（以 provider override / spy 驗證）。
- 既有詳情頁 lazy backfill 測試若存在則無需改動；可補一個「index 新增 gallery 條目後，開啟 dialog 會對缺檔 chip 觸發下載」的迴歸測試（若既有測試未涵蓋）。

## 驗收條件

1. `fvm flutter analyze` 輸出 `No issues found!`。
2. `fvm flutter test` 輸出 `All tests passed!`，含上述新增測試。
3. 設定頁出現獨立「物品資料」區與「更新物品資料」按鈕，行為符合上述（輕量確認、進度 dialog、非破壞性）。
4. 實機驗證：對已有 gallery 的物品，HoYoWiki 新增圖後執行更新 → 開啟該物品詳情可見新頁籤且圖會補下載；已下載的圖未被清除。
