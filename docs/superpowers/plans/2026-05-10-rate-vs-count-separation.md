# Rate vs Count Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「中獎率（%）」與「中獎數（件）」在 UI 上明確分離 — Stat Card 主視覺=次數、副視覺=「佔總抽 X.XX%」；餅圖切片不再有字，旁邊以分欄圖例呈現「次數」與「率」。

**Architecture:** 新增通用 `DistributionLegend` widget（搭配 `DistributionEntry`）；現有 `RarityPie` / `ItemTypePie` 把切片標題隱藏（`showTitle: false`），並各自提供 module-level helper 產生 entries；OverviewPage 與 BannerPage 在呼叫 `ChartCard` 時注入 `legend`。l10n 新增 5 個 key、移除 5 個過時 key。`ChartCard` / `StatCard` / `WishStats` 不需修改。

**Tech Stack:** Flutter, Riverpod, fl_chart, flutter gen-l10n。

---

## File Structure

**Create:**
- `lib/widgets/distribution_legend.dart` — 通用 legend widget 與 `DistributionEntry` 資料類別。
- `test/widgets/distribution_legend_test.dart` — widget 測試。

**Modify:**
- `lib/widgets/rarity_pie.dart` — 切片標題隱藏；新增 `rarityDistributionEntries` 模組層 helper。
- `lib/widgets/item_type_pie.dart` — 同上（含 i18n）。
- `lib/pages/overview_page.dart` — Stat card label/subtitle、ChartCard title 與 legend。
- `lib/pages/banner_page.dart` — ChartCard title 與 legend。
- `lib/l10n/app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb`、`app_zh.arb` — 新增/移除 key。

**Auto-regenerated（不要手動編輯）：**
- `lib/l10n/generated/app_localizations*.dart` — 透過 `flutter gen-l10n`。

**No changes:**
- `lib/widgets/cards/chart_card.dart`（`legend` 參數已具備）
- `lib/widgets/cards/stat_card.dart`（API 已足夠）
- `lib/services/wish_stats.dart`（rate/count getter 已足夠）

---

## Task 1: 新增 l10n keys

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`（template）
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Auto-regenerate: `lib/l10n/generated/`

新增 5 個 key：`statsFiveStarCount`、`statsFourStarCount`、`statsShareOfTotal`、`statsRarityDistribution`、`statsItemTypeDistribution`。**舊 key 暫不移除**（會在 Task 7 才刪，避免中途 build 失敗）。

- [ ] **Step 1：在 `lib/l10n/app_zh_Hant.arb`（template）的 `statsNoData` 上方新增 5 個 key**

於檔案中找到這段：

```json
"statsTotal": "總抽數",
"statsFiveStarRate": "5★ 中獎率",
"statsFourStarRate": "4★ 中獎率",
"statsThreeStarRate": "3★ 中獎率",
"statsCharacterRate": "角色中獎率",
"statsWeaponRate": "武器中獎率",
"statsNoData": "無資料",
```

改為：

```json
"statsTotal": "總抽數",
"statsFiveStarRate": "5★ 中獎率",
"statsFourStarRate": "4★ 中獎率",
"statsThreeStarRate": "3★ 中獎率",
"statsCharacterRate": "角色中獎率",
"statsWeaponRate": "武器中獎率",
"statsFiveStarCount": "5★ 件數",
"statsFourStarCount": "4★ 件數",
"statsShareOfTotal": "佔總抽 {rate}%",
"@statsShareOfTotal": {
  "placeholders": { "rate": { "type": "String" } }
},
"statsRarityDistribution": "稀有度分布",
"statsItemTypeDistribution": "類型分布",
"statsNoData": "無資料",
```

- [ ] **Step 2：在 `lib/l10n/app_zh_Hans.arb` 對應位置新增**

```json
"statsFiveStarCount": "5★ 件数",
"statsFourStarCount": "4★ 件数",
"statsShareOfTotal": "占总抽 {rate}%",
"@statsShareOfTotal": {
  "placeholders": { "rate": { "type": "String" } }
},
"statsRarityDistribution": "稀有度分布",
"statsItemTypeDistribution": "类型分布",
```

- [ ] **Step 3：在 `lib/l10n/app_zh.arb` 對應位置新增**

```json
"statsFiveStarCount": "5★ 件數",
"statsFourStarCount": "4★ 件數",
"statsShareOfTotal": "佔總抽 {rate}%",
"@statsShareOfTotal": {
  "placeholders": { "rate": { "type": "String" } }
},
"statsRarityDistribution": "稀有度分布",
"statsItemTypeDistribution": "類型分布",
```

- [ ] **Step 4：在 `lib/l10n/app_en.arb` 對應位置新增**

```json
"statsFiveStarCount": "5★ Count",
"statsFourStarCount": "4★ Count",
"statsShareOfTotal": "{rate}% of total",
"@statsShareOfTotal": {
  "placeholders": { "rate": { "type": "String" } }
},
"statsRarityDistribution": "Rarity Distribution",
"statsItemTypeDistribution": "Type Distribution",
```

- [ ] **Step 5：重新生成 l10n**

Run: `flutter gen-l10n`
Expected: 無 error，`lib/l10n/generated/app_localizations*.dart` 內含新增的 getter（`String get statsFiveStarCount;` 等與 `String statsShareOfTotal(String rate);`）。

- [ ] **Step 6：跑 analyze 確認無錯**

Run: `flutter analyze`
Expected: `No issues found!` 或僅有與本 Task 無關的既有警告。

- [ ] **Step 7：commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/generated
git commit -m "feat(l10n): add count/share/distribution strings for rate-vs-count split"
```

---

## Task 2: DistributionEntry + DistributionLegend widget（TDD）

**Files:**
- Create: `lib/widgets/distribution_legend.dart`
- Create: `test/widgets/distribution_legend_test.dart`

- [ ] **Step 1：寫第一個 failing test（基本渲染）**

新檔 `test/widgets/distribution_legend_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(body: SizedBox(width: 320, child: child)),
      );

  testWidgets('renders name, count, and rate for each entry', (tester) async {
    await tester.pumpWidget(_wrap(const DistributionLegend(entries: [
      DistributionEntry(
          color: Color(0xFFD4A64A), name: '5★', count: 12, rate: 0.0123),
      DistributionEntry(
          color: Color(0xFFB48CD6), name: '4★', count: 88, rate: 0.0907),
    ])));
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1.23%'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('9.07%'), findsOneWidget);
  });
}
```

- [ ] **Step 2：跑測試確認失敗（檔案還沒建）**

Run: `flutter test test/widgets/distribution_legend_test.dart`
Expected: 編譯失敗，訊息類似 `Target of URI doesn't exist: 'package:.../widgets/distribution_legend.dart'`。

- [ ] **Step 3：建立 widget 與資料類別**

新檔 `lib/widgets/distribution_legend.dart`：

```dart
// lib/widgets/distribution_legend.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class DistributionEntry {
  const DistributionEntry({
    required this.color,
    required this.name,
    required this.count,
    required this.rate,
  });

  final Color color;
  final String name;
  final int count;

  /// 0.0 ~ 1.0
  final double rate;
}

class DistributionLegend extends StatelessWidget {
  const DistributionLegend({super.key, required this.entries});

  final List<DistributionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final visible =
        entries.where((e) => e.count > 0).toList(growable: false);

    final tabular = const [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    e.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: tokens.textPrimary),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${e.count}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${(e.rate * 100).toStringAsFixed(2)}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textMuted,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4：跑測試確認通過**

Run: `flutter test test/widgets/distribution_legend_test.dart`
Expected: PASS（1 test）。

- [ ] **Step 5：加入「count == 0 entry 不渲染」測試**

於 `test/widgets/distribution_legend_test.dart` 的 `main()` 內 append：

```dart
testWidgets('hides entries with count == 0', (tester) async {
  await tester.pumpWidget(_wrap(const DistributionLegend(entries: [
    DistributionEntry(
        color: Color(0xFFD4A64A), name: '5★', count: 12, rate: 0.0123),
    DistributionEntry(
        color: Color(0xFF9E9E9E), name: '未知', count: 0, rate: 0.0),
  ])));
  expect(find.text('5★'), findsOneWidget);
  expect(find.text('未知'), findsNothing);
  expect(find.text('0'), findsNothing);
});
```

- [ ] **Step 6：跑測試確認新增的測試通過**

Run: `flutter test test/widgets/distribution_legend_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 7：加入「率格式為兩位小數」測試**

於 `main()` 內 append：

```dart
testWidgets('formats rate with two decimals', (tester) async {
  await tester.pumpWidget(_wrap(const DistributionLegend(entries: [
    DistributionEntry(
        color: Color(0xFF7EC0D8), name: '角色', count: 1, rate: 0.5),
    DistributionEntry(
        color: Color(0xFFE6C389), name: '武器', count: 1, rate: 0.5000999),
  ])));
  expect(find.text('50.00%'), findsOneWidget);
  // 0.5000999 * 100 = 50.00999 → toStringAsFixed(2) = "50.01"
  expect(find.text('50.01%'), findsOneWidget);
});
```

- [ ] **Step 8：跑測試確認通過**

Run: `flutter test test/widgets/distribution_legend_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 9：commit**

```bash
git add lib/widgets/distribution_legend.dart test/widgets/distribution_legend_test.dart
git commit -m "feat(widgets): add DistributionLegend with count/rate columns"
```

---

## Task 3: RarityPie — 加 helper + 隱藏切片字（TDD）

**Files:**
- Modify: `lib/widgets/rarity_pie.dart`
- Create: `test/widgets/rarity_pie_test.dart`

- [ ] **Step 1：寫 helper 的 failing test**

新檔 `test/widgets/rarity_pie_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

void main() {
  group('rarityDistributionEntries', () {
    test('returns 5★/4★/3★ entries with correct counts and rates', () {
      const stats = WishStats(
        total: 100,
        fiveStarCount: 1,
        fourStarCount: 9,
        threeStarOrBelowCount: 90,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries, hasLength(3));
      expect(entries[0].name, '5★');
      expect(entries[0].count, 1);
      expect(entries[0].rate, closeTo(0.01, 1e-9));
      expect(entries[0].color, GachaTokens.dark.fiveStar);
      expect(entries[1].name, '4★');
      expect(entries[1].count, 9);
      expect(entries[2].name, '3★');
      expect(entries[2].count, 90);
    });

    test('keeps zero-count entries (legend filters them itself)', () {
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries, hasLength(3));
      expect(entries.every((e) => e.count == 0), isTrue);
    });
  });
}
```

- [ ] **Step 2：跑測試確認失敗**

Run: `flutter test test/widgets/rarity_pie_test.dart`
Expected: 編譯錯誤 `The function 'rarityDistributionEntries' isn't defined`。

- [ ] **Step 3：在 `lib/widgets/rarity_pie.dart` 新增 helper 並隱藏切片字**

完整改寫此檔內容為：

```dart
// lib/widgets/rarity_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

List<DistributionEntry> rarityDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
) {
  return [
    DistributionEntry(
      color: tokens.fiveStar,
      name: '5★',
      count: stats.fiveStarCount,
      rate: stats.fiveStarRate,
    ),
    DistributionEntry(
      color: tokens.fourStar,
      name: '4★',
      count: stats.fourStarCount,
      rate: stats.fourStarRate,
    ),
    DistributionEntry(
      color: tokens.threeStar,
      name: '3★',
      count: stats.threeStarOrBelowCount,
      rate: stats.threeStarOrBelowRate,
    ),
  ];
}

class RarityPie extends StatelessWidget {
  const RarityPie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData,
            style: TextStyle(color: tokens.textMuted)),
      );
    }
    final sections = <PieChartSectionData>[
      _section(stats.fiveStarCount, tokens.fiveStar),
      _section(stats.fourStarCount, tokens.fourStar),
      _section(stats.threeStarOrBelowCount, tokens.threeStar),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  PieChartSectionData _section(int value, Color color) =>
      PieChartSectionData(
        showTitle: false,
        value: value.toDouble(),
        color: color,
        radius: 60,
      );
}
```

- [ ] **Step 4：跑 helper 測試確認通過**

Run: `flutter test test/widgets/rarity_pie_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5：跑全部測試確認沒打到既有測試**

Run: `flutter test`
Expected: 所有測試 PASS。

- [ ] **Step 6：commit**

```bash
git add lib/widgets/rarity_pie.dart test/widgets/rarity_pie_test.dart
git commit -m "feat(widgets): add rarityDistributionEntries helper, hide pie slice titles"
```

---

## Task 4: ItemTypePie — 加 helper + 隱藏切片字（TDD）

**Files:**
- Modify: `lib/widgets/item_type_pie.dart`
- Create: `test/widgets/item_type_pie_test.dart`

注意：item type helper 接收 `AppLocalizations` 用於本地化「角色 / 武器 / 未知」名稱。

- [ ] **Step 1：寫 helper 的 failing test**

新檔 `test/widgets/item_type_pie_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';

Future<AppLocalizations> _loadL10n() async {
  return AppLocalizations.delegate.load(const Locale('zh', 'Hant'));
}

void main() {
  group('itemTypeDistributionEntries', () {
    test('returns character + weapon when no unknown', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 100,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 38,
        weaponCount: 62,
        unknownCount: 0,
      );
      final entries =
          itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(2));
      expect(entries[0].name, l.kindCharacter);
      expect(entries[0].count, 38);
      expect(entries[0].rate, closeTo(0.38, 1e-9));
      expect(entries[1].name, l.kindWeapon);
      expect(entries[1].count, 62);
    });

    test('appends unknown row when unknownCount > 0', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 10,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 4,
        weaponCount: 5,
        unknownCount: 1,
      );
      final entries =
          itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(3));
      expect(entries.last.name, l.kindUnknown);
      expect(entries.last.count, 1);
      expect(entries.last.rate, closeTo(0.1, 1e-9));
    });

    test('zero total → unknown rate is 0 (no division)', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries =
          itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.rate == 0.0), isTrue);
    });
  });
}
```

- [ ] **Step 2：跑測試確認失敗**

Run: `flutter test test/widgets/item_type_pie_test.dart`
Expected: 編譯錯誤 `itemTypeDistributionEntries isn't defined`。

- [ ] **Step 3：改寫 `lib/widgets/item_type_pie.dart`**

完整內容：

```dart
// lib/widgets/item_type_pie.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

const _unknownColor = Color(0xFF9E9E9E);

List<DistributionEntry> itemTypeDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
  AppLocalizations l,
) {
  return [
    DistributionEntry(
      color: tokens.character,
      name: l.kindCharacter,
      count: stats.characterCount,
      rate: stats.characterRate,
    ),
    DistributionEntry(
      color: tokens.weapon,
      name: l.kindWeapon,
      count: stats.weaponCount,
      rate: stats.weaponRate,
    ),
    if (stats.unknownCount > 0)
      DistributionEntry(
        color: _unknownColor,
        name: l.kindUnknown,
        count: stats.unknownCount,
        rate: stats.total == 0 ? 0.0 : stats.unknownCount / stats.total,
      ),
  ];
}

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData,
            style: TextStyle(color: tokens.textMuted)),
      );
    }
    final sections = <PieChartSectionData>[
      _section(stats.characterCount, tokens.character),
      _section(stats.weaponCount, tokens.weapon),
      if (stats.unknownCount > 0)
        _section(stats.unknownCount, _unknownColor),
    ].where((s) => s.value > 0).toList(growable: false);

    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: 32,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  PieChartSectionData _section(int value, Color color) =>
      PieChartSectionData(
        showTitle: false,
        value: value.toDouble(),
        color: color,
        radius: 60,
      );
}
```

說明：
- 第二個 test 期望 `unknownCount > 0` 時 entries 含「未知」row；helper 中 `if (stats.unknownCount > 0)` 條件判斷實作此邏輯。
- 第三個 test 期望 `total == 0` 時不會除以 0；helper 中 `stats.total == 0 ? 0.0 : ...` 守護此情況。

- [ ] **Step 4：跑 helper 測試確認通過**

Run: `flutter test test/widgets/item_type_pie_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5：跑全部測試**

Run: `flutter test`
Expected: 全 PASS。

- [ ] **Step 6：commit**

```bash
git add lib/widgets/item_type_pie.dart test/widgets/item_type_pie_test.dart
git commit -m "feat(widgets): add itemTypeDistributionEntries helper, hide pie slice titles"
```

---

## Task 5: OverviewPage — Stat card 改文案 + ChartCard 注入 legend

**Files:**
- Modify: `lib/pages/overview_page.dart`

- [ ] **Step 1：在 `lib/pages/overview_page.dart` 加上 distribution_legend 的 import**

於檔案頂端 import 區段（rarity_pie 旁邊）加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
```

- [ ] **Step 2：替換 5★/4★ Stat Card 的 label 與 subtitle**

將 `build()` 中第 55–68 行附近：

```dart
final fiveCard = StatCard(
  label: l.statsFiveStarRate,
  value: '${stats.fiveStarCount}',
  accent: tokens.fiveStar,
  subtitle:
      '${(stats.fiveStarRate * 100).toStringAsFixed(2)}%',
);
final fourCard = StatCard(
  label: l.statsFourStarRate,
  value: '${stats.fourStarCount}',
  accent: tokens.fourStar,
  subtitle:
      '${(stats.fourStarRate * 100).toStringAsFixed(2)}%',
);
```

改為：

```dart
final fiveCard = StatCard(
  label: l.statsFiveStarCount,
  value: '${stats.fiveStarCount}',
  accent: tokens.fiveStar,
  subtitle: l.statsShareOfTotal(
    (stats.fiveStarRate * 100).toStringAsFixed(2),
  ),
);
final fourCard = StatCard(
  label: l.statsFourStarCount,
  value: '${stats.fourStarCount}',
  accent: tokens.fourStar,
  subtitle: l.statsShareOfTotal(
    (stats.fourStarRate * 100).toStringAsFixed(2),
  ),
);
```

- [ ] **Step 3：替換 Row 2 的兩張 ChartCard（RarityPie / ItemTypePie）**

將 `build()` 中第 128–141 行附近：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: '${l.statsFiveStarRate} / ${l.statsFourStarRate} / ${l.statsThreeStarRate}',
    chart: RarityPie(stats: stats),
  ),
),
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: '${l.kindCharacter} / ${l.kindWeapon}',
    chart: ItemTypePie(stats: stats),
  ),
),
```

改為：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.statsRarityDistribution,
    chart: RarityPie(stats: stats),
    legend: DistributionLegend(
      entries: rarityDistributionEntries(stats, tokens),
    ),
  ),
),
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.statsItemTypeDistribution,
    chart: ItemTypePie(stats: stats),
    legend: DistributionLegend(
      entries: itemTypeDistributionEntries(stats, tokens, l),
    ),
  ),
),
```

注意：`tokens` 已在第 25 行宣告（`final tokens = Theme.of(context).gacha;`），可直接使用。

- [ ] **Step 4：跑 analyze 與 test**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全 PASS。

- [ ] **Step 5：實機視覺驗證**

Run: `flutter run -d windows`
驗證項目：
- 總覽頁 Row 1：5★/4★ 卡片標題顯示「5★ 件數」「4★ 件數」，副欄顯示「佔總抽 X.XX%」
- 總覽頁 Row 2：稀有度卡標題為「稀有度分布」、類型卡為「類型分布」；餅圖切片內無文字；圖例顯示三/二行（名稱、次數、率）
- ChartCard 高度 260 下餅圖與圖例不擁擠（若擁擠，於該 ChartCard 加 `height: 320`）

- [ ] **Step 6：commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "feat(overview): use count label, share-of-total subtitle, distribution legends"
```

---

## Task 6: BannerPage — ChartCard 注入 legend

**Files:**
- Modify: `lib/pages/banner_page.dart`

- [ ] **Step 1：加上 import**

於 `lib/pages/banner_page.dart` 頂端 import 區段加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
```

- [ ] **Step 2：替換 Row 2 的兩張 ChartCard**

將 `build()` 中第 170–184 行附近：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.statsFiveStarRate,
    chart: RarityPie(stats: stats),
  ),
),
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: '${l.kindCharacter} / ${l.kindWeapon}',
    chart: ItemTypePie(stats: stats),
  ),
),
```

改為：

```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.statsRarityDistribution,
    chart: RarityPie(stats: stats),
    legend: DistributionLegend(
      entries: rarityDistributionEntries(stats, tokens),
    ),
  ),
),
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.statsItemTypeDistribution,
    chart: ItemTypePie(stats: stats),
    legend: DistributionLegend(
      entries: itemTypeDistributionEntries(stats, tokens, l),
    ),
  ),
),
```

`tokens` 在第 43 行已宣告（`final tokens = Theme.of(context).gacha;`），可直接使用。

- [ ] **Step 3：跑 analyze 與 test**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全 PASS。

- [ ] **Step 4：實機視覺驗證**

Run: `flutter run -d windows`
切換到角色/武器/常駐/新手 任一卡池：
- Row 1 PityCard / 總抽 StatCard 不變
- Row 2 兩張餅圖卡標題「稀有度分布」「類型分布」；切片無字；圖例顯示

- [ ] **Step 5：commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(banner): use distribution title and legend for rarity/type charts"
```

---

## Task 7: 移除已不使用的舊 l10n keys

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Auto-regenerate: `lib/l10n/generated/`

要移除：`statsFiveStarRate`、`statsFourStarRate`、`statsThreeStarRate`、`statsCharacterRate`、`statsWeaponRate`。

- [ ] **Step 1：用搜尋工具確認 dart 程式碼已不引用舊 key**

使用 Grep 工具，於 `lib/pages/`、`lib/widgets/`、`test/` 搜尋：

```
pattern: statsFiveStarRate|statsFourStarRate|statsThreeStarRate|statsCharacterRate|statsWeaponRate
```

Expected：上述目錄為 0 命中。
若 `lib/l10n/generated/` 仍命中屬正常（將於 Step 3 重生）。`lib/l10n/app_*.arb` 命中亦正常（將於 Step 2 移除）。

- [ ] **Step 2：從 4 個 .arb 檔移除這 5 個 key**

於每個 arb 檔中刪除以下 5 行（不存在於某些 locale 時跳過）：

```json
"statsFiveStarRate": "...",
"statsFourStarRate": "...",
"statsThreeStarRate": "...",
"statsCharacterRate": "...",
"statsWeaponRate": "...",
```

對 4 個檔案各做一次：`app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_zh.arb`、`app_en.arb`。

- [ ] **Step 3：重新生成 l10n**

Run: `flutter gen-l10n`
Expected: 無 error；`lib/l10n/generated/app_localizations*.dart` 內已不含 `statsFiveStarRate` 等 getter。

- [ ] **Step 4：再次搜尋確認整個 `lib/` 已乾淨**

使用 Grep 工具，於整個 `lib/` 搜尋：

```
pattern: statsFiveStarRate|statsFourStarRate|statsThreeStarRate|statsCharacterRate|statsWeaponRate
```

Expected：no matches。

- [ ] **Step 5：跑 analyze 與 test**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: 全 PASS。

- [ ] **Step 6：commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/generated
git commit -m "chore(l10n): remove obsolete rate keys replaced by count/distribution"
```

---

## 驗收 Checklist（全部 Task 完成後）

- [ ] `flutter analyze` 乾淨
- [ ] `flutter test` 全 PASS
- [ ] 總覽頁 Row 1 stat card：標題=「件數」、副欄=「佔總抽 X.XX%」
- [ ] 總覽頁 Row 2 餅圖卡：標題「稀有度分布」「類型分布」，切片無文字，圖例顯示色塊+名稱+次數+率
- [ ] 卡池頁 Row 2 餅圖卡：同上
- [ ] 切換語言（zh-Hant / zh-Hans / en）後字串正常
- [ ] 空資料（無紀錄帳號）：餅圖顯示「無資料」、圖例不顯示
- [ ] `unknownCount = 0` 時類型圖例只顯示「角色」「武器」兩行
