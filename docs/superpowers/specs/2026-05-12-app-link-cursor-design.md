# AppLink 與連結滑鼠指標統一規範

## 背景

桌面端使用者觀察到：貢獻名單頁面（專案負責人、測試人員、翻譯審稿人）的姓名雖然是連結，但滑鼠移上去時不會切換成 click cursor，導致「這是連結嗎？」的視覺判讀困難。

調查後發現兩個成因：

1. **`lib/widgets/translator_text.dart`**：使用 `Text.rich` + `TextSpan` + `TapGestureRecognizer` 渲染連結。`TextSpan` 沒有設定 `mouseCursor`，因此 GitHub 貢獻者連結、Crowdin 連結、License 連結、語言翻譯者連結 hover 時**都不會**切換 cursor。
2. **`lib/pages/contributors_page.dart`** 的 `_ContributorChips`：使用 `InkWell + Text`。`InkWell` 預設帶有 `WidgetStateMouseCursor.clickable`，但其所在的 `SectionCard` 父層是純 `Container`、不是 `Material`，cursor 切換在此 layout 下未生效。

更廣的觀察是：專案內部「外部 URL 連結」沒有統一元件，`launchUrl` 邏輯在 `_ContributorChips._open` 與 `TranslatorText._open` 各自實作一次，違反 `CLAUDE.md` 的「嚴禁重複造輪子」。

## 目標

1. 連結 hover 時穩定切換為 click cursor，跨平台行為一致。
2. 統一外部 URL 連結的 UI（樣式、cursor、hover 視覺變化）。
3. 消除 `launchUrl` 重複實作。
4. 不引入新依賴，符合 YAGNI（不做未要求的 active/pressed/focus 樣式、不做動畫過渡、不抽 InlineSpan 版本）。

## 設計

### 新增 `lib/widgets/app_link.dart`

兩個對外單元：

#### `AppLink` widget

```dart
class AppLink extends StatefulWidget {
  const AppLink({super.key, required this.url, required this.child});
  final String url;
  final Widget child;
}
```

行為：

- 外層 `MouseRegion(cursor: SystemMouseCursors.click, onEnter, onExit)` 切換 cursor 與更新 `_hovering` flag。
- 內層 `GestureDetector(onTap: ..., behavior: HitTestBehavior.opaque)` 觸發 `openExternalUrl(Uri.parse(url))`。
- 透過 `DefaultTextStyle.merge` 把連結樣式套到 `child`（通常是 `Text`），使用端不需要手寫 `TextStyle`。

樣式規則（在 build 時計算）：

| 狀態 | color | decoration |
|---|---|---|
| 預設 | `theme.colorScheme.primary` | `TextDecoration.underline` |
| Hover | `Color.lerp(primary, theme.colorScheme.onSurface, 0.15)` | `TextDecoration.underline` |

Hover 用 `Color.lerp` 而不寫死色票，讓 dark/light theme 都自動適用。不加動畫過渡。

選用 `MouseRegion + GestureDetector` 而非 `InkWell`：`InkWell` 需要 `Material` 父層才能正確渲染 ripple，且現有 `SectionCard` 是 `Container` 父層；`MouseRegion + GestureDetector` 與 Material widget 樹無耦合，更穩定。

#### `openExternalUrl` top-level function

```dart
Future<void> openExternalUrl(Uri uri) async {
  if (!await canLaunchUrl(uri)) {
    debugPrint('openExternalUrl: cannot launch $uri');
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

`AppLink` 與 `TranslatorText` 內部都呼叫此 helper。`debugPrint` 與 `LaunchMode.externalApplication` 行為延續既有兩處實作。

### 修改 `lib/widgets/translator_text.dart`

- `LinkSegment` 對應的 `TextSpan` 加上 `mouseCursor: SystemMouseCursors.click`。這是 cursor 不切換的直接原因，補一行即解。
- `_open(Uri)` 改為直接呼叫 `openExternalUrl(uri)`，並移除重複的 `canLaunchUrl + launchUrl` 邏輯。
- 不切 `WidgetSpan(AppLink)`：保留 `TextSpan` + recognizer 架構以維持 inline 文字流的高度對齊。

### 修改 `lib/pages/contributors_page.dart`

- `_ContributorChips` 內 `InkWell + Text(c.name, style: ...)` 改為 `AppLink(url: c.url!, child: Text(c.name))`。
- 移除 `_open` 私有方法（已由 `AppLink` 內部處理）。
- 移除 `url_launcher` import（檔案不再直接使用）。

### 不做的範圍（YAGNI）

- 不調整 `app_shell.dart` 的側欄 `InkWell`、`sortable_table.dart` 的排序欄位 `InkWell`。它們是 App 內互動而非外部 URL 連結，且本來就在 Material widget 樹下、cursor 預設可運作。
- 不做 active、pressed、focus 樣式。
- 不做 hover 動畫過渡（cursor 切換本身就是即時反饋訊號）。
- 不在 `AppLink` 加 link icon、tooltip 等延伸特性。
- 不抽出 InlineSpan 版本的 `AppLinkSpan`。`TranslatorText` 直接補 `mouseCursor` 就解決。

## 測試計畫

### 新增 `test/widgets/app_link_test.dart`

- **渲染**：`AppLink(url: 'https://example.test', child: Text('hi'))` 渲染後，`Text` 取得 `DefaultTextStyle` 的 color 等於 `theme.colorScheme.primary`、`decoration` 等於 `TextDecoration.underline`。
- **Hover cursor**：透過 `tester.createGesture(kind: PointerDeviceKind.mouse)` 模擬 hover 後，包覆 child 的 `MouseRegion.cursor == SystemMouseCursors.click`。
- **Hover 變色**：hover 後 child 文字的 color 與未 hover 時不同（不寫死 RGB，比較不相等即可）。
- **Tap 不 throw**：點擊一次不應拋例外。不 mock `url_launcher`（第三方套件職責，跨平台 mock 成本高且邊際價值低）。

### 修改 `test/widgets/translator_text_test.dart`

既有 `TranslatorText widget` 群組（line 78 起）的「含連結」測試補一筆：

```dart
expect(linkSpan.mouseCursor, SystemMouseCursors.click);
```

### 修改 `test/pages/contributors_page_test.dart`

`find.byType(InkWell)` 改為 `find.byType(AppLink)`：

- Line 42–45：`'GoneTone'` 的 ancestor matcher
- Line 62–69：`'pan93412'`、`'Lemon7777'` 的 ancestor matcher

## 受影響檔案

| 檔案 | 動作 |
|---|---|
| `lib/widgets/app_link.dart` | 新增 |
| `lib/widgets/translator_text.dart` | 修改 |
| `lib/pages/contributors_page.dart` | 修改 |
| `test/widgets/app_link_test.dart` | 新增 |
| `test/widgets/translator_text_test.dart` | 修改 |
| `test/pages/contributors_page_test.dart` | 修改 |

## 提交前檢查

依 `CLAUDE.md` 規則，提交前依序通過：

1. `dart format lib/ test/`
2. `flutter analyze`（必須 `No issues found!`）
3. `flutter test`（必須 `All tests passed!`）
