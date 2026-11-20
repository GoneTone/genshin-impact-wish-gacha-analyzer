# Android 雲端同步登入（子專案 5）— 設計 spec

- 狀態：已核准（2026-11-20）
- 日期：2026-11-20
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 5、第七節 Google Cloud）
- 既有雲端同步設計：`2026-07-06-google-drive-cloud-sync-design.md`
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-06-android-cloud-sync-login-design.md`，以及 commit `9dde37a`、`28bfd10`、`70139fb`、`e3b5944`、`a870562`、`53aff8f`、`7ab0e10`（程式）與 `2adf595`（README）；移植筆記第 29～33 節

---

## 一、目的

讓只用手機的玩家也能把卡池記錄同步到 Google 雲端硬碟，而且手機和電腦版**讀寫同一份同步檔**。路線圖已決定「登入分流，Drive 同步本體共用」，Android 使用 Android 類型的 OAuth 用戶端。做法照搬鳴潮版的最終狀態，檔案分工與名稱和鳴潮版相同，只換術語。

## 二、範圍

- 移植鳴潮版子專案 5 的 7 個程式 commit（`9dde37a`～`7ab0e10`，扣掉移植筆記的 `2adf595`、`3106597`、`4a147f6`），以及 `2adf595` 裡的 README 段落。
- 移植前兩邊的雲端同步程式幾乎相同：`lib/state/cloud_sync.dart` 與鳴潮 `9dde37a~1` 只差三處註解（原神多 `scopeMissing` 的說明、spec 章節號、「記錄」用字），`google_auth_service.dart`、`cloud_sync_config.dart`、`token_store.dart` 只差套件名稱。所以這次**可以逐 commit 照搬**，只換套件名稱與術語（「喚取紀錄」→「卡池記錄」）。
- 鳴潮之後只有 `f87c2a4`（右到左語言）碰過這些檔案，屬於後面的子專案，不在這次範圍。
- **不移植**鳴潮的效能 commit（`4a0a9db`～`52cb8c8`、`b8a6bf1`，雲端同步移到背景 isolate）：那是鳴潮子專案 8 的改動，留到子專案 8。
- 鳴潮版 `docs/Android移植筆記.md` 第九節的內容，在原神版改記在本 spec 的附錄（原神版沒有移植筆記檔，和子專案 3、4 相同）。

## 三、目標／非目標／反目標

**目標**

- Android 上能連結 Google 帳號、自動／手動同步、中斷連結，行為與電腦版相同。
- 手機與電腦連結同一個 Google 帳號時，看到的是同一份同步檔（`cloud_sync_config.dart` 的 `cloudSyncFileName`＝`genshin_gacha_sync.json`）。
- 一台裝置中斷連結，不影響其他裝置的同步（使用者 2026-11-20 選 A，見 5.3）。

**非目標**

- 沒有 Google Play 服務的裝置（App 只在 Play 上架）。這類裝置連結失敗時顯示既有的「授權失敗」即可。
- 改動同步檔格式、合併規則、觸發時機。
- 驗收時手機上是朋友的帳號：連結使用者的 Google 帳號後，朋友的記錄會同步到使用者的雲端同步檔與電腦，這是預期中的（使用者 2026-11-20 確認）。

**反目標**

- 改壞 Windows 既有的登入流程與 UX（瀏覽器授權、完成頁、取消、把視窗帶回前景）。中斷連結不再撤銷授權是使用者決定的行為變更，不算改壞。
- 在手機上冒用桌面版 OAuth 憑證。
- 只在開發用金鑰簽的版本能登入、Play 下載的版本登入失敗（三把金鑰的 SHA-1 都要登記，見 5.6）。

## 四、做法比較（照鳴潮版選 A）

| | 做法 | 取捨 |
|---|---|---|
| **A** | **官方 `google_sign_in`，系統的 Google 帳號選擇視窗** | **Google 建議的 Android 做法；不必存任何密鑰或 refresh token；只有登入那段依平台分流** |
| B | `flutter_appauth`＋自訂 URI scheme 轉回 App | 可沿用 refresh token 那套；但 Google 新建的 Android 用戶端預設停用自訂 scheme，官方不鼓勵 |
| C | 手機沿用電腦的瀏覽器＋localhost 流程 | 改最少；但等於在手機上用桌面版憑證，違反用戶端類型規範 |

鳴潮版 2026-11-06 的手機實驗（`google_sign_in` 7.2.0／`google_sign_in_android` 7.2.18）已驗證 A 可行，結論見附錄 A，原神版不重做實驗。

## 五、設計

和鳴潮版第五節相同，只換術語。下面列出原神版要注意的地方。

### 5.1 憑證與啟用條件

- 不新增 define、不建網頁應用程式用戶端。
- `isCloudSyncConfigured` 在 Android 上以 `CLOUD_SYNC_CLIENT_ID` 不為空當作「這個建置有設定雲端專案」的開關（程式用不到這個 ID，但「沒帶 `secrets` 建置就停用同步」在兩個平台一致）。Windows 維持 `CLIENT_ID`＋`CLIENT_SECRET`。
- Android 的 CI 建置注入留給子專案 7。
- 套件：`google_sign_in: ^7.2.0`（和鳴潮版相同，鳴潮 `70139fb` 從釘死改成 `^`）。lock 版本以 `flutter pub get` 結果為準，預期 `google_sign_in` 7.2.0、`google_sign_in_android` 7.2.x。

### 5.2 登入分流

- 把「連結／還原／中斷連結」抽成平台無關的介面（`lib/services/cloud_sync/cloud_auth.dart`），`CloudSyncNotifier` 只依賴介面。Windows 實作是現在的 `GoogleAuthService`；Android 新增 `android_cloud_auth.dart`（授權邏輯）與 `google_authorization_gateway.dart`（包住 `google_sign_in` 的薄層，方便測試），依 `isAndroidProvider` 選擇。
- **Android 連結**：`authorizeScopes(cloudSyncScopes)` → 用通行證呼叫 userinfo 取 email → 存 email、立即同步一輪（與 Windows 相同）。
- **Android 還原**：不讀 `TokenStore`，改用 `authorizationForScopes` 靜默取通行證，再以 userinfo 確認 email。回 null，或 email 與 settings 存的不同，一律丟 `CloudReauthRequiredException`，走既有「需要重新連結」流程。
- **通行證過期與快取**：Android 通行證約 1 小時過期，App 無法自己續期，所以每輪同步都重新靜默取得，不沿用上一輪的 client。通行證被拒時（googleapis 的 401，或 `AccessDeniedException` 帶 `invalid_token`），先 `clearAuthorizationToken` 再靜默重取**一次**；仍失敗才走 `reauthRequired`。清除快取是盡力而為：舊版 Play 服務不支援，失敗只記警告。
- **缺少 Drive 權限**：依賴既有路徑（同步時遇到 insufficient scope → `reauthRequired`＋`scopeMissing`）。
- **使用者取消**：`GoogleSignInExceptionCode.canceled`，以及「`unknownError` 且 Play 服務狀態碼 16」都當成取消，回到閒置、不顯示「授權失敗」。log 記完整的 code 與 description。
- 啟動時只還原一次；`link` 在 commit 失敗時要關掉 client（鳴潮 `53aff8f`、`7ab0e10` 的修正一併照搬）。

### 5.3 中斷連結：只忘記本機（使用者 2026-11-20 選 A，兩個平台）

同一個 Google 帳號對同一個 Cloud 專案只有一份授權，任何一台裝置撤銷，所有裝置都會失效，所以**兩個平台的中斷連結都不再向 Google 撤銷**：

- Windows：只刪本機 refresh token、清 settings。
- Android：`clearAuthorizationToken`（目前通行證，盡力而為）＋`signOut()`、清 settings。
- Windows「取消後才到的授權」改成只丟棄、不撤銷；「授權缺 Drive 權限」改成只丟棄並報 `scopeMissing`、不撤銷。
- `revokeToken()` 因此不再有呼叫者，刪除。
- 中斷連結的確認文字不改（和鳴潮版相同）。想徹底取消授權的玩家可到 Google 帳戶設定移除。

### 5.4 介面（手機）

- 設定頁雲端同步區塊沿用既有元件。
- 等待授權的文字：Android 用新字串 `cloudSyncAwaitingConsentAndroid`（繁中「請在 Google 視窗完成授權...」），取消按鈕保留（和鳴潮版相同）。
- 「把視窗帶回前景」只在 Windows 呼叫；Android 不呼叫 `windowManager`。授權完成頁（`postAuthPage`）只有 Windows 的瀏覽器流程會用到。
- `cloudSyncIntro` 的「在多台電腦間同步」改成「在多台裝置間同步」（會改到 Windows 的文字）。
- **ARB**：`cloudSyncIntro` 的修改與新字串 `cloudSyncAwaitingConsentAndroid` 加到所有已翻譯的 9 份 ARB（zh、zh_Hans、en、es、fr、ja、pt_BR、th、vi），空殼 ARB 不動（**我的判斷**：鳴潮版當時只有 4 份已翻譯；原神版依「新 key 只加在已翻譯的 ARB」的慣例）。先寫 `app_zh.arb`，再以中文為準翻其他語言；省略號用半形 `...`。

### 5.5 log

Logger 沿用 `cloudsync.auth`／`cloudsync.sync`，訊息用英文，內容照搬鳴潮版：連結開始／成功／取消（含 exception code）／失敗、靜默還原成功／需要互動／email 不符／失敗、通行證被拒時清快取重試、中斷連結結果。絕不記通行證內容，email 不寫進 log。

### 5.6 Google Cloud Console

- **已完成（使用者 2026-11-20）**：在原神電腦版雲端同步所在的同一個專案建立 Android OAuth 用戶端，套件名稱 `tw.reh.genshin.gacha`，登記開發機 debug 金鑰的 SHA-1（`F8:09:DC:34:0C:1C:D5:92:C5:0A:44:8E:0B:DB:1C:96:8D:30:08:1B`）。
- **子專案 7 待辦**：上傳金鑰與 Play 應用程式簽署金鑰的 SHA-1 都要補登記，否則 Play 版會授權失敗。

## 六、驗收

**自動測試**（`fvm dart format lib/ test/` 無改動、`fvm flutter analyze` 無問題、`fvm flutter test` 全過）

- Windows 既有雲端同步測試驗證的行為保留：refresh token 寫入、遲到授權不寫入、完成頁、取消。測試可以為了新介面做機械式調整。原本斷言「有撤銷」的地方，依 5.3 改為斷言「沒有撤銷」；其餘斷言不可刪減。
- 原神的 `test/helpers/cloud_sync_fakes.dart` 與 `test/state/cloud_sync_test.dart` 已和鳴潮分岔（原神的 fake 用 `revokedTokens`、`signInGate`、`downloadGate`，沒有鳴潮的 `restoreCalls`、`lastPostAuthPage`、`signInThrowsScopeMissing`，測試名稱也不同），測試部分不能逐行套鳴潮的 patch，要依上一點手動對應；鳴潮新增的測試檔（`android_cloud_auth_test.dart`、`google_authorization_gateway_test.dart`、`cloud_auth_test.dart`、`cloud_sync_config_test.dart` 的新增案例）照搬（**我的判斷**，審查時發現）。
- Android 實作（以假的授權層測試），照搬鳴潮版的測試：
  - 連結成功存 email 並同步一輪；使用者取消（含狀態碼 16）回到閒置且不顯示錯誤。
  - 靜默還原回 null → `reauthRequired`；email 不符 → `reauthRequired`。
  - 通行證被拒（401、`invalid_token`）→ 清快取並重取一次；重取成功則同步成功。
  - 中斷連結會清快取、登出、清 settings，且不撤銷；清快取失敗不影響中斷連結。
  - 通行證過期後，下一輪同步會重新取得。
- `isCloudSyncConfigured` 在兩個平台各自依 5.1 判斷。
- 設定頁在 Android 顯示 Android 版等待文字，且不呼叫把視窗帶回前景。

**模擬器（Pixel_8a，Google Play 映像）**：需要使用者在模擬器登入一個 Google 帳號。

- 在帳號選擇畫面按返回，回到「連結 Google 帳號」按鈕，不顯示「授權失敗」。
- 連結後，電腦上的記錄同步下來，並自動補抓物品圖片。
- 同一個 App 程序開超過 1 小時後按「立即同步」仍成功。
- 測完在 App 裡中斷連結（只清本機），避免之後在模擬器做清除資料的測試時，刪除同步到雲端。

**手機（ROG Phone，debug 版）**

- 連結 → 帳號選擇 → 授權 → 顯示 email。
- 手機上的記錄同步到雲端，電腦同步後也看得到（朋友的帳號，見第三節非目標）。
- 殺掉 App 重開，不必重新連結就能同步。
- 手機中斷連結後電腦照常同步；再連結時跳帳號選擇。

**Windows**：連結、同步正常；電腦中斷連結後，手機照常同步；重新連結（瀏覽器授權）正常。

Android release 版實跑照之前的決定，留到 `feat/android` 開 PR 前。

## 七、留給實作者決定

- 鳴潮版第七節留給實作者的項目，鳴潮已經做出決定，原神版照搬鳴潮的實作，不重新決定。
- 移植時遇到原神特有的差異（例如 `scopeMissing` 的註解、`記錄` 用字），保留原神現狀。

## 八、文件

- 本 spec 附錄 A：鳴潮版實驗與實測結論（移植筆記第 29～33 節的摘要）。附錄 B：原神版驗收結果與實作坑，驗收後補上。
- README ×4 的「雲端同步憑證（選用）」段落加第 4 點：Android 沿用同一個 `secrets/cloud_sync_defines.json`，並要在同一個 Cloud 專案建立 Android 用戶端（套件名稱 `tw.reh.genshin.gacha`＋SHA-1），附 `keytool` 查 debug 金鑰指紋的指令與 Android 的 `flutter run` 範例。
- 子專案 7 的待辦：上傳金鑰與 Play 簽署金鑰的 SHA-1 補登記（記在路線圖第七節已有，這裡只確認）。

---

## 附錄 A：鳴潮版的實驗與實測結論（2026-11-06）

1. **只走「授權」、不走「登入」**：`GoogleSignIn.instance.initialize()` 不帶參數，直接 `authorizationClient.authorizeScopes([drive.appdata, email])`。走 `authenticate()` 必須另建「網頁應用程式」用戶端當 `serverClientId`，拿桌面用戶端 ID 去填會得到 `[28444] Developer console is not set up correctly.`。
2. **Android 用戶端的 ID 不放進程式**：Play 服務用「套件名稱＋簽章 SHA-1」找到專案裡對應的 Android 用戶端。查證方法：tokeninfo 看通行證的 `azp`。
3. **授權是整個 Cloud 專案共用一份**：手機第一次授權時可能連授權畫面都不跳，直接沿用電腦給過的授權；任何一台撤銷，所有裝置都要重新連結。appDataFolder 也以 Cloud 專案區分，Android 用戶端必須和桌面用戶端在同一個專案。
4. **Play 服務會快取已失效的通行證**：撤銷後重新授權拿到的是舊通行證，API 回 401，要 `clearAuthorizationToken` 再要一次。判斷「通行證被拒」要同時認 401 與 `AccessDeniedException`（`invalid_token`）。
5. **使用者取消不是 `canceled`**：在帳號選擇畫面按返回，`google_sign_in_android` 7.2.18 回報 `GoogleSignInException(unknownError, "...16: [16] Cancelled by user.")`。
6. **簽章指紋要逐把登記**：只登記 debug 金鑰時，Play 下載的版本會授權失敗（推論是狀態碼 10 = `DEVELOPER_ERROR`）。
7. **舊版 Play 服務不支援清除快取憑證**：模擬器（Play 服務 23.18）呼叫 `clearAuthorizationToken` 會丟 `Missing Feature{name=auth_api_credentials_clear_token}`，而且要好幾分鐘才回來，所以清除一律盡力而為。
8. **App 完全關掉再開，靜默授權直接拿到通行證**；「只忘記本機」之後靜默授權拿不到，再授權時跳帳號選擇，可以換帳號。
9. **模擬器關機會存快照**，重開後是從原狀態繼續跑。模擬器連結真實帳號後，測完要中斷連結。
