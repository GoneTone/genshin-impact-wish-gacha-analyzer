# 綜合頁簡化 + 各卡池 5★ 件數圖表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除綜合頁的 StatCards / Pie / 橫向時間軸，改為「PageHeader → 各卡池 5★ 件數 Card → 5★ 時間軸 (TimelineVertical)」三段式。

**Architecture:** 新增 `BannerFiveStarBars` widget（水平 bar 列表，5 個卡池固定順序，bar 用 `Container + widthFactor` 模式自製，沿用既有 `BannerColors` 配色 + `computePity` / `computeWishStats` 計算）。`OverviewPage` 移除原本 Row 1 / Row 2 與相關 imports，僅留 PageHeader / 新 Card / TimelineVertical。

**Tech Stack:** Flutter / Dart / flutter_riverpod / Flutter i18n (`.arb` + `flutter gen-l10n`)。

**Spec：** `docs/superpowers/specs/2026-05-11-overview-banner-fivestar-chart-design.md`

---

## File Structure

**Create:**
- `lib/widgets/cards/banner_five_star_bars.dart` — 新元件，輸入 `Map<String, List<WishRecord>> banners` + `BannerColors`，渲染 5 row 水平 bar。
- `test/widgets/cards/banner_five_star_bars_test.dart` — 對應測試。

**Modify:**
- `lib/l10n/app_en.arb` — 加入 `bannerFiveStarCountTitle`、`bannerFiveStarPullsSinceLast`。
- `lib/l10n/app_zh.arb` — 同上（繁體文案）。
- `lib/l10n/app_zh_Hans.arb` — 同上（簡體文案）。
- `lib/l10n/app_zh_Hant.arb` — 同上（繁體文案，template-arb-file，需含 `@bannerFiveStarPullsSinceLast` 的 placeholders metadata）。
- `lib/pages/overview_page.dart` — 整頁改寫：移除 Row 1 / Row 2、插入新 Card、imports 縮減、timeline 標題改用 `timelineEntries.length`。

**Do NOT touch:**
- `lib/pages/banner_page.dart`（per-banner 頁面）
- `lib/widgets/cards/timeline_vertical.dart`
- 既有 `rarity_pie.dart` / `item_type_pie.dart` / `stat_card.dart` / `timeline_horizontal.dart` / `distribution_legend.dart`（仍由 banner_page 使用）

---

## Task 1: 新增 i18n keys 並重新生成 localization 檔

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`（template；含 metadata）
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Auto-regenerated: `lib/l10n/generated/app_localizations*.dart`

- [ ] **Step 1.1: 修改 `lib/l10n/app_zh_Hant.arb`（template）**

把檔案結尾的 `timelineCountFiveStar` 區塊（line 226-229）改成：

```json
  "timelineCountFiveStar": "5★ 時間軸 ({n})",
  "@timelineCountFiveStar": {
    "placeholders": { "n": { "type": "int" } }
  },

  "bannerFiveStarCountTitle": "各卡池 5★ 件數",
  "bannerFiveStarPullsSinceLast": "距上次 5★ {n} 抽",
  "@bannerFiveStarPullsSinceLast": {
    "placeholders": { "n": { "type": "int" } }
  }
}
```

注意：原本 `@timelineCountFiveStar` 區塊後是 `}` 結尾；要把它後面接 `,` 再加新 keys，最後再 `}`。

- [ ] **Step 1.2: 修改 `lib/l10n/app_zh.arb`**

同樣位置加入兩個 key（繁體文案，與 `app_zh_Hant.arb` 一致；**不**重複 metadata，因為 metadata 只放 template）：

```json
  "timelineCountFiveStar": "5★ 時間軸 ({n})",
  "@timelineCountFiveStar": {
    "placeholders": { "n": { "type": "int" } }
  },

  "bannerFiveStarCountTitle": "各卡池 5★ 件數",
  "bannerFiveStarPullsSinceLast": "距上次 5★ {n} 抽"
}
```

- [ ] **Step 1.3: 修改 `lib/l10n/app_zh_Hans.arb`**

簡體文案：

```json
  "timelineCountFiveStar": "5★ 时间轴 ({n})",
  "@timelineCountFiveStar": {
    "placeholders": { "n": { "type": "int" } }
  },

  "bannerFiveStarCountTitle": "各卡池 5★ 件数",
  "bannerFiveStarPullsSinceLast": "距上次 5★ {n} 抽"
}
```

- [ ] **Step 1.4: 修改 `lib/l10n/app_en.arb`**

英文文案：

```json
  "timelineCountFiveStar": "5★ Timeline ({n})",
  "@timelineCountFiveStar": {
    "placeholders": { "n": { "type": "int" } }
  },

  "bannerFiveStarCountTitle": "5★ count per banner",
  "bannerFiveStarPullsSinceLast": "{n} pulls since last 5★"
}
```

- [ ] **Step 1.5: 重新生成 localization 檔**

Run: `flutter gen-l10n`

Expected: 無錯誤輸出。`lib/l10n/generated/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` 三檔被更新，可以 grep 到新 getter：

Run: `grep -E "bannerFiveStarCountTitle|bannerFiveStarPullsSinceLast" lib/l10n/generated/app_localizations.dart`
Expected: 至少 4 行（兩 getter × 兩處：抽象 getter + 子類覆寫）。

不要單獨 commit — 在 Task 2 一起 commit。

---

## Task 2: 建立 `BannerFiveStarBars` widget + 測試（TDD）

**Files:**
- Create: `lib/widgets/cards/banner_five_star_bars.dart`
- Create: `test/widgets/cards/banner_five_star_bars_test.dart`

### Stage A: 建立測試骨架 + 「5 row 永遠存在」（red → green）

- [ ] **Step 2.1: 先寫 widget 骨架（empty stub），讓測試能 import**

Create `lib/widgets/cards/banner_five_star_bars.dart`：

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

class BannerFiveStarBars extends StatelessWidget {
  const BannerFiveStarBars({
    super.key,
    required this.banners,
    required this.colors,
  });

  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
```

- [ ] **Step 2.2: 寫測試 1「5 row 永遠存在」**

Create `test/widgets/cards/banner_five_star_bars_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_five_star_bars.dart';

WishRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'X',
  String itemType = '角色',
}) => WishRecord(
  id: id,
  uid: '100000000',
  gachaType: gachaType,
  name: name,
  itemType: itemType,
  kind: WishItemKind.fromItemType(itemType),
  rankType: rank,
  time: time,
  lang: 'zh-tw',
);

Widget _wrap(
  Widget Function(BuildContext ctx, BannerColors colors) build,
) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 800,
      height: 280,
      child: Builder(
        builder: (ctx) {
          final colors = BannerColors.fromTokens(Theme.of(ctx).gacha);
          return build(ctx, colors);
        },
      ),
    ),
  ),
);

void main() {
  testWidgets('empty banners → still renders 5 banner name rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            BannerFiveStarBars(banners: const {}, colors: colors),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerFiveStarBars)),
    )!;
    for (final t in gachaTypes) {
      expect(find.text(t.resolveName(l)), findsOneWidget);
    }
    // 5 row 中 4 個非新手池都顯示「暫無 5★」，新手池顯示「已結束」
    expect(find.text(l.pityNoFiveStar), findsNWidgets(4));
    expect(find.text(l.pityBeginnerEnded), findsOneWidget);
    // 件數全為 0；分隔點「·」出現 5 次
    expect(find.text('0'), findsNWidgets(5));
    expect(find.text('·'), findsNWidgets(5));
  });
}
```

- [ ] **Step 2.3: 跑測試確認 FAIL**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: FAIL — 找不到卡池名 Text。

- [ ] **Step 2.4: 在 widget 中實作 5 row 骨架**

Replace `lib/widgets/cards/banner_five_star_bars.dart`：

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

class BannerFiveStarBars extends StatelessWidget {
  const BannerFiveStarBars({
    super.key,
    required this.banners,
    required this.colors,
  });

  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    final rows = gachaTypes.map((type) {
      final records = banners[type.gachaType] ?? const <WishRecord>[];
      final fiveStarCount = computeWishStats(records).fiveStarCount;
      final isEnded = type.gachaType == '100';
      final String subtitle;
      if (isEnded) {
        subtitle = l.pityBeginnerEnded;
      } else if (fiveStarCount == 0) {
        subtitle = l.pityNoFiveStar;
      } else {
        final pity =
            computePity(records, threshold: type.fiveStarPity).current;
        subtitle = l.bannerFiveStarPullsSinceLast(pity);
      }
      return _BannerRow(
        name: type.resolveName(l),
        color: colors.colorFor(type.gachaType),
        fiveStarCount: fiveStarCount,
        subtitle: subtitle,
        ratio: 0.0, // ratio 在 Stage C 補
      );
    }).toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s),
          rows[i],
        ],
      ],
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({
    required this.name,
    required this.color,
    required this.fiveStarCount,
    required this.subtitle,
    required this.ratio,
  });

  final String name;
  final Color color;
  final int fiveStarCount;
  final String subtitle;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            name,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: _Bar(color: color, ratio: ratio, tokens: tokens),
        ),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: 156,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$fiveStarCount',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Text('·', style: TextStyle(color: tokens.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: tokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.ratio, required this.tokens});
  final Color color;
  final double ratio;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.55), color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2.5: 跑測試確認 PASS**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: PASS — 卡池名 + 4 「暫無 5★」 + 1 「已結束」 都找得到。

### Stage B: 件數與「距上次 5★」邏輯（red → green）

- [ ] **Step 2.6: 加測試 2「件數與 subtitle 正確」**

Append to `test/widgets/cards/banner_five_star_bars_test.dart` (before `void main()` close brace):

```dart
  testWidgets('renders 5★ count and "距上次 5★" subtitle correctly', (tester) async {
    // 301 角色：desc-by-time → [4★, 4★, 5★A] → 5★ count = 1, 距上次 5★ = 2
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      '301': [
        _r(id: '3', gachaType: '301', rank: 4, time: t0.add(const Duration(days: 3))),
        _r(id: '2', gachaType: '301', rank: 4, time: t0.add(const Duration(days: 2))),
        _r(id: '1', gachaType: '301', rank: 5, time: t0.add(const Duration(days: 1))),
      ],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            BannerFiveStarBars(banners: banners, colors: colors),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerFiveStarBars)),
    )!;
    // 件數 = 1 出現一次（其他卡池 0 件）
    expect(find.text('1'), findsOneWidget);
    expect(find.text(l.bannerFiveStarPullsSinceLast(2)), findsOneWidget);
  });

  testWidgets('100 (beginner) → subtitle always "已結束" even with 5★ records', (
    tester,
  ) async {
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      '100': [
        _r(id: 'b1', gachaType: '100', rank: 5, time: t0),
      ],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            BannerFiveStarBars(banners: banners, colors: colors),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(BannerFiveStarBars)),
    )!;
    // 新手池件數 = 1；subtitle 仍為「已結束」而非「暫無 5★」
    expect(find.text('1'), findsOneWidget);
    expect(find.text(l.pityBeginnerEnded), findsOneWidget);
    // 其他 4 個卡池仍是「暫無 5★」（不會因為 100 有件數而改變）
    expect(find.text(l.pityNoFiveStar), findsNWidgets(4));
  });
```

- [ ] **Step 2.7: 跑測試確認 PASS（Stage A 實作已含此邏輯）**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: PASS — 3 個測試全綠。如果失敗，仔細檢查 RichText 字串組成。

### Stage C: bar 比例（red → green）

- [ ] **Step 2.8: 加測試 3「bar 比例 = fiveStarCount / max」**

Append to `test/widgets/cards/banner_five_star_bars_test.dart`:

```dart
  testWidgets(
    'bar widthFactor = fiveStarCount / max(fiveStarCount across banners)',
    (tester) async {
      final t0 = DateTime(2025, 1, 1);
      // 301: 4 個 5★；302: 1 個 5★；其他 0
      final banners = <String, List<WishRecord>>{
        '301': [
          for (var i = 0; i < 4; i++)
            _r(
              id: '301-$i',
              gachaType: '301',
              rank: 5,
              time: t0.add(Duration(days: i)),
            ),
        ],
        '302': [
          _r(id: '302-0', gachaType: '302', rank: 5, time: t0),
        ],
      };
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) =>
              BannerFiveStarBars(banners: banners, colors: colors),
        ),
      );
      // 找所有 ClipRRect → Align.widthFactor
      final aligns = tester
          .widgetList<Align>(
            find.descendant(
              of: find.byType(BannerFiveStarBars),
              matching: find.byType(Align),
            ),
          )
          .where((a) => a.widthFactor != null)
          .toList();
      expect(aligns.length, 5);
      // 第一個（301）= 1.0；第二個（302）= 0.25；其他 = 0.0
      expect(aligns[0].widthFactor, 1.0);
      expect(aligns[1].widthFactor, closeTo(0.25, 1e-6));
      expect(aligns[2].widthFactor, 0.0);
      expect(aligns[3].widthFactor, 0.0);
      expect(aligns[4].widthFactor, 0.0);
    },
  );
```

- [ ] **Step 2.9: 跑測試確認 FAIL**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: FAIL — bar widthFactor 全為 0（因為 Stage A 實作 `ratio: 0.0` 是 placeholder）。

- [ ] **Step 2.10: 補 bar 比例邏輯**

修改 `lib/widgets/cards/banner_five_star_bars.dart` 中 `build` 方法的兩處：

(a) 先計算 max：把 `final rows = gachaTypes.map((type) { … }).toList(...)` 之前加：

```dart
    final counts = <String, int>{
      for (final t in gachaTypes)
        t.gachaType: computeWishStats(banners[t.gachaType] ?? const [])
            .fiveStarCount,
    };
    final maxCount =
        counts.values.fold<int>(0, (m, v) => v > m ? v : m);
```

(b) 把原本 row 內 `computeWishStats(records).fiveStarCount` 改用 `counts[type.gachaType]!`，並把 `ratio: 0.0` 改為：

```dart
        ratio: maxCount == 0 ? 0.0 : fiveStarCount / maxCount,
```

最終 build 方法看起來：

```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final counts = <String, int>{
      for (final t in gachaTypes)
        t.gachaType: computeWishStats(banners[t.gachaType] ?? const [])
            .fiveStarCount,
    };
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    final rows = gachaTypes.map((type) {
      final records = banners[type.gachaType] ?? const <WishRecord>[];
      final fiveStarCount = counts[type.gachaType]!;
      final isEnded = type.gachaType == '100';
      final String subtitle;
      if (isEnded) {
        subtitle = l.pityBeginnerEnded;
      } else if (fiveStarCount == 0) {
        subtitle = l.pityNoFiveStar;
      } else {
        final pity =
            computePity(records, threshold: type.fiveStarPity).current;
        subtitle = l.bannerFiveStarPullsSinceLast(pity);
      }
      return _BannerRow(
        name: type.resolveName(l),
        color: colors.colorFor(type.gachaType),
        fiveStarCount: fiveStarCount,
        subtitle: subtitle,
        ratio: maxCount == 0 ? 0.0 : fiveStarCount / maxCount,
      );
    }).toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s),
          rows[i],
        ],
      ],
    );
  }
```

注意 `tokens` / `theme` 變數已不需要在最外層的 `build` 中（_BannerRow 內部自己取），可從外層 build 移除。如果 Stage A 留下未用變數，這次清掉。

- [ ] **Step 2.11: 跑測試確認 PASS**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: PASS — 全部測試綠。

### Stage D: 顏色（red → green）

- [ ] **Step 2.12: 加測試 4「bar 顏色 = BannerColors.colorFor」**

Append to `test/widgets/cards/banner_five_star_bars_test.dart`:

```dart
  testWidgets('bar color matches BannerColors.colorFor(gachaType)', (tester) async {
    final t0 = DateTime(2025, 1, 1);
    final banners = <String, List<WishRecord>>{
      for (final t in gachaTypes)
        t.gachaType: [_r(id: '${t.gachaType}-0', gachaType: t.gachaType, rank: 5, time: t0)],
    };
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            BannerFiveStarBars(banners: banners, colors: colors),
      ),
    );
    final colors = BannerColors.fromTokens(
      Theme.of(tester.element(find.byType(BannerFiveStarBars))).gacha,
    );
    // 找 5 個 bar 的 Container with gradient
    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BannerFiveStarBars),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) => (c.decoration as BoxDecoration?)?.gradient is LinearGradient,
        )
        .toList();
    expect(containers.length, gachaTypes.length);
    for (var i = 0; i < gachaTypes.length; i++) {
      final gradient =
          (containers[i].decoration as BoxDecoration).gradient as LinearGradient;
      // 第二個顏色 stop 是 accent（未透明化）
      expect(gradient.colors.last, colors.colorFor(gachaTypes[i].gachaType));
    }
  });
```

- [ ] **Step 2.13: 跑測試確認 PASS（Stage A 實作已含此邏輯）**

Run: `flutter test test/widgets/cards/banner_five_star_bars_test.dart`
Expected: PASS — 全部 5 個測試綠。

### Stage E: 提交前檢查 + Commit

- [ ] **Step 2.14: 格式化**

Run: `dart format lib/ test/`
Expected: 可能會 reformat 一些行。確認沒有錯誤輸出。

- [ ] **Step 2.15: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`。如果有 unused import / unused variable，回去清掉。

- [ ] **Step 2.16: 跑完整測試**

Run: `flutter test`
Expected: `All tests passed!`。

- [ ] **Step 2.17: Commit**

```bash
git add lib/l10n/ lib/widgets/cards/banner_five_star_bars.dart test/widgets/cards/banner_five_star_bars_test.dart
git commit -m "feat(overview): add BannerFiveStarBars widget for per-banner 5★ counts"
```

注意：`lib/l10n/generated/` 應該也被加進去（如果是 tracked 的話）；用 `git status` 確認。

---

## Task 3: 改寫 `OverviewPage`

**Files:**
- Modify: `lib/pages/overview_page.dart`

### Stage A: 改寫 build 方法

- [ ] **Step 3.1: 整個替換 `lib/pages/overview_page.dart` 內容**

Replace 整檔為：

```dart
// lib/pages/overview_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_five_star_bars.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final activeData = state.activeData;

    if (state.isBootstrapping) {
      return const LoadingState();
    }
    if (activeData == null) {
      return EmptyState.noSync(context);
    }
    final bannerColors = BannerColors.fromTokens(tokens);
    final timelineEntries = buildTimelineEntriesAcrossBanners(
      activeData.banners,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: l.pageOverviewTitle),

          ChartCard(
            title: l.bannerFiveStarCountTitle,
            height: 280,
            chart: BannerFiveStarBars(
              banners: activeData.banners,
              colors: bannerColors,
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          Text(
            l.timelineCountFiveStar(timelineEntries.length),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.s),
          TimelineVertical(
            entries: timelineEntries,
            colors: bannerColors,
            nowPulls: pullsSinceLastFiveStarAcrossBanners(activeData.banners),
            isAcrossBanners: true,
          ),
        ],
      ),
    );
  }
}
```

被移除的 imports（與原檔對比）：
- `services/wish_stats.dart`
- `widgets/cards/stat_card.dart`
- `widgets/cards/timeline_horizontal.dart`
- `widgets/distribution_legend.dart`
- `widgets/item_type_pie.dart`
- `widgets/rarity_pie.dart`

新增 import：
- `widgets/cards/banner_five_star_bars.dart`

### Stage B: 提交前檢查 + Commit

- [ ] **Step 3.2: 格式化**

Run: `dart format lib/ test/`
Expected: 無錯誤。

- [ ] **Step 3.3: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`。

- [ ] **Step 3.4: 跑完整測試**

Run: `flutter test`
Expected: `All tests passed!`。

- [ ] **Step 3.5: 手動驗證（UI smoke test）**

如方便，跑 `flutter run` 進入綜合頁，確認：
- 頁面只有三段：PageHeader / 各卡池 5★ 件數 Card / 5★ 時間軸。
- 5 row 卡池順序為 301 → 302 → 500 → 200 → 100。
- 新手池（100）右欄顯示「已結束」；無 5★ 紀錄的卡池顯示「暫無 5★」。
- 切換語言（繁/簡/英）標題與 subtitle 都翻譯正確。
- 視窗縮放在 360–1400 寬都不破版。

若不便手動跑，**註明在 commit 訊息**或回報，由 reviewer 跑。

- [ ] **Step 3.6: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "refactor(overview): replace stats/pie/horizontal-timeline with BannerFiveStarBars"
```

---

## Self-Review Checklist（writer fills before handing off）

- [x] **Spec coverage**：兩大目標（簡化版面、新元件）→ Task 3、Task 2 對應；六項測試 → Stage A/B/C/D 涵蓋；i18n 新 key → Task 1。
- [x] **Placeholder scan**：所有 step 都附有具體 code 或 command。
- [x] **Type consistency**：`BannerFiveStarBars({banners, colors})` 在 Task 2 定義、Task 3 呼叫一致。`_BannerRow` 接 `(name, color, fiveStarCount, subtitle, ratio)` 與 Stage A/C 一致。
- [x] **邊界覆蓋**：empty banners / beginner pool / all-zero / 某 banner null 都在測試或 widget 邏輯中處理。

---

## Execution Notes

- **不**手動編輯 `lib/l10n/generated/*`；只改 `.arb` 並跑 `flutter gen-l10n`。
- 任何步驟 fail 就停下來修，不要 `--no-verify` 跳 hook。
- 兩個 commit 順序：先 Task 2（widget + i18n）再 Task 3（page）— 因為 page 依賴 widget，順序顛倒會有暫時編譯錯誤。
