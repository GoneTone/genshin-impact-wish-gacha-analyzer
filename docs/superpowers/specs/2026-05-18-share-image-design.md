# 分享圖生成功能 — 設計文件

日期：2026-05-18
分支：flutter-rewrite

## 目標

在「綜合頁」與「各卡池頁」新增「生成分享圖」功能，把該頁的祈願數據彙整成一張可公開分享的 PNG，輸出方式為「存檔 + 複製到剪貼簿」。

## 需求定案

| 項目 | 決定 |
|---|---|
| 入口 | `OverviewPage` 與 `BannerPage` 的 `PageHeader` 各加一個動作鈕，無資料時禁用 |
| 綜合頁涵蓋 | 合併單張長圖：祈願段 + 頌願段（版面 B 兩欄，總高度可控） |
| 輸出 | 存檔（`getSaveLocation` + 寫檔 + reveal）**且** 複製到剪貼簿 |
| 生成前 dialog | `AppDialog`：主題（深/淺）segmented + 「顯示完整 UID」`Switch` |
| 數字摘要 | 祈願段：總抽數、5★/4★ 件數 + 佔比 + 平均幾抽出；頌願段：沿用既有 odes 組成（總抽數、事件 5★、常駐 4★）；皆含資料更新時間 |
| 圖表 | 稀有度分布圓餅、類型分布圓餅、垂直時間軸最新 10 筆 |
| Header | 左：app icon + `l.appName` + `v版本`；次標題 GitHub 網址。右：UID + 資料更新時間 |
| 版面 | B 寬幅兩欄：左欄數字摘要 + 雙圓餅，右欄垂直時間軸 |
| 主題 | 生成前 dialog 由使用者選深/淺；語言跟隨 App |
| UID | 開關預設關 = 遮罩（顯示前 3 碼，其餘以 `x` 遮罩、長度保留）；開 = 完整 UID。UID 始終在圖上 |
| 檔名 | `genshin_gacha_share_<page>_<時間>.png`，`<page>` = `overview` 或卡池 slug |
| 實作 | 方案 A：專用 `ShareCard` widget 樹，離屏固定寬度渲染 |
| 剪貼簿 | 引入 `super_clipboard` 套件（Windows/macOS 支援圖片剪貼簿）|

## 架構

```
PageHeader 分享鈕
  → showDialog(ShareImageDialog) → ShareImageOptions? (取消則 null)
  → buildShareCard(options, data...)            // 固定寬 1200px widget 樹
  → renderWidgetToPng(card, size, pixelRatio)   // 離屏 RepaintBoundary.toImage
  → 複製到剪貼簿 (super_clipboard)
  → getSaveLocation(.png) → File.writeAsBytes   // 取消仍保留剪貼簿
  → SnackBar + revealInFileManager
```

## 元件

### 1. `lib/models/share_image_options.dart`
```dart
class ShareImageOptions {
  final Brightness brightness;
  final bool showFullUid;
}
```

### 2. `lib/widgets/dialogs/share_image_dialog.dart`
`AppDialog`（`size: AppDialogSize.sm`）。內容：主題 segmented（深/淺，預設跟隨當前 App brightness）、「在圖上顯示完整 UID」`SwitchListTile`（預設 false）。按鈕：取消 / 生成。回傳 `ShareImageOptions?`。

### 3. `lib/widgets/share/share_card.dart`
固定寬 `1200`、`crossAxisAlignment.stretch` 的 widget 樹，外層包：
- `Theme(data: options.brightness == dark ? buildDarkTheme() : buildLightTheme())` — 重用 `lib/theme/app_theme.dart`
- 沿用當前 `Localizations`（App 語言）

子元件（同檔 private widget）：
- `_ShareHeader`：左 `Image.asset('assets/icons/app_icon.png')` + `l.appName` + `'v$appVersion'`；次標題 `AppRepo.githubUrl`。右：UID 文字 + 資料更新時間（`intl` 格式化）。
- `_ShareSection({title, statsColumn, rarityPie, itemTypePie, timeline})`：標題列 + `Row`（左欄 flex 大：摘要 `StatCard` 風格 + 兩圓餅；右欄：`_ShareTimeline`）。卡池頁 1 段；綜合頁 2 段（祈願 + 頌願，中間 `Divider`）。
- `_ShareTimeline`：靜態精簡垂直時間軸，重用 `timeline_entries` 服務 + `BannerColors`，取最新 10 筆，無 `TimelineVertical` 的分頁/互動 chrome。

圓餅重用 `RarityPie` / `ItemTypePie` / `DistributionLegend`，渲染時關閉 fl_chart 動畫（`PieChartData` 不啟用動畫 / `duration: Duration.zero`）以利截圖穩定。

### 4. `lib/services/share_image_renderer.dart`
```dart
Future<Uint8List> renderWidgetToPng(BuildContext ctx, Widget card,
    {required Size logicalSize, double pixelRatio = 3.0});
```
作法：以 `OverlayEntry` 將 `Offstage` + `RepaintBoundary`(GlobalKey) 掛入 app `Overlay`；`await WidgetsBinding.instance.endOfFrame`（必要時連等兩幀，確保 fl_chart 繪完）；`boundary.toImage(pixelRatio)` → `toByteData(png)` → 移除 entry。`Logger('share.image')` 記錄 size/pixelRatio/bytes 長度與錯誤。

### 5. `lib/services/share_image_export.dart`
```dart
Future<ShareExportResult> exportShareImage(Uint8List png, {required String suggestedName});
```
- 先 `super_clipboard` 寫圖片剪貼簿（失敗 → `Logger.warning`，續行）。
- `getSaveLocation(suggestedName, PNG XTypeGroup)`；null（取消）→ result = clipboardOnly。
- `File(loc.path).writeAsBytes(png)` → result = saved，呼叫端 `revealInFileManager`。
- 仿 `lib/services/file_reveal.dart` 的 `@visibleForTesting` seam：注入 `getSaveLocation` / 寫檔 / 剪貼簿，使 `flutter test` 不碰真實 FS / 剪貼簿。
- `Logger('share.image')` 埋 log：脫敏路徑、bytes 長度、clipboard 成功與否、retcode 類分支。

### 6. 共用 helper：`lib/services/overview_sections.dart`（重構抽出）
綜合頁「祈願/頌願分組 + 各區 stats / 平均間隔 / timeline entries」目前內嵌於 `overview_page.dart`。抽成純函式回傳區段 view-model，`OverviewPage` 與 `ShareCard` 共用，避免複製貼上（遵守 CLAUDE.md「嚴禁重複造輪子」）。

### 7. UID 遮罩
公開分享需求比 `sanitizeUid`（前3+後3）更嚴，**刻意不重用**：新增 share 專用遮罩 = 顯示前 3 碼，其餘逐字以 `x` 取代（長度保留）；長度 < 3 全遮。放在 `share_card.dart` 內 private helper 或 `share_image_options.dart`。理由註解寫清楚，非重造輪子。

## 資料流

頁面已 `ref.watch(gachaRepositoryProvider)` 取 `activeData`。傳入 `ShareCard`：
- 綜合頁：用 `overview_sections.dart` helper 產祈願 + 頌願兩段。**頌願段沿用 `overview_page` 既有 odes 統計組成**（總抽數、事件 5★ 件數、常駐 4★ 件數），不硬套「佔比 + 平均幾抽出」（odes 無對應保底語意）；祈願段才是總抽數 + 5★/4★ 件數 + 佔比 + 平均幾抽出。
- 卡池頁：`computeGachaStats(records)`、`averageIntervalAcrossBanners`/平均間隔、`buildTimelineEntries(records, targetRank)`。
- `appVersion` ← `appVersionProvider`；UID ← `activeData.uid`（依開關遮罩或完整）；更新時間 ← `lastUpdated`。

## 錯誤處理

| 情境 | 行為 |
|---|---|
| 無 `activeData` / 無紀錄 | 分享鈕 disabled |
| `toImage` 例外 | catch、`Logger.severe`、錯誤 SnackBar，不崩潰 |
| 存檔視窗取消 | 保留剪貼簿，SnackBar「已複製到剪貼簿」 |
| 剪貼簿失敗（平台不支援）| `Logger.warning`，續行存檔，SnackBar 只提檔案 |
| UID | 一律先過 share 專用遮罩；完整僅在開關開啟 |

## 測試（須過 `flutter analyze` 與 `flutter test`）

- Widget：`ShareCard` 固定寬下不 overflow — (a) 卡池頁有紀錄 (b) 綜合頁祈願+頌願 (c) 單筆邊界。
- Renderer：pump `ShareCard` 後 `renderWidgetToPng` 回非空、可解碼且尺寸正確的 PNG。
- Export service：注入 seam 驗證 saved / clipboardOnly / 取消三分支，不碰真實 FS/剪貼簿。
- UID 遮罩：前 3 碼可見、其餘為 `x`、長度保留；< 3 全遮。
- `ShareImageDialog`：回傳 options（含預設值）與取消回 null。

## 範圍外（YAGNI）

- 不做手機系統分享面板（桌面 App 無此 API）。
- 不做自訂版面/主題色板/浮水印開關以外的客製。
- 不做卡池頁的「保底進度」入圖（摘要不含距上次 X 抽）。

## 注意

本文件位於 `docs/superpowers/`，依使用者規範**不進版控、不 commit**。
