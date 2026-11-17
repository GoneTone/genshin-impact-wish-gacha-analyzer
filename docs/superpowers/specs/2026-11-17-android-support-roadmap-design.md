# Android 版支援：總體路線圖與可行性結論

- 狀態：草稿，待使用者核准
- 日期：2026-11-17
- 分支：`feat/android`（所有子專案都在這條分支上，全部完成後開一個 PR）
- 範圍：記錄為什麼做、要做成什麼樣子、怎麼拆分，以及實機驗證過的事實。各子專案的細節另外寫設計文件。
- 對照來源：
  - 鳴潮版姐妹專案 `wuthering-waves-convene-gacha-analyzer`：PR #101（`a6835c0`），以及合併後 master 上到 `795c59c` 為止的 commit。
  - 該專案的 `docs/Android移植筆記.md`（以下簡稱「筆記」，`#N` 指筆記第 N 節）與 `docs/superpowers/specs/2026-11-0x-*.md`。

---

## 一、目的與動機

讓只玩手機、沒有電腦的原神玩家也能使用本 App，並上架 Google Play。鳴潮版已經完成同樣的移植，原神版要跟它保持一致。

**原則（使用者 2026-11-17 指定）**：UI/UX、程式碼與架構都和鳴潮版一致，只有遊戲本身條件不同的地方才偏離。凡是要偏離鳴潮版的地方，都要先在設計階段和使用者確認，不能自行決定（見 `feedback_align_sister_project_verbatim`）。

**目標**

- Android 版提供和 Windows 版相同的全部功能，上架 Google Play。
- 鳴潮版的寫法能跨平台共用時就共用，做不到才依平台分流。
- 鳴潮版的通用改動照搬到原神版：流暢度、手機 UI/UX、多國語言、廣告、CI 與發版、README。

**非目標**

- iOS（沒有讀取其他 App log 的途徑）。
- 國服（和 Windows 版一樣，只支援國際服 `*.hoyoverse.com`）。
- 鳴潮版裡和遊戲本身綁定、原神用不到的部分，見第五節。

**反目標**

- 在背景偷偷讀取，或在玩家不知情時取得權限。每一步都要讓玩家知道，並由玩家觸發。
- 為了 Android 改壞 Windows 版既有的流程或 UX。

## 二、取得祈願紀錄網址的方式（實機驗證，2026-11-17）

### 2.1 Android

測試機：ASUS AI2501C（ROG Phone 9），Android 16，國際服原神 `com.miHoYo.GenshinImpact` 7.2.0（從 Google Play 安裝）。實驗只用 USB adb 與 session scratchpad，沒有寫進 repo；含 authkey 的暫存檔已經刪除。

- **攔截不可行**：和鳴潮版相同，遊戲的 WebView 不信任使用者安裝的 CA（筆記 #1）。
- **網址只出現在 logcat**。每打開一次「祈願 → 歷史紀錄」，logcat 會出現兩行帶完整網址的紀錄：
  - `D MiHoYoWebview.load(L:179): load:<id>,url:<網址>`
  - `I UnityUtils.sendUnityMessage(L:8): send unity message:<id>,func :OnGetWebViewPageFinish,message:<網址>`
- **網址格式**：`https://gs.hoyoverse.com/genshin/event/e20190909gacha-<hash>/index.html?win_mode=...&authkey_ver=1&sign_type=2&auth_appid=webview_gacha&init_type=200&gacha_id=...&timestamp=...&lang=...&device_type=...&game_version=...&plat_type=...&region=...&authkey=...&game_biz=...`。
  - 實測長度 1866 字元，其中 authkey 1368 字元，沒有被 logcat 截斷（單筆上限 4068 bytes）。
  - 這是祈願紀錄的**頁面網址**，不是 API 網址。把它的 query 原樣接到 `https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog` 後面（加上 `gacha_type`、`page`、`size`、`end_id`），API 回傳 `retcode 0`。所以要寫一段「頁面網址 → API 網址」的轉換；Windows 版攔到的本來就是 API 網址，不需要轉換。
- **同一個網址也能查頌願**：祈願歷史紀錄頁的 authkey（`auth_appid=webview_gacha`）接到 `getBeyondGachaLog`，`gacha_type=1000` 與 `2000` 都回傳 `retcode 0`。玩家只要開祈願的歷史紀錄頁，不用另外開頌願的頁面；`GachaUrl.build` 換最後一段路徑的做法照樣適用。
- **每次開啟的 authkey 都不同**：連開兩次，authkey 的雜湊不同，`timestamp` 參數相同。所以「按下更新之後才出現的網址」一定是剛開的，不會拿到舊網址。
- **遊戲檔案裡沒有網址**：開啟期間，`/sdcard/Android/data/com.miHoYo.GenshinImpact/` 底下只有 `files/LocalLog.log`（網路重連訊息）與 `files/GMESDK_<日期>.log`（語音 SDK）被寫入，兩者都是純文字，也都沒有網址。WebView 快取在 `/data/data/` 私有目錄，只有 root 讀得到。
- **歷史紀錄頁沒有網址列**：是遊戲內嵌的頁面，玩家沒辦法在遊戲裡直接複製網址。
- **logcat 緩衝區**：這台手機的 main 緩衝區是 8 MiB，遊戲執行時大約保留 29 分鐘。玩家開完歷史紀錄後幾分鐘內回到 App，網址都還在。
- **誰讀得到 logcat**：adb shell（`uid=2000`，無線偵錯自我配對拿到的也是這個身分）和 root 都可以。一般 App 讀不到其他 App 的 logcat，因為 `READ_LOGS` 不會授權給一般 App。
- **社群做法**（2026-11-17 查詢）：
  - 目前還能用的 Android 做法全部都是讀 logcat：jogerj 的 gist「Genshin Impact 5.x Wish URL Android」用 `adb logcat -m 1 -e "OnGetWebViewPageFinish.+https.+/log"`，有 Termux 無線偵錯、電腦 USB 腳本、WebADB 幾種版本。
  - 中文站流傳的「開飛航模式後重新整理，從錯誤頁複製連結」已經失效：paimon.moe 的 Android 分頁寫著「The old android method is not working on 3.1」，使用者也實測過沒用。

**結論與決定**

- **取得 shell 的方式照搬鳴潮版**（筆記 #2、#19、#20、#53）：
  - 依序嘗試 root（常駐 `su`）、無線偵錯自我配對（Android 11 以上，`flutter_adb`），都不行時手動輸入。
  - 照搬的細節：配對通知與前景服務、`WRITE_SECURE_SETTINGS` 一鍵恢復、NSD、開始前就開著的無線偵錯不關、取消時等輪詢結束才釋放、`guardAdbZone` 與逾時。
- **讀取方式：從 logcat 讀，而不是讀檔案**（使用者 2026-11-17 選定）。
  - 按下更新時記下裝置時間，App 每秒透過 shell 查一次，只取起始時間之後、符合網址規則的那幾行。
  - 不採用由 App 持續維持的 logcat 串流：長時間維持無線偵錯串流，斷線、重連、取消都要另外處理，鳴潮版在這些地方踩過雷（筆記 #53）。
- **網址可能在玩家回到 App 前被擠出緩衝區**：logcat 是環狀緩衝區。這台測試機開得比較大，但很多手機預設只有 256 KB～1 MB，以原神寫 log 的量估算，可能只保留 1～4 分鐘。鳴潮版讀的是檔案，沒有這個問題，所以「回到 App 再補讀」不能直接照搬。
  - **處理：在手機上啟動獨立的監看程序**（使用者 2026-11-17 選定方案 A）。按下更新時，透過 shell（或 root 的 `su`）啟動 `setsid logcat -T <起始時間> -m 1 -e '<網址規則>' > <暫存檔>`。它以 shell／root 身分獨立執行，App 被凍結也照常監看，遇到第一筆符合的就寫進暫存檔並結束。App 每秒讀一次暫存檔，讀到後立刻刪除。
  - 已實機驗證（2026-11-17，USB adb）：下指令的 shell 連線結束後，監看程序仍繼續執行，符合時寫入暫存檔並自行結束。
  - **踩雷**：adbd 會把收到的 shell 指令原文寫進 logcat（`adbd service requested 'shell,...:<指令>'`）。如果網址規則能對到啟動指令本身的文字，監看程序會被自己的啟動紀錄觸發。規則要寫成只能對到真正的網址行。
  - 取消更新、更新結束時都要結束監看程序並刪掉暫存檔。暫存檔裡會短暫存著 authkey，放在只有 shell／root 讀得到的 `/data/local/tmp`。
  - 不採用：只在回到 App 時補讀並提示玩家「盡快回來」（讀不到要重開頁面）；用 `logcat -G` 調大緩衝區（會改到玩家的系統設定，違反反目標）。
  - 鳴潮版的「由新到舊分段讀」「用檔頭識別判斷換檔」（筆記 #51）在 logcat 用不到，**不照搬**。
- **鳴潮版的「Android 10 以下直接讀檔」在原神版不存在**：沒有檔案可讀，logcat 也讀不到。
  - Android 10 以下、沒有 root 的裝置只能手動輸入（使用者 2026-11-17 選定方案 A）。
  - 不做「玩家先用電腦開 `adb tcpip 5555`，再由 App 連線」這條路。
  - 鳴潮版的儲存權限流程、`requestLegacyExternalStorage` 都不需要。
- **手動輸入**（兩個平台共用，鳴潮版在子專案 2 加入）：可以整段貼上，由 App 從文字裡找出網址（筆記 #19）；頁面網址與 API 網址兩種格式都接受。說明文字**不教**飛航模式，改寫「在電腦或其他工具取得網址後貼上」，最後的用詞在子專案設計時再定。

### 2.2 Windows：讀遊戲網頁快取（新增，比照鳴潮版移植前的 2026-11-01 設計）

鳴潮版在移植 Android 之前，電腦版就已經有「攔截＋讀遊戲 log」雙來源（`2026-11-01-client-log-credential-fallback-design.md`）。原神版電腦版目前只有 MITM 攔截。使用者 2026-11-17 決定這次一起補上，作為本分支的第一個子專案。

在維護者電腦上初步確認（2026-11-17）：

- 登錄檔 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\HYP_standalone_1_6_hk4e_global_<id>` 的 `InstallPath` 是 `D:\Program Files\Genshin Impact`，遊戲本體在 `<InstallPath>\games\Genshin Impact game`。另外有 `hk4e_global_1_0_<id>_production`，它的 `InstallLocation` 指向 HoYoPlay 啟動器資料夾。
- `%USERPROFILE%\AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt` 裡**有**遊戲路徑（例如 `D:/Program Files/Genshin Impact/games/Genshin Impact game/GenshinImpact_Data/...`），社群腳本（paimon.moe 的 `getlink.ps1`）就是用 `.:/.+(GenshinImpact_Data|YuanShen_Data)` 從這裡找路徑。（更正：初稿誤寫成沒有路徑，原因是當時用的搜尋規則排除了空白，對不到 `Program Files`。）
- 網頁快取在 `<遊戲>\GenshinImpact_Data\webCaches\<版本>\Cache\Cache_Data\data_2`，每個遊戲版本一個資料夾（本機有 2.51～2.57）。`2.55.0.0` 的 `data_2` 找得到 4 筆祈願網址，最新的 `2.57.0.0` 還沒有。
- `data_2` 是 Chromium 的快取區塊檔，不是一直往檔尾追加，鳴潮版「起點之後新寫入的網址」的判斷方式要改。

尚未驗證，留給子專案 0 設計時實測：

- 遊戲執行中能不能用共享模式讀 `data_2`；
- 打開歷史紀錄後多快寫進快取；
- 快取裡的是頁面網址還是 API 網址；
- 怎麼判斷「這筆是按下更新之後才出現的」。

## 三、子專案拆分與順序

一次做一個子專案，每個子專案各自走「設計 → 計畫 → 實作」，設計文件與計畫都提交在 `feat/android`。編號沿用鳴潮版，方便對照；原神版新增的編為 0。

| # | 子專案 | 對應鳴潮版 | 說明 |
|---|---|---|---|
| 0 | 電腦版讀遊戲網頁快取取得網址 | `2026-11-01-client-log-credential-fallback` | 原神版新增，見 2.2 |
| 1 | Android 平台基礎（能建置、能啟動） | `2026-11-05-android-platform-foundation` | 筆記 #4～#14 |
| ~~6~~ | ~~喚取立繪擷取~~ | `2026-11-05-android-luckdraw-capture` | **不適用**，見第五節 |
| 2 | Android 取得紀錄（root、無線偵錯、讀 logcat；兩平台共用的手動輸入） | `2026-11-06-android-credential-capture` | 筆記 #2、#19～#21、#51～#53，讀取層依 2.1 改寫 |
| 3 | 手機版面 | `2026-11-06-mobile-layout` | 筆記 #22～#25 |
| 4 | 檔案存取與分享 | `2026-11-06-file-access-and-sharing` | 筆記 #26～#28 |
| 5 | 雲端同步登入 | `2026-11-06-android-cloud-sync-login` | 筆記 #29～#33 |
| 7 | Play 上架與更新 | `2026-11-06-play-release` | 筆記 #34～#40 |
| 8 | 滑動流暢度 | `2026-11-07-mobile-scroll-smoothness` | 筆記 #41 |
| 9 | 手機 UI/UX 調整 | `2026-11-07-mobile-ui-ux-adjustments` | 筆記 #46～#48 |
| 10 | 原生廣告 | `2026-11-10-android-native-ads` | 筆記 #50 |
| 11 | 多國語言補齊與術語表 | 筆記 #49 | 22 種空殼語言一次補齊，先更新 `docs/術語表.md`，見下方說明 |
| 12 | 畫面停住的效能修正 | 筆記 #42～#45 | 桌面也適用 |
| 13 | 收尾：授權頁、README、商店素材、CI 與發版 | 筆記 #54～#56、合併後的 commit | 見第四節 |

**子專案 11 的術語表（使用者 2026-11-17 指定）**：翻譯前先更新 `docs/術語表.md`，這份表是翻譯的唯一依據。做法比照筆記 #49「怎麼找官方翻譯」：

- 遊戲內的祈願歷史紀錄頁是官方網頁（`gs.hoyoverse.com/genshin/event/e20190909gacha-*/index.html`），頁面文字依語言另外載入。用 2.1 取得的網址在一般瀏覽器開啟，從開發者工具的網路請求或 JS bundle 找出語系檔，取得每種遊戲語言的官方用語：
  - 卡池（祈願類型）名稱與下拉選單；
  - 頁面標題「祈願歷史紀錄」；
  - 欄位名稱「類型」「名稱」「祈願類型」「時間」；
  - 物品類型「角色」「武器」。
- 不要自動操作遊戲切換語言（有被防作弊誤判的風險）。
- 術語表目前只有 9 欄（zh_Hant、zh_Hans、en、ja、es、fr、pt、th、vi）。要補上遊戲有出、App 也有 ARB 的語言（預計 ko、de、ru、it、tr 等，以語系檔實際有的為準），pt_BR 跟官方葡文。
- 遊戲沒出的語言，在遊戲裡找得到的名稱（卡池名稱、側欄的祈願區塊標題、物品類型、句子裡提到的遊戲選單）一律用英文官方名稱。App 自己的敘述照常翻譯（筆記 #49 第 4 點）。
- Android 系統用語（「無線偵錯」「使用配對碼配對裝置」等）照各語言 Android 官方譯名，一併記進術語表。

順序：**0 → 1 → 2 → 3 → 4 → 5 → 7 → 8 → 9 → 10 → 11 → 12 → 13**，大致照鳴潮版實際完成的先後。子專案 7 之後可以從分支建 rc 版，送 Play 內部測試，邊做邊測。

## 四、鳴潮版合併後的 commit（也要照搬）

PR #101 合併後到 `795c59c` 的 commit，除了版本號 bump 與 Crowdin 自動 PR，都要套用到原神版：

- `d5aa15b`：恢復 MSVC coroutine workaround（`build_release.ps1` 的 `CL` 注入，筆記 #17）。原神版目前沒有 `flutter_inappwebview`，要在子專案設計時確認是否需要。
- `308587a`、`24c83e0`、`b263eea`、`6429ae8`：`release.yml` 改成 prepare／build-windows／build-android／publish 四個 job，Windows 在短路徑 worktree 建置，Play 上傳用 `tracks`（筆記 #9、#35）。原神版目前是 `release-windows.yml`，要合併成同一份 `release.yml`。
- `1a6a5ca`：安裝檔的數字版本欄位去掉 `-rc.N`（筆記 #35）。
- `37f8226`、`b29aa88`：Crowdin 同步，提醒合併後要用 CLI 補匯入 `strings.xml` 的既有翻譯（筆記 #49）。
- `8dac97f`、`ceef20a`、`795c59c`：README 截圖順序、下載徽章、商店主題圖片、`.github/release-footer.md`（筆記 #54、#56）。
- `6c6357b`：release-notes skill 指向本專案。原神版已經有自己的 `writing-release-notes` skill，只檢查有沒有要同步的段落。

## 五、和鳴潮版刻意不同的地方

| 項目 | 鳴潮版 | 原神版 | 原因 |
|---|---|---|---|
| Android 讀取來源 | `Client.log` 檔案（XOR 混淆） | logcat，由手機上的獨立監看程序寫進暫存檔 | 2.1 實測；logcat 會被擠掉（使用者選定） |
| Android 10 以下 | 宣告儲存權限後直接讀檔 | 只有 root 或手動輸入 | 沒有檔案可讀（使用者選定） |
| 由新到舊讀、檔頭識別換檔（#51） | 有 | 不需要 | logcat 用時間過濾 |
| 電腦版第二來源 | `Client.log` | `webCaches/.../data_2` | 遊戲不同 |
| 喚取立繪擷取（子專案 6，#16、#17） | `flutter_inappwebview` 離屏擷取 | 不做 | 原神版圖片來自 HoYoWiki，不需要 WebView |
| encore 網址修正（#18） | 有 | 不需要 | 原神版不用 encore |
| WinDivert 授權檔（#55） | 有 | 不需要 | 原神版用 MITM 代理，沒有 WinDivert |
| 底部橫幅廣告 | 先做後拿掉 | 不做，直接做原生廣告 | 鳴潮版最後的狀態就是只有原生廣告 |
| 手動輸入說明 | 教飛航模式複製錯誤訊息 | 不教飛航模式 | 原神 3.1 起失效 |

要照搬的通用提醒（筆記標「原神版也要注意」的地方）：

- 圖片下載用檔頭（magic bytes）確認是圖片才寫進快取（#18 的原則；原神版的圖片來源是 HoYoWiki）。
- Windows 解除安裝時清掉根憑證與私鑰（#40）。CN 與路徑要和 `rust/src/ca.rs` 一致。
- `ci.yml` 裡直接把 `${{ github.head_ref }}` 拼進 shell 的寫法改成走 `env`（#35）。
- 語言回退：整份清單對不上時回傳英文、挪威文 `nb`／`nn` 對到 `no`、`zh-Hant-*` 對到 `zh`（#12、#49）。

## 六、身分

- Android applicationId：**`tw.reh.genshin.gacha`**（鳴潮版路線圖第四節已經訂好的規則，上架後不能改）。
- 原神 Android 套件：國際服 `com.miHoYo.GenshinImpact`。其他商店有沒有不同的套件名稱，在子專案 2 調查（比照筆記 #52）。

## 七、需要使用者在帳號後台處理的事

做到相關子專案時再提醒，這裡先列出來：

- **Google Cloud**：在雲端同步桌面用戶端所在的**同一個專案**，為 debug、上傳金鑰、Play 簽署金鑰（含量子簽章的另外兩張憑證）各建一筆 Android OAuth 用戶端（#29～#32、#36）。
- **Play Console**：建立新 App、內部測試軌道、服務帳戶權限（唯讀＋發布到測試群組）、應用程式內容表單、隱私權政策網址（#35、Play 上架段落）。
- **AdMob**：新建 App 與一個原生廣告單元，在「隱私權與訊息」發布 GDPR 與美國州級訊息，把測試裝置登記好（#50）。
- **`app-ads.txt`**：商店頁「開發人員網站」要填有 `app-ads.txt` 的網域，不能填 GitHub（#50）。
- **GitHub secrets**：上傳金鑰、服務帳戶、`ADMOB_APP_ID`、`ADMOB_NATIVE_UNIT_ID`（#35、#50）。
- **Crowdin**：加入 `strings.xml` 這組設定，合併後補匯入既有翻譯（#49）。

## 八、留給各子專案設計時決定的事

- 子專案 0：`data_2` 的讀取與「新網址」判斷、遊戲資料夾的偵測順序（見 2.2 的待驗證項）。設計見 `2026-11-17-web-cache-credential-fallback-design.md`。
- 子專案 1：原神版沒有鳴潮版的 `tool/generate_app_icons.dart`（筆記 #10、#38 都說「沿用既有工具」），要一起移植，並確認目前 Windows 圖示是怎麼產生的。
- 子專案 2：
  - logcat 的網址規則與起始時間的格式。網址的判斷要用子專案 0 的 `findGachaUrls`（`auth_appid=webview_gacha`），不要寫死 `e20190909gacha`：頌願頁的網址是 `e20250716gacha`。也要實機確認打開頌願頁時 logcat 寫的是什麼；
  - 監看程序的生命週期：用什麼辨識並結束它（例如記下 PID）、App 被系統殺掉或手機重開機後留下的程序與暫存檔怎麼清，以及無線偵錯被關掉時監看程序會不會一起被終止。若會，回到 App 時要用 `logcat -d` 補查一次；
  - 頁面網址轉 API 網址放在哪一層；
  - 手動輸入的說明文字；
  - 其他商店版本的套件名稱；
  - 是否要依 pid 或套件過濾 logcat。
- 其餘子專案：照鳴潮版對應的設計文件逐檔對照，只換術語（卡池記錄、祈願、原神官方譯名，以 `docs/術語表.md` 為準）。
