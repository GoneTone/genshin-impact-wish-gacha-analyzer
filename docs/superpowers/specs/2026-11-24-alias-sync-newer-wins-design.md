# 別名同步：較新的修改勝出（設計）

狀態：設計中（2026-11-24）

## 目的

在一台裝置上清空或修改帳號別名後，其他裝置同步後也要跟著變。

現在的合併規則是「本機已有別名就保留本機，本機沒有才用雲端的」（`GachaRepository._runImport`），雲端同步和匯入備份檔都用它。這條規則造成兩個問題：

- **清空別名同步不出去**：清空後本機變成「沒有別名」，下一輪同步會把雲端的別名帶回來。2026-11-24 拍 Windows 截圖時實際遇到。
- **修改別名傳不到已有別名的裝置**：B 裝置已有舊別名時會保留舊的，A 裝置的修改過不去。

根源是雲端檔只能表達「有這個別名」，不能表達「這個別名被清掉了」或「哪一邊比較新」。

## 範圍

### 做

1. **每個別名記錄最後修改時間**：設定、修改、清空都記。
2. **匯出格式加欄位**：帳號多一個 `alias_updated_at`（ISO 8601 UTC，和 `exported_at` 同格式）。清空後仍寫時間、不寫 `alias`，代表「已清空」。
3. **合併規則改成比時間**：雲端同步與匯入備份檔一致（都走 `_runImport`）。
4. **內容相同就跳過合併的判斷**（`_identicalAccountsInBackground`）改用同一條規則，避免該合併的別名被跳過。

### 不做

- **衝突提示介面**：兩台裝置先後修改時，直接以較新的為準，不跳出選擇。
- **帳號順序、目前帳號等其他偏好**：維持現狀。
- **時鐘校正**：用裝置本身的時間。裝置時間差很多時，結果可能不如預期，可以接受。

## 做法比較

- **A. 記下待上傳的別名修改**（仿照刪除帳號的 `cloudPendingRemovals`）：改過的 UID 以本機為準，其他 UID 以雲端為準。
  - 不改雲端格式。
  - 但已有別名、從沒同步過的裝置第一次連結時，本機別名會被雲端蓋掉或清空，要補救就得加更多規則。
- **B. 記錄修改時間，較新的勝出**：一次解決清空、修改、先後修改。
  - 沒有時間的舊資料沿用現在的規則，升級後不會誤清。
  - 雲端格式多一個欄位。舊版讀得懂，但舊版上傳時會丟掉這個欄位，這時退回舊規則。

**使用者 2026-11-24 選 B。**

## 設計

### 本機儲存

- `AppSettings` 新增 `uidAliasUpdatedAt`：`Map<String, DateTime>`，以 UID 為 key，值為 UTC。存在 `pref.uidAliasUpdatedAt`（JSON，值為 ISO 8601 字串）。損毀時記 warning、重設為空，和 `uidAliases` 一樣。
- `setUidAlias`：值有變（設定、修改、清空）時，把該 UID 的時間設為現在。值沒變時照舊不寫入。
  - 清空時 `uidAliases` 移除該 UID，`uidAliasUpdatedAt` 保留時間，作為「已清空」的記錄。
- `removeUidFromSettings`、`clearAllUidPreferences`：一併移除時間。
- `applyImportedPreferences`：多收合併後的時間表，和別名同一次寫入。

### 匯出與讀取

- `ExportedAccount` 新增 `aliasUpdatedAt`（`DateTime?`）。
  - `toJson`：`alias` 照舊（空的不寫）。有時間就寫 `alias_updated_at`，即使沒有別名也寫。
  - `fromJson`：讀 `alias_updated_at`。格式不對就當成沒有時間，不讓整個帳號匯入失敗。
- `buildAccountsBundle`（`accounts_export.dart`）把 `uidAliasUpdatedAt` 帶進每個帳號。
- `schema_version` 不變：只是加欄位，舊版會忽略。

### 合併規則

抽成一個純函式，給 `_runImport` 和 `_identicalAccountsInBackground`（isolate 內）共用：

| 本機時間 | 匯入方時間 | 結果 |
|---|---|---|
| 有 | 有 | 較新的勝出；時間相同時保留本機 |
| 無 | 有 | 匯入方勝出（匯入方是新版留下的明確修改） |
| 有 | 無 | 保留本機 |
| 無 | 無 | 舊規則：本機有別名就保留，沒有才用匯入方的 |

- 匯入方勝出時，別名和時間都改成匯入方的；匯入方沒有別名（已清空）就移除本機別名，但保留時間。
- 匯入失敗的帳號照舊跳過。

### 內容相同就跳過合併

`_identicalAccountsInBackground` 目前的條件是「內容（不看別名）相同」，再加上「本機已有別名或雲端沒有別名」。後半段改成「依上面的規則，匯入方不會勝出」，並且比較內容時同時排除 `alias` 和 `alias_updated_at`。

### Log

- `setUidAlias` 的現有 log 不變。
- `_runImport` 在有別名被匯入方覆寫或清空時，記一行英文的統計，例如 `import aliases: taken=N cleared=M`，不記別名內容和 UID。

## 驗收

- **單元測試**：
  - `ExportedAccount` 的 JSON 來回轉換，包含「有時間、沒有別名」和格式錯誤的時間。
  - 合併規則的表格四種情況，以及時間相同、匯入方清空。
  - `_runImport`：雲端較新的清空會移除本機別名；本機較新的修改不會被雲端蓋掉；沒有時間的舊資料行為不變（現有的 keep-local 測試保持綠燈）。
  - `_identicalAccountsInBackground`：雲端有較新的清空或修改時，不可跳過合併。
  - `SettingsStorage` 存取 `uidAliasUpdatedAt`，以及損毀時重設。
  - `setUidAlias` 會記錄時間；`removeUidFromSettings`、`clearAllUidPreferences` 會清掉時間。
- **兩個平台**：這是 Android 與電腦版共用的程式，兩邊都跑相關測試。
- **實測**：Windows 和 Android 模擬器連結同一個雲端帳號，在一邊清空、修改別名，另一邊同步後要跟著變；舊別名（沒有時間）升級後不會消失。
  - 這會動到使用者 Google 雲端硬碟裡的同步檔，實測前先備份雲端檔和兩邊的資料夾，並先問過使用者。
- `fvm flutter analyze`、`fvm flutter test` 全綠。

## 鳴潮

原神完成後，同樣的修正移植到鳴潮。鳴潮另開分支、開 PR，比照鳴潮 PR 128 的做法。
