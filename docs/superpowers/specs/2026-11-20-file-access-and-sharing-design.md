# 檔案存取與分享（子專案 4）— 設計 spec

- 狀態：已核准（2026-11-20）
- 日期：2026-11-20
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 4）
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-06-file-access-and-sharing-design.md`，以及 commit `a795f58`～`54e0abc`、`017fc8d`、`98d26f0`、`7067e7a`、`01b39fc`（清單見附錄 A）；移植筆記第 26～28 節

---

## 一、目的

讓只用手機的玩家也能使用桌面版所有「存出去、拿進來、複製」的功能，並且依手機習慣多一個「分享」。做法照搬鳴潮版的最終狀態，檔案分工與函式名稱和鳴潮版相同，只換術語與原神特有的部分（第四節）。

## 二、範圍

- 移植鳴潮版子專案 4 的 10 個程式 commit（`a795f58`～`54e0abc` 扣掉移植筆記，再加 `017fc8d`），以及同一天在子專案 4 驗收時補的 3 個修正與測試（`98d26f0`、`7067e7a`、`01b39fc`），共 13 個，見附錄 A。
- **移植的是這些 commit 帶來的改動，不是把整個檔案換成鳴潮版的樣子**（和子專案 3 相同做法）。`share_image_helper.dart`、`share_image_dialog.dart`、`gacha_item_detail_dialog.dart`、`settings_page.dart` 在移植前兩邊就有和本子專案無關的差異（例如分享圖按鈕用的字串不同），這些維持原神現狀。全新的檔案（`file_access.dart`、`item_image_actions.dart`、`file_picker_kotlin_shim.gradle`）整檔照搬並換術語與原神特有部分。
- **例外：分享圖的進度視窗順便對齊鳴潮**（使用者 2026-11-20 要求）。原神的 `generateAndShareImage` 先載入 App 圖示、預先解碼 HoYoWiki 圖片，做完才顯示「生成中」進度視窗，只蓋住渲染；鳴潮（`a795f58~1` 時的寫法，源自 `ef12a06`）是按下按鈕就顯示，蓋住「載入圖示＋預載＋渲染」整段。改成鳴潮的寫法：選項對話框關閉後立刻 `showShareProgressDialog`；可重複呼叫的 `closeProgress()` 在渲染完成、進入存檔／分享／複製之前關閉（不能遮住系統存檔對話框），`catch` 與 `finally` 再各呼叫一次當保險；`icon`、`preloaded` 改成可為 null，在 `finally` 釋放。這項做成獨立的 commit。
- **不移植** `b8a6bf1`（把匯出／匯入的組檔與解析移到背景 isolate）：那是鳴潮版子專案 8（流暢度）的改動，留到子專案 8。
- 鳴潮版的 `docs/Android移植筆記.md` 第八節在原神版改記在本 spec 的附錄 B（原神版沒有移植筆記檔，實作坑一律記在各子專案 spec 的附錄）。

## 三、目標／非目標／反目標

和鳴潮版第一節相同，只換術語。

**目標**

- Android 上能正常使用：匯出備份、匯出日誌、另存物品圖、另存分享圖、複製圖片到剪貼簿。
- 手機上多一個「分享」（系統分享面板），用在分享圖、物品圖、日誌、備份。
- 選檔、選資料夾、存檔統一用 `file_picker`，兩個平台走同一段程式。

**非目標**

- 桌面版加上「分享」按鈕（桌面維持原樣）。
- iOS。
- 改動備份檔、日誌的內容格式。
- 背景 isolate 組檔（子專案 8）。

**反目標**

- 改壞 Windows 既有的流程或 UX（對話框種類、預設檔名、副檔名篩選、覆蓋確認、成功後的「開啟資料夾」）。唯一接受的差異見 5.1。
- 匯入備份時再出現中文亂碼（子專案 1 修過的問題，現有回歸測試在 `test/services/accounts_import_test.dart`）。
- 電腦版複製、儲存 GIF 時失去動畫（原神特有，見 4.1）。

## 四、做法（Approaches）

鳴潮版比較過三種做法，使用者當時選 C，原神版沿用，理由相同（只剩一個套件、兩個平台同一段程式、不自寫原生程式）：

| | 做法 | 取捨 |
|---|---|---|
| A | 存檔改用 `file_picker`，開檔維持 `file_selector` | 動得最少；但會有兩個選檔套件 |
| B | Windows 維持 `file_selector`，Android 自寫 Kotlin 呼叫系統建立文件畫面 | Windows 不動；但要依平台分流、自己維護原生程式 |
| **C** | **`file_picker` 全面取代 `file_selector`（開檔、選資料夾、存檔）** | **只剩一個套件；代價是要重新驗證匯入、選遊戲資料夾** |

分享用 `share_plus`；剪貼簿維持 `super_clipboard`，只補 Android manifest。

### 原神版與鳴潮版的差異（使用者 2026-11-20 確認）

| 項目 | 鳴潮版 | 原神版 |
|---|---|---|
| 要換成 `file_picker` 的開檔點 | 匯入備份、從其他工具匯入、手動輸入網址選 Client.log、選遊戲資料夾 | 只有**匯入備份**與**選遊戲資料夾**（原神沒有另外兩個功能） |
| 移植前的存圖程式 | `item_image_save.dart`、`share_image_export.dart` 兩份重複 | 已合併成 `image_clipboard_save.dart` 一份 |
| 圖片格式 | 一律轉 PNG | **GIF 保留原始 bytes**（保留動畫），其餘轉 PNG；電腦版複製 GIF 另外掛實體檔路徑 |
| 新字串要寫的 ARB | 4 份核心 ARB | 9 份已翻譯的 ARB；「分享 logs」配合原神現有用詞（第七節） |
| 備份／日誌建議檔名 | `wuwa_convene_backup_*.json`、`wwcga_logs_*.log` | 維持原神現有的 `genshin_gacha_backup_*.json`、`giwga_logs_*.log` |
| log 命名 | `io.file`、`gacha.itemimage.save`、`share.image`、`accounts.io` | 新檔 `file_access.dart` 用 `io.file`；圖片相關沿用原神現有的 `gacha.hoyowiki.save`、`gacha.hoyowiki.zoom`；其餘沿用 `share.image`、`accounts.io` |

物品詳情選單的「重抓圖片」兩版都有，不是差異。

**檔案結構照鳴潮版**（使用者 2026-11-20 要求「存圖的程式結構改成相同」）：

| 檔案 | 內容 |
|---|---|
| `lib/services/file_access.dart`（新增） | 存檔、分享、剪貼簿、選檔、選資料夾；所有測試 seam 集中於此 |
| `lib/services/item_image_save.dart`（由 `image_clipboard_save.dart` 改名） | 只剩「本地圖檔 → 要輸出的 bytes」：原神的 `OutputImage`／`prepareOutputImage`（GIF 保留、其餘轉 PNG），對應鳴潮的 `encodeImageFileToPng` |
| `lib/widgets/dialogs/item_image_actions.dart`（新增） | 物品詳情與看圖共用的選單項目 `itemImageMenuItems` 與動作 `runItemImageAction` |
| `lib/widgets/share/share_image_helper.dart` | 分享圖的存檔／分享／複製分派，函式名與鳴潮版相同（`deliverShareImage`，取代原神現有的 `exportRenderedShareImage`） |

`image_clipboard_save.dart` 的存檔、剪貼簿程式與它的 seam 全部搬進 `file_access.dart` 後刪除；對應測試 `image_clipboard_save_test.dart` 拆到 `file_access_test.dart` 與 `item_image_save_test.dart`。

### 4.1 GIF（原神特有，使用者 2026-11-20 選 A）

- **電腦版**：行為不變。複製 GIF 時剪貼簿項目放「實體檔路徑（`Formats.fileUri`）＋GIF bytes」，路徑放最前面；儲存存成 `.gif`。
- **手機儲存**：存成 `.gif`（`extension: 'gif'`、`mimeType: 'image/gif'`），保留動畫。
- **手機分享**：分享 `.gif`、`image/gif`，保留動畫。
- **手機複製（選 A）**：只放 GIF bytes（`Formats.gif`），**不掛實體檔路徑**（App 私有目錄的路徑其他 App 讀不到）。支援的 App 貼上會動，不支援的通常貼出第一格。實機驗收用 LINE 試貼；若貼不出任何東西，改成 B（手機複製 GIF 時轉成 PNG），並記在附錄 B。
- 是否掛實體檔路徑在服務層用 `defaultTargetPlatform`（和鳴潮 `saveBytes` 判斷 Android 的方式相同，服務層沒有 Riverpod ref）。

因此 `file_access.dart` 的剪貼簿 API 比鳴潮版多兩個參數：鳴潮的 `copyPngToClipboard(png)` 在原神版是「寫圖片到剪貼簿」，帶 `isGif` 與可選的 `filePath`（對應原神現有的 `imageClipboardWriter` 簽名）；分享圖仍是 PNG，呼叫時 `isGif: false`。函式與 seam 的確切命名留給建造者，原則是能和鳴潮同名就同名。

## 五、技術決定

除特別註明外，照鳴潮版附錄 A 各 commit 的改動（範圍見第二節）；新檔以鳴潮 `01b39fc` 時的內容為準。

### 5.1 `file_picker` 取代 `file_selector`

- `pubspec.yaml` 移除 `file_selector`，加入 `file_picker`、`share_plus`，版本和鳴潮版相同（`file_picker: ^11.0.3`、`share_plus: ^12.0.2`）；`path_provider` 原神已有。
- 存檔：`FilePicker.saveFile(dialogTitle:, fileName:, bytes:, type: FileType.custom, allowedExtensions: [ext], lockParentWindow: true)`，回傳字串。Windows 是實際路徑；Android 是 `content:` Uri 去掉 scheme 的 path，**要依平台判斷，不能看字串長相**。
- 開檔：`pickFiles(withData: true, lockParentWindow: true)`，拿不到 bytes 時退回讀 path；讀完在 Android 呼叫 `FilePicker.clearTemporaryFiles()`（Windows 會丟 `UnimplementedError`，所以只限 Android）。文字檔**自己 `utf8.decode`**，不合法 UTF-8 走既有的「無法讀取」訊息。
- 選資料夾：`FilePicker.getDirectoryPath(dialogTitle:, lockParentWindow: true)`，用在 `game_dir_picker.dart`。
- 三種對話框都傳在地化標題（`dialogSaveAsTitle`、`dialogOpenTitle`、`dialogSelectFolderTitle`），否則 Windows 標題是英文「File Picker」。
- **建議檔名先把 `<>:"/\|?*` 換成 `_`**：`file_picker` 在 Windows 遇到這些字元會丟例外，而且 `await` 永遠不會完成。原神的物品圖檔名已在 `gacha_item_detail_dialog.dart` 的 `_suggestedBaseName` 處理，看圖元件的 `suggestedBaseName` 也是由它傳入；備份、日誌、分享圖的檔名是固定格式，不含這些字元。
- **已知且接受的 Windows 差異**：「存檔類型」從「JSON (*.json)」變成「Files (*.json)」（圖片同理變成「Files (*.png)」／「Files (*.gif)」）。鳴潮版使用者 2026-11-06 已接受；原神版沿用（使用者 2026-11-20 確認）。
- 鳴潮版當時的 go／no-go 檢查已在鳴潮版做過，原神版不重做，改在驗收時於 Windows 比對（第九節）。

### 5.2 AGP 9 的 Kotlin shim

照搬 `android/file_picker_kotlin_shim.gradle`，在 `android/build.gradle.kts` 的 `cargokit_gradle9_shim.gradle` 下一行 `apply`。原因：`file_picker` 11.0.3 偵測到 AGP 9 就不套 Kotlin 外掛，但專案 `android.builtInKotlin=false`，沒人編它的 Kotlin。不能改 `builtInKotlin=true`（其他外掛會壞）。上游修好後刪除。

### 5.3 剪貼簿 provider

`android/app/src/main/AndroidManifest.xml` 加 `super_clipboard` 的 provider：`com.superlist.super_native_extensions.DataProvider`，authority `${applicationId}.SuperClipboardDataProvider`，`exported="true"`、`grantUriPermissions="true"`，前面一行中文註解（照鳴潮）。

### 5.4 存檔結果與分享

- `saveBytes` 回傳 `SavedFile(displayName, path)`；`path` 只有桌面有值。Android 的顯示名稱用 `displayNameForSavedPath`：取最後一段，副檔名符合才用，否則用建議檔名（下載資料夾的 provider 只給 `msf:1234`）。
- 成功訊息顯示 `saved.path ?? saved.displayName`；`showExportResultDialog` 的 `revealPath` 傳 `saved.path`（Android 為 null，不顯示「開啟資料夾」）。
- 分享：bytes 先寫到 `getTemporaryDirectory()/share_out/<檔名>`（寫前刪掉上一次的 `share_out`），再 `XFile(path)` 交給 `SharePlus`，避免 `XFile.fromData` 在暫存目錄堆積副本。分享成功不提示，失敗跳「無法分享」。

### 5.5 各功能在手機上的樣子

桌面全部不變；「分享」「儲存」是否出現看 `isAndroidProvider`（`lib/state/platform.dart`），**不看螢幕寬度**。

| 功能 | 桌面（不變） | 手機 |
|---|---|---|
| 分享圖對話框 | 取消／複製圖片／儲存圖片 | 取消／複製圖片／**分享**／儲存圖片（`ShareImageAction` 加 `share`；既有按鈕字串 `shareImageActionCopy`／`shareImageActionSave` 不變） |
| 物品圖選單（詳情與看圖） | 複製／儲存（詳情另有分隔線＋重抓） | 複製／儲存／**分享**（詳情另有分隔線＋重抓） |
| 日誌（設定頁） | 匯出 logs／開啟 logs 資料夾 | 匯出 logs／**分享 logs**（取代開啟資料夾） |
| 備份（設定頁） | 選帳號 → 匯出 | 選帳號後按鈕為 取消／**分享**／**儲存** |

- 帳號挑選對話框照鳴潮版改成回傳 `AccountsPickResult = ({List<String> uids, bool secondary})`，加 `secondaryConfirmLabel`；匯入流程（不給次要按鈕）同步改用 `.uids`。
- 日誌匯出照鳴潮 `98d26f0`：先組 bundle 再開存檔對話框（`saveFile` 需要 bytes 備妥），組 bundle 失敗與存檔失敗分開記 log 並提示；`_buildBundle` 與 `_share` 共用。
- 設定頁的 `_savedLocation`、`_shareOrReport` 兩個 helper 照搬。

### 5.6 log

照鳴潮版：存檔、分享、剪貼簿、選檔、選資料夾的成功／取消／失敗都記（英文），路徑經 `sanitizeFsPath`；Android 沒有路徑時記 `name=`。物品圖動作照 `017fc8d` 記一行 `item image action=<copy|save|share> name=<...> outcome=<ok|cancelled|failed>`。Logger 名稱見第四節的差異表。

## 六、各檔改動清單

| 檔案 | 改動 |
|---|---|
| `pubspec.yaml`、`pubspec.lock` | 移除 `file_selector`；加 `file_picker`、`share_plus` |
| `android/build.gradle.kts`、`android/file_picker_kotlin_shim.gradle` | 5.2 |
| `android/app/src/main/AndroidManifest.xml` | 5.3 |
| `lib/services/file_access.dart` | 新增（第四節、5.1、5.4、4.1） |
| `lib/services/image_clipboard_save.dart` → `item_image_save.dart` | 改名並只留圖片準備 |
| `lib/widgets/dialogs/item_image_actions.dart` | 新增 |
| `lib/widgets/dialogs/gacha_item_detail_dialog.dart`、`zoomable_image_overlay.dart` | 改用共用選單與動作；手機多「分享」 |
| `lib/models/share_image_options.dart`、`lib/widgets/dialogs/share_image_dialog.dart`、`lib/widgets/share/share_image_helper.dart` | 分享圖的分享動作與 `deliverShareImage`；進度視窗涵蓋預載（第二節） |
| `lib/widgets/dialogs/accounts_picker_dialog.dart` | 次要確認鈕 |
| `lib/pages/settings_page.dart` | 備份匯出／匯入、日誌匯出／分享 |
| `lib/widgets/game_dir_picker.dart` | 改用 `file_access.pickDirectory` |
| 9 份 ARB 與產生的 `app_localizations*.dart` | 第七節 |

## 七、文字與語系

新增 7 個 key，和鳴潮版相同：`actionShare`（分享）、`shareFailed`（無法分享）、`dialogSaveAsTitle`（另存新檔）、`dialogOpenTitle`（開啟）、`dialogSelectFolderTitle`（選取資料夾）、`actionSave`（儲存）、`settingsLogsShare`（分享 logs）。

- 從 `app_zh.arb` 起手，再寫其他 8 份已翻譯的 ARB（`en`、`zh_Hans`、`ja`、`es`、`fr`、`pt_BR`、`th`、`vi`）；22 份空殼不動。
- 鳴潮版 master 的這 9 個語系都已有這 7 個 key 的翻譯，直接沿用，**只有 `settingsLogsShare` 要配合原神同語系現有的 `settingsLogsExport` 用詞**：鳴潮的 `zh_Hans`／`es`／`th`／`vi` 寫「日志／registros／ล็อก／log」，原神這四個語系寫「logs」（例如「导出 logs」），所以原神版是 `zh_Hans`「分享 logs」、`es`「Compartir logs」、`th`「แชร์ logs」、`vi`「Chia sẻ logs」；`zh`（分享 logs）、`en`、`ja`、`fr`、`pt_BR` 兩邊用詞相同，照鳴潮。（我的判斷：同一頁的按鈕用詞一致優先於和鳴潮逐字相同。）
- 已有的字串（`actionCopyImage`、`imageCopied`、`shareImageSaved` 等）沿用，不改名。

## 八、限制

- `file_picker` 在 Windows 的「存檔類型」名稱寫死（5.1）。
- Android 存檔拿不到可開啟的路徑，成功訊息只顯示檔名。
- 手機複製 GIF 能不能動取決於貼上的 App（4.1）。

## 九、驗證

**自動測試**（`fvm dart format lib/ test/`、`fvm flutter analyze` 無問題、`fvm flutter test` 全過）

照搬鳴潮版的測試並換術語，另外加原神特有的部分：

- `file_access_test.dart`：存檔取消／成功／失敗、Android 名稱推導、分享（含 `prepareShareFile` 只留一個檔）、剪貼簿、選檔與 UTF-8 解碼（含中文別名；取代 `accounts_import_test.dart` 裡 `XFile.fromData` 那一則）、選資料夾。**原神特有**：GIF 在 Android 不掛實體檔路徑、在 Windows 掛路徑且放最前面。
- `item_image_save_test.dart`：GIF 保留、其餘轉 PNG（由 `image_clipboard_save_test.dart` 搬來）。
- 設定頁、分享圖對話框、物品詳情、看圖：Android 才出現「分享」，Windows 不出現；Android 不出現「開啟日誌資料夾」；帳號挑選對話框在 Android 有「分享」「儲存」。
- `settings_page_export_test.dart`、`settings_page_import_button_test.dart`、`deliver_share_image_test.dart` 照搬（扣掉原神沒有的「從其他工具匯入」）；`share_image_export_routing_test.dart` 併入或改寫為 `deliver_share_image_test.dart`。
- 分享圖進度視窗：選項對話框關閉後、預載完成前，進度視窗已經顯示；渲染失敗或預載丟例外時進度視窗會關閉並跳失敗訊息；存檔對話框出現時進度視窗已關閉。
- **原神特有**：物品圖動作對 GIF 的儲存／分享用 `.gif`、`image/gif`。注意鳴潮的預設存檔函式沒有把 `mimeType` 傳給 `FilePicker.saveFile`（只用在 log 與 seam），所以這則測試只驗證參數；Android 實際存出的格式靠實機確認。

**實機（ROG Phone，debug 版）**

- 匯出備份：儲存到下載資料夾、分享到雲端硬碟或 LINE；再匯入剛存的備份（含中文別名）。
- 匯出日誌：儲存、分享。
- 分享圖、物品圖：複製（貼到 LINE 確認是圖片）、儲存、分享。**另測一張 GIF 物品圖**：儲存與分享後仍會動；複製後貼到 LINE 的結果記在附錄 B（4.1 的 A／B 判斷）。

**Windows（release 或 debug 視窗）**

- 存檔對話框：標題是在地化的「另存新檔」、預設檔名、「Files (*.json)」篩選、覆蓋確認；成功後「開啟資料夾」會選中檔案；對話框歸屬於 App 視窗（模態）。
- 匯入備份、選遊戲資料夾正常，對話框標題在地化。
- 複製 GIF 物品圖貼到 Discord 或檔案總管仍是會動的 `.gif`；複製 PNG 貼到小畫家正常。
- 檔名含 `:` 等字元的物品圖能正常存檔（不卡住）。

依 CLAUDE.md「改到 manifest、Kotlin 或 R8 相關的東西時要用 release 版實跑」：manifest 與 Gradle 有改，驗收時另外建一次 Android release 版，至少確認能建置、存檔與複製正常。

## 十、留給建造者的部分

- `file_access.dart` 剪貼簿函式與 seam 的確切命名（4.1），以及 `item_image_save.dart` 裡函式要不要改成鳴潮的名字（`encodeImageFileToPng` 在原神不貼切，因為 GIF 不轉 PNG）。
- 分享按鈕圖示用 `Icons.share`（選單）／`Icons.share_outlined`（按鈕），順序照鳴潮版。
- 測試檔的拆分方式。

## 附錄 A：鳴潮版對應 commit

| commit | 內容 |
|---|---|
| `a795f58` | 加入 `file_picker`、`share_plus` |
| `26de1bb` | 共用的檔案存取服務 |
| `f3c9ba6` | Android 存檔結果當成文件路徑處理 |
| `d22351c` | 分享圖：儲存、分享、複製 |
| `7f5093a` | 物品圖分享 |
| `8e1f8ee` | 設定頁備份與日誌的儲存、分享 |
| `e45f6da` | 開檔改用 `file_picker`，移除 `file_selector` |
| `b6297eb` | Windows 對話框歸屬 App 視窗、標題在地化 |
| `54e0abc` | 桌面顯示選到的檔名、分享暫存檔不堆積 |
| `017fc8d` | 物品圖動作的 log、分享圖複製失敗 |
| `98d26f0` | 日誌組檔失敗處理、記錄匯出位置 |
| `7067e7a` | 從其他工具匯入失敗的測試（原神沒有此功能，只取 `share_image_helper.dart` 的一行清理）、改用條件等待 |
| `01b39fc` | import 排序 |

（另外 `1f4774f` 是移植筆記，見第二節。）

## 附錄 B：實機驗收與實作坑

（實作與驗收時補上。）
