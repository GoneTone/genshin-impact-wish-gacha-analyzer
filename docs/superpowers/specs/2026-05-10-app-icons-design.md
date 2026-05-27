# App icon 與 AppBar logo 設計

- 日期：2026-05-10
- 範圍：
  - 新增 `assets/icons/app_icon.png`
  - 覆寫 `windows/runner/resources/app_icon.ico`
  - 修改 `pubspec.yaml`（註冊 assets）
  - 修改 `lib/pages/app_shell.dart`（AppBar.title）
- 不影響：`PageHeader`、`NavigationRail`、AppBar `actions`、各 page widget

## 目標

把舊版 (master 分支) 已具備的兩種 icon 帶回 flutter-rewrite：

1. **AppBar logo**：在 AppBar 標題「App 名稱 v0.x.x」前加上 app icon，重現舊版 sidebar brand「icon + 名稱 + 版本」的品牌一體感。
2. **應用程式 (Windows exe) icon**：把 Flutter 預設 `app_icon.ico` 替換為原專案的正式 app icon，讓工作列 / Alt+Tab / 視窗標題列 / .exe 檔案總管縮圖都顯示正確圖示。

## 非目標

- 不動 `PageHeader`（標題只放純文字，不加 leading icon）。
- 不動 `NavigationRail` 的 destination icon（已是 Material Icons，與舊版 FontAwesome 風格不同但語意已涵蓋）。
- 不在 AppBar `actions` 加社群連結 icon（舊版 NavLayout 的 FB / Discord / Line / GitHub 區塊本次不還原）。
- 不補齊舊版 sidebar 的「官網 / 社群 / 贊助 / 翻譯 / Issue 回報 / contribution_list」項目。
- 不處理 macOS / Linux / Android / iOS 平台 icon — flutter-rewrite 目前**不存在**這些平台目錄；日後加平台時再個別處理。
- 不引入新的 icon 套件（不用 `font_awesome_flutter`）。
- 不抽出獨立的 `AppLogo` widget — 僅一處使用，YAGNI。

## 異動檔案總覽

| 檔案 | 動作 | 來源 / 說明 |
|---|---|---|
| `assets/icons/app_icon.png` | 新增 | 取自 `master:build/icons/256x256.png`（256×256 PNG，給 Flutter UI 用） |
| `windows/runner/resources/app_icon.ico` | 覆寫 | 取自 `master:build/icons/icon.ico`（多解析度 .ico，給 Windows exe 用） |
| `pubspec.yaml` | 修改 | 在 `flutter:` 區塊新增 `assets:` 子段，註冊 `assets/icons/` |
| `lib/pages/app_shell.dart` | 修改 | AppBar 的 `title` 從 `Text(...)` 改為 `Row([Image.asset, SizedBox, Text])` |

## 設計

### 1. Asset 結構

```
assets/
  icons/
    app_icon.png       ← 256×256，來源 master:build/icons/256x256.png
```

僅放單一 1× 解析度。AppBar 內顯示 28×28 dp，256px 來源足以涵蓋 high-DPI 顯示縮放，不需額外提供 `2.0x/` `3.0x/` 變體。日後若視覺出現鋸齒再補。

`pubspec.yaml` 加入：

```yaml
flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/icons/
```

註冊整個資料夾而非單一檔，避免之後加圖時忘記同步註冊。

### 2. AppBar.title 結構

`lib/pages/app_shell.dart` 第 60–76 行的 `AppBar` 區塊：

```dart
appBar: AppBar(
  title: Row(
    mainAxisSize: MainAxisSize.min,           // 不撐到滿版，留空間給 actions
    children: [
      Image.asset(
        'assets/icons/app_icon.png',
        width: 28,
        height: 28,
        filterQuality: FilterQuality.medium,
      ),
      const SizedBox(width: AppSpacing.s),
      Text('${l.appName} v$version'),
    ],
  ),
  actions: [
    const UidIndicator(),
    Padding(...),                              // 「更新」按鈕，不變
  ],
),
```

**關鍵決定：**

- **大小 28×28 dp**：AppBar 預設高度 56 dp，logo 上下各留 14 dp padding，視覺舒適不擁擠。
- **`mainAxisSize: MainAxisSize.min`**：避免 Row 撐到滿版而把右側 `actions` 推出畫面。
- **`filterQuality: FilterQuality.medium`**：256px → 28dp 縮圖時減少鋸齒。
- **不可點擊**：與舊版 sidebar brand 行為一致（純裝飾）。
- **不抽 widget**：只有一處使用，inline 寫死即可；日後若要重複使用再抽 `AppLogo`。

### 3. Windows exe icon 替換

- `windows/runner/Runner.rc` 第 53 行已宣告 `IDI_APP_ICON ICON "resources\\app_icon.ico"`，**檔名與路徑不能改**，只能覆寫檔案內容。
- 直接以 `master:build/icons/icon.ico` 內容覆寫 `windows/runner/resources/app_icon.ico` 即可，不動 .rc / CMakeLists / win32_window.cpp。
- 舊有 Flutter 預設 `app_icon.ico` 是範例 icon，無資料價值，覆寫無風險。
- 替換後需重新 `flutter build windows`（或 `flutter run -d windows`）才會把新 icon 編進 .exe；hot reload 不會生效。

## 測試

**自動化：**

- 既有 widget tests (`test/widgets/page_header_test.dart`、`test/widgets/data/pager_test.dart`) 都不涵蓋 `AppShell` 的 AppBar，**無迴歸風險**。
- 不新增單元測試 — 純視覺裝飾，無邏輯分支。

**手動驗證 (Windows)：**

- `flutter run -d windows` 後檢查：
  - AppBar 左側顯示 logo + 「App 名稱 v0.x.x」並排，logo 與文字緊鄰。
  - 切換 dark / light theme，logo 在兩主題下都可辨識（PNG 為彩色，背景對比足）。
  - 切換中文 / 英文 locale，標題長度變化下不破版（極窄視窗會 ellipsis，是既有行為）。
- 重新 `flutter build windows` 後：
  - 工作列圖示
  - Alt+Tab 縮圖
  - 視窗標題列左上角圖示
  - 檔案總管中 `genshin_impact_wish_gacha_analyzer.exe` 圖示

  以上四處應全部顯示新 icon。

## 風險與已接受的取捨

- **AppBar title 在極窄視窗 (< 600 dp) overflow**：既有行為（`Text('${l.appName} v$version')` 本來就會 ellipsis），新增 logo 不會擴大此問題；本次不處理。
- **Image.asset 找不到檔會拋例外**：build-time asset 不會發生；不加 fallback。
- **未來新增 macOS / Linux 平台時還要再放一次 icon**：本次範圍只 Windows；日後加平台時各自處理對應 icon 流程。
