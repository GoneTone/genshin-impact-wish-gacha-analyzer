# 匯入資料改為合併（非覆蓋）設計

## 背景與目標

目前「匯入全部資料」採**整帳號覆蓋**：對備份檔裡的每個帳號直接 `storage.save(account.data)`，用備份的整包 `BannerStorage` 換掉該 UID 的磁碟檔，完全不去重。同一 UID 重複匯入 → 本機既有資料被整包蓋掉；本機有、備份沒有的 UID 則保留不動。此行為是當初 `2026-05-12-export-import-all-accounts-design.md` 刻意選的（「衝突一律覆蓋整個帳號」）。

本設計把匯入改為**永遠合併、非破壞性**：匯入是純加法，本機既有的祈願記錄絕不會因匯入而消失。移除覆蓋模式（不提供切換）。

**成功條件**

- 既有 UID 重複匯入時，本機與備份的祈願記錄依 `id` union 去重，兩邊都保留。
- 本機有、備份沒有的 UID、記錄、偏好一律不受影響。
- 匯入流程改為非破壞性語意（移除「輸入 IMPORT」強確認），並回報「新增 / 已存在」筆數。
- `fvm flutter analyze` 全綠、`fvm flutter test` 全綠。

## 決策摘要

| 面向 | 決策 |
|------|------|
| 衝突策略 | 永遠合併（union by `id`），移除覆蓋；不提供切換 |
| 去重 key | `GachaRecord.id`（HoYoverse 19 碼遞增流水號，天然唯一） |
| 同 id 衝突 | 保留本機那筆；本機 `lang` 空、備份非空 → 回填 `lang` |
| `lastUpdated` | 合併後取兩者較新者 |
| 別名 | 只補空缺：本機該 UID 已有別名則保留；僅當本機無別名且備份非空時採用備份；備份空別名不清掉本機別名 |
| 上次選取帳號（active） | 本機已有有效 active 則保留；否則採用備份 `lastActiveUid`（須存在）；再否則 fallback 到 `newOrder.first`（皆無則 null） |
| 帳號顯示順序（`uidOrder`） | 本機既有順序原封不動；這次新出現的 UID 依備份檔順序接在最後 |
| 確認流程 | 移除打字閘，改一般確認；badge／文案改合併語意；非 danger 配色 |
| 結果回報 | 顯示「已合併 N 個帳號：新增 X 筆、已存在 Y 筆」 |

## 設計

### 1. 合併原語：`BannerStorage.mergeWith`

在 `lib/models/banner_storage.dart` 新增純函式方法（可獨立單測，不依賴 I/O 或 Riverpod）：

```dart
/// 將 [incoming]（同一 UID 的另一份存檔）合併進本份，回傳新的 [BannerStorage]。
/// 逐 banner 依 record.id union 去重後降序排序；本機既有記錄一律保留。
BannerStorage mergeWith(BannerStorage incoming)
```

行為：

- **逐 banner（gacha_type）union**：兩邊 `banners` 的 key 取聯集；每個 banner 內把本機與備份兩條 list 依 `id` 去重後**降序排序**。`id` 等長 19 碼，字典序＝數值序，排序用 `(a, b) => b.id.compareTo(a.id)`（與 `gacha_fetcher.dart` 的 `_idGreater` 同一套字典序規則）。
- **同 `id` 衝突**：保留本機那筆；但若本機該筆 `lang` 為空字串、備份那筆 `lang` 非空 → 以 `GachaRecord.copyWith(lang:)` 回填（鏡像 `fetchBannerWithMerge` 既有的頌願 lang 補值哲學；一般祈願記錄 `lang` 必非空，不受影響）。
- **`lastUpdated`**：取 `this.lastUpdated` 與 `incoming.lastUpdated` 較新者。
- 記錄級合併抽成 `static` 私有 helper：`static List<GachaRecord> _mergeRecordsById(List<GachaRecord> local, List<GachaRecord> incoming)`，集中「兩條 list → 依 id union 去重（同 id 保留 local，必要時回填 lang）→ 依 id 降序排序」的邏輯，避免散落於 banner 迴圈。

逐 banner 合併（pseudocode）：

```
for (final key in {...local.banners.keys, ...incoming.banners.keys}) {
  merged[key] = _mergeRecordsById(
    local.banners[key] ?? const [],
    incoming.banners[key] ?? const [],
  );
}
```

> 註：不重用 `fetchBannerWithMerge`。該方法靠「網路分頁掃到 `existingMaxId` 即停」做增量抓取，回傳 `[...fresh, ...existing]`（fresh 為嚴格更新者，非任意重疊集合的 union），語意與匯入合併不同。抓取流程維持原樣，不在本次改動範圍（YAGNI、控制 blast radius）。

### 2. `_runImport` 改寫（`lib/state/gacha_repository.dart`）

**記錄合併**：把「直接覆蓋」改為「合併」——

- 備份的 UID 本機**沒有** → 直接 `storage.save(account.data)`（等同合併進空存檔）。
- 備份的 UID 本機**已有** → `final merged = state.byUid[uid]!.mergeWith(account.data); await storage.save(merged);` 並以 `merged` 更新 `newByUid[uid]`。
- 保留現有 per-account `try/catch`：單一 UID 寫入失敗 → 加入 `failedUids`、其餘帳號繼續；保留 `ref.mounted` 檢查與提前返回。

**新增 / 已存在計數**（用既有的 `BannerStorage.allRecords` getter，免讓 `mergeWith` 回傳 tuple）：

- 每帳號：`addedThisAccount = merged.allRecords.length - localBefore.allRecords.length`（union 的性質：恰等於「備份記錄中 id 本機原本沒有的數量」）；`duplicateThisAccount = incoming.allRecords.length - addedThisAccount`。
- 新 UID（本機無）時 `localBefore` 視為空 → `added` ＝ 備份全部、`duplicate` ＝ 0。
- 累加為整體 `addedRecords` / `duplicateRecords`，提前返回路徑也帶當前累計值。

**偏好「只補空缺」**：

- **別名**：移除「備份空別名 → `mergedAliases.remove(uid)`」這條覆蓋邏輯。改為：僅當 `currentSettings.uidAliases` 不含該 UID（本機無別名）且備份別名非空時，才 `mergedAliases[uid] = a`；本機已有別名則保留不動。
- **`uidOrder`**：

  ```dart
  final localOrder = currentSettings.uidOrder; // 本機既有順序原封不動
  final localSet = localOrder.toSet();
  final appended = bundle.accounts
      .where((a) => !failed.contains(a.data.uid))
      .map((a) => a.data.uid)
      .where((uid) => !localSet.contains(uid)) // 只取本機原本沒有的
      .toList(growable: false);
  final newOrder = [...localOrder, ...appended];
  ```

- **active UID**：本機目前若已有有效 active（`state.activeUid != null && newByUid.containsKey(state.activeUid)`）→ 保留本機；否則才採用備份的 `lastActiveUid`（仍須存在於 `newByUid`）；再否則 fallback 到 `newOrder.first`；皆無則 null。此選擇在所有 per-account `save()` 與 `applyImportedPreferences()` 之後才定案。

### 3. 確認流程改非破壞性

涉及 `lib/pages/settings_page.dart`（`_import`）、`lib/widgets/dialogs/confirm_dialog.dart`、`lib/widgets/dialogs/accounts_picker_dialog.dart`。

**共用一般確認 dialog（不重造輪子）**：`settings_page.dart` 內 `_clearGallery`（約 784-804）與 `_refetchAll`（約 825-845）已各自手寫一份「`showDialog<bool>` + `AppDialog` + 取消/確認」的無打字確認（兩者目前都用 danger 紅）。依 CLAUDE.md「抽出來共用」，在 `confirm_dialog.dart` 新增一支抽取自這兩處的 `showConfirmDialog`，並把 `_clearGallery`／`_refetchAll` 改呼叫它（兩者傳 `isDanger: true` 維持現有紅色，不改其視覺）：

```dart
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String cancelLabel,
  required String confirmLabel,
  IconData? confirmIcon,
  bool isDanger = false, // true → stateDanger 紅；false → 中性 accentPrimary
})
```

匯入確認改用 `showConfirmDialog(..., isDanger: false)`，取代原本的 `showConfirmTypeDialog(expectedText: 'IMPORT')`。`settings_page.dart` 另外三處危險確認（`_clearActive` 646、`_clearAll` 1069，及 `account_management.dart:101` 的 `_remove`）維持打字閘，不動。

**Picker badge**：既有 UID 的 badge 文字由 `settingsImportOverwriteBadge`（「覆蓋」）改為 `settingsImportMergeBadge`（「合併」）。`accounts_picker_dialog.dart` 的 `_PickerRow`（約 217-232）目前把 badge 底色／文字硬編為 `tokens.stateDanger`；由於 badge 唯一消費者就是這個匯入流程（export picker 不帶 badge），直接把該處改為中性 token（如 `tokens.textSecondary`／`tokens.accentPrimary`），不另加 enum 參數（YAGNI）。

**內文改寫**：

- 前言改合併語意（改寫 `settingsImportConfirmIntro`：「即將匯入…」→「即將合併…」），沿用既有 `• UID (別名)` 清單格式。
- 衝突區塊：把「覆蓋」標頭（`settingsImportConfirmOverwriteHeader`）改為新 key `settingsImportConfirmMergeHeader`（「下列帳號將與本機資料合併，不會刪除既有記錄：」），列出衝突 UID。
- 移除危險警告句（刪 `_import` 對 `settingsImportConfirmWarning` 的引用與該 ARB key）。
- 保留「未匯入的帳號維持不動」footer（`settingsImportConfirmPreserveFooter`）與「無資料衝突」（`settingsImportConfirmNoConflict`）。

### 4. 結果回報「新增 / 已存在」（`lib/state/update_progress.dart` 與 `lib/widgets/update_progress_dialog.dart`）

- `ImportResult` 欄位改為：`successAccounts`、`addedRecords`、`duplicateRecords`、`failedUids`（移除 `totalRecords`）。`_runImport` 三處 `ImportResult(...)` 建構（含兩處 unmount 提前返回與最終返回）一併改用新欄位；計數公式見段 2。
- `progressDoneImportSummary` 由 2 個 placeholder（accounts、records）改為 3 個（successAccounts、addedRecords、duplicateRecords），文案如「已合併 {accounts} 個帳號：新增 {added} 筆、已存在 {duplicate} 筆」；`update_progress_dialog.dart`（約 235-238）呼叫點同步改。
- **兩處 log 都要改**：`importAccountsAndFetchHoYoWiki`（約 608-611）與 `_runImport` 收尾（約 747-751）原本印 `records=$totalRecords`，改印 `added` / `duplicate`；含 UID 的 log 一律經 `sanitizeUid` 脫敏（對齊 CLAUDE.md log 規範）。

### 5. 受影響檔案清單

| 檔案 | 變更 |
|------|------|
| `lib/models/banner_storage.dart` | 新增 `mergeWith` + `static _mergeRecordsById` |
| `lib/state/gacha_repository.dart` | `_runImport`：記錄合併、added/duplicate 計數、偏好只補空缺、`uidOrder` append、active 保留本機、log；`importAccountsAndFetchHoYoWiki` log 改欄位 |
| `lib/state/update_progress.dart` | `ImportResult` 欄位改版 |
| `lib/widgets/update_progress_dialog.dart` | 改用新 `ImportResult` 欄位與新 `progressDoneImportSummary` 簽名 |
| `lib/pages/settings_page.dart` | `_import`：badge 改合併、改用 `showConfirmDialog`、內文改寫；`_clearGallery`／`_refetchAll` 改用抽取後的 `showConfirmDialog` |
| `lib/widgets/dialogs/confirm_dialog.dart` | 新增 `showConfirmDialog`（無打字閘、`isDanger` 參數） |
| `lib/widgets/dialogs/accounts_picker_dialog.dart` | `_PickerRow` badge 改中性 token |
| `lib/l10n/app_*.arb`（已翻譯語系） | 見 i18n 段 |

## 錯誤處理

- 合併為純記憶體運算，唯一 I/O 風險在 `storage.save`，維持既有 `_atomicWrite`（寫 `.tmp` 後 rename 到目標；rename 失敗則該帳號磁碟資料不變、`.tmp` 殘留）與 per-account `try/catch`。
- 本機檔案損毀的容錯維持現狀：合併以已載入記憶體的 `state.byUid` 為來源，不重讀磁碟。
- `ref.mounted` 檢查與提前返回路徑全部保留，且提前返回也回傳正確的 `addedRecords` / `duplicateRecords` 累計值。

## 測試計畫

- **`BannerStorage.mergeWith` 單元測試**：union；id 去重；降序排序；banner key 聯集（其中一邊缺某 banner）；`lastUpdated` 取較新；同 id 的 lang 回填（本機空、備份非空）；空本機 / 空備份邊界；本機與備份完全不重疊。
- **`_runImport`（`debugImportOnly`）測試**：
  - 既有 UID **合併不覆蓋**：本機 `[A,B]` ＋ 備份 `[B,C]` → `[A,B,C]`，`addedRecords=1`、`duplicateRecords=1`。
  - 本機獨有 UID 完全不動。
  - 備份新 UID 加入，且 `uidOrder` append 在最後、本機既有順序不變。
  - 別名只補空缺：本機已有別名不被備份覆蓋；備份空別名不清掉本機別名。
  - active 三層 fallback：(1) 本機有效 → 保留本機；(2) 本機無效、備份有效 → 採用備份；(3) 兩者皆無、`newOrder` 非空 → `newOrder.first`。
  - **更新**目前假設覆蓋語意的既有測試：`test/state/gacha_repository_test.dart`（別名 merge 測試與「overwritten」註解約 1108-1126；`uidOrder` 測試約 1189-1191）、`test/state/gacha_repository_import_with_hoyowiki_test.dart`（`totalRecords` 斷言 184、230 改驗新欄位）。
- **Widget 測試**：
  - `test/widgets/dialogs/confirm_dialog_test.dart`：新增 `showConfirmDialog`（不需打字即可確認、`isDanger` 配色）測試；既有 `showConfirmTypeDialog` 測試不動。
  - `test/widgets/dialogs/accounts_picker_dialog_test.dart`：badge 文字斷言（約 26、166）改為「合併」文案。

## i18n

ARB key 異動（先寫 `lib/l10n/app_zh.arb`，再以中文為基準翻**已實際翻譯過**的語系；空殼 ARB 留給 Crowdin pipeline，不主動補）：

- **新增**：
  - `settingsImportMergeBadge` ＝「合併」
  - `settingsImportConfirmMergeHeader` ＝「下列帳號將與本機資料合併，不會刪除既有記錄：」
- **改寫**：
  - `settingsImportConfirmIntro`：「即將匯入 {accounts} 個帳號（共 {records} 筆紀錄）」→ 合併語意（如「即將合併 {accounts} 個帳號（共 {records} 筆紀錄）」）
  - `progressDoneImportSummary`：2 → 3 placeholder（successAccounts、addedRecords、duplicateRecords），如「已合併 {accounts} 個帳號：新增 {added} 筆、已存在 {duplicate} 筆」
- **刪除**（全語系；刪前再全域 grep 確認無其他引用）：`settingsImportOverwriteBadge`、`settingsImportConfirmWarning`、`settingsImportConfirmOverwriteHeader`
- **保留**：`settingsImportConfirmNoConflict`、`settingsImportConfirmPreserveFooter`
- CJK 全形標點；結尾省略號一律半形 `...`。

## 非目標（YAGNI）

- 不提供「合併／覆蓋」切換（永遠合併）。
- 不支援 UIGF / SRGF / Excel 等外部格式（維持自家 `AccountsBundle` JSON）。
- 不重構 `fetchBannerWithMerge` 抓取流程。
- 不改 `_clearGallery`／`_refetchAll` 的危險紅色語意（僅抽取共用 helper，傳 `isDanger: true` 維持現狀）。
- 不為 picker badge 加 enum 樣式參數（唯一消費者直接改色即可）。
