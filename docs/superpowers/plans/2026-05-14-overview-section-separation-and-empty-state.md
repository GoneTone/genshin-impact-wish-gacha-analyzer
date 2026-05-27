# 綜合頁區塊視覺分隔 + 空狀態保護 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 綜合頁「祈願綜合」與「頌願綜合」兩區塊在視覺上用 Divider 明顯分開,任一區塊無資料時保留標題、僅在內容區顯示縮小版空狀態 placeholder。

**Architecture:** `EmptyState` widget 擴充 `compact` 變體(40px icon + 邊框、非滿屏)與 `noRecords` factory 的 `title` override,讓兩個 section 用同一個 factory 但顯示不同文案;移除 `EmptyState.noOdesRecords` factory。`OverviewPage` 移除 `odesAll.isEmpty` 早返,改在兩個 `_OverviewSection` 之間放 `Divider`;`_OverviewSection` 內部判斷 `banners` 是否全空,空就只 render 標題 + compact `EmptyState`。

**Tech Stack:** Flutter / Dart;Riverpod(既有);Flutter i18n(ARB + `flutter gen-l10n`);`flutter_test` widget tests。

**Spec:** `docs/superpowers/specs/2026-05-14-overview-section-separation-and-empty-state-design.md`

---

## Task 1: `EmptyState` 加 `compact` 變體與 `noRecords` 的 `title` override

**Files:**
- Create: `test/widgets/empty_state_test.dart`
- Modify: `lib/widgets/empty_state.dart`(完整 build 邏輯重寫;`noRecords` factory 改簽名)

EmptyState 過去沒有獨立測試,本 task 一併補上。`noOdesRecords` factory 在本 task **不**移除(會留下未引用 dead code,讓 Task 3 一併處理,避免 Task 1 的 `flutter analyze` 連動 `overview_page.dart`)。

### Steps

- [ ] **Step 1.1: 寫 failing widget tests**

`test/widgets/empty_state_test.dart`(新檔)整檔內容:

```dart
// test/widgets/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'Hant'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('EmptyState 滿屏版(compact = false)', () {
    testWidgets('renders 72px icon inside Center', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(icon: Icons.inbox_outlined, title: '無資料'),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 72);
      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('title uses titleLarge style', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(icon: Icons.inbox_outlined, title: '無資料'),
        ),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      expect(text.style?.fontSize, 18); // titleLarge = AppFontSize.title
    });
  });

  group('EmptyState compact 變體', () {
    testWidgets('renders 40px icon and bordered container', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);

      // compact 版本不在 Center 內(全頁置中)
      expect(find.byType(Center), findsNothing);

      // 最外層 Container 帶 borderSubtle 邊框
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
    });

    testWidgets('title uses titleMedium style in compact mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      // compact 用 titleMedium、滿屏用 titleLarge (=18),兩者字級不同
      expect(text.style?.fontSize, isNot(18));
    });
  });

  group('EmptyState.noRecords factory', () {
    testWidgets('uses l.emptyNoRecords when title is omitted', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => EmptyState.noRecords(context),
          ),
        ),
      );
      expect(find.text('此卡池無紀錄'), findsOneWidget);
    });

    testWidgets('uses title override when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                EmptyState.noRecords(context, title: '自訂標題 XYZ'),
          ),
        ),
      );
      expect(find.text('自訂標題 XYZ'), findsOneWidget);
      expect(find.text('此卡池無紀錄'), findsNothing);
    });

    testWidgets('compact:true makes icon 40px', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => EmptyState.noRecords(context, compact: true),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);
    });
  });
}
```

- [ ] **Step 1.2: 跑測試確認 fail**

```
flutter test test/widgets/empty_state_test.dart
```

Expected: 多個 case 失敗,訊息會抱怨 `compact` 不是 `EmptyState` 的有效參數、`EmptyState.noRecords` 不接 `title` / `compact` 參數。

- [ ] **Step 1.3: 重寫 `lib/widgets/empty_state.dart`**

完整新內容(整檔覆寫):

```dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// 縮小版:用於「頁面內某個 section 的空位佔位」(icon 40px + 邊框框出範圍),
  /// 非滿屏置中。
  final bool compact;

  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: l.emptyNoSyncMessage,
      action: action,
    );
  }

  /// `title` 可選 override 既定 `l.emptyNoRecords`,讓不同 section 共用此 factory。
  /// `compact: true` 時改為縮小版邊框 placeholder,非滿屏。
  factory EmptyState.noRecords(
    BuildContext context, {
    String? title,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: title ?? l.emptyNoRecords,
      compact: compact,
    );
  }

  factory EmptyState.noFiltered(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: l.emptyNoFiltered,
      action: action,
    );
  }

  factory EmptyState.noOdesRecords(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.auto_awesome_outlined,
      title: l.emptyNoOdesRecords,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: AppSpacing.l,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.s),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.m),
              action!,
            ],
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: tokens.textMuted),
          const SizedBox(height: AppSpacing.l),
          Text(title, style: theme.textTheme.titleLarge),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.l),
            action!,
          ],
        ],
      ),
    );
  }
}
```

> 註:本 step **不**移除 `factory EmptyState.noOdesRecords` — 它仍被 `overview_page.dart` 引用,Task 3 同步移除呼叫端跟 factory。

- [ ] **Step 1.4: 跑測試確認通過**

```
flutter test test/widgets/empty_state_test.dart
```

Expected: 所有 7 個 case PASS。

- [ ] **Step 1.5: Commit**

```
git add lib/widgets/empty_state.dart test/widgets/empty_state_test.dart
git commit -m "feat(empty-state): add compact variant and title override on noRecords"
```

---

## Task 2: ARB 新增 `emptyNoWishRecords`(3 locale)

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`(template)
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Regenerate: `lib/l10n/generated/`(`flutter gen-l10n` 產出)

不動 `app_zh.arb` / `app_ja.arb` / `app_es.arb` / `app_fr.arb` / `app_pt.arb` / `app_th.arb` / `app_vi.arb`,由 Flutter gen-l10n fallback 到 template(`zh_Hant`)。

### Steps

- [ ] **Step 2.1: 在 `app_zh_Hant.arb` 加 `emptyNoWishRecords`**

在 `lib/l10n/app_zh_Hant.arb` 找到 `"emptyNoOdesRecords": "尚無頌願記錄",` 那一行(目前 line 85),**之後**緊接著加一行:

```
  "emptyNoWishRecords": "尚無祈願記錄",
```

最終該區段應為:

```json
  "emptyNoRecords": "此卡池無紀錄",
  "emptyNoFiltered": "沒有符合條件的紀錄",
  "emptyNoOdesRecords": "尚無頌願記錄",
  "emptyNoWishRecords": "尚無祈願記錄",
```

- [ ] **Step 2.2: 在 `app_zh_Hans.arb` 加 `emptyNoWishRecords`**

在 `lib/l10n/app_zh_Hans.arb` 找到 `"emptyNoOdesRecords": ...` 那一行,**之後**緊接著加一行:

```
  "emptyNoWishRecords": "尚无祈愿记录",
```

- [ ] **Step 2.3: 在 `app_en.arb` 加 `emptyNoWishRecords`**

在 `lib/l10n/app_en.arb` 找到 `"emptyNoOdesRecords": "No Odes records yet",`(目前 line 65),**之後**緊接著加一行:

```
  "emptyNoWishRecords": "No wish records yet",
```

- [ ] **Step 2.4: 重生 generated localization**

```
flutter gen-l10n
```

Expected: 無錯誤輸出。

- [ ] **Step 2.5: 驗證 generated 檔含新 getter**

```
grep -n "emptyNoWishRecords" lib/l10n/generated/app_localizations.dart
grep -n "emptyNoWishRecords" lib/l10n/generated/app_localizations_zh.dart
grep -n "emptyNoWishRecords" lib/l10n/generated/app_localizations_en.dart
```

Expected:
- `app_localizations.dart` 有 abstract getter 宣告
- `app_localizations_zh.dart` 三個 class(`AppLocalizationsZh`、`AppLocalizationsZhHans`、`AppLocalizationsZhHant`)各有實作,值依序為「尚無祈願記錄」/「尚无祈愿记录」/「尚無祈願記錄」(`AppLocalizationsZh` 因為 ARB 無此 key,會 fallback 到 template 文案「尚無祈願記錄」)
- `app_localizations_en.dart` 值為「No wish records yet」
- 其他語系 generated 檔(`_ja` / `_es` / `_fr` / `_pt` / `_th` / `_vi`)應該也 fallback 顯示「尚無祈願記錄」

- [ ] **Step 2.6: Commit**

```
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "feat(i18n): add emptyNoWishRecords key (zh_Hant/zh_Hans/en)"
```

---

## Task 3: `OverviewPage` / `_OverviewSection` 套用 + 移除 `noOdesRecords` factory

**Files:**
- Modify: `lib/pages/overview_page.dart`(`OverviewPage.build` 134–169 / `_OverviewSection` 172–361)
- Modify: `lib/widgets/empty_state.dart`(移除 `factory EmptyState.noOdesRecords`)

### Steps

- [ ] **Step 3.1: 修改 `_OverviewSection` 加 `emptyTitle` 與 `hasData` 判斷**

`lib/pages/overview_page.dart` 第 172–207 行(`_OverviewSection` constructor / fields / `build` 開頭),把整段改成:

```dart
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.types,
    required this.banners,
    required this.stats,
    required this.bannerColors,
    required this.statCards,
    required this.emptyTitle,
  });

  final String title;
  final List<GachaType> types;
  final Map<String, List<WishRecord>> banners;
  final WishStats stats;
  final BannerColors bannerColors;
  final List<Widget> statCards;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final hasData = banners.values.any((r) => r.isNotEmpty);

    if (!hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
          const SizedBox(height: AppSpacing.m),
          EmptyState.noRecords(context, title: emptyTitle, compact: true),
        ],
      );
    }

    final typesByGt = <String, GachaType>{
      for (final t in types) t.gachaType: t,
    };

    final timelineEntries = buildTimelineEntriesAcrossBanners(
      banners,
      rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
    );
    final timelineNowPulls = pullsSinceLastRankedAcrossBanners(
      banners,
      rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
    );
    final timelineRank = types.first.primaryPity.rank;

    return Column(
```

(這段 `return Column(` 之後既有「stat row、pie row、bar chart、timeline」內容**完全不變**,結尾 `);` 也不變。只是把上面 build 開頭的 5 行替換成新的 `hasData` early return + 既有 typesByGt/timeline 計算前移。)

> 注意:`final l = AppLocalizations.of(context)!;` 雖然新 build 路徑不直接用,但既有路徑後續會用到,保留。

- [ ] **Step 3.2: 修改 `OverviewPage.build` — 移除早返、插 Divider、傳 emptyTitle**

`lib/pages/overview_page.dart` 第 134–169 行(`return SingleChildScrollView` 整段),覆寫為:

```dart
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: l.pageOverviewTitle,
            icon: Icons.dashboard_outlined,
          ),
          _OverviewSection(
            title: l.pageOverviewWishSection,
            types: wishTypes,
            banners: wishBanners,
            stats: wishStats,
            bannerColors: bannerColors,
            statCards: wishStatCards,
            emptyTitle: l.emptyNoWishRecords,
          ),
          const SizedBox(height: AppSpacing.xl),
          Divider(
            color: Theme.of(context).gacha.borderEmphasis,
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: AppSpacing.xl),
          _OverviewSection(
            title: l.pageOverviewOdesSection,
            types: odesTypes,
            banners: odesBanners,
            stats: odesStats,
            bannerColors: bannerColors,
            statCards: odesStatCards,
            emptyTitle: l.emptyNoOdesRecords,
          ),
        ],
      ),
    );
  }
}
```

(上方既有 `final tokens = Theme.of(context).gacha;` 在 line 33 已存在,Divider 可直接寫 `color: tokens.borderEmphasis` 也可重新取一次 `Theme.of(context).gacha`;選後者更直白,且既有 `tokens` 變數只有 stat cards 用到,保留範圍最小。)

> 同時刪除既有 import 中已經不需要的 `import '.../empty_state.dart'` ? **不需要刪 import**,因為 `OverviewPage.build` 第 41 行還用 `EmptyState.noSync(context)`,且 `_OverviewSection` 內 `EmptyState.noRecords(...)` 也用得到。

- [ ] **Step 3.3: 移除 `EmptyState.noOdesRecords` factory**

`lib/widgets/empty_state.dart`,刪除 `factory EmptyState.noOdesRecords` 整個區塊(在 Task 1 完成後該檔的 line ~50–56):

```dart
  factory EmptyState.noOdesRecords(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.auto_awesome_outlined,
      title: l.emptyNoOdesRecords,
    );
  }
```

刪除上述 6 行(連同上下空白行)。

- [ ] **Step 3.4: 跑 analyze 確認沒漏引用**

```
flutter analyze
```

Expected: `No issues found!`

若 fail,常見原因是 `overview_page.dart` 仍引用 `EmptyState.noOdesRecords(context)` — 回頭確認 Step 3.2 是否覆寫完整。

- [ ] **Step 3.5: 跑全套測試**

```
flutter test
```

Expected: `All tests passed!`

- [ ] **Step 3.6: Commit**

```
git add lib/pages/overview_page.dart lib/widgets/empty_state.dart
git commit -m "feat(overview): split wish/odes sections with divider and per-section empty placeholders"
```

---

## Task 4: 提交前品質檢查(最終 pass)

**Files:** 全 repo(format / analyze / test)

`CLAUDE.md` 規定 commit 前要跑這三項。Task 1 / 2 / 3 各自已跑過相關檢查,本 task 是最終確認整個 stack 沒被中間 step 留下髒東西。

### Steps

- [ ] **Step 4.1: 格式化**

```
dart format lib/ test/
```

Expected: 若有檔案被 reformat,git status 會看到變更;若已格式整齊,輸出顯示「0 files were changed」。

- [ ] **Step 4.2: 若 Step 4.1 有變更,commit**

只在 Step 4.1 真的改了檔案時跑:

```
git status
# 確認改的是哪些檔案
git add <被 format 動到的檔案>
git commit -m "chore: dart format"
```

否則跳過。

- [ ] **Step 4.3: Analyze**

```
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4.4: 全套測試**

```
flutter test
```

Expected: `All tests passed!`

---

## Self-Review(計畫撰寫者已自查,記錄於下)

**Spec coverage:**

| Spec 章節 | 覆蓋 Task |
|---|---|
| §4.1 EmptyState 擴充 | Task 1 |
| §4.2 ARB 新增 emptyNoWishRecords | Task 2 |
| §4.3 `_OverviewSection` empty 保護 | Task 3 (Step 3.1) |
| §4.4 OverviewPage Divider + 移除早返 | Task 3 (Step 3.2) |
| §4.5 noOdesRecords factory 移除 | Task 3 (Step 3.3) |
| §5.1 empty_state_test.dart | Task 1 (Step 1.1) |
| §6 提交前品質檢查 | Task 4 |

**Placeholder scan:** 無 TBD/TODO/「補上 X」字眼;所有 code step 都有完整 code 塊。

**Type consistency:**
- `_OverviewSection.emptyTitle: String`(Task 3 §3.1 宣告)— 與 Task 3 §3.2 傳 `l.emptyNoWishRecords` / `l.emptyNoOdesRecords` 一致(`AppLocalizations` getter 都回傳 `String`)。
- `EmptyState.compact: bool = false` / `EmptyState.noRecords({String? title, bool compact = false})`(Task 1 §1.3)— 與 Task 3 §3.1 呼叫 `EmptyState.noRecords(context, title: emptyTitle, compact: true)` 簽名一致。
- `Divider(color:, height:, thickness:)`(Task 3 §3.2)— 標準 Flutter `Divider`,參數 OK。
