# 放大頁面標題 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `PageHeader` 顯示的頁面標題字級從 18 px 放大到 22 px,卡片標題與其餘 UI 完全不變。

**Architecture:** 走 Material 3 textTheme 的語意分層 — 在 theme 新增 `headlineSmall` slot 給頁標,沿用既有 `titleLarge` 給卡標。token 新增 `AppFontSize.pageTitle = 22`,`PageHeader` 從 `titleLarge` 改成 `headlineSmall`。

**Tech Stack:** Flutter / Dart,Material 3 textTheme,`flutter_test` widget test。

**Spec:** `docs/superpowers/specs/2026-05-13-page-titles-larger-design.md`

---

## File Structure

- **Modify** `lib/theme/tokens.dart` — 新增 `AppFontSize.pageTitle = 22`;`AppFontSize.title` 註解 `頁標 / 卡標` → `卡標`
- **Modify** `lib/theme/app_theme.dart` — `textTheme.copyWith(...)` 新增 `headlineSmall` slot
- **Modify** `lib/widgets/page_header.dart` — `titleLarge` → `headlineSmall`
- **Modify** `test/widgets/page_header_test.dart` — 新增 regression test 斷言 PageHeader 的 title `fontSize == 22`

---

## Task 1: 放大 PageHeader 字級到 22 (TDD 一次循環)

**Files:**
- Modify: `test/widgets/page_header_test.dart`
- Modify: `lib/theme/tokens.dart`
- Modify: `lib/theme/app_theme.dart`
- Modify: `lib/widgets/page_header.dart`

### TDD 紅燈

- [ ] **Step 1: 在 `test/widgets/page_header_test.dart` 新增 fontSize regression test**

在檔案結尾的 `}` 之前 (與既有兩個 `testWidgets` 同一個 `main()` 內) 插入下列測試:

```dart
testWidgets('title renders at pageTitle font size (22 px)', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(body: PageHeader(title: 'Overview')),
    ),
  );

  final titleText = tester.widget<Text>(find.text('Overview'));
  expect(titleText.style?.fontSize, 22);
});
```

> 用 `style?.fontSize` 直接拿 widget 樹上實際套用的字級。M3 textTheme 解析後 `headlineSmall.fontSize` 會出現在 `Text.style`。

- [ ] **Step 2: 跑這個測試,確認失敗 (紅燈)**

Run: `flutter test test/widgets/page_header_test.dart --plain-name "title renders at pageTitle font size"`
Expected: FAIL,訊息類似 `Expected: <22> Actual: <18>` (因為現在仍套用 `titleLarge = 18`)。

### TDD 綠燈

- [ ] **Step 3: 在 `lib/theme/tokens.dart` 新增 `pageTitle` token 並更新註解**

把現有 `AppFontSize` 區塊改成:

```dart
/// 字級語意（搭配 ThemeData.textTheme 對應 M3 名稱）。
abstract class AppFontSize {
  static const double display = 32; // 保底大數字
  static const double pageTitle = 22; // 頁標
  static const double title = 18; // 卡標
  static const double body = 14;
  static const double label = 11; // uppercase 小寫上標
}
```

> 變更兩處: 新增 `pageTitle = 22`、把 `title` 註解 `頁標 / 卡標` 改為 `卡標`。

- [ ] **Step 4: 在 `lib/theme/app_theme.dart` `textTheme.copyWith(...)` 加入 `headlineSmall`**

把 `textTheme: base.textTheme.copyWith(...)` 區塊改成:

```dart
textTheme: base.textTheme.copyWith(
  headlineSmall: base.textTheme.headlineSmall?.copyWith(
    fontSize: AppFontSize.pageTitle,
    fontWeight: FontWeight.w700,
    color: tokens.textPrimary,
  ),
  titleLarge: base.textTheme.titleLarge?.copyWith(
    fontSize: AppFontSize.title,
    fontWeight: FontWeight.w700,
    color: tokens.textPrimary,
  ),
  bodyMedium: base.textTheme.bodyMedium?.copyWith(
    fontSize: AppFontSize.body,
    color: tokens.textSecondary,
  ),
  labelSmall: base.textTheme.labelSmall?.copyWith(
    fontSize: AppFontSize.label,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: tokens.textMuted,
  ),
),
```

> 只在最前面新增 `headlineSmall` 區塊。`titleLarge` / `bodyMedium` / `labelSmall` 保持原樣。

- [ ] **Step 5: 在 `lib/widgets/page_header.dart` 把 `titleLarge` 換成 `headlineSmall`**

把 line 22 從:

```dart
Text(title, style: theme.textTheme.titleLarge),
```

改成:

```dart
Text(title, style: theme.textTheme.headlineSmall),
```

> 其餘 (`subtitle` 用 `bodyMedium`、padding、layout) 完全不動。

- [ ] **Step 6: 跑新增的 regression test,確認通過 (綠燈)**

Run: `flutter test test/widgets/page_header_test.dart --plain-name "title renders at pageTitle font size"`
Expected: PASS。

### 全套品質檢查

- [ ] **Step 7: 跑整個 `page_header_test.dart`,確認原有兩個測試仍綠**

Run: `flutter test test/widgets/page_header_test.dart`
Expected: 3 個測試全部 PASS (`renders title only` / `renders subtitle when provided` / `title renders at pageTitle font size (22 px)`)。

- [ ] **Step 8: 跑 `dart format`**

Run: `dart format lib/ test/`
Expected: 顯示被改動的 4 個檔案 (`lib/theme/tokens.dart`、`lib/theme/app_theme.dart`、`lib/widgets/page_header.dart`、`test/widgets/page_header_test.dart`) 已格式化,其餘 `Unchanged`。

> 注意: **不要** 對 `.` 跑,會動到 `rust_builder/` 內 vendored 程式碼。

- [ ] **Step 9: 跑 `flutter analyze`**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: 跑整個測試套件**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 11: Commit**

```bash
git add lib/theme/tokens.dart lib/theme/app_theme.dart lib/widgets/page_header.dart test/widgets/page_header_test.dart
git commit -m "feat(page-header): enlarge page title to 22 px via headlineSmall"
```

> 不要 `git add -A` / `git add .`,只加這 4 個檔。`docs/superpowers/` 已在 `.gitignore` 不會被誤加。

---

## 驗收 (對照 spec)

跑完 Task 1 後對照 spec `驗收標準`:

- [x] 4 個頁面開頭標題明顯比卡片標題大 (22 vs 18) — Step 6 的 regression test 已保證。
- [x] 所有卡片標題、`EmptyState` 標題、`banner_page` / `overview_page` 內部小節標題與調整前一致 — 它們仍用 `titleLarge`,Step 4 並未改動 `titleLarge`,Step 7 / Step 10 的測試也未觸發 regression。
- [x] `dart format lib/ test/` 通過 — Step 8。
- [x] `flutter analyze` 輸出 `No issues found!` — Step 9。
- [x] `flutter test` 輸出 `All tests passed!`,且包含新增的 PageHeader fontSize regression test — Step 10。

實際視覺確認 (非自動化):打開 app,翻過 4 個頁面 (`Overview` / `Banner` / `Settings` / `Contributors`),確認頁面開頭標題明顯比卡片標題大。
