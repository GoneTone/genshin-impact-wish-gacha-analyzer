# Android 原生廣告（子專案 10）— 設計 spec

- 狀態：已完成（2026-11-22）
- 日期：2026-11-22
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 10；順序 8 → 9 → 12 → 10 → 11 → 7 → 13）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-09-android-banner-ads-design.md`（同意流程、SDK 初始化、ID 注入等基礎建設）與 `2026-11-10-android-native-ads-design.md`（原生廣告），移植筆記第 50 節（「十四、廣告（Android）」整節，含「原生廣告」小節）
- 前一個子專案：`2026-11-21-ui-stall-fixes-design.md`（子專案 12）

---

## 一、目的

照鳴潮版的最終狀態，讓原神 Android 版在內容中間穿插 AdMob 原生廣告，讓專案多少有一點收入。底線和鳴潮相同：**不打擾使用者**，沒有強制觀看的廣告，也不追求收入最大化。

鳴潮先做了底部橫幅，加上原生廣告後又拿掉橫幅（2026-11-10）。路線圖已決定原神**不做橫幅，直接做原生廣告**，所以移植的是鳴潮 `master` 目前的廣告程式，不重演橫幅那段。

## 二、範圍

**做法：以鳴潮 `master` 上廣告檔案的最終版本為底**，換套件名、術語，套到原神現有結構上。鳴潮的廣告 commit 夾著橫幅的新增與刪除，逐個重播沒有意義，所以這次不照 commit 搬（和子專案 3、4、8、9 不同）。鳴潮廣告相關 commit 範圍是 `601b11d`～`b74dc9c`（2026-11-09～12），實作時拿來對照「為什麼這樣寫」；之後到現在沒有再動過廣告程式。

**要移植的檔案（鳴潮路徑 → 原神同路徑）**：

| 類別 | 檔案 |
|---|---|
| 套件 | `pubspec.yaml` 加 `google_mobile_ads`（鳴潮 `^9.2.0`；UMP 已包在裡面） |
| 服務 | `lib/services/ads/ads_platform.dart`、`ad_config.dart`、`ad_placement.dart` |
| 狀態 | `lib/state/ads.dart` |
| 元件 | `lib/widgets/ads/native_ad.dart` |
| 頁面 | `lib/pages/app_shell.dart`（啟動時在 Android 呼叫 `adsProvider.start()`）、`banner_page.dart`、`overview_page.dart`、`settings_page.dart`（隱私區塊的「廣告隱私權選項」） |
| 文案 | ARB `settingsAdPrivacyOptions`、`settingsAdPrivacyOptionsHint` |
| Android | `android/app/build.gradle.kts`（從 `dart-defines` 解出 `ADMOB_APP_ID`，只在 release 覆寫 manifest placeholder `admobAppId`，其餘用官方測試 App ID `ca-app-pub-3940256099942544~3347511713`）、`android/app/src/main/AndroidManifest.xml`（`com.google.android.gms.ads.APPLICATION_ID` = `${admobAppId}`）、新增 `android/app/src/release/AndroidManifest.xml`（關掉原生廣告驗證器）、新增 `android/app/proguard-rules.pro`（WorkManager 的 Room 建構子保留規則） |
| 開發設定 | `.run/main_dart_cloud_sync.run.xml` 改名為 `main_dart_cloud_sync_ads.run.xml`，多帶 `--dart-define-from-file=secrets/ads_defines.json` |
| 測試 | `test/helpers/native_ad_fakes.dart`、`test/services/ads/ad_config_test.dart`、`ad_placement_test.dart`、`test/state/ads_test.dart`、`test/widgets/ads/native_ad_test.dart`、`test/pages/app_shell_ads_test.dart`、`banner_page_native_ads_test.dart`、`overview_page_native_ads_test.dart`、`settings_privacy_section_test.dart`（原神沒有這個檔就新建，已有的隱私區塊測試要一起看） |
| 文件 | `docs/privacy-policy.md`（新增，見第五節）、CLAUDE.md（見第八節） |

**不移植**：
- 橫幅相關的一切（`BannerAdSlot`、外殼的橫幅列、有廣告時 SnackBar 改浮動、`ADMOB_BANNER_UNIT_ID`、`pageHasAdContent` 裡只給橫幅用的「設定頁、貢獻者頁一律有內容」）。鳴潮已全部刪除，原神從沒有過。
- **發版 CI 的「Write ads defines from secrets」步驟與 GitHub secrets**：原神目前沒有 Android 發版 CI（只有 `ci.yml`、`release-windows.yml`），留到子專案 7 建 Android 發版流程時一起做。
- **README 提到 Android 版有廣告**：路線圖把 README 分給子專案 13，那時一起寫。（2026-11-22 我曾跟使用者說這次會改 README，寫設計時發現路線圖已分給 13，改回照路線圖。）
- Play Console 的廣告聲明、資料安全表單、`app-ads.txt` 與「開發人員網站」、AdMob 連結商店頁：子專案 7。
- `private/play-store/` 的商店文字：子專案 7。

## 三、目標／非目標／反目標

**目標**：
- Android 版在四個位置顯示原生廣告（見第四節），外觀套 App 色票、仍看得出是廣告。
- 廣告沒顯示時，版面和沒有廣告時完全一樣。
- 需要同意的地區（歐盟／英國、美國部分州）用 UMP 取得同意，設定頁提供「廣告隱私權選項」。
- 開發版、除錯版、沒注入 ID 的建置一律只載入測試廣告。

**非目標**：Windows 版不放廣告、不呼叫廣告 SDK；設定頁、貢獻者頁、側邊選單、對話框、讀取遊戲記錄設定流程不放；不做插頁、獎勵、應用程式開啟廣告；不做跨頁預先載入或背景輪替。

**反目標**（沿用鳴潮）：
- 廣告還沒顯示時列表被切開、多出空白或間距。
- 廣告緊鄰可點的按鈕（搜尋框、篩選列、排序、分頁列、分享按鈕）。
- 廣告出現在沒有內容的畫面或區段。
- 廣告外觀和記錄、統計卡片一模一樣。
- 開發或測試時載入正式廣告。
- Windows 版的任何行為改變。
- 頁面跑版、溢出，或在手機橫向、平板、放大字級時擠壞版面。

## 四、廣告位置與原神的差異

鳴潮有三個位置；原神綜合頁分成「祈願」與「頌願」兩個區段，所以有四個：

| 位置 | 頁面與插入點 | 模板 | `NativeAdPlacement` |
|---|---|---|---|
| 卡池頁列表 | 記錄列表（卡片模式）當頁第 10 筆與第 11 筆之間，是列表裡的一列，不切開列表 | 小型 | `bannerList` |
| 卡池頁中段 | 5★ 時間軸正上方（圓餅卡與時間軸之間）；寬度 ≥1024 的三欄排版放在整列下方 | 中型 | `bannerMid` |
| 綜合頁祈願 | 「祈願」區段「類型分布」下方、「各卡池最高稀有度件數」上方 | 中型 | `overviewGacha`（**原神新增**） |
| 綜合頁頌願 | 「頌願」區段同一個位置 | 中型 | `overviewOdes`（**原神新增**） |

- 卡池頁兩個位置的條件、間距、模板、在沒有 5★ 時照放等細節，全部照鳴潮最終程式與移植筆記第 50 節。頌願的卡池頁也是 `BannerPage`，照樣有這兩個位置。
- **綜合頁每個區段各自判斷（使用者 2026-11-22 選 B）**：區段有資料就放一則，沒有資料（顯示「沒有祈願記錄」／「沒有頌願記錄」空狀態）就不放、也不載入。兩個區段各自載入、各自釋放，互不影響；只有頌願有資料時，只會有頌願那一則。
- 「區段有資料」的判斷沿用 `pageHasAdContent` 的精神（啟動載入中、尚未同步、沒有記錄都算沒有），再依 `GachaCategory` 分祈願與頌願。實作方式留給實作者，但要有測試鎖住「只有祈願／只有頌願／兩者都有／都沒有」四種情況。
- 兩則綜合頁廣告之間隔著祈願區段的「各卡池最高稀有度件數」、5★ 一覽、時間軸、分隔線，以及頌願區段的統計卡。一般手機不會同時看到兩則；驗收時在長螢幕確認，若會同時出現就記錄下來回報，不在這次處理（比照鳴潮第 50 節「長螢幕會同時看到兩則」的處理方式）。

## 五、隱私權政策

新增 `docs/privacy-policy.md`，以鳴潮 `docs/privacy-policy.md`（中英雙語）為底：
- 名稱、套件名稱換成原神的（「祈願卡池分析 for 原神」，套件 `tw.reh.genshin.gacha`）；涵蓋 Android 版與 Windows 版。商店名稱在子專案 7 才定案，到時若改名要回來同步。
- 每一節的事實都要照原神的實作改寫，不能照抄鳴潮：存在裝置上的資料、會連線的對象（HoYoverse 的祈願記錄 API、HoYoWiki 圖片、Google 雲端硬碟同步、AdMob）、Android 版讀取網址的方式（root、無線偵錯、logcat）、Windows 版取得網址的方式（遊戲網頁快取、MITM 等原神實際有的方式）、刪除資料的方式。寫完要逐節對照原神程式確認。
- 「廣告（只限 Android 版）」一節照鳴潮最終版（只有原生廣告、UMP 同意與退出方式、`maxAdContentRating` T）。
- 「兒童」「聯絡方式」照鳴潮，換成原神 repo 的網址。
- 網址：`https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/blob/master/docs/privacy-policy.md`。已填進 AdMob「隱私權與訊息」，`feat/android` 合併到 `master` 前會是 404；那之前原神沒有上 Play，一般使用者看不到同意視窗。

## 六、ID 與建置

- `secrets/ads_defines.json` 已建立（`ADMOB_APP_ID`、`ADMOB_NATIVE_UNIT_ID`，2026-11-22），`/secrets/` 已在 `.gitignore`。不要讀取或印出內容。
- 只有 release 且有注入值時才用正式 ID；其餘一律官方測試 ID（原生 `ca-app-pub-3940256099942544/2247696110`、App `ca-app-pub-3940256099942544~3347511713`）。
- 本機 release 建置要同時帶 `--dart-define-from-file=secrets/cloud_sync_defines.json --dart-define-from-file=secrets/ads_defines.json`。
- AdMob 後台已完成（2026-11-22）：原神 App（未上架）、原生廣告單元、歐洲與美國州級訊息已加入原神並發布。測試裝置是帳戶層級，沿用鳴潮登記的手機。

## 七、驗收

- `fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。
- 測試至少涵蓋（照鳴潮的測試再加原神的部分）：廣告未載入時版面和沒有廣告時相同（列表不切開）；當頁 10 筆以下或表格模式不放卡池頁列表位置；載入後才插入；主題切換重新載入；失敗收起；非 Android 不載入；可用寬度不足 320dp 不載入；綜合頁四種資料情況（第四節）。
- **Windows**：跑一次 debug，確認綜合頁、卡池頁、設定頁和改動前一樣，沒有廣告、沒有多出的間距或設定項目。
- **Android 模擬器 debug（測試廣告）**：四個位置都出現在預期的地方；只有頌願／只有祈願的帳號看綜合頁；直向、橫向、深淺色切換（log 依序 `native disposed` 再 `native loaded`）；翻頁沿用同一則；斷網時不顯示也不留白。
- **Android release（正式 ID）**：照 CLAUDE.md「改到 manifest、Kotlin 或 R8 相關要用 release 實跑」，用和之後 AAB 相同的參數建 release APK 裝到模擬器，確認啟動不閃退（`logcat -b crash` 為空，這次會新增 R8 規則）、Manifest 的 App ID 與 `libapp.so` 的單元 ID 是正式值、驗證器不彈出、廣告正常載入或收起。原神未上架，正式 ID 拿不到正式廣告是正常的。
- 手機實機只在使用者同意時做。

## 八、文件

- CLAUDE.md：照鳴潮 CLAUDE.md 有提到廣告的規則補上（實作時比對鳴潮 CLAUDE.md／AGENTS.md）。
- 本 spec 附錄記錄驗收結果；原神沒有移植筆記，鳴潮第 50 節有、原神也踩到或刻意不同的地方記在附錄。

## 九、留給實作者決定

- 綜合頁兩個區段「有資料」的判斷放在哪裡（擴充 `pageHasAdContent` 或在綜合頁計算），只要語意符合第四節。
- ARB 只加到已有實際翻譯的語系檔，空殼語系留給 Crowdin 與子專案 11；從 `app_zh.arb` 起手。
- 隱私權政策英文版的措辭。

## 附錄：驗收結果

（2026-11-22）

**實作**：`e649c76`～`fb5a50c`（Task 1～7、Task 6 修正一輪、整體審查修正波）。每個任務都經過審查；整體審查提出 2 個 Important（隱私權政策補「攔截期間 HTTPS 在本機解密」、四份 README 的執行設定改名與廣告 ID 開發說明）與 5 個 Minor，全部修正。

**模擬器 debug（wuwa_api37，Android 17，測試廣告）**
- 四個位置都在預期的地方，AdMob native ad validator 顯示「No implementation issues found」。
- 800…（沒有頌願記錄）：只載入 `overviewGacha`，頌願區段顯示空狀態、沒有廣告。切到 801…（有頌願）：只多載入 `overviewOdes`，祈願那則沒有重新載入；切回 800…：只有 `native disposed placement=overviewOdes`。
- 祈願廣告捲出按需建構範圍再捲回來：沒有 `AdWidget is already in the Widget tree`，也沒有紅框。
- 淺色切深色：log 依序 `native disposed` 再 `native loaded`，深色樣式正確。
- 卡池頁（武器活動）：`bannerMid` 在 5★ 時間軸正上方；`bannerList` 在第 10、11 筆之間，和列表在同一個外框，上下有分隔線。
- 驗收時誤觸驗證器或測試廣告開啟了 Chrome，按返回即回到 App（測試廣告，無影響）。

**模擬器 release（正式 ID，與 AAB 相同的兩個 defines 檔）**
- `build/app/outputs/mapping/release/seeds.txt` 有 `WorkDatabase_Impl()`；release merged manifest 有 `NATIVE_AD_DEBUGGER_ENABLED=false`，App ID 是正式值，SDK 帶入 `AD_ID` 權限（子專案 7 填資料安全表單時要用）。
- `libapp.so` 含正式原生單元 ID、不含測試單元 ID。
- 覆蓋安裝後啟動正常，`logcat -b crash` 為空；正式 ID 在模擬器拿到測試影片廣告（模擬器自動算測試裝置），驗證器沒有彈出。

**Windows（debug，801… 帳號，測前備份資料夾）**
- `flutter build windows` 成功，新增的 `google_mobile_ads`、`webview_flutter*` 沒有造成外掛註冊錯誤。
- 綜合頁、武器（空卡池）、常駐（三欄＋表格）、頌願活動、設定頁都沒有廣告、沒有多出的間距；設定頁「隱私」區塊只有遮蔽 UID 開關。
- 這次啟動的 App log 沒有任何 `[ads]`，也沒有 warning／severe。

**沒有實測的部分**：翻頁到不足 10 筆的最後一頁、斷網、手機橫向、長螢幕兩則同框（單元測試涵蓋前三項）；歐盟同意表單與「廣告隱私權選項」的實際表單（模擬器不在 EEA）；手機實機。

**和鳴潮第 50 節刻意不同的地方**
- 綜合頁分成祈願、頌願兩個位置（`overviewGacha`、`overviewOdes`），各自依區段是否有記錄載入（使用者 2026-11-22 選 B）。
- 沒有橫幅、沒有發版 CI 的 ads defines 步驟（子專案 7）。
- 錯誤 log 照兩個 repo 2026-11-22 統一後的寫法（`'msg', e, st`）。

**寫隱私權政策時發現的移植缺漏（使用者 2026-11-22 決定要補，另外處理）**
- 原神沒有鳴潮的 `backup_rules`／`data_extraction_rules`，加密的配對金鑰會被 Android 系統備份（還原後無法使用）。
- Windows 解除安裝不會移除根憑證與 `ca` 資料夾（鳴潮會）；政策已照實寫並附手動移除步驟。
- 原神還沒有 Google Play App 內更新，隱私權政策等子專案 7 再補。
