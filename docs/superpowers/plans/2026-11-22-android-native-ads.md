# Android 原生廣告（子專案 10）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把鳴潮 `master` 上的原生廣告（UMP 同意、SDK 初始化、ID 注入、原生模板、卡池頁兩個位置、綜合頁）移植到原神 Android 版，綜合頁依祈願／頌願兩個區段各放一則，並新增隱私權政策。

**Architecture:** 以鳴潮 `master` 上廣告檔案的最終版本為底，換套件名與術語後放進原神同路徑（不逐 commit 重播，spec 第二節）。廣告在頁面層級以 `nativeAdProvider`（autoDispose family）監聽，載入完成才插入版面；Windows 完全不碰 SDK。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、`google_mobile_ads` ^9.2.0（含 UMP）、Android Gradle Kotlin DSL、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-22-android-native-ads-design.md`（必讀；第四節是位置與原神差異，第七節是驗收）。鳴潮設計：`../wuthering-waves-convene-gacha-analyzer/docs/superpowers/specs/2026-11-10-android-native-ads-design.md`；鳴潮移植筆記「十四、廣告（Android）」第 50 節（`docs/Android移植筆記.md` 第 740～857 行）。

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」），一律以 `master` 目前的檔案為底：`git -C ../wuthering-waves-convene-gacha-analyzer show master:<路徑>`。想知道某段為什麼這樣寫，看 `601b11d`～`b74dc9c` 之間的 commit。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；卡池代碼 `cardPoolType`（路由 `/banner/<cardPoolType>`）→ 原神的 `gachaType`（路由 `/banner/<gachaType>`，例如 `301`、`1000`）；測試資料的 `playerId` → `uid`；「紀錄」→「記錄」；「喚取」→「祈願」。
- 鳴潮的改法在原神行不通、或需要改變原神特有行為時，回報 NEEDS_CONTEXT，不要自行改寫（使用者原則：偏離姐妹專案前先問）。spec 已決定的偏離照 spec 做。

## Global Constraints

- 只新增 `google_mobile_ads: ^9.2.0` 一個依賴。不改 `rust/`、`rust_builder/`。
- **Windows 行為不可改變**：非 Android 不呼叫任何廣告 SDK、不監聽 `nativeAdProvider`、版面與設定頁和改動前完全相同。
- 正式 ID 只在 release 且有注入值時使用；其餘一律官方測試 ID：原生單元 `ca-app-pub-3940256099942544/2247696110`、App `ca-app-pub-3940256099942544~3347511713`。`secrets/` 不可讀取或印出。
- log 用 `Logger('ads')`、英文、帶 `placement=<name>` 與錯誤碼。例外照原神 2026-11-22 統一的寫法傳給 Logger：`_log.severe('native load threw placement=$placement', e, st)`，**訊息裡不要再串 `: $e`**（鳴潮 `ads.dart`、`native_ad.dart` 的 `': $e'` 四處都改掉）。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；註解中文全形標點。
- ARB 從 `app_zh.arb` 起手，只加到已有實際翻譯的語系檔（目前行數遠多於 11 行的：`zh`、`zh_Hans`、`en`、`es`、`fr`、`ja`、`pt_BR`、`th`，以及其他同樣有實際翻譯的檔），不碰只有 11 行的空殼；改完跑 `fvm flutter gen-l10n`。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（輸出必須含 `All tests passed!`，看實際的最後一行）。commit 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（不可跳過 GPG 簽章）。分支 `feat/android`，不開新分支、不 push。
- 模擬器、手機、Windows 視窗的操作只在 Task 8，由主控執行；手機要使用者明講「可以測」才動。

## Review Focus

1. **綜合頁切換帳號**：從有頌願記錄的帳號切到沒有頌願記錄的帳號，頌願那則要從畫面移除並釋放，祈願那則不重新載入 → Task 6 測試 `切到沒有頌願記錄的帳號：頌願廣告移除並釋放，祈願廣告不重載`。
2. **Windows 綜合頁與卡池頁**：非 Android 即使 `canRequestAds` 被設成 true，也絕不呼叫載入器 → Task 5、Task 6 各一個 `非 Android 不載入` 測試（載入器呼叫次數為 0）。
3. **頌願卡池頁**：`/banner/1000` 有記錄時兩個位置照放，沒有記錄時不放 → Task 4 的 `pageHasAdContent` 測試與 Task 5 的頌願卡池測試。
4. **深淺色切換時綜合頁兩則都重載**：兩則都以新主題各載入一次，舊的離開畫面後才釋放 → Task 6 測試。
5. **只有頌願有記錄**：祈願區段顯示空狀態且沒有廣告、頌願區段有一則 → Task 6 的四種資料情況測試。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `pubspec.yaml`、`pubspec.lock` | 加 `google_mobile_ads` | 1 |
| `android/app/build.gradle.kts` | 從 `dart-defines` 解出 `ADMOB_APP_ID`，release 覆寫 placeholder `admobAppId` | 1 |
| `android/app/src/main/AndroidManifest.xml` | `com.google.android.gms.ads.APPLICATION_ID` = `${admobAppId}` | 1 |
| `android/app/src/release/AndroidManifest.xml`（新） | 正式版關閉原生廣告驗證器 | 1 |
| `android/app/proguard-rules.pro`（新） | `-keep class * extends androidx.room.RoomDatabase { <init>(); }` | 1 |
| `.run/main_dart_cloud_sync_ads.run.xml`（由 `main_dart_cloud_sync.run.xml` 改名） | 開發時帶兩個 defines 檔 | 1 |
| `lib/services/ads/ad_config.dart`（新） | 原生單元 ID 解析 | 1 |
| `lib/services/ads/ads_platform.dart`（新） | UMP／MobileAds 平台包裝 | 2 |
| `lib/state/ads.dart`（新） | 同意流程與 SDK 初始化狀態 | 2 |
| `lib/pages/app_shell.dart` | Android 啟動時 `adsProvider.start()` | 2 |
| `lib/pages/settings_page.dart`、ARB | 隱私區塊的「廣告隱私權選項」 | 3 |
| `lib/widgets/ads/native_ad.dart`（新） | 模板樣式、載入器、`nativeAdProvider`、`NativeAdBlock` | 4 |
| `lib/services/ads/ad_placement.dart`（新） | 頁面／綜合頁區段是否有內容 | 4 |
| `lib/widgets/data/sortable_table.dart` | `kMidListAdAfter = 10` 與列表中的廣告列 | 5 |
| `lib/pages/banner_page.dart` | 卡池頁兩個位置 | 5 |
| `lib/pages/overview_page.dart` | 綜合頁祈願、頌願各一則 | 6 |
| `docs/privacy-policy.md`（新）、`CLAUDE.md` | 隱私權政策、規則 | 7 |
| spec 附錄 | 驗收結果 | 8 |

---

### Task 1: 套件、Android 建置設定與單元 ID

**Files:**
- Modify: `pubspec.yaml`、`android/app/build.gradle.kts`、`android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/release/AndroidManifest.xml`、`android/app/proguard-rules.pro`、`lib/services/ads/ad_config.dart`
- Rename: `.run/main_dart_cloud_sync.run.xml` → `.run/main_dart_cloud_sync_ads.run.xml`（名稱與 `additionalArgs` 照鳴潮同名檔）
- Test: `test/services/ads/ad_config_test.dart`

**Interfaces:**
- Produces: `const String kTestAdmobNativeUnitId`；`String resolveNativeUnitId({required bool release, required String injected})`；`String get admobNativeUnitId`。

- [ ] **Step 1: 照搬鳴潮 `test/services/ads/ad_config_test.dart`**，斷言 `resolveNativeUnitId(release: true, injected: '')`、`(release: false, injected: 'x')` 都回 `kTestAdmobNativeUnitId`，`(release: true, injected: 'x')` 回 `'x'`。
- [ ] **Step 2: 跑 `fvm flutter test test/services/ads/ad_config_test.dart`**，預期 FAIL（檔案不存在）。
- [ ] **Step 3: 實作**：`fvm flutter pub add google_mobile_ads:^9.2.0`；`ad_config.dart`、`build.gradle.kts` 的注入段、兩個 Manifest、`proguard-rules.pro` 照鳴潮 `master` 同名檔（註解保留，`1.9.0-rc.10` 這類鳴潮版號改寫成「鳴潮 1.9.0-rc.10」）；`.run` 改名並補參數。
- [ ] **Step 4: 驗證**：測試 PASS；`fvm flutter build apk --debug` 成功，`build/app/intermediates/merged_manifest/debug/**/AndroidManifest.xml` 的 `com.google.android.gms.ads.APPLICATION_ID` 是測試 App ID、沒有 `NATIVE_AD_DEBUGGER_ENABLED`。
- [ ] **Step 5: Commit** `build(ads): add the mobile ads SDK and inject the AdMob IDs at build time`

### Task 2: 同意流程與 SDK 初始化

**Files:**
- Create: `lib/services/ads/ads_platform.dart`、`lib/state/ads.dart`
- Modify: `lib/pages/app_shell.dart`（`initState` 的 post-frame 裡，`isAndroidProvider` 為真才 `unawaited(ref.read(adsProvider.notifier).start())`，照鳴潮 `app_shell.dart` 第 108～118 行）
- Test: `test/state/ads_test.dart`、`test/pages/app_shell_ads_test.dart`

**Interfaces:**
- Produces: `class AdsConsentException { final String code; final String message; }`；`class AdsPlatform`（`requestConsentUpdate()`、`loadAndShowConsentFormIfRequired()`、`canRequestAds()`、`isPrivacyOptionsRequired()`、`showPrivacyOptionsForm()`、`initializeSdk()`）；`adsPlatformProvider`；`class AdsState { final bool canRequestAds; final bool privacyOptionsRequired; }`；`adsProvider`（`AdsController.start()`、`AdsController.showPrivacyOptions()`）。

- [ ] **Step 1: 照搬鳴潮 `test/state/ads_test.dart` 全部案例**，以及 `test/pages/app_shell_ads_test.dart` 的 `starts the ads flow on Android only`、`never starts the ads flow off Android` 兩個。該檔另外三個（`phone portrait has only the status bar at the bottom`、`tablet keeps the status bar above the keyboard`、`snack bars keep the default behavior`）是橫幅拿掉後留下的外殼版面測試，原神沒有橫幅，**不搬**。外殼的測試骨架改用原神既有外殼測試的寫法（找 `test/pages/` 裡建 `AppShell` 的 helper）。
- [ ] **Step 2: 跑這兩個測試檔**，預期 FAIL。
- [ ] **Step 3: 實作**：兩個檔照鳴潮 `master`；log 依 Global Constraints 改成不串 `: $e`（`'ads consent failed'`、`'ads start failed'`、`'privacy options failed'`）。`maxAdContentRating` T 與 `_sdkInit ??=` 的寫法照搬。
- [ ] **Step 4: 驗證**：兩個測試檔 PASS，全套 `All tests passed!`。
- [ ] **Step 5: Commit** `feat(ads): run the ad consent flow and initialize the SDK on Android`

### Task 3: 設定頁「廣告隱私權選項」

**Files:**
- Modify: `lib/pages/settings_page.dart`（原神 `_PrivacySection`，約第 1170 行）、ARB
- Test: `test/pages/settings_privacy_section_test.dart`（原神已有，加案例，既有斷言不可刪）

**Interfaces:**
- Consumes: `adsProvider`（`privacyOptionsRequired`、`showPrivacyOptions()`）。
- Produces: ARB `settingsAdPrivacyOptions`（繁中「廣告隱私權選項」）、`settingsAdPrivacyOptionsHint`（繁中「變更是否同意顯示個人化廣告。」），其他語系照鳴潮同 key 的翻譯。

- [ ] **Step 1: 把鳴潮 `settings_privacy_section_test.dart` 中與廣告有關的案例搬進原神同名檔**（需要時顯示、不需要時不顯示、點了呼叫 `showPrivacyOptions`、非 Android 不顯示，以鳴潮檔實際案例為準）。
- [ ] **Step 2: 跑該測試檔**，預期新案例 FAIL。
- [ ] **Step 3: 實作**：照鳴潮 `settings_page.dart` 第 1405～1435 行附近的寫法加進 `_PrivacySection`；ARB 依 Global Constraints；`fvm flutter gen-l10n`。
- [ ] **Step 4: 驗證**：該測試檔 PASS，全套 `All tests passed!`。
- [ ] **Step 5: Commit** `feat(ads): add the ad privacy options entry to settings`

### Task 4: 原生廣告元件與「有內容」判斷

**Files:**
- Create: `lib/widgets/ads/native_ad.dart`、`lib/services/ads/ad_placement.dart`、`test/helpers/native_ad_fakes.dart`
- Test: `test/widgets/ads/native_ad_test.dart`、`test/services/ads/ad_placement_test.dart`

**Interfaces:**
- Consumes: `admobNativeUnitId`（Task 1）。
- Produces:
  - `const double kNativeSmallHeight = 100`、`kNativeMediumHeight = 355`、`kNativeMinWidth = 320`
  - `enum NativeAdPlacement { bannerList, bannerMid, overviewGacha, overviewOdes }`，`TemplateType get template`（`bannerList` 小型，其餘中型）。鳴潮的 `overview` 拆成 `overviewGacha`、`overviewOdes`；log 的 `placement=` 用 `name`。
  - `typedef LoadedNative`、`typedef NativeAdLoader`、`typedef NativeAdKey = ({NativeAdPlacement placement, String scope, Brightness brightness})`、`NativeTemplateStyle nativeTemplateStyleFor(TemplateType, Brightness)`、`nativeAdLoaderProvider`、`nativeAdProvider`、`class NativeAdBlock({required LoadedNative ad, required NativeAdPlacement placement})`——全部照鳴潮 `master`。
  - `bool pageHasAdContent({required String path, required GachaState gacha})`：照鳴潮，`/` 為任一卡池有記錄，`/banner/<gachaType>` 為該卡池有記錄。
  - `bool overviewSectionHasAdContent({required GachaCategory category, required GachaState gacha})`（**原神新增**）：啟動載入中、`activeData == null` 為 false；否則 `gachaTypes` 中 `category` 相符的卡池任一有記錄為 true。篩選條件要和 `buildOverviewSections` 分區用的完全一樣（`lib/services/overview_sections.dart`）。
  - `test/helpers/native_ad_fakes.dart` 照鳴潮（假載入器、計數、釋放紀錄），供 Task 5、6 使用。

- [ ] **Step 1: 照搬鳴潮 `native_ad_test.dart`、`ad_placement_test.dart`**；`ad_placement_test` 改用原神 `GachaState`／`BannerStorage`／`GachaRecord` 建資料，並加：
  - `pageHasAdContent` 對 `/banner/1000`（頌願）有記錄為 true、無記錄為 false。
  - `overviewSectionHasAdContent`：只有 `301` 有記錄時 gacha=true／odes=false；只有 `1000` 有記錄時 gacha=false／odes=true；都有時兩者 true；都沒有、啟動載入中、沒有作用中帳號時兩者 false。
- [ ] **Step 2: 跑這兩個測試檔**，預期 FAIL。
- [ ] **Step 3: 實作**，log 依 Global Constraints。
- [ ] **Step 4: 驗證**：兩個測試檔 PASS，全套 `All tests passed!`。
- [ ] **Step 5: Commit** `feat(ads): load native ads with templates styled from the app theme`

### Task 5: 卡池頁兩個位置

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart`（`const kMidListAdAfter = 10` 與卡片列表第 10、11 筆之間的廣告列，照鳴潮同檔）、`lib/pages/banner_page.dart`（`_requestedAds`、`didUpdateWidget` 清空、`_nativeAd(...)`、`bannerMid` 放在圓餅卡與 5★ 時間軸之間、≥1024 三欄時放整列下方、沒有 5★ 時下方留 `AppSpacing.xl` 再接「記錄列表」標題，照鳴潮 `master` 同檔）
- Test: `test/pages/banner_page_native_ads_test.dart`

**Interfaces:**
- Consumes: Task 4 全部；`adsProvider`、`isAndroidProvider`、`WidthLayoutBuilder`、`recordListUsesCards`（原神已有）。
- Produces: `const kMidListAdAfter = 10`（`sortable_table.dart`）。

- [ ] **Step 1: 照搬鳴潮 `banner_page_native_ads_test.dart` 全部案例**（卡池代碼改原神，例如 `301`），並加：
  - `頌願卡池頁（1000）有記錄時兩個位置照放`。
  - `非 Android 不載入`：`isAndroidProvider` false、`canRequestAds` true、有記錄 → 載入器呼叫 0 次，版面與沒有廣告時相同。
- [ ] **Step 2: 跑該測試檔**，預期 FAIL。
- [ ] **Step 3: 實作**。
- [ ] **Step 4: 驗證**：該測試檔 PASS；既有 `banner_page`／`sortable_table` 測試不改斷言仍 PASS；全套 `All tests passed!`。
- [ ] **Step 5: Commit** `feat(ads): show native ads in the banner page list and above the timeline`

### Task 6: 綜合頁祈願、頌願各一則

**Files:**
- Modify: `lib/pages/overview_page.dart`
- Test: `test/pages/overview_page_native_ads_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `overviewSectionHasAdContent`、`NativeAdPlacement.overviewGacha`／`overviewOdes`、`nativeAdProvider`、`NativeAdBlock`。

做法：照鳴潮 `overview_page.dart` 第 50～125 行的寫法（頁面層級計算 `adsAllowed`、`WidthLayoutBuilder` + `Consumer` 監聽），但算兩次：
- `gachaAdsAllowed` / `odesAdsAllowed` = `isAndroid && canRequestAds && overviewSectionHasAdContent(category: …)`；`fits` 共用。
- 兩則的 key：`(placement: overviewGacha 或 overviewOdes, scope: 'overview', brightness: …)`。
- `_OverviewSection` 多一個可為 null 的廣告參數，插在「類型分布」（`rarityCard`／`itemTypeCard` 那一列）之後、「各卡池主稀有度件數」`ChartCard` 之前，前後間距照鳴潮（`AppSpacing.m`）。null 時版面與現在完全相同。

- [ ] **Step 1: 照搬鳴潮 `overview_page_native_ads_test.dart` 全部案例**（改用祈願資料），並加：
  - 四種資料情況：只有祈願（只載入 `overviewGacha`，頌願區段空狀態下沒有廣告）、只有頌願（只載入 `overviewOdes`）、兩者都有（兩則各載入一次，各自在自己區段的「類型分布」下方）、都沒有（0 次）。
  - `切到沒有頌願記錄的帳號：頌願廣告移除並釋放，祈願廣告不重載`。
  - `深色切淺色：兩則都以 light 各再載入一次，舊的離開畫面後才釋放`。
  - `非 Android 不載入`（同 Task 5）。
- [ ] **Step 2: 跑該測試檔**，預期 FAIL。
- [ ] **Step 3: 實作**。
- [ ] **Step 4: 驗證**：該測試檔 PASS；既有綜合頁測試不改斷言仍 PASS；全套 `All tests passed!`。
- [ ] **Step 5: Commit** `feat(ads): show a native ad in each overview section that has records`

### Task 7: 隱私權政策與 CLAUDE.md

**Files:**
- Create: `docs/privacy-policy.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: 寫 `docs/privacy-policy.md`**：結構照鳴潮 `master:docs/privacy-policy.md`（繁中＋英文、相同章節）。名稱「祈願卡池分析 for 原神」、套件 `tw.reh.genshin.gacha`、原神 repo 網址；每一節依原神實作改寫並逐節對照程式確認（spec 第五節）：存在裝置上的資料（`%APPDATA%`／App 資料夾裡的記錄檔、設定、log、HoYoWiki 圖片快取）、會連線的對象（HoYoverse 祈願記錄 API、HoYoWiki、GitHub 版本檢查、Google 雲端硬碟同步、Google Play 更新檢查、AdMob）、Android 讀取網址的方式（root、無線偵錯、logcat，照 `lib/services/android/` 實際做法）、Windows 取得網址的方式（遊戲網頁快取、MITM，照 `lib/services/` 與 `rust/` 實際做法）、廣告（照鳴潮最終版）、刪除資料、兒童、聯絡方式。「最後更新」填實作當天。
- [ ] **Step 2: CLAUDE.md**：比對鳴潮 `master:CLAUDE.md` 與 `master:AGENTS.md` 中提到廣告的規則，原神缺的補上（換術語）；沒有就不改。
- [ ] **Step 3: 驗證**：`grep -n "鳴潮\|Wuthering\|wuwa\|playerId\|喚取" docs/privacy-policy.md` 沒有殘留；文件內每個原神事實都能指到對應程式。
- [ ] **Step 4: Commit** `docs(privacy): add the privacy policy with the Android ads section`

### Task 8: 驗收（主控執行）

- [ ] **Step 1: Windows debug**：`fvm flutter run -d windows --dart-define-from-file=secrets/cloud_sync_defines.json`，綜合頁、卡池頁（祈願與頌願各一）、設定頁和改動前一樣，沒有廣告、沒有多出的間距或設定項目；App log 沒有 `[ads]`。（實體輸入需使用者同意。）
- [ ] **Step 2: Android 模擬器 debug（測試廣告）**：用 `.run` 同參數執行；四個位置都在預期位置；只有頌願／只有祈願的資料各看一次綜合頁；直向、橫向、深淺色切換（log 依序 `native disposed` 再 `native loaded`）；紀錄翻頁沿用同一則；斷網重開不顯示也不留白。驗證器提示要先關掉再操作。
- [ ] **Step 3: Android release（正式 ID）**：`fvm flutter build apk --release --dart-define-from-file=secrets/cloud_sync_defines.json --dart-define-from-file=secrets/ads_defines.json`；`build/app/outputs/mapping/release/seeds.txt` 有 `WorkDatabase_Impl()`；release merged manifest 有 `NATIVE_AD_DEBUGGER_ENABLED=false`、App ID 是正式值；`libapp.so` 含正式原生單元 ID、不含測試單元 ID（用 `grep -c` 計數確認，不印出內容、不讀 `secrets/`）；模擬器移除 debug 版後安裝，啟動正常、`logcat -b crash` 為空、匯入資料後廣告載入或正常收起、驗證器不彈出。
- [ ] **Step 4: 長螢幕兩則同框檢查**：綜合頁兩個區段都有資料時，在模擬器長螢幕捲動，記錄是否會同時看到兩則（spec 第四節，只記錄不處理）。
- [ ] **Step 5: 寫 spec 附錄**（驗收結果、和鳴潮第 50 節刻意不同或也踩到的地方），commit `docs(spec): record the native ads acceptance results`。
