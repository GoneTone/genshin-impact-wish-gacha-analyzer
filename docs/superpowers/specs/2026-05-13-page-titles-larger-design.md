# 設計:放大所有頁面標題

- **日期**: 2026-05-13
- **分支**: flutter-rewrite
- **目標**: 把 `PageHeader` 顯示的頁面標題字級由 18 px 放大到 22 px,同時不影響卡片標題。

## 背景

目前所有頁面 (`Overview` / `Banner` / `Settings` / `Contributors`) 開頭都用 `lib/widgets/page_header.dart` 的 `PageHeader` widget 顯示標題,而 `PageHeader` 套用 `theme.textTheme.titleLarge`,其字級在 `lib/theme/app_theme.dart:47` 設為 `AppFontSize.title = 18` (`lib/theme/tokens.dart:23`)。

問題在於同一個 `titleLarge` (亦即 `AppFontSize.title`) 同時被多個卡片標題使用:

- `lib/widgets/cards/section_card.dart:27`
- `lib/widgets/cards/chart_card.dart:41`
- `lib/widgets/empty_state.dart:54`
- `lib/pages/banner_page.dart:217`
- `lib/pages/overview_page.dart:202`

因此單純把 `AppFontSize.title` 改大,會連帶把所有卡片標題一起放大,而我們只想放大「頁面開頭的標題」。

## 設計

走 Material 3 textTheme 的語意分層:**page header → `headlineSmall`,card title → `titleLarge`**,把兩者拆開。

### 變更

1. **`lib/theme/tokens.dart`**
   - 新增 `static const double pageTitle = 22;` 到 `AppFontSize`。
   - 修改 `AppFontSize.title` 的註解,由 `頁標 / 卡標` 改為 `卡標`,還原語意。

2. **`lib/theme/app_theme.dart`**
   - 在 `textTheme.copyWith(...)` 內新增 `headlineSmall`,風格對齊現有 `titleLarge`,僅字級不同:
     ```dart
     headlineSmall: base.textTheme.headlineSmall?.copyWith(
       fontSize: AppFontSize.pageTitle,
       fontWeight: FontWeight.w700,
       color: tokens.textPrimary,
     ),
     ```
   - `titleLarge` 不動,卡片標題不受影響。

3. **`lib/widgets/page_header.dart`**
   - `Text(title, style: theme.textTheme.titleLarge)` → `Text(title, style: theme.textTheme.headlineSmall)`。
   - `subtitle` 仍用 `bodyMedium` (14 px),維持不動。14 / 22 的比例比 14 / 18 更分明,合理。

### 測試

- `test/widgets/page_header_test.dart` 現有兩個測試只 assert 文字渲染,不需更動 (它們不檢查字級)。
- 新增一個 regression test,確保 `PageHeader` 渲染的 title `Text` 的 effective `fontSize` 為 22 px,避免未來有人不小心把它接回 `titleLarge` 卻無人察覺。實作上可透過 `tester.widget<Text>(find.text(...)).style?.fontSize` 取值斷言。

### 影響面

| 區域 | 變化 |
|---|---|
| 4 個頁面開頭標題 (Overview / Banner / Settings / Contributors) | 18 → 22 |
| `SectionCard` / `ChartCard` / `EmptyState` 標題 | 不變 (18) |
| `banner_page` / `overview_page` 內部小節標題 | 不變 (18) |
| 卡標數值字級 (`AppFontSize.display = 32`) | 不變 |
| 主體文字 / labelSmall | 不變 |

## 為什麼選這個 Approach

當時討論的 3 個方向:

1. **(採用) `headlineSmall` 給頁標 / `titleLarge` 給卡標** — M3 語意分層 (headline > title),3 個檔改動,卡標完全不動。
2. 在 `PageHeader` 內 `copyWith(fontSize: pageTitle)` — 改動最少 (2 檔),但字級不在 textTheme 體系內,日後想複用「頁標等級」要重抄。
3. `titleLarge` 拉大到 22、卡標改用 `titleMedium = 18` — 要動 5 處用 `titleLarge` 的卡標,且 M3 語意上 PageHeader 用 headline 才正確,選項 3 屬於「反 M3」方向。

選 1 是因為:對齊 M3 語意、改動小、卡標零影響、未來頁標再調只動 token。

## 驗收標準

- [ ] 4 個頁面開頭標題視覺上明顯比卡片標題大。
- [ ] 所有卡片標題、`EmptyState` 標題、`banner_page` / `overview_page` 內部小節標題與調整前一致 (字級 18)。
- [ ] `dart format lib/ test/` 通過。
- [ ] `flutter analyze` 輸出 `No issues found!`。
- [ ] `flutter test` 輸出 `All tests passed!`,且包含新增的 PageHeader fontSize regression test。

## 不在範圍

- 不調整 subtitle 字級。
- 不調整字重、行高、letterSpacing。
- 不調整卡標、`EmptyState`、`SectionCard`、`ChartCard` 任何字級。
- 不調整深淺色主題以外的 token。
