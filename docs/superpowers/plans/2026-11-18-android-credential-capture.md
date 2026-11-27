# Android 取得祈願紀錄網址（子專案 2）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 版按「更新資料」後，透過 root 或自我配對的無線偵錯，在手機上啟動獨立的 logcat 監看程序，取得祈願紀錄網址；兩個平台都能手動貼上網址。

**Architecture:** 照搬鳴潮版子專案 2 的**最終程式**（讀取方式判斷、root／無線偵錯 shell、配對前景服務、設定頁區塊、等待畫面、手動輸入），只把讀 `Client.log` 的那層換成 `LogcatUrlWatch`。`GachaRepository` 在 Android 走 `_runAndroidWait`，電腦版照舊 `_runMitm`（MITM＋讀網頁快取）。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、`flutter_adb` 1.0.0、既有 `flutter_secure_storage`／`synchronized`、Kotlin（AGP 9）。

**Spec:** `docs/superpowers/specs/2026-11-18-android-credential-capture-design.md`（必讀；第 3.2 節是和鳴潮版的差異，第 3.3 節是實機事實，第八、九節是檔案對照與合併重點）

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）**master 上目前的檔案**，不是它舊計畫裡的程式片段（之後修過很多次，見移植筆記 #19、#20、#52、#53）。看檔案用 `git -C ../wuthering-waves-convene-gacha-analyzer show master:<路徑>`。照搬時：
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`、`tw.reh.wuwa.gacha` → `tw.reh.genshin.gacha`、`wuwa` 字樣的檔名與識別名稱 → `genshin`；
- 換術語：鳴潮 → 原神、喚取記錄 → 祈願紀錄、`Client.log`／遊戲記錄檔 → 系統記錄（logcat），依 `docs/術語表.md`；
- 其餘（結構、流程、錯誤處理、逾時、log 格式、測試案例）逐字一致。不確定是否要偏離時，回報 NEEDS_CONTEXT，不要自行改寫。

移植筆記在 `C:\Users\p2902\.t3\userdata\attachments\e5876792-ebce-4c0e-b110-5aaa3874cab1-66f23b36-5edf-4703-888c-59303b7ad260-md.md`（#2、#19～#21、#52、#53 與這個子專案有關）。

## Global Constraints

- 所有 Flutter／Dart 指令走 `fvm`；每次 commit 前依序 `fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。不要 `git push`。
- Commit message 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。分支 `feat/android`（已 checkout，不開新分支、不用 worktree）。
- 新增 Dart 依賴只有 `flutter_adb: 1.0.0`。不引入 `device_info_plus`、`permission_handler`、`connectivity_plus`、`flutter_local_notifications`。
- 所有宣告（含 private）要有一行 `///` dartdoc；`//` 註解只寫 WHY；中文註解與 UI 文字用全形標點，省略號一律半形 `...`。
- Log 一律英文；Logger：`capture.android`、`capture.adb`、`capture.pairing`、`gacha.logcat`。網址經 `sanitizeUrl`；authkey、配對碼、金鑰、暫存檔內容絕不入 log。
- UI 一律稱「裝置」不說「手機」（引用系統設定原名例外）。新 dialog 一律 `AppDialog`；手機橫向時等待畫面 `scrollable: true`。
- ARB：新字串先寫 `app_zh.arb`，再翻 `app_en`、`app_zh_Hans`、`app_ja`、`app_es`、`app_fr`、`app_pt_BR`、`app_th`、`app_vi`（共 9 份已有翻譯的 ARB）；22 份空殼 ARB 不動。遊戲內名稱依 `docs/術語表.md`。改完跑 `fvm flutter gen-l10n`。
- Android 的 `values*/strings.xml` 新字串同樣做 9 種語言（`values`、`values-zh-rTW`、`values-zh-rCN`、`values-ja`、`values-es`、`values-fr`、`values-pt-rBR`、`values-th`、`values-vi`）。
- 監看比對規則（常數，逐字）：`OnGetWebViewPageFinis[h],message:https://[^ ]*auth_appid=webview_gach[a]`。App 送出的任何 shell 指令都不能含連續的 `OnGetWebViewPageFinish,` 或 `webview_gacha` 字樣。
- 暫存檔路徑（常數）：`/data/local/tmp/tw.reh.genshin.gacha.url`。起點格式：`^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}$`，由手機上 `date "+%m-%d %H:%M:%S.000"` 取得。
- 原神套件：`com.miHoYo.GenshinImpact`，或以它加 `.` 開頭；套件名稱只接受 `^com\.miHoYo\.GenshinImpact(\.[A-Za-z0-9_]+)*$`。
- 配對名稱（`AdbKeyStore.keyName`）：`genshin-wish-analyzer`。
- 電腦版既有攔截、讀網頁快取、3 秒寬限行為不能變；既有測試全部要繼續通過。Android 完全不呼叫 Rust。
- 不移植：`ClientLogSource`、`client_log_credential.dart`、`client_log_watch.dart`、`LogAccessMethod.legacyDirect`、儲存權限、選遊戲版本（`gamePackage` 設定、`selectGame`、`switchGameVersion`、選版本畫面）。
- Ascent 是 AGPL，不可參考其程式碼。

## Review Focus

1. **玩家先開公告或活動頁、再開歷史紀錄**：只能抓到歷史紀錄頁，不能停在不相干的網頁 → Task 5 測試（啟動指令含收窄規則）＋ Task 9 實機。
2. **玩家在遊戲裡時 adbd 重啟（Wi‑Fi 斷線、USB 偵錯沒開）**：回到 App 後仍拿得到網址或繼續等待，不卡死、不報錯 → Task 5 測試（監看程序不在時用同一個起點重啟）＋ Task 9 實機。
3. **App 在等待中被系統殺掉**：下次更新開始前清掉殘留的監看程序與暫存檔 → Task 5 測試（啟動前先跑清理指令）。
4. **讀取方式判斷還在連線時按取消**：取消後不能再啟動監看，本次打開的無線偵錯要關掉 → Task 6 測試（照搬鳴潮版）。
5. **抓資料進行中又送出手動輸入**：忽略，不重入更新；電腦版等待攔截中送出：走快取勝出的寬限收尾 → Task 1 測試。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `lib/services/gacha_url_extract.dart`（改） | 新增 `latestApiUrlIn` | 1 |
| `lib/state/platform.dart`（新） | `isAndroidProvider` | 1 |
| `lib/widgets/dialogs/manual_url_dialog.dart`（新） | 手動輸入對話框（兩平台） | 1 |
| `lib/state/gacha_repository.dart`（改） | `submitManualUrl`（1）、Android 等待分支（6） | 1、6 |
| `lib/widgets/update_progress_dialog.dart`（改） | 手動輸入連結（1）、Android 等待畫面（6） | 1、6 |
| `lib/services/android/genshin_game_package.dart`（新） | 原神套件名稱開頭、已知套件、排序、驗證 | 2 |
| `lib/services/android/log_access_platform.dart`（新） | Kotlin MethodChannel 的 Dart 包裝 | 2 |
| `android/.../LogAccessChannel.kt`（新）、`MainActivity.kt`、`AndroidManifest.xml`（改） | 系統層 channel、權限、queries | 2 |
| `lib/services/android/adb_shell_client.dart`、`flutter_adb_session.dart`、`root_shell.dart`、`shell_exec.dart`（新） | shell 連線、金鑰、`su`、`ShellExec` typedef | 3 |
| `lib/services/android/log_access_method.dart`、`log_access_resolver.dart`（新） | 讀取方式與判斷 | 4 |
| `lib/services/settings_storage.dart`、`lib/state/settings.dart`（改） | `logAccessMethod` | 4 |
| `lib/state/logcat_url_watch.dart`（新） | logcat 監看程序的啟動、輪詢、重啟、清理 | 5 |
| `lib/state/app_foreground.dart`（新）、`lib/state/update_progress.dart`（改）、`lib/widgets/android_log_wait_body.dart`（新） | 前景偵測、等待狀態欄位、Android 等待畫面 | 6 |
| `android/.../AdbPairingService.kt`（新）、`lib/state/adb_pairing.dart`、`lib/pages/log_access_setup_page.dart`（新）、`values*/strings.xml`（改） | 配對 | 7 |
| `lib/widgets/cards/log_access_section.dart`（新）、`lib/pages/settings_page.dart`（改） | 設定頁區塊、解除配對 | 8 |

---

### Task 1: 手動輸入祈願紀錄網址（兩平台）

**Files:**
- Modify: `lib/services/gacha_url_extract.dart`、`lib/state/gacha_repository.dart`、`lib/widgets/update_progress_dialog.dart`、9 份 ARB
- Create: `lib/state/platform.dart`、`lib/widgets/dialogs/manual_url_dialog.dart`
- Test: `test/services/gacha_url_extract_test.dart`、`test/state/gacha_repository_manual_test.dart`（新；沿用 `gacha_repository_web_cache_test.dart` 的 fake 與 helper 寫法）、`test/widgets/manual_url_dialog_test.dart`（新）、`test/widgets/update_progress_dialog_test.dart`

**Interfaces:**
- Produces:
  - `String? latestApiUrlIn(String text)`（`gacha_url_extract.dart`）：`findGachaUrls(text)` 依 `offset` 由大到小，第一個能 `toApiUrl` 的回傳；沒有則 null。頁面網址與 API 網址都接受。
  - `final isAndroidProvider = Provider<bool>((_) => Platform.isAndroid);`（`lib/state/platform.dart`，照搬鳴潮版）
  - `Future<void> showManualUrlDialog(BuildContext context)`（照搬鳴潮版 `showManualCredentialDialog`，去掉 `pickClientLog` 與 `_pickLog`）
  - `GachaRepository.submitManualUrl(String apiUrl) → Future<void>`：
    - 正在等待（`_cacheHit` 未完成）：完成 `_cacheHit`。電腦版會走既有的快取勝出流程（`_stopCaptureAfterCacheWin` 3 秒寬限），log `url source=manual`。
    - 正在抓資料（`_isUpdating` 且沒有可完成的等待）：忽略並記 info。
    - 其他：`_runUpdate(forceRecapture: false, manualUrl: apiUrl)`，先用手動網址，跳過帳號存的網址與等待流程。
  - 手動網址跟其他來源一樣在成功後存成帳號的快取網址（沿用既有存檔流程）。
- 說明文字（`manualUrlHint`，逐字）：「如果已經用其他方式（例如電腦上的工具）取得祈願紀錄網址，可以貼在這裡；整段文字也可以，App 會自動找出網址。」找不到網址時（`manualUrlNotFound`）：「找不到祈願紀錄網址，請確認貼上的內容。」輸入框：`keyboardType: TextInputType.url`、`autocorrect: false`、`enableSuggestions: false`、多行。
- 等待畫面（電腦版）：`WaitingForCapture` 新增「手動輸入祈願紀錄網址」連結（`manualUrlEntry`），位置照鳴潮版。

- [ ] **Step 1: 寫失敗測試**

```dart
// gacha_url_extract_test.dart
test('latestApiUrlIn picks the newest valid url from surrounding text', ...); // 兩個網址＋前後全形字「」。→ 取後者、轉成 API 網址
test('latestApiUrlIn accepts an api url as is', ...);
test('latestApiUrlIn returns null without a webview_gacha url', ...);
// repository
test('manual url completes a pending capture wait via the cache-win path', ...); // Review Focus 5（電腦版）
test('manual url while fetching is ignored', ...);                              // Review Focus 5
test('manual url when idle starts an update with that url', ...);               // 不讀帳號存的網址、不開攔截
// widget
testWidgets('manual dialog shows hint and an error for text without a url', ...);
testWidgets('waiting dialog shows the manual input link on desktop', ...);
```

- [ ] **Step 2: 跑測試確認失敗**　Run: `fvm flutter test test/services/gacha_url_extract_test.dart test/widgets/manual_url_dialog_test.dart`　Expected: 編譯失敗或 FAIL（函式不存在）

- [ ] **Step 3: 實作**（介面如上；對話框照搬鳴潮版的版面與 RWD）

- [ ] **Step 4: 全部測試通過**　Run: `fvm flutter gen-l10n; fvm flutter test`　Expected: `All tests passed!`

- [ ] **Step 5: Commit**　`feat(capture): add manual wish history url input on all platforms`

---

### Task 2: Kotlin 系統層 channel、權限、遊戲套件偵測

**Files:**
- Create: `android/app/src/main/kotlin/tw/reh/genshin/gacha/LogAccessChannel.kt`、`lib/services/android/log_access_platform.dart`、`lib/services/android/genshin_game_package.dart`
- Modify: `android/app/src/main/kotlin/tw/reh/genshin/gacha/MainActivity.kt`、`android/app/src/main/AndroidManifest.xml`
- Test: `test/services/android/log_access_platform_test.dart`、`test/services/android/genshin_game_package_test.dart`（新）

**Interfaces:**
- Produces（照搬鳴潮版 `LogAccessPlatform`，channel `tw.reh.genshin.gacha/log_access`，去掉 `hasStoragePermission`／`requestStoragePermission`；配對服務相關的四個方法 `startPairingService`、`stopPairingService`、`isPairingServiceRunning`、`setPairingCodeHandler` 這裡**不加**，Dart 與 Kotlin 兩端都留到 Task 7）：`sdkInt`、`isWifiConnected`、`isDevelopmentSettingsEnabled`、`isAdbWifiEnabled`、`setAdbWifiEnabled`、`hasWriteSecureSettings`、`discoverAdbConnectPorts`、`openWirelessDebugging`、`openDeveloperOptions`、`openDeviceInfoSettings`、`openAppNotificationSettings`、`areNotificationsEnabled`、`requestNotificationPermission`、`installedGamePackages`（`Future<List<String>?>`，null 表示查詢失敗）、`launchGame(String pkg)`、`logAccessPlatformProvider`。
- `genshin_game_package.dart`：`genshinPackagePrefix = 'com.miHoYo.GenshinImpact'`、`genshinGlobalPackage = 'com.miHoYo.GenshinImpact'`、`knownGenshinPackages = [genshinGlobalPackage]`、`bool isGenshinPackage(String)`（Global Constraints 的 regex）、`List<String> sortGenshinPackages(Iterable<String>)`（已知的在前，其餘照字母）。沒有 log 路徑函式。
- Manifest：`WRITE_SECURE_SETTINGS`（`tools:ignore="ProtectedPermissions"`）、`ACCESS_NETWORK_STATE`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`；`<queries>` 宣告 `com.miHoYo.GenshinImpact` 與 MAIN／LAUNCHER intent。不加 `READ_EXTERNAL_STORAGE`、`requestLegacyExternalStorage`。

- [ ] **Step 1: 寫失敗測試**：照搬鳴潮版 `log_access_platform_test.dart`（去掉儲存權限案例）；`genshin_game_package_test.dart`：接受 `com.miHoYo.GenshinImpact`、`com.miHoYo.GenshinImpact.samsung`，拒絕 `com.miHoYo.GenshinImpactX`、`com.miHoYo.Yuanshen`、含 `'`、空白、`;` 的字串；排序已知在前。
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**（Kotlin `installedGames` 用原神開頭，`launchGame` 只開原神開頭的套件）
- [ ] **Step 4: 全部測試通過，並 `fvm flutter build apk --debug` 成功**
- [ ] **Step 5: Commit**　`feat(android): add log access platform channel`

---

### Task 3: ADB shell 用戶端、金鑰保存、root shell

**Files:**
- Modify: `pubspec.yaml`（`flutter_adb: 1.0.0`）、`pubspec.lock`
- Create: `lib/services/android/shell_exec.dart`、`adb_shell_client.dart`、`flutter_adb_session.dart`、`root_shell.dart`
- Test: `test/services/android/adb_shell_client_test.dart`、`flutter_adb_session_test.dart`、`root_shell_test.dart`、`adb_key_store_test.dart`

**Interfaces:**
- Produces：
  - `typedef ShellExec = Future<Uint8List> Function(String command);`（`shell_exec.dart`，鳴潮版放在 `client_log_source.dart`，原神版獨立成檔）
  - 其餘照搬鳴潮版：`AdbSession`、`AdbConnector`、`AdbShellException`、`AdbShellClient`（`connectAny`、`exec`、`healthChanges`、`isConnected`、`close`）、`FlutterAdbSession`、`connectFlutterAdb`、`pairWithCode`、`guardAdbZone`、`AdbKeyStore`（key `adb.keypair.v1`、`keyName = 'genshin-wish-analyzer'`）、`adbKeyStoreProvider`、`AdbPairingOps`、`adbPairingOpsProvider`、`RootShell`（`isSuPresent`、`verify`、`exec`、`close`）。
- `pubspec.lock` 只能新增 `flutter_adb` 與它的間接依賴，既有套件版本不變。

- [ ] **Step 1: 照搬四個測試檔**（包含鳴潮版 Review Focus：secure storage 讀金鑰丟例外 → 視為未配對；連線不產生金鑰）
- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 照搬實作**
- [ ] **Step 4: 全部測試通過**
- [ ] **Step 5: Commit**　`feat(android): add adb shell client, key store and root shell`

---

### Task 4: 讀取方式判斷（`LogAccessResolver`）與偏好保存

**Files:**
- Create: `lib/services/android/log_access_method.dart`、`lib/services/android/log_access_resolver.dart`
- Modify: `lib/services/settings_storage.dart`、`lib/state/settings.dart`
- Test: `test/services/android/log_access_resolver_test.dart`、既有 settings 測試檔

**Interfaces:**
- Consumes: Task 2 `LogAccessPlatform`、`genshin_game_package.dart`；Task 3 `ShellExec`、`AdbShellClient`、`RootShell`、`AdbKeyStore`。
- Produces（照搬鳴潮版，差異列出）：
  - `enum LogAccessMethod { root, wirelessDebugging }`（去掉 `legacyDirect`），`fromName`。
  - `LogAccessUnavailable { notPaired, noWifi, adbConnectFailed, wirelessDebuggingOff, networkNotAllowed, unsupported, gameNotInstalled }`（去掉 `storagePermissionDenied`、`chooseGame`）。
  - `LogAccessReady { ShellExec exec, LogAccessMethod method, String? game, Future<bool> Function() release, Stream<bool> healthChanges }`：`exec` 取代鳴潮版的 `source`；`game` 是「開啟原神」要開的套件（裝了多個時取 `sortGenshinPackages` 第一個；查詢失敗時為 null）。沒有 `games`。
  - `LogAccessBlocked { reason, rootDenied, enabledWireless }`。
  - `LogAccessResolver.resolve({LogAccessMethod? preferred, bool forceDisableAfterUse, bool requestPermissions, Future<void>? abort})`：先偵測原神（沒裝 → `Blocked(gameNotInstalled)`，不試 root、不開無線偵錯；查詢失敗照常判斷），再依序 preferred → root → 無線偵錯（Android 11 以上）；Android 10 以下且沒有 root → `Blocked(unsupported)`。
  - `AppSettings.logAccessMethod`（key `pref.logAccessMethod`，只存本機）、`SettingsNotifier.setLogAccessMethod(LogAccessMethod?)`。沒有 `gamePackage`。
- 去掉：`_tryLegacy`、`_shellSource`、`_logIfMissing`、`_pickGame` 的選版本邏輯。

- [ ] **Step 1: 照搬鳴潮版 resolver 測試**，去掉 legacy、選版本、log 路徑案例，新增：Android 10（sdk 29）無 root → `unsupported`；沒裝原神 → `gameNotInstalled` 且沒有呼叫 root／`setAdbWifiEnabled`；查詢失敗（null）照常判斷；`Ready.exec` 是 root／adb 的 exec。
- [ ] **Step 2–4: 失敗 → 實作 → 全部通過**
- [ ] **Step 5: Commit**　`feat(android): resolve how to read the system log`

---

### Task 5: `LogcatUrlWatch`（新寫，取代鳴潮版的 `PollingClientLogWatch`）

**Files:**
- Create: `lib/state/logcat_url_watch.dart`
- Test: `test/state/logcat_url_watch_test.dart`

**Interfaces:**
- Consumes: Task 3 `ShellExec`；Task 1 `latestApiUrlIn`；既有 `CaptureSession`（`lib/state/gacha_capture.dart`）、`sanitizeUrl`。
- Produces：
  - `abstract class LogcatUrlWatch { Future<CaptureSession> start(ShellExec exec); }`：`result` 是 API 網址，取消為 null，永不 completeError；`cancel()` 等進行中的輪詢結束、結束監看程序、刪暫存檔後才完成。
  - `class PollingLogcatUrlWatch implements LogcatUrlWatch`，`PollingLogcatUrlWatch({Duration interval = const Duration(seconds: 1)})`。
  - `final logcatUrlWatchProvider = Provider<LogcatUrlWatch>((ref) => PollingLogcatUrlWatch());`
  - 指令產生函式（top-level，供測試直接驗證字串）：`String logcatStartCommand(String since)`（起點不符合格式時丟 `ArgumentError`）、`String logcatPollCommand(int pid)`、`const String logcatCleanupCommand`、`const String deviceTimeCommand = 'date "+%m-%d %H:%M:%S.000"'`。
- 行為（spec 4.2、4.3）：
  1. 起點：`deviceTimeCommand`，輸出 trim 後要符合起點格式。失敗時不放棄，下一輪輪詢再試；還沒拿到起點前不啟動監看程序。
  2. 每次啟動前先跑 `logcatCleanupCommand`（結束命令列含 `webview_gach[a]` 的 `logcat` 程序，再 `rm -f` 暫存檔；不能用 `pkill -f`）。確切寫法在實機上確認（`pidof logcat`＋`/proc/<pid>/cmdline`）。
  3. `logcatStartCommand(since)`：`umask 077; setsid logcat -T '<since>' -m 1 -e '<規則>' > '<暫存檔>' 2>/dev/null < /dev/null & echo $!`，輸出是 PID。
  4. 每 `interval` 輪詢一次（同一時間只有一個輪詢）：`logcatPollCommand(pid)` 讀暫存檔，並在監看程序還在時多印一行固定標記 `__GW_LOGCAT_ALIVE__`。
     - 有網址：`latestApiUrlIn` 轉成 API 網址，完成 `result`，跑清理。
     - 有內容但沒有合法網址：跑清理，**用手機目前時間**為新起點重啟，記 warning `logcat hit without a valid url, restarting from now`。
     - 沒內容且監看程序不在：用**同一個起點**重啟，記 info `logcat monitor gone, restarting restarts=<n>`。
     - exec 丟例外：記 warning，這輪結束，下一輪再試（重連由 `AdbShellClient` 負責）。
  5. log：`logcat watch started since=<起點> pid=<pid>`、命中 `logcat hit url=<sanitizeUrl>`。不記暫存檔內容。

- [ ] **Step 1: 寫失敗測試**（假的 `ShellExec`：依指令字首回傳預設輸出並記錄收到的指令）

```dart
test('start runs cleanup, then launches the monitor from the device time', ...);
test('start command uses the narrowed rule and never contains the raw match text', ...); // Review Focus 1：不含 'OnGetWebViewPageFinish,' 與 'webview_gacha'
test('start command rejects a malformed since', ...);
test('hit converts the page url to the api url and cleans up', ...);
test('content without a valid url restarts from the current device time', ...);
test('dead monitor without content restarts from the same since', ...);           // Review Focus 2
test('cleanup runs before every launch', ...);                                     // Review Focus 3
test('exec failures keep waiting and recover', ...);
test('device time failure retries on the next poll', ...);
test('cancel waits for the in-flight poll, then cleans up and resolves null', ...);
test('commands sent never contain OnGetWebViewPageFinish, or webview_gacha', ...); // 掃過所有記錄的指令
```

- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 實機確認清理指令**（USB adb，`MSYS_NO_PATHCONV=1`）：手動用 `logcatStartCommand` 的輸出啟動兩個監看程序，跑 `logcatCleanupCommand`，確認兩個都結束、暫存檔已刪、其他 `logcat` 程序不受影響。把確認過的指令寫進程式。
- [ ] **Step 5: 全部測試通過，Commit**　`feat(android): watch logcat for the wish history url`

---

### Task 6: `GachaRepository` 的 Android 等待分支與等待畫面

**Files:**
- Create: `lib/state/app_foreground.dart`、`lib/widgets/android_log_wait_body.dart`
- Modify: `lib/state/gacha_repository.dart`、`lib/state/update_progress.dart`、`lib/widgets/update_progress_dialog.dart`、9 份 ARB
- Test: `test/state/gacha_repository_android_test.dart`（新）、`test/widgets/android_log_wait_test.dart`（新）、`test/widgets/update_progress_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 `isAndroidProvider`、`submitManualUrl`、`showManualUrlDialog`；Task 4 `LogAccessResolver`／`LogAccessOutcome`／`setLogAccessMethod`；Task 5 `logcatUrlWatchProvider`；Task 2 `launchGame`、`openWirelessDebugging`。
- Produces（照搬鳴潮版，合併規則見 spec 第九節）：
  - `_acquireUrl({required bool isFallback})`：`isAndroidProvider` → `_runAndroidWait`，否則 `_runMitm`；取代 `_runUpdate` 兩處 `_runMitm` 呼叫。
  - `_runAndroidWait`：鳴潮版的流程，`_logHit` 用電腦版既有的 `_cacheHit`、`_waitCancelled` 用 `_captureBackstop`；`ready.exec` 交給 `logcatUrlWatchProvider.start`；命中後 App 不在前景時 `credentialReady`，等 `untilForeground()` 才回傳；`finally` 依序：停 health 訂閱 → `await watch.cancel()` → `ready.release()` → `invalidate(wirelessPairingStatusProvider)`（Task 7 才有這個 provider，這裡先不 invalidate，Task 7 補上）。
  - `cancelCapture()`：Android 時只完成 `_captureBackstop`、停監看，不呼叫 `_activeCancel`／Rust；`_cancelTriggered` 照舊設定。
  - `update({bool afterPairing = false})`、`retryLogAccess()`、`_updateDone`。
  - `WaitingForCapture` 新增 `checkingLogAccess`、`logAccessUnavailable`、`rootDenied`、`logConnectionLost`、`credentialReady`、`gameNotInstalled`（由 `logAccessUnavailable == gameNotInstalled` 表示，不另開欄位亦可，照鳴潮版）；`UpdateCompleted.wirelessDebuggingLeftOn`。
  - `AndroidLogWaitBody`：照搬，去掉選版本、`_regrantStorage`；「開啟原神」開 `ready.game`（放在 `WaitingForCapture` 的 `gamePackage` 欄位）；沒裝原神時顯示「這台裝置上找不到原神」與並排的「重新偵測」「前往 Google Play」（`https://play.google.com/store/apps/details?id=com.miHoYo.GenshinImpact`）＋手動輸入。
  - 等待畫面文字：標題 `progressWaitingLog`「等待祈願紀錄...」、提示「請開啟原神 → 祈願 → 歷史紀錄」；其他原因文字照搬鳴潮版並換術語；`unsupported` 文字：「這台裝置無法自動讀取祈願紀錄網址（需要 Android 11 以上，或已 root），請改用手動輸入。」
- 「等 App 回到前景」放在 `_fetchAllBanners` 之前（`probeUid` 也是網路請求）。

- [ ] **Step 1: 照搬鳴潮版 `gacha_repository_android_test.dart` 與 `android_log_wait_test.dart`**（去掉選版本、儲存權限、Client.log 案例），補上：Android 不呼叫 `gachaCaptureProvider`／Rust；Android 等待時送出手動網址完成等待；取消時 `watch.cancel()` 在 `release()` 之前完成（Review Focus 4 照搬）；電腦版 `isAndroidProvider` false 時仍走 MITM＋快取。
- [ ] **Step 2–4: 失敗 → 實作 → 全部通過**（`fvm flutter gen-l10n; fvm flutter test`）
- [ ] **Step 5: Commit**　`feat(android): wait for the wish history url through logcat`

---

### Task 7: 配對前景服務、說明頁與配對引導

**Files:**
- Create: `android/app/src/main/kotlin/tw/reh/genshin/gacha/AdbPairingService.kt`、`lib/state/adb_pairing.dart`、`lib/pages/log_access_setup_page.dart`
- Modify: `LogAccessChannel.kt`、`AndroidManifest.xml`（`<service android:name=".AdbPairingService" android:exported="false" android:foregroundServiceType="shortService"/>`）、9 份 `values*/strings.xml`（`pairing_*`）、`lib/services/android/log_access_platform.dart`（`startPairingService`、`stopPairingService`、`isPairingServiceRunning`、`setPairingCodeHandler`）、`lib/state/gacha_repository.dart`（`finally` 補 `invalidate(wirelessPairingStatusProvider)`）、9 份 ARB
- Test: `test/state/adb_pairing_test.dart`、`test/pages/log_access_setup_page_test.dart`

**Interfaces:**
- Produces（照搬鳴潮版）：`PairingPhase`、`AdbPairingState`、`AdbPairingController`、`adbPairingProvider`、`unpairWirelessDebugging`、`unpairWirelessDebuggingProvider`、`wirelessPairingStatusProvider`、`openLogAccessSetup(context, {retryGrant})`、`LogAccessSetupPage`。
- 說明頁文字依 spec 第五節換成原神：只讀原神的祈願紀錄網址；Android 不允許 App 讀其他 App 的系統記錄。
- 版面：鳴潮版 `log_access_setup_page.dart` 用到子專案 3 的 `pagePaddingOf`（`theme/layout.dart`），原神版還沒有，改用既有的間距 token（`AppSpacing`），子專案 3 再換。

- [ ] **Step 1: 照搬兩個測試檔**
- [ ] **Step 2–4: 失敗 → 實作 → 全部通過，`fvm flutter build apk --debug` 成功**
- [ ] **Step 5: Commit**　`feat(android): pair wireless debugging through a notification`

---

### Task 8: 設定頁「讀取遊戲記錄」區塊與解除配對

**Files:**
- Create: `lib/widgets/cards/log_access_section.dart`
- Modify: `lib/pages/settings_page.dart`、9 份 ARB
- Test: `test/pages/settings_page_log_access_test.dart`（新）

**Interfaces:**
- Consumes: Task 4 `logAccessMethod`；Task 7 `wirelessPairingStatusProvider`、`unpairWirelessDebuggingProvider`、`openLogAccessSetup`。
- Produces: `LogAccessSection`（照搬，去掉 legacy 標籤）；`settings_page.dart` 在 `isAndroidProvider` 為 true 時顯示「讀取遊戲記錄」區塊、不顯示「遊戲資料夾」區塊（子專案 0 的 `_GameDirSection`）。

- [ ] **Step 1: 照搬鳴潮版 `settings_page_log_access_test.dart`**，補：Android 不顯示遊戲資料夾區塊、電腦版顯示遊戲資料夾區塊且不顯示讀取區塊。
- [ ] **Step 2–4: 失敗 → 實作 → 全部通過**
- [ ] **Step 5: Commit**　`feat(android): add log access settings and unpairing`

---

### Task 9: 實機、模擬器驗證與文件

這個 Task 由 controller 帶使用者一起做（需要玩家操作遊戲）。任何一項失敗，回到負責的 Task 修正。

**實機（ASUS Android 16，USB 與無線都可能用到；`adb` 指令前 `export MSYS_NO_PATHCONV=1`）**

- [ ] 全新安裝 → 按更新 → 說明頁 → 配對引導 → 在通知輸入配對碼 → 自動更新、開「祈願 → 歷史紀錄」→ 回到 App 抓到資料。
- [ ] 先開其他遊戲內網頁再開歷史紀錄，仍抓到（Review Focus 1）；開頌願的歷史紀錄也能抓到。
- [ ] 等待中在遊戲裡關掉 Wi‑Fi（USB 偵錯關閉）再打開、開歷史紀錄、回到 App：仍拿到網址或繼續等待（Review Focus 2）。
- [ ] 等待中從最近使用的 App 清單把 App 滑掉，再開 App 按更新：手機上沒有殘留兩個監看程序（Review Focus 3）。
- [ ] 取消、更新完成後：`ps -A | grep logcat` 沒有我們的監看程序、`/data/local/tmp/tw.reh.genshin.gacha.url` 不存在；無線偵錯照開始前的狀態。
- [ ] 關閉無線偵錯、重開機、換 Wi‑Fi 後各更新一次；配對服務逾時後重新開始；`pm revoke` 模擬授權失敗（手動開關模式）；解除配對後再按更新。
- [ ] 手動輸入：貼上整段文字（頁面網址）、貼上 API 網址。

**模擬器**

- [ ] Android 10（API 29）：無 root 顯示「無法自動讀取（需要 Android 11 以上，或已 root）」與手動輸入。
- [ ] Android 12 或 13：配對服務自行逾時。
- [ ] rootAVD 修補的模擬器：root 讀取；`su` 下啟動的監看程序在 `su` session 結束前後的存活與清理。模擬器沒有原神，用 `log -t UnityUtils.sendUnityMessage 'send unity message:1,func :OnGetWebViewPageFinish,message:<假網址，含 auth_appid=webview_gacha>'` 寫入假紀錄。

**電腦版回歸**

- [ ] 攔截、讀網頁快取、手動輸入（等待中與不在等待時），結束後系統代理還原、18080 釋放。

**文件**

- [ ] 把驗證結果與新發現寫進 spec 的「3.3 實機實驗結果」與一個新的「附錄：實作時發現」；更新「尚未驗證」。Commit `docs(android): record credential capture verification results`。
