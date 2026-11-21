# 畫面停住的效能修正（子專案 12）— 設計 spec

- 狀態：已完成（2026-11-22）
- 日期：2026-11-21
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 12；順序 8 → 9 → 12 → 10 → 11 → 7 → 13）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `docs/Android移植筆記.md` 第 42～45 節，commit `4a0a9db`～`1b7f8e8`（清單見第二節）；鳴潮沒有為這段寫 spec
- 前一個子專案：`2026-11-20-mobile-ui-ux-adjustments-design.md`（子專案 9，附錄 B 有 ROG Phone 的滑動流暢度）

---

## 一、目的

子專案 8、9 處理的是「捲動時掉幀」。這個子專案處理另一種卡頓：某些操作讓主 isolate 一次忙幾十到幾百毫秒，畫面在那段時間完全凍住。鳴潮在 ROG Phone 上量到的情境與修正前的最長停頓：

| 情境 | 鳴潮修正前 | 鳴潮修正後 |
|---|---|---|
| 開 App 的雲端同步 | 上傳 387 ms，另有 100、43、30 ms 等多段 | 約 5～10 ms |
| 轉換資料語言（0 筆要轉） | 76 ms 起，多段 | 約 18 ms |
| 更新記錄（新增 0 筆） | 超過 8 ms 的 99 段，最長 72.8 ms | 3 段，最長 14.2 ms，後來也處理了 |
| 打開設定頁 | 53 ms | 43 ms |

這些修正都在 Android 與電腦版共用的程式（`lib/services`、`lib/state`），電腦版也一起受益。

## 二、範圍：鳴潮 commit 對照

| 鳴潮 commit | 內容 | 原神 |
|---|---|---|
| `4a0a9db`、`57eb498`、`c80f960`、`e526a20`、`f4d8555`、`52cb8c8` | 雲端同步：解析、匯出、指紋改在背景 isolate；指紋相同時跳過合併與上傳；下載與上傳在背景直接打 Drive REST（上傳用 `uploadType=media`）；匯出改傳記錄檔路徑；合併前挑出內容相同的帳號；合併後沒變的帳號不重寫、不換物件；變動檢查與同步互不重疊 | 照搬。原神這幾個檔和鳴潮改版前只差套件名稱、`playerId`→`uid`、用字 |
| `b8a6bf1` | 存檔 JSON 編碼改在背景；設定頁匯出、匯入改在背景；轉換資料語言沒變就不寫檔；`test/helpers/wait_until.dart` | 照搬；`sameContentAs` 依原神資料模型改寫（第四節） |
| `ac19cfa`、`c0f4217` | 進度在對話框建構前就清空時，對話框自己關掉（只在第一次建構時檢查） | 照搬。原神多了「抓 HoYoWiki」「轉換資料語言」兩個階段，不影響修法 |
| `81d3dfa` | 等待擷取時的 Client.log 輪詢改在背景；綜合頁、卡池頁只訂閱需要的欄位 | 輪詢部分不適用（第四節）；頁面訂閱原神已經有 |
| `a5aafcf` | 測試鎖住「只改進度時資料頁不重建」 | 原神已經有（`phone_layout_pages_test.dart` 約第 758 行），不用搬 |
| `60b6f2a` | 語言對照表在背景讀檔解析 | 照搬；原神的解析欄位不同（HoYoWiki），讀檔流程相同 |
| `19a911d` | 設定頁語言選單只排版選中項目（`_onlySelectedLabel`）；兩個 setter 先改狀態再存檔 | `_onlySelectedLabel` 照搬到原神的介面語言、資料語言兩個選單；setter 原神已經是先改狀態再存檔（`state/settings.dart` 的 `setLocale`、`setDataLanguage`），不用改 |
| `1b7f8e8` | 量測工具 `tool/measure_ui_stalls.py` | 照搬，第一個做（第五節）。要改兩處：App 套件 `PKG = 'tw.reh.genshin.gacha'`，以及 `bursts` 用來辨識 App 函式的 Dart 套件名稱（鳴潮寫死 `'wuthering_waves_convene_gacha_analyzer'`，改成 `'genshin_impact_wish_gacha_analyzer'`，否則列不出 App 函式） |
| `66ed80f`、`0a241f9`、`9bd47bd`、`e9a64f2`、`95f4f40` | 移植筆記 | 不搬。原神把量測結果與實作坑記在本 spec 附錄 |
| `2e0a962`（2026-11-18） | 手動輸入對話框測試改用共用的 `pumpUntil` | 原神的手動輸入對話框測試沒有自己的等待 helper，不用改；原神自帶等待 helper 的是 `game_dir_help_dialog_test.dart`、`share_image_progress_test.dart`、`gacha_repository_web_cache_test.dart`，改用共用的 `pumpUntil`／`waitUntil`（**我的判斷**：同一個精神，順手統一） |

**不在範圍**：鳴潮 `1b7f8e8` 之後改擷取流程的 commit（`3a49857`、`e5e6cbc`、`5a00899`、`c0a8870`、`199c979`）屬於鳴潮的 Client.log 擷取，原神沒有這條路徑；`337ce7d` 是鳴潮的用字修正。

**追加（2026-11-21，使用者決定在這次一起改，鳴潮同步修正）**：修正前量測的情境 6 發現，「更新完成」或「更新失敗」視窗開著時，`importBundleForCloudSync` 把留給視窗顯示的終態進度（`UpdateCompleted`、`UpdateFailed`）也當成忙碌，拋 `CloudSyncBusyException`。同步層接著每 5 秒 `busyRetry` 一次，而且每次都先整份下載雲端檔再被擋，直到使用者關閉視窗。
- **改法**：忙碌判斷改成 `_isUpdating` 為真，或進度不是 null 且不是終態。更新、匯入、轉換資料語言的入口原本就會檢查 `_isUpdating`，所以雲端合併與這些流程仍然互斥。
- **鳴潮**：`lib/state/gacha_repository.dart` 的同一處（另有 `isBootstrapping` 條件，保留），在鳴潮 master 另外 commit；push 前問使用者。鳴潮另一處相同判斷 `fetchItemImagesForCloudSync` 不改：它自己會顯示進度視窗，結果視窗開著時略過是對的，也不會重試。

**追加二（2026-11-21，使用者決定這次一起做，鳴潮同步修正）**：開 App 讀存檔 `GachaStorage.load` 在主 isolate 讀檔＋解析 JSON＋轉成資料物件，朋友帳號約 1,100 筆時 31 ms；時間隨記錄筆數線性增加，記錄很多的使用者開 App 時載入動畫會停住。
- **改法**：讀檔、解析與 `BannerStorage.fromJson` 整段放進背景 isolate（top-level 函式、只抓路徑）；錯誤丟回主 isolate 後照原本的 `severe` log 與 `rethrow`。檔案不存在時仍回 null。
- **鳴潮**：`lib/services/gacha_storage.dart` 的 `load` 同樣改，在鳴潮另外 commit。

**追加三（2026-11-22，使用者決定，鳴潮同步修正）**：Task 5 照搬鳴潮 `e526a20` 後，同步匯出會在背景 isolate 讀 `<uid>.json`。Windows 上 Dart 開檔不帶 `FILE_SHARE_DELETE`，同一瞬間的存檔（`_atomicWrite` 的 rename）或刪除會拋 `PathAccessException`（errno 5，審查已實測重現），那次更新、匯入或刪帳號就會失敗。不會毀損資料，Android 不受影響。
- **改法**：`GachaStorage` 的 rename 與 delete 遇到 `PathAccessException` 時短暫重試，用盡才照原本的方式拋出。不改同步層，也不加鎖（使用者選擇）。
- **鳴潮**：同樣改。

**追加四（2026-11-22，使用者決定，鳴潮同步修正）**：鳴潮 `52cb8c8` 的「內容相同的帳號不送進合併」比對時忽略別名。雲端有別名、本機沒有的帳號因此被判為相同而跳過合併，雲端別名進不來，接著還會被本機上傳洗掉，兩台裝置每輪互相覆寫。
- **改法**：帳號只有在「內容（不看別名）相同」而且「本機已有別名，或雲端沒有別名」時才算相同，與 `_runImport`「本機已有別名就保留本機」的規則一致。
- **鳴潮**：同樣改。

**追加五（2026-11-22，使用者決定，鳴潮同步修正）**：審查時發現，log 寫入的例外物件與 stack trace 可能帶出 Windows 使用者名稱（家目錄路徑）、檔名裡的 uid，以及網址的 authkey。
- **曾經的做法**：起初逐處改成只記錄錯誤型別。這樣改動量大、寫法不一致，排查時也看不到錯誤原因（例如 `errno`、`Permission denied`），因此撤回。
- **改法**：改在 `LogService` 寫入每一筆 log 前，對整行文字統一套用 `sanitizeLogMessage`，範圍涵蓋訊息、例外物件與 stack trace：
  - 網址：沿用 `sanitizeUrl`。
  - 任意位置的家目錄路徑：使用者名稱換成 `***`。
  - 卡池記錄檔名裡的 uid：套用 `sanitizeUid`。

  呼叫端照常傳 `(message, e, st)` 給 `Logger`。Rust log 原本在 `main.dart` 另外呼叫 `sanitizeLogMessage`，現在一併由 `LogService` 處理。
- **已知限制**：例外訊息若夾帶檔案內容片段（例如 `jsonDecode` 的 `FormatException`），統一遮罩擋不住。訊息裡自己組的 uid 仍然要經過 `sanitizeUid`。
- **鳴潮**：同樣改。

**鳴潮的提交方式（使用者 2026-11-22 決定）**：上面四項鳴潮修正都放在鳴潮分支 `fix/cloud-sync-follow-ups`，做完後開 PR，不直接進 master。

## 三、目標／非目標／反目標

**目標**
- 照搬鳴潮第 42～45 節的修正，量到的停頓與鳴潮修正後同等級（第一節的表）。
- 先量原神修正前的數字，修完再量一次，附錄列前後對照。
- 原神獨有的路徑若量到明顯停頓（見第五節），一併處理或回報。

**非目標**
- 不重做設定頁成按需建構的清單（鳴潮第 45 節「沒做」的理由同樣適用）。
- 不改 Drive 下載成先比 `md5Checksum`（鳴潮也沒做）。
- 不做頁面統計快取（鳴潮實測轉向時成本在排版，不在統計）。
- 不量「新增大量記錄」的情況（需要實際抽卡，鳴潮也沒量）。

**反目標**（做到了也算失敗）
- 雲端同步、匯入、匯出、轉換資料語言的結果改變：資料遺失、合併結果不同、該上傳卻沒上傳、`byUid` 該更新卻沒更新。
- 電腦版行為改變：Windows 的同步、匯入匯出、讀網頁快取任何一個流程壞掉。
- 背景 isolate 裡的錯誤沒有記到 App log（背景 isolate 的 `Logger` 不會寫進 App log）。
- 進度對話框在正常流程中被誤關（鳴潮 `c0f4217` 修的就是這個）。
- 子專案 8、9 的成果退步。

## 四、原神與鳴潮的差異，以及各自的做法

已逐檔比對原神現況與鳴潮改版前（`4a0a9db~1`，比對時忽略 CRLF）：

- **雲端同步**（`cloud_sync_service.dart`、`cloud_sync_remote.dart`、`state/cloud_sync.dart`）、**匯出匯入**（`accounts_export.dart`、`accounts_import.dart`）：只差套件名稱、`playerId`→`uid`、卡池代碼欄位（`t.key`→`t.gachaType`）與註解用字。鳴潮的改法直接套用，術語換成原神的。
- **`gacha_storage.dart`**：原神檔名是 `<uid>.json`、`<uid>.url.json`（鳴潮是 `.records.json`、`.cred.json`），存的是網址不是憑證，載入失敗會 rethrow（鳴潮跳過舊檔）。這些都維持原神現狀；只把 `save` 的 `jsonEncode(data.toJson())` 改成在背景 isolate 編碼，寫法照鳴潮。
- **「匯出改傳記錄檔路徑、背景自己讀檔」**：背景要用原神的檔名規則（`<uid>.json`）組路徑。`GachaStorage` 的路徑方法 `_dataFile` 是私有的，照鳴潮（公開成 `recordsFile`）把它公開，不要另寫一套組路徑的邏輯。
- **`BannerStorage.sameContentAs`**：鳴潮比對 `playerId`、`languageCode`、`lastUpdated`、各卡池記錄。原神沒有帳號級語言欄位，記錄以 `id` 去重、每筆有 `lang`。改寫成比對 `uid`、`lastUpdated`、各卡池記錄逐筆相等（以原神 `GachaRecord` 的相等判斷為準；沒有的話比對 `toStorageJson` 的內容）。測試照鳴潮 `banner_storage_test` 的案例改寫。
- **`gacha_repository.dart`**：鳴潮改的兩處在原神都有同樣的位置：合併匯入／同步（原神約第 1470 行，`localBefore.mergeWith(incoming)` 後 `storage.save`）與 `unifyDataLanguage`（約第 1600 行，`converter.convert` 後 `storage.save`）。原神的合併後還有「補抓 HoYoWiki 物品」的流程（`cloud_sync.dart` 約第 341 行），條件是 `mergeResult.addedRecords > 0`，跟內容是否相同無關，跳過寫檔不影響它：有新增記錄時內容一定不同、照常寫檔並補抓；內容不同但新增 0 筆（例如只有 `lastUpdated` 較新、或回填空的 `lang`）時照常寫檔、不補抓。
- **進度對話框**：原神多了 `FetchingHoYoWiki`、`ConvertingDataLanguage` 兩個階段，對話框也用在轉換資料語言。鳴潮的「第一次建構時進度已是 null 就關」照搬；原神若有類似鳴潮 `android_log_wait_test` 的流程（取消更新後推設定頁），同樣要用測試鎖住不誤關。
- **語言對照表**：原神 `LangCatalogStorage.load` 解析 `items` 成 `(name, kind)`，鳴潮是 `LangCatalog.fromJson`。把原神現有的解析整段放進背景 isolate 的 top-level 函式，錯誤原樣拋回，`load` 現有的 warning 與回傳 null 行為不變。
- **設定頁**：原神的 `_LocaleDropdown`（約第 215 行，`DropdownButtonFormField`）與 `_DataLanguageSection`（約第 1443 行）都用 `isExpanded: true`，套用 `_onlySelectedLabel`。
- **等待擷取（鳴潮 `81d3dfa` 的輪詢部分）**：鳴潮是每秒讀 Client.log 增量並在主 isolate 解碼。原神電腦版是讀遊戲網頁快取 `data_2`，`WebCacheUrlWatch` 已經在背景 isolate 掃描（`_scanInBackground`），不需要改。Android 是 `logcat_url_watch.dart`，每次輪詢在主 isolate 做 `utf8.decode` 與網址比對，量了才知道會不會卡（第五節）。
- **測試等待工具**：原神 `test/helpers/wait_until.dart` 已有 `waitUntil`（以時間為上限，每輪等 1 ms），沒有 `pumpUntil`。照搬鳴潮的 `pumpUntil`；`waitUntil` 保留原神寫法（行為等價）。`GachaRepository.waitForBootstrap()` 原神已經有（約第 155 行）。子專案 2 留下的待辦「`gacha_repository_test.dart` 沒等 bootstrap」在這裡處理：這個檔有 31 處 `Future.delayed(50ms)`，其中用來等帳號從磁碟載入的改成 `waitForBootstrap()`。**範圍只到這個檔**（**我的判斷**）：其他約 25 個測試檔還有約 70 處固定延遲，鳴潮也沒有全部清掉（筆記第 43 節「部分純 state 測試仍有 delay(50ms)」），不在這次範圍。
- **同步時不再順帶轉換資料語言**（**我的判斷**，照鳴潮）：原神現在每輪同步都會 `mergeWith` → `_convertAccountToDataLanguage` → `save`，即使雲端與本機相同。照搬 `f4d8555`（指紋相同跳過合併）、`52cb8c8`（內容相同的帳號不送進合併）與「內容相同不寫檔」之後，雲端與本機相同的帳號不會再被順帶轉換。改了資料語言但沒按「統一資料語言」的使用者，舊語言的記錄會維持原樣，直到下次更新記錄（更新時仍會轉換整個帳號）或手動統一。這和鳴潮現在的行為一致；資料語言的轉換本來就有明確的入口（設定頁的統一按鈕、更新記錄），同步順帶轉換是副作用，不是承諾的行為。合併結果本身不變。加測試鎖住：雲端與本機相同時，同步不寫檔、不轉換。
- **背景 isolate 的寫法**（鳴潮第 42 節的坑，照做）：送進 `Isolate.run` 的閉包寫在 top-level 函式裡、只抓參數；背景 isolate 的 log 不會進 App log，要記錄的錯誤丟回主 isolate 再記；例外原樣傳回，既有的 `on FormatException` 等分支不改。

## 五、量測（先量再修，使用者 2026-11-21 選 A）

**工具**：先照搬 `tool/measure_ui_stalls.py`（`PKG = 'tw.reh.genshin.gacha'`），作為第一個 commit。用法、坑都照鳴潮第 43～45 節：
- App 要以 `--ez enable-dart-profiling true` 啟動，**不要**加 `start-paused`（背景 isolate 也會停住，量到假的結果）。
- 以 CPU 取樣串成連續忙碌時段為準，不只看時間軸。
- 每次 `input` 前確認前景是本 App；開選單這類步驟先手動操作、截圖確認座標。
- 手機和模擬器同時連著時先設 `ANDROID_SERIAL`。

**建置**：profile 版，要帶 `--dart-define-from-file=secrets/cloud_sync_defines.json`，否則雲端同步整個停用、量不到第一個情境。

**情境**（修正前、修正後各量一次，同一台 ROG Phone 9）：
1. 開 App 的雲端同步：A．同一台裝置重開（雲端與本機相同）；B．先在電腦同步、再開手機（只差目前選中的帳號等設定）。
2. 轉換資料語言（0 筆要轉）。
3. 設定頁匯出、匯入。
4. 轉向、切換帳號。
5. 打開設定頁（開 App 後第一次）。
6. 更新記錄：要使用者在手機上按「更新記錄」並開遊戲進祈願歷史頁，所以這一項用 `dump` 模式。原神的更新流程多了抓 HoYoWiki 與轉換資料語言兩個階段，Android 等網址走 logcat，這幾段若有停頓要特別看。

**原神獨有、要特別看的地方**：logcat 輪詢（情境 6）、HoYoWiki 索引寫檔與補圖（情境 1 的合併後補抓、情境 6）、物品類型對照（情境 2、6）。量到超過約 16 ms 的停頓時：修法明確、且屬於同一類（把 JSON 編碼或解析移到背景、沒變就不寫）就一併修；需要改架構或偏離鳴潮的，停下來回報使用者。

**手機操作規則**：
- 要使用者明講「接好了／可以測」才動手機，每次量測各自取得同意。
- 量之前記下 `user-rotation`、無障礙服務、目前安裝的版本、雲端同步是否已連結。手機上的原神 App 若沒連結雲端同步，請使用者在手機上連結（要登入 Google 帳號），不代為操作登入。
- 量測用朋友帳號（800…）；情境 1 的 B 需要在電腦上同步一次，電腦版平常是 801… 帳號且已連結雲端，測完切回 801…。
- 情境 1 的 B 會讓手機與電腦用同一份雲端檔。量之前先確認兩邊連的是同一個 Google 帳號、帳號清單相同（都有 800… 與 801…）；不同的話第一次同步會把多出的帳號永久合併進電腦的真實資料，這時停下來問使用者，不要先量。
- 測完還原：裝回 debug 版、轉向（`cmd window user-rotation` 隔幾秒再查一次）、帳號；用到 agent-device 時，snapshot helper 要問使用者要不要移除。

## 六、驗收

**自動測試**（`fvm dart format lib/ test/` 無改動、`fvm flutter analyze` 無問題、`fvm flutter test` 全過）
- 照搬鳴潮這些 commit 新增的測試，改寫成原神的資料與 helper；既有斷言不可刪減。
- 原神特有：`sameContentAs` 依原神欄位的案例（`lang` 不同、`lastUpdated` 不同、記錄多一筆都要判為不同）；合併後內容相同時不寫檔、`byUid` 不換物件；有新增記錄時照常寫檔並觸發 HoYoWiki 補抓，內容不同但新增 0 筆時照常寫檔、不補抓；雲端與本機相同時同步不寫檔、不轉換資料語言；進度對話框在 `ConvertingDataLanguage` 流程中不被誤關（取消更新後推設定頁的情境 `android_log_wait_test` 已經有，照鳴潮確認仍通過）。

**電腦版**（CLAUDE.md「共用邏輯改動兩個平台都要顧到」）
- 雲端同步牽涉真實流程，要在 Windows debug 版實際跑一次：開 App 同步、資料變動後的同步、匯出、匯入。Windows debug 版與正式安裝版共用資料夾，而且平常是已連結雲端，測之前先備份 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`，要操作 Windows 視窗時需使用者當次同意。
- 讀網頁快取等網址的流程沒改，只跑既有測試。

**手機**：第五節的情境修正前、修正後各量一次，附錄 B 列前後對照；同時確認同步結果正確（設定頁「上次同步」時間有更新、雲端檔沒有被覆蓋成舊資料）。

**release 版**：這次不改 manifest、Kotlin、R8 設定，不需要 release 實跑；Android release 實跑仍留到 `feat/android` 開 PR 前。

## 七、留給實作者決定

- 鳴潮 commit 的套用順序與拆 commit 的方式：以鳴潮 commit 為單位，依序套用；原神檔名、欄位不同的地方照第四節改寫。
- 量到原神獨有的停頓時，修法屬於第五節「同一類」者自行處理，記在附錄 A。

## 八、產出

- 程式與測試（第二節）、`tool/measure_ui_stalls.py`。
- 本 spec 附錄 A：各鳴潮 commit 在原神的落點與偏離、實作坑。附錄 B：量測結果（修正前後對照）與電腦版驗收。
- 不改 README。

## 附錄 A：各鳴潮 commit 在原神的落點、偏離與實作坑

| 鳴潮 commit | 原神 commit | 偏離與說明 |
|---|---|---|
| `1b7f8e8` | `db101c9` | 只改 `PKG` 與 `bursts` 辨識 App 函式的套件名稱 |
| `2e0a962` | `4d80df3`、`bd6a161` | 共用 `pumpUntil` 加進 `test/helpers/wait_until.dart`，`waitUntil` 保留原神寫法。`game_dir_help_dialog_test`、`share_image_progress_test` 保留自帶 helper：共用的 `pumpUntil` 最後會 `pumpAndSettle`，這兩個測試有一直在跑的動畫，換上去會逾時。`gacha_repository_test` 38 處固定延遲換掉 33 處，剩 5 處是 `update()` 同步設好進度後才 await mock HTTP，改成等進度會太早返回，每處都加了註解 |
| `4a0a9db`、`57eb498` | `679de4a`、`dd67566` | lib 逐字照搬。原神 `cloud_sync_test` 有 5 個測試原本數「上傳次數」，雲端已是最新時不再上傳後改數「下載次數」，斷言沒有刪減 |
| `c80f960`、`e526a20` | `430dcba` | `fetchDriveMedia` 簽名以鳴潮為準（`client, fileId, accessToken`）；照搬鳴潮既有的 `debugSeedAccount` 供測試用；`GachaStorage._dataFile` 公開為 `recordsFile` |
| （追加三） | `90f0d73`、`2e43b88` | 不是鳴潮 commit。`e526a20` 讓同步匯出在背景讀記錄檔後，Windows 上同時進行的存檔、刪除會拋 `PathAccessException`（審查實測重現），改成短暫重試。鳴潮同步修正 |
| `f4d8555` | `aef38b5`、`900cb20` | `sameContentAs` 依原神 `GachaRecord` 的 8 個欄位比對。測試共用的 `CountingStorage` 抽到 `test/helpers/counting_storage.dart`（鳴潮各檔自帶） |
| `52cb8c8` | `6d472de`、`c79c90c` | 比對 key 用 `uid`。相同帳號在原神的轉換資料語言之前就剔除，有測試鎖住。**偏離**（追加四）：別名規則，鳴潮同步修正。原神一個既有測試的本機帳號從 800000002 改成 800000003，因為它剛好和雲端帳號相同，會被正確剔除；斷言不變 |
| `b8a6bf1` | `068e2bd`、`2c4f030` | 鳴潮的 `unify_data_language_test` 對應原神 `gacha_repository_data_language_test`；轉換後內容沒變就不寫檔、不換 `byUid`，hints 照常收集 |
| （追加二） | `d53433e` | 不是鳴潮 commit。`GachaStorage.load` 改在背景解析；新增 top-level `readRecordsFileSync`，背景匯出也改用它，沒有重複的讀檔邏輯。鳴潮同步修正（鳴潮保留自己「損毀檔 → warning＋null」的語意） |
| `ac19cfa`、`c0f4217` | `d408e9f` | 直接套 `c0f4217` 的最終形，`ac19cfa` 每次 build 都檢查的中間版已被取代。另有測試鎖住 `ConvertingDataLanguage` 期間不會被誤關 |
| `81d3dfa` | — | 不適用：原神頁面已經只訂閱需要的欄位，`WebCacheUrlWatch` 本來就在背景掃描 |
| `a5aafcf` | — | 原神已經有（`phone_layout_pages_test.dart`） |
| `60b6f2a` | `3f3cd53` | 背景函式多帶 `lang` 參數，因為原神的 `LangCatalog.fromEntries` 需要它 |
| `19a911d` | `f4a8953`、`b6cfc8c` | `_onlySelectedLabel` 套用到介面語言與資料語言兩個選單；setter 原神本來就先改狀態再存檔，不用改。測試改選「日本語」，因為原神的德文沒有翻譯 |
| （追加） | `64af71a` | 不是鳴潮 commit。結果視窗開著時，雲端合併不再被當成忙碌。鳴潮同步修正 |
| （量測時發現） | `3dbb4eb`、`4aafcca` | 不是鳴潮 commit。Task 13 量到 App 啟動檢查新版本時在主 isolate 解析 GitHub JSON（11～24 ms），屬第五節「同一類」，改在背景解析。第一版把閉包建在 async 函式裡，可能把連線物件一起帶進 isolate，第二個 commit 改成 top-level 函式。鳴潮同步修正 |
| （量測時發現） | `4390843` | 檢查全部 `Isolate.run` 時發現 `GachaStorage.load` 的閉包也建在方法裡，改成 top-level `_readRecordsFileInBackground`。鳴潮同步修正 |
| — | `886d000` | 鳴潮分支整體審查發現的兩個小問題（過時的 dartdoc、`clearAll` 的 log ID），原神也有，一併修正 |

**同步不再順帶轉換資料語言**：照鳴潮的做法，雲端與本機相同時整輪跳過，相同的帳號也不送進合併，所以這些帳號不會被轉換。其餘帳號照原本的流程轉換。

**實作坑**
- 背景 isolate 的 `Logger` 不會寫進 App log。`importAccounts` 在背景解析失敗時，原本那行較詳細的 warning（`app=` 值與 stack trace）會留在背景，主 isolate 只記得到例外訊息。鳴潮也是這樣，全域限制禁止另外新增 log，所以保持一致。
- Windows 的 Dart 開檔不帶 `FILE_SHARE_DELETE`。只要有一個 isolate 開著檔案，另一個 isolate 的 rename 或 delete 就會失敗（追加三）。
- 只在 Windows 才會發生的重試測試，用 `skip: !Platform.isWindows` 跳過；CI 是 Linux，所以只有本機 Windows 會實際跑到。
- 檢查結果不要看 `| tail` 的結束碼：鳴潮分支曾經因此漏看一個 analyze info。

**鳴潮同步修正**：追加、追加二、追加三、追加四、追加五共五項，加上 `886d000` 的對應修正，放在鳴潮 PR 121。

## 附錄 B：量測結果

### 修正前（2026-11-21，ROG Phone 9，profile 版 `bd6a161`）

**量法**：用 `tool/measure_ui_stalls.py` 量。
- 情境 1A、1B：重開 App 後等 15 秒，再用 `dump` 抓回資料。
- 情境 3、6：先清空緩衝區，由人操作，再用 `dump` 抓回資料。
- 其餘情境：用 `record` 量。

下表列出主 isolate 上 ≥ 8 ms 的連續忙碌時段中，與本次範圍相關的幾段，已排除量測工具自己的 VM Service 時段。量測期間手機與電腦連的是同一個 Google 帳號，帳號清單相同（800…、801…）；電腦端用已安裝的 1.7.0 正式版同步一次。

| 情境 | 停頓 | 主因 | 對應任務 |
|---|---|---|---|
| 1A 同裝置重開 | 31.9 ms | 同步上傳時編碼請求內容（`_UnicodeSubsetEncoderSink`，googleapis 上傳） | Task 7 |
| | 31.1 ms | 開 App 讀存檔 `GachaStorage.load` | 範圍外 |
| | 21.3 ms | 同步後的變動檢查：`_exportLocal` → `exportAccounts`＋`syncFingerprint` | Task 4、5 |
| | 20.4 ms | 同步輪匯出本機：`_exportLocal` → `exportAccounts` | Task 5 |
| | 15.1 ms | 同步輪計算指紋 `syncFingerprint` | Task 4 |
| | 14.8 ms | 同步輪解析雲端內容 `importAccounts` | Task 4 |
| | 8.6 ms | 合併後存檔 `_runImport` → `GachaStorage.save` | Task 6 |
| 1B 先在電腦同步 | 47.1 ms | 同步上傳時編碼請求內容（同 1A） | Task 7 |
| | 21.2 ms | 同步後的變動檢查（同 1A） | Task 4、5 |
| | 17.8 ms | 同步輪計算指紋 `syncFingerprint` | Task 4 |
| | 14.6 ms | 同步輪解析雲端內容 `importAccounts` | Task 4 |
| | 13.7 ms | 同步輪匯出本機 `exportAccounts` | Task 5 |
| | 9.6 ms | 合併後存檔 `_runImport` → `GachaStorage.save` | Task 6 |
| 2 轉換資料語言（0 筆要轉） | 25.7 ms | `unifyDataLanguage` → `GachaStorage.save`：沒有東西要轉也重寫存檔 | Task 8 |
| | 22.5 ms | 存檔觸發的同步變動檢查（`exportAccounts`＋`syncFingerprint`） | Task 4、5 |
| 3 匯出 | 13.8 ms | `_DataManagement._export` → `exportAccounts` | Task 8 |
| 3 匯入相同的檔案（新增 0 筆） | 32.3 ms | `_runImport` → `GachaStorage.save`：沒有新增也重寫存檔 | Task 6、8 |
| | 21.9 ms | 存檔觸發的同步變動檢查 | Task 4、5 |
| 4 轉向、切換帳號 | 20.2 ms | 切帳號後版面重建（`OverviewPage.build`、圖例排版） | 範圍外 |
| 5 第一次開設定頁 | 51.0 ms | `_LocaleDropdown.build`、`localeMetadataProvider` | Task 11 |
| 6 更新記錄（新增 0 筆） | 39.5 ms | 更新後的同步變動檢查（`syncFingerprint`＋`exportAccounts`） | Task 4、5 |
| | 16.0 ms | 同步輪解析雲端內容 `importAccounts` | Task 4 |
| | 8.4 ms | 同步下載 `DriveSyncRemote.download` | Task 5 |

**每輪同步**：雲端與本機內容相同時，每一輪仍然整份上傳（log 每輪都是 `upload: updated, 335177 bytes`），一輪約 3.6～4.3 秒。

**原神獨有路徑**：
- **logcat 輪詢**：情境 6 等網址的約 56 秒內，沒有 ≥ 8 ms 的停頓。
- **HoYoWiki**：情境 3 匯入有一段 11.7 ms、情境 6 有一段 25.2 ms 的停頓，堆疊裡出現 `_fetchHoYoWiki`，但 App 函式各只佔 1 筆取樣，大部分是原生或框架的工作，不是 JSON 編碼或寫檔。沒有可以歸到這條路徑、超過 16 ms 的停頓，修正後再對照。
- **物品類型對照**：`itemTypeKeyOf` 只在情境 1A 開 App 首頁計算的 9.1 ms 時段裡出現 1 筆取樣。

**範圍外的發現**（兩個專案寫法相同；量完後使用者決定這次一起修，見第二節「追加」「追加二」，Task 11b、8b）：
- 「更新完成」對話框開著時，資料變動後的同步會被 `cloud import rejected: busy` 擋下，接著每 5 秒（`busyRetry`）重試一次，每次都先整份下載雲端檔（335 KB），直到使用者關閉對話框才同步成功。
- 開 App 讀存檔 `GachaStorage.load` 31 ms。

### 修正後（2026-11-22，ROG Phone 9，profile 版 `c672069`；1A、1B 用 `4390843` 重量）

量法與修正前相同。「修正後最長」只列 App 函式或畫面工作的時段，已排除量測工具自己的 VM Service 時段。

| 情境 | 修正前最長 | 修正後最長 | 說明 |
|---|---|---|---|
| 1A 同裝置重開 | 31.9 ms（上傳編碼）；另有 15～21 ms 多段同步工作、31.1 ms 讀存檔 | 14.8 ms（啟動時建主題） | 同步整輪判定 `already in sync`，合併與上傳都跳過；一輪從 4.2 秒降到 1.7 秒；之後的變動檢查也跳過。讀存檔已在背景 |
| 1B 先在電腦同步 | 47.1 ms（上傳編碼） | 31.4 ms（啟動 0.27 秒時首頁統計卡片排版） | `merge skipped: all 2 remote accounts match`；雲端匯出時間不同所以照常上傳，上傳在背景 |
| 2 轉換資料語言（0 筆） | 25.7 ms 重寫存檔＋22.5 ms 同步檢查 | 23.4 ms（取樣分散：圖片快取用量、寫 log、轉換各 1～2 筆） | 不再寫檔，也不再觸發同步 |
| 3 匯出 | 13.8 ms | 約 10.6 ms | 組 bundle 在背景 |
| 3 匯入相同的檔案 | 32.3 ms 重寫存檔＋21.9 ms 同步檢查 | 27.8 ms（「更新完成」視窗繪製文字）、14.8 ms（合併比對） | 新增 0 筆時不寫檔；之後的變動檢查判定指紋沒變，整輪跳過 |
| 4 轉向、切換帳號 | 20.2 ms | 25.7 ms（轉橫向時綜合頁重建）、20.6 ms（切帳號） | 這次沒有改這部分（「頁面統計快取」是非目標），量測波動範圍內 |
| 5 第一次開設定頁 | 51.0 ms（`_LocaleDropdown`、`localeMetadataProvider`） | 36.5 ms、35.7 ms（量兩次；設定頁本身建構與排版） | 語言選單的成本已消失；設定頁改按需建構是非目標 |
| 6 更新記錄（新增 0 筆） | 39.5 ms（更新後同步檢查） | 16.4 ms（非 App 函式） | logcat 等網址期間沒有停頓。「更新完成」視窗開著時同步照常完成（有變動的 801… 合併、相同的 800… 跳過），不再每 5 秒重下載 |

**量測中發現並一併修正的同類停頓**：App 啟動時檢查新版本（`_githubGet`），在主 isolate 解碼並解析 GitHub 回傳的 JSON，量到 11～24 ms。改在背景解析（`3dbb4eb`、`4aafcca`，閉包寫在 top-level 函式），重量 1A、1B 後這段消失，`release check: up-to-date` 正常。鳴潮同步修正。

**手機目視**：設定頁兩個語言選單在直向、橫向收合時顯示正確，展開後所有選項都看得到。

**同步結果**：有實際跑同步的情境（1A、1B、6），log 都有 `round done` 或 `already in sync`；其餘情境的變動檢查判定指紋沒變而跳過。雲端檔大小維持 335177 bytes，沒有被舊資料覆蓋。

### 電腦版驗收（2026-11-22，Windows debug 版 `4390843`）

測之前備份 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer`；測完記錄檔與備份逐位元組相同，設定檔只有「上次同步時間」不同，沒有殘留 `.tmp`，使用中帳號維持 801…。

- **開 App 同步**：背景下載、`merge skipped: all 2 remote accounts match`、背景上傳（Windows 也走 `putDriveMedia`），一輪 3.7 秒；之後的變動檢查判定指紋沒變而跳過。檢查新版本正常（`release check: up-to-date`）。
- **資料變動後的同步**：把 801… 的別名暫時加一個字元再改回。兩次都在 5 秒後觸發 `trigger=dataChange` 的一輪，本機已有別名所以合併跳過，上傳的檔案分別是 335178、335177 bytes，最後雲端回到原本內容。
- **匯出**：設定頁匯出 2 個帳號、1113 筆記錄，檔案 335177 bytes，與手機匯出相同。
- **匯入**：匯入剛匯出的檔案，新增 0 筆、已存在 1113 筆，記錄檔沒有被重寫，之後的變動檢查跳過。
- **設定頁語言選單**：收合時顯示正確。
