# 別名同步：較新的修改勝出 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 清空或修改帳號別名後，其他裝置同步或匯入備份檔時也跟著變。

**Architecture:** 本機為每個別名記錄最後修改時間（含清空）。匯出時帶上 `alias_updated_at`。合併時，雲端同步、匯入備份檔與「內容相同就跳過合併」三處都用同一個純函式判斷：較新的勝出，沒有時間的舊資料沿用舊規則。

**Tech Stack:** Flutter／Dart、Riverpod、shared_preferences（`SettingsStorage`）。

**Spec:** `docs/superpowers/specs/2026-11-24-alias-sync-newer-wins-design.md`

## Global Constraints

- **JSON 欄位**：`alias_updated_at`，ISO 8601 UTC 字串（同 `exported_at`，用 `toUtc().toIso8601String()`）。
- **本機偏好**：key 是 `pref.uidAliasUpdatedAt`，內容為 JSON 物件，UID 對應 ISO 8601 字串。損毀時記 warning、重設為空。
- **schema 版本**：`AccountsBundle.currentSchemaVersion` 維持 1。
- **合併規則**：
  - 兩邊都有時間：較新的勝出，時間相同保留本機。
  - 只有匯入方有時間：匯入方勝出。
  - 只有本機有時間：保留本機。
  - 兩邊都沒有時間：本機有別名就保留，沒有才用匯入方的。
- **清空別名**：`uidAliases` 移除該 UID，`uidAliasUpdatedAt` 保留時間。匯出時不寫 `alias`，但寫 `alias_updated_at`。
- **程式慣例**：
  - log 訊息用英文，不記別名內容；UID 要經 `sanitizeUid`。
  - 每個宣告都要寫一行 `///` dartdoc。
  - 註解與 dartdoc 用繁中全形標點。
- **提交前**：`fvm dart format lib/ test/`、`fvm flutter analyze`（No issues found!）、`fvm flutter test`（All tests passed!）都要通過。commit 用 PowerShell 執行（GPG 簽章），訊息用英文 conventional commits，結尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

- **舊資料升級**：本機與雲端都沒有時間時，行為和現在完全相同（既有的 keep-local 測試要保持綠燈）。
- **雲端有「已清空」記錄**：沒有 `alias`、只有較新的 `alias_updated_at` 時，本機別名要被移除，而且不能被「內容相同就跳過」擋掉。
- **時間格式錯誤**：`alias_updated_at` 不是合法字串或型別不對時，當成沒有時間，帳號照常匯入。
- **刪除帳號與清除全部**：`removeUidFromSettings` 與 `clearAllUidPreferences` 也要移除時間，不留下孤兒記錄。
- **別名沒變**：沿用現有的「與現值相同不寫入」，不更新時間，也不觸發同步。

---

### Task 1: 合併規則與時間解析（純函式）

**Files:**
- Create: `lib/models/alias_merge.dart`
- Test: `test/models/alias_merge_test.dart`

**Interfaces:**
- Produces:
  - `DateTime? parseAliasUpdatedAt(Object? raw)`：字串能被 `DateTime.tryParse` 解析就回傳 UTC，否則回傳 null。
  - `bool incomingAliasWins({required String? localAlias, required DateTime? localUpdatedAt, required String? incomingAlias, required DateTime? incomingUpdatedAt})`：依 Global Constraints 的合併規則判斷。在「兩邊都沒有時間」時，只有本機別名是 null 或空白、且匯入方別名不是空白才回傳 true。
- 只用 `dart:core`，能在 `Isolate.run` 裡呼叫。

- [ ] **Step 1: Write the failing tests**：`test/models/alias_merge_test.dart`

```dart
final t1 = DateTime.utc(2026, 11, 24, 1);
final t2 = DateTime.utc(2026, 11, 24, 2);
// 兩邊都有時間
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: t1, incomingAlias: 'B', incomingUpdatedAt: t2), isTrue);
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: t2, incomingAlias: 'B', incomingUpdatedAt: t1), isFalse);
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: t1, incomingAlias: 'B', incomingUpdatedAt: t1), isFalse); // 相同保留本機
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: t1, incomingAlias: null, incomingUpdatedAt: t2), isTrue); // 較新的清空
// 只有一邊有時間
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: null, incomingAlias: null, incomingUpdatedAt: t1), isTrue);
expect(incomingAliasWins(localAlias: null, localUpdatedAt: t1, incomingAlias: 'B', incomingUpdatedAt: null), isFalse);
// 都沒有時間（舊規則）
expect(incomingAliasWins(localAlias: 'A', localUpdatedAt: null, incomingAlias: 'B', incomingUpdatedAt: null), isFalse);
expect(incomingAliasWins(localAlias: null, localUpdatedAt: null, incomingAlias: 'B', incomingUpdatedAt: null), isTrue);
expect(incomingAliasWins(localAlias: null, localUpdatedAt: null, incomingAlias: null, incomingUpdatedAt: null), isFalse);
// 解析
expect(parseAliasUpdatedAt('2026-11-24T01:00:00.000Z'), t1);
expect(parseAliasUpdatedAt('not a date'), isNull);
expect(parseAliasUpdatedAt(123), isNull);
expect(parseAliasUpdatedAt(null), isNull);
```

- [ ] **Step 2: Run**：`fvm flutter test test/models/alias_merge_test.dart`。預期 FAIL（檔案不存在）。
- [ ] **Step 3: Implement**：在 `lib/models/alias_merge.dart` 實作上面兩個函式。
- [ ] **Step 4: Run**：同一個指令。預期 PASS。
- [ ] **Step 5: Commit**：`feat(alias): add the newer-wins alias merge rule`

### Task 2: 本機記錄別名修改時間

**Files:**
- Modify:
  - `lib/services/settings_storage.dart`：`AppSettings` 加欄位、`copyWith`、load／save、新增 `_parseAliasTimes`。
  - `lib/state/settings.dart`：`setUidAlias`、`removeUidFromSettings`、`clearAllUidPreferences`、`applyImportedPreferences`。
- Test: `test/services/settings_storage_test.dart`、`test/state/settings_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `parseAliasUpdatedAt`（解析每個值）。
- Produces:
  - `AppSettings.uidAliasUpdatedAt`：`Map<String, DateTime>`，預設 `const {}`。
  - `copyWith({Map<String, DateTime>? uidAliasUpdatedAt})`
  - `applyImportedPreferences({required Map<String, String> aliases, required Map<String, DateTime> aliasUpdatedAt, required List<String> uidOrder, required String? lastActiveUid})`
- 現有的呼叫端只有 `GachaRepository._runImport`，Task 4 才改。這個 Task 先傳 `currentSettings.uidAliasUpdatedAt`，讓編譯通過。

- [ ] **Step 1: Write the failing tests**
  - `settings_storage_test.dart`
    - 存入 `{'800000001': DateTime.utc(2026,11,24,1)}` 再讀回，值相等。
    - `pref.uidAliasUpdatedAt` 是 `'not json'` 時讀回 `{}`。
    - 單一值無法解析時，略過該筆，其他照讀。
  - `settings_test.dart`
    - `setUidAlias('u', '甲')` 之後，`uidAliasUpdatedAt['u']` 在呼叫前後的 `DateTime.now().toUtc()` 之間。
    - 清空（`setUidAlias('u', null)`）之後，`uidAliases` 沒有 `u`，`uidAliasUpdatedAt['u']` 存在而且有更新。
    - 設成相同的值時，時間不變。
    - `removeUidFromSettings('u')` 與 `clearAllUidPreferences()` 之後，`uidAliasUpdatedAt` 不含 `u`。
- [ ] **Step 2: Run**：`fvm flutter test test/services/settings_storage_test.dart test/state/settings_test.dart`。預期 FAIL。
- [ ] **Step 3: Implement**：時間一律存 UTC，`setUidAlias` 用 `DateTime.now().toUtc()`。
- [ ] **Step 4: Run**：同上。預期 PASS。
- [ ] **Step 5: Commit**：`feat(settings): record when each account alias last changed`

### Task 3: 匯出與讀取 `alias_updated_at`

**Files:**
- Modify:
  - `lib/models/accounts_bundle.dart`（`ExportedAccount`）
  - `lib/services/accounts_export.dart`：`exportAccounts`、`exportAccountsInBackground`、`exportAccountsBytesInBackground`、`_exportInBackground` 都加 `required Map<String, DateTime> uidAliasUpdatedAt`。
  - 呼叫端：`lib/state/cloud_sync.dart` 約 489 行、`lib/pages/settings_page.dart` 約 626 行，傳 `settings.uidAliasUpdatedAt`。
- Test: `test/models/accounts_bundle_test.dart`、`test/services/accounts_export_test.dart`（現有呼叫補上新參數）

**Interfaces:**
- Consumes: Task 1 的 `parseAliasUpdatedAt`、Task 2 的 `AppSettings.uidAliasUpdatedAt`。
- Produces: `ExportedAccount({required BannerStorage data, String? alias, DateTime? aliasUpdatedAt})` 與欄位 `final DateTime? aliasUpdatedAt`。

- [ ] **Step 1: Write the failing tests**
  - `ExportedAccount(data: d, alias: null, aliasUpdatedAt: t1).toJson()`：不含 `alias`，`alias_updated_at == '2026-11-24T01:00:00.000Z'`。
  - `fromJson` 讀回 `aliasUpdatedAt == t1`、`alias == null`。
  - `alias_updated_at: 42` 時，`aliasUpdatedAt` 為 null，帳號照常解析。
  - `exportAccounts(..., uidAliasUpdatedAt: {'uid': t1})` 的輸出中，該帳號有 `alias_updated_at`。
- [ ] **Step 2: Run**：`fvm flutter test test/models/accounts_bundle_test.dart test/services/accounts_export_test.dart`。預期 FAIL。
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run**：同上，再加 `fvm flutter analyze`。預期 PASS、No issues found!
- [ ] **Step 5: Commit**：`feat(export): carry the alias change time in exported accounts`

### Task 4: `_runImport` 依時間合併別名

**Files:**
- Modify: `lib/state/gacha_repository.dart`（`_runImport` 的別名合併段，約 1522–1556 行）
- Test: `test/state/gacha_repository_test.dart`（在現有 `importAccounts: keeps local alias on conflict` 附近加測試）

**Interfaces:**
- Consumes: Task 1 的 `incomingAliasWins`、Task 2 的 `applyImportedPreferences(aliasUpdatedAt:)`、Task 3 的 `ExportedAccount.aliasUpdatedAt`。

- [ ] **Step 1: Write the failing tests**
  - 本機別名「甲」、時間 t1。bundle 沒有 `alias`、`aliasUpdatedAt` 是 t2：匯入後 `uidAliases` 沒有該 UID，`uidAliasUpdatedAt` 是 t2。
  - 本機別名「甲」、時間 t2。bundle 別名「乙」、時間 t1：保留「甲」與 t2。
  - 本機別名「甲」、沒有時間。bundle 別名「乙」、時間 t1：變成「乙」與 t1。
  - 既有的 `keeps local alias on conflict`（兩邊都沒有時間）不改，保持綠燈。
- [ ] **Step 2: Run**：`fvm flutter test test/state/gacha_repository_test.dart`。預期新測試 FAIL。
- [ ] **Step 3: Implement**
  - 匯入方勝出時：別名有值就寫入，沒有值就移除；有時間就寫入時間。
  - 有別名被覆寫或清空時，記 `_log.info('import aliases: taken=$taken cleared=$cleared')`。
- [ ] **Step 4: Run**：同上，再加 `fvm flutter test test/state/gacha_repository_cloud_import_test.dart`。預期 PASS。
- [ ] **Step 5: Commit**：`fix(import): let the newer alias change win when merging accounts`

### Task 5: 「內容相同就跳過合併」改用同一條規則

**Files:**
- Modify: `lib/services/cloud_sync/cloud_sync_service.dart`（`_identicalAccountsInBackground`）
- Test: `test/services/cloud_sync/cloud_sync_service_test.dart`（擴充 `_bundleJson`，加 `Map<String, String> aliasTimes = const {}`，寫入 `alias_updated_at`）

**Interfaces:**
- Consumes: Task 1 的 `incomingAliasWins`、`parseAliasUpdatedAt`。

- [ ] **Step 1: Write the failing tests**
  - 雲端沒有別名、`alias_updated_at` 為 t2；本機別名「本機名」、時間 t1，其餘相同：`applyRemote` 被呼叫。
  - 雲端「雲端名」t2，本機「本機名」t1：被呼叫。
  - 雲端「雲端名」t1，本機「本機名」t2：不呼叫。
  - 既有兩個別名測試（「雲端有別名、本機沒有 → 合併」「本機已有別名 → 跳過」）不改，保持綠燈。
- [ ] **Step 2: Run**：`fvm flutter test test/services/cloud_sync/cloud_sync_service_test.dart`。預期新測試 FAIL。
- [ ] **Step 3: Implement**
  - `content()` 移除 `alias` 與 `alias_updated_at`。
  - 判斷條件改成 `content(l) == content(value) && !incomingAliasWins(...)`。
  - 更新函式的 dartdoc 與行內註解。
- [ ] **Step 4: Run**：同上。預期 PASS。
- [ ] **Step 5: Commit**：`fix(cloudsync): judge the identical-account skip by alias change time`

### Task 6: 全套驗證與記錄

- [ ] **Step 1**：`fvm dart format lib/ test/`、`fvm flutter analyze`、`fvm flutter test`，全部通過。
- [ ] **Step 2**：spec 狀態改成「實作完成」，附錄列出 commit。實測（兩台裝置連同一個雲端帳號）要等使用者同意才做，附錄記下結果或「待實測」。
- [ ] **Step 3: Commit**：`docs(spec): record the newer-wins alias sync results`
