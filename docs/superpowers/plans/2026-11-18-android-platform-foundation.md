# Android 平台基礎 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 App 能在 Android 上建置、安裝、啟動，並正常使用不依賴 Windows 的功能，Windows 版不受影響。

**Architecture:** 用 `flutter create` 加入 `android/` 平台，套件名稱改為 `tw.reh.genshin.gacha`。Android 上不編譯也不載入 App 的 Rust：`main.dart` 只在 Windows 初始化 Rust bridge 和 Rust log 串流。App 名稱用 `strings.xml` 提供 9 種語言；圖示產生工具從鳴潮版移植。另外照搬鳴潮版的兩個語言解析修正與 `cross_file` 升級。

**Tech Stack:** Flutter 3.47.5（FVM）、Gradle Kotlin DSL（Flutter 範本）、`image` 套件（圖示工具，dev dependency）

**Spec:** `docs/superpowers/specs/2026-11-18-android-platform-foundation-design.md`（上層：`docs/superpowers/specs/2026-11-17-android-support-roadmap-design.md`）

**對照來源：** 姐妹專案 `E:\IdeaProjects\wuthering-waves-convene-gacha-analyzer`（下稱「鳴潮版」）。各 Task 標明要照搬的 commit，用 `git -C ../wuthering-waves-convene-gacha-analyzer show <commit>` 看原始 diff。照搬時只換套件名（`wuthering_waves_convene_gacha_analyzer` → `genshin_impact_wish_gacha_analyzer`、`tw.reh.wuwa.gacha` → `tw.reh.genshin.gacha`）與術語，其餘逐字一致。

## Global Constraints

- applicationId 和 namespace：`tw.reh.genshin.gacha`（上架後不能改，必須逐字一致）。
- minSdk：維持 `flutter.minSdkVersion`，不要寫死數字。
- 主 manifest 只宣告 `android.permission.INTERNET`，不加其他權限。
- 不把 `rust_builder` 接進 Android Gradle，不改 `rust/`、`rust_builder/`。
- Windows 的行為不能改變：新條件都以 `Platform.isWindows` 為真時維持原本的路徑。
- 所有 Flutter／Dart 指令透過 `fvm`。每次 commit 前依序跑 `fvm dart format lib/ test/`、`fvm flutter analyze`（No issues found!）、`fvm flutter test`（All tests passed!）。
- Commit message 用英文 conventional commits，結尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。不要 push。
- 註解和 dartdoc 用中文全形標點，log 訊息用英文；所有新宣告都要有一行 `///` dartdoc（Flutter override 除外）。
- 依賴有變動後，建 APK 前先 `fvm flutter clean`（筆記 #8：只改 `pubspec.lock` 時 Dart 不會重新編譯）。
- 測試裝置：Android 模擬器 `Medium_Phone_API_36.0`（Android 16，x86_64，使用者 2026-11-18 指定，不占用實機）。啟動：`"$LOCALAPPDATA/Android/Sdk/emulator/emulator.exe" -avd Medium_Phone_API_36.0`（背景執行），等 `adb -e wait-for-device` 且 `getprop sys.boot_completed` 為 1。adb 一律用 `adb -e`。使用者的實機若同時接上也不要動它。

## Review Focus

1. **在 Android 上按「更新」**：Rust 沒初始化，`startCapture` 會同步丟 `StateError`；子專案 0 的讀網頁快取也定位不到遊戲資料夾。預期顯示錯誤，或停在等待畫面但可以取消，不能崩潰或卡死 → Task 5 Step 4。
2. **Android 匯入的檔案選擇器**：`file_selector` 把 `.json` 對應成 MIME 類型的方式不確定，檔案可能變灰選不到。預期能選到 `.json` 備份檔，中文別名不是亂碼 → Task 5 Step 3。
3. **系統語言是繁中（`zh-Hant-TW`）**：預期 App 顯示繁中，Material 內建文字（例如關閉按鈕的提示）也是繁中 → Task 3 的測試與 Task 5 Step 5。
4. **第一次啟動、沒有任何資料**：預期顯示空的總覽頁，不崩潰 → Task 1 Step 6。
5. **Windows 不受影響**：Rust log 串流照常連上（log 裡有 `rust log stream connected`），「更新」照常運作 → Task 5 Step 6。

---

### Task 1: 加入 Android 平台，並讓 App 在 Android 上能啟動

照搬鳴潮版 `a862386`、`6c97924`、`8f81306`。

**Files:**
- Create: `android/**`（由 `flutter create` 產生）
- Modify: `android/app/build.gradle.kts`（`namespace`、`applicationId`；刪掉範本的 applicationId TODO）
- Move: `MainActivity.kt` → `android/app/src/main/kotlin/tw/reh/genshin/gacha/MainActivity.kt`（`package tw.reh.genshin.gacha`）
- Modify: `android/app/src/main/AndroidManifest.xml`（`INTERNET`；`android:label="@string/app_name"`）
- Create: `android/app/src/main/res/values{,-zh-rTW,-zh-rCN,-ja,-es,-fr,-pt-rBR,-th,-vi}/strings.xml`
- Modify: `android/gradle.properties`（`kotlin.incremental=false` 與中文說明註解）
- Create: `android/cargokit_gradle9_shim.gradle`（內容照搬鳴潮版目前的檔案，即 `6c97924` 之後的版本）
- Modify: `android/build.gradle.kts`（第一行 `apply(from = "cargokit_gradle9_shim.gradle")`，寫法照鳴潮版）
- Modify: `.metadata`、`analysis_options.yaml`（`flutter create` 的改動，見 Step 1）
- Modify: `lib/main.dart:32-38,68,124`

**Interfaces:**
- Produces: Android 套件 `tw.reh.genshin.gacha`；字串資源 `@string/app_name`；`android/app/src/main/res/` 目錄（Task 2 輸出 mipmap 到這裡）。

- [ ] **Step 1: 產生 Android 平台**

Run: `fvm flutter create --platforms=android --org tw.reh .`
接著 `git status --short`。處理方式（筆記 #4）：
- `pubspec.lock` 被改到 → `git checkout -- pubspec.lock`；
- 新增的 `test/widget_test.dart` → 刪除；
- `.metadata` → 手動合併：保留原本的 windows 紀錄，只新增 android；
- `analysis_options.yaml` 自動加的 `android/**` 排除 → 保留；
- 其他既有檔案被改到 → 還原。
Expected: 最後除了 `android/`、`.metadata`、`analysis_options.yaml` 之外沒有變動。

- [ ] **Step 2: 改套件名稱與建置設定**

`build.gradle.kts` 的 `namespace` 和 `defaultConfig.applicationId` 改成 `"tw.reh.genshin.gacha"`，刪掉 applicationId 上方的範本 TODO 註解，`minSdk = flutter.minSdkVersion`、`ndkVersion = flutter.ndkVersion` 保持不變。`MainActivity.kt` 移到 `kotlin/tw/reh/genshin/gacha/`，改 package 宣告，刪掉舊的空資料夾。依 Files 清單加上 `kotlin.incremental=false` 與 cargokit shim。

- [ ] **Step 3: manifest 和 App 名稱**

主 manifest 在 `<application>` 前加 `<uses-permission android:name="android.permission.INTERNET"/>`，`android:label` 改成 `@string/app_name`。9 份 `strings.xml` 格式照鳴潮版（`<resources><string name="app_name">…</string></resources>`），值逐字取自各 ARB 的 `appName`：

| 檔案 | 值（來源 ARB） |
|---|---|
| `values/` | `Genshin Impact Wish Gacha Analyzer`（`app_en.arb`） |
| `values-zh-rTW/` | `原神祈願卡池分析`（`app_zh.arb`） |
| `values-zh-rCN/` | `原神祈愿卡池分析`（`app_zh_Hans.arb`） |
| `values-ja/` | `原神祈願分析ツール`（`app_ja.arb`） |
| `values-es/` | `Analizador de Gacha de Genshin Impact`（`app_es.arb`） |
| `values-fr/` | `Analyse des vœux Genshin Impact`（`app_fr.arb`） |
| `values-pt-rBR/` | `O analisador de gacha de Genshin Impact`（`app_pt_BR.arb`） |
| `values-th/` | `Genshin Impact Wish Gacha Analyzer`（`app_th.arb`） |
| `values-vi/` | `Genshin Impact Wish Gacha Analyzer`（`app_vi.arb`） |

- [ ] **Step 4: `main.dart` 只在 Windows 初始化 Rust**

`await RustLib.init();`（第 38 行）移進既有的 `if (Platform.isWindows)` 區塊第一行；`unawaited(_connectRustLogStream());`（第 68 行）包進 `if (Platform.isWindows)`。`main()` 的 dartdoc 改成「應用程式入口：初始化 Flutter、Rust bridge（僅 Windows）、視窗管理、log 服務，然後啟動 app。」並加一行「Rust 只提供 Windows 的攔截功能，其他平台不編譯也不載入 Rust 函式庫。」；`_connectRustLogStream` 的 dartdoc 補「只在 Windows 呼叫」。其他行不動。

- [ ] **Step 5: 建置 APK**

Run: `fvm flutter build apk --debug`
Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`。失敗時對照筆記 #5～#7 與鳴潮版的對應檔案；仍無法解決就停下來回報，不要自行加其他 Gradle 設定。

- [ ] **Step 6: 在實機上安裝並啟動（Review Focus 4）**

Run: `adb -e install -r build/app/outputs/flutter-apk/app-debug.apk`，再 `adb -e shell am start -n tw.reh.genshin.gacha/.MainActivity`，等 5 秒。
Expected:
- 畫面顯示總覽頁而不是空白（`adb -e exec-out screencap -p > <scratchpad>/android_start.png` 截圖確認）。
- `adb -e shell run-as tw.reh.genshin.gacha sh -c 'cat files/logs/*.log' | grep "app start"` 有一行包含 `on android`（log 在 `<applicationSupport>/logs/`；路徑不對時用 `run-as ... find . -name '*.log'` 找）。
- `adb -e logcat -d | grep -E "FATAL|flutter.*(Unhandled|Exception)"` 沒有本 App 的致命錯誤。

- [ ] **Step 7: 品質檢查並 commit**

```bash
git add android/ .metadata analysis_options.yaml lib/main.dart
git commit -m "feat(android): add Android platform and skip Rust bridge on non-Windows"
```
Commit body 比照鳴潮版 `a862386`，列出套件名、Rust 只在 Windows、Kotlin 增量編譯、Gradle 9 shim 四點，App 名稱寫 9 種語言。

---

### Task 2: 圖示產生工具與 Android 啟動器圖示

照搬鳴潮版 `89704b5` 時的 `tool/generate_app_icons.dart`（`git -C ../wuthering-waves-convene-gacha-analyzer show 89704b5:tool/generate_app_icons.dart`）。**不要**拿鳴潮版目前的版本：自適應圖示與商店圖示屬於子專案 7。

**Files:**
- Create: `tool/app_icon_source.png`（`git show 16eab50:build/icons/1024x1024.png`，以二進位寫出）
- Create: `tool/generate_app_icons.dart`
- Modify: `pubspec.yaml`、`pubspec.lock`（dev_dependencies 加 `image: ^4.10.1`）
- Modify（工具輸出）: `assets/icons/app_icon.png`、`assets/icons/2.0x/app_icon.png`、`assets/icons/3.0x/app_icon.png`、`windows/runner/resources/app_icon.ico`
- Create（工具輸出）: `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（覆蓋 Flutter 預設圖示）

**Interfaces:**
- Consumes: Task 1 的 `android/app/src/main/res/`。
- Produces: `fvm dart run tool/generate_app_icons.dart`，子專案 7 換主檔後重跑同一支工具。

- [ ] **Step 1: 取出主檔並確認**

Run: `git show 16eab50:build/icons/1024x1024.png > tool/app_icon_source.png`（在 Git Bash 執行，避免 PowerShell 改寫二進位）。
Expected: 檔案約 1.3 MB，是 1024×1024 的 PNG（可用 `fvm dart` 或 Python 讀尺寸確認）。

- [ ] **Step 2: 加依賴與工具**

Run: `fvm flutter pub add --dev image:^4.10.1`。`pubspec.lock` 的 diff 只能是新增 `image` 和它的間接依賴，既有套件版本不能變；有變就還原後改用手動編輯 `pubspec.yaml` 再 `fvm flutter pub get`。工具照搬 `89704b5` 版本，檔頭 dartdoc 逐字保留（主檔路徑、用法都相同）。

- [ ] **Step 3: 執行工具並確認**

Run: `fvm dart run tool/generate_app_icons.dart`
Expected: 印出 3 行 `assets/icons`、1 行 `.ico`、5 行 `android/...`，每行開頭是 `✓`。`assets/icons` 與 `.ico` 會有 binary diff（從 1024 重新縮圖，平均像素差約 2.5/255），用 Read 看 `assets/icons/3.0x/app_icon.png` 確認仍是同一張圖。

- [ ] **Step 4: 實機確認**

重新建置並安裝 APK（Task 1 Step 5～6），用截圖確認模擬器桌面上的圖示是本 App 的圖示，不是 Flutter 預設的藍色圖示。

- [ ] **Step 5: 品質檢查並 commit**

```bash
git add tool/ pubspec.yaml pubspec.lock assets/icons/ windows/runner/resources/app_icon.ico android/app/src/main/res/
git commit -m "feat(android): generate Android launcher icons from the shared icon source"
```
Commit body 註明：工具從鳴潮版移植；主檔取自舊 master 的 1024 原圖，是暫時的，子專案 7 會換成原創圖示。

---

### Task 3: 繁中系統語言的解析修正

照搬鳴潮版 `3fba7de`（`zh-Hant-*` → 裸 `zh`）與 `b36ff4a`（裸 `zh` 時 Material／Cupertino 載入 `zh-Hant-TW`），兩個 commit 分開提交。原神版的 `lib/state/localization_metadata.dart` 和鳴潮版 `3fba7de^` 時逐字相同（只差套件名），diff 應能直接套用。

**Files:**
- Modify: `lib/state/localization_metadata.dart`
- Modify: `lib/main.dart:189`（`localizationsDelegates` 改用 `b36ff4a` 新增的 delegate 清單）
- Test: `test/l10n/locale_metadata_test.dart`

**Interfaces:**
- Produces: `b36ff4a` 新增的公開宣告，名稱與簽名照鳴潮版。

- [ ] **Step 1: 寫 `3fba7de` 的測試並確認失敗**

把 `3fba7de` 在 `test/l10n/locale_metadata_test.dart` 新增的測試照搬過來。
Run: `fvm flutter test test/l10n/locale_metadata_test.dart`
Expected: 新測試 FAIL（`zh-Hant-TW` 解析成 `zh_Hans`），其餘 PASS。

- [ ] **Step 2: 套用 `3fba7de` 的實作，測試通過，品質檢查後 commit**

Run: 同上，Expected: 全部 PASS。commit 訊息用 `fix(l10n): resolve zh-Hant-* system locales to Traditional Chinese`，body 比照鳴潮版。

- [ ] **Step 3: 寫 `b36ff4a` 的測試並確認失敗**

照搬 `b36ff4a` 新增的測試。Expected: 新測試 FAIL（因為宣告不存在而編譯失敗也算）。

- [ ] **Step 4: 套用 `b36ff4a` 的實作與 `main.dart` 改動，測試通過，品質檢查後 commit**

Expected: 全部 PASS。commit 訊息用 `fix(l10n): show Traditional Chinese Material and Cupertino strings for bare zh`。

---

### Task 4: 升級 `cross_file`，修正 Android 匯入亂碼

照搬鳴潮版 `3b537ae`。

**Files:**
- Modify: `pubspec.lock`（`cross_file` `0.3.5+2` → `0.3.5+5` 以上）
- Test: `test/services/accounts_import_test.dart`

- [ ] **Step 1: 寫回歸測試並確認失敗**

照搬 `3b537ae` 的測試 `Android 選檔回傳的 XFile.fromData 以 UTF-8 讀出別名（防 cross_file 亂碼回歸）`：`XFile.fromData(utf8.encode('{"alias": "我的帳號"}')).readAsString()` 經 `jsonDecode` 後等於 `{'alias': '我的帳號'}`。
Run: `fvm flutter test test/services/accounts_import_test.dart`
Expected: 新測試 FAIL（讀出亂碼）。

- [ ] **Step 2: 升級並確認**

Run: `fvm flutter pub upgrade cross_file`
Expected: `pubspec.lock` 的 diff 只有 `cross_file` 的版本與 sha256；版本 ≥ `0.3.5+5`。其他套件有變動就還原，改用只動 `cross_file` 的方式。再跑同一個測試，Expected: PASS。

- [ ] **Step 3: 品質檢查並 commit**

```bash
git add pubspec.lock test/services/accounts_import_test.dart
git commit -m "fix(deps): bump cross_file to 0.3.5+5 to fix garbled text in Android imports"
```

---

### Task 5: 驗收

沒有新程式碼，逐條驗證 spec 第四節與 Review Focus。任何一項失敗就回到負責的 Task 修正。需要使用者操作的步驟，帶著使用者一起做（說明要點哪裡、預期看到什麼），不要自動略過。

- [ ] **Step 1: Android 建置**

Run: `fvm flutter clean`，再 `fvm flutter build apk --debug`，Expected: 成功；安裝到模擬器並啟動，看到總覽頁。

- [ ] **Step 2: Windows 建置**

Run: `fvm flutter build windows`，Expected: 成功。

- [ ] **Step 3: 在 Android 上匯入（Review Focus 2）**

在 Windows 版匯出一份含中文帳號別名的備份 `.json`（沒有的話請使用者提供），`adb -e push <檔案> /sdcard/Download/`，在模擬器的 App 設定頁用匯入功能選它。
Expected: 選擇器裡可以選到 `.json`；匯入後總覽和各卡池頁的筆數正確，別名不是亂碼。如果檔案選不到，記錄下來回報使用者，決定這次修還是留給子專案 4。

- [ ] **Step 4: 在 Android 上按「更新」（Review Focus 1）**

Expected: 出現錯誤提示，或停在等待畫面但按取消能結束；App 沒有崩潰、沒有一直轉圈無法離開。log 裡有對應的 warning 或 severe。記下實際看到的是哪一種，寫進驗收回報。

- [ ] **Step 5: 主題、語言、App 名稱、圖示（Review Focus 3）**

在 App 內切換深淺主題、切換語言，畫面正常。在模擬器的系統設定把語言依序切到繁中、簡中、日文、英文（可自行操作模擬器，不需使用者）：App（語言設定為跟隨系統時）顯示對應語言，繁中時 Material 內建文字也是繁中；桌面上的 App 名稱顯示 Task 1 Step 3 表格裡的值。測完把模擬器語言還原。

- [ ] **Step 6: Windows 不受影響（Review Focus 5）**

`fvm flutter run -d windows`，log 裡有 `rust log stream connected`。請使用者開遊戲的祈願歷史紀錄，確認「更新」照常完成。結束後確認系統代理已關閉（`ProxyEnable` 為 0）、18080 已釋放。

- [ ] **Step 7: 品質檢查**

`fvm dart format lib/ test/`、`fvm flutter analyze`、`fvm flutter test` 全部通過。有修正就 commit。
