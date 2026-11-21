# 畫面停住的效能修正（子專案 12）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把鳴潮筆記第 42～45 節的「主 isolate 停頓」修正（雲端同步、存檔、匯入匯出、轉換資料語言、進度對話框、語言對照表、設定頁選單）移植到原神，並在 ROG Phone 上量修正前後的停頓。

**Architecture:** 以鳴潮 commit 為單位依序移植（`4a0a9db`～`19a911d`），套到原神現有結構上；雲端同步與匯入匯出幾乎可逐行套用，存檔與資料模型依原神格式改寫（spec 第四節）。先搬量測工具、量修正前（Task 1、2），最後量修正後並在 Windows 實跑（Task 13）。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、`dart:isolate`（`Isolate.run`）、`package:http`、googleapis、flutter_test；量測用 Python 3 + `websockets`。

**Spec:** `docs/superpowers/specs/2026-11-21-ui-stall-fixes-design.md`（必讀；第二節是 commit 對照，第四節是原神差異與做法，第五節是量測，第六節是驗收）。鳴潮筆記：`git -C ../wuthering-waves-convene-gacha-analyzer show origin/master:docs/Android移植筆記.md` 第 42～45 節。

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。
- 看改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`。比對原神與鳴潮差異時，鳴潮基準是 `4a0a9db~1`，比對要加 `--strip-trailing-cr`（原神檔案是 CRLF）。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；`playerId` → `uid`；卡池代碼 `t.key` → `t.gachaType`；記錄檔 `recordsFile` 對應原神 `<uid>.json`；「紀錄」→「記錄」；「喚取」→「祈願」。
- 鳴潮的測試改寫到原神既有的測試檔與 helper 上（對應表見各 Task）；既有斷言不可刪減。
- 鳴潮的改法在原神行不通、或需要改變原神特有行為時，回報 NEEDS_CONTEXT，不要自行改寫（使用者原則：偏離姐妹專案前先問）。spec 第四節已決定的偏離照 spec 做。

## Global Constraints

- 不新增依賴（`http`、`googleapis`、`googleapis_auth` 原神 `pubspec.yaml` 都已有）。不改 `android/`、manifest、`rust/`、`rust_builder/`、ARB。
- 送進 `Isolate.run` 的閉包寫在 top-level 函式裡、只抓參數；背景 isolate 的 `Logger` 不會進 App log，要記錄的錯誤丟回主 isolate 再記；例外原樣傳回，既有 `on FormatException` 等分支不改。
- 照搬鳴潮新增的 log（英文、`Logger` 命名對齊原神既有樹、敏感資料經 `sanitizeUid`／`sanitizeUrl`），例如 `already in sync (merge and upload skipped)`、`uploaded=skipped (unchanged)`；不另外新增。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；註解中文全形標點。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（輸出必須含 `All tests passed!`；不可用 `| tail -1` 的結束碼判斷）。commit 英文 conventional commits，subject 沿用鳴潮對應 commit 的 subject（合併多個時用第一個，body 列其餘 subject），結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（Git Bash 裡 GPG 簽章會失敗，不可跳過簽章）。分支 `feat/android`，不開新分支、不 push。
- 手機、Windows 視窗的操作只在 Task 2、Task 13，由主控執行，每次都要使用者明講「接好了／可以測」或同意操作電腦才開始。

## Review Focus

1. **兩邊帳號不同時的同步**：雲端有本機沒有的帳號、或本機有雲端沒有的帳號，「挑出內容相同的帳號不送進合併」不可把只在一邊的帳號漏掉 → Task 7 加測試 `identical-account skip keeps accounts that exist on one side only`。
2. **雲端檔損毀或版本過新**：在背景解析時拋出的 `FormatException`／版本過新例外，主 isolate 仍走原本的錯誤分支、狀態列顯示同樣的錯誤、App log 有 warning → Task 3 加測試 `corrupt cloud bundle still reports schema error after background parse`。
3. **token 失效時上傳／下載**：背景直接打 Drive REST 收到 401 帶 `www-authenticate` 時，丟 `AccessDeniedException`，既有「需要重新連結」流程照常（Windows、Android 都是）→ Task 5、7 的 remote 測試涵蓋下載與上傳兩條。
4. **匯出時某帳號只在記憶體、還沒有記錄檔**：背景讀檔匯出不可漏掉這個帳號或拋錯（鳴潮 `e526a20` 用 `inMemory` 補）→ Task 5 加測試 `export includes an account whose records file does not exist yet`。
5. **匯入損毀或外來的檔案**：背景解析失敗時，設定頁照原本顯示錯誤，log 由設定頁的錯誤分支在主 isolate 記錄 → Task 8 的 `settings_page_import_button_test` 加一個損毀檔案案例。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `tool/measure_ui_stalls.py`（新） | 實機量主 isolate 停頓 | 1 |
| `test/helpers/wait_until.dart`、三個自帶 helper 的測試、`test/state/gacha_repository_test.dart` | 共用等待工具、等 bootstrap | 3 |
| `lib/services/cloud_sync/cloud_sync_service.dart`、`lib/state/cloud_sync.dart` | 同步一輪的流程、指紋、變動檢查 | 4、5、6、7、8 |
| `lib/services/cloud_sync/cloud_sync_remote.dart` | Drive 下載／上傳 | 5、7 |
| `lib/services/gacha_storage.dart` | 記錄檔路徑、背景編碼存檔 | 5、8 |
| `lib/services/accounts_export.dart`、`lib/services/accounts_import.dart` | 背景匯出、匯入解析 | 5、8 |
| `lib/models/banner_storage.dart` | `sameContentAs` | 6 |
| `lib/state/gacha_repository.dart` | 合併匯入／同步、統一資料語言 | 6、8 |
| `lib/pages/settings_page.dart` | 匯出匯入按鈕、語言選單 | 8、11 |
| `lib/widgets/update_progress_dialog.dart` | 進度清空時自己關 | 9 |
| `lib/services/lang_catalog_storage.dart` | 背景讀語言對照表 | 10 |
| 本 spec 附錄 A、B | 落點、量測結果 | 2、12、13 |

---

### Task 1: 量測工具

**Files:** Create `tool/measure_ui_stalls.py`

- [ ] **Step 1:** 從鳴潮 `1b7f8e8` 取出整檔（`git -C ../wuthering-waves-convene-gacha-analyzer show 1b7f8e8:tool/measure_ui_stalls.py`），只改兩處：`PKG = 'tw.reh.genshin.gacha'`；`bursts` 辨識 App 函式的 Dart 套件字串改成 `'genshin_impact_wish_gacha_analyzer'`。說明文字裡提到鳴潮的地方換成原神用語。
- [ ] **Step 2:** 驗證：`python -m py_compile tool/measure_ui_stalls.py` 無輸出；`grep -n "wuthering\|wuwa" tool/measure_ui_stalls.py` 無結果。
- [ ] **Step 3:** 照 Global Constraints 跑 format／analyze／test，Commit `chore(tool): add the on-device UI stall measurement script`。

### Task 2: 量修正前（主控執行，需要使用者同意動手機）

依 spec 第五節。
- [ ] **Step 1:** 記下手機現況：`cmd window user-rotation`、`settings get system accelerometer_rotation`、無障礙服務、安裝版本、App 內雲端同步是否已連結（設定頁截圖）。沒連結就請使用者在手機上連結，不代為登入。情境 1B 前確認手機與電腦是同一個 Google 帳號、帳號清單相同（800…、801…），不同就停下來問使用者。
- [ ] **Step 2:** `fvm flutter build apk --profile --target-platform android-arm64 --dart-define-from-file=secrets/cloud_sync_defines.json`，`adb install -r`；`export ANDROID_SERIAL=SBAIOC583904X7L`。
- [ ] **Step 3:** 依序量 spec 第五節的情境 1A、1B、2、3、4、5、6，每個情境的動作檔與輸出放 scratchpad。座標先手動操作、截圖確認。情境 1B 的電腦端同步：Windows 已安裝的正式版開一次即可（不用 debug 版），開之前使用者同意。情境 6 用 `dump` 模式，請使用者在手機上按「更新記錄」並開遊戲進祈願歷史頁。
- [ ] **Step 4:** `python tool/measure_ui_stalls.py bursts <輸出目錄>` 每個情境取最長 5 段與主因函式，寫進 spec 附錄 B「修正前」；標出原神獨有路徑（logcat 輪詢、HoYoWiki、物品類型）超過 16 ms 的停頓。
- [ ] **Step 5:** 還原：裝回 debug 版（`fvm flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=secrets/cloud_sync_defines.json`）、轉向隔幾秒再查、帳號切回朋友帳號、電腦切回 801…。
- [ ] **Step 6:** Commit `docs(spec): record the UI stalls before the fixes`。

### Task 3: 共用等待工具與等 bootstrap

**Files:** Modify `test/helpers/wait_until.dart`、`test/widgets/dialogs/game_dir_help_dialog_test.dart`、`test/widgets/share/share_image_progress_test.dart`、`test/state/gacha_repository_web_cache_test.dart`、`test/state/gacha_repository_test.dart`

**Interfaces:** Produces `Future<void> pumpUntil(WidgetTester tester, bool Function() cond, {Duration timeout = const Duration(seconds: 5)})`（照鳴潮 `test/helpers/wait_until.dart`）。`waitUntil` 保留原神現有寫法。

- [ ] **Step 1:** 加 `pumpUntil`；三個測試檔自帶的 `_pumpUntil`／`_until` 改用共用的 `pumpUntil` 或 `waitUntil`（語意對應者），刪掉本地 helper。
- [ ] **Step 2:** `gacha_repository_test.dart` 的 31 處 `Future.delayed(50ms)`：用來等帳號從磁碟載入的改成 `await container.read(gachaRepositoryProvider.notifier).waitForBootstrap()`（以原神 `GachaRepository.waitForBootstrap` 的實際呼叫方式為準）；等其他非同步結果的改成 `waitUntil(<條件>)`；兩者都不是的保留並在報告列出。
- [ ] **Step 3:** 驗證：`fvm flutter test test/state/gacha_repository_test.dart test/widgets/dialogs/game_dir_help_dialog_test.dart test/widgets/share/share_image_progress_test.dart test/state/gacha_repository_web_cache_test.dart` 全過；全套連跑兩次都過。
- [ ] **Step 4:** Commit `test: share the wait helpers and wait for bootstrap explicitly`。

### Task 4: 同步的 JSON 工作移到背景、雲端已是最新時跳過上傳（鳴潮 `4a0a9db`、`57eb498`）

**Files:** Modify `lib/services/cloud_sync/cloud_sync_service.dart`、`lib/state/cloud_sync.dart`；Test `test/services/cloud_sync/cloud_sync_service_test.dart`

**Interfaces:** Produces `Future<String> syncFingerprintInBackground(String bundleJson)`；`runSyncRound` 的 `exportLocal` 參數從原神現在的 `String Function()`（`cloud_sync_service.dart` 約第 54 行）改成 `Future<String> Function()`；`_importInBackground(String json)` 回傳 `Future<(AccountsBundle, String)>`（bundle 與遠端指紋）。

- [ ] **Step 1:** 照搬兩個 commit 在 `cloud_sync_service_test.dart` 新增與修改的測試（含「雲端與本機指紋相同時不上傳」），跑一次確認新測試失敗。
- [ ] **Step 2:** 照搬兩個 commit 的 lib 改動；`cloud_sync.dart` 的 `_exportLocal` 改成回傳 `Future<String>`，原本同步呼叫它的地方（約第 444 行變動檢查）一併改成 await。
- [ ] **Step 3:** 加 Review Focus 2 的測試：雲端內容是損毀 JSON、以及版本過新時，`runSyncRound` 拋出的例外型別與改版前相同，`cloud_sync.dart` 記錄的錯誤 token 不變（`'schemaTooNew'` 等）。
- [ ] **Step 4:** 相關測試全過後 Commit（subject `perf(cloudsync): move bundle JSON work off the UI isolate`，body 列 `57eb498` 的 subject）。

### Task 5: 下載與匯出不碰主 isolate、解碼編碼在背景（鳴潮 `c80f960`、`e526a20`）

**Files:** Modify `lib/services/cloud_sync/cloud_sync_remote.dart`、`lib/services/gacha_storage.dart`、`lib/state/cloud_sync.dart`；Create `test/services/cloud_sync/cloud_sync_remote_test.dart`；Modify `test/helpers/cloud_sync_fakes.dart`、`test/state/cloud_sync_test.dart`

**Interfaces:**
- Produces `Future<({String text, int bytes})> fetchDriveMedia(String fileId, String accessToken, {http.Client? client})`（簽名以鳴潮為準）。錯誤對應：`www-authenticate` → `AccessDeniedException`，其他非 2xx → `DetailedApiRequestError`。
- Produces `File GachaStorage.recordsFile(String uid)`：原本私有的 `_dataFile` 公開改名（回傳 `<baseDir>/<uid>.json`），類內原本的呼叫一併改。
- 匯出背景化：照鳴潮把「全部帳號的記錄檔路徑＋只在記憶體的帳號」送進背景，由背景讀檔組 bundle。

- [ ] **Step 1:** 照搬兩個 commit 新增的測試（remote 測試新建檔案；`cloud_sync_test.dart` 的案例改寫成原神帳號）。加 Review Focus 4 的測試 `export includes an account whose records file does not exist yet`：一個帳號只在 `byUid`、磁碟沒有 `<uid>.json`，匯出結果含該帳號且內容等於記憶體版本。確認新測試失敗。
- [ ] **Step 2:** 照搬 lib 改動。查檔案 ID 仍在主 isolate 用 googleapis；第一次建檔仍走 googleapis。
- [ ] **Step 3:** 測試全過後 Commit（subject `perf(cloudsync): decode and encode the bundle off the UI isolate`，body 列 `e526a20`）。

### Task 5b: 存檔、刪除在 Windows 被背景讀檔擋住時短暫重試（spec 第二節「追加三」）

**Files:** Modify `lib/services/gacha_storage.dart`（`_atomicWrite` 的 rename、`delete`／其他刪除記錄檔的地方）；Test `test/services/gacha_storage_test.dart`

- [ ] **Step 1:** 新增測試（Windows 才有這個鎖定行為，非 Windows 用 `skip: !Platform.isWindows` 跳過）：
  - `save retries when the records file is briefly held open`：先用 `RandomAccessFile` 開著 `<uid>.json`，50 ms 後關閉；同時呼叫 `save`，結果成功、檔案內容是新的。
  - `save still throws when the records file stays locked`：一直開著不關，`save` 最後拋 `PathAccessException`，而且 `.tmp` 不會被當成資料留下來誤讀（`listKnownUids` 不含它）。
  - `delete retries when the records file is briefly held open`：同第一個，改測 `delete`。

  在 Windows 跑，確認失敗。
- [ ] **Step 2:** 在 `GachaStorage` 加一個私有 helper，重試只針對 `PathAccessException`：最多 5 次，等待從 20 ms 開始每次加倍（總共約 300 ms）。rename 與 delete 都走它；重試後成功時記 `info` log（英文，帶 `sanitizeUid` 後的 uid 和重試次數），用盡就照原本拋出。
- [ ] **Step 3:** 相關測試全過後 Commit `fix(storage): retry rename and delete while another isolate holds the file`。
- 鳴潮的同一修正由主控在鳴潮分支 `fix/cloud-sync-follow-ups` 做，不屬於這個任務。

### Task 6: 雲端已相同時跳過合併（鳴潮 `f4d8555`）

**Files:** Modify `lib/models/banner_storage.dart`、`lib/services/cloud_sync/cloud_sync_service.dart`、`lib/state/gacha_repository.dart`；Test `test/models/banner_storage_test.dart`、`test/services/cloud_sync/cloud_sync_service_test.dart`、`test/state/cloud_sync_test.dart`、`test/state/gacha_repository_cloud_import_test.dart`

**Interfaces:** Produces `bool BannerStorage.sameContentAs(BannerStorage other)`：比對 `uid`、`lastUpdated`、卡池數、每個卡池的記錄數與逐筆記錄（top-level 私有 `_sameRecord` 比對原神 `GachaRecord` 全部欄位：`id`、`uid`、`gachaType`、`name`、`itemType`、`rankType`、`time`、`lang`）。`GachaRecord` 不定義 `==`。

- [ ] **Step 1:** 測試（先寫、確認失敗）：
  - `banner_storage_test`：`sameContentAs` 對相同內容回 true；`lang` 不同、`lastUpdated` 不同、某卡池多一筆、`name` 不同各回 false。
  - `gacha_repository_cloud_import_test`：合併後與本機內容相同 → 不呼叫 `storage.save`（用既有 fake storage 計數）、`state.byUid` 與合併前 `identical`；內容不同但新增 0 筆（只有 `lastUpdated` 較新）→ 寫檔、`addedRecords == 0`；新增 1 筆 → 寫檔、`addedRecords == 1`。
  - `cloud_sync_test`：雲端與本機相同時一輪同步不寫檔、不呼叫資料語言轉換（spec 第四節「同步時不再順帶轉換資料語言」）；`addedRecords > 0` 時才觸發 HoYoWiki 補抓（沿用原神約第 341 行的條件，測試鎖住新增 0 筆時不補抓）。
  - 照搬 `f4d8555` 在 `cloud_sync_service_test` 新增的案例。
- [ ] **Step 2:** 照搬 lib 改動；`gacha_repository.dart` 的位置在原神約第 1466～1473 行（`mergeWith` → `_convertAccountToDataLanguage` → `save`）與最後替換 `byUid` 處。內容相同時沿用 `localBefore`、不寫檔。
- [ ] **Step 3:** 測試全過後 Commit `perf(cloudsync): skip the merge when the cloud copy already matches`。

### Task 7: 上傳原始位元組、跳過相同帳號（鳴潮 `52cb8c8`）

**Files:** Modify `lib/services/cloud_sync/cloud_sync_remote.dart`、`lib/services/cloud_sync/cloud_sync_service.dart`；Test `test/services/cloud_sync/cloud_sync_remote_test.dart`、`test/services/cloud_sync/cloud_sync_service_test.dart`

**Interfaces:** Produces `Future<int> putDriveMedia(String fileId, String accessToken, String content, {http.Client? client})`（`uploadType=media`，回傳送出的位元組數）、私有 `_throwIfDriveError(http.Response resp, String action)`、`_identicalAccountsInBackground(String remoteJson, String localJson)` → `Future<Set<String>>`。

- [ ] **Step 1:** 照搬 `52cb8c8` 的測試；加 Review Focus 1 的測試 `identical-account skip keeps accounts that exist on one side only`：雲端有 A、B，本機有 B、C，B 相同 → 送進合併的是 A（以及 C 保留在本機），合併後三個帳號都在；加 Review Focus 3 的上傳案例：PATCH 回 401 帶 `www-authenticate` → `AccessDeniedException`。確認失敗。
- [ ] **Step 2:** 照搬 lib 改動。
- [ ] **Step 3:** 測試全過後 Commit `perf(cloudsync): upload raw bytes off the UI isolate and skip identical accounts`。

### Task 8: 存檔編碼、匯出、匯入解析移到背景；轉換語言沒變就不寫（鳴潮 `b8a6bf1`）

**Files:** Modify `lib/services/gacha_storage.dart`、`lib/services/accounts_export.dart`、`lib/services/accounts_import.dart`、`lib/state/cloud_sync.dart`、`lib/state/gacha_repository.dart`、`lib/pages/settings_page.dart`；Test `test/pages/settings_page_export_test.dart`、`test/pages/settings_page_import_button_test.dart`、`test/state/gacha_repository_data_language_test.dart`

**Interfaces:**
- Produces `Future<String> exportAccountsInBackground({...})`、`Future<Uint8List> exportAccountsBytesInBackground({...})`（參數照鳴潮；記錄檔路徑由 `GachaStorage.recordsFile` 取得），雲端同步與設定頁匯出共用同一實作（Task 5 的同步匯出改呼叫這裡）。
- Produces `Future<AccountsBundle> importAccountsInBackground(String text)`。
- `GachaStorage.save` 的 `jsonEncode(data.toJson())` 改成私有 `_encodeInBackground(BannerStorage data)`；其他（檔名、rethrow、log）不變。

- [ ] **Step 1:** 測試（先寫、確認失敗）：照搬 `b8a6bf1` 在匯出、匯入按鈕測試的改動（用 Task 3 的 `pumpUntil` 等背景結果）；`gacha_repository_data_language_test`：統一資料語言時，0 筆要轉的帳號不寫檔、`byUid` 不換物件；有要轉的照常寫檔。加 Review Focus 5：匯入一個損毀檔案，設定頁顯示與改版前相同的錯誤訊息。
- [ ] **Step 2:** 照搬 lib 改動；`unifyDataLanguage` 在原神約第 1588 行起，`converter.convert` 後 `storage.save` 的那段。
- [ ] **Step 3:** 測試全過後 Commit `perf: move record encoding, export and import parsing off the UI isolate`。

### Task 8b: 開 App 讀存檔在背景解析（spec 第二節「追加二」）

**Files:** Modify `lib/services/gacha_storage.dart`（`load`）；Test `test/services/gacha_storage_test.dart`

- [ ] **Step 1:** 先找 Task 5、8 有沒有已經寫好「在背景讀記錄檔並解析成 `BannerStorage`」的 top-level 函式（例如背景匯出讀 `recordsFile`），有就直接用，不另寫一個。
- [ ] **Step 2:** 確認既有測試涵蓋：正常讀回內容相同、檔案不存在回 null、損毀的 JSON 拋例外且主 isolate 記 `severe` log（`load failed for uid=`）。缺的補上（損毀檔案例要用 `Logger.root.onRecord` 確認 log 在主 isolate 記到）。
- [ ] **Step 3:** `load` 改成在背景 isolate 讀檔、解析、`BannerStorage.fromJson`；`exists` 檢查與 catch／log／`rethrow` 留在主 isolate。
- [ ] **Step 4:** 相關測試全過後 Commit `perf(storage): decode the records file off the UI isolate`。
- 鳴潮的同一修正由主控在鳴潮 master 做，push 前問使用者，不屬於這個任務。

### Task 9: 進度在對話框建構前就清空時自己關（鳴潮 `ac19cfa`、`c0f4217`）

**Files:** Modify `lib/widgets/update_progress_dialog.dart`；Test `test/widgets/update_progress_dialog_test.dart`

- [ ] **Step 1:** 照搬 `ac19cfa` 的測試；加一個 `ConvertingDataLanguage` 流程：開啟時進度非 null、之後清空 → 對話框依原本流程關閉，不因 `_CloseIfIdleOnOpen` 提早關。確認失敗。
- [ ] **Step 2:** 照搬兩個 commit 的改動（`_CloseIfIdleOnOpen` 只在第一次建構時檢查）。
- [ ] **Step 3:** `fvm flutter test test/widgets/update_progress_dialog_test.dart test/widgets/android_log_wait_test.dart` 全過；全套通過後 Commit（subject `fix(update): close the progress dialog when progress cleared before it built`，body 列 `c0f4217`）。

### Task 10: 語言對照表在背景解析（鳴潮 `60b6f2a`）

**Files:** Modify `lib/services/lang_catalog_storage.dart`

**Interfaces:** 私有 top-level `Future<LangCatalog> _loadInBackground(String path)`：把原神 `load` 目前的「讀檔 → `jsonDecode` → 組 `items` → `LangCatalog.fromEntries`」整段放進 `Isolate.run`。`load` 的 warning 與回傳 null 不變。

- [ ] **Step 1:** 改動後 `test/services/lang_catalog_storage_test.dart` 既有案例全過；若缺「損毀檔回 null」的案例就補上（背景 isolate 拋出的例外要被 `load` 的 catch 接住）。
- [ ] **Step 2:** Commit `perf(lang): parse the cached language catalog in a background isolate`。

### Task 11: 設定頁語言選單只排版選中項目（鳴潮 `19a911d`）

**Files:** Modify `lib/pages/settings_page.dart`；Create `test/pages/settings_locale_dropdown_test.dart`

- [ ] **Step 1:** 照搬鳴潮 `settings_locale_dropdown_test.dart`：收合時介面語言選單只建構已選語言的名稱（其他語言名稱的 `Text` 找不到），展開後全部看得到；資料語言選單同樣。確認失敗。
- [ ] **Step 2:** 照搬 `_onlySelectedLabel`，套到 `_LocaleDropdown`（約第 246 行的 `DropdownButtonFormField`）與 `_DataLanguageSection`（約第 1443 行）。setter 不改（spec 第二節）。
- [ ] **Step 3:** 測試全過後 Commit `perf(settings): lay out only the selected label in language dropdowns`。

### Task 11b: 更新結果視窗開著時雲端合併不再當成忙碌（spec 第二節「追加」）

**Files:** Modify `lib/state/gacha_repository.dart`（`importBundleForCloudSync`，約第 1343 行）；Test `test/state/gacha_repository_cloud_import_test.dart`

- [ ] **Step 1:** 新增測試：
  - 進度是 `UpdateCompleted` 時，`importBundleForCloudSync` 正常合併、不拋 `CloudSyncBusyException`，合併後進度仍是同一個 `UpdateCompleted`（視窗內容不變）。
  - 進度是 `UpdateFailed` 時同上。
  - 更新進行中（進度是 `WaitingForCapture` 等非終態）時，仍然拋 `CloudSyncBusyException`。

  跑一次，確認前兩個測試失敗。
- [ ] **Step 2:** 忙碌條件改成 `_isUpdating || (progress != null && progress is! UpdateCompleted && progress is! UpdateFailed)`，log 訊息不變。dartdoc 改成說明終態進度不算忙碌。
- [ ] **Step 3:** 相關測試全過後 Commit `fix(cloudsync): stop treating a finished update dialog as busy`。
- 鳴潮的同一修正由主控在鳴潮 master 做，push 前問使用者，不屬於這個任務。

### Task 12: 附錄 A

- [ ] **Step 1:** spec 附錄 A：每個鳴潮 commit 對應的原神 commit、偏離（`recordsFile` 對應 `<uid>.json`、`sameContentAs` 欄位、同步不再順帶轉換資料語言、只清 `gacha_repository_test` 的延遲、setter 不用改、`81d3dfa` 輪詢不適用），以及實作中遇到的坑。
- [ ] **Step 2:** Commit `docs(spec): record where each WuWa stall fix landed`。

### Task 13: 量修正後、Windows 實跑（主控執行，需要使用者同意）

- [ ] **Step 1:** 手機：照 Task 2 同樣的情境與步驟再量一次，附錄 B 寫成前後對照表，並確認設定頁「上次同步」時間有更新。原神獨有路徑若仍有超過 16 ms 的停頓：修法屬 spec 第五節「同一類」者另開 Task 處理（TDD、單獨 commit），否則停下來回報使用者。測完照 Task 2 Step 5 還原。
- [ ] **Step 2:** Windows：先備份 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`；`fvm flutter run -d windows --dart-define-from-file=secrets/cloud_sync_defines.json`，確認開 App 同步、資料變動後同步、設定頁匯出、匯入都正常，log 有 `already in sync` 或 `uploaded=skipped (unchanged)`；使用中帳號維持 801…。
- [ ] **Step 3:** 附錄 B 補電腦版結果，spec 狀態改為「已完成」，Commit `docs(spec): record the UI stall measurements after the fixes`。
