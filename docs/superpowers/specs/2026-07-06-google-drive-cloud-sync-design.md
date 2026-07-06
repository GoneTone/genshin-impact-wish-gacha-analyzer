# Google Drive 雲端同步 — Design

**Date:** 2026-07-06
**Branch:** feat/cloud-sync
**Status:** Approved（三段設計皆經使用者確認）
**References:** 對齊姐妹專案 wuthering-waves-convene-gacha-analyzer PR #45（同步本體）、#46（README）、#47（同步後補抓物品資料）

## 1. Motivation & Goals

使用者的卡池記錄目前只存在本機（每帳號一個 JSON 檔），跨電腦搬遷得靠手動匯出／匯入。本功能讓使用者登入**自己的 Google 帳號**，把資料自動備份到自己的 Google 雲端硬碟，並在多台電腦間自動同步。UI/UX 與同步行為全面對齊姐妹專案（鳴潮版）已實戰驗證的做法。

### 目標

- 設定頁新增「雲端同步」區塊：連結 Google 帳號、自動同步開關（登入後預設開啟）、「立即同步」手動按鈕、中斷連結。
- 同步檔格式**與手動匯出完全相同**（`AccountsBundle`，`schema_version: 1`），複用現有匯出／匯入／合併程式碼。
- 自動雙向同步：App 啟動、本機資料變動後自動跑「下載 → 合併 → 上傳」。
- 同步合併出新記錄時自動補抓 HoYoWiki 物品資料與圖片（對齊姐妹專案 PR #47）。
- 同步永不刪除資料；唯一例外是使用者刪帳號時勾選「同時從雲端移除」。

### 非目標

- 不支援 Google 以外的雲端服務。
- 不做選擇性同步（部分帳號）——一律同步全部帳號。
- 不做 etag 樂觀鎖／衝突版本管理——非破壞性合併＋last-writer-wins 已足夠（見 §3）。
- 不做定時輪詢同步（Timer）——只有連結後首輪、啟動、資料變動、手動四類觸發（見 §5）。
- 不同步 UI 偏好（themeMode／locale 等），僅同步 `AccountsBundle` 既有內容（記錄＋別名＋lastActiveUid）。

## 2. 雲端檔案佈局與權限

- **存放位置**：Google Drive 隱藏的 `appDataFolder`（`drive.appdata` scope），使用者在雲端硬碟介面看不到、也改不到，不會被誤刪誤改。
- **檔案**：單一檔案 `genshin_gacha_sync.json`，內容即 `exportAccounts` 產出的 `AccountsBundle` JSON——與手動匯出檔同格式，拿下來可直接餵給「匯入」功能。
- **OAuth scopes**：`https://www.googleapis.com/auth/drive.appdata`（最小權限）＋ `email`（僅用於設定頁顯示已連結帳號）。
- **OAuth 用戶端**：為本專案在 Google Cloud Console **另建**專案與 Desktop app 類型 client（不與鳴潮 App 共用），`appDataFolder` 兩 App 完全隔離；就算出現外來檔，`importAccounts` 既有的 `accountsBundleAppId` 驗證也會擋掉。憑證**不進 repo**（GitHub push protection 會攔截 Google OAuth 憑證），改於建置時注入（`--dart-define-from-file`：本機用 git-ignored 的 `secrets/cloud_sync_defines.json`，CI 由 repo secrets `CLOUD_SYNC_CLIENT_ID`／`CLOUD_SYNC_CLIENT_SECRET` 產生同名檔）；未注入時 `isCloudSyncConfigured` 為 false、功能優雅停用——代價是 fork 者需自備憑證才能啟用同步。

## 3. 同步演算法

一輪同步 = **下載 → 合併 → 上傳**：

1. **下載**：從 appDataFolder 找 `genshin_gacha_sync.json` 下載；不存在視為空 bundle；檔案損毀（JSON 壞掉）視為不存在，以本機內容上傳自癒。
2. **合併**：走現有匯入解析路徑——`importAccounts`（含 app id／schema 驗證）→ `BannerStorage.mergeWith` 非破壞性合併進本機 → 落盤。不寫任何新的合併邏輯。與手動匯入的差異：**silent**（不開帳號 picker、全帳號合併）。
3. **上傳**：以合併後的本機全帳號 `exportAccounts` 打包，上傳覆蓋雲端檔。

**合併細節**：

- 雲端 bundle 的 `last_active_uid` 在同步時**不套用**（手動匯入才會還原），避免靜默同步偷偷切換使用者目前作用中的帳號。實作語意：本機已有作用中帳號一律 local-wins；本機完全沒有帳號（如新機首次同步）才會採用雲端的 `last_active_uid`。
- 別名衝突：本機已有別名以本機為準，本機沒有才採用雲端的。

**併發語意**：多台電腦同時同步採 last-writer-wins。因合併只增不減，最壞情況是另一台的新記錄晚一輪才收斂，不會遺失資料，故不需樂觀鎖。

**Schema 保護**：雲端檔 `schema_version` 比本機支援的新時（`UnsupportedSchemaVersionException`），該輪**整個跳過**——不合併、不上傳覆蓋——並提示使用者更新 app。避免舊版 app 用舊格式蓋掉新版資料。

**單飛鎖**：以 `synchronized` 套件確保同時只跑一輪；進行中再被觸發就記一個 pending 旗標，該輪結束後補跑一輪。

## 4. 同步後補抓物品資料（對齊姐妹專案 PR #47）

同步合併出本機沒見過的新記錄時（典型情境：第二台電腦首次同步），自動補抓缺漏的 HoYoWiki 物品資料與圖片，不然這些記錄會停在缺圖 placeholder，要等使用者手動「更新」才補齊。

- **觸發條件**：同步輪**成功**且合併出新記錄 → 同步收尾後 fire-and-forget 觸發；沒有新增記錄的同步輪完全不觸發（不多彈視窗、不浪費流量）。
- **呈現**：走與既有「更新物品資料」相同的進度管線（`app_shell` 既有的 `ref.listen` 進度對話框機制）——即時顯示取得物品資料／下載圖片進度，結束顯示物品資料更新摘要。完成狀態**帶物品資料摘要、不帶匯入摘要**（避免顯示成手動匯入的結果文案）。複用既有 i18n，無新字串。
- **實作形態**：`GachaRepository` 新增 `fetchItemImagesForCloudSync()`——busy 檢查＋互斥旗標＋可取消 client，收尾模式比照既有匯入流程；`CloudSyncNotifier.syncNow` 自合併結果取得新增記錄清單，成功收尾後觸發。
- **防護**：更新／匯入進行中或 bootstrap 未完成時直接略過，缺圖留待下次手動「更新」補齊；補抓 best-effort，單筆失敗僅記 `cloudsync.sync` log、照常收尾；進度框可取消。

## 5. 觸發時機

| 入口 | 模式 | 行為 |
|------|------|------|
| 連結成功後 | manual | 立刻同步一次 |
| App 啟動時 | silent | 已連結且開關開啟才跑（`app_shell` bootstrap 完成後）；失敗不打擾 |
| 本機資料變動後 | silent | 擷取到新記錄、匯入完成、別名變更、帳號刪除 → debounce 5 秒＋內容指紋去重後同步 |
| 設定頁「立即同步」 | manual | 手動觸發，失敗明確顯示錯誤 |

## 6. 登入／登出與 token 管理

### 登入（「連結 Google 帳號」）

1. `url_launcher` 開**系統瀏覽器**跑 Google 授權頁；`googleapis_auth`（`auth_io`）的 installed-app 流程自動在本機開臨時 localhost port 接收授權回跳，使用者按「允許」即完成。不用 embedded WebView（Google 封鎖，回 `403 disallowed_useragent`）。
2. 授權當下驗證**實授 scopes**：使用者漏勾雲端硬碟權限 → 立即 revoke 該授權並顯示指引（授權完成頁就地顯示，見 §8）。
3. 授權成功 → 存 token、取 email → 立刻觸發第一輪同步；等待授權結束後用 `window_manager` 把 App 視窗帶回前景。
4. 等待授權期間設定頁顯示等待狀態＋「取消」。實作限制沿用姐妹專案：`clientViaUserConsent` 的 localhost 監聽無法中途中止，取消後若使用者仍在瀏覽器完成授權，該次授權結果會被丟棄並即時 revoke，不會寫入本機。

### Token 儲存

- **refresh token（敏感）**：存 `flutter_secure_storage`（Windows 底層 DPAPI，綁定 Windows 使用者），不進 shared_preferences。
- **非敏感狀態**：已連結 email、自動同步開關、上次同步時間（`lastSyncedAt`）、待雲端移除清單 → `AppSettings`／`SettingsStorage`（`pref.cloudSync*` key）＋ `SettingsNotifier` setter，沿用既有 settings 慣例。
- access token 由 `googleapis_auth` 自動續期 client 管理，不自寫刷新邏輯。
- refresh token 失效（使用者於 Google 端撤銷授權 → `invalid_grant`）：停止自動同步、狀態標「需要重新連結」，不無限重試。

### 登出（「中斷連結」）

- 向 Google 打 revoke（盡力而為，失敗不阻擋登出）→ 刪本機 refresh token → 清 settings 相關欄位（email、開關、上次同步時間）。
- **待雲端移除清單保留不清**：使用者刪帳號的意圖在重新連結後仍應補刪。
- 本機卡池記錄不動；**雲端檔保留**（重連或他機仍可同步回來）。

## 7. 刪帳號的雲端整合

- 現有刪除帳號確認對話框加勾選「同時從雲端同步資料移除此帳號」——僅已連結時顯示，預設不勾（`confirm_dialog.dart` 加 checkbox 支援）。
- 勾選後該 UID 加入 settings 的**待雲端移除清單**，並觸發一輪同步。
- 同步時先把清單內 UID 從**下載的雲端 bundle 剔除**（防止剛刪的帳號被合併「復活」），上傳成功後才自清單移除該 UID。
- 離線也安全：清單留存，下次同步成功時補刪。

## 8. UI（設定頁「雲端同步」區塊）

UI/UX 完全照姐妹專案的版面與互動。落點：「資料管理」區塊正下方，`SectionCard`＋`Icons.cloud_sync_outlined`，元件放 `lib/widgets/cards/cloud_sync_section.dart`。

- **未設定憑證**（`isCloudSyncConfigured == false`）：只顯示一行 muted 說明文字，功能優雅停用。
- **未連結**：一段說明（「登入 Google 帳號後，卡池記錄會自動備份並在多台電腦間同步」）＋「連結 Google 帳號」`FilledButton.icon`（`Icons.link`）；授權失敗／缺權限時在按鈕上方顯示 danger 色錯誤文字。
- **等待授權中**：spinner＋提示＋「取消」`TextButton` 一列（未連結與重連兩處共用同一元件）。
- **已連結**：
  - 「已連結為 {email}」（直接顯示，不做遮蔽）。
  - 「自動同步」`SwitchListTile`（含副標說明，登入後預設開啟）。
  - 狀態列：成功顯示 `RelativeTimeText` 相對時間；從未同步顯示「尚未同步」；錯誤依 token（`busy`／`schemaTooNew`／`authFailed`／`scopeMissing`／網路）顯示 danger 色簡短原因；「需要重新連結」顯示警告＋重連按鈕。
  - 「立即同步」`FilledButton.icon`（同步中變 spinner＋停用）＋「中斷連結」`OutlinedButton.icon`（`showConfirmDialog` 確認，說明本機與雲端資料皆保留），按鈕用 `Wrap` 排列。
- **授權完成頁**：瀏覽器內顯示的多語言自訂 HTML 頁（完全自足、隨系統深淺色、文案經 HTML escape），用回跳 URL 的 `scope` 參數在缺 `drive.appdata` 權限時就地切換成「缺少權限」指引文案。
- **授權結束帶回前景**：`ref.listen` 偵測離開等待授權態時，透過 `window_manager` 把 App 視窗帶回前景。
- 所有新字串進 9 個已有實體翻譯的 ARB（zh 起手 → zh_Hans、en、ja、es、fr、pt_BR、th、vi），空殼 ARB 留給 Crowdin pipeline；全形標點、省略號用半形 `...`。

## 9. 錯誤處理

| 情境 | 行為 |
|------|------|
| silent 同步失敗（啟動／資料變動觸發） | 不彈窗；更新設定頁狀態列＋log，下次觸發再試 |
| manual 同步失敗 | 狀態列明確顯示錯誤，區分：網路問題／授權失效／雲端 schema 過新 |
| 授權失效（`invalid_grant`） | 停止自動同步、標「需要重新連結」 |
| 雲端 schema 過新 | 跳過整輪（不上傳），提示更新 app |
| 雲端檔損毀 | 視為不存在，以本機內容上傳自癒 |

## 10. Logging

新增 `cloudsync.*` logger 樹：

- `cloudsync.auth`：登入／登出／token 刷新／revoke 結果——**絕不記 token 內容**。
- `cloudsync.sync`：每輪的觸發來源、下載檔案大小、合併結果（added／duplicate）、上傳結果、耗時、失敗原因、補抓物品資料結果。
- UID 過 `sanitizeUid`、URL 過 `sanitizeUrl`。

## 11. 程式碼落點

| 檔案 | 職責 |
|------|------|
| `lib/services/cloud_sync/cloud_sync_config.dart` | dart-define 憑證讀取、`isCloudSyncConfigured` |
| `lib/services/cloud_sync/google_auth_service.dart` | OAuth 授權流程、scope 驗證、revoke |
| `lib/services/cloud_sync/token_store.dart` | refresh token 存取（包 `flutter_secure_storage`） |
| `lib/services/cloud_sync/cloud_sync_remote.dart` | appDataFolder 檔案查找／下載／上傳（包 `googleapis` Drive v3） |
| `lib/services/cloud_sync/cloud_sync_service.dart` | 「下載→合併→上傳」編排、待移除清單剔除、schema 保護 |
| `lib/state/cloud_sync.dart` | `CloudSyncNotifier`（NotifierProvider）：連結狀態、同步狀態機、debounce、觸發入口 |
| `lib/widgets/cards/cloud_sync_section.dart` | 設定頁區塊 UI＋授權完成頁 HTML |
| `lib/pages/settings_page.dart` | 掛載 `CloudSyncSection` |
| `lib/state/gacha_repository.dart` | silent 合併入口、`fetchItemImagesForCloudSync()`、資料變動通知 |
| `lib/services/settings_storage.dart`／`lib/state/settings.dart` | `AppSettings` 加 `cloudSync*` 欄位與 setter |
| `lib/widgets/cards/account_management.dart`／`lib/widgets/dialogs/confirm_dialog.dart` | 刪帳號雲端移除勾選 |
| `lib/pages/app_shell.dart` | 啟動觸發掛載 |
| `.github/workflows/release-windows.yml`／`scripts/build_release.ps1` | CI 憑證注入 |
| `README.md`／`README_EN.md`／`README_JA-JP.md`／`README_ZH-HANS.md` | 功能條目、憑證開發指引、隱私敘述修正 |

**新依賴**：`googleapis`（僅 import drive v3）、`googleapis_auth`、`flutter_secure_storage`。

## 12. README（對齊姐妹專案 PR #45／#46）

- 四份 README「功能與特色」新增雲端同步條目（連結自己的 Google 帳號、自動備份到 Google 雲端硬碟、多台電腦雙向同步、刪帳號可勾選一併從雲端移除）。
- 修正隱私承諾：「所有資料留在本機，不上傳」改為「預設留在本機；雲端同步為選擇性功能，啟用後也只會備份到您自己的 Google 雲端硬碟」——避免 README 敘述與新功能矛盾。
- 補「雲端同步憑證」開發指引（fork 者如何自備憑證）。

## 13. 測試策略

- `google_auth_service`／`cloud_sync_remote` 抽介面；`cloud_sync_service` 對 mock 介面寫單元測試：
  - 雲端無檔首輪 → 直接上傳本機資料。
  - 雙向合併：雲端多的補進本機、本機多的上傳。
  - 雲端 schema 過新 → 跳過且**不上傳**。
  - 待移除清單：下載剔除、上傳成功後清除、失敗保留。
  - `invalid_grant` → 標記需重連、停止自動同步。
- 既有合併邏輯（`BannerStorage.mergeWith`）已有測試，不重測。
- 同步後補抓：合併出新記錄 → 補抓啟動且完成狀態帶物品資料摘要、不帶匯入摘要；無新增 → 不觸發。
- `CloudSyncSection` 未連結／已連結／等待授權三態 widget test；刪帳號 checkbox widget test。
- 驗收：`fvm flutter analyze` 無 issue、`fvm flutter test` 全綠；實機手動驗證一次真實 Google 授權＋同步（OAuth 無法自動化）。

## 14. 合併前注意

- 需在 Google Cloud Console 為本專案另建專案與 OAuth 同意畫面＋ Desktop app client。
- 需在 repo settings 新增 Actions secrets：`CLOUD_SYNC_CLIENT_ID`、`CLOUD_SYNC_CLIENT_SECRET`，release 建置才會啟用同步功能。
