# Play 上架與更新（子專案 7）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓原神 Android 版能用正式金鑰簽章、由 CI 上傳到 Play 內部測試，App 內以 Play 判斷新版並做彈性更新，全平台換上新圖示。

**Architecture:** 以鳴潮 repo（`E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`，以下稱「鳴潮」）`master` 上的最終檔案為底，換套件名稱與術語後套到原神。新檔整份照搬；原神已有、結構已分歧的檔案（`app_shell.dart`、`settings_page.dart` 等）只套用各任務列出的鳴潮 commit 中與 Play 更新有關的 hunk。

**Tech Stack:** Flutter（FVM）、Riverpod、`in_app_update` 5.x、Kotlin（`com.google.android.play:app-update`）、GitHub Actions、Inno Setup、`package:image`。

**Spec:** `docs/superpowers/specs/2026-11-23-play-release-design.md`

## Global Constraints

- 名稱替換：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；applicationId／Kotlin 套件 `tw.reh.wuwa.gacha` → `tw.reh.genshin.gacha`；repo `wuthering-waves-convene-gacha-analyzer` → `genshin-impact-wish-gacha-analyzer`；註解與文件中的「喚取」→「祈願」、「鳴潮」→「原神」、「庫洛遊戲」→「HoYoverse」。
- 照搬後 grep 新增或修改的檔案，不可殘留 `wuwa`、`wuthering`、`鳴潮`、`鸣潮`、`喚取`、`唤取`、`Kuro`（刻意指向鳴潮的連結除外）。
- 新增 ARB key 必須 31 個 ARB 全部有（`af ar ca cs da de el en es fi fr he hu it ja ko nl no pl pt pt_BR ro ru sr sv th tr uk vi zh zh_Hans`），值取鳴潮同 key 同語言，`@key` 說明一併帶上；改完跑 `fvm flutter gen-l10n`。
- Windows 行為不得改變：`isAndroidProvider` 為 false 時走原本的 GitHub 檢查。
- log 訊息英文，Logger 沿用 `release` 等既有名稱；例外寫成 `warning('...', e, st)`。
- 每個宣告要有一行 `///` dartdoc；註解與 dartdoc 用繁中全形標點；UI 結尾省略號用半形 `...`。
- commit message 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；commit 一律用 PowerShell（GPG 簽章）；不要 push。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。
- 不可讀取或印出 `secrets/`、`android/key.properties`、`*.jks`、服務帳戶 JSON 的內容；不可開 `G:/_APK_Key/.../pw.txt`、不可 cat／grep `~/.crowdin.yml`。
- git 內一律 LF；`.ps1`、`.iss`、`.isl`、`.cmd`、`.bat` 本機保留 CRLF。
- 實機（手機）只在使用者明講「接好了／可以測」後操作；模擬器可直接用。

## Review Focus

1. Windows 上的「檢查更新」與啟動自動檢查仍只查 GitHub、從不呼叫 Play gateway（Task 2 加測試：非 Android 時 gateway 被呼叫就失敗）。
2. 沒有 `android/key.properties` 時 `fvm flutter build apk --release` 仍能建置（退回 debug 金鑰），開發者不受影響（Task 6 驗證步驟）。
3. 「目前無法在 App 內更新」提示與「前往 Google Play」按鈕在 320 dp 寬下，31 種語言都不溢出（鳴潮只測核心四種；Task 3 把測試擴到全部語言）。
4. release 版（R8）裝上後能啟動，`in_app_update`／Play Core 的類別沒有被縮掉（Task 8 在模擬器實跑）。
5. 從鳴潮複製的 31 種譯文沒有殘留鳴潮遊戲名稱（Task 2 的 grep 檢查）。

---

### Task 1: 版本代碼換算

**Files:**
- Create: `lib/services/android_version_code.dart`、`tool/android_version_code.dart`
- Test: `test/services/android_version_code_test.dart`、`test/tool/android_version_code_test.dart`

**Interfaces:**
- Produces: `int androidVersionCodeForTag(String tag)`（不合法拋 `FormatException`）；`String? tagForAndroidVersionCode(int code)`；`int runVersionCodeCli(List<String> args, StringSink out, StringSink err)`（成功 0、格式錯誤 1、參數數量錯誤 64，輸出 `VERSION_CODE=`、`BUILD_NAME=` 兩行）。

- [ ] **Step 1：照搬兩個測試檔**（鳴潮同路徑，只換 import 套件名）。測試必須包含：`v1.8.1`→`1080199`、`v1.9.0-rc.2`→`1090002`、`v1.9.0`→`1090099`；`v01.9.0`、`v1.9.0-rc.0`、`v1.9.0-rc.99`、`v2100.0.0`、`v1.100.0`、`1.9.0` 拋 `FormatException`；`tagForAndroidVersionCode(1090002)`=`'v1.9.0-rc.2'`；CLI 參數數量錯誤回 64。
- [ ] **Step 2：** `fvm flutter test test/services/android_version_code_test.dart test/tool/android_version_code_test.dart`，預期因檔案不存在失敗。
- [ ] **Step 3：照搬兩個實作檔**（鳴潮 `master` 版本，換 import）。
- [ ] **Step 4：** 同 Step 2 的指令，預期全過；另跑 `fvm dart run tool/android_version_code.dart v1.9.0-rc.2`，stdout 為 `VERSION_CODE=1090002` 與 `BUILD_NAME=1.9.0-rc.2`。
- [ ] **Step 5：commit** `feat(android): map release tags to Play version codes`

### Task 2: Android 改以 Play 判斷有沒有新版

鳴潮對照 commit：`cd098d1`、`9765148`、`b28aa0b`、`e671736`、`3a648e7`（只取 `lib/services/play_update.dart`、`lib/state/app_release.dart`、`lib/pages/settings_page.dart`、ARB、`pubspec.yaml` 與對應測試的部分），以及 `269aac7` 之後的 `master` 狀態。

**Files:**
- Modify: `pubspec.yaml`（`in_app_update: ^5.0.0`）、`pubspec.lock`
- Create: `lib/services/play_update.dart`（先不含下載進度的 `PlayDownloadProgress`／`playDownloadProgressProvider`，那是 Task 4）
- Modify: `lib/state/app_release.dart`（以鳴潮 `master` 為底，保留原神多出的 dartdoc）、`lib/pages/settings_page.dart`（手動檢查失敗顯示 `updateErrorPlay` 的 hunk）
- Modify: 31 個 `lib/l10n/app_*.arb`：新增 `updateButtonUpdate`、`updateNotesUnavailable`、`updateDownloadingMessage`、`updateDownloadedMessage`、`updateRestartAction`、`updateInAppUnavailable`、`updateErrorPlay`（`updateOpenPlayStore`、`updateChecking` 原神已有，不動）
- Test: `test/state/app_release_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `tagForAndroidVersionCode`。
- Produces（與鳴潮同名）：`PlayUpdateInfo`、`enum PlayDownloadResult`、`abstract class PlayUpdateGateway { Future<PlayUpdateInfo> check(); Future<PlayDownloadResult> downloadFlexible(); Future<void> completeFlexible(); }`、`InAppUpdatePlayGateway`、`playUpdateGatewayProvider`；`app_release.dart` 的 Android 分支產生的 `ReleaseAvailable` 帶 Play 版本資訊，供 Task 3 的對話框使用。

- [ ] **Step 1：照搬鳴潮 `test/state/app_release_test.dart` 中 Play 相關的 group／test**，並新增一個測試：`isAndroidProvider` 覆寫為 false、`playUpdateGatewayProvider` 覆寫成任何方法被呼叫就 `fail(...)` 的 fake，啟動檢查與手動檢查都仍走 GitHub 的既有結果（Review Focus 1）。
- [ ] **Step 2：** `fvm flutter test test/state/app_release_test.dart`，預期新測試編譯失敗。
- [ ] **Step 3：實作**：加套件、建 `play_update.dart`、改 `app_release.dart` 與 `settings_page.dart`、補 ARB 後 `fvm flutter gen-l10n`。
- [ ] **Step 4：** 跑 Step 2 的指令全過；`grep -n -i -E "wuthering|鳴潮|鸣潮|kuro" lib/l10n/app_*.arb` 新增的 7 個 key 沒有命中（Review Focus 5）。
- [ ] **Step 5：commit** `feat(update): check Google Play for updates on Android`

### Task 3: 彈性更新流程與提示

鳴潮對照 commit：`f89f995`、`282c4ee`、`b28aa0b`、`182fd2f`、`e671736`、`3a648e7`、`53bfb6b`、`be5bd56`。

**Files:**
- Create: `lib/state/play_update_download.dart`、`test/helpers/fake_url_launcher.dart`、`test/state/play_update_download_test.dart`、`test/widgets/dialogs/new_version_dialog_test.dart`
- Modify: `lib/widgets/dialogs/new_version_dialog.dart`、`lib/widgets/dialogs/release_notes_content.dart`、`lib/pages/app_shell.dart`（重新啟動提示、失敗提示與「前往 Google Play」按鈕放在 SnackBar 內容裡）、`pubspec.yaml` dev 依賴（照 `182fd2f`）
- Test: `test/pages/app_shell_test.dart`（套用上述 commit 的測試 hunk）

**Interfaces:**
- Consumes: Task 2 的 `PlayUpdateGateway`、`PlayUpdateInfo`、`PlayDownloadResult`、`playUpdateGatewayProvider`。
- Produces: `enum PlayDownloadPhase`、`PlayUpdateDownloadNotifier`（`start()`、`syncWithPlay(PlayUpdateInfo)`、`install()`）、`playUpdateDownloadProvider`。

- [ ] **Step 1：照搬上述測試**；`53bfb6b` 的 320 dp 失敗提示測試改成對 `AppLocalizations.supportedLocales` 全部語言跑（Review Focus 3）。
- [ ] **Step 2：** `fvm flutter test test/state/play_update_download_test.dart test/widgets/dialogs/new_version_dialog_test.dart test/pages/app_shell_test.dart`，預期失敗。
- [ ] **Step 3：實作**（新檔照搬鳴潮 `master`；`app_shell.dart`、對話框只套 Play 相關 hunk，原神既有的 9b、10、12 改動保留）。
- [ ] **Step 4：** Step 2 的指令全過。若某語言在 320 dp 溢出，修元件的換行，不縮短譯文。
- [ ] **Step 5：commit** `feat(update): flexible Play update flow with restart prompt`

### Task 4: 下載進度

鳴潮對照 commit：`85351a5`、`93bc81f`。

**Files:**
- Create: `android/app/src/main/kotlin/tw/reh/genshin/gacha/PlayUpdateProgressChannel.kt`、`lib/widgets/play_download_progress.dart`
- Modify: `MainActivity.kt`（註冊 channel）、`android/app/build.gradle.kts`（`com.google.android.play:app-update` 依賴，版本照鳴潮）、`lib/services/play_update.dart`（`PlayDownloadProgress`、`playDownloadProgressProvider`）、`lib/pages/app_shell.dart`（下載中常駐 SnackBar，以保存的 controller 關閉）
- Test: `test/pages/app_shell_test.dart`（`85351a5` 的測試 hunk）

**Interfaces:**
- Produces: `typedef PlayDownloadProgress = ({int bytes, int total})`、`playDownloadProgressProvider`、`PlayDownloadProgressBar`（total 為 0 時是不確定進度條）。EventChannel 名稱照鳴潮，只換套件前綴。

- [ ] **Step 1：照搬測試 hunk**（進度 SnackBar 出現、百分比與大小、total 未知時不確定進度條、完成或失敗只關掉這一條）。
- [ ] **Step 2：** `fvm flutter test test/pages/app_shell_test.dart`，預期失敗。
- [ ] **Step 3：實作。**
- [ ] **Step 4：** 測試全過；`fvm flutter build apk --debug` 成功（Kotlin 編得過）。
- [ ] **Step 5：commit** `feat(android): show download progress while Play fetches an update`

### Task 5: 新 App 圖示與自適應圖示

鳴潮對照 commit：`884323c`、`64cff46`（圖示路徑）、`012958f`（Play 圖示改放 `docs/images/play-store/`）。

**Files:**
- Replace: `tool/app_icon_source.png`
- Modify: `tool/generate_app_icons.dart`（加自適應前景與 Play 512 輸出；保留原神已有的啟動畫面圖示輸出；檔頭說明改成「滿版正方形、不含圓角與透明」）
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`、`android/app/src/main/res/values/ic_launcher_background.xml`、各密度 `ic_launcher_foreground.png`、`docs/images/play-store/icon-512.png`
- Regenerate: `assets/icons/**/app_icon.png`、`windows/runner/resources/app_icon.ico`、`mipmap-*/ic_launcher.png`、`assets/splash/icon.png` 與 `flutter_native_splash:create` 的輸出

- [ ] **Step 1：產生主檔**：讀 spec 4.7 的附件路徑，依 spec 4.7 的「處理」補滿四角，存成 1024×1024 RGB PNG 到 `tool/app_icon_source.png`；驗證四個角像素都不是接近白色（每個通道 < 80）。處理腳本放 scratchpad，不進 repo。
- [ ] **Step 2：** 擴充 `generate_app_icons.dart`（前景＝整張縮到畫布 2/3、外圍用邊緣像素延伸；Play 圖示轉 4 通道），`ic_launcher_background` 取主檔左右邊緣中段的平均色（附同鳴潮的 XML 註解）。
- [ ] **Step 3：** `fvm dart run tool/generate_app_icons.dart` 每個輸出都印 `✓`；再跑 `fvm dart run flutter_native_splash:create`。
- [ ] **Step 4：目視檢查**：拼一張預覽（legacy 192 px、前景套 72dp 圓形與方圓形遮罩、Play 512、Windows 16/32 px），主體不被裁、四周沒有白邊或接縫。`git grep` 確認沒有其他地方引用舊圖。
- [ ] **Step 5：** analyze、test 全過後 **commit** `feat(branding): replace the app icon on all platforms and add an Android adaptive icon`

### Task 6: 簽章、發版 CI、安裝檔與發版文件

鳴潮對照：`481a602`（`build.gradle.kts` 簽章）、`release.yml` 最終版（`87edab3`、`1252c76`、`308587a`、`24c83e0`、`b263eea`、`6429ae8`、`e420832` 的結果）、`e04f5fa`（`ci.yml`）、`1a6a5ca`（安裝檔）、`64cff46`（`.gitignore` 的 `/private/`）、`f8cce2f`、`ea4f0c5`（工具）。

**Files:**
- Modify: `android/app/build.gradle.kts`（讀 `android/key.properties`，不存在時 release 用 debug 金鑰；檔頭 `import java.util.Properties`）、`android/.gitignore`（`key.properties`、`**/*.keystore`、`**/*.jks`）、`.gitignore`（`/private/`）
- Create: `.github/workflows/release.yml`（鳴潮 `master` 版本照搬換名）；Delete: `.github/workflows/release-windows.yml`
- Modify: `.github/workflows/ci.yml`（`head_ref` 走 `env: HEAD_REF`）、`scripts/build_installer/installer.iss`（數字版本欄位去掉 `-rc.N`，完整字串放文字版本欄位；保持 CRLF）、`.github/release-footer.md`（防毒說明改為「Windows 版…」／「The Windows version…」，其餘不動）、`docs/release.md`（以鳴潮 `master` 版本為底換名）
- Create: `tool/apk_signer_certs.py`、`tool/play_upload_internal.py`（照搬換名）

- [ ] **Step 1：** 套用以上檔案。`release.yml` 的 AdMob／雲端同步 secrets 缺少時只發 `::warning::`；上傳金鑰或服務帳戶缺少時失敗（spec 4.4）。
- [ ] **Step 2：** `go run github.com/rhysd/actionlint/cmd/actionlint@latest .github/workflows/*.yml` 沒有錯誤（沒有 Go 就記下未檢查，告知控制者）。
- [ ] **Step 3：** 確認 `android/key.properties` 不存在後跑 `fvm flutter build apk --release`，建置成功（Review Focus 2）；`git status` 不出現任何金鑰檔。
- [ ] **Step 4：** 用 Inno Setup 編譯器以 `MyAppVersion=1.9.0-rc.1` 試編 `installer.iss`（`build_release.ps1` 的參數方式），不出現 `VersionInfoVersion is invalid`；沒有 ISCC 就記下未檢查。
- [ ] **Step 5：** analyze、test 全過後 **commit**，可分兩個：`build(android): sign release builds with an upload key when present`、`ci(release): build Windows and Android together and upload to the Play internal track`（含 ci.yml、安裝檔、頁尾、docs、工具）。

### Task 7: 本機上架文件（不進版控）

**Files:**
- Create（git-ignored）：`private/play-store/README.md`、`listing.md`、`data-safety.md`、`review-notes.md`，以鳴潮同名檔為底。

- [ ] **Step 1：** 確認 `git check-ignore private/play-store/README.md` 有輸出（Task 6 的 `.gitignore` 生效）。
- [ ] **Step 2：** 改寫四個檔案，依 spec 4.6 與第五節：
  - `listing.md`：四種語言的名稱照 spec 4.6（逐一數字數 ≤ 30），簡短說明 ≤ 80、完整說明 ≤ 4000；說明開頭「非官方工具，與 HoYoverse 無關」；讀取方式照原神 Android 的實際行為（logcat 監看、無線偵錯、root、手動貼網址，沒有「Android 10 以下直接讀檔」）；圖片來源 HoYoWiki；有原生廣告；網站欄位寫明需有 `app-ads.txt` 的網域、由使用者決定網址。
  - `data-safety.md`、`review-notes.md`：換成原神的實際行為（spec 4.6），審查說明用手動貼網址測試。
  - `README.md`：spec 第五節的步驟順序、secrets 一覽（名稱與 `release.yml` 實際讀的一致）、每次發版步驟、keytool 指令（密碼由使用者在終端機輸入）。
- [ ] **Step 3：** 用腳本數各語言名稱與說明的字元數，列在回報裡。不 commit。

### Task 8: release 版實跑與交接

- [ ] **Step 1：** 在模擬器（不是使用者手機）裝 Task 6 建的 release APK（`adb install --user 0`），啟動後 `adb logcat -b crash` 沒有東西、停在首頁；從設定頁「檢查更新」顯示 `updateErrorPlay` 的訊息（非 Play 安裝）（Review Focus 4）。結束後解除安裝、還原模擬器原本裝的版本。
- [ ] **Step 2：** 在 spec 末尾新增「附錄：實作結果」，記下與鳴潮不同或實作時才發現的事（例如背景色值、自適應比例、actionlint／ISCC 有沒有實際跑）。
- [ ] **Step 3：** commit `docs(spec): record the Play release implementation results`。
- [ ] **Step 4：** 交給使用者：spec 第五節的步驟 1～3（產生上傳金鑰、建 App、第一次手動上傳 `-rc.1`），以及之後需要實機驗收的項目（spec 第六節「實機與手動」）。這些都等使用者操作或同意後再進行。
