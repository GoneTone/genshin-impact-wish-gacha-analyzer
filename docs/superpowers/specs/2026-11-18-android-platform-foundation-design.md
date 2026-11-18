# Android 平台基礎（子專案 1）— 設計 spec

- 狀態：已核准（2026-11-18）
- 日期：2026-11-18
- 上層文件：`2026-11-17-android-support-roadmap-design.md`
- 對應鳴潮版：`wuthering-waves-convene-gacha-analyzer` 的 `2026-11-05-android-platform-foundation-design.md`，以及 commit `a862386`、`89704b5`、`3fba7de`、`3b537ae`、`6c97924`、`b36ff4a`、`8f81306`；移植筆記 #4～#14

---

## 一、目的

讓 App 能在 Android 上建置、安裝、啟動，作為後續所有 Android 子專案的地基。現況是連啟動都做不到：`main.dart` 無條件執行 `RustLib.init()`，但 Android 上沒有 Rust 函式庫，初始化失敗會被 `runZonedGuarded` 吞掉，結果 `runApp` 永遠不會執行，畫面停在空白。

## 二、目標／非目標／反目標

**目標**

- 新增 `android/` 平台，applicationId 是 `tw.reh.genshin.gacha`（路線圖第六節）。minSdk 沿用 Flutter 預設的 `flutter.minSdkVersion`（目前是 24，也就是 Android 7），和鳴潮版一致。
- 在 Android 上能啟動 App，不依賴 Windows 的功能都能正常使用：第三方匯入、總覽、各卡池頁、設定。
- 啟動時的 log 會寫進 Android 上的 log 檔。

**非目標（留給後續子專案）**

- 在手機上取得紀錄（子專案 2）。在那之前，Android 上的「更新」不會成功，這是預期內的。
- 手機版面（3）、另存新檔／分享（4）、雲端同步登入（5）、正式簽章與上架（7）。
- 換成原創圖示、自適應圖示、Play 商店圖示（7，見 3.2 第 4 點）。
- 其餘 22 種語言的 App 名稱（11）。

**反目標**

- Windows 版的行為、建置或測試有任何改變（圖示重新產生後的像素差異除外，見 3.2 第 4 點）。
- 為了這個子專案把 Rust 的 Android 編譯目標加進 App 自己的建置需求。

## 三、做法

### 3.1 考慮過的做法

| 做法 | 取捨 | 結論 |
|---|---|---|
| **Android 不編譯 App 的 Rust，啟動時依平台略過** | 原神版的 Rust（`genshin_capture_core`）只負責 Windows 的 MITM 攔截與它的 log 串流，Android 上完全用不到。改動只在 `main.dart` | ✅ 採用（和鳴潮版相同） |
| 用 cargokit 的 Gradle 外掛把 Rust 編進 Android | 要先把憑證安裝、系統代理等 Windows 專用程式碼用 `cfg(windows)` 隔開，還要把 `rust_builder` 接進 Gradle。這些都只是為了一個手機上用不到的模組 | ❌ |

`rust_builder/pubspec.yaml` 雖然宣告了 android 平台，但它不在 App 的 `pubspec.yaml` 依賴裡，也沒有 `android/` 目錄，不會被 Gradle 建置（和鳴潮版相同）。

### 3.2 改動

1. **建立 Android 平台**（筆記 #4）：用 `fvm flutter create --platforms=android --org tw.reh .` 產生 `android/`，再把 `applicationId` 和 `namespace` 改成 `tw.reh.genshin.gacha`、Kotlin 套件路徑改成 `tw/reh/genshin/gacha`，並刪掉範本裡關於 applicationId 的 TODO 註解（鳴潮版 `8f81306`）。`minSdk` 維持 `flutter.minSdkVersion`。執行後要處理 `flutter create` 順手改到的檔案：還原 `pubspec.lock`、刪掉 `test/widget_test.dart`、手動合併 `.metadata`（保留 windows，新增 android）。`analysis_options.yaml` 自動加上的 `android/**` 排除保留。
2. **建置設定**（筆記 #5～#7）：
   - `android/app/build.gradle.kts` 保留 `ndkVersion = flutter.ndkVersion`。`super_clipboard` 依賴的 `super_native_extensions` 仍會用 cargokit 在 Android 編 Rust，沒設 NDK 版本 cargokit 會直接報錯。
   - `android/gradle.properties` 加 `kotlin.incremental=false`（pub cache 在 C 槽、專案在 E 槽時，Kotlin 增量編譯會失敗）。
   - 新增 `android/cargokit_gradle9_shim.gradle`，在 `android/build.gradle.kts` 第一行 `apply(from = ...)`。內容照搬鳴潮版最後的版本（`6c97924` 之後）：用 `ext.exec` 補回 Gradle 9 移除的 `Project.exec()`，轉接到 `@Inject` 注入的 `ExecOperations`（不吞 cargo 輸出），並用 `afterEvaluate` 把兩個外掛寫死的 `compileSdkVersion 31` 改成 `:app` 的 compileSdk。上游修正發布後刪除。
3. **`lib/main.dart`**：`RustLib.init()` 和 `_connectRustLogStream()` 只在 `Platform.isWindows` 時執行。dartdoc 跟著更新，註明 Rust 只提供 Windows 的攔截功能。
4. **App 圖示**（筆記 #10）：原神版沒有圖示產生工具，現有圖示最大只有 256px（`assets/icons/3.0x/app_icon.png` 與 `.ico`），是從舊 master 的 `build/icons/` 複製來的。
   - 從 git 歷史（`16eab50` 的 `build/icons/1024x1024.png`，`128f035` 刪除前的最後版本）取出 1024×1024 原圖，放到 `tool/app_icon_source.png` 當主檔。已比對：它縮到 256 後和現有圖示的平均像素差約 2.5/255，是同一張圖。
   - 移植鳴潮版 `tool/generate_app_icons.dart` 在子專案 1 時的版本（`89704b5`）：輸出 `assets/icons/` 的 1×／2×／3× 圖、Windows 多解析度 `.ico`，以及 Android `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（48／72／96／144／192）。`pubspec.yaml` 的 dev_dependencies 加 `image`（和鳴潮版相同）。
   - 執行工具會一併重新產生 Windows `.ico` 與 `assets/icons/`，肉眼看不出差別。
   - **這張主檔只是暫時的**。它是胡桃的二創圖，有繪師與 HoYoverse 兩層權利；Google Play 的智慧財產權政策把與原作無法區分的「fan art」列為違規範例，冒用政策也把「在圖示中照抄知名作品的角色」列為誤導使用者的範例。使用者決定（2026-11-18）在子專案 7 換成不含角色的原創圖示，時間點和鳴潮版（`884323c`，在 Play CI 之後換圖）一致，自適應圖示與 512px 商店圖示也在那時一起做。debug 版不公開，這段期間沒有風險。
5. **App 名稱**（筆記 #11）：Android 的 `android:label` 無法讀 ARB，改用 `@string/app_name`，由 `res/values*/strings.xml` 提供。這次做目前 ARB 已有 `appName` 的 9 種語言，內容逐字照抄 ARB（使用者決定，2026-11-18）：

   | ARB | 資料夾 |
   |---|---|
   | `app_en.arb` | `values`（預設） |
   | `app_zh.arb` | `values-zh-rTW` |
   | `app_zh_Hans.arb` | `values-zh-rCN` |
   | `app_ja.arb` | `values-ja` |
   | `app_es.arb` | `values-es` |
   | `app_fr.arb` | `values-fr` |
   | `app_pt_BR.arb` | `values-pt-rBR` |
   | `app_th.arb` | `values-th` |
   | `app_vi.arb` | `values-vi` |

   th、vi 的 `appName` 目前和英文相同，一樣照抄，子專案 11 翻好後再更新。其餘 22 種語言在子專案 11 補 ARB 時一起加（鳴潮版也是子專案 1 先做核心語言、子專案 11 補齊）。
6. **權限**：主 manifest 只宣告 `INTERNET`。其他權限等到用到的子專案再加。
7. **語言解析**（筆記 #12、#13）：原神版的 `lib/state/localization_metadata.dart` 和鳴潮版修改前的內容完全相同，照搬兩個 commit：
   - `3fba7de`：`localeListResolution` 把 `zh-Hant-*` 明確對應到裸 `zh`。Android 回報的系統語言帶 script code（`zh-Hant-TW`），目前會被排在後面的 `zh-Hans-CN` 搶走，繁中使用者看到簡中。
   - `b36ff4a`：包一層 `GlobalMaterialLocalizations`／`GlobalCupertinoLocalizations` 的 delegate，遇到裸 `zh` 時載入 `zh-Hant-TW`，`MaterialApp` 改用這份清單。這個問題 Windows 也有（例如關閉按鈕的提示文字顯示「关闭」），一併修正。
   - 兩者都附上鳴潮版的測試（`test/l10n/locale_metadata_test.dart`）。
8. **匯入亂碼**（筆記 #14）：原神版的 `cross_file` 是 `0.3.5+2`，`file_selector` 在 Android 回傳 `XFile.fromData`，`readAsString` 會把中文讀成亂碼。照搬 `3b537ae`：把 `cross_file` 升到 `0.3.5+5` 以上（只動 `pubspec.lock`），並在 `test/services/accounts_import_test.dart` 加回歸測試。依賴有變動，Android 建置前先 `flutter clean`（筆記 #8）。

### 3.3 不改的部分（以及原因）

和鳴潮版相同，這次不刻意隱藏只能在 Windows 用的介面。正式發布要等子專案 7，在那之前只有開發用的測試版；現在先隱藏，之後子專案 2～5 又要一一改回來。目前已知在 Android 上不能用、但也不會讓 App 崩潰的項目：

- 「更新」：MITM 攔截需要 Rust，`startCapture` 會丟例外；子專案 0 的讀網頁快取靠登錄檔和 win32 定位遊戲資料夾，也找不到。預期走既有的失敗處理或停在等待畫面，可以取消，不能崩潰 → 子專案 2
- 設定頁的「遊戲資料夾」區塊：`GameDirLocator.locate()` 外層有 `catch (e)`，Android 上讀登錄檔、載入 win32 失敗會被接住，顯示找不到 → 子專案 2
- 匯出、另存 log、存分享圖、存物品圖：`file_selector` 在 Android 上沒有實作 `getSaveLocation`，會丟 `UnimplementedError` → 子專案 4
- 「開啟 log 資料夾」：Android 不能打開 `file://` → 子專案 4
- 雲端同步登入 → 子專案 5
- 視窗相關（`window_manager`）：大多已經有 `Platform.isWindows` 防護；沒有防護的地方例外會被接住並記一筆 log → 不處理

## 四、驗收條件

1. `fvm flutter build apk --debug` 成功。
2. 在測試機上安裝並啟動，能看到總覽頁，log 裡有 `app start ... on android`。log 檔放在 App 的私有目錄，debug 版可以用 `adb shell run-as tw.reh.genshin.gacha ls files/...` 讀取。
3. 在 Android 上用第三方匯入功能匯入一份紀錄（含中文帳號別名）後，總覽和卡池頁都能正確顯示，中文不是亂碼。
4. 切換主題和語言正常；系統語言是繁中時 App 顯示繁中；App 名稱依系統語言顯示各 ARB 的 `appName`；圖示正確。
5. 在 Android 上按「更新」不會崩潰，可以取消或看到錯誤。
6. Windows：`fvm flutter build windows` 成功，Windows 上的「更新」照常運作（log 裡有 `rust log stream connected`）。
7. `fvm dart format lib/ test/`、`fvm flutter analyze`（No issues found!）、`fvm flutter test`（All tests passed!）全部通過。

## 五、風險與留給實作的部分

- **`super_clipboard` 的 Android 原生層**：開發機為了 Windows 一定裝了 rustup，cargokit 會從原始碼編 `super_native_extensions`，需要 Rust toolchain 與 NDK（筆記 #5）。CI 的 Android job 也要裝 Rust，到子專案 7 處理。
- **沒有初始化 Rust 時呼叫 FRB 會同步丟 `StateError`**（筆記 #5）。子專案 1 靠既有的錯誤處理接住；子專案 2 會在進入攔截前就依平台分流。之後新增 Rust 呼叫點時也要先分流。
- **圖示**：暫時主檔、一般 mipmap PNG，不做自適應圖示。換圖與自適應圖示在子專案 7。
- **簽章**：這個子專案只用 debug 簽章，正式的 keystore 在子專案 7 處理。
