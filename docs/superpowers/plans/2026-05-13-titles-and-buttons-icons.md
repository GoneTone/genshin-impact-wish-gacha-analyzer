# 標題與按鈕補 icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓所有頁面標題、Section 標題、圖表卡標題與按鈕都帶上 icon，提升視覺辨識度。

**Architecture:** 在三個共用標題容器（`PageHeader`、`SectionCard`、`ChartCard`）加可選的 `IconData? icon` 參數；抽一個 `InlineSectionTitle` 給頁內內聯標題；按鈕沒 icon 的全部改用 `.icon` 變體。caller 端在每個頁面 / dialog 傳入對應 icon。

**Tech Stack:** Flutter / Material 3 / Riverpod。icon 全部來自 `package:flutter/material.dart` 的 `Icons.*` constants。

**Spec:** `docs/superpowers/specs/2026-05-13-titles-and-buttons-icons-design.md`

---

## 檔案結構

**新增：**
- `lib/widgets/inline_section_title.dart` — 內聯區塊標題小元件（titleLarge + icon）
- `test/widgets/inline_section_title_test.dart` — 對應 widget test

**修改（共用元件加 `icon` 參數）：**
- `lib/widgets/page_header.dart`
- `lib/widgets/cards/section_card.dart`
- `lib/widgets/cards/chart_card.dart`

**修改（caller 端傳 icon）：**
- `lib/pages/overview_page.dart`
- `lib/pages/banner_page.dart`
- `lib/pages/settings_page.dart`
- `lib/pages/contributors_page.dart`

**修改（按鈕改 `.icon` 變體）：**
- `lib/widgets/dialogs/confirm_dialog.dart`
- `lib/widgets/dialogs/accounts_picker_dialog.dart`
- `lib/widgets/update_progress_dialog.dart`
- `lib/widgets/cards/account_management.dart`

**測試修改：**
- `test/widgets/page_header_test.dart` — 加 icon 測試
- `test/widgets/cards/section_card_test.dart` — 加 icon 測試
- `test/widgets/cards/chart_card_test.dart` — 加 icon 測試
- `test/widgets/dialogs/confirm_dialog_test.dart` — 驗證按鈕 icon
- `test/widgets/dialogs/accounts_picker_dialog_test.dart` — 驗證按鈕 icon

---

## Task 1: PageHeader 加 `icon` 參數

**Files:**
- Modify: `lib/widgets/page_header.dart`
- Test: `test/widgets/page_header_test.dart`

- [ ] **Step 1: Write the failing test**

把以下測試加到 `test/widgets/page_header_test.dart` `main()` 函式裡（在現有測試後面，for-loop 之前）：

```dart
testWidgets('renders leading icon when icon is provided', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: PageHeader(title: 'Overview', icon: Icons.dashboard_outlined),
      ),
    ),
  );
  expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
  expect(find.text('Overview'), findsOneWidget);
});

testWidgets('renders no icon when icon is null', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(body: PageHeader(title: 'Overview')),
    ),
  );
  expect(find.byType(Icon), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/page_header_test.dart`
Expected: FAIL — 第一個新測試找不到 `icon` 參數（編譯錯誤）。

- [ ] **Step 3: Modify `lib/widgets/page_header.dart`**

整個檔案改成：

```dart
// lib/widgets/page_header.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final titleText = Text(title, style: theme.textTheme.headlineSmall);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon == null)
            titleText
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: tokens.textPrimary),
                const SizedBox(width: AppSpacing.s),
                Flexible(child: titleText),
              ],
            ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/page_header_test.dart`
Expected: PASS — 全部測試通過（含舊的 title only / subtitle / font size）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/page_header.dart test/widgets/page_header_test.dart
git commit -m "feat(page-header): support optional leading icon"
```

---

## Task 2: SectionCard 加 `icon` 參數

**Files:**
- Modify: `lib/widgets/cards/section_card.dart`
- Test: `test/widgets/cards/section_card_test.dart`

- [ ] **Step 1: Write the failing test**

把以下測試加到 `test/widgets/cards/section_card_test.dart` `main()` 函式內（既有測試後面）：

```dart
testWidgets('renders leading icon when provided', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: SectionCard(
          title: 'Theme',
          icon: Icons.palette_outlined,
          child: Text('inside'),
        ),
      ),
    ),
  );
  expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  expect(find.text('Theme'), findsOneWidget);
});

testWidgets('renders no icon when icon is null', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: SectionCard(title: 'Theme', child: Text('inside')),
      ),
    ),
  );
  expect(find.byType(Icon), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/cards/section_card_test.dart`
Expected: FAIL — 編譯錯誤，無 `icon` 參數。

- [ ] **Step 3: Modify `lib/widgets/cards/section_card.dart`**

整個檔案改成：

```dart
// lib/widgets/cards/section_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final titleText = Text(title, style: theme.textTheme.titleLarge);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon == null)
            titleText
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: tokens.textPrimary),
                const SizedBox(width: AppSpacing.s),
                Flexible(child: titleText),
              ],
            ),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/cards/section_card_test.dart`
Expected: PASS — 全部通過。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/section_card.dart test/widgets/cards/section_card_test.dart
git commit -m "feat(section-card): support optional leading icon"
```

---

## Task 3: ChartCard 加 `icon` 參數

**Files:**
- Modify: `lib/widgets/cards/chart_card.dart`
- Test: `test/widgets/cards/chart_card_test.dart`

- [ ] **Step 1: Write the failing test**

把以下測試加到 `test/widgets/cards/chart_card_test.dart` `main()` 函式內：

```dart
testWidgets('renders leading icon when provided', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: ChartCard(
          title: 'Rarity',
          icon: Icons.pie_chart_outline,
          chart: Center(child: Text('chart-content')),
        ),
      ),
    ),
  );
  expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
  expect(find.text('Rarity'), findsOneWidget);
});

testWidgets('renders no icon when icon is null', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: ChartCard(
          title: 'Rarity',
          chart: Center(child: Text('chart-content')),
        ),
      ),
    ),
  );
  expect(find.byType(Icon), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/cards/chart_card_test.dart`
Expected: FAIL — 編譯錯誤。

- [ ] **Step 3: Modify `lib/widgets/cards/chart_card.dart`**

整個檔案改成：

```dart
// lib/widgets/cards/chart_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.chart,
    this.legend,
    this.height = 380,
    this.icon,
  });

  final String title;
  final Widget chart;
  final Widget? legend;

  /// 卡片固定高度；傳 `null` 則改為依內容 shrink-wrap，chart 不會被
  /// `Expanded` 撐滿（適合非圓形、自身有 intrinsic height 的圖表）。
  final double? height;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final fixedHeight = height != null;
    final titleText = Text(title, style: theme.textTheme.titleLarge);

    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon == null)
            titleText
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: tokens.textPrimary),
                const SizedBox(width: AppSpacing.s),
                Flexible(child: titleText),
              ],
            ),
          const SizedBox(height: AppSpacing.l),
          if (fixedHeight) Expanded(child: chart) else chart,
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.s),
            legend!,
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/cards/chart_card_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/chart_card.dart test/widgets/cards/chart_card_test.dart
git commit -m "feat(chart-card): support optional leading icon"
```

---

## Task 4: 新增 InlineSectionTitle

**Files:**
- Create: `lib/widgets/inline_section_title.dart`
- Test: `test/widgets/inline_section_title_test.dart`

- [ ] **Step 1: Write the failing test**

新建 `test/widgets/inline_section_title_test.dart`：

```dart
// test/widgets/inline_section_title_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';

void main() {
  testWidgets('renders icon and title side by side', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: InlineSectionTitle(
            icon: Icons.timeline,
            title: '5★ 時間軸 (3)',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.timeline), findsOneWidget);
    expect(find.text('5★ 時間軸 (3)'), findsOneWidget);
  });

  testWidgets('title uses titleLarge style', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: InlineSectionTitle(
            icon: Icons.table_chart_outlined,
            title: '紀錄列表',
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('紀錄列表'));
    expect(text.style?.fontSize, 18); // AppFontSize.title
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/inline_section_title_test.dart`
Expected: FAIL — `inline_section_title.dart` 還不存在。

- [ ] **Step 3: Create `lib/widgets/inline_section_title.dart`**

```dart
// lib/widgets/inline_section_title.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 用在頁面內、不在卡片裡的區塊標題（titleLarge + 前置 icon）。
/// 視覺與 [SectionCard]、[ChartCard] 的標題列一致。
class InlineSectionTitle extends StatelessWidget {
  const InlineSectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: tokens.textPrimary),
        const SizedBox(width: AppSpacing.s),
        Flexible(
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/inline_section_title_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/inline_section_title.dart test/widgets/inline_section_title_test.dart
git commit -m "feat(inline-section-title): add reusable inline section title widget"
```

---

## Task 5: OverviewPage caller 傳 icon

**Files:**
- Modify: `lib/pages/overview_page.dart`

- [ ] **Step 1: Read the file**

先確認目前 `overview_page.dart` 的 PageHeader / ChartCard / inline title 在哪些行：
- `PageHeader(title: l.pageOverviewTitle)` 在第 50 行附近
- `ChartCard(title: l.statsRarityDistribution, ...)` 在 134 行附近
- `ChartCard(title: l.statsItemTypeDistribution, ...)` 在 141 行附近
- `ChartCard(title: l.bannerFiveStarCountTitle, ...)` 在 190 行附近
- `Text(l.timelineCountFiveStar(...), style: titleLarge)` 在 200-203 行附近

- [ ] **Step 2: 加 PageHeader icon**

把：
```dart
PageHeader(title: l.pageOverviewTitle),
```
改成：
```dart
PageHeader(
  title: l.pageOverviewTitle,
  icon: Icons.dashboard_outlined,
),
```

- [ ] **Step 3: 加 ChartCard icons**

`ChartCard(title: l.statsRarityDistribution, ...)` → 加 `icon: Icons.pie_chart_outline,`
`ChartCard(title: l.statsItemTypeDistribution, ...)` → 加 `icon: Icons.donut_small_outlined,`
`ChartCard(title: l.bannerFiveStarCountTitle, ...)` → 加 `icon: Icons.bar_chart,`

例如其中一個會變成：

```dart
final rarityCard = ChartCard(
  title: l.statsRarityDistribution,
  icon: Icons.pie_chart_outline,
  chart: RarityPie(stats: stats),
  legend: DistributionLegend(
    entries: rarityDistributionEntries(stats, tokens),
  ),
);
```

- [ ] **Step 4: 把內聯 titleLarge 換成 InlineSectionTitle**

import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
```

把：

```dart
const SizedBox(height: AppSpacing.xl),
Text(
  l.timelineCountFiveStar(timelineEntries.length),
  style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: AppSpacing.s),
```

改成：

```dart
const SizedBox(height: AppSpacing.xl),
InlineSectionTitle(
  icon: Icons.timeline,
  title: l.timelineCountFiveStar(timelineEntries.length),
),
const SizedBox(height: AppSpacing.s),
```

- [ ] **Step 5: Verify analyze + tests pass**

Run:
```
dart format lib/pages/overview_page.dart
flutter analyze
flutter test
```

Expected: 無錯誤、`No issues found!`、`All tests passed!`。

- [ ] **Step 6: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "feat(overview-page): add icons to title and section headers"
```

---

## Task 6: BannerPage caller 傳 icon

**Files:**
- Modify: `lib/pages/banner_page.dart`

- [ ] **Step 1: 加 `_iconForGachaType` helper**

在檔案最後（class `BannerPage` 結尾後）加上：

```dart
IconData _iconForGachaType(GachaType type) {
  return switch (type.nameKey) {
    'gachaTypeCharacter' => Icons.person_outline,
    'gachaTypeWeapon' => Icons.shield_outlined,
    'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
    'gachaTypeStandard' => Icons.history,
    'gachaTypeBeginner' => Icons.school_outlined,
    _ => Icons.casino_outlined,
  };
}
```

> 用 `nameKey` 而非 `gachaType` code 是因為 `nameKey` 在 `GachaType.resolveName` 已是顯示 name 的 source of truth；icon 與 name 同步維護更安全。所有 nameKey 列舉參考 `lib/data/gacha_types.dart`（`gachaTypeCharacter`、`gachaTypeWeapon`、`gachaTypeChronicled`、`gachaTypeStandard`、`gachaTypeBeginner`）。

- [ ] **Step 2: 加 PageHeader icon（兩處：empty records 分支 + 主分支）**

把兩處：

```dart
PageHeader(title: type.resolveName(l)),
```

都改成：

```dart
PageHeader(
  title: type.resolveName(l),
  icon: _iconForGachaType(type),
),
```

- [ ] **Step 3: 加 ChartCard icons**

三個 ChartCard：
- `title: l.statsRarityDistribution` → `icon: Icons.pie_chart_outline,`
- `title: l.statsItemTypeDistribution` → `icon: Icons.donut_small_outlined,`
- `title: l.timelineCountFiveStar(stats.fiveStarCount)` → `icon: Icons.timeline,`

- [ ] **Step 4: 把「紀錄列表」內聯 titleLarge 換成 InlineSectionTitle**

import：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
```

把：

```dart
const SizedBox(height: AppSpacing.xl),
Text(
  l.pageBannerRecordList,
  style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: AppSpacing.s),
```

改成：

```dart
const SizedBox(height: AppSpacing.xl),
InlineSectionTitle(
  icon: Icons.table_chart_outlined,
  title: l.pageBannerRecordList,
),
const SizedBox(height: AppSpacing.s),
```

- [ ] **Step 5: Verify analyze + tests pass**

Run:
```
dart format lib/pages/banner_page.dart
flutter analyze
flutter test
```

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(banner-page): add icons to page title, chart cards, and record list header"
```

---

## Task 7: SettingsPage caller 傳 icon

**Files:**
- Modify: `lib/pages/settings_page.dart`

- [ ] **Step 1: PageHeader icon**

把：

```dart
PageHeader(title: l.settingsTitle),
```

改成：

```dart
PageHeader(
  title: l.settingsTitle,
  icon: Icons.settings_outlined,
),
```

- [ ] **Step 2: 五個 SectionCard icons**

把：

```dart
SectionCard(
  title: l.settingsAppearance,
  child: _ThemeRadios(...),
),
```

加 `icon: Icons.palette_outlined,`。

依序對應：

| SectionCard | icon |
|---|---|
| `title: l.settingsAppearance` | `Icons.palette_outlined` |
| `title: l.settingsLanguage` | `Icons.language` |
| `title: l.settingsDataManagement` | `Icons.folder_outlined` |
| `title: l.settingsAccountManagement` | `Icons.manage_accounts_outlined` |
| `title: l.settingsAbout` | `Icons.info_outline` |

- [ ] **Step 3: Verify analyze + tests pass**

Run:
```
dart format lib/pages/settings_page.dart
flutter analyze
flutter test
```

Expected: PASS。

- [ ] **Step 4: Commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings-page): add icons to page title and section cards"
```

---

## Task 8: ContributorsPage caller 傳 icon

**Files:**
- Modify: `lib/pages/contributors_page.dart`

- [ ] **Step 1: PageHeader icon**

把：

```dart
PageHeader(
  title: l.contributorsTitle,
  subtitle: l.contributorsSubtitle,
),
```

改成：

```dart
PageHeader(
  title: l.contributorsTitle,
  subtitle: l.contributorsSubtitle,
  icon: Icons.volunteer_activism_outlined,
),
```

- [ ] **Step 2: 六個 SectionCard icons**

| SectionCard | icon |
|---|---|
| `title: l.contributorsProjectLeader` | `Icons.workspace_premium_outlined` |
| `title: l.contributorsTesters` | `Icons.bug_report_outlined` |
| `title: l.contributorsGithubContributors` | `Icons.groups_outlined` |
| `title: l.contributorsTranslationReviewer` | `Icons.translate` |
| `title: l.contributorsTranslatedLanguages` | `Icons.public` |
| `title: l.contributorsProjectLicense` | `Icons.gavel_outlined` |

- [ ] **Step 3: Verify analyze + tests pass**

Run:
```
dart format lib/pages/contributors_page.dart
flutter analyze
flutter test
```

Expected: PASS（包含既有 `test/pages/contributors_page_test.dart`）。

- [ ] **Step 4: Commit**

```bash
git add lib/pages/contributors_page.dart
git commit -m "feat(contributors-page): add icons to page title and section cards"
```

---

## Task 9: confirm_dialog 按鈕加 icon

**Files:**
- Modify: `lib/widgets/dialogs/confirm_dialog.dart`
- Test: `test/widgets/dialogs/confirm_dialog_test.dart`

- [ ] **Step 1: Add icon-presence test**

把以下測試加到 `test/widgets/dialogs/confirm_dialog_test.dart` `main()` 函式內（既有測試後面）：

```dart
testWidgets('action buttons render with icons', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showConfirmTypeDialog(
                context: ctx,
                title: 'Confirm',
                body: 'Type X',
                expectedText: 'X',
                cancelLabel: 'Cancel',
                confirmLabel: 'Delete',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.close), findsOneWidget);
  expect(find.byIcon(Icons.delete_outline), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: FAIL — 找不到 icon。

- [ ] **Step 3: Modify `lib/widgets/dialogs/confirm_dialog.dart`**

把 `actions` 區塊：

```dart
actions: [
  TextButton(
    onPressed: () => Navigator.of(context).pop(false),
    child: Text(widget.cancelLabel),
  ),
  FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: tokens.stateDanger,
      foregroundColor: Colors.white,
    ),
    onPressed: matches ? () => Navigator.of(context).pop(true) : null,
    child: Text(widget.confirmLabel),
  ),
],
```

改成：

```dart
actions: [
  TextButton.icon(
    onPressed: () => Navigator.of(context).pop(false),
    icon: const Icon(Icons.close, size: 18),
    label: Text(widget.cancelLabel),
  ),
  FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: tokens.stateDanger,
      foregroundColor: Colors.white,
    ),
    onPressed: matches ? () => Navigator.of(context).pop(true) : null,
    icon: const Icon(Icons.delete_outline, size: 18),
    label: Text(widget.confirmLabel),
  ),
],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/dialogs/confirm_dialog_test.dart`
Expected: PASS。

> **注意**：既有的「delete button disabled until input matches」測試使用 `find.widgetWithText(FilledButton, 'Delete')` — `FilledButton.icon` 仍然是 `FilledButton`，這個 finder 還能找到，測試不會壞。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dialogs/confirm_dialog.dart test/widgets/dialogs/confirm_dialog_test.dart
git commit -m "feat(confirm-dialog): add icons to cancel and delete buttons"
```

---

## Task 10: accounts_picker_dialog 按鈕加 icon

**Files:**
- Modify: `lib/widgets/dialogs/accounts_picker_dialog.dart`
- Test: `test/widgets/dialogs/accounts_picker_dialog_test.dart`

- [ ] **Step 1: Add icon-presence test**

讀 `test/widgets/dialogs/accounts_picker_dialog_test.dart`，找到 `main()` 函式，在最後一個 testWidgets 後面加：

```dart
testWidgets('action buttons render with icons', (tester) async {
  await _open(tester);
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.close), findsOneWidget);
  expect(find.byIcon(Icons.check), findsOneWidget);
});
```

> `_open` 是該檔的 helper（會 push dialog，confirmLabel 預設 '繼續'）。

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart`
Expected: FAIL — 找不到 icon。

- [ ] **Step 3: Modify `lib/widgets/dialogs/accounts_picker_dialog.dart`**

把 `actions` 區塊：

```dart
actions: [
  TextButton(
    onPressed: () => Navigator.of(context).pop(),
    child: Text(l.confirmCancel),
  ),
  FilledButton(
    onPressed: _selected.isEmpty
        ? null
        : () {
            final ordered = [
              for (final e in widget.entries)
                if (_selected.contains(e.uid)) e.uid,
            ];
            Navigator.of(context).pop(ordered);
          },
    child: Text(widget.confirmLabel),
  ),
],
```

改成：

```dart
actions: [
  TextButton.icon(
    onPressed: () => Navigator.of(context).pop(),
    icon: const Icon(Icons.close, size: 18),
    label: Text(l.confirmCancel),
  ),
  FilledButton.icon(
    onPressed: _selected.isEmpty
        ? null
        : () {
            final ordered = [
              for (final e in widget.entries)
                if (_selected.contains(e.uid)) e.uid,
            ];
            Navigator.of(context).pop(ordered);
          },
    icon: const Icon(Icons.check, size: 18),
    label: Text(widget.confirmLabel),
  ),
],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dialogs/accounts_picker_dialog.dart test/widgets/dialogs/accounts_picker_dialog_test.dart
git commit -m "feat(accounts-picker-dialog): add icons to cancel and confirm buttons"
```

---

## Task 11: update_progress_dialog 按鈕加 icon

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1: 找到 `_actions` 函式**

位於 `update_progress_dialog.dart` 39-63 行附近，現狀：

```dart
return switch (p) {
  Preparing() => [
    TextButton(onPressed: r.cancelPreparing, child: Text(l.actionCancel)),
  ],
  WaitingForCapture() => [
    TextButton(
      onPressed: () async {
        await r.cancelCapture();
      },
      child: Text(l.actionCancel),
    ),
  ],
  FetchingBanner() => const <Widget>[],
  UpdateCompleted() || UpdateFailed() => [
    TextButton(onPressed: r.clearProgress, child: Text(l.actionClose)),
  ],
  null => const <Widget>[],
};
```

- [ ] **Step 2: 改成 `.icon` 變體**

```dart
return switch (p) {
  Preparing() => [
    TextButton.icon(
      onPressed: r.cancelPreparing,
      icon: const Icon(Icons.close, size: 18),
      label: Text(l.actionCancel),
    ),
  ],
  WaitingForCapture() => [
    TextButton.icon(
      onPressed: () async {
        await r.cancelCapture();
      },
      icon: const Icon(Icons.close, size: 18),
      label: Text(l.actionCancel),
    ),
  ],
  FetchingBanner() => const <Widget>[],
  UpdateCompleted() || UpdateFailed() => [
    TextButton.icon(
      onPressed: r.clearProgress,
      icon: const Icon(Icons.close, size: 18),
      label: Text(l.actionClose),
    ),
  ],
  null => const <Widget>[],
};
```

- [ ] **Step 3: Verify analyze + tests pass**

Run:
```
dart format lib/widgets/update_progress_dialog.dart
flutter analyze
flutter test
```

Expected: PASS。

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/update_progress_dialog.dart
git commit -m "feat(update-progress-dialog): add icons to cancel and close buttons"
```

---

## Task 12: account_management `_Row` 按鈕加 icon

**Files:**
- Modify: `lib/widgets/cards/account_management.dart`

- [ ] **Step 1: 找到 `_Row.build` 末尾的兩個 TextButton**

位於 `account_management.dart` 253-264 行附近：

```dart
if (!widget.isActive)
  TextButton(
    onPressed: widget.onSetActive,
    child: Text(l.accountSetActive),
  ),
TextButton(
  onPressed: widget.onRemove,
  child: Text(
    l.accountRemove,
    style: TextStyle(color: tokens.stateDanger),
  ),
),
```

- [ ] **Step 2: 改成 `.icon` 變體**

```dart
if (!widget.isActive)
  TextButton.icon(
    onPressed: widget.onSetActive,
    icon: const Icon(Icons.check_circle_outline, size: 18),
    label: Text(l.accountSetActive),
  ),
TextButton.icon(
  onPressed: widget.onRemove,
  icon: Icon(
    Icons.delete_outline,
    size: 18,
    color: tokens.stateDanger,
  ),
  label: Text(
    l.accountRemove,
    style: TextStyle(color: tokens.stateDanger),
  ),
),
```

> 「移除」icon 也染紅色，與文字一致；「設為活躍」沿用預設色（不需 stateDanger）。

- [ ] **Step 3: Verify analyze + tests pass**

Run:
```
dart format lib/widgets/cards/account_management.dart
flutter analyze
flutter test
```

Expected: PASS（包含既有 `test/widgets/cards/account_management_test.dart`，因為按鈕的 label 沒變、只是多了 icon）。

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/cards/account_management.dart
git commit -m "feat(account-management): add icons to row action buttons"
```

---

## Task 13: 最終品質檢查

**Files:** N/A — 跑專案的完整 pre-commit 流程。

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 列出修改的檔案，無錯誤。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 視覺驗證（manual）**

Run: `flutter run -d windows`

依序檢查：

- **Overview 頁**：標題列有 `dashboard` icon；三張 ChartCard 標題列各自有 pie / donut / bar icon；「5★ 時間軸 (n)」前有 timeline icon。
- **各 Banner 頁（5 個卡池）**：標題列 icon 對應正確（角色/武器/集錄/常駐/新手）；ChartCard / 「紀錄列表」前有 icon。
- **Settings 頁**：標題 `settings` icon；五張 SectionCard 標題 icon 對應正確。
- **Contributors 頁**：標題 `volunteer_activism` icon；六張 SectionCard 標題 icon 對應正確。
- **Confirm dialog**（清除目前帳號 / 全部清除 / 匯入）：取消按鈕 close icon、刪除按鈕 delete_outline icon。
- **Accounts picker dialog**（匯出 / 匯入）：取消 close、確認 check。
- **Update progress dialog**（按更新資料）：取消按鈕 close icon。
- **Account management row**：「設為活躍」check_circle_outline、「移除」delete_outline 紅。

切換 Light / Dark theme 各看一次，icon 顏色都跟標題文字同色（`textPrimary`）、間距一致。

- [ ] **Step 5: 若上面任何一步發現問題**

修掉後重複 Step 1-3，並在受影響的 task 補 commit。

---

## YAGNI / DRY 邊界

- 不額外為 icon 設計 theme token——統一用 `textPrimary` 就好。
- 不重構 `_DataManagement` 內既有的 `.icon` 按鈕（它們已經有 icon 了）。
- BannerPage 的 `_iconForGachaType` 是 caller-local 函式，不擴散到 `data/gacha_types.dart`（IconData 不該污染 model）。
- `InlineSectionTitle` 只給有實際 caller 的兩處用——之後若有第三處再用；不預先設計 `subtitle` 等多餘參數。
