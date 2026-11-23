# Play 上架與更新（子專案 7）— 設計 spec

- 狀態：實作完成，待上架驗收
- 日期：2026-11-23
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 7；順序 … → 11 → 7 → 13）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-06-play-release-design.md`，移植筆記第 34～40 節（「十、Play 上架與更新」整節），以及路線圖第四節列的合併後 CI commit
- 前一個子專案：`2026-11-22-l10n-complete-locales-design.md`（子專案 11）

---

## 一、目的

讓只玩手機的原神玩家可以從 **Google Play** 安裝、更新這個 App，維護者每次發版只要觸發一次 CI，再到 Play Console 按「升級到正式版」。做法、取捨與玩家看到的行為全部照鳴潮版的最終狀態，只換套件名稱、遊戲名稱與術語。

## 二、範圍

**做法：以鳴潮 `master` 上相關檔案的最終版本為底**，換套件名稱（`tw.reh.wuwa.gacha` → `tw.reh.genshin.gacha`）、遊戲名稱與術語（喚取 → 祈願），套到原神現有結構上。鳴潮子專案 7 的 commit（`b48bc94`～`85351a5`，2026-11-07～09）中間夾著多次修正，之後又有 `269aac7`（log 改傳例外物件）等全專案重構，所以不逐個重播，實作時拿 commit 對照「為什麼這樣寫」（和子專案 10 相同）。原神的更新檢查（`app_release.dart`、`app_release_checker.dart`）和鳴潮子專案 7 開始前的版本只差已經套用過的重構，可以直接疊上去。

**要移植的檔案（鳴潮路徑 → 原神同路徑）**：

| 類別 | 檔案 |
|---|---|
| 套件 | `pubspec.yaml` 加 `in_app_update`（鳴潮 `^5.0.0`） |
| 版本代碼 | `lib/services/android_version_code.dart`、`tool/android_version_code.dart` |
| 更新流程 | `lib/services/play_update.dart`、`lib/state/play_update_download.dart`、`lib/widgets/play_download_progress.dart`，以及鳴潮對 `lib/state/app_release.dart`、`current_release.dart`、`update_progress.dart`、`lib/services/app_release_checker.dart`、`lib/widgets/dialogs/new_version_dialog.dart`、`release_notes_content.dart`、`lib/pages/app_shell.dart`、`settings_page.dart` 的對應改動 |
| 文案 | ARB `updateNotesUnavailable`、`updateDownloadingMessage`、`updateRestartAction`、`updateInAppUnavailable`、`updateOpenPlayStore`、`updateErrorPlay` 等鳴潮子專案 7 新增的 key，**31 種語言全部補上**（子專案 11 已補齊所有語言，不能只加核心四種）；譯文以鳴潮同 key 為底，術語依 `docs/術語表.md` |
| Android | `android/app/build.gradle.kts`（release 簽章讀 `android/key.properties`，沒有時退回 debug 金鑰；檔頭 `import java.util.Properties`）、`android/.gitignore`（`key.properties`、`*.jks`、`*.keystore`）、`MainActivity.kt` 註冊新增的 `PlayUpdateProgressChannel.kt`、app 模組加 `com.google.android.play:app-update` 依賴 |
| 圖示 | 新主檔取代 `tool/app_icon_source.png`；`tool/generate_app_icons.dart` 照鳴潮擴充，多產生自適應圖示（`mipmap-anydpi-v26/ic_launcher.xml`、各密度 `ic_launcher_foreground.png`、`values/ic_launcher_background.xml`）與 Play 512 px 圖示（`docs/images/play-store/icon-512.png`，含 alpha 的 32 位元 PNG）；執行後再跑 `dart run flutter_native_splash:create` |
| CI | `.github/workflows/release.yml`（鳴潮最終版：prepare／build-windows／build-android／publish 四個 job），取代 `release-windows.yml`；`ci.yml` 的 `${{ github.head_ref }}` 改走 `env`（筆記第 35 節） |
| 安裝檔 | `scripts/build_installer/installer.iss` 的數字版本欄位去掉 `-rc.N`（鳴潮 `1a6a5ca`） |
| 工具 | `tool/apk_signer_certs.py`、`tool/play_upload_internal.py`（CI 不能用時備用） |
| 發版頁尾 | `.github/release-footer.md` 的防毒說明改成只針對 Windows 版（鳴潮 4.9） |
| 測試 | `test/services/android_version_code_test.dart`、`test/tool/android_version_code_test.dart`、`test/state/play_update_download_test.dart`，以及鳴潮對 `app_release_test.dart`、更新對話框、設定頁、`app_shell` 相關測試的改動 |
| 文件 | `docs/release.md`（改寫成兩個平台一起發版）、本機 `private/play-store/`（見 4.6）、`docs/privacy-policy.md`（只檢查，見 4.6） |

**從子專案 13 提前到這裡（我的判斷）**：路線圖把 `release.yml` 四個 job（鳴潮 `308587a`、`24c83e0`、`b263eea`、`6429ae8`）、`ci.yml` 的 `head_ref` 修正、安裝檔 `-rc.N`（`1a6a5ca`）列在子專案 13。鳴潮是先在子專案 7 建 `release-android.yml`、後來才合併；原神直接做最終版，不先建一份馬上要刪的流程。子專案 13 剩下授權頁、README、商店截圖與主題圖片、下載徽章、Crowdin `strings.xml`。

**已經做過、不再動**：
- 系統自動備份排除加密儲存（筆記第 39 節）：`AndroidManifest.xml` 已有 `fullBackupContent`、`dataExtractionRules`。
- Windows 解除安裝清掉根憑證與私鑰（筆記第 40 節）：`f5ad2a2`。
- 隱私權政策 `docs/privacy-policy.md`：子專案 10 已新增，已涵蓋 Android 版、廣告、刪除資料。

**不做**：
- GitHub Releases 提供 APK，或分成兩種建置版本（只上 Play）。
- 改動 Windows 的版本號規則（照舊用 workflow 的執行序號）。
- 自動升級到正式版（一律在 Play Console 手動按）。
- 商店主題圖片、截圖、`tool/generate_feature_graphic.py`、README 的 Android 段落與下載徽章：子專案 13。
- 把啟動器上的 App 名稱改成商店標題的寫法（啟動器空間小，長名稱會被截斷）。

## 三、目標／非目標／反目標

**目標**：
- 用正式的上傳金鑰簽章 AAB，觸發 `release.yml` 後 CI 建置兩個平台，兩邊都成功才發佈：Windows 建 GitHub Release 草稿，Android 上傳到 Play **內部測試軌道**並推出。
- Android 版的「有新版」以 Play 為準，對話框沿用 `NewVersionDialog`（更新內容、略過此版本），按「更新」在背景下載並顯示進度，下載完提示重新啟動。
- 準備上架所需的文件：商店頁文字、資料安全表單答案、給審查人員的說明、一次性設定與每次發版的步驟。
- 全平台換上新的 App 圖示，Android 加自適應圖示。

**非目標**：見第二節「不做」。

**反目標**（沿用鳴潮）：
- 改壞 Windows 的發佈流程或 GitHub 更新檢查。
- 上傳金鑰、密碼、服務帳戶金鑰進入 repo 或 log。
- Play 上還沒有的版本，App 卻叫玩家去更新。
- 從 Play 下載的版本雲端同步授權失敗。
- 一個平台建置失敗，另一個平台卻已經發佈（用掉版本代碼、GitHub 沒有對應版本）。

## 四、設計

### 4.1 版本代碼（只限 Android）

照鳴潮筆記第 34 節，不改：
- 公式 `MAJOR × 1,000,000 ＋ MINOR × 10,000 ＋ PATCH × 100 ＋ 尾碼`，正式版尾碼 99，`-rc.N` 尾碼 N（1～98）。
- tag 每段不接受前導零；MAJOR 最大 2099，MINOR、PATCH 最大 99；不合法一律失敗。
- App 反推 Play 版本與 CI 換算共用 `lib/services/android_version_code.dart`；CI 只擷取 `VERSION_CODE=`／`BUILD_NAME=` 兩行。
- 只在 Android 建置時以 `--build-number` 傳入，不寫回 `pubspec.yaml`；Windows 照舊用執行序號（版本資源每欄上限 65535）。

### 4.2 上傳金鑰與簽章

- 另開一把原神 App 專用的上傳金鑰（PKCS12，RSA 2048 以上，有效期 25 年以上），不沿用 `G:\_APK_Key` 或鳴潮的金鑰。使用者在自己電腦用 `keytool` 產生，密碼在終端機輸入，**不經過對話**。計畫附指令。
- `build.gradle.kts` 讀 git-ignored 的 `android/key.properties`；不存在時 release 退回 debug 金鑰，`flutter run --release` 照常能用。
- Play 應用程式簽署照 Play 預設，第一次上傳時自動啟用。

### 4.3 App 內更新（Android）

照鳴潮筆記第 37 節的最終行為，依 `isAndroidProvider` 分流，Windows 完全照舊：
- 有沒有新版以 Play 的 `checkForUpdate()` 為準，`developerTriggeredUpdateInProgress` 也算有更新；用 `availableVersionCode` 反推版本號，再從 GitHub Releases 取「目前版本之後、到該版本為止」的更新內容。GitHub 查不到時仍提示有新版，內容顯示「無法取得更新內容」。
- 「略過此版本」沿用 `skippedReleaseTag`，以反推的 `vX.Y.Z` 比對。
- 彈性更新：呼叫前先 `checkForUpdate` 判斷狀態（已下載就直接提示重新啟動），下載期間同時監聽安裝狀態，取消或失敗就自行結束，不讓 Future 永遠等待。
- 下載中顯示常駐 SnackBar：「正在下載新版本...」、百分比、進度條、已下載／總大小（`PlayUpdateProgressChannel` 送出位元組數）。下載完換成不會自動消失的「重新啟動」提示。
- 玩家拒絕或從通知列取消：視為玩家的選擇，不顯示提示。真正失敗才顯示「目前無法在 App 內更新，請到 Google Play 更新」與「前往 Google Play」；按鈕放在 SnackBar 內容裡讓它可以換行（320 dp 寬、放大字級不溢出）。
- 不是從 Play 安裝的版本：啟動時的自動檢查安靜略過、只記 log；手動檢查顯示「無法連線到 Google Play，或此版本不是從 Google Play 安裝」。
- Android 顯示的更新內容與 Windows 相同，不裁掉頁尾（頁尾改成適用兩個平台，見第二節）。
- log 沿用 `release` 等既有 Logger 名稱，英文，記 Play 回報的狀態、版本代碼與彈性更新各階段結果；例外以物件傳入。

### 4.4 CI：`release.yml`

照鳴潮最終版（筆記第 35 節），換原神的建置細節：
- 手動觸發，輸入 tag 與是否為預覽版。四個 job：
  - `prepare`：驗證 tag、算出版本號與版本代碼、記下要建置的 master commit（`base_sha`），不推任何東西。
  - `build-windows`、`build-android`：同時從 `base_sha` 建置，產物存成 artifact。Windows 只在 runner 上改 pubspec 版本號，在短路徑建置（鳴潮 `24c83e0`）。
- **直接以鳴潮最終版 `release.yml` 為底，只換專案名稱與 repo 名稱**：原神現在的 `release-windows.yml` 和鳴潮合併前（`87edab3^`）的版本除了一段註解完全相同（2026-11-23 比對），沒有原神獨有的步驟要保留。
  - `publish`：兩個 build 都成功才執行：版本號 commit 推回 master、建 GitHub Release 草稿、用 `r0adkll/upload-google-play` 上傳 AAB 到 internal（參數用 `tracks`、狀態 `completed`、不填「新功能」）。
- Android job：從 secrets 還原上傳金鑰、`key.properties`、`secrets/cloud_sync_defines.json`、`secrets/ads_defines.json`（子專案 10 留下的「Write ads defines from secrets」在這裡做）。照鳴潮：缺**上傳金鑰或服務帳戶** secret 就失敗；缺雲端同步或 AdMob secrets 只發 `::warning::`（該功能停用或只顯示測試廣告），不擋建置。建置後用 `keytool -printcert -jarfile` 確認不是 debug 金鑰簽的。第五節的步驟要提醒使用者先設好 `ADMOB_APP_ID`、`ADMOB_NATIVE_UNIT_ID`，發版後檢查 log 沒有這兩個警告。
- 秘密一律寫進 runner 暫存檔，不印到 log，job 結束時刪除。
- 同一個 tag 不能重跑整個 workflow（Play 版本代碼已用掉）；失敗時用「Re-run failed jobs」只重跑失敗的那邊。
- 預覽版只能留在內部測試，不可升級正式版（App 查 GitHub 時會略過預覽版）。
- 修改後用 actionlint 檢查兩份 workflow。

### 4.5 雲端同步 SHA-1

Google Cloud 的 Android OAuth 用戶端一筆只能填一個 SHA-1。在雲端同步桌面用戶端所在的同一個專案，套件名稱 `tw.reh.genshin.gacha`，為上傳金鑰與 Play 應用程式簽署金鑰（Play Console「複製所有憑證指紋」給的三個 SHA-1，含量子簽章的兩張）各建一筆。debug 金鑰在子專案 5 已建。

### 4.6 上架文件

- 照鳴潮 `64cff46`：商店頁文字、資料安全表單、審查說明、一次性設定與發版步驟放在本機不進版控的 `private/play-store/`（`.gitignore` 加 `/private/`），檔案切分照鳴潮：`README.md`（步驟與 secrets 一覽）、`listing.md`、`data-safety.md`、`review-notes.md`。
- **商店標題**（使用者 2026-11-23 決定，上限 30 字）：
  - 繁中「祈願卡池分析 for 原神」
  - 英文「Wish Analyzer for Genshin」（「Wish Analyzer for Genshin Impact」32 字超過上限，比照鳴潮用縮寫）
  - 日文「祈願分析 for 原神」
  - 簡中「祈愿卡池分析 for 原神」
  - 說明開頭加「非官方工具，與 HoYoverse 無關」（各語言對應譯文）。預設語言英文。
- 完整說明強調資料留在本機，以及 Android 的讀取方式（無線偵錯、root、手動貼網址），內容依原神子專案 2 的實際行為寫（讀 logcat，不是檔案）。
- 資料安全與審查說明照鳴潮，換成原神的實際行為：圖片來自 HoYoWiki、有原生廣告（AdMob）、雲端同步寫入玩家自己的 Google 雲端硬碟、`WRITE_SECURE_SETTINGS` 用途、審查人員沒有原神帳號時怎麼用手動貼網址測試。
- 商店頁「網站」要填有 `app-ads.txt` 的網域，不能填 GitHub（筆記第 50 節）。
- `docs/privacy-policy.md` 只檢查與實際行為一致、刪除資料一節有錨點可填進資料安全表單；送審前必須已合併到 master 且網址打得開。

### 4.7 新 App 圖示（全平台）

- 來源：使用者 2026-11-23 提供的星形圖示（`C:\Users\p2902\.t3\userdata\attachments\e5876792-ebce-4c0e-b110-5aaa3874cab1-919bc609-e458-4b4b-b6d5-4c30a98d734a.png`，1024×1024，圓角外是白色）。造型由使用者決定，不再改。
- 處理（比照鳴潮 4.7）：從四個角 flood fill 偏亮像素（含反鋸齒邊，再外擴 3px），每一列用該列其餘深色背景的中位數補滿。背景是垂直漸層、左右一致，補完沒有接縫；主體不動。2026-11-23 已試做並經使用者看過預覽。
- 取代 `tool/app_icon_source.png`，執行擴充後的 `dart run tool/generate_app_icons.dart` 重產：App 內 UI、Windows `.ico`、legacy mipmap、自適應圖示、Play 512 px、Android 12 以下啟動畫面圖示；再跑 `dart run flutter_native_splash:create`。
- 自適應圖示照筆記第 38 節：前景是整張圖縮進中央 72dp 可見區、外圍用邊緣像素延伸到 108dp，不去背；背景色取圖的深藍。比例用圓形與方圓形遮罩的預覽決定。
- 舊的胡桃圖示一併移除，grep 確認 repo 內沒有其他地方引用。

### 4.8 文件

- 實作與上架時遇到的技術決定和踩雷，記在本 spec 的附錄（和之前的子專案相同，原神沒有另外的移植筆記）。
- `docs/release.md` 改寫成觸發 `release.yml`、兩個平台一起發版、到 Play Console 升級正式版。

## 五、需要使用者操作的事（計畫要標出順序與時機）

1. 產生上傳金鑰，建立本機 `android/key.properties`。
2. 在 Play Console 建立 App（不填套件名稱，第一次上傳 AAB 時由檔案決定；預設語言英文）。
3. **第一次手動上傳** AAB 到內部測試並推出（新 App 只能由 Console 手動建立第一版；用 `-rc.1`）。上傳前先在模擬器實際啟動一次本機建的 release APK（筆記第 35 節：R8 只在 release 生效）。
4. 建 Google Cloud 服務帳戶（只啟用 Google Play Android Developer API，不給專案角色），Play Console 只給「查看應用程式資訊」與「發布至測試群組」；JSON 金鑰、上傳金鑰設成 GitHub secrets。
5. 在 Google Cloud 為上傳金鑰與 Play 簽署金鑰的三個 SHA-1 各建一筆 Android 用戶端。
6. AdMob 連結 Play 商店頁；商店頁「網站」填有 `app-ads.txt` 的網域。
7. 填商店頁、資料安全、內容分級、目標對象（只勾 13 歲以上），上傳主題圖片與截圖（子專案 13 產生）。
8. PR 合併後：確認隱私權政策網址打得開，跑一次 `release.yml`，再送審。

## 六、驗收

**自動測試**（`fvm flutter analyze` 無問題、`fvm flutter test` 全過）
- 版本代碼：正式版、預覽版、反推、不合法 tag（前導零、超出上限、格式錯誤），App 與 `tool/` 兩份結果一致。
- Android 更新分流：Play 有新版顯示對話框且內容來自 GitHub；Play 沒有但 GitHub 有不提示；GitHub 查不到仍提示；略過此版本；非 Play 安裝時自動檢查安靜略過、手動檢查顯示失敗；已下載或進行中的更新接續；取消不提示；失敗顯示前往 Google Play；下載進度與重新啟動提示。
- Windows 的更新檢查行為與測試不變。
- 新增字串 31 種語言都有，`plural_one_placeholder_test` 等既有 l10n 測試全過；失敗提示在 320 dp 寬、核心四種語言不溢出。

**實機與手動**
- 圖示：Windows 工作列、安裝檔、App 標題列；Android 啟動器圓形、方圓形裁切與啟動畫面，主體沒有被裁、沒有白邊或接縫。
- 本機 release APK 在模擬器啟動，`adb logcat -b crash` 沒有東西。
- 內部測試軌道安裝的版本：能開啟、讀取記錄的各種方式照常、雲端同步能授權並同步（驗證 4.5）。
- 彈性更新：用 Play「內部應用程式分享」裝舊版、分享版本代碼較大的版本，確認對話框、下載進度、重新啟動；另測下載完滑掉提示再重開、下載途中關 App 再重開、從通知列取消。
- CI（PR 合併後）：`release.yml` 跑一次，GitHub Release 草稿有安裝檔、AAB 出現在內部測試且版本代碼正確、log 沒有任何秘密。

實機要等使用者明講「接好了／可以測」才操作；手機上目前是 debug 版，從 Play 安裝前要先備份、解除安裝（所有使用者空間），本機測試版一律 `adb install --user 0`。

## 七、Play 審查風險（推論，未實際送審）

- `WRITE_SECURE_SETTINGS` 與自我配對 ADB 可能被要求說明用途，審查說明要寫清楚。
- 圖示與商店圖近似遊戲道具：使用者已知並接受（比照鳴潮）。
- 被拒時回到使用者決定。

## 八、留給實作者決定

- `generate_app_icons.dart` 自適應前景的縮放比例（依遮罩預覽）。
- 鳴潮檔案套到原神時，遇到原神結構不同（例如 `app_shell.dart` 已有子專案 9b、10 的改動）怎麼合，原則是行為和鳴潮一致。
- `private/play-store/` 內文的具體字句（遵守 4.6 的事實與字數上限）。

---

## 附錄：實作結果

### Commit 對照（feat/android）

| Task | Commit |
|---|---|
| 1 版本與上傳驗證 | `8270733` |
| 2 Play 更新服務 | `3ed8dfc` |
| 3 彈性更新流程與重啟提示 | `fd9b683` |
| 4 下載進度顯示 | `9067332` |
| 5 圖示（含自適應圖示） | `f336dc6` |
| 6 簽章、發版 CI、安裝檔與文件 | `04013b6`、`0330af0` |
| 7 `private/play-store/` 上架素材 | 無 commit（git 忽略） |
| 8 實跑與交接 | 本附錄所在 commit |

### 實作時才決定的值

- 自適應圖示前景縮放比例 2/3（與鳴潮相同），背景色 `#131E30`。預覽圖確認圓環留在 72dp 可見範圍內，只有左下角的裝飾星芒會被圓形遮罩裁掉。

### 已驗證

- actionlint 實際跑過，`.github/workflows/*.yml` 無任何輸出（本機沒有 shellcheck，`run:` 腳本未經 shellcheck）。
- ISCC 實際跑過：新版 `installer.iss` 以 `1.9.0-rc.1` 編譯成功（`FileVersionRaw` 為 `1.9.0.0`，文字版本保留 `-rc.1`）；對照組舊版 `installer.iss` 以同樣參數編譯失敗（`VersionInfoVersion` 無效），證明修正有效。打包的是本機既有的 Windows Release 建置，只驗證版本欄位邏輯。
- 沒有 `android/key.properties` 時，release APK 可用 debug 簽章後備建置成功。
- 模擬器（Medium_Phone_API_36.0）實跑 release APK：啟動後 `adb logcat -b crash` 無任何輸出，停在首頁；設定頁按「檢查更新」顯示 `updateErrorPlay` 的訊息（非 Play 安裝的預期結果）。
- 格式化、`flutter analyze`、`flutter test` 全綠。

### 與鳴潮不同的裁決

- `docs/release.md` 拿掉「下載徽章／`{{INSTALLER_URL}}`」那句，等子專案 13 加徽章時再恢復鳴潮原文；`release.yml` 仍逐字保留鳴潮的 Replace 步驟（目前不作用）。
- 沿用既有的 `updateOpenPlayStore` 鍵（「前往 Google Play」）給 App 自身的更新失敗提示，並放寬其 `@description` 同時涵蓋兩種用途，文字不變。
- 320dp 寬度的版面測試擴大到全部 31 個語系（計畫要求）。
- `docs/privacy-policy.md` 的設定項目名稱對齊 ARB `settingsLogAccess`（「讀取遊戲 log」）。

### 尚待使用者處理

- 第五節步驟 1～3：產生上傳金鑰、在 Play Console 建立 App、第一次手動上傳 `-rc.1`。
- 第六節「實機與手動」各項：實機驗收（內部測試軌道安裝、彈性更新流程、雲端同步授權）、合併後的 `release.yml` 實跑。這些都要等使用者同意才會操作手機。
