# 子專案 0：祈願網址改由「攔截＋讀遊戲網頁快取」雙來源取得

- 狀態：已核准（2026-11-17）
- 日期：2026-11-17
- 分支：`feat/android`
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第 2.2 節、第三節的子專案 0）
- 對照：
  - 鳴潮版 `docs/superpowers/specs/2026-11-01-client-log-credential-fallback-design.md`（以下簡稱「鳴潮版設計」）。本文件照它的結構寫，只寫原神不同的地方與實測事實；沒提到的行為一律和鳴潮版設計相同。
  - 社群腳本 paimon.moe `getlink.ps1`（MadeBaruna 的 gist），它是原神電腦版取得網址的通行做法。本設計找資料夾與認網址的方式照它，差異見第四節。

---

## 一、目的與動機

讓「更新」不再只靠 MITM 攔截。等待攔截期間，同時讀取遊戲寫在本機的網頁快取 `data_2`，從裡面取得祈願網址。兩條路哪邊先拿到新網址就用哪邊。

兩條路的弱點互補：攔截怕根憑證被拒、埠被佔用、代理設定被其他程式改掉；讀快取怕遊戲改快取格式或位置。

這也是 Android 移植的前置工作：鳴潮版的 Android 讀取流程是從電腦版這層共用出去的，原神版補上這層，架構才和鳴潮版一致（路線圖第 2.2 節）。

## 二、目標／非目標／反目標

**目標**

- 等待攔截期間，背景同時監看 `data_2`，抓到**新出現**的祈願網址時就以它完成等待；下游流程（抓各卡池、存檔、進度 UI）完全不變。
- 自動偵測遊戲資料夾；偵測不到或偵測錯時，玩家可以從等待畫面的連結手動選擇。選擇結果存進設定，設定頁可以查看、修改、清除。
- 讀快取這條路的任何失敗都不能打斷等待，也不能讓更新失敗；一律只寫 log。
- 順便修好現有的 bug：攔截丟錯時畫面停在等待中、按取消沒反應（見 6.4）。

**非目標**

- 不改 MITM 攔截本身（`rust/`、系統代理、根憑證）。
- 不支援國服（和現有 MITM 一致，只認 `*.hoyoverse.com`；腳本裡的 `YuanShen_Data`、`public-operation-hk4e.mihoyo.com` 不採用）。
- 不修改遊戲檔案的權限，不執行或內嵌第三方腳本。只參考公開事實，自己實作。
- 手動輸入網址不在這個子專案，放在子專案 2（兩個平台共用，和鳴潮版相同）。

**反目標**

- 玩家看到的更新流程變了，或多了一個必須先做的步驟。
- 拿到快取裡**之前**留下的網址。舊網址可能還有效，但可能屬於遊戲目前登入的另一個帳號；鳴潮版的原則是一律請玩家開紀錄頁（鳴潮筆記 #51 最後一段）。
- 網址原文（含 authkey）寫進 App log。

## 三、已驗證的事實（2026-11-17，維護者本機，原神 PC 國際服，遊戲版本資料夾 `2.57.0.0`）

**遊戲資料夾**

- `%USERPROFILE%\AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt` 裡有遊戲路徑，例如 `D:/Program Files/Genshin Impact/games/Genshin Impact game/GenshinImpact_Data/StreamingAssets\...`（斜線混用）。腳本用 `.:/.+(GenshinImpact_Data|YuanShen_Data)` 取第一筆。這個檔案每次啟動遊戲會重寫，遊戲關掉後仍留著。
- 登錄檔 `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\HYP_standalone_1_6_hk4e_global_<隨機 id>` 的 `InstallPath` 是 `D:\Program Files\Genshin Impact`，遊戲本體在 `<InstallPath>\games\Genshin Impact game`。
- 另有 `Uninstall\hk4e_global_1_0_<隨機 id>_production`，`InstallLocation` 是 HoYoPlay 啟動器資料夾 `D:\Program Files\HoYoPlay`。本機的原神不在 HoYoPlay 底下，推測由 HoYoPlay 管理的安裝會在 `<HoYoPlay>\games\Genshin Impact game`，**未實測**。
- 子鍵名稱帶隨機 id，**不能寫死**，要列舉 `Uninstall` 底下名稱含 `hk4e_global` 的子鍵。

**網頁快取**

- 位置：`<遊戲>\GenshinImpact_Data\webCaches\<版本>\Cache\Cache_Data\data_2`。每個遊戲版本一個資料夾（本機有 `2.51.0.0`～`2.57.0.0`），舊版本的資料夾不會被刪掉。目前版本的網址只寫進最新版本的資料夾。
- `data_2` 是 Chromium 的快取區塊檔。本機 5 個版本的 `data_2` 都是 1,056,768 bytes，但這是區塊檔的初始大小，**不保證固定**，讀檔要依實際大小。內容沒有混淆，網址是 ASCII 原文。
- **祈願**歷史紀錄頁：每開一次寫進一把新的 authkey，同時有兩筆網址：
  - 頁面網址：`https://gs.hoyoverse.com/genshin/event/e20190909gacha-<hash>/index.html?...&auth_appid=webview_gacha&...&authkey=...&game_biz=...`
  - API 網址：`https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?...&auth_appid=webview_gacha&...&authkey=...&gacha_type=...`
- **頌願**歷史紀錄頁：網址不一樣，但同樣帶 `auth_appid=webview_gacha`：
  - 頁面網址：`https://gs.hoyoverse.com/genshin/event/e20250716gacha/index.html?...`
  - API 網址：`https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getBeyondGachaLog?...`
  - 頌願頁拿到的 authkey 查 `getGachaLog`（祈願）和 `getBeyondGachaLog`（頌願）都回傳 `retcode 0`。路線圖 2.1 已驗證祈願頁的 authkey 也能查頌願。所以**玩家開哪一頁都可以**，拿到的網址都能抓全部卡池。
  - 寫死 `e20190909gacha` 的話會漏掉頌願頁，這就是改用 `webview_gacha` 判斷的理由。
- **同一把 authkey 在頁面網址和 API 網址裡的百分比編碼可能不同**：直接比原始字串時，同一把 authkey 被算成兩把不同的；URL 解碼後才相同。比較 authkey 前一律先解碼。
- **舊的 authkey 不會被刪掉**：重開歷史紀錄後，舊的仍在快取裡，也仍然能用。
- 快取裡也有其他帶 authkey 的網址，例如公告頁 `act.hoyoverse.com/ys/event/.../blue-post`，它的 `auth_appid` 不是 `webview_gacha`。
- 新 authkey 寫進快取的時間：監看每 0.5 秒讀一次，玩家打開頁面後很快就出現（確切延遲沒量，但都在玩家回報「開好了」之前）。

**讀檔**

- 遊戲執行中，`data_2` 被瀏覽器元件開著。讀取端必須帶 `FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE`：
  - Dart 內建 `File(path).open()` 會失敗（`PathAccessException`，`errno = 32`）。鳴潮版讀 `Client.log` 用的就是它，這裡**不能照搬**。
  - .NET 只帶 `FileShare.ReadWrite` 也失敗，加上 `Delete` 才成功。
  - `package:win32` 的 `CreateFile`（`GENERIC_READ`、三種共享旗標、`OPEN_EXISTING`）＋`ReadFile` 可以完整讀出。

**攔截的失敗方式**（審查時讀程式確認）

- 原神版的攔截**不需要提權，沒有 UAC**。`rust/src/api/capture.rs` 的 `start_capture` 把根憑證裝進「目前使用者」的信任清單（只有第一次會跳 Windows 的憑證確認視窗），接著監聽 `127.0.0.1:18080` 並設定 HKCU 的系統代理。
- 會失敗的情況：第一次安裝根憑證時按了拒絕、18080 埠被佔用、套用代理失敗、`capture already running`。
- 憑證確認視窗開著時，`start_capture` 拿著 `SESSION` 鎖，`stop_capture` 要等同一把鎖，所以 `cancel()` 會等到玩家回應那個視窗（對應鳴潮版設計裡 UAC 的情況）。
- **現有 bug**：`session.result` 丟錯時，例外沒被接住，`progress` 停在 `WaitingForCapture`，而且 `_activeCancel` 已經是 null，按取消沒有反應。目前沒有測試涵蓋攔截丟錯。

## 四、做法選擇

**讀檔方式**

| 做法 | 取捨 | 結果 |
|---|---|---|
| **A. 純 Dart 每秒讀一次，用 `win32` 套件開檔** | 和鳴潮版相同的純 Dart 輪詢，只有開檔改用 `CreateFile`。`win32` 已經是間接依賴，改成直接依賴 | **採用**（使用者 2026-11-17 選定） |
| B. 在 Rust 寫讀檔函式，透過 FRB 呼叫 | 不新增 Dart 依賴，但要改 `rust/` 並重跑 codegen，使用者比較不熟 Rust | 不採用 |
| C. 檔案變更通知 | 鳴潮版已評估過：通知要等 flush，最後還是要輪詢 | 不採用 |

**和 paimon.moe 腳本的差異**（使用者 2026-11-17 決定採用前兩項）

| 項目 | 腳本 | 本設計 |
|---|---|---|
| 找遊戲資料夾 | 讀 `output_log.txt` | 依序：設定 → `output_log.txt` → 登錄檔 → 常見路徑（照腳本，再補登錄檔） |
| 認出祈願網址 | 含 `webview_gacha` 的快取項目 | 照腳本：`*.hoyoverse.com` 上 `auth_appid=webview_gacha` 且帶 authkey 的網址 |
| 轉成 API 網址 | 換網域與路徑，query 保留 | 相同 |
| 選快取版本資料夾 | 資料夾修改時間最新 | 版本號最大（結果固定、好測試；遊戲更新時兩種做法選到的一樣） |
| 選哪一筆 | 從最後一筆往前逐筆呼叫 API，挑第一筆能用的 | 只採用監看開始後才出現的 authkey（反目標：不拿舊網址） |
| 讀檔 | 複製到暫存檔再讀 | `win32` 共享讀取，不留暫存檔 |

## 五、使用者決定的行為（沿用鳴潮版設計第五節）

1. **流程不變，背景兩路比快**：按「更新」後一樣先試帳號存的網址，失效才進入等待畫面。等待期間攔截和讀快取同時進行，先拿到的那邊勝出。
2. **等待畫面多一行固定顯示的連結**，大意是「已經開啟祈願歷史紀錄，卻一直沒有反應？」。一直顯示，不加計時。唯一例外：攔截失敗、又找不到遊戲資料夾時，改由「選擇遊戲資料夾」按鈕取代這個連結（見 6.4）。
3. **點連結開說明視窗**，內容依情況調整：
   - 找不到遊戲資料夾：說明找不到，提供「選擇遊戲資料夾」。
   - 已經有資料夾：顯示目前讀取的路徑，提供「重新選擇」。
4. **選好的資料夾存進設定**；設定頁新增「遊戲資料夾」欄位，可以查看、修改、清除。

## 六、設計細節

### 6.1 新元件

鳴潮版之後在 Android 移植時，把這層改成「來源介面＋共用監看器」的結構。原神版的 Android 讀的是 logcat（路線圖 2.1），來源形狀和電腦版不同，所以只共用「監看器介面」與「從文字找網址」，不共用讀檔細節。

- **`lib/services/gacha_url_extract.dart`**（純函式，不碰 I/O）：
  - `findGachaUrls(String text)`：找出所有 `https://*.hoyoverse.com/...` 且 query 有 `auth_appid=webview_gacha` 與 `authkey` 的網址，依在文字中的位置排序，回傳每筆的網址、解碼後的 authkey、是不是 API 網址（路徑以 `/getGachaLog` 或 `/getBeyondGachaLog` 結尾）。
  - `toApiUrl(String url)`：網域換成 `public-operation-hk4e-sg.hoyoverse.com`、路徑換成 `/gacha_info/api/getGachaLog`、去掉 fragment，query 原樣保留；已經是 API 網址的也統一成 `getGachaLog`。`GachaUrl.build` 之後會依卡池換成正確的端點與 `gacha_type`。
  - 子專案 2 的 Android logcat 讀取與手動輸入都用這兩個函式（路線圖第八節要同步改寫 logcat 規則）。
- **`lib/services/web_cache_reader.dart`**：Windows 專用，用 `win32` 的 `CreateFile`（三種共享旗標）＋`ReadFile` 依實際檔案大小讀出整個檔案。只有這個檔案 import `win32`。
- **`lib/services/game_dir_locator.dart`**：自動偵測遊戲資料夾，並驗證手動選擇的資料夾。結構照鳴潮版同名檔案（`GameDirLocation`、`GameDirLocator.locate`／`normalize`、可注入的登錄檔讀取函式），多一個可注入的 `output_log.txt` 讀取函式。用 `win32_registry`（改成直接依賴，版本跟著 lock 檔現有的 2.1.0）。
- **`lib/state/gacha_url_watch.dart`**：監看器介面，比照 `GachaCapture`／`CaptureSession`（`start()` 回傳有 `result` future 和 `cancel` 的物件），讓 `gacha_repository` 對稱地比快，測試也能注入 fake。Windows 的實作是 `WebCacheUrlWatch`；子專案 2 會加 Android 的 logcat 實作。鳴潮版現在的 `client_log_watch.dart` 是 Android 移植後的形狀（`start(ClientLogSource)`），介面細節由實作者照本專案需要決定。

### 6.2 新網址的判定（避免拿到舊網址）

- 監看開始時，讀一次**所有已存在**的 `webCaches\<版本>\...\data_2`，記下裡面所有祈願網址的 authkey（解碼後），當作 **baseline 集合**。
- 之後每一輪出現**不在 baseline 裡**的 authkey，就是玩家剛開的：
  - 同一把 authkey 有 API 網址時，優先用 API 網址；只有頁面網址時用 `toApiUrl` 轉換。
  - 一輪裡出現多把新 authkey 時（玩家連開兩次），任取一把都可以，因為都是剛開的、都有效。實作取檔案中位置最後的那把。
- 監看開始後才出現的版本資料夾（遊戲在監看期間更新、或第一次打開網頁才建立），裡面的 authkey 一律不在 baseline 裡，全部算新的。**不要**在切換到新資料夾時重算 baseline，否則會吃掉玩家剛開的網址。
- 開始監看時 `data_2` 或整個 `webCaches` 還不存在：baseline 為空集合。
- 等待途中才選好或換了遊戲資料夾時，baseline 從**選好的那一刻**重新讀，並請玩家**再開一次祈願歷史紀錄**（和鳴潮版相同）。

### 6.3 定時讀取

- 每 1 秒找一次**版本號最大**的 `webCaches\<版本>` 資料夾（每輪都重找），讀它的 `data_2`。版本號依數字比較（`2.57.0.0` > `2.9.0.0`），不能用字串排序；名稱不是版本號格式的資料夾略過。
- 只掃 `data_2`，和腳本一致。
- 讀檔與找網址整段在背景 isolate 執行（`Isolate.run`）。這是鳴潮版後來為了不讓畫面停住才改的做法（鳴潮筆記 #44），這裡一開始就照最後的樣子寫：
  - 送進 isolate 的閉包寫在 top-level 函式、只抓參數（鳴潮筆記 #42）；
  - 背景 isolate 的 `Logger` 不會進 App log，需要記錄的事由背景交回，在主 isolate 寫。
- 讀檔失敗（被鎖、權限、檔案不存在）只記 `warning`，下一輪再試。同樣的錯誤連續發生時只在狀態改變時記一次，不要每秒都記。

### 6.4 與攔截的比快（`gacha_repository._runMitm`）

沿用鳴潮版設計 6.4 的規則，把「log」換成「快取」，「UAC」換成原神版的實際失敗方式：

- 進入 `WaitingForCapture` 時，同時呼叫 `gachaCapture.start()` 和 `gachaUrlWatch.start()`。
- **快取先拿到**：先給攔截最多 **3 秒**寬限，等它的 `result` 自己完成；3 秒內沒完成才呼叫 `cancel()`。不論哪一種，都要**等 `result` 完成**（MITM 已停、系統代理已還原）才回傳網址。現有程式刻意等 stream `onDone` 才開始抓資料，這個前提要保留。
  - **為什麼要寬限**（2026-11-17 手動 E2E 發現，使用者選定方案 A、上限 3 秒）：快取通常只比 MITM 晚幾十毫秒看到網址，這時遊戲的 API 請求還在經過代理轉送。立刻 `cancel()` 會切斷這個請求，遊戲的歷史紀錄頁顯示「無法取得數據，請檢查網路後重試-(undefined)」。MITM 本來就會在上游回應回來後再等 500 毫秒自己停止（`rust/src/mitm.rs` 的 `handle_response`），所以一般情況只多等 0.5～1 秒，和改版前相同；3 秒上限只在 MITM 活著卻攔不到時才會用滿。
  - 寬限期間使用者按取消，要立即生效（照常走 `cancelCapture`）。
  - 快取勝出後，攔截端的錯誤一律記 `warning` 並忽略。
  - `cancel()` 可能卡住（例如憑證確認視窗還開著），等待期間取消按鈕要照樣能用。
- **攔截先拿到**：停止快取監看，流程跟現在一樣。
- **使用者取消**：兩邊都停掉。
- **快取還沒勝出前，攔截就失效**（`result` 丟錯，或結束時沒攔到、且不是使用者取消）：
  - **先呼叫攔截 session 的 `cancel()`（Rust `stop_capture`）收掉它，再改成只等快取。**（2026-11-17 手動 E2E 發現）`mitm::start` 是在背景 task 裡才 bind 18080，bind 失敗時 `start_capture` 已經回傳成功、系統代理也已經設成 `127.0.0.1:18080`；之後 MITM task 結束、stream `onDone`，但 Rust 的 `SESSION` 仍握著代理的 guard。不呼叫 `stop_capture` 的話，系統代理一直指向不存在的代理，遊戲頁面與瀏覽器全部連不上。`cancel()` 丟錯只記 `warning`，照樣改成只等快取。
  - 快取監看有在跑：不判定失敗，改成只等快取。等待畫面多一行警示色提示，說明攔截程式無法啟動（可能是憑證被拒絕或連接埠被佔用），改為只從遊戲網頁快取偵測，請開啟祈願歷史紀錄。用詞由實作定，**不能**寫成鳴潮版的「Windows 權限提示被拒絕」。
  - 沒有快取可等（找不到遊戲資料夾）：留在等待畫面，提示說明兩者都不行，並直接顯示「選擇遊戲資料夾」按鈕，此時不顯示說明連結。選好後監看接上，提示換回上一則。
  - 只有使用者主動按取消時，才當作取消結束。
  - 這同時修掉第三節的現有 bug：攔截丟錯時不再卡住，取消也一定有效。
- 第一次（primary）和網址失效後重新取得（fallback）兩種情況都走這個比快流程。
- 現有的 `_captureBackstop`（確保等待一定有界）要涵蓋兩條路都在跑的情況。

### 6.5 遊戲資料夾

- **自動偵測的順序**：
  1. 設定裡存的資料夾（驗證有效才用）。
  2. `output_log.txt`：用和腳本相同的規則找 `.:/.+GenshinImpact_Data`，取第一筆，去掉結尾的 `GenshinImpact_Data` 得到遊戲資料夾。斜線統一成 `\`。
  3. 登錄檔：在 HKLM、HKCU、`WOW6432Node` 的 `...\CurrentVersion\Uninstall` 底下，列舉名稱含 `hk4e_global` 的子鍵，讀 `InstallPath`，沒有就讀 `InstallLocation`。每個路徑依序試：路徑本身、`<路徑>\games\Genshin Impact game`、`<路徑>\Genshin Impact game`。
  4. 常見安裝路徑（清單由實作者定，只列查證得到的）。

  不掃描整個磁碟。log 記下用的是哪個來源（`setting`／`outputLog`／`registry`／`common`／`none`）。
- **有效的定義**：`<資料夾>\GenshinImpact_Data` 存在。不要求 `webCaches` 存在，因為還沒開過任何網頁時它可能還沒建立。
- **手動選擇時的寬容處理**：選到啟動器資料夾或安裝根目錄時，自動往下找 `games\Genshin Impact game`、`Genshin Impact game`；選到 `GenshinImpact_Data` 本身時往上一層。都不符合時在視窗內顯示錯誤，讓玩家重選。
- **設定**：`SettingsStorage` 新增 `pref.gameDir`（和鳴潮版同名），每台電腦各自的設定，**不加入雲端同步**。
- 設定的資料夾後來失效時，當作沒設定，退回自動偵測。

### 6.6 UI

照鳴潮版設計 6.6，元件名稱也照鳴潮版：

- **等待畫面**（`lib/widgets/update_progress_dialog.dart` 的 `WaitingForCapture` 分支）：在開遊戲提示下方加一個不顯眼的文字連結。
- **說明視窗**：`lib/widgets/dialogs/game_dir_help_dialog.dart`，用 `AppDialog`（`size: AppDialogSize.sm`），開在等待視窗上方。資料夾選擇與錯誤顯示放在 `lib/widgets/game_dir_picker.dart`，等待畫面、說明視窗、設定頁共用。選資料夾用既有依賴 `file_selector` 的 `getDirectoryPath`（子專案 4 會整批換成 `file_picker`）。
  - **陷阱**（鳴潮版已踩過）：`UpdateProgressDialog` 在 progress 變成 null 時會 `Navigator.pop()`。說明視窗要在狀態離開 `WaitingForCapture` 時自己先關閉，否則被 pop 掉的是說明視窗、進度視窗反而留著。
- **設定頁**：放在既有的 `SectionCard` 裡，顯示目前路徑和來源（自動偵測／手動設定），提供「選擇」「清除」。
- **字串**：
  - 先寫 `app_zh.arb`（template），再翻到其他**已翻譯**的 ARB（en、zh_Hans、es、fr、ja、pt_BR、th、vi）。空殼 ARB 留到子專案 11 一次補齊。
  - 用詞照 `docs/術語表.md` 與遊戲內用語（「祈願」「歷史紀錄」）。描述遊戲檔案時用「遊戲網頁快取」這類描述行為的說法。
  - 提示文字只要請玩家開「祈願歷史紀錄」即可；玩家開的是頌願頁也一樣能用，不必另外說明。
  - 標點：繁中全形，省略號用半形 `...`。
- 所有可點的連結與 `InkWell` 都顯式設 `mouseCursor: SystemMouseCursors.click`。

### 6.7 Log（logger 名稱 `gacha.webCache`，訊息一律英文）

- `info`：
  - 監看開始：資料夾來源、快取版本資料夾、baseline 筆數；
  - 換到新的版本資料夾；
  - 命中：網址經 `sanitizeUrl`，標明是 API 網址還是頁面網址；
  - 哪一邊贏了比快。
- `warning`：開檔或讀檔失敗（附 Win32 錯誤碼）、找不到遊戲資料夾、登錄檔或 `output_log.txt` 讀取失敗、攔截失效後改成只等快取。
- 網址一律經 `sanitizeUrl`（現有函式會遮蔽 authkey），路徑一律經 `sanitizeFsPath`。

## 七、測試（驗收條件）

- 單元測試：
  - `findGachaUrls`：
    - 從混雜的二進位內容裡找出祈願與頌願的頁面、API 網址；
    - 忽略公告頁等 `auth_appid` 不是 `webview_gacha` 的網址；
    - 忽略非 `hoyoverse.com` 網域；
    - 同一把 authkey 的編碼不同時，解碼後視為同一把。
  - `toApiUrl`：頁面網址（祈願、頌願）與 `getBeyondGachaLog` 網址都轉成 `getGachaLog`，網域、query 正確。
  - 監看器（用暫存檔與 fake 讀檔函式）：
    - baseline 裡的 authkey 不採用；
    - 新 authkey 優先用 API 網址，只有頁面網址時轉換後回傳；
    - 開始時檔案不存在、之後才出現；
    - 監看開始後才出現的版本資料夾，裡面的網址算新的；
    - 版本資料夾用數字排序，非版本格式的資料夾略過；
    - 讀檔失敗不中斷監看。
  - `game_dir_locator`：
    - 從 `output_log.txt` 內容取出遊戲資料夾（含斜線混用）；
    - 列舉登錄檔子鍵並組出三種候選路徑；
    - 選到安裝根目錄或 `GenshinImpact_Data` 時自動修正；
    - 無效資料夾回報錯誤。
- repository 測試：用 fake watcher 和 fake capture 驗證比快，案例同鳴潮版設計第七節：
  - 快取贏時，一定在攔截的 `result` 完成後才開始抓資料；
  - 快取贏後攔截收尾丟錯，照樣完成更新；
  - 攔截贏；
  - 取消；
  - 攔截先丟錯時改成只等快取，取消仍然有效（鎖住第三節的現有 bug）；
  - 找不到資料夾時顯示選擇按鈕。
- widget 測試：說明視窗開著時狀態離開 `WaitingForCapture`，兩個視窗都正確關閉。
- 等待非同步結果的測試，等條件成立，不要賭時間或圈數（鳴潮筆記 #43）。
- `fvm flutter analyze`、`fvm flutter test` 全綠。
- 手動 E2E（維護者本機）：
  1. 正常情況：攔截和快取都能拿到，任一方勝出後都能完成更新。
  2. 先佔住 `127.0.0.1:18080` 讓攔截失敗（例如另開一個程式監聽這個埠）：等待畫面顯示改為只從快取偵測，只靠快取也能完成更新。
  3. 打開的是頌願歷史紀錄頁：同樣能完成更新，祈願與頌願卡池都有抓到。
  4. 清掉設定的資料夾，並讓自動偵測找不到（例如在除錯建置注入空結果）：等待畫面顯示選擇資料夾，選好後能完成更新。

## 八、留給實作者決定

- 讀取間隔的精確值（約 1 秒）。
- 常見安裝路徑的清單內容。
- 說明視窗、設定頁欄位、警示提示的實際版面與用詞（遵守 RWD、不超出邊界）。
- 監看器內部用 `Timer.periodic` 或 async loop，以及介面的確切形狀。
- `win32` 讀檔的緩衝方式與錯誤碼對應。
