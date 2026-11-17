# 網頁快取祈願網址備援 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 等待 MITM 攔截期間，背景同時讀遊戲的網頁快取 `data_2`，抓到新出現的祈願網址就跟攔截比快；找不到遊戲資料夾時，玩家可以從等待畫面或設定頁手動指定。

**Architecture:** 照鳴潮版 PR #93（`0d36c79`）的分層：純函式（找網址、轉 API 網址）→ `GameDirLocator`（設定 → `output_log.txt` → 登錄檔 → 常見路徑）→ `WebCacheUrlWatch`（每秒在背景 isolate 讀最新版本資料夾的 `data_2`，用 authkey baseline 判斷新網址）→ `GachaRepository._runMitm` 讓攔截和快取比快。監看器沿用既有的 `CaptureSession` 型別，比快邏輯對稱。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、`win32`（`CreateFile` 共享讀取）、`win32_registry`（列舉 Uninstall 子鍵）、`file_selector`（選資料夾）、`dart:isolate`。

**Spec:** `docs/superpowers/specs/2026-11-17-web-cache-credential-fallback-design.md`（上層：`2026-11-17-android-support-roadmap-design.md`）

**參考實作（唯讀）：** 鳴潮版 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`，用 `git show 0d36c79:<path>` 看當時的版本：
- `lib/state/gacha_repository.dart` 的 `_runMitm`、`_canWaitLogOnly`、`_waitLogOnly`、`_startClientLogWatch`、`_syncLogOnlyNotice`、`_stopClientLogWatch`、`restartClientLogWatch`、`cancelCapture`；
- `lib/services/game_dir_locator.dart`、`lib/widgets/game_dir_picker.dart`、`lib/widgets/dialogs/game_dir_help_dialog.dart`、`lib/pages/settings_page.dart` 的遊戲資料夾區塊、`lib/widgets/update_progress_dialog.dart`；
- 測試：`test/helpers/no_game_dir.dart`、`test/state/gacha_repository_update_test.dart`、`test/widgets/dialogs/game_dir_help_dialog_test.dart`、`test/pages/settings_game_dir_section_test.dart`。

結構、命名、UX 照它，只換本文件與 spec 寫到的地方。

## Global Constraints

- Flutter／Dart 指令一律 `fvm flutter`／`fvm dart`；格式化只跑 `fvm dart format lib/ test/`。
- 每個宣告都要一行 `///` dartdoc（Flutter override 除外）；實作層 `//` 註解只寫「為什麼」。
- Log 一律英文；logger 名稱 `gacha.webCache`。網址一律經 `sanitizeUrl`，路徑一律經 `sanitizeFsPath`。**禁止 log 網址原文或 authkey。**
- Dialog 一律 `AppDialog`（`size: AppDialogSize.sm`）；可點的 `InkWell`／連結顯式 `mouseCursor: SystemMouseCursors.click`。
- 新字串先寫 `app_zh.arb`（template，含英文 `@key` description），再加到 `app_en`、`app_zh_Hans`、`app_es`、`app_fr`、`app_ja`、`app_pt_BR`、`app_th`、`app_vi`。**不要碰其他 22 個空殼 ARB。** ARB 沒有結尾換行。CJK 全形標點，省略號用半形 `...`。用詞照 `docs/術語表.md`（「祈願」「歷史紀錄」）。
- 祈願網址的判定：`https://*.hoyoverse.com/...`，query 有 `auth_appid=webview_gacha` 且 `authkey` 不為空。API 網址：路徑結尾是 `/getGachaLog` 或 `/getBeyondGachaLog`。
- API 網址的網域與路徑：`public-operation-hk4e-sg.hoyoverse.com`、`/gacha_info/api/getGachaLog`。
- authkey 比較前一律用 `Uri.decodeComponent` 解碼原始值（不要用 `queryParameters`，它會把 `+` 轉成空白）。
- 快取檔路徑：`<遊戲資料夾>\GenshinImpact_Data\webCaches\<版本>\Cache\Cache_Data\data_2`；版本資料夾依數字比較，名稱不是 `\d+(\.\d+)*` 的略過。
- 遊戲資料夾有效 ⇔ `<dir>\GenshinImpact_Data` 存在。
- 設定 key：`pref.gameDir`，只存本機，不加入雲端同步。
- 快取監看的任何失敗都**不能**讓更新失敗，只寫 log。
- `win32` 只在 `lib/services/web_cache_reader.dart` import；`win32`、`win32_registry` 改成直接依賴，版本照 `pubspec.lock` 現有的（`win32` 5.15.0、`win32_registry` 2.1.0），用 `^` 寫該版本，不升級。
- Commit message 用英文 conventional commits，結尾附 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。每次 commit 前跑 format、analyze、test（CLAUDE.md）。不要 push。

## Review Focus

1. **網址後面緊接著可列印的雜訊**：`data_2` 是二進位檔，網址結尾可能不是空白或 `\0`。網址要在第一個不可列印字元、空白、`"`、`'`、`<`、`>` 停下；`game_biz` 等最後一個參數被多吃字時，API 仍要能用。Task 1 加測試：網址後接 `\x00`、`\x01`、`"` 都正確截斷。
2. **同一把 authkey 在頁面與 API 網址的編碼不同**（`%2F` vs `%2f`、`/` vs `%2F`）：要視為同一把，否則 baseline 裡的舊 key 會被當成新的。Task 1 加測試。
3. **遊戲更新後第一次開歷史紀錄**：新版本資料夾在監看開始後才建立，裡面的網址要算新的，不能被 baseline 吃掉。Task 4 測試。
4. **說明視窗開著時狀態離開等待**（成功、取消、失敗）：說明視窗和進度視窗都正確關閉，不多 pop、不少 pop。Task 6 測試。
5. **攔截先丟錯、找不到遊戲資料夾**：不能卡在等待畫面沒反應；要顯示選擇資料夾按鈕，取消要有效。Task 5 測試（現有 bug）。

---

### Task 1: 找網址與轉 API 網址的純函式

**Files:**
- Create: `lib/services/gacha_url_extract.dart`
- Test: `test/services/gacha_url_extract_test.dart`

**Interfaces:**
- Produces:
  ```dart
  /// 文字中找到的一筆祈願網址。
  class GachaUrlMatch {
    const GachaUrlMatch({required this.url, required this.authkey, required this.isApi, required this.offset});
    final String url;      // 原文，未改寫
    final String authkey;  // Uri.decodeComponent 後
    final bool isApi;      // 路徑以 /getGachaLog 或 /getBeyondGachaLog 結尾
    final int offset;      // 在輸入文字中的起始位置
  }
  List<GachaUrlMatch> findGachaUrls(String text); // 依 offset 遞增
  String toApiUrl(String url);
  ```

- [ ] **Step 1: 寫失敗測試**（fixture 字串在測試檔裡組；authkey 用假值如 `abc%2Fdef%3D%3D`）
  - 祈願頁 `https://gs.hoyoverse.com/genshin/event/e20190909gacha-df01aea2/index.html?win_mode=fullscreen&auth_appid=webview_gacha&authkey=K1&game_biz=hk4e_global`、頌願頁 `.../e20250716gacha/index.html?...auth_appid=webview_gacha&authkey=K2...`、`https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?...auth_appid=webview_gacha&authkey=K1&gacha_type=301`、`.../getBeyondGachaLog?...` 混在 `\x00\x01` 雜訊中：回傳 4 筆，`isApi` 依序 false、false、true、true，offset 遞增。
  - 公告頁 `https://act.hoyoverse.com/ys/event/blue-post/index.html?auth_appid=announcement&authkey=X` 不回傳；`https://evil.example.com/x?auth_appid=webview_gacha&authkey=X` 不回傳；`authkey=` 空值不回傳。
  - 網址後面緊接 `\x00`、`\x01`、`"`：`url` 都在 `game_biz=hk4e_global` 結束。
  - 同一把 key 寫成 `abc%2Fdef` 和 `abc%2fdef` 和 `abc/def`：三筆的 `authkey` 都等於 `abc/def`。含 `+` 的原始值保留成 `+`。
  - `toApiUrl(祈願頁)`、`toApiUrl(頌願頁)`、`toApiUrl(getBeyondGachaLog 網址)` 都得到 `https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?<原 query 字串原樣>`；有 `#fragment` 時去掉。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/services/gacha_url_extract_test.dart`，期望 FAIL（找不到函式）。
- [ ] **Step 3: 實作**
  - 候選 regex：`https://[A-Za-z0-9.-]+\.hoyoverse\.com/[!#-&(-;=?-~]+`（可列印 ASCII，排除空白、`"`、`'`、`<`、`>`）。逐筆用 `Uri.tryParse`，檢查 `auth_appid`（可以用 `queryParameters`）；authkey 用 `RegExp(r'[?&]authkey=([^&#]*)')` 取原始值後 `Uri.decodeComponent`（解碼失敗就略過這筆）。
  - `toApiUrl`：`Uri.parse(url).replace(host: ..., path: ...).removeFragment()`，不傳 `query`／`queryParameters`，保留原始 query 字串。
- [ ] **Step 4: 跑測試確認通過**：同 Step 2，期望 PASS。
- [ ] **Step 5: Commit**：`feat(capture): extract wish urls from text`

---

### Task 2: 設定新增 `gameDir`

**Files:**
- Modify: `lib/services/settings_storage.dart`（`AppSettings.gameDir`、`copyWith`、`_kGameDir = 'pref.gameDir'`、`load`／`save`）
- Modify: `lib/state/settings.dart`（`setGameDir`）
- Test: `test/services/settings_storage_test.dart`、`test/state/settings_test.dart`（追加）

**Interfaces:**
- Produces：`AppSettings.gameDir`（`String?`）、`copyWith({..., String? gameDir, bool clearGameDir = false})`、`Future<void> SettingsNotifier.setGameDir(String? dir)`（null 代表清除）。

- [ ] **Step 1: 寫失敗測試**：`setGameDir(r'D:\Program Files\Genshin Impact\games\Genshin Impact game')` 後 `SettingsStorage.load()` 讀回同值；`setGameDir(null)` 後讀回 null，prefs 裡沒有 `pref.gameDir`。
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**：照 `skippedReleaseTag` 的寫法（null 就 `remove`）。`setGameDir` 記 `Logger('app.settings').info('gameDir set source=manual path=${sanitizeFsPath(dir)}')`，null 時記 `gameDir cleared`。
- [ ] **Step 4: 跑測試確認通過**
- [ ] **Step 5: Commit**：`feat(settings): persist game directory preference`

---

### Task 3: `GameDirLocator`

**Files:**
- Modify: `pubspec.yaml`（`win32_registry: ^2.1.0` 加到 dependencies）
- Create: `lib/services/game_dir_locator.dart`
- Create: `test/helpers/no_game_dir.dart`
- Test: `test/services/game_dir_locator_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum GameDirSource { setting, outputLog, registry, common }
  class GameDirLocation { const GameDirLocation(this.path, this.source); final String path; final GameDirSource source; }
  typedef RegistryInstallPathReader = Future<List<String>> Function(); // 所有 hk4e_global 子鍵的 InstallPath／InstallLocation
  typedef OutputLogReader = Future<String?> Function();                 // output_log.txt 內容；不存在回 null
  class GameDirLocator {
    GameDirLocator({RegistryInstallPathReader? readInstallPaths, OutputLogReader? readOutputLog, List<String>? commonDirs});
    Future<GameDirLocation?> locate({String? settingDir});
    Future<String?> normalize(String picked);
    static String? gameDirFromOutputLog(String content);
    static String webCachesPath(String gameDir); // <gameDir>\GenshinImpact_Data\webCaches
  }
  final gameDirLocatorProvider = Provider<GameDirLocator>((ref) => GameDirLocator());
  ```
  `test/helpers/no_game_dir.dart`：`NoGameDirLocator`（`locate` 一律回 null）與 `final noGameDirOverride = gameDirLocatorProvider.overrideWithValue(NoGameDirLocator());`，照鳴潮版同名檔。

- [ ] **Step 1: 寫失敗測試**（temp dir 建假結構，`GenshinImpact_Data` 為空資料夾即可）
  - `gameDirFromOutputLog`：內容含 `[2026-11-17 15:35:55.781] DeserializeBinary (D:/Program Files/Genshin Impact/games/Genshin Impact game/GenshinImpact_Data/Persistent\AssetBundles/x)` 時回傳 `D:\Program Files\Genshin Impact\games\Genshin Impact game`；多筆時取第一筆；沒有符合時回 null。
  - `normalize`：遊戲資料夾 → 原值；安裝根目錄（底下有 `games\Genshin Impact game\GenshinImpact_Data`）→ 遊戲資料夾；`<root>\Genshin Impact game` 形式也可；選到 `GenshinImpact_Data` 本身 → 上一層；空資料夾 → null。
  - `locate`：設定有效 → `setting`；設定無效時依序 `outputLog`（reader 回傳的內容指向有效資料夾）→ `registry`（reader 回 `[root]`，經 normalize）→ `common`；全無效回 null。任一 reader 丟例外時不丟，往下一個來源找。
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
  - `gameDirFromOutputLog` regex 照 paimon.moe 腳本：`.:/.+?GenshinImpact_Data`（取到 `GenshinImpact_Data` 為止，去掉它與結尾斜線），`/` 換成 `\`。
  - 預設 output log reader：`%USERPROFILE%\AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt`（用 `Platform.environment['USERPROFILE']`），`File.readAsString` 失敗就回 null（遊戲執行中也能用一般開檔讀，已在本機確認；若失敗只記 warning）。
  - 預設 registry reader：HKLM、HKCU、HKLM `WOW6432Node` 的 `SOFTWARE\...\CurrentVersion\Uninstall`，列舉子鍵名稱含 `hk4e_global` 者，讀 `InstallPath`，沒有就讀 `InstallLocation`；每個 key 的失敗只略過。結構照鳴潮版 `_readRegistryInstallPaths`，多了列舉子鍵。
  - registry 路徑依序試：本身、`<p>\games\Genshin Impact game`、`<p>\Genshin Impact game`（都經 `normalize` 處理即可）。
  - 預設 `commonDirs`：`C:\Program Files\Genshin Impact\games\Genshin Impact game`、`C:\Program Files\HoYoPlay\games\Genshin Impact game`；其他（Epic 等）只在查證得到時才加。
  - 結果記 `info` `game dir resolved source=<s> path=<sanitizeFsPath>` 或 `warning` `game dir not found`。
- [ ] **Step 4: 跑測試確認通過**
- [ ] **Step 5: Commit**：`feat(capture): locate the Genshin game directory`

---

### Task 4: `data_2` 讀取與 `WebCacheUrlWatch`

**Files:**
- Modify: `pubspec.yaml`（`win32: ^5.15.0` 加到 dependencies）
- Create: `lib/services/web_cache_reader.dart`
- Create: `lib/state/gacha_url_watch.dart`
- Test: `test/state/gacha_url_watch_test.dart`

**Interfaces:**
- Consumes：Task 1 `findGachaUrls`、`toApiUrl`；Task 3 `GameDirLocator.webCachesPath`；既有 `CaptureSession`（`lib/state/gacha_capture.dart`，`result` 為 `Future<String?>`）。
- Produces:
  ```dart
  // web_cache_reader.dart
  typedef CacheFileReader = Uint8List Function(String path); // 同步，供 isolate 內呼叫；檔案不存在丟 FileSystemException
  Uint8List readSharedFile(String path); // CreateFile(GENERIC_READ, SHARE_READ|WRITE|DELETE, OPEN_EXISTING) + GetFileSizeEx + ReadFile
  // gacha_url_watch.dart
  abstract class GachaUrlWatch { CaptureSession start(String gameDir); }
  class WebCacheUrlWatch implements GachaUrlWatch {
    WebCacheUrlWatch({Duration interval = const Duration(seconds: 1), CacheFileReader read = readSharedFile});
  }
  final gachaUrlWatchProvider = Provider<GachaUrlWatch>((ref) => WebCacheUrlWatch());
  ```
  `result`：命中時 complete 成 API 網址（`String`）；`cancel()` 後 complete 成 null；**永遠不 completeError**。

- [ ] **Step 1: 寫失敗測試**（真的 temp 檔，`interval: Duration(milliseconds: 20)`，`read: (p) => File(p).readAsBytesSync()`，讓 Linux CI 也能跑；等待用「等到條件成立、5 秒上限」，不要賭時間）
  - `ignores authkeys present at start`：`webCaches\2.57.0.0\...\data_2` 先寫入 K1 的頁面與 API 網址，`start` 後 200ms 內 `result` 不 complete；`cancel()` 後是 null。
  - `prefers api url for a new authkey`：start 後重寫檔案加入 K2 的頁面與 API 網址，`result` 等於 `toApiUrl(K2 的 API 網址)`。
  - `converts page-only url`：只加入 K3 的頁面網址，`result` 等於 `toApiUrl(該頁面網址)`。
  - `new version folder counts as new`：start 時只有 `2.57.0.0`（含 K1）；之後建立 `2.58.0.0` 並寫入 K1 與 K4，`result` 對應 K4；**K1 仍不採用**。
  - `missing webCaches then created`：start 時 `GenshinImpact_Data` 底下沒有 `webCaches`，之後才建立並寫入 K5，拿到 K5。
  - `numeric version ordering`：同時有 `2.9.0.0`（含新 key K6）與 `2.57.0.0`（含新 key K7），拿到 K7；名為 `tmp` 的資料夾不影響。
  - `read failure keeps watching`：reader 前兩次丟 `FileSystemException`，第三次回傳含新 key 的內容，最後拿到網址。
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
  - 每輪掃描整段用 `Isolate.run(() => _scan(gameDir, read, allVersions))`，`_scan` 是 top-level 函式、只抓參數；回傳 `(String? versionDir, List<GachaUrlMatch> matches, String? error)` 這類可傳送的值。背景不寫 log，錯誤字串交回主 isolate 記。
  - `start`：掃描**所有**版本資料夾，收集 authkey 當 baseline（`Set<String>`）。
  - 每輪：只掃版本號最大的資料夾。找出 authkey 不在 baseline 的 match；有的話，以 offset 最大的那把 key 為準，同 key 有 `isApi` 的優先，回傳 `toApiUrl(url)`。
  - 版本資料夾和上一輪不同時記 `info` `web cache version dir=<name>`；**不重算 baseline**。
  - 讀檔錯誤：記 `warning`，同一種錯誤連續發生只在狀態改變時記一次。
  - 開始時記 `info` `web cache watch started baseline=<n>`；命中記 `info` `web cache hit api=<bool> url=<sanitizeUrl>`。
  - `readSharedFile` 用 `package:win32` + `package:ffi`（`calloc` 配置、`finally` 釋放、`CloseHandle`）；開檔失敗丟 `FileSystemException(..., OSError('', GetLastError()))`。只依實際大小讀，不寫死 1,056,768。
- [ ] **Step 4: 跑測試確認通過**
- [ ] **Step 5: Commit**：`feat(capture): watch the game web cache for new wish urls`

---

### Task 5: Repository 比快（含現有 bug）

**Files:**
- Modify: `lib/state/update_progress.dart`（`WaitingForCapture` 加 `captureUnavailable`、`gameDirMissing`，預設 false，dartdoc 照鳴潮版改寫成原神的失敗方式）
- Modify: `lib/state/gacha_repository.dart`（`_runMitm` 比快、`cancelCapture`、新增 `restartWebCacheWatch`）
- Modify: 所有會建 `GachaRepository` 的測試 container 加 `noGameDirOverride`：`test/state/gacha_repository_test.dart`、`test/state/gacha_repository_cloud_import_test.dart`、`test/state/cloud_sync_test.dart`、`test/widgets/cards/account_management_test.dart`、`test/widgets/cloud_sync_section_test.dart`、`test/pages/settings_data_language_section_test.dart`、`test/pages/settings_image_cache_section_test.dart`、`test/pages/settings_page_import_button_test.dart`、`test/pages/settings_page_refetch_button_test.dart`、`test/pages/settings_privacy_section_test.dart`（實作時再 grep `gachaCaptureProvider` 與 `GachaRepository` 確認沒有漏）
- Test: `test/state/gacha_repository_web_cache_test.dart`（新檔；fake capture 比照 `gacha_repository_test.dart` 的 `_FakeCapture` 寫法）

**Interfaces:**
- Consumes：`gameDirLocatorProvider`、`gachaUrlWatchProvider`、`settingsProvider`（`gameDir`）。
- Produces：`Future<void> GachaRepository.restartWebCacheWatch()`：只在 `state.progress is WaitingForCapture` 時有作用；停掉目前的監看、重新 `locate` 後 `start`（baseline 從此刻重算）。`WaitingForCapture({bool isFallback = false, bool captureUnavailable = false, bool gameDirMissing = false})`。

- [ ] **Step 1: 寫失敗測試**（fake capture、fake watch 都用 `Completer` 控制；locator 用 override 回傳固定 `GameDirLocation`；fetcher 用既有的 mock client）
  - `cache wins: waits capture teardown before fetching`：watch 先 complete，fake capture 的 `cancel` 被呼叫；capture `result` complete 前沒有任何 HTTP 請求；之後才拉取，結果 `UpdateCompleted`。
  - `cache wins: capture teardown error is ignored`：capture `result` `completeError`，照樣 `UpdateCompleted`。
  - `capture wins: cache watch cancelled`。
  - `capture error: waits on cache only`：capture `result` `completeError` → progress 變成 `WaitingForCapture(captureUnavailable: true, gameDirMissing: false)`；之後 watch complete → `UpdateCompleted`。
  - `capture ended without url (not user cancel): waits on cache only`：同上，capture `result` 回 null 且沒按取消。
  - `capture error and no game dir: shows picker, cancel works`：locator 回 null，capture 丟錯 → `gameDirMissing: true`；呼叫 `cancelCapture()` 後 progress 被清掉（鎖住現有 bug：以前會卡在 `WaitingForCapture`）。
  - `user cancel stops both`、`user cancel during cache-won teardown aborts`（capture 收尾期間取消 → 不發任何拉取請求、progress 清掉）。
  - `no game dir: capture only`：locator 回 null 時不呼叫 watch 的 `start`，攔截成功照常完成。
  - `restartWebCacheWatch re-locates and restarts`：舊 session 被 `cancel`、新 session 被 `start`；在 `gameDirMissing: true` 狀態選好資料夾後，progress 改回 `gameDirMissing: false`。
  - `fallback recapture also races`：用既有的 `AuthExpiredException` 情境（第一次拉取 auth 過期），第二輪由快取勝出也能完成。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/state/gacha_repository_web_cache_test.dart`
- [ ] **Step 3: 實作**：移植鳴潮版 `0d36c79` 的 `_runMitm` 與相關私有方法（見文件開頭的參考清單），型別從 `GachaCredential` 換成 `String`（API 網址），`clientLog` 字樣換成 `webCache`，Logger 用 `gacha.webCache`。保留：`_captureCancelRequested`、單一 hit `Completer`、`_watchGeneration` 防舊定位結果生效、log 勝出後「先 `cancel()` 再等 `result`、各自 try」、收尾後若已按取消就回 null。`_captureBackstop` 照現有寫法保留，`cancelCapture` 要一併完成「只等快取」的等待（鳴潮版的 `_waitCancelled`）。記 `info` `url source=cache|capture`、`warning` `capture failed error=<runtimeType>`、`capture ended without url`。
- [ ] **Step 4: 跑測試確認通過**：`fvm flutter test test/state/ test/pages/ test/widgets/`，既有測試也要全過。
- [ ] **Step 5: Commit**：`feat(capture): race the web cache watch against capture`

---

### Task 6: 等待畫面連結、說明視窗、選資料夾

**Files:**
- Create: `lib/widgets/game_dir_picker.dart`
- Create: `lib/widgets/dialogs/game_dir_help_dialog.dart`
- Modify: `lib/widgets/update_progress_dialog.dart`（`WaitingForCapture` 分支：連結、`captureUnavailable` 警示提示、`gameDirMissing` 時改顯示選擇按鈕；progress 變 null 時只 pop 到自己）
- Modify: 9 份 ARB（見 Global Constraints）
- Test: `test/widgets/update_progress_dialog_test.dart`（新建或追加）、`test/widgets/dialogs/game_dir_help_dialog_test.dart`

**Interfaces:**
- Consumes：`gameDirLocatorProvider`、`settingsProvider`、`GachaRepository.restartWebCacheWatch()`。
- Produces（照鳴潮版 `game_dir_picker.dart`）：
  ```dart
  enum GameDirPickOutcome { saved, cancelled, invalid }
  Future<GameDirPickOutcome> pickAndSaveGameDir(WidgetRef ref, {Future<String?> Function()? pickDirectory});
  Future<GameDirPickOutcome> pickGameDirAndRewatch(WidgetRef ref, {Future<String?> Function()? pickDirectory}); // saved 時呼叫 restartWebCacheWatch
  Future<void> showGameDirHelpDialog(BuildContext context);
  ```

- [ ] **Step 1: 新增 ARB 字串**（zh 如下，其他 8 份照意思翻譯；`path` placeholder 型別 String）

  | key | zh（template） |
  |---|---|
  | `progressNotDetectedLink` | 已經開啟祈願歷史紀錄，卻一直沒有反應？ |
  | `progressCaptureUnavailableHint` | 無法啟動攔截程式（可能是憑證被拒絕或連接埠被佔用），改為只從遊戲網頁快取偵測。請開啟祈願歷史紀錄。 |
  | `progressCaptureUnavailableNoGameDirHint` | 無法啟動攔截程式（可能是憑證被拒絕或連接埠被佔用），也找不到遊戲資料夾。請按下方「選擇遊戲資料夾」手動指定。 |
  | `gameDirHelpTitle` | 偵測不到祈願歷史紀錄 |
  | `gameDirHelpNotFound` | 找不到原神的遊戲資料夾。選擇遊戲資料夾後，本工具也能改從遊戲網頁快取讀取祈願歷史紀錄。 |
  | `gameDirHelpFound` | 目前讀取的遊戲資料夾：{path}。如果不是你正在玩的那份遊戲，請重新選擇。 |
  | `gameDirHelpReopen` | 已設定遊戲資料夾。請回到遊戲，再開啟一次祈願歷史紀錄。 |
  | `gameDirInvalid` | 這個資料夾裡找不到原神，請選擇「Genshin Impact game」資料夾。 |
  | `actionChooseGameDir` | 選擇遊戲資料夾 |
  | `actionRechooseGameDir` | 重新選擇 |

  跑 `fvm flutter gen-l10n`，確認沒有錯誤。
- [ ] **Step 2: 寫失敗測試**
  - 等待狀態顯示 `progressNotDetectedLink`，點下去出現 `gameDirHelpTitle`。
  - `captureUnavailable: true` 時顯示 `progressCaptureUnavailableHint`；再加 `gameDirMissing: true` 時顯示 `...NoGameDirHint` 與 `actionChooseGameDir` 按鈕，且不顯示連結。
  - 說明視窗：locator 回 null → `gameDirHelpNotFound` + `actionChooseGameDir`；回 `GameDirLocation(p, outputLog)` → 含 `p` 的文字 + `actionRechooseGameDir`。
  - `pickAndSaveGameDir`：有效 → `saved` 且 `settings.gameDir` 是 normalize 後的值；空資料夾 → `invalid`、設定不變；null → `cancelled`。
  - 說明視窗內選好後改顯示 `gameDirHelpReopen`，並呼叫 `restartWebCacheWatch`（fake repository 計數）。
  - `help dialog closes when progress leaves waiting`：progress 改成 `FetchingBanner`，說明視窗消失、進度視窗還在。
  - `both dialogs close when progress becomes null`：兩個視窗都消失，底下的頁面還在。
- [ ] **Step 3: 實作**：照鳴潮版三個檔案。說明視窗用 `ref.listen` 監看 progress，離開 `WaitingForCapture` 且自己是目前 route 時 pop 自己；`UpdateProgressDialog` 的 listener 改成先 `popUntil` 到自己的 route 再 `pop()`。預設 `pickDirectory` 是 `file_selector` 的 `getDirectoryPath`。路徑長時要能換行或省略，不能超出邊界。
- [ ] **Step 4: 跑測試確認通過**：`fvm flutter test test/widgets/`
- [ ] **Step 5: Commit**：`feat(ui): add game folder help to the capture waiting dialog`

---

### Task 7: 設定頁「遊戲資料夾」區塊

**Files:**
- Modify: `lib/pages/settings_page.dart`（在「資料管理」`SectionCard` 之後新增一張，icon `Icons.sports_esports_outlined`，內容放私有類別 `_GameDirSection`，照鳴潮版）
- Modify: 9 份 ARB
- Test: `test/pages/settings_game_dir_section_test.dart`

**Interfaces:**
- Consumes：`pickAndSaveGameDir`（Task 6）、`gameDirLocatorProvider`、`SettingsNotifier.setGameDir`。

- [ ] **Step 1: 新增 ARB 字串**：`settingsGameDir`＝遊戲資料夾、`settingsGameDirAuto`＝自動偵測：{path}、`settingsGameDirManual`＝手動設定：{path}、`settingsGameDirNone`＝找不到遊戲資料夾、`actionClearGameDir`＝清除。
- [ ] **Step 2: 寫失敗測試**：有設定值時顯示「手動設定」與路徑、有清除按鈕，按下後 `gameDir` 變 null；沒設定、locator 回結果時顯示「自動偵測」；按選擇走 `pickAndSaveGameDir`（注入 fake `pickDirectory`），`invalid` 時顯示 `gameDirInvalid`（呈現方式照設定頁其他錯誤）。窄寬度（360）與 1.3 倍字級下沒有 overflow。
- [ ] **Step 3: 實作**
- [ ] **Step 4: 跑測試確認通過**：`fvm flutter test test/pages/settings_game_dir_section_test.dart`
- [ ] **Step 5: Commit**：`feat(settings): add game folder section`

---

### Task 8: 收尾驗證

- [ ] **Step 1**：`fvm dart format lib/ test/`
- [ ] **Step 2**：`fvm flutter analyze`，必須輸出 `No issues found!`
- [ ] **Step 3**：`fvm flutter test`，必須輸出 `All tests passed!`
- [ ] **Step 4: 手動 E2E（維護者本機，`fvm flutter run -d windows`，需要人開遊戲）**
  1. 正常更新：log 出現 `url source=...`，更新完成。
  2. 先佔住 `127.0.0.1:18080`（例如 PowerShell `$l=[System.Net.Sockets.TcpListener]::new([ipaddress]::Loopback,18080);$l.Start()`，測完 `$l.Stop()`）：等待畫面出現 `progressCaptureUnavailableHint`，開祈願歷史紀錄後只靠快取完成。
  3. 開的是頌願歷史紀錄頁：同樣完成，祈願與頌願卡池都有新資料或「已是最新」。
  4. 清掉設定的資料夾，並暫時讓自動偵測找不到（除錯時在 `gameDirLocatorProvider` 注入 `NoGameDirLocator`，**不要 commit**）＋佔住 18080：顯示選擇按鈕 → 選資料夾 → 提示再開一次 → 完成。
  5. 匯出 log，確認沒有網址原文與 authkey。
- [ ] **Step 5: Commit**（format 有改動時）：`style: format`
