# 啟動畫面配合主題與系統應用程式語言同步（子專案 9b）— 簡短設計

- 狀態：已核准（2026-11-22）
- 上層文件：`2026-11-17-android-support-roadmap-design.md`（2026-11-22 調整順序：… → 10 → 9b → 11 → 7 → 13）
- 來源：子專案 9 拆出的範圍（`2026-11-20-mobile-ui-ux-adjustments-design.md` 第一節），鳴潮移植筆記第 47、48 節；鳴潮 commit `c8307a3`、`a0c9180`、`d5383ea`，以鳴潮 `master` 的最終版本為底（`AppThemeChannel` 已在 `d5383ea` 併入 `AppPrefsChannel`）。

## 做法

1. **啟動畫面**：`flutter_native_splash`（只放 dev_dependencies）讀 `flutter_native_splash.yaml` 產生 Android 資源，只開 Android。背景色淺色 #FAFBFD、深色 #0C1220（原神 `surfaceBackground` 與鳴潮相同）。Android 12 以上中央沿用啟動器圖示；Android 11 以下用 `tool/generate_app_icons.dart` 裁出的 `assets/splash/icon.png`。底部品牌圖由 `tool/generate_splash_branding.py` 畫，文字兩行「Genshin Impact」「Wish Gacha Analyzer」（照鳴潮用 App 名稱，不用暫定商店名稱），顏色對應 `textSecondary`／`textMuted`。
2. **啟動畫面跟 App 內深淺色**：Android 12 以上用 `UiModeManager.setApplicationNightMode` 告訴系統；設定載入完才送，「跟隨系統」送 `MODE_NIGHT_AUTO`。
3. **系統應用程式語言**（Android 13 以上）：`<application android:localeConfig="@xml/locales_config">`，`locales_config.xml` 只列 `releasedLocalesProvider` 開放的語言，`test/l10n/android_locales_config_test.dart` 比對；雙向同步（App → `LocaleManager`、系統 → `didChangeLocales` 讀回），繁中送 `zh-Hant`，只寫一次的 `pref.localeSyncedToSystem` 旗標區分舊使用者升級與使用者在系統改回預設。
4. Kotlin `AppPrefsChannel`、Dart `AppPrefsPlatform`、`AndroidAppPrefsSync`（`MainApp` 在 Android 上啟動）。Windows 不受影響。

不在範圍：挪威文 `0069630`（子專案 11）。

## 驗證

`fvm dart format lib/ test/`、`fvm flutter analyze`、`fvm flutter test`；模擬器：手機深色＋App 淺色錄冷啟動確認不閃、`cmd locale get-app-locales` 檢查雙向同步；Windows 跑一次確認不變。

## 附錄：驗收結果

2026-11-22，commit `a968657`、`c1f585d`。

- **自動化**：`fvm flutter analyze` 無問題；`fvm flutter test` 全數通過（+2144）。
- **模擬器（wuwa_api37，Android 17，debug 版）**：
  - App 內把語言改成日本語：`cmd locale get-app-locales` 變成 `[ja]`，log 出現 `app locale pushed tag=ja applied=true`。
  - 系統端設成 `zh-Hant-TW`：開著的設定頁即時換成繁中，語言選單顯示「繁體中文」。
  - 系統端清空：App 回到「跟隨系統」，log 出現 `pref=SystemLanguage`。
  - 系統深色、App 選淺色，冷啟動錄影逐格看亮度：桌面（深）→淺色啟動畫面（含品牌文字）→淺色 App，中間沒有閃深色。
  - 系統淺色、App 選深色：桌面→深色啟動畫面→深色 App，中間沒有閃亮。
  - 測完還原：系統淺色、App 外觀跟隨系統、App 語言未設定；log 沒有 WARNING 或 SEVERE。
- **Windows（debug 版）**：啟動正常，log 沒有 `app.prefs` 相關訊息，也沒有警告；雲端同步判定已一致，沒有上傳。
