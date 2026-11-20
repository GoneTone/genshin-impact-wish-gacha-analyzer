# Android 雲端同步登入（子專案 5）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 上能連結 Google 帳號並和電腦版讀寫同一份雲端同步檔；兩個平台的中斷連結都改成只忘記本機。

**Architecture:** 照搬鳴潮版子專案 5：新增平台無關的 `CloudAuth` 介面（`cloud_auth.dart`），`CloudSyncNotifier` 只依賴它；Windows 實作是既有的 `GoogleAuthService`，Android 實作是新的 `AndroidCloudAuth`＋`GoogleAuthorizationGateway`（包 `google_sign_in` 授權 API），依 `isAndroidProvider` 選擇。同步本體不動。

**Tech Stack:** Flutter（FVM）、Riverpod 3、`googleapis_auth`、`google_sign_in` ^7.2.0、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-20-android-cloud-sync-login-design.md`（必讀；第五節是設計，第六節是驗收，附錄 A 是鳴潮實測結論）

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。
- 移植前兩邊的雲端同步程式幾乎相同（spec 第二節），所以 `lib/` 可以直接套鳴潮的改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`。新檔以鳴潮 `7ab0e10` 的版本為底：`git -C ../wuthering-waves-convene-gacha-analyzer show 7ab0e10:<路徑>`。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；註解與字串裡的「喚取紀錄」→「卡池記錄」。原神現有的註解差異（`scopeMissing` 說明、spec 章節號、「記錄」用字）保留原神版。
- **測試不能逐行套 patch**：原神的 `test/helpers/cloud_sync_fakes.dart`、`test/state/cloud_sync_test.dart` 已和鳴潮分岔（原神 fake 用 `revokedTokens`、`signInGate`、`downloadGate`）。依鳴潮測試的意圖改寫到原神的 fake 上；既有斷言不可刪減，只有「有撤銷」改成「沒有撤銷」。鳴潮新增的測試檔整檔照搬再換名稱。
- 不確定要不要偏離時回報 NEEDS_CONTEXT，不要自行改寫。

## Global Constraints

- 依賴只加 `google_sign_in: ^7.2.0`（用 `fvm dart pub add`），其他依賴不動；lock 解出 `google_sign_in` 7.2.0、`google_sign_in_android` 7.2.x，不同主次版本就回報。不改 `android/`、manifest、proguard。
- 平台判斷：state／widget 用 `isAndroidProvider`；`cloud_sync_config.dart` 沒有 ref，照鳴潮版的寫法。
- `isCloudSyncConfigured`：Android 只看 `CLOUD_SYNC_CLIENT_ID` 不為空；Windows 要 `CLIENT_ID` 與 `CLIENT_SECRET` 都不為空。
- 兩個平台的中斷連結、取消後遲到的授權、缺 Drive 權限都**不向 Google 撤銷**；`revokeToken()` 刪除。
- 使用者取消＝`GoogleSignInExceptionCode.canceled`，或 `unknownError` 且 description 帶 Play 服務狀態碼 16；回 idle、不顯示錯誤。
- Android 通行證不跨輪沿用（`keepsClientAcrossRounds == false`）；通行證被拒（`isInvalidToken`：401 或 `AccessDeniedException` 帶 `invalid_token`）→ `clearToken` 後重取一次。`clearToken`／`signOut` 失敗只記警告（盡力而為）。
- 新字串只有 `cloudSyncAwaitingConsentAndroid`；`cloudSyncIntro` 改「電腦」為「裝置」。只改 9 份已翻譯 ARB（zh、zh_Hans、en、es、fr、ja、pt_BR、th、vi），22 份空殼不動。改完 `fvm flutter gen-l10n`。
- log：英文，Logger 沿用 `cloudsync.auth`／`cloudsync.sync`；不記通行證、不記 email。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；中文全形標點、省略號半形 `...`。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。commit 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（Git Bash 裡 GPG 簽章會失敗，不可跳過簽章）。分支 `feat/android`，不開新分支、不 push。

## Review Focus

1. **在帳號選擇畫面按返回**：Play 服務回報的是 `unknownError`＋狀態碼 16，不是 `canceled`；畫面要回到「連結 Google 帳號」而不是「授權失敗」 → Task 2 測試 `unknownError with Play services status 16 → true` 與 `link cancelled by the user → idle without error`。
2. **舊版 Play 服務不支援清除快取憑證**：中斷連結時清除失敗，仍要清掉 email 並回到 idle → Task 2 測試 `unlink: silentToken throws → still completes and signs out`、`unlink: signOut throws → still completes`、`Android unlink → Play services 清理失敗仍清掉 email 並回 idle`。
3. **App 開著超過 1 小時**：通行證過期後下一輪要重新取得，不沿用舊 client → Task 2 測試 `keepsClientAcrossRounds is false`，以及 `cloud_sync_test.dart` 照搬鳴潮「non-persistent auth 每輪重新 restore」的案例。
4. **手機上 Google 帳號換成別人**：靜默還原拿到不同 email 時不能默默同步到別的帳號 → Task 2 測試 `restore: different account than the linked email → reauth`。
5. **Windows 按取消後才在瀏覽器按允許**：結果被丟棄、不寫入 token、不撤銷 → Task 1 把既有測試 `cancelLink：等待授權中途取消 → 回到 idle，遲到的 signIn 結果被丟棄並 revoke` 改成斷言 `revokedTokens` 為空。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `lib/services/cloud_sync/cloud_auth.dart`（新） | `CloudAuth` 介面、`CloudLinkResult`、例外、`fetchCloudEmail`、`isInvalidGrant`／`isInsufficientScope`／`isInvalidToken` | 1、2 |
| `lib/services/cloud_sync/google_auth_service.dart` | Windows 實作 `CloudAuth`，不再撤銷 | 1 |
| `lib/services/cloud_sync/cloud_sync_config.dart` | 依平台判斷 `isCloudSyncConfigured` | 1 |
| `lib/state/cloud_sync.dart` | `cloudAuthProvider`、只依賴 `CloudAuth`、每輪 restore | 1、2 |
| `lib/services/cloud_sync/android_cloud_auth.dart`、`google_authorization_gateway.dart`（新）、`pubspec.yaml`／`.lock` | Android 實作 | 2 |
| `lib/widgets/cards/cloud_sync_section.dart`、9 份 ARB、README ×4 | Android 等待文字、簡介用字、自行建置說明 | 3 |
| spec 附錄 B | 驗收紀錄 | 4 |

---

### Task 1: 登入介面抽出、兩平台不再撤銷授權

鳴潮版 commit：`9dde37a`，加上 `53aff8f` 把例外與判斷函式搬到 `cloud_auth.dart` 的部分。

**Files:**
- Create: `lib/services/cloud_sync/cloud_auth.dart`
- Modify: `lib/services/cloud_sync/google_auth_service.dart`、`lib/services/cloud_sync/cloud_sync_config.dart`、`lib/state/cloud_sync.dart`
- Test: `test/helpers/cloud_sync_fakes.dart`、`test/state/cloud_sync_test.dart`、`test/services/cloud_sync/google_auth_service_test.dart`、`test/services/cloud_sync/cloud_auth_test.dart`（新）、`test/services/cloud_sync/cloud_sync_config_test.dart`（新）

**Interfaces:**
- Produces（以鳴潮 `7ab0e10:lib/services/cloud_sync/cloud_auth.dart` 為準）：
  - `abstract class CloudAuth { bool get keepsClientAcrossRounds; Future<CloudLinkResult> link({...}); Future<http.Client?> restoreClient({required String expectedEmail}); Future<void> unlink(); }`（`link` 的具名參數照鳴潮）
  - `class CloudLinkResult { http.Client client; String email; Future<void> Function() commit; }`
  - `CloudLinkCancelledException(String reason)`、`CloudReauthRequiredException`、`CloudScopeMissingException`
  - `Future<String> fetchCloudEmail(http.Client client)`
  - `bool isInvalidGrant(Object e)`、`bool isInsufficientScope(Object e)`（`isInvalidToken` 在 Task 2 加）
  - `final cloudAuthProvider = Provider<CloudAuth>(...)`（`lib/state/cloud_sync.dart`；這個 Task 只回 `GoogleAuthService`，Task 2 再依平台分流）
  - `GoogleAuthService implements CloudAuth`，`keepsClientAcrossRounds == true`，沒有 `revokeToken`。

- [ ] **Step 1: 改測試**
  - `cloud_sync_fakes.dart`：fake auth 實作 `CloudAuth`；保留 `revokedTokens` 以斷言「沒有撤銷」。
  - `cloud_sync_test.dart`：`cancelLink：等待授權中途取消 → 回到 idle，遲到的 signIn 結果被丟棄並 revoke` 改名為 `cancelLink：等待授權中途取消 → 回到 idle，遲到的 signIn 結果被丟棄、不撤銷`，斷言改成 `expect(authService.revokedTokens, isEmpty)`；照搬鳴潮 `9dde37a` 新增的案例（中斷連結只刪本機 token、不撤銷；缺 Drive 權限只丟棄並報 `scopeMissing`、不撤銷）。
  - 新增 `cloud_auth_test.dart`：照搬鳴潮 `7ab0e10` 版的 `isInvalidGrant`／`isInsufficientScope` 兩個 group（`isInvalidToken` 是 `70139fb` 才加的，放 Task 2）；`google_auth_service_test.dart` 移走對應的判斷函式測試（鳴潮 `53aff8f` 的做法）。
  - 新增 `cloud_sync_config_test.dart`：`android: configured when the desktop client id is present`、`windows: needs both id and secret`。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/state/cloud_sync_test.dart test/services/cloud_sync/` → 編譯失敗或斷言失敗（`CloudAuth` 未定義、仍有撤銷）。
- [ ] **Step 3: 實作**：照鳴潮 `9dde37a` 的改法改 `lib/`，例外與判斷函式放進 `cloud_auth.dart`（`53aff8f` 的最終位置）；刪 `revokeToken()` 與所有呼叫點。
- [ ] **Step 4: 跑測試確認通過**：同 Step 2 的指令 → `All tests passed!`；`fvm flutter analyze` → `No issues found!`。
- [ ] **Step 5: Commit**：`refactor(cloudsync): route sign-in through a platform auth interface and stop revoking grants`

### Task 2: Android 用 Play 服務授權 API 連結

鳴潮版 commit：`28bfd10`、`70139fb`、`a870562`、`53aff8f`（其餘部分）、`7ab0e10`。

**Files:**
- Create: `lib/services/cloud_sync/android_cloud_auth.dart`、`lib/services/cloud_sync/google_authorization_gateway.dart`
- Modify: `pubspec.yaml`、`pubspec.lock`、`lib/state/cloud_sync.dart`、`lib/services/cloud_sync/cloud_auth.dart`（加 `isInvalidToken`，以及 `7ab0e10` 版本裡其他 Android 用到的共用部分）、`lib/services/cloud_sync/google_auth_service.dart`（`70139fb` 的 invalid_token 處理）
- Test: `test/services/cloud_sync/android_cloud_auth_test.dart`（新）、`test/services/cloud_sync/google_authorization_gateway_test.dart`（新）、`test/state/cloud_sync_test.dart`、`test/helpers/cloud_sync_fakes.dart`

**Interfaces:**
- Consumes：Task 1 的 `CloudAuth`、`CloudLinkResult`、例外、`fetchCloudEmail`、`isInvalidToken`、`cloudAuthProvider`。
- Produces（以鳴潮 `7ab0e10` 為準）：
  - `abstract class GoogleAuthorizationGateway { Future<String?> silentToken(); Future<String> interactiveToken(); Future<void> clearToken(String token); Future<void> signOut(); }`、`PluginGoogleAuthorizationGateway`
  - `bool isUserCancellation(GoogleSignInException e)`（`google_authorization_gateway.dart`）
  - `AndroidCloudAuth({required GoogleAuthorizationGateway gateway, required http.Client Function() baseClientFactory})`，`keepsClientAcrossRounds == false`
  - `cloudAuthProvider` 依 `isAndroidProvider` 回 `AndroidCloudAuth` 或 `GoogleAuthService`。

- [ ] **Step 1: 加依賴**：`fvm dart pub add google_sign_in:^7.2.0`，確認 lock 版本（Global Constraints）。
- [ ] **Step 2: 寫測試**：整檔照搬鳴潮 `7ab0e10` 的 `android_cloud_auth_test.dart` 與 `google_authorization_gateway_test.dart`；`cloud_auth_test.dart` 補上 `isInvalidToken` group，`google_auth_service_test.dart` 補鳴潮 `70139fb` 的 invalid_token 案例；`cloud_sync_test.dart` 依原神 fake 改寫鳴潮新增的 `Android unlink → Play services 清理失敗仍清掉 email 並回 idle`、`link cancelled by the user → idle without error`、`cloudAuthProvider picks the implementation by platform`，以及 non-persistent auth 每輪重新 restore、啟動只 restore 一次、`link` commit 失敗會關 client 的案例（`28bfd10`、`53aff8f`、`7ab0e10`）。
- [ ] **Step 3: 跑測試確認失敗**：`fvm flutter test test/services/cloud_sync/ test/state/cloud_sync_test.dart` → 編譯失敗（`AndroidCloudAuth` 未定義）。
- [ ] **Step 4: 實作**：兩個新檔以鳴潮 `7ab0e10` 為底整檔照搬；`cloud_sync.dart` 套 `28bfd10`、`53aff8f`、`7ab0e10` 的改法。
- [ ] **Step 5: 跑測試確認通過**：同 Step 3 → `All tests passed!`；全套 `fvm flutter test` 也要過。
- [ ] **Step 6: 確認 Windows 仍可建置**：`fvm flutter build windows --debug --dart-define-from-file=secrets/cloud_sync_defines.json` 成功（`google_sign_in` 沒有 Windows 實作，只是不被呼叫）。
- [ ] **Step 7: Commit**：`feat(cloudsync): sign in on Android with the Play services authorization API`

### Task 3: 設定頁的 Android 文字與 README

鳴潮版 commit：`e3b5944`，以及 `2adf595` 的 README 段落。

**Files:**
- Modify: `lib/widgets/cards/cloud_sync_section.dart`、9 份 `lib/l10n/app_*.arb`、`README.md`、`README_EN.md`、`README_JA-JP.md`、`README_ZH-HANS.md`
- Test: `test/widgets/cloud_sync_section_test.dart`

**Interfaces:**
- Consumes：`isAndroidProvider`、`windowForegroundProvider`、`CloudSyncPhase.awaitingConsent`。
- Produces：ARB key `cloudSyncAwaitingConsentAndroid`。

- [ ] **Step 1: 寫測試**：照搬鳴潮 `e3b5944` 的 `android: awaiting consent shows the Google window hint`（顯示 `cloudSyncAwaitingConsentAndroid` 的文字、取消按鈕仍在）與 `android: leaving consent does not bring the window to front`（`windowForegroundProvider` 沒被呼叫），改寫到原神的測試 helper 上。
- [ ] **Step 2: 跑測試確認失敗**：`fvm flutter test test/widgets/cloud_sync_section_test.dart` → 失敗。
- [ ] **Step 3: ARB**：
  - `cloudSyncAwaitingConsentAndroid`：zh「請在 Google 視窗完成授權...」、zh_Hans「请在 Google 窗口完成授权...」、en「Please finish authorization in the Google window...」、es「Completa la autorización en la ventana de Google...」、fr「Veuillez terminer l'autorisation dans la fenêtre Google...」、ja「Google の画面で認可を完了してください...」、pt_BR「Conclua a autorização na janela do Google...」、th「โปรดให้สิทธิ์ให้เสร็จในหน้าต่าง Google...」、vi「Vui lòng hoàn tất ủy quyền trong cửa sổ Google...」。放在 `cloudSyncAwaitingConsent` 下一行。
  - `cloudSyncIntro` 只換這幾個字，其餘不動：zh「多台電腦間」→「多台裝置間」；zh_Hans「多台电脑间」→「多台设备间」；en「multiple computers」→「multiple devices」；es「varios equipos」→「varios dispositivos」；fr「plusieurs ordinateurs」→「plusieurs appareils」；ja「複数の PC 間」→「複数のデバイス間」；pt_BR「vários computadores」→「vários dispositivos」；th「คอมพิวเตอร์หลายเครื่อง」→「หลายอุปกรณ์」；vi「nhiều máy tính」→「nhiều thiết bị」。
  - `fvm flutter gen-l10n`。
- [ ] **Step 4: 實作**：照 `e3b5944` 改 `cloud_sync_section.dart`（Android 用新字串；離開 `awaitingConsent` 時只有非 Android 才呼叫 `windowForegroundProvider`）。
- [ ] **Step 5: README**：四份 README 的「雲端同步憑證（選用）」第 3 點後加第 4 點，內容照鳴潮 `2adf595`，套件名稱換成 `tw.reh.genshin.gacha`；英日簡體照各自 README 既有語氣翻。
- [ ] **Step 6: 跑測試確認通過**：`fvm flutter test` → `All tests passed!`；`fvm flutter analyze` → `No issues found!`。
- [ ] **Step 7: Commit**：`feat(cloudsync): show Android-specific consent hint and device-neutral intro`（README 可分一個 `docs(readme): explain the Android OAuth client for cloud sync`）。

### Task 4: 實機驗收與附錄 B

**需要使用者在場**：模擬器要登入 Google 帳號；手機要使用者明講「接好了／可以測」才能動；Windows 實體輸入要當次授權。

- [ ] **Step 1: 模擬器（Pixel_8a，Google Play 映像，debug 版帶 `--dart-define-from-file=secrets/cloud_sync_defines.json`）**：依 spec 第六節逐項驗：帳號選擇畫面按返回不顯示錯誤；連結後同步下電腦的記錄並補抓物品圖；同一個程序開超過 1 小時後「立即同步」成功；測完在 App 中斷連結。
- [ ] **Step 2: 手機（ROG Phone，debug 版）**：連結、顯示 email；記錄同步到電腦；殺掉重開自動同步；手機中斷連結後電腦照常同步；再連結跳帳號選擇。測完依記憶「手機測完要真的還原」收尾。
- [ ] **Step 3: Windows**：連結、同步；電腦中斷連結後手機照常同步；重新連結（瀏覽器授權）正常。
- [ ] **Step 4: 附錄 B**：在 spec 加「附錄 B：原神版驗收結果」，記各平台結果、未驗證項目、實作坑；狀態行改為驗收完成。
- [ ] **Step 5: Commit**：`docs(spec): record the cloud sync sign-in device check`
