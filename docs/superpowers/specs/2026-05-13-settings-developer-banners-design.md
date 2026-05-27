# 設定頁開發者橫幅 Banner 設計

**日期**：2026-05-13
**目標**：在設定頁「關於」區塊的 "Developed by" 文字行下方,新增兩張可點擊的橫幅圖片。

## 背景

目前 `lib/pages/settings_page.dart` 的 `_AboutContent` widget (行 174-208) 顯示版本號與一行文字:

```
Developed by GoneTone (原神資訊站 Genshin Impact Info)
```

其中 `GoneTone` 連到 `https://github.com/GoneTone`、`原神資訊站 Genshin Impact Info` 連到 `https://genshininfo.reh.tw/`。

需求是在這行下方新增兩張橫幅圖片,各自連到不同網址,作為開發者品牌的禮貌性 credit。

## 範圍與決策

| 項目 | 決定 | 備註 |
|---|---|---|
| 圖片來源 | 打包進 `assets/banners/` | 離線可用、不依賴網路 |
| 連結目標 | GoneTone 橫幅 → `https://blog.reh.tw/`;原神資訊站橫幅 → `https://genshininfo.reh.tw/` | 與現有文字行 GitHub 連結互補 |
| 佈局 | 響應式 `Wrap` | 寬視窗並排、窄視窗自動換行堆疊 |
| 兩張圖高度 | **一致(64px)** | 視覺對齊,寬度由原圖比例決定 |
| 既有文字行 | **保留**,橫幅加在下方 | 不犧牲既有 GitHub 連結 |
| 互動 | Hover 顯示 click 游標 + opacity 0.85 + Tooltip | 圖片連結應有明確視覺回饋 |
| 暗色模式 | 不做專屬版本 | YAGNI,實機觀察後再決定 |

## 元件設計

### 新元件:`BannerLink`

位置:`lib/widgets/banner_link.dart`

**為何拆出新元件而不直接寫在 `_AboutContent`**:
- 既有 `AppLink` 是文字連結語意(`DefaultTextStyle.merge` 套底線顏色),不適用於圖片
- 圖片連結的視覺回饋(opacity)、語意(`Semantics(button: true)`)與文字連結不同
- 拆出後可單獨測試、未來其他頁面要用圖片連結時可重用
- 但**底層 URL 開啟邏輯共用** `app_link.dart` 已匯出的 `openExternalUrl()` 函式,避免重複造輪子(對齊 CLAUDE.md 規則)

**介面**:

```dart
class BannerLink extends StatefulWidget {
  const BannerLink({
    super.key,
    required this.assetPath,
    required this.url,
    required this.semanticLabel,
    required this.height,
  });

  final String assetPath;
  final String url;
  final String semanticLabel;
  final double height;
}
```

**行為**:
- `MouseRegion`:游標切換為 `SystemMouseCursors.click`,並追蹤 hover 狀態
- `AnimatedOpacity`(duration 120ms):hover 時 opacity 1.0 → 0.85
- `Tooltip(message: semanticLabel)`:滑鼠停留顯示連結說明
- `Semantics(button: true, label: semanticLabel)`:螢幕閱讀器辨識為按鈕
- `GestureDetector(behavior: HitTestBehavior.opaque, onTap: ...)`:點擊呼叫 `openExternalUrl(Uri.parse(url))`
- `Image.asset(assetPath, height: height, fit: BoxFit.contain)`:固定高度,寬度依原圖比例自動計算

## 資產

新增到 `assets/banners/`:

| 檔名 | 來源 | 比例 |
|---|---|---|
| `gonetone_banner.png` | `G:\_圖片\_個人圖片\_旋風之音 GonTone\橫幅\GoneTone Banner_954x200.png` | 954×200(4.77:1) |
| `genshin_info_banner.png` | `G:\_圖片\原神資訊站 Genshin Impact Info\Logo\banner.png` | 約 3.3:1 |

`pubspec.yaml` 的 `flutter.assets` 加入:

```yaml
flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/icons/
    - assets/banners/
```

## `_AboutContent` 修改

在 `lib/pages/settings_page.dart` 的 `_AboutContent.build` 的最外層 `Column` 末端,接續現有 `Wrap` 之後新增:

```dart
const SizedBox(height: AppSpacing.s),
Wrap(
  spacing: AppSpacing.s,
  runSpacing: AppSpacing.s,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: const [
    BannerLink(
      assetPath: 'assets/banners/gonetone_banner.png',
      url: 'https://blog.reh.tw/',
      semanticLabel: '旋風之音 GoneTone',
      height: 64,
    ),
    BannerLink(
      assetPath: 'assets/banners/genshin_info_banner.png',
      url: 'https://genshininfo.reh.tw/',
      semanticLabel: '原神資訊站 Genshin Impact Info',
      height: 64,
    ),
  ],
),
```

**設計理由**:
- `Wrap` + `AppSpacing.s` 與既有 `_DataManagement`(行 219-)用法一致,不引入新模式
- `crossAxisAlignment: WrapCrossAlignment.center`:同列圖片垂直置中(防呆;當前兩張同高,但容差佳)
- `height: 64`:設定頁「關於」區塊是次要資訊,橫幅當作禮貌性 credit。64px 與相鄰版本號文字視覺重量相近,不喧賓奪主。GoneTone 寬約 305、原神資訊站寬約 213,並排總寬約 526 + spacing,桌面預設視窗可並排;窄視窗時 Wrap 自動換行

## 測試

新增 `test/widgets/banner_link_test.dart`,涵蓋:

1. **渲染**:給定 `assetPath` 與 `height`,渲染後可找到 `Image` 且 `height` 等於指定值
2. **Tooltip / Semantics**:widget tree 中可找到對應 `semanticLabel` 的 `Tooltip` 與 `Semantics(button: true)` 節點
3. **Hover 切換**:用 `WidgetTester.createGesture(kind: PointerDeviceKind.mouse)` 模擬進入/離開,驗證 `AnimatedOpacity.opacity` 為 0.85(hover 中)、離開後變回 1.0
4. **點擊**:`tester.tap` 觸發 `GestureDetector.onTap`,驗證 callback 被呼叫(URL 啟動屬 `url_launcher` 平台行為,不在 widget test 內驗證實際開啟,與既有 `test/widgets/app_link_test.dart` 策略一致)

`_AboutContent` 不另寫新測試:它只是把 `BannerLink` 組裝起來,單元測試在 `BannerLink` 已涵蓋。

## 不做的事(YAGNI)

- 不做暗色模式專屬橫幅版本 — 先實機觀察,若對比不夠再加
- 不引入網路載入或 `cached_network_image` — 圖片已決定打包
- 不抽 `BannerList` 之類的容器元件 — 兩張寫死在 `_AboutContent` 即可,無重用需求
- 不做點擊縮放/水波紋動畫 — `AnimatedOpacity` 已足夠視覺回饋
- 不為 `semanticLabel` 做 i18n — 固定中文人名/站名,翻譯沒有意義

## 檔案清單

| 動作 | 路徑 |
|---|---|
| 新增 | `assets/banners/gonetone_banner.png` |
| 新增 | `assets/banners/genshin_info_banner.png` |
| 修改 | `pubspec.yaml`(`flutter.assets` 加 `- assets/banners/`) |
| 新增 | `lib/widgets/banner_link.dart` |
| 新增 | `test/widgets/banner_link_test.dart` |
| 修改 | `lib/pages/settings_page.dart`(`_AboutContent` 末端加 `Wrap` + 2 個 `BannerLink`) |

## 完成條件

- `dart format lib/ test/` 無變更
- `flutter analyze` 輸出 `No issues found!`
- `flutter test` 輸出 `All tests passed!`
- 實機跑起來,設定頁「關於」區塊可看到兩張橫幅;hover 顯示 click 游標 + opacity 變化 + Tooltip;點擊開啟對應網址
- 寬視窗下兩張並排、窄視窗下自動換行
