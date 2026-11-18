# Android 取得祈願紀錄網址（子專案 2）— 設計 spec

- 狀態：已核准（2026-11-18）
- 日期：2026-11-18
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第 2.1 節、第三節子專案 2、第八節）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-06-android-credential-capture-design.md`，以及合併到 master 後的最終程式（移植筆記 #2、#19～#21、#51～#53）
- 相關前作：`2026-11-17-web-cache-credential-fallback-design.md`（子專案 0，電腦版讀網頁快取）

---

## 一、目的

讓只用手機或平板、沒有電腦的玩家，在 Android 版按下「更新資料」後也能取得祈願紀錄網址，接著沿用既有的抓資料流程。兩個平台同時多一個「手動輸入祈願紀錄網址」的入口。

Android 無法攔截網路（遊戲的 WebView 不信任使用者安裝的 CA），遊戲檔案裡也沒有網址；網址只出現在系統記錄（logcat）。一般 App 讀不到其他 App 的 logcat，所以要用更高的身分讀：root，或無線偵錯自我配對取得的 shell（`uid=2000`）。

## 二、目標／非目標／反目標

**目標**

- Android 按「更新資料」後的體驗跟電腦版一致：先按更新，再去遊戲開「祈願 → 歷史紀錄」（或頌願的歷史紀錄），App 偵測到網址就自動開始抓。
- 讀取方式由 App 自動選擇，玩家不用懂 root 或 ADB。
- 無線偵錯配對只需做一次；之後每次更新由 App 自己開啟無線偵錯並連線。
- 兩個平台都能手動輸入：貼上網址或整段文字。
- 電腦版既有的攔截與讀網頁快取行為不變（手動輸入是新增入口）。
- 架構、UI/UX、檔案拆分比照鳴潮版最終程式（使用者要求一致），只換掉讀取層與術語。

**非目標**

- Android 10 以下的自動讀取（沒有 root 時只能手動輸入；使用者 2026-11-17 選定）。
- 國服（`hoyoverse.com` 以外的網域；App 本來就只支援國際服）、iOS。
- 讓 App 在背景持續監看：玩家在遊戲裡時 App 被系統凍結沒關係，由手機上獨立的監看程序負責。
- 讓玩家手動選讀取方式的設定。
- 選遊戲版本的畫面（見 3.2 第 5 點）。

**反目標**

- 讀取祈願紀錄網址以外的任何東西，或執行白名單以外的指令。
- 改動玩家的系統設定（例如用 `logcat -G` 調大緩衝區）；無線偵錯用完後保持開啟（除非玩家原本就開著）。
- 第一次使用就卡在配對：配對流程對不熟開發人員選項的人也要走得完。
- 把 authkey 寫進 App 的 log、通知內容，或留在手機上任何其他程式讀得到的地方。
- 在玩家沒有操作的情況下更新別的帳號（只採用按下更新之後才出現的網址）。

**用語**：UI 文字一律稱「裝置」，不說「手機」（比照鳴潮版）。遊戲內名稱依 `docs/術語表.md`（「祈願」「歷史紀錄」「頌願」等）。

## 三、做法

### 3.1 考慮過的做法

整體架構只有一種合理做法：照搬鳴潮版最終架構（讀取方式判斷、root／無線偵錯 shell、配對前景服務、設定頁區塊、等待畫面、手動輸入），只換讀取層。重新設計等於重踩鳴潮版已修好的雷（筆記 #19、#20、#53）。

讀取層的選擇（使用者 2026-11-17 已在路線圖選定）：

| 做法 | 取捨 | 結論 |
|---|---|---|
| **手機上獨立的 logcat 監看程序＋暫存檔** | 監看程序以 shell／root 身分在手機上跑，App 被凍結也照常運作；App 每秒讀暫存檔 | ✅ |
| App 維持 logcat 串流 | 長時間串流的斷線、重連、取消都要另外處理（筆記 #53） | ❌ |
| 只在回到 App 時補查 | 緩衝區小的手機，網址可能在玩家回來前被擠掉 | ❌（但作為補救，見 4.2） |
| 用 `logcat -G` 調大緩衝區 | 改到玩家的系統設定 | ❌ 反目標 |

### 3.2 和鳴潮版刻意不同的地方

1. **讀取來源**：logcat，不是 `Client.log`。`ClientLogSource`、`PollingClientLogWatch`、由新到舊讀、檔頭判斷換檔、XOR 解碼（筆記 #51）都不需要。
2. **沒有「Android 10 以下直接讀檔」**：沒有檔案可讀。`LogAccessMethod.legacyDirect`、儲存權限流程、`READ_EXTERNAL_STORAGE`、`requestLegacyExternalStorage` 都不移植。
3. **頁面網址轉 API 網址**：logcat 裡是祈願紀錄的頁面網址（`gs.hoyoverse.com/genshin/event/e20190909gacha-*/index.html?...`，頌願頁是 `e20250716gacha`）。沿用子專案 0 的 `findGachaUrls`（要求 `auth_appid=webview_gacha`）與 `toApiUrl` 轉成 `getGachaLog` 網址，不另寫。
4. **手動輸入只有貼上**：沒有「選擇 `Client.log` 檔案」。頁面網址與 API 網址兩種格式都接受。
5. **遊戲版本（筆記 #52）簡化**（使用者 2026-11-18 同意）：鳴潮版要依套件名稱決定 log 路徑，才需要選版本畫面；logcat 跟套件名稱無關。原神版只用套件名稱偵測「有沒有裝原神」與「開啟原神」按鈕：
   - 偵測國際服原神：套件名稱是 `com.miHoYo.GenshinImpact`，或以它加 `.` 開頭（涵蓋查不到套件名稱的其他商店版本）。不用 `QUERY_ALL_PACKAGES`，manifest 宣告已知套件與 MAIN／LAUNCHER `<queries>`（同鳴潮版）。
   - 沒有裝：等待畫面顯示「這台裝置上找不到原神」，並排「重新偵測」「前往 Google Play」與手動輸入；不跳 root 授權、不開無線偵錯。
   - 裝了多個：「開啟原神」開排序第一個（已知的 Google Play 版優先），不顯示選版本畫面、不記住選擇（沒有 `gamePackage` 設定）。
   - 查詢失敗（channel 出錯）不能當成沒裝，照常判斷讀取方式。
6. **手動輸入說明**（使用者 2026-11-18 選 A）：「如果已經用其他方式（例如電腦上的工具）取得祈願紀錄網址，可以貼在這裡；整段文字也可以，App 會自動找出網址。」不教飛航模式（原神 3.1 起失效），不提外部網站或工具。

### 3.3 實機實驗結果（2026-11-17～18，ASUS AI2501C、Android 16，USB adb）

這些是設計依據：

- 每打開一次「祈願 → 歷史紀錄」或頌願的歷史紀錄，logcat 都會出現 `MiHoYoWebview.load` 與 `UnityUtils.sendUnityMessage ... func :OnGetWebViewPageFinish,message:<網址>` 兩行，網址完整（authkey 約 1368 字元，沒被截斷）。兩頁都是 `auth_appid=webview_gacha`。
- 每次開啟的 authkey 都不同，所以按下更新之後才出現的網址一定是剛開的。
- `setsid logcat -T '<MM-DD hh:mm:ss.mmm>' -m 1 -e '<規則>' > <暫存檔> 2>&1 < /dev/null &` 在下指令的 shell 結束後仍繼續執行（父行程變成 init），符合時寫入暫存檔並自行結束。時間用手機上的 `date "+%m-%d %H:%M:%S.000"` 取得。
- **adbd 會把收到的指令原文寫進 logcat**。規則寫成 `OnGetWebViewPageFinis[h],message:https://[^ ]*auth_appid=webview_gach[a]`，指令原文裡沒有連續的 `OnGetWebViewPageFinish,` 與 `webview_gacha` 字樣，實測不會被自己的啟動紀錄觸發。App 送出的任何指令都不能含這兩段連續字樣。
- **只對到祈願／頌願紀錄頁**（2026-11-18 實測）：規則加上 `auth_appid=webview_gach[a]` 後，先開其他遊戲內網頁、再開祈願歷史紀錄，監看程序只抓到歷史紀錄頁。這次開的其他網頁在 logcat 沒有留下 `OnGetWebViewPageFinish` 紀錄，但其他種類的網頁可能會有，所以規則一律收窄（builder check 提出：寬鬆規則加上 `-m 1` 會停在第一個不相干的網頁，用同一個起點重啟又會停在同一行）。
- **adbd 重啟時監看程序會被一起結束**（`adb usb` 重啟 adbd 後實測）：init 停止 adbd 時會清掉它的 cgroup。USB 偵錯開著時只切換無線偵錯，監看程序不受影響。實際會發生在：玩家在遊戲裡時 Wi‑Fi 斷線（系統 2 秒內關掉無線偵錯），而且 USB 偵錯沒開，adbd 整個停掉。所以需要 4.2 的「監看程序不在了就重新啟動」。
- `/data/local/tmp` 屬於 shell，只有 shell 與 root 讀得到。

尚未驗證：root 的 `su` 下啟動的監看程序在 `su` session 結束後是否存活（用 rootAVD 模擬器驗）、其他廠牌的 logcat 格式與緩衝區大小、`-T` 跨年時的行為。

## 四、整體流程

### 4.1 按下「更新資料」（Android）

沿用 `GachaRepository._runUpdate`：手動輸入的網址 → 帳號存的網址 → 等待流程。等待流程在 Android 改走新的分支（`_acquireUrl` 依 `isAndroidProvider` 分到 `_runAndroidWait`，電腦版照舊 `_runMitm`）。Android 完全不呼叫 Rust：不攔截、不設系統代理、沒有 3 秒寬限與 backstop 收尾。

1. **判斷中**（`checkingLogAccess`）：只顯示「正在準備讀取遊戲記錄…」、進度條與「取消」（筆記 #20 流程段）。
2. **決定讀取方式**（`LogAccessResolver`）：先偵測原神（3.2 第 5 點），再依序：上次成功的方式 → root（找得到 `su` 且 `id` 回 `uid=0`；整次更新只開一個常駐 `su`）→ 無線偵錯（Android 11 以上：已配對、連著 Wi‑Fi、開啟無線偵錯、NSD 收集連接埠逐一連線）。
3. **沒有自動讀取方式時**：等待畫面不顯示進度條，改顯示原因（未配對、沒有 Wi‑Fi、連不上、需要允許網路、root 被拒、Android 10 以下不支援、找不到原神），並提供「設定讀取方式」（無線偵錯未配對時）與「手動輸入」。回到前景時自動重新判斷（不重新要求權限）。原因與重試規則照鳴潮版（筆記 #20）。
4. **開始監看**（4.2）：等待畫面顯示「開啟原神」與手動輸入。
5. **拿到網址**：App 不在前景時先顯示「已取得網址，請回到本 App」（`credentialReady`），等回到前景才開始抓（背景 App 的網路會被擋，筆記 #20）。接著結束監看、釋放連線，走既有的 `_fetchAllBanners`。
6. **無線偵錯的關閉規則**（照鳴潮版）：開始這次更新時已經開著的維持開啟；App 這次打開的一律關掉；沒有權限關閉時，完成畫面提示玩家可以自行關閉。
7. **全池失敗**（網址失效）：沿用既有的「重新取得一次」流程。

### 4.2 logcat 監看（取代鳴潮版的 `PollingClientLogWatch`）

新增 `LogcatUrlWatch`（`lib/state/logcat_url_watch.dart`），透過 `LogAccessReady` 提供的 shell 執行函式（`ShellExec`，root 與無線偵錯共用）運作，`start()` 回傳既有的 `CaptureSession`（`result` 是 API 網址或 null）：

1. **起點**：在手機上取時間 `date "+%m-%d %H:%M:%S.000"`，記為起點。不用 App 的時鐘（兩邊可能不同步）。
2. **清掉殘留**：結束上一次（App 被殺、手機沒重開）留下的監看程序並刪掉暫存檔（見 4.3）。
3. **啟動監看程序**：`umask 077; setsid logcat -T '<起點>' -m 1 -e 'OnGetWebViewPageFinis[h],message:https://[^ ]*auth_appid=webview_gach[a]' > '<暫存檔>' 2>/dev/null < /dev/null & echo $!`，記下 PID。不依 pid 或套件過濾 logcat：按下更新時遊戲可能還沒啟動，pid 未知；比對規則加上 App 端的 `findGachaUrls`（要求 `hoyoverse.com` 與 `webview_gacha`）已經夠精準。
4. **每秒輪詢**一次（App 回到前景時立刻補一次）：一條指令同時讀暫存檔並回報監看程序是否還在（`kill -0 <PID>`）。
   - 暫存檔有內容：用 `findGachaUrls` 找出網址、`toApiUrl` 轉換，完成 `result`。找不到合法網址（理論上不會發生，例如行被截斷）就刪掉暫存檔，以**手機目前的時間**為新起點重新啟動監看程序並記一筆 warning：沿用舊起點會一直停在同一行。
   - 暫存檔是空的、監看程序不在了（adbd 重啟過）：用同一個起點重新啟動監看程序。`-T` 會先輸出緩衝區裡起點之後的舊紀錄，所以監看程序不在的那段期間，只要網址還在緩衝區就不會漏。
   - 讀不到（連線斷了）：照鳴潮版重連；重連期間等待畫面顯示「連線中斷」。
5. **結束**（拿到網址、取消、更新結束）：結束監看程序、刪掉暫存檔，然後才釋放 shell（等進行中的輪詢停下來，筆記 #20）。

同一時間只有一個輪詢在跑（鳴潮版的 `polling` 旗標），取消時等進行中的輪詢結束。

### 4.3 暫存檔與殘留清理

- 暫存檔固定一個路徑：`/data/local/tmp/tw.reh.genshin.gacha.url`（只放這一個檔案），用 `umask 077` 建立，只有建立它的身分（shell 或 root）讀得到。檔案裡會短暫有 authkey，讀到後立刻刪除。
- 結束監看程序時不只靠記下的 PID（App 可能被殺、PID 會不見）：清理指令找出所有 `logcat` 程序，命令列含 `OnGetWebViewPageFinis[h]` 的才結束，再刪掉暫存檔。每次開始監看前、每次結束時都跑一次。
- root 啟動的殘留程序 shell 身分結束不了，下次用 root 時會清掉；手機重開機後也會消失。暫存檔若殘留，內容最多是一個已經被讀過、或從未被讀到的網址，只有 shell／root 讀得到。

### 4.4 手動輸入（兩個平台共用）

- 對話框（`AppDialog`）一個多行輸入框，接受任何文字（`keyboardType: TextInputType.url`、`autocorrect: false`、`enableSuggestions: false`，筆記 #20）。用 `findGachaUrls` 找出網址，由新到舊試，第一個轉得出 API 網址的就用。找不到時在輸入框下方提示，不關閉對話框。
- 說明文字照 3.2 第 6 點。
- **送出後**：
  - 正在等待時（等待畫面點進來）：直接完成這次等待。電腦版立即停止攔截（`_stopCaptureAfterCacheWin` 的 `skipGrace`），不等寬限，因為沒有遊戲請求要等；此行為於 2026-11-18 使用者實測後修改。
  - 不在等待時（說明頁、無法自動讀取的畫面點進來）：用這個網址啟動一次更新。
- 手動輸入的網址跟其他來源一樣存成帳號的快取網址。

### 4.5 等待畫面

沿用 `update_progress_dialog.dart` 的 `WaitingForCapture`，Android 改用 `AndroidLogWaitBody`（照搬）：

- Android 標題「等待祈願紀錄…」，提示「請開啟原神 → 祈願 → 歷史紀錄」（電腦版維持「等待攔截…」）。
- Android 新增「開啟原神」按鈕（`getLaunchIntentForPackage`），沒有裝原神時改成 3.2 第 5 點的畫面。
- 兩個平台都新增「手動輸入祈願紀錄網址」連結。
- Android 不顯示電腦版的「已經開啟歷史紀錄頁，卻一直沒有反應？」（那是選遊戲資料夾用的）。
- 判斷中、無法自動讀取、連線中斷、已取得網址請回到 App、root 被拒等狀態照鳴潮版。
- 手機橫向時 `AppDialog` 開 `scrollable: true`；長標題用 `Flexible`（筆記 #20）。

## 五、無線偵錯的第一次設定

照搬鳴潮版（第五節與筆記 #19、#20 的修正），只換名稱與用語：

- **說明頁**（也是 Google Play 要求的事前清楚揭露）：為什麼需要（Android 不允許 App 讀其他 App 的系統記錄）、本 App 會做什麼（只讀原神的祈願紀錄網址；讀完立刻中斷並關閉無線偵錯；授權自己開關無線偵錯；可以隨時在設定頁解除）、需要什麼（Android 11 以上、Wi‑Fi、通知權限）；按鈕「開始設定」「改用手動輸入」。
- **配對引導頁**：確認開發人員選項 → 通知權限 → 「前往無線偵錯」（兩段式 intent，加 `FLAG_ACTIVITY_NO_HISTORY`）→ 在通知輸入配對碼 → 配對成功後連線、授權 `WRITE_SECURE_SETTINGS`、自動返回並重新更新。
- **配對服務**（Kotlin `AdbPairingService`）：`shortService` 前景服務、自己計時 3 分鐘、只採用本機位址的配對服務、配對碼只留數字、結果通知用另一個 ID 並先結束服務。通知字串（`R.string.pairing_*`）放在各 `values-*`。
- **金鑰與授權**：`flutter_adb` 金鑰存在 `flutter_secure_storage`（連線時只讀不產生）；首次連上授權 `WRITE_SECURE_SETTINGS`；授權失敗走教學＋手動開關模式；設定頁「解除配對」。
- **配對名稱**：`genshin-wish-analyzer`（不能有空格，筆記 #20）。

## 六、指令白名單

透過 shell（無線偵錯或 `su`）只執行以下指令，全部是常數或只插入整數、經驗證的時間字串：

- `id`
- `date "+%m-%d %H:%M:%S.000"`
- 啟動監看程序（4.2 第 3 點，比對規則是常數）；起點只接受 `^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}$`
- 讀暫存檔並回報監看程序狀態：`cat '<暫存檔>' 2>/dev/null; kill -0 <PID> 2>/dev/null && echo <標記>`
- 清理（4.3）：結束命令列含 `OnGetWebViewPageFinis[h]` 的 `logcat` 程序，`rm -f '<暫存檔>'`
- `pm grant <本 App 套件> android.permission.WRITE_SECURE_SETTINGS`／`pm revoke ...`
- `settings put global adb_wifi_enabled 0`

確切的清理指令寫法留給實作（要用到的 `ps`／`pidof`／`/proc/<pid>/cmdline` 在實機確認），但只能比對上述固定字串，不能用 `pkill -f` 這類寬鬆比對。

## 七、原生程式（Kotlin）、權限與依賴

- `LogAccessChannel`（`tw.reh.genshin.gacha/log_access`）：照搬鳴潮版，去掉儲存權限；`installedGames` 改用原神的套件名稱開頭；`launchGame` 只開這個開頭的套件。
- `MainActivity`：建立／分離 channel、轉送權限結果。
- `AndroidManifest.xml` 新增：`WRITE_SECURE_SETTINGS`（`tools:ignore="ProtectedPermissions"`）、`ACCESS_NETWORK_STATE`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`、配對服務（`shortService`、`exported="false"`）、`<queries>`（`com.miHoYo.GenshinImpact` 與 MAIN／LAUNCHER intent）。
- Dart 依賴：新增 `flutter_adb` 1.0.0（純 Dart、BSD-3-Clause）；`flutter_secure_storage`、`synchronized` 已有。
- 設定（只存本機，不參與雲端同步）：`logAccessMethod`（`root`／`wirelessDebugging`）。沒有 `gamePackage`。

## 八、檔案對照（照搬鳴潮版最終程式）

| 鳴潮版 | 原神版 | 處理 |
|---|---|---|
| `lib/services/android/adb_shell_client.dart`、`flutter_adb_session.dart`、`root_shell.dart`、`log_access_platform.dart` | 同名 | 照搬，只換名稱（金鑰名、套件名、channel 名）；`log_access_platform` 去掉儲存權限 |
| `lib/services/android/log_access_method.dart` | 同名 | 去掉 `legacyDirect` |
| `lib/services/android/log_access_resolver.dart` | 同名 | `LogAccessReady.source` 改成 `ShellExec`；去掉 `_tryLegacy`、log 路徑相關；`_pickGame` 改成 3.2 第 5 點 |
| `lib/services/android/wuwa_game_package.dart` | `genshin_game_package.dart` | 套件名稱開頭、已知套件、排序、注入防護；去掉 log 路徑 |
| `lib/services/client_log_source.dart`、`client_log_credential.dart` | — | 不移植（只保留 `ShellExec` typedef，放在 shell 相關檔案） |
| `lib/state/client_log_watch.dart` | `lib/state/logcat_url_watch.dart` | 改寫（4.2、4.3） |
| `lib/state/adb_pairing.dart`、`app_foreground.dart`、`platform.dart` | 同名 | 照搬 |
| `lib/pages/log_access_setup_page.dart`、`lib/widgets/android_log_wait_body.dart`、`lib/widgets/cards/log_access_section.dart` | 同名 | 照搬；去掉選版本、儲存權限 |
| `lib/widgets/dialogs/manual_credential_dialog.dart` | 同名（或 `manual_url_dialog.dart`） | 只保留貼上 |
| `lib/state/gacha_repository.dart`、`update_progress.dart`、`lib/widgets/update_progress_dialog.dart`、`settings_storage.dart`、`settings.dart`、`settings_page.dart` | 同名 | 合併鳴潮版的 Android 分支（見第九節） |
| Kotlin `AdbPairingService.kt`、`LogAccessChannel.kt`、`MainActivity.kt` | `tw/reh/genshin/gacha/` | 照搬，換套件名 |

## 九、和子專案 0 的合併重點（`GachaRepository`）

- 電腦版的 `_cacheHit` 與鳴潮版的 `_logHit` 角色相同（「另一個來源先拿到網址」）；Android 等待也用這個 Completer 接手動輸入。
- 鳴潮版的 `_waitCancelled` 對應電腦版的 `_captureBackstop`；`cancelCapture()` 在 Android 只完成它並結束監看，不呼叫 Rust。`_cancelTriggered` 照電腦版保留。
- 「等 App 回到前景才抓」要放在 `_fetchAllBanners` 之前（`probeUid` 也是網路請求），之後才進 `Preparing`。
- 新增 `update({afterPairing})`、`retryLogAccess()`、`submitManualUrl(url)`、`_updateDone`；`forceRecaptureAndUpdate` 在 Android 一樣走 `_runAndroidWait`。
- `WaitingForCapture` 新增 `checkingLogAccess`、`logAccessUnavailable`、`rootDenied`、`logConnectionLost`、`credentialReady`、`gameNotInstalled` 相關欄位（照鳴潮版，去掉 `gamePackage`／`installedGames` 中選版本用到的部分）；`UpdateCompleted` 新增 `wirelessDebuggingLeftOn`。電腦版的 `captureUnavailable`、`gameDirMissing` 不變。
- 設定頁：Android 顯示「讀取遊戲記錄」區塊、不顯示「遊戲資料夾」區塊。

## 十、錯誤與邊界情況

| 情況 | 處理 |
|---|---|
| 沒有 Wi‑Fi、連不上、需要允許網路、授權失敗、root 被拒 | 照鳴潮版（筆記 #20） |
| 監看程序被結束（adbd 重啟） | 輪詢發現就用同一個起點重新啟動（4.2） |
| 網址在監看程序不在時被擠出緩衝區 | 等不到；玩家看得到仍在等待，重開歷史紀錄頁即可（新的網址一定在起點之後） |
| 暫存檔內容不是合法網址 | 刪掉，以手機目前時間為新起點重新啟動監看程序（4.2） |
| 玩家在遊戲裡時就拿到網址 | 等回到前景才抓（`credentialReady`） |
| 等待中切到背景、回來後連線已斷 | 自動重連；無線偵錯被關掉就重新開啟；不中斷等待 |
| 取消、更新結束 | 結束監看程序、刪暫存檔，再釋放連線；本次開啟的無線偵錯關掉 |
| App 被系統殺掉 | 監看程序與暫存檔留到下次更新時清掉（4.3） |
| 找不到原神、查詢失敗 | 3.2 第 5 點 |
| 手機時間在監看期間被調整 | 不處理（極少見），重開歷史紀錄頁即可 |

## 十一、Log

依 CLAUDE.md 用英文，Logger 沿用鳴潮版的樹：`capture.android`（讀取方式決定與耗時）、`capture.adb`（無線偵錯開關、NSD、連線、串流重試）、`capture.pairing`（配對，不記配對碼）、`gacha.logcat`（監看啟動、PID、重新啟動次數與原因、命中，網址一律 `sanitizeUrl`，不記暫存檔內容）。

## 十二、測試

**單元測試**（照鳴潮版的測試檔逐一移植，去掉 Client.log 相關）

- `adb_shell_client`、`flutter_adb_session`、`root_shell`、`adb_key_store`、`log_access_platform`、`log_access_resolver`（去掉 legacy、改成原神偵測）、`genshin_game_package`、`adb_pairing`。
- `LogcatUrlWatch`（新）：用假的 `ShellExec` 驗證：起點與啟動指令字串、命中後轉成 API 網址並清理、暫存檔是非法內容時以新起點重啟、送出的指令都不含連續的 `OnGetWebViewPageFinish,` 與 `webview_gacha` 字樣、監看程序不在時用同一個起點重啟、讀取失敗不中斷、取消時等輪詢結束再清理、清理指令只比對固定字串、起點格式驗證。
- `GachaRepository` Android 流程（照鳴潮版 `gacha_repository_android_test`）：命中、背景時等回前景、取消順序、無法自動讀取與重試、手動輸入完成等待／啟動新更新、全池失敗後重新等待、Windows 不受影響。
- 手動輸入：從整段文字找出頁面網址與 API 網址、多個網址取最新的合法一個、找不到時的提示；電腦版等待中送出會走快取勝出的收尾。
- 等待畫面、設定頁、說明頁的 widget 測試（照鳴潮版）。

**實機驗證（ASUS Android 16）**

- 全新安裝：說明頁 → 配對引導 → 配對 → 自動更新並抓到資料。
- 等待中切去遊戲開歷史紀錄再切回來；開頌願的歷史紀錄也能抓到；先開其他遊戲內網頁再開歷史紀錄，仍抓到歷史紀錄頁。
- 等待中關掉 Wi‑Fi 或關掉無線偵錯（USB 偵錯關閉時），回來後仍能拿到網址或繼續等待。
- 關閉無線偵錯、重開機、換 Wi‑Fi 後各更新一次。
- 配對服務逾時後重新開始；手動開關模式（`pm revoke` 模擬）。
- 手動輸入貼上整段文字；解除配對後再按更新。
- 取消後手機上沒有殘留的監看程序與暫存檔。

**模擬器驗證**：Android 10（只能手動輸入的畫面）、Android 12 或 13（配對服務自行逾時）、rootAVD 修補的模擬器（root 讀取、`su` 下的監看程序存活與清理）。模擬器沒有原神，用 `log -t UnityUtils.sendUnityMessage '...OnGetWebViewPageFinish,message:<假網址>'` 寫入假紀錄。

**電腦版回歸**：攔截、讀網頁快取、手動輸入（等待中與不在等待時）。

## 十三、文件

- 不新增移植筆記檔；實作中發現的新坑記進這份設計文件的附錄或子專案 13 整理。
- Google Play 上架說明（`WRITE_SECURE_SETTINGS`、前景服務、讀取 logcat 的用途、給審核員的操作說明）留給子專案 7，這裡只記下需要說明的項目。

## 十四、留給實作者決定

- 清理指令的確切寫法（只能比對固定字串）。
- 單次輪詢的指令合併方式、NSD 收集時間等數值（照鳴潮版）。
- ARB 字串的 key 名稱：新字串先寫 `app_zh.arb`，再翻其他已有翻譯的 8 份 ARB（空殼留給子專案 11）；`values-*/strings.xml` 的配對通知字串同樣做 9 種語言。
- 說明頁與引導頁照鳴潮版用獨立頁面。
