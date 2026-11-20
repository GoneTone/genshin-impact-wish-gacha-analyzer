# 檔案存取與分享（子專案 4）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 上能匯出備份與日誌、另存與複製物品圖和分享圖，手機另外多一個「分享」；選檔、選資料夾、存檔統一改用 `file_picker`，桌面行為不變。

**Architecture:** 照搬鳴潮版子專案 4：新增 `lib/services/file_access.dart` 集中存檔／分享／剪貼簿／選檔與測試 seam，物品圖選單抽到 `item_image_actions.dart`，各呼叫端改用它；「分享」「儲存」看 `isAndroidProvider`。原神特有的 GIF（保留原始 bytes）留在 `item_image_save.dart`，剪貼簿 API 多帶 `isGif`／`filePath`。

**Tech Stack:** Flutter 3.47.5（FVM）、Riverpod 3、`file_picker`、`share_plus`、`super_clipboard`、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-20-file-access-and-sharing-design.md`（必讀；第二節是範圍，第四節是原神差異與檔案結構，4.1 是 GIF）

**照搬來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。
- 看最終檔案：`git -C ../wuthering-waves-convene-gacha-analyzer show 01b39fc:<路徑>`。
- 看某個 commit 的改法：`git -C ../wuthering-waves-convene-gacha-analyzer show <commit> -- <路徑>`。
- **只移植附錄 A 各 commit 改到的地方**，不要把既有檔案整檔換成鳴潮版（spec 第二節）。新檔（`file_access.dart`、`item_image_actions.dart`、`file_picker_kotlin_shim.gradle`、新測試檔）以 `01b39fc` 為底整檔照搬，再換名稱與原神差異。
- 換名稱：套件 `wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`；`ItemImage*`／`itemImage*` 類的 provider 換成原神對應的 `hoyowiki*`；鳴潮字串 `itemImageCopied`／`itemImageCopyFailed`／`itemImageSavedTo`／`itemImageSaveFailed` 換成原神的 `imageCopied`／`imageCopyFailed`／`imageSavedTo`／`imageSaveFailed`；檔名前綴 `wuwa_convene_backup_`／`wwcga_logs_` 換成 `genshin_gacha_backup_`／`giwga_logs_`。
- 不確定要不要偏離時回報 NEEDS_CONTEXT，不要自行改寫。

## Global Constraints

- 依賴：移除 `file_selector`；加 `file_picker: ^11.0.3`、`share_plus: ^12.0.2`，`pubspec.lock` 解出的版本要和鳴潮 `01b39fc` 的 `pubspec.lock` 相同（不同就回報）。`super_clipboard`、`path_provider` 不動。
- 「分享」「儲存」是否出現只看 `isAndroidProvider`，不看螢幕寬度。服務層（沒有 ref）判斷 Android 用 `defaultTargetPlatform == TargetPlatform.android`。
- 三種對話框都傳在地化標題：存檔 `l.dialogSaveAsTitle`、開檔 `l.dialogOpenTitle`、選資料夾 `l.dialogSelectFolderTitle`；`file_picker` 呼叫一律 `lockParentWindow: true`。
- 新字串 7 個：`actionShare`、`shareFailed`、`dialogSaveAsTitle`、`dialogOpenTitle`、`dialogSelectFolderTitle`、`actionSave`、`settingsLogsShare`，加在 9 份已翻譯 ARB（zh、zh_Hans、en、ja、es、fr、pt_BR、th、vi），22 份空殼不動。翻譯取鳴潮 master 同語系同 key；`settingsLogsShare` 例外：zh「分享 logs」、zh_Hans「分享 logs」、es「Compartir logs」、pt_BR「Compartilhar logs」、th「แชร์ logs」、vi「Chia sẻ logs」，en／ja／fr 照鳴潮。改完 `fvm flutter gen-l10n`。
- log：英文；`file_access.dart` 用 `Logger('io.file')`；圖片相關沿用 `gacha.hoyowiki.save`（`item_image_save.dart`、`item_image_actions.dart`）與 `gacha.hoyowiki.zoom`；設定頁沿用 `accounts.io`；分享圖沿用 `share.image`。路徑經 `sanitizeFsPath`。
- 所有宣告（含 private）一行 `///` dartdoc；`//` 只寫 WHY；中文全形標點、省略號半形 `...`。對話框一律 `AppDialog`。
- 測試：Android 平台用 `TargetPlatformVariant.only(TargetPlatform.android)` 或覆寫 `isAndroidProvider`（照鳴潮各測試的做法）；純 `test()` 裡要改 `debugDefaultTargetPlatformOverride` 時在 `tearDown` 還原。seam 一律在 `tearDown` 呼叫 reset 函式。
- 每次 commit 前：`fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。commit 英文 conventional commits，結尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；**`git commit` 用 PowerShell 執行**（Git Bash 裡 GPG 簽章會失敗，不可跳過簽章）。分支 `feat/android`，不開新分支、不 push。

## Review Focus

1. **手機複製 GIF**：剪貼簿不能帶 App 私有檔路徑，只放 GIF bytes；電腦版維持「路徑在前＋GIF bytes」→ Task 2 測試 `copyImageToClipboard drops the file path on Android` 與 `copyImageToClipboard keeps the file path on desktop`。
2. **手機把 GIF 存到「下載」資料夾**：provider 只回 `/document/msf:1234`，成功訊息要顯示建議檔名 `<名稱>.gif` → Task 2 測試 `displayNameForSavedPath falls back for a gif saved to Downloads`。
3. **物品名稱或圖片標籤含 `:`、`/` 等字元**：存檔不能卡住，存檔對話框收到的檔名已換成 `_` → Task 5 測試 `saving an image with illegal characters in its name passes a sanitized name`。
4. **含中文別名的備份，存出去再匯入回來**：別名不能變亂碼 → Task 6 測試 `a saved backup imports back with its Chinese alias`。
5. **Windows 視窗拉到手機寬度**：仍是桌面行為，不出現「分享」 → Task 3 測試 `narrow Windows window still has no share button`、Task 6 測試 `narrow Windows window keeps open logs folder`。

---

## File Structure

| 檔案 | 責任 | Task |
|---|---|---|
| `pubspec.yaml`／`.lock`、`android/build.gradle.kts`、`android/file_picker_kotlin_shim.gradle`（新）、`AndroidManifest.xml`、9 份 ARB | 依賴、AGP 9 shim、剪貼簿 provider、新字串 | 1 |
| `lib/services/file_access.dart`（新） | 存檔、分享、剪貼簿、選檔、選資料夾與 seam | 2 |
| `share_image_options.dart`、`share_image_dialog.dart`、`share_image_helper.dart` | 分享圖的分享動作、`deliverShareImage` | 3 |
| `share_image_helper.dart` | 進度視窗涵蓋預載 | 4 |
| `item_image_save.dart`（由 `image_clipboard_save.dart` 改名）、`item_image_actions.dart`（新）、`gacha_item_detail_dialog.dart`、`zoomable_image_overlay.dart` | 物品圖選單與動作 | 5 |
| `accounts_picker_dialog.dart`、`settings_page.dart`、`game_dir_picker.dart`、`pubspec.yaml` | 備份／日誌的儲存與分享、匯入、選資料夾；移除 `file_selector` | 6 |
| spec 附錄 B、記憶 | 驗收紀錄 | 7 |

---

### Task 1: 依賴、Android 建置設定、新字串

鳴潮版 commit：`a795f58`，以及 `26de1bb`～`8e1f8ee` 加 ARB 的部分。

**Files:**
- Modify: `pubspec.yaml`、`pubspec.lock`、`android/build.gradle.kts`、`android/app/src/main/AndroidManifest.xml`、9 份 `lib/l10n/app_*.arb`
- Create: `android/file_picker_kotlin_shim.gradle`

**Interfaces:**
- Produces: `package:file_picker`、`package:share_plus` 可 import（`file_selector` 先保留，Task 6 移除）；`AppLocalizations` 有 Global Constraints 的 7 個 key。

- [ ] **Step 1: 加依賴**：`pubspec.yaml` 加 `file_picker: ^11.0.3`、`share_plus: ^12.0.2`（位置照鳴潮 `a795f58`），跑 `fvm flutter pub get`，比對鳴潮 `01b39fc:pubspec.lock` 中兩者與新增傳遞依賴的版本。
- [ ] **Step 2: Gradle shim**：整檔照搬 `01b39fc:android/file_picker_kotlin_shim.gradle`；`android/build.gradle.kts` 在 `apply(from = "cargokit_gradle9_shim.gradle")` 下一行加 `apply(from = "file_picker_kotlin_shim.gradle")`。
- [ ] **Step 3: Manifest**：照鳴潮 `a795f58` 加 `super_clipboard` provider（`com.superlist.super_native_extensions.DataProvider`、authority `${applicationId}.SuperClipboardDataProvider`、`exported="true"`、`grantUriPermissions="true"`、前一行中文註解），放在 `AdbPairingService` 之後。
- [ ] **Step 4: ARB**：9 份 ARB 末尾加 7 個 key（字串見 Global Constraints；`app_en.arb` 照鳴潮加 `@` 描述），`fvm flutter gen-l10n`。
- [ ] **Step 5: 確認建置**：`fvm flutter build apk --debug` 成功（找不到 `FilePickerPlugin` 表示 shim 沒生效）；`fvm flutter analyze`、`fvm flutter test` 全過。
- [ ] **Step 6: Commit** `chore(deps): add file_picker and share_plus`

---

### Task 2: 共用的檔案存取服務

鳴潮版 commit：`26de1bb`、`f3c9ba6`、`b6297eb`、`54e0abc`、`98d26f0`（只取 `file_access_test.dart`）。

**Files:**
- Create: `lib/services/file_access.dart`、`test/services/file_access_test.dart`

**Interfaces:**
- Consumes: Task 1 的套件。
- Produces（除剪貼簿外與鳴潮 `01b39fc` 同名同簽名）：
  - `class SavedFile { final String displayName; final String? path; }`
  - `Future<SavedFile?> saveBytes(Uint8List bytes, {required String suggestedName, required String extension, required String mimeType, String? dialogTitle})`
  - `String displayNameForSavedPath(String saved, {required String suggestedName, required String extension})`
  - `Future<bool> shareBytes(Uint8List bytes, {required String fileName, required String mimeType})`
  - `Future<Uint8List?> pickFileBytes({List<String>? extensions, String? dialogTitle})`
  - `Future<String?> pickTextFile({required List<String> extensions, String? dialogTitle})`
  - `Future<String?> pickDirectory({String? dialogTitle})`
  - `@visibleForTesting Future<File> prepareShareFile(Directory tempRoot, Uint8List bytes, String fileName)`
  - **原神版剪貼簿**（取代鳴潮 `copyPngToClipboard`／`PngClipboardWriter`／`pngClipboardWriter`）：`typedef ImageClipboardWriter = Future<bool> Function(Uint8List bytes, {required bool isGif, String? filePath});`、`Future<bool> copyImageToClipboard(Uint8List bytes, {bool isGif = false, String? filePath})`。在 Android 呼叫 writer 前把 `filePath` 換成 null；成功／失敗 log 照鳴潮（`copy image clipboard=$ok gif=$isGif bytes=...`）。
  - seam：`fileSaveDialog`、`fileOpenDialog`、`directoryDialog`、`fileSharer`、`imageClipboardWriter`，`resetFileAccessSeams()` 全部重設。
  - 預設剪貼簿 writer 的內容從原神 `image_clipboard_save.dart` 的 `_defaultClipboardWriter` 搬來（GIF 且有 `filePath` 時先 `Formats.fileUri`，再 `Formats.gif`／`Formats.png`），不是鳴潮的 PNG 版。

- [ ] **Step 1: 寫失敗的測試**：照搬 `01b39fc:test/services/file_access_test.dart` 全部案例（剪貼簿兩則改測 `copyImageToClipboard`），另加：
  - `copyImageToClipboard drops the file path on Android`：Android 下呼叫 `copyImageToClipboard(gif, isGif: true, filePath: 'C:/x.gif')`，seam 收到 `isGif == true`、`filePath == null`。
  - `copyImageToClipboard keeps the file path on desktop`：Windows 下 seam 收到 `filePath == 'C:/x.gif'`。
  - `displayNameForSavedPath falls back for a gif saved to Downloads`：`displayNameForSavedPath('/document/msf:1234', suggestedName: '胡桃_立繪.gif', extension: 'gif')` == `'胡桃_立繪.gif'`；`'/document/primary:Download/a.gif'` → `'a.gif'`。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/services/file_access_test.dart`，因 `file_access.dart` 不存在而編譯失敗。
- [ ] **Step 3: 實作**：以 `01b39fc:lib/services/file_access.dart` 為底，換成上面的剪貼簿 API。
- [ ] **Step 4: 確認通過**，再跑全套 `fvm flutter test`。
- [ ] **Step 5: Commit** `feat(files): add a shared file access service`

---

### Task 3: 分享圖：儲存、分享、複製

鳴潮版 commit：`d22351c`、`017fc8d`（只取 `share_image_helper.dart` 與 `deliver_share_image_test.dart`）、`7067e7a`（只取 `share_image_helper.dart` 的 import 清理）。

**Files:**
- Modify: `lib/models/share_image_options.dart`、`lib/widgets/dialogs/share_image_dialog.dart`、`lib/widgets/share/share_image_helper.dart`、`test/widgets/dialogs/share_image_dialog_test.dart`
- Create: `test/widgets/share/deliver_share_image_test.dart`
- Delete: `test/widgets/share/share_image_export_routing_test.dart`（案例併入新檔）

**Interfaces:**
- Consumes: `saveBytes`、`shareBytes`、`copyImageToClipboard`（PNG 用 `isGif: false`）。
- Produces: `ShareImageAction.share`；`@visibleForTesting Future<void> deliverShareImage({required BuildContext context, required AppLocalizations l, required ShareImageAction action, required Uint8List png, required String suggestedName})`，取代原神的 `exportRenderedShareImage`（`generateAndShareImage` 改呼叫它）。

- [ ] **Step 1: 寫失敗的測試**：
  - `deliver_share_image_test.dart` 照搬 `01b39fc` 版 8 則；原神 `share_image_export_routing_test.dart` 若有鳴潮沒有的案例，一併搬進來。
  - `share_image_dialog_test.dart` 加鳴潮的兩則（Android 有「分享」且回傳 `action=share`；Windows 沒有），以及 `narrow Windows window still has no share button`：Windows、360×800，找不到 `l.actionShare`。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/widgets/share/ test/widgets/dialogs/share_image_dialog_test.dart`。
- [ ] **Step 3: 實作**：照鳴潮 `d22351c` 的改法；`_ShareImageDialog` 改 `ConsumerStatefulWidget`，Android 時在「複製圖片」與「儲存圖片」之間加 `TextButton(l.actionShare)`；按鈕字串維持原神的 `shareImageActionCopy`／`shareImageActionSave`。
- [ ] **Step 4: 確認通過**，跑全套。
- [ ] **Step 5: Commit** `feat(share): save, share and copy share images on Android`

---

### Task 4: 分享圖進度視窗涵蓋預載

對齊鳴潮 `a795f58^:lib/widgets/share/share_image_helper.dart` 的 `generateAndShareImage`（源自 `ef12a06`），spec 第二節的例外。

**Files:**
- Modify: `lib/widgets/share/share_image_helper.dart`
- Test: `test/widgets/share/share_image_progress_test.dart`（新；原神目前沒有 `generateAndShareImage` 的測試）

**Interfaces:**
- Consumes: Task 3 的 `deliverShareImage`；現有 `showShareProgressDialog`、`loadAppIconImage`、`preloadHoYoWikiImages`、`disposePreloadedHoYoWikiImages`。
- Produces: 行為改變，`generateAndShareImage` 簽名不變；新增測試 seam `@visibleForTesting Future<Map<String, ui.Image>> Function(Iterable<GachaRecord> records)? shareImagePreloadOverride;`（非 null 時取代「`preloadHoYoWikiImages` 那一步」），寫法比照 `prepareOutputImageOverride`。

- [ ] **Step 1: 寫失敗的測試**：
  - `progress dialog shows while images preload`：`shareImagePreloadOverride` 回傳一個不完成的 `Completer` future，選項對話框按「儲存圖片」後 `pump()`，找到進度視窗。
  - `progress dialog closes and reports failure when preloading throws`：`shareImagePreloadOverride` 丟例外 → 進度視窗消失、顯示 `l.shareImageFailed`。
  - `progress dialog is gone before the save dialog opens`：存檔 seam 被呼叫時，畫面上已找不到進度視窗。
- [ ] **Step 2: 確認失敗**（第一則：目前預載期間沒有進度視窗）。
- [ ] **Step 3: 實作**：選項對話框關閉後立刻 `unawaited(showShareProgressDialog(context))`；可重複呼叫的 `closeProgress()`（只在開著且 `context.mounted` 時 pop）在渲染完成後、`deliverShareImage` 前呼叫，`catch` 與 `finally` 再各呼叫一次；`icon`／`preloaded` 改可為 null，在 `finally` 釋放。註解照鳴潮那段的意思。
- [ ] **Step 4: 確認通過**，跑全套。
- [ ] **Step 5: Commit** `fix(share): show the progress dialog while share images preload`

---

### Task 5: 物品圖：共用選單、儲存、分享、複製

鳴潮版 commit：`7f5093a`、`017fc8d`、`98d26f0`（只取 `gacha_item_detail_dialog_test.dart`）。

**Files:**
- Rename: `lib/services/image_clipboard_save.dart` → `lib/services/item_image_save.dart`；`test/services/image_clipboard_save_test.dart` → `test/services/item_image_save_test.dart`
- Create: `lib/widgets/dialogs/item_image_actions.dart`
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`lib/widgets/dialogs/zoomable_image_overlay.dart`、`test/widgets/dialogs/gacha_item_detail_dialog_test.dart`、`test/widgets/dialogs/zoomable_image_overlay_test.dart`

**Interfaces:**
- Consumes: `saveBytes`、`shareBytes`、`copyImageToClipboard`。
- Produces:
  - `item_image_save.dart` 只留 `OutputImage`、`prepareOutputImage(File)`、`prepareOutputImageOverride`、`resetItemImageSaveSeams()`（只重設 `prepareOutputImageOverride`）；存檔與剪貼簿函式、seam 全部刪除。
  - `List<PopupMenuEntry<String>> itemImageMenuItems(AppLocalizations l, {required bool share})`（複製／儲存／分享，圖示 `Icons.copy`／`Icons.save_alt`／`Icons.share`）。
  - `Future<void> runItemImageAction(String value, {required File file, required String suggestedBaseName, required AppLocalizations l, required void Function(String message) toast})`：先 `prepareOutputImage`，失敗依動作提示 `imageCopyFailed`／`imageSaveFailed`／`shareFailed`；檔名 `'$suggestedBaseName.${out.ext}'`、MIME `out.isGif ? 'image/gif' : 'image/png'`；copy 用 `copyImageToClipboard(out.bytes, isGif: out.isGif, filePath: out.isGif ? file.path : null)`；save 成功提示 `imageSavedTo(saved.path ?? saved.displayName)`、取消不提示；share 失敗提示 `shareFailed`。最後記 `item image action=$value name=<檔名> outcome=<ok|cancelled|failed>`（準備失敗時 `name=` 用不含副檔名的 base）。
  - 詳情選單 = `...itemImageMenuItems(l, share: ref.read(isAndroidProvider))`＋分隔線＋重抓；看圖元件改 `ConsumerStatefulWidget`，選單 = `itemImageMenuItems(l, share: ref.read(isAndroidProvider))`。兩處的 `_copyImage`／`_saveImage`／`_copy`／`_save` 改為呼叫 `runItemImageAction`（看圖元件保留既有的 `gacha.hoyowiki.zoom` 選單 log）。

- [ ] **Step 1: 改名並刪除搬走的程式**：`git mv` 兩個檔；`item_image_save_test.dart` 只留 GIF／PNG 準備的案例（存檔與剪貼簿案例已在 Task 2 涵蓋）；更新所有 import。
- [ ] **Step 2: 寫失敗的測試**：照搬 `01b39fc` 的 `zoomable_image_overlay_test.dart` copy/save 群組與 `gacha_item_detail_dialog_test.dart` 的分享、log 案例（seam 換成 Task 2 的名稱），另加：
  - `sharing a gif item image keeps it as a gif`：`prepareOutputImageOverride` 回 `isGif: true` → `fileSharer` 收到 `'<base>.gif'`、`'image/gif'`。
  - `saving a gif item image asks for a .gif`：`fileSaveDialog` 收到 `suggestedName` 以 `.gif` 結尾、`extension == 'gif'`。
  - `copying a gif on Android sends no file path`：Android 下 `imageClipboardWriter` 收到 `isGif: true`、`filePath: null`。
  - `saving an image with illegal characters in its name passes a sanitized name`：record 名稱 `'A:B/C'` 的詳情對話框按儲存 → `fileSaveDialog` 收到的檔名不含 `<>:"/\|?*`。
- [ ] **Step 3: 確認失敗**：`fvm flutter test test/widgets/dialogs/ test/services/item_image_save_test.dart`。
- [ ] **Step 4: 實作** `item_image_actions.dart` 與兩個呼叫端。
- [ ] **Step 5: 確認通過**，跑全套。
- [ ] **Step 6: Commit** `feat(share): share item images on Android`

---

### Task 6: 設定頁的備份與日誌、匯入、選資料夾，移除 `file_selector`

鳴潮版 commit：`8e1f8ee`、`e45f6da`、`b6297eb`（`game_dir_picker.dart`）、`98d26f0`、`7067e7a`（只取「改用條件等待」的寫法，原神沒有「從其他工具匯入」）、`01b39fc`。

**Files:**
- Modify: `lib/widgets/dialogs/accounts_picker_dialog.dart`、`lib/pages/settings_page.dart`、`lib/widgets/game_dir_picker.dart`、`pubspec.yaml`、`pubspec.lock`、`test/widgets/dialogs/accounts_picker_dialog_test.dart`、`test/pages/settings_page_import_button_test.dart`、`test/services/accounts_import_test.dart`、`test/widgets/dialogs/zoomable_image_overlay_test.dart`（移除 `file_selector` import）
- Create: `test/pages/settings_page_export_test.dart`

**Interfaces:**
- Consumes: `saveBytes`、`shareBytes`、`pickTextFile`、`pickDirectory`、`SavedFile`。
- Produces: `typedef AccountsPickResult = ({List<String> uids, bool secondary});`；`showAccountsPickerDialog(..., String? secondaryConfirmLabel, ...)` 回傳 `Future<AccountsPickResult?>`（次要鈕 `OutlinedButton.icon` + `Icons.share_outlined`，在取消與主確認之間）。設定頁新增 top-level `_savedLocation(SavedFile)`、`_shareOrReport(...)`，`_LogsSection` 新增 `_buildBundle`、`_share`，皆照鳴潮 `01b39fc`。

- [ ] **Step 1: 寫失敗的測試**：
  - `accounts_picker_dialog_test.dart` 加鳴潮的 `secondary button returns secondary == true`、`no secondary button unless a label is given`，既有案例改讀 `.uids`。
  - `settings_page_export_test.dart` 照搬 `01b39fc` 版全部案例（檔名與 log 字串換原神），另加：
    - `a saved backup imports back with its Chinese alias`：別名「主號」的帳號匯出，`fileSaveDialog` 抓到 bytes；把同一份 bytes 交給 `fileOpenDialog` 再匯入 → 匯入確認畫面出現「主號」。
    - `narrow Windows window keeps open logs folder`：Windows、360×800，有 `l.settingsLogsOpenFolder`、沒有 `l.settingsLogsShare`。
  - `settings_page_import_button_test.dart` 加鳴潮的 `import dialog gets the localized open title` 與匯入不合法 UTF-8 顯示無法讀取的案例（只取匯入備份那幾則）。
  - `accounts_import_test.dart` 刪掉 `XFile.fromData` 那一則（已由 Task 2 的 `pickTextFile decodes UTF-8 Chinese text` 取代）與 `file_selector` import。
- [ ] **Step 2: 確認失敗**：`fvm flutter test test/pages/ test/widgets/dialogs/accounts_picker_dialog_test.dart`。
- [ ] **Step 3: 實作**：照鳴潮改設定頁（備份匯出：Android 主鈕 `l.actionSave`、次要鈕 `l.actionShare`，桌面維持 `l.confirmExport`；匯入用 `pickTextFile(extensions: const ['json'], dialogTitle: l.dialogOpenTitle)`；日誌：Android 用「分享 logs」取代開啟資料夾）；`game_dir_picker.dart` 預設改 `file_access.pickDirectory(dialogTitle: l.dialogSelectFolderTitle)`（`import ... as file_access`），`SettingsPage.pickGameDir` 測試注入維持；`pubspec.yaml` 移除 `file_selector`，`fvm flutter pub get`；`grep -rn file_selector lib test` 應無結果。
- [ ] **Step 4: 確認通過**，跑全套。
- [ ] **Step 5: Commit** `feat(settings): save and share backups and logs on Android`（如改動過大，可把移除 `file_selector` 另拆成 `refactor(files): open files through file_picker and drop file_selector`）

---

### Task 7: 驗收與紀錄

**Files:**
- Modify: `docs/superpowers/specs/2026-11-20-file-access-and-sharing-design.md`（附錄 B）、記憶 `project_android_port_branch_strategy.md`

- [ ] **Step 1: Windows**：`fvm flutter run -d windows`，依 spec 第九節 Windows 項目逐項確認（存檔對話框標題、檔名、「Files (*.json)」、覆蓋確認、開啟資料夾選中檔案、對話框模態；匯入備份、選遊戲資料夾；複製 GIF 貼到 Discord／檔案總管會動；含 `:` 檔名的物品圖能存）。需要實體滑鼠鍵盤操作時先問使用者授權。
- [ ] **Step 2: Android debug（ROG Phone）**：依 spec 第九節實機項目逐項確認，含 GIF 物品圖的儲存、分享、複製貼到 LINE（記錄 4.1 的結果；貼不出任何東西就停下來回報，由使用者確認改用 B）。安裝前確認手機上現有 App 的安裝來源（記憶 `project_phone_test_installs.md`）。
- [ ] **Step 3: Android release**：建 release 版並安裝實跑，至少確認存檔、分享、複製正常（manifest 與 Gradle 有改）。
- [ ] **Step 4: 記錄**：spec 附錄 B 寫實測結果與踩到的坑；記憶更新子專案 4 完成與下一步。
- [ ] **Step 5: Commit** `docs(spec): record the file access and sharing device check`
