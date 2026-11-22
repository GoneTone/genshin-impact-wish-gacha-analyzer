# 多國語言補齊與術語表（子專案 11）— 設計 spec

- 狀態：已完成（2026-11-22；驗收結果見附錄）
- 日期：2026-11-22
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（第三節子專案 11 與「子專案 11 的術語表」段落；順序 8 → 9 → 12 → 10 → 11 → 7 → 13）
- 對應鳴潮版：移植筆記第 49 節（`docs/Android移植筆記.md` 第 700～738 行），commit 見第二節
- 前一個子專案：子專案 9b（啟動畫面配合主題、系統「應用程式語言」雙向同步）。9b 會帶進 `locales_config.xml` 與 `android_locales_config_test`，本子專案以它們為前提。

---

## 一、目的

原神版目前 31 個語系檔中，只有 9 個有實際翻譯（`zh`、`zh_Hans`、`en`、`es`、`fr`、`ja`、`pt_BR`、`th`、`vi`），其餘 22 個是只有十幾行的空殼，選這些語言的使用者幾乎整個 App 都是英文。照鳴潮第 49 節的做法一次補齊，並把鳴潮同一節修掉的多語系問題（複數、由右往左、長字串溢出、Android 原生字串、不支援語言掉到南非語、挪威文）一起移植。

**術語表優先（使用者 2026-11-17 指定）**：翻譯前先更新 `docs/術語表.md`，這份表是翻譯遊戲用語的唯一依據。既有 9 欄就是官方正確譯名，不重新質疑、不改動；這次只新增欄位。

## 二、範圍

**移植的鳴潮 commit**（`git -C ../wuthering-waves-convene-gacha-analyzer show <commit>`）：

| 項目 | 鳴潮 commit |
|---|---|
| 英文複數、核心語言缺漏 | `4a23e4c` |
| 長翻譯在手機不溢出 | `7370042` |
| 補齊其他語言 | `25c7256` |
| 由右往左版面 | `f87c2a4` |
| 遊戲有出的語言照官方用語 | `a11352c`、`56ec259` |
| 沒有支援的系統語言改回英文 | `cde6409` |
| Android 啟動器名稱與配對通知翻譯 | `d6bf944` |
| 挪威文對應 | `0069630` |
| 數量為 1 時的詞形變化 | `46ae22d` |
| 遊戲沒出的語言用英文官方名稱 | `2cef632` |
| 之後針對文案的修正（照原神現況判斷是否適用） | `337ce7d`、`6b0978e`、`307a45e`、`08bb4ab`、`8dbb5e9`、`a53f4f0` |

**不在這次範圍**：
- 子專案 9b 的功能本身（啟動畫面、系統「應用程式語言」雙向同步）。9b 先做（使用者 2026-11-22 選 A），所以這次 `0069630` 可以整個搬，包含 `locales_config.xml` 與送給系統的代碼改用 `nb`；`locales_config.xml` 也要列出補齊後的所有語言。
- 合併前 Crowdin 的處理（既有待辦「30 處原文改動要補傳翻譯」）與合併後的 Crowdin 同步：照鳴潮，翻譯先直接寫進 repo，合併後若被蓋掉再處理。
- README、商店文字（子專案 13、7）。

## 三、目標／非目標／反目標

**目標**：
- 31 種語言的 ARB key 全部齊全，佔位符與 ICU 參數名稱和範本一致。
- 遊戲有出的語言，遊戲用語逐字照官方；遊戲沒出的語言，玩家要在遊戲裡找的名稱用英文官方名稱。
- 數量相關的字串在每種語言都用正確的單複數。
- 阿拉伯文、希伯來文的版面正確鏡像；比例數字、遮罩 UID 不被倒過來。
- 1.3 倍字級下，所有語言的手機版面都不溢出。
- Android 啟動器名稱與無線偵錯配對通知在每種語言都有翻譯。
- 系統語言完全不在 App 支援範圍時顯示英文，不是南非語。

**非目標**：新增 App 不支援的語言（例如印尼文，遊戲有出但 App 沒有 ARB）；改變繁中原文的意思。

**反目標**：
- AI 自己猜卡池名稱（鳴潮法、西、葡、泰文一開始 12 個全錯）。
- 改動術語表既有 9 欄的內容。
- 翻譯者欄位寫錯：繁中、簡中保持空白，其他語言固定 `<a href="https://claude.com/claude-code">Claude Code</a>`（`locale_metadata_test` 鎖住）。
- Windows 版面或行為改變（RTL 修正除外，且只影響由右往左的語言）。

## 四、術語表

**來源（2026-11-22 查證）**：
- **祈願**：遊戲內祈願歷史頁是官方網頁 `https://gs.hoyoverse.com/genshin/event/e20190909gacha-v3/index.html`，它的 `bundle_*.js` 直接內含 15 種語言（`zh-cn`、`zh-tw`、`en-us`、`ja-jp`、`ko-kr`、`de-de`、`fr-fr`、`es-es`、`pt-pt`、`ru-ru`、`th-th`、`vi-vn`、`id-id`、`it-it`、`tr-tr`）的卡池名稱（例如 `"en-us":[{key:"100",name:"Novice Wishes"},{key:"301",...}]`）與頁面文字。下載到 scratchpad 的獨立資料夾當資料讀，不執行。
- **頌願**：頌願紀錄頁是 `https://gs.hoyoverse.com/genshin/event/e20250716gacha/index.html`，名稱不在 bundle 裡，是透過 HoYoverse 的 mi18n 服務（`https://webstatic-sea.hoyoverse.com/admin/mi18n/...`）載入，鍵名為 `beyond_gacha_type_1000`、`beyond_gacha_type_2000` 等。實作時先從 bundle／vendors 找出 mi18n 的專案名稱組出語系檔網址；找不到的話，請使用者在遊戲裡重新打開頌願紀錄頁（使用者 2026-11-22 同意），用 App 擷取到的網址在瀏覽器開啟，從開發者工具的網路請求取得語系檔。不要自動操作遊戲切換語言。

**要新增的欄位**：App 有 ARB、遊戲也有出的語言：`ko`、`de`、`ru`、`it`、`tr`。`pt_BR` 跟官方葡文（`pt-pt`），App 的 `pt`（葡萄牙）也一樣。

**要記錄的詞**：卡池名稱（含頌願）、側欄的祈願／頌願區塊標題、頁面標題「祈願歷史紀錄」、欄位名稱（類型、名稱、祈願類型、時間）、物品類型（角色、武器），以及 Android 系統用語（「無線偵錯」「使用配對碼配對裝置」等，照各語言 Android 官方譯名，沿用 ARB 引導頁已對過的寫法）。

**遊戲沒出的語言**（`af`、`ar`、`ca`、`cs`、`da`、`el`、`fi`、`he`、`hu`、`nl`、`no`、`pl`、`ro`、`sr`、`sv`、`uk`）：
- **用英文官方名稱**：卡池名稱與短名、側欄的祈願／頌願區塊標題、物品類型，以及句子裡提到的遊戲選單與頁面。句子裡只把名稱換成英文，其餘照常翻譯；需要詞尾變化時改寫句子，不要把詞尾黏在英文名稱後面。
- **照常翻譯**：App 自己的敘述與標籤（例如「還沒有祈願記錄」「祈願時間」「祈願總覽」、描述網址的「祈願記錄網址」）。
- 這條規則寫進術語表。既有 9 種語言遊戲都有出，不適用這條。

## 五、翻譯流程

兩個專案的原文都是繁中（`l10n.yaml` 範本 `app_zh.arb`、Crowdin 原文也是繁中）。鳴潮第 49 節那次批次翻譯讓子代理看英文文字翻、繁中 `@` 說明當語境；這次依原神規則改成以繁中為原文：
- **原文**：`app_zh.arb`（含 `@` 說明當語境），`app_en.arb` 當參考。省略號一律半形 `...`（含 CJK）。
- **分工**：子代理平行翻譯，每個負責 3 種語言，共用一份翻譯說明（術語表、上面第四節的規則、複數規則、引號與空格規則）。派子代理的指示用中文寫。
- **檢查腳本**（每個檔）：key 與範本一致、佔位符與 ICU 參數名稱不變、沒有殘留中日文（遊戲沒出的語言）、翻譯者欄位正確、`@@locale` 正確（不帶地區碼）。
- **既有 9 種語言**：補上缺的 key；依術語表校正卡池名稱；做第六節的複數修正。
- 全部回來後跑 `fvm flutter gen-l10n`、analyze、完整測試。

## 六、程式與資源改動

- **複數**（`4a23e4c`、`46ae22d`）：範本的佔位符型別是 `int`／`num` 時，其他語言可以寫 ICU plural。`=1{}`／`one{}`／`few{}`／`many{}` 的選擇照第 49 節（英、德、西、葡、北歐、荷、希等用 `=1`；法文用 `one`；斯拉夫語系、阿拉伯、羅馬尼亞照 CLDR）。新增 `test/l10n/plural_forms_test.dart` 抽查幾種語言在 1 與 2 時的輸出。
- **不支援的語言改回英文**（`cde6409`）：`lib/state/localization_metadata.dart` 的 `localeListResolution` 在整份清單都對不上或清單為空時回傳英文；`nb`／`nn` 對到 `no`。`locale_metadata_test` 用實際語言清單鎖住。
- **由右往左**（`f87c2a4`）：卡片彩色邊條、進度條對齊與漸層、垂直時間軸軸線、水平捲動區的邊緣漸層與箭頭改用 directional；比例數字（「5 / 80」）與遮罩 UID 固定 `TextDirection.ltr`；遊戲資料文字（HoYoWiki 說明）在由右往左介面裡用 `Directionality(ltr)` 包住。新增 `test/widgets/rtl_layout_test.dart` 以阿拉伯文鎖住。實際要改的位置以原神程式為準（原神的元件和鳴潮不完全一樣，例如原神圖片來自 HoYoWiki）。
- **長字串溢出**（`7370042`）：`phone_layout_pages_test` 的「1.3 倍字級不溢出」改跑全部語言並加上設定頁；抓到的溢出照鳴潮的修法（`CompactLegendRow`、`Wrap`）處理。
- **Android 原生字串**（`d6bf944`、`0069630` 的資料夾部分）：所有語言都要有 `res/values-*/strings.xml`，App 名稱沿用各語言 ARB 的 `appName`，系統用語照術語表；資料夾代碼：希伯來文 `values-iw`、挪威文 `values-nb`、巴西葡文 `values-pt-rBR`、繁中 `values-zh-rTW`、簡中 `values-zh-rCN`、英文 `values/`。單、雙引號要跳脫。照搬鳴潮擴充後的 `test/l10n/android_locales_config_test.dart`：`locales_config.xml` 列出的每種語言都有字串檔，且字串名稱與英文版一致（`locales_config.xml` 由 9b 帶進）。
- **Crowdin**：`crowdin.yml` 照鳴潮加一組 `strings.xml`（以 `values-zh-rTW/strings.xml` 為原文、`languages_mapping`、`translation_replace`、`"no": nb` 加引號）。

## 七、驗收

- `fvm dart format lib/ test/`、`fvm flutter analyze`（`No issues found!`）、`fvm flutter test`（`All tests passed!`）。
- 每個語系檔通過檢查腳本；術語表新增欄位的每個詞都能指回官方來源。
- **模擬器**：用 `adb shell cmd locale set-app-locales tw.reh.genshin.gacha --locales <code>` 切換，至少看阿拉伯文（由右往左）、德文（長字串）、韓文（遊戲有出）、挪威文 `nb`（對到 `no`）、一個不支援的語言（例如印尼文，應顯示英文）；啟動器名稱與配對通知看一種新語言。
- **Windows**：備份 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer\shared_preferences.json` 後，把 `flutter.pref.locale` 改成 `ar` 啟動看由右往左版面，驗完還原。實體輸入要使用者同意。

## 八、留給實作者決定

- 子代理的分組（每組 3 種語言的組合）與翻譯說明的寫法。
- 由右往左與溢出修正的實際位置（以測試抓到的為準）。
- 鳴潮後續文案修正（第二節最後一列）在原神是否適用，逐一判斷並在附錄記錄。

## 附錄：驗收結果

2026-11-22，commit `7c918b2`～`1cf32cf`。

- **自動化**：`fvm flutter analyze` 無問題；`fvm flutter test` 全數通過（+2312）；release APK 建置成功（aapt2 接受全部 `strings.xml`）。31 個 ARB 都通過檢查腳本（key、佔位符與 ICU 參數、翻譯者欄位、`@@locale`、遊戲沒出的語言無中日文、複數類別、遊戲有出的非英文語言 `kind*`／`gachaType*` 不等於英文、不含字面 `\n`）。
- **術語表來源**：祈願取自 `e20190909gacha-v3` 頁的 `bundle_*.js` 與 mi18n 專案 `m20240201hy47qinta8`；頌願取自頌願頁 bundle 寫死的 mi18n 專案 `m20250904hy2dmxqebk`（`https://webstatic.hoyoverse.com/admin/mi18n/hk4e_cn/m20250904hy2dmxqebk/m20250904hy2dmxqebk-<語言>.json`，`hk4e_global` 底下是空檔），使用者在遊戲裡重開頌願頁後從 Windows 遊戲的網頁快取找到。新增欄位逐字照官方；既有 9 欄有 4 處與官方 bundle 寫法不同（en「Standard Wish」、pt 兩個活動祈願、fr 武器活動祈願），依「既有 9 欄不改」維持。
- **模擬器（wuwa_api37，Android 17，debug 版）**：
  - 阿拉伯文：卡片彩色邊條在右、圖例文字在右數值在左、「0 / 90」「0 / 10」維持由左往右、五星頭像數量徽章在左下、記錄列表鏡像；側欄卡池名稱為英文。
  - 德文：側欄用官方用語（Gebet、Wunsch、Figur、Waffe）；設定頁長字串排版正常。驗收時發現德、荷、南非語引導頁 5 個字串與義、加泰隆尼亞、葡萄牙文 1 個字串把換行寫成字面 `\n`（畫面直接顯示），已修正（`1cf32cf`）並加 `arb_newline_test` 鎖住，重建後確認換行正常。
  - 韓文：介面為韓文。挪威文 `nb`：系統端設 `nb` 後 App 顯示挪威文，log `adopted from system tag=nb pref=LocaleLanguage(no)`。
  - 印尼文：系統端設 `id` 時 App 記一筆 `not offered` 警告並保留原本語言（9b 的設計）。「整份系統語言都不支援時顯示英文」在模擬器上不易重現（Android 會把系統語言接在 App 語言後面），與鳴潮結論相同，由 `locale_metadata_test` 鎖住。
  - 啟動器名稱：`aapt dump badging` 列出 85 個 `application-label-*`，抽查 ar、de、iw、ko、nb、pt、pt-BR、uk、zh-TW 都對應各語言 ARB 的 `appName`。配對通知需走完開發人員選項等步驟才會出現，未在模擬器實看，由 `android_locales_config_test` 與 release 建置確認字串檔齊全。
  - 測完還原：App 語言未設定（App 同步回「跟隨系統」）、系統淺色；log 沒有 SEVERE。
- **Windows（debug 版）**：備份整個 `%APPDATA%\tw.reh\genshin_impact_wish_gacha_analyzer` 後，把 `flutter.pref.locale` 從 `system` 改成 `ar` 啟動，只截圖不操作：視窗標題為阿拉伯文、側欄在右、垂直時間軸的軸線與圓點同在右側、卡片邊條在右、遮罩 UID 順序正常。驗完用 PID 關閉並還原 `shared_preferences.json`（值回到 `system`），log 沒有警告。

### 鳴潮後續文案修正

- `337ce7d`（網址與遊戲 log 的說法）：**部分適用**。原神的 Android 設定流程與手動輸入網址等字串早已是修正後的說法（`setupWhatBody`、`setupNeedTitle`、`setupStepPairBody`、`settingsUnpairConfirmBody`、`progressCredentialReady`、手動輸入網址相關標題皆已就緒），不用動。仍是舊說法而已修正的：`progressWaitingLog`、`progressCaptureUnavailableHint`、`gameDirHelpNotFound`（「祈願記錄」被當成要輸入或讀取的內容，改為「在遊戲中開啟祈願歷史記錄頁」「取得祈願記錄網址」），以及 zh／zh_Hans 的 `logUnavailableNotPaired`、`settingsLogAccess`、`setupTitle`、`setupWhyBody`（「遊戲記錄」「系統記錄」改為「遊戲 log」「系統 log」，原神讀的是 logcat 而非檔案，所以不加「檔」）、`logUnavailableUnsupported`（「手動輸入」補成「手動輸入網址」）。既有 8 種語言中，en、ja 等原本就用「log」的不必改 log 用詞，只改上述意思有變的字串。`gameDirInvalid` 原神本來就說找不到原神，不適用。
- `6b0978e`（確認讀取方式改為說明讀取遊戲 log）：**不適用**，被 `307a45e` 取代，且原神已是「正在準備讀取…」。
- `307a45e`（每次更新的步驟改成「準備讀取」）：**適用，但原神已經是這個說法**（`progressCheckingLogAccess` 已為「正在準備讀取遊戲記錄...」），只需把「遊戲記錄」改為「遊戲 log」，已併入 `337ce7d` 的修改。
- `08bb4ab`（用「裝置」取代「手機」、不寫死商店清單）：**不適用**，原神 `logUnavailableGameNotInstalled` 已是「這台裝置上找不到原神…」且無商店清單；`logChooseGameVersion` 在原神不存在。
- `8dbb5e9`（台灣用語「飛航模式」）：**不適用**，原神 zh 沒有「飛行模式」或「飛航模式」相關字串（`manualCredentialHelpAndroid` 在原神不存在）。
- `a53f4f0`（把 `progressCheckingLogAccess` 翻成所有語言）：**不適用於本任務**，原神這個 key 已在 8 種語言有翻譯，其餘 22 種空殼語言留給 Task 5。
