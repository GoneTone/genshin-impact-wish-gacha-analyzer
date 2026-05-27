# 時間軸重新設計 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 BannerPage Row 2 的 `TimelineCard`、OverviewPage Row 2 的 `_LatestFiveStar`、OverviewPage 下方的 `FiveStarList` 三處,統一重新設計為兩個時間軸 widget:`TimelineHorizontal`(用於兩處 Row 2)與 `TimelineVertical`(用於 Overview 下方)。

**Architecture:** 資料層收斂為 `lib/services/timeline_entries.dart` 內的純函式;配色抽出為 `lib/widgets/banner_colors.dart` 的 `BannerColors`;A 與 B 兩個 widget 各自獨立、不強行共用排版邏輯;新增 4 個 i18n key,移除 1 個。

**Tech Stack:** Flutter 3.x、Dart 3、Riverpod(沿用)、`intl`(已在 pubspec,用於 `DateFormat`)、`flutter_test`(widget test)。

**Spec:** `docs/superpowers/specs/2026-05-11-timeline-redesign-design.md`

**Convention 提醒:** 提交前依序執行(專案 CLAUDE.md 要求):
1. `dart format lib/ test/`
2. `flutter analyze` → 必須 `No issues found!`
3. `flutter test` → 必須 `All tests passed!`

格式化**不要對 `.` 跑**(會動到 `rust_builder/` vendored 程式碼)。

---

## Task 1: 資料層 — `TimelineEntry` model + 純函式

**Files:**
- Create: `lib/services/timeline_entries.dart`
- Create: `test/services/timeline_entries_test.dart`

這個檔案是後續所有 widget 的依賴基礎。一次 TDD 把 4 個函式寫完。

### Step 1: Write failing tests

- [ ] **建立 `test/services/timeline_entries_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

WishRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'x',
}) => WishRecord(
  id: id,
  uid: '1',
  gachaType: gachaType,
  name: name,
  itemType: '角色',
  kind: WishItemKind.character,
  rankType: rank,
  time: time,
  lang: 'zh-tw',
);

void main() {
  group('buildTimelineEntries', () {
    test('empty records → empty list', () {
      expect(buildTimelineEntries(const []), isEmpty);
    });

    test('records without 5★ → empty list', () {
      final records = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        _r(id: '2', gachaType: '301', rank: 4, time: DateTime(2025, 1, 2)),
      ];
      // desc by time as input
      expect(buildTimelineEntries(records.reversed.toList()), isEmpty);
    });

    test('computes pullsSincePrev counting from start', () {
      // chronological asc: r1(3★), r2(3★), r3(5★ A), r4(3★), r5(5★ B)
      // expected: entries desc by time, B with pullsSincePrev=2, A with pullsSincePrev=3
      final asc = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        _r(id: '2', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '3', gachaType: '301', rank: 5, name: 'A', time: DateTime(2025, 1, 3)),
        _r(id: '4', gachaType: '301', rank: 3, time: DateTime(2025, 1, 4)),
        _r(id: '5', gachaType: '301', rank: 5, name: 'B', time: DateTime(2025, 1, 5)),
      ];
      final desc = asc.reversed.toList(); // input must be desc
      final result = buildTimelineEntries(desc);
      expect(result, hasLength(2));
      expect(result[0].name, 'B');
      expect(result[0].pullsSincePrev, 2);
      expect(result[1].name, 'A');
      expect(result[1].pullsSincePrev, 3);
    });
  });

  group('buildTimelineEntriesAcrossBanners', () {
    test('merges multiple banners and sorts by time desc', () {
      final banners = {
        '301': [
          _r(id: 'c2', gachaType: '301', rank: 5, name: 'CharB', time: DateTime(2025, 3, 1)),
          _r(id: 'c1', gachaType: '301', rank: 5, name: 'CharA', time: DateTime(2025, 1, 1)),
        ],
        '302': [
          _r(id: 'w1', gachaType: '302', rank: 5, name: 'WepA', time: DateTime(2025, 2, 1)),
        ],
      };
      final result = buildTimelineEntriesAcrossBanners(banners);
      expect(result.map((e) => e.name).toList(), ['CharB', 'WepA', 'CharA']);
    });

    test('per-pool pullsSincePrev preserved (not recomputed across pools)', () {
      // Pool A: 1 record (5★) → pullsSincePrev = 1
      // Pool B: 1 record (5★) → pullsSincePrev = 1
      final banners = {
        '301': [_r(id: 'a', gachaType: '301', rank: 5, time: DateTime(2025, 2, 1))],
        '302': [_r(id: 'b', gachaType: '302', rank: 5, time: DateTime(2025, 1, 1))],
      };
      final result = buildTimelineEntriesAcrossBanners(banners);
      expect(result.every((e) => e.pullsSincePrev == 1), isTrue);
    });
  });

  group('pullsSinceLastFiveStar', () {
    test('no 5★ → returns total records count', () {
      final records = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '2', gachaType: '301', rank: 4, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastFiveStar(records), 2);
    });

    test('counts records newer than latest 5★', () {
      // desc input: r3(3★), r2(3★), r1(5★) → 2 records since 5★
      final records = [
        _r(id: '3', gachaType: '301', rank: 3, time: DateTime(2025, 1, 3)),
        _r(id: '2', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '1', gachaType: '301', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastFiveStar(records), 2);
    });

    test('empty records → 0', () {
      expect(pullsSinceLastFiveStar(const []), 0);
    });
  });

  group('pullsSinceLastFiveStarAcrossBanners', () {
    test('counts across all pools after cross-pool latest 5★', () {
      // Latest 5★ across pools is at 2025-02-15 (pool 302)
      // After it: pool 301 has 1 record (2025-03-01), pool 302 has 0 records after.
      // Total cross-pool: 1
      final banners = {
        '301': [
          _r(id: 'c3', gachaType: '301', rank: 3, time: DateTime(2025, 3, 1)),
          _r(id: 'c2', gachaType: '301', rank: 5, time: DateTime(2025, 2, 1)),
          _r(id: 'c1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        ],
        '302': [
          _r(id: 'w1', gachaType: '302', rank: 5, time: DateTime(2025, 2, 15)),
        ],
      };
      expect(pullsSinceLastFiveStarAcrossBanners(banners), 1);
    });

    test('no 5★ anywhere → total cross-pool record count', () {
      final banners = {
        '301': [_r(id: 'a', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1))],
        '302': [
          _r(id: 'b', gachaType: '302', rank: 4, time: DateTime(2025, 1, 1)),
          _r(id: 'c', gachaType: '302', rank: 3, time: DateTime(2025, 1, 2)),
        ],
      };
      expect(pullsSinceLastFiveStarAcrossBanners(banners), 3);
    });

    test('empty banners → 0', () {
      expect(pullsSinceLastFiveStarAcrossBanners(const {}), 0);
    });
  });
}
```

### Step 2: Run tests to verify they fail

- [ ] **執行測試,確認失敗**

```
flutter test test/services/timeline_entries_test.dart
```
預期:compile error(`timeline_entries.dart` 不存在 / 函式未定義)。

### Step 3: Implement the data layer

- [ ] **建立 `lib/services/timeline_entries.dart`**

```dart
import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

/// 時間軸條目:一筆 5★ 紀錄 + 距該卡池上一筆 5★ 的抽數。
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });

  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

/// 從單一卡池 desc-by-time 排序的 records,萃取 5★ 條目並計算每筆的 pullsSincePrev。
/// 回傳結果依時間 desc(最新在前)。
List<TimelineEntry> buildTimelineEntries(List<WishRecord> records) {
  final asc = records.reversed.toList(growable: false);
  final out = <TimelineEntry>[];
  var pull = 0;
  for (final r in asc) {
    pull++;
    if (r.rankType == 5) {
      out.add(TimelineEntry(
        name: r.name,
        gachaType: r.gachaType,
        time: r.time,
        pullsSincePrev: pull,
      ));
      pull = 0;
    }
  }
  return out.reversed.toList(growable: false);
}

/// 跨卡池:合併所有卡池的 entries,依時間 desc 排序。
/// 每筆 entry 的 pullsSincePrev 仍以「該 entry 所屬卡池的上一筆 5★」為基準,
/// 不是「跨卡池上一筆」 — 保底計算永遠 per-pool。
List<TimelineEntry> buildTimelineEntriesAcrossBanners(
  Map<String, List<WishRecord>> banners,
) {
  final out = <TimelineEntry>[];
  for (final records in banners.values) {
    out.addAll(buildTimelineEntries(records));
  }
  out.sort((a, b) => b.time.compareTo(a.time));
  return out;
}

/// 從 desc 排序的 records 計算「最後一個 5★ 之後又抽了多少抽」。
/// 若無任何 5★,回傳 records.length(視為從頭累計)。
int pullsSinceLastFiveStar(List<WishRecord> records) {
  var count = 0;
  for (final r in records) {
    if (r.rankType == 5) return count;
    count++;
  }
  return count;
}

/// 跨卡池:從 banners map 找到跨卡池最新 5★,計算其後跨全部卡池 record 總數。
/// 若所有卡池皆無 5★,回傳全部卡池 record 數總和。
int pullsSinceLastFiveStarAcrossBanners(
  Map<String, List<WishRecord>> banners,
) {
  DateTime? latest;
  for (final records in banners.values) {
    for (final r in records) {
      if (r.rankType == 5) {
        if (latest == null || r.time.isAfter(latest)) {
          latest = r.time;
        }
        break; // records 已 desc,該卡池的第一筆 5★ 就是該池最新 5★
      }
    }
  }
  if (latest == null) {
    var total = 0;
    for (final records in banners.values) {
      total += records.length;
    }
    return total;
  }
  var count = 0;
  for (final records in banners.values) {
    for (final r in records) {
      if (r.time.isAfter(latest)) count++;
    }
  }
  return count;
}
```

### Step 4: Run tests to verify they pass

- [ ] **執行測試**

```
flutter test test/services/timeline_entries_test.dart
```
預期:`All tests passed!`(8 tests)。

### Step 5: Format + analyze + commit

- [ ] **格式化、分析、提交**

```
dart format lib/services/timeline_entries.dart test/services/timeline_entries_test.dart
flutter analyze
```
預期 analyze:`No issues found!`

```
git add lib/services/timeline_entries.dart test/services/timeline_entries_test.dart
git commit -m "feat(services): add timeline_entries data layer with TimelineEntry + 4 pure helpers"
```

---

## Task 2: i18n — 新增字串、移除舊字串、重產 generated

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Regenerated: `lib/l10n/generated/*.dart`(由 `flutter gen-l10n` 自動)

### Step 1: Remove `timelineLatestEntry` from all 4 arb files

- [ ] **在四個 .arb 檔中各自移除以下兩段**(`timelineLatestEntry` key + 其 `@timelineLatestEntry` metadata)

範例(zh_Hant,行 210-216):
```json
  "timelineLatestEntry": "最新：{name}（{n} 抽）",
  "@timelineLatestEntry": {
    "placeholders": {
      "name": { "type": "String" },
      "n": { "type": "int" }
    }
  }
```
刪除這段(連同上一行尾的逗號處理)。其他三個 .arb 檔做相同處理。

### Step 2: Add 4 new i18n keys

- [ ] **在 `app_zh_Hant.arb` 加入**(放在 `timelineSinceLast` 之後,保持 timeline 相關字串聚集)

```json
  "timelineNowLabel": "現在",
  "timelineNowPulls": "已 {n} 抽",
  "@timelineNowPulls": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceLast": "距上次 5★ {n} 抽",
  "@timelineNowSinceLast": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceCrossPool": "從上次 5★ 至今 {n} 抽",
  "@timelineNowSinceCrossPool": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineMonthLabel": "{year} / {month}",
  "@timelineMonthLabel": {
    "placeholders": {
      "year": { "type": "String" },
      "month": { "type": "String" }
    }
  },
```

- [ ] **在 `app_zh_Hans.arb` 加入相同的 key(value 用簡體)**

```json
  "timelineNowLabel": "现在",
  "timelineNowPulls": "已 {n} 抽",
  "@timelineNowPulls": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceLast": "距上次 5★ {n} 抽",
  "@timelineNowSinceLast": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceCrossPool": "从上次 5★ 至今 {n} 抽",
  "@timelineNowSinceCrossPool": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineMonthLabel": "{year} / {month}",
  "@timelineMonthLabel": {
    "placeholders": {
      "year": { "type": "String" },
      "month": { "type": "String" }
    }
  },
```

- [ ] **在 `app_en.arb` 加入**

```json
  "timelineNowLabel": "Now",
  "timelineNowPulls": "{n} pulls",
  "@timelineNowPulls": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceLast": "{n} pulls since last 5★",
  "@timelineNowSinceLast": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineNowSinceCrossPool": "{n} pulls since last 5★ across banners",
  "@timelineNowSinceCrossPool": {
    "placeholders": { "n": { "type": "int" } }
  },
  "timelineMonthLabel": "{month} / {year}",
  "@timelineMonthLabel": {
    "placeholders": {
      "year": { "type": "String" },
      "month": { "type": "String" }
    }
  },
```

- [ ] **`app_zh.arb`**:若該檔是 zh-Hant 或 zh-Hans 的 alias / fallback,加入與其相符的版本。先 `head -3 app_zh.arb` 看 `@@locale` 標籤再決定用繁/簡內容。若標籤是 `zh`(無變體),使用簡體版本以符合一般 zh fallback 慣例。

### Step 3: Regenerate localizations

- [ ] **執行 flutter gen-l10n**

```
flutter gen-l10n
```
預期:無錯誤,`lib/l10n/generated/app_localizations*.dart` 被更新。

### Step 4: Verify analyze

- [ ] **靜態分析**

```
flutter analyze
```

預期:會在 `overview_page.dart` 與 `timeline_card.dart` 報「`timelineLatestEntry` 不存在」之類錯誤 — **預期之內**,因為這兩個檔還未被 Task 6 / 7 / 10 / 11 修改。先記下,**這個 commit 暫時不要求 analyze 全綠**。

### Step 5: Commit(允許 analyze 暫時飄紅)

- [ ] **commit i18n 變更**

```
dart format lib/l10n/
git add lib/l10n/
git commit -m "i18n: add timeline now/month keys, remove timelineLatestEntry"
```

> 註:此 commit 後到 Task 11 完成前,專案 analyze 會暫時 fail。Task 11 完成後即恢復。如果你想保持每個 commit 都 analyze 全綠,可以把 Task 2 跟 Task 10 + 11 合併執行不分開 commit,但失去 bite-sized 顆粒。建議仍分開,並在最後 Task 13 統一驗證。

---

## Task 3: 共用配色 `BannerColors`

**Files:**
- Create: `lib/widgets/banner_colors.dart`

從現有 `lib/widgets/data/five_star_list.dart:9-33` 的 `FiveStarListColors` 搬出,改名 `BannerColors`,並加 `fromTokens` factory。

### Step 1: Create the file

- [ ] **建立 `lib/widgets/banner_colors.dart`**

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 卡池配色表,給 Timeline 系列 widget 共用。
@immutable
class BannerColors {
  const BannerColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.fallback,
  });

  /// 從 [GachaTokens] 推導預設配色;
  /// 邏輯與原 `FiveStarListColors` 一致。
  factory BannerColors.fromTokens(GachaTokens tokens) => BannerColors(
    character: tokens.character,
    weapon: tokens.weapon,
    chronicled: tokens.accentPrimary,
    standard: tokens.threeStar,
    beginner: tokens.textMuted,
    fallback: tokens.textMuted,
  );

  final Color character;
  final Color weapon;
  final Color chronicled;
  final Color standard;
  final Color beginner;
  final Color fallback;

  Color colorFor(String gachaType) => switch (gachaType) {
    '301' => character,
    '302' => weapon,
    '500' => chronicled,
    '200' => standard,
    '100' => beginner,
    _ => fallback,
  };
}
```

### Step 2: Format + analyze

- [ ] **格式化與分析**

```
dart format lib/widgets/banner_colors.dart
flutter analyze
```
預期:`No issues found!`(就此檔而言;i18n 引發的舊有飄紅仍會在 — 後續會修)

### Step 3: Commit

- [ ] **提交**

```
git add lib/widgets/banner_colors.dart
git commit -m "feat(widgets): extract BannerColors as shared banner color palette"
```

---

## Task 4: `TimelineHorizontal` widget(視覺隱喻 A · 變體 1)

**Files:**
- Create: `lib/widgets/cards/timeline_horizontal.dart`
- Create: `test/widgets/cards/timeline_horizontal_test.dart`

### Step 1: Write failing widget tests

- [ ] **建立 `test/widgets/cards/timeline_horizontal_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(name: name, gachaType: gachaType, time: time, pullsSincePrev: pulls);

Widget _wrap(Widget Function(BuildContext ctx, BannerColors colors) build) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 1000,
      height: 160,
      child: Builder(builder: (ctx) {
        final colors = BannerColors.fromTokens(Theme.of(ctx).gacha);
        return build(ctx, colors);
      }),
    ),
  ),
);

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) =>
        TimelineHorizontal(entries: const [], colors: colors)));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineHorizontal)))!;
    expect(find.text(l.timelineNoRecords), findsOneWidget);
  });

  testWidgets('renders one column per entry', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) => TimelineHorizontal(
          entries: [
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
        )));
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets('nowPulls != null → adds Now column at the leftmost', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) => TimelineHorizontal(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 28,
        )));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineHorizontal)))!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNowPulls(28)), findsOneWidget);
  });

  testWidgets('empty + nowPulls != null → renders only the Now column', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) =>
        TimelineHorizontal(entries: const [], colors: colors, nowPulls: 5)));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineHorizontal)))!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNoRecords), findsNothing);
  });
}
```

### Step 2: Run tests to verify they fail

- [ ] **執行**

```
flutter test test/widgets/cards/timeline_horizontal_test.dart
```
預期:compile error(`timeline_horizontal.dart` 不存在)。

### Step 3: Implement `TimelineHorizontal`

- [ ] **建立 `lib/widgets/cards/timeline_horizontal.dart`**

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

const double _colWidth = 90;
const double _nodeSize = 14;
const double _haloSize = 22;

/// 橫向時間軸(視覺隱喻 A · 變體 1):
/// - 左 → 右 = 新 → 舊
/// - 每欄 3 行:名稱 / 節點(軸線居中) / `MM/dd · N抽`
/// - `nowPulls != null` 時最左欄為「現在」(中空節點 + 虛線 halo)
class TimelineHorizontal extends StatelessWidget {
  const TimelineHorizontal({
    super.key,
    required this.entries,
    required this.colors,
    this.nowPulls,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    if (entries.isEmpty && nowPulls == null) {
      return Center(
        child: Text(
          l.timelineNoRecords,
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    // LayoutBuilder 取得父層高度,確保 Stack 有明確高度可以讓背景軸線 Positioned.fill 正確繪製
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: constraints.maxHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 背景軸線:水平中央一條 2px 線,左右留 AppSpacing.s 內距
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                    child: Center(
                      child: Container(
                        height: 2,
                        color: tokens.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                // 節點欄:橫向 Row,垂直置中於 Stack
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (nowPulls != null)
                      _NowColumn(nowPulls: nowPulls!, tokens: tokens, l: l),
                    for (final entry in entries)
                      _EntryColumn(entry: entry, colors: colors, tokens: tokens),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EntryColumn extends StatelessWidget {
  const _EntryColumn({required this.entry, required this.colors, required this.tokens});
  final TimelineEntry entry;
  final BannerColors colors;
  final GachaTokens tokens;

  String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final l = AppLocalizations.of(context)!;
    return SizedBox(
      width: _colWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Node(color: accent, tokens: tokens),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatShortDate(entry.time)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _NowColumn extends StatelessWidget {
  const _NowColumn({required this.nowPulls, required this.tokens, required this.l});
  final int nowPulls;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _colWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l.timelineNowLabel,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.accentPrimary, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Node(color: tokens.accentPrimary, tokens: tokens, hollow: true),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l.timelineNowPulls(nowPulls),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _Node extends StatelessWidget {
  const _Node({required this.color, required this.tokens, this.hollow = false});
  final Color color;
  final GachaTokens tokens;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _haloSize,
      height: _haloSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? tokens.surfaceCard : color,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}
```

### Step 4: Run widget tests to verify they pass

- [ ] **執行**

```
flutter test test/widgets/cards/timeline_horizontal_test.dart
```
預期:`All tests passed!`(4 tests)。

### Step 5: Format + analyze + commit

- [ ] **格式化、分析、提交**

```
dart format lib/widgets/cards/timeline_horizontal.dart test/widgets/cards/timeline_horizontal_test.dart
flutter analyze lib/widgets/cards/timeline_horizontal.dart test/widgets/cards/timeline_horizontal_test.dart
```
預期:這兩個檔無 issue(專案級 `flutter analyze` 仍會因 Task 2 留下的 timelineLatestEntry 飄紅,先忽略)。

```
git add lib/widgets/cards/timeline_horizontal.dart test/widgets/cards/timeline_horizontal_test.dart
git commit -m "feat(widgets): add TimelineHorizontal with axis line, nodes, and Now marker"
```

---

## Task 5: `TimelineVertical` widget(視覺隱喻 B · 月份分組 + 連續軸線)

**Files:**
- Create: `lib/widgets/cards/timeline_vertical.dart`
- Create: `test/widgets/cards/timeline_vertical_test.dart`

### Step 1: Write failing widget tests

- [ ] **建立 `test/widgets/cards/timeline_vertical_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(name: name, gachaType: gachaType, time: time, pullsSincePrev: pulls);

Widget _wrap(Widget Function(BuildContext, BannerColors) build) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(builder: (ctx) {
      final colors = BannerColors.fromTokens(Theme.of(ctx).gacha);
      return SizedBox(width: 600, child: build(ctx, colors));
    }),
  ),
);

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) =>
        TimelineVertical(entries: const [], colors: colors)));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineVertical)))!;
    expect(find.text(l.timelineNoRecords), findsOneWidget);
  });

  testWidgets('renders entries with month tag per month group', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) => TimelineVertical(
          entries: [
            _e('娜維婭', '301', 62, DateTime(2025, 4, 19)),
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
        )));
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;
    // 2 個月份(2025/04 與 2025/03),所以 month tag 應該出現 2 次
    expect(find.text(l.timelineMonthLabel('2025', '04')), findsOneWidget);
    expect(find.text(l.timelineMonthLabel('2025', '03')), findsOneWidget);
    expect(find.text('娜維婭'), findsOneWidget);
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets('nowPulls + isAcrossBanners=true → top row shows cross-pool i18n', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) => TimelineVertical(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 12,
          isAcrossBanners: true,
        )));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineVertical)))!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNowSinceCrossPool(12)), findsOneWidget);
    expect(find.text(l.timelineNowSinceLast(12)), findsNothing);
  });

  testWidgets('nowPulls + isAcrossBanners=false → top row shows single-pool i18n', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) => TimelineVertical(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 28,
        )));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineVertical)))!;
    expect(find.text(l.timelineNowSinceLast(28)), findsOneWidget);
  });

  testWidgets('empty + nowPulls → renders only Now row, no NoRecords', (tester) async {
    await tester.pumpWidget(_wrap((ctx, colors) =>
        TimelineVertical(entries: const [], colors: colors, nowPulls: 5)));
    final l = AppLocalizations.of(tester.element(find.byType(TimelineVertical)))!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNoRecords), findsNothing);
  });
}
```

### Step 2: Run tests to verify they fail

- [ ] **執行**

```
flutter test test/widgets/cards/timeline_vertical_test.dart
```
預期:compile error。

### Step 3: Implement `TimelineVertical`

- [ ] **建立 `lib/widgets/cards/timeline_vertical.dart`**

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

const double _monthColumnWidth = 80;
const double _nodeSize = 14;
const double _haloSize = 22;
const double _railLeft = _monthColumnWidth + (_haloSize / 2);

/// 直向時間軸(視覺隱喻 B):
/// - 上 → 下 = 新 → 舊
/// - 軸線一條連續貫穿;月份標籤貼於軸線左外側(獨立左欄,不打斷軸線)
/// - `nowPulls != null` 時最頂端為「現在」row;`isAcrossBanners` 決定 i18n 文案
class TimelineVertical extends StatelessWidget {
  const TimelineVertical({
    super.key,
    required this.entries,
    required this.colors,
    this.nowPulls,
    this.isAcrossBanners = false,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;
  final bool isAcrossBanners;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    final container = (Widget child) => Container(
          decoration: BoxDecoration(
            color: tokens.surfaceCard,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.l,
            horizontal: AppSpacing.l,
          ),
          child: child,
        );

    if (entries.isEmpty && nowPulls == null) {
      return container(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              l.timelineNoRecords,
              style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
            ),
          ),
        ),
      );
    }

    // 計算每個 entry 是否為月份分組首 row
    final monthFlag = <bool>[];
    int? prevYearMonth;
    for (final entry in entries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthFlag.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    return container(
      Stack(
        children: [
          // 背景軸線(從容器內邊距上緣到下緣)
          Positioned(
            left: _railLeft,
            top: 0,
            bottom: 0,
            width: 2,
            child: Container(color: tokens.textMuted.withValues(alpha: 0.3)),
          ),
          // 前景:Column of rows
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nowPulls != null)
                _NowRow(
                  nowPulls: nowPulls!,
                  isAcrossBanners: isAcrossBanners,
                  tokens: tokens,
                  l: l,
                ),
              for (var i = 0; i < entries.length; i++)
                _EntryRow(
                  entry: entries[i],
                  showMonthTag: monthFlag[i],
                  colors: colors,
                  tokens: tokens,
                  l: l,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.showMonthTag,
    required this.colors,
    required this.tokens,
    required this.l,
  });

  final TimelineEntry entry;
  final bool showMonthTag;
  final BannerColors colors;
  final GachaTokens tokens;
  final AppLocalizations l;

  String _formatShortDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}/${two(t.day)}';
  }

  String _bannerName(String gachaType) => gachaTypes
      .firstWhere(
        (t) => t.gachaType == gachaType,
        orElse: () => GachaType(
          gachaType: gachaType,
          nameKey: gachaType,
          fiveStarPity: 90,
          fourStarPity: 10,
        ),
      )
      .resolveName(l);

  @override
  Widget build(BuildContext context) {
    final accent = colors.colorFor(entry.gachaType);
    final year = entry.time.year.toString();
    final month = entry.time.month.toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.only(
        top: showMonthTag ? AppSpacing.m : 0,
        bottom: AppSpacing.m,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 月份左欄(固定寬度,僅在 showMonthTag 時填字)
          SizedBox(
            width: _monthColumnWidth,
            child: showMonthTag
                ? Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.s, top: 4),
                    child: Text(
                      l.timelineMonthLabel(year, month),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // 節點圓
          SizedBox(width: _haloSize, child: Center(child: _Node(color: accent, tokens: tokens))),
          const SizedBox(width: AppSpacing.m),
          // 主內容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatShortDate(entry.time)} · ${_bannerName(entry.gachaType)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowRow extends StatelessWidget {
  const _NowRow({
    required this.nowPulls,
    required this.isAcrossBanners,
    required this.tokens,
    required this.l,
  });

  final int nowPulls;
  final bool isAcrossBanners;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final meta = isAcrossBanners
        ? l.timelineNowSinceCrossPool(nowPulls)
        : l.timelineNowSinceLast(nowPulls);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _monthColumnWidth),
          SizedBox(
            width: _haloSize,
            child: Center(child: _Node(color: tokens.accentPrimary, tokens: tokens, hollow: true)),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.timelineNowLabel,
                    style: TextStyle(
                      color: tokens.accentPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.color, required this.tokens, this.hollow = false});
  final Color color;
  final GachaTokens tokens;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _haloSize,
      height: _haloSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.25),
      ),
      child: Container(
        width: _nodeSize,
        height: _nodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? tokens.surfaceCard : color,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}
```

### Step 4: Run widget tests to verify they pass

- [ ] **執行**

```
flutter test test/widgets/cards/timeline_vertical_test.dart
```
預期:`All tests passed!`(5 tests)。

### Step 5: Format + analyze + commit

- [ ] **格式化、分析、提交**

```
dart format lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
flutter analyze lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
```
預期:這兩個檔無 issue。

```
git add lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "feat(widgets): add TimelineVertical with continuous rail + month tags + Now row"
```

---

## Task 6: 整合 `BannerPage` 並刪除舊 `TimelineCard`

**Files:**
- Modify: `lib/pages/banner_page.dart:17` (import) 與 `:200` (ChartCard.chart)
- Delete: `lib/widgets/cards/timeline_card.dart`
- Delete: `test/widgets/cards/timeline_card_test.dart`

### Step 1: Update `banner_page.dart`

- [ ] **修改 import**(`banner_page.dart:17`)

把:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_card.dart';
```
改為:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
```

- [ ] **修改 ChartCard 第 3 格**(`banner_page.dart:198-202` 附近)

把:
```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineCard(records: records),
  ),
),
```
改為:
```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineHorizontal(
      entries: buildTimelineEntries(records),
      colors: BannerColors.fromTokens(tokens),
      nowPulls: pullsSinceLastFiveStar(records),
    ),
  ),
),
```

### Step 2: Delete old files

- [ ] **刪除**

```
rm lib/widgets/cards/timeline_card.dart
rm test/widgets/cards/timeline_card_test.dart
```

### Step 3: Run analyze + tests

- [ ] **檢查**

```
flutter analyze
flutter test
```

預期:
- `flutter analyze`:`overview_page.dart` 仍會因 `_LatestFiveStar` 使用了被移除的 `timelineLatestEntry` 飄紅;`banner_page.dart` 已乾淨 — 預期內,Task 7 修。
- `flutter test`:`timeline_card_test.dart` 已刪,跑全部仍應 PASS(舊測試是否被引用?應該沒有)。

### Step 4: Commit

- [ ] **提交**

```
git add lib/pages/banner_page.dart lib/widgets/cards/timeline_card.dart test/widgets/cards/timeline_card_test.dart
git commit -m "refactor(banner_page): swap TimelineCard for TimelineHorizontal with Now marker"
```

---

## Task 7: 整合 `OverviewPage` 並刪除 `_LatestFiveStar` 與 `FiveStarList`

**Files:**
- Modify: `lib/pages/overview_page.dart`(整個檔案重整 import + 兩處替換 + 刪除 `_LatestFiveStar`)
- Delete: `lib/widgets/data/five_star_list.dart`

### Step 1: Modify `overview_page.dart`

- [ ] **修改 import 區塊**(`overview_page.dart:6-18`)

把:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/five_star_list.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
```

改為(刪除 `wish_record`、`five_star_list`,新增 `timeline_entries`、`banner_colors`、`timeline_horizontal`、`timeline_vertical`;`wish_stats` 仍留給上方 StatCard 用):
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/loading_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
```

- [ ] **替換 Row 2 第 3 格**(`overview_page.dart:154-163` 附近)

把:
```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: _LatestFiveStar(
      stats: stats,
      banners: activeData.banners,
    ),
  ),
),
```
改為:
```dart
SizedBox(
  width: tileWidth,
  child: ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineHorizontal(
      entries: buildTimelineEntriesAcrossBanners(activeData.banners),
      colors: BannerColors.fromTokens(tokens),
    ),
  ),
),
```

- [ ] **替換下方 `FiveStarList`**(`overview_page.dart:175` 附近)

把:
```dart
FiveStarList(banners: activeData.banners),
```
改為:
```dart
TimelineVertical(
  entries: buildTimelineEntriesAcrossBanners(activeData.banners),
  colors: BannerColors.fromTokens(tokens),
  nowPulls: pullsSinceLastFiveStarAcrossBanners(activeData.banners),
  isAcrossBanners: true,
),
```

- [ ] **刪除整個 `_LatestFiveStar` private widget**(`overview_page.dart:182-239`)

從 `class _LatestFiveStar extends StatelessWidget {` 到該 class 結束的 `}` 全部刪除。

### Step 2: Delete `FiveStarList` source

- [ ] **刪除**

```
rm lib/widgets/data/five_star_list.dart
```

### Step 3: Run analyze + tests

- [ ] **檢查**

```
flutter analyze
flutter test
```

預期:**兩者皆全綠**。`flutter analyze` 應該輸出 `No issues found!`。`flutter test` 應該全 PASS。

### Step 4: Commit

- [ ] **提交**

```
git add lib/pages/overview_page.dart lib/widgets/data/five_star_list.dart
git commit -m "refactor(overview_page): replace _LatestFiveStar + FiveStarList with TimelineHorizontal + TimelineVertical"
```

---

## Task 8: 最終驗證

**Files:** 無修改,純驗證。

### Step 1: Full format check

- [ ] **檢查 lib/ 與 test/ 格式**

```
dart format lib/ test/
```

預期:無檔案被改動(若先前 commit 都跑過 dart format)。若有改動 → `git diff` 確認後 commit。

### Step 2: Full analyze

- [ ] **靜態分析**

```
flutter analyze
```

預期:`No issues found!`(分析整個專案)。

### Step 3: Full test suite

- [ ] **執行全部測試**

```
flutter test
```

預期:`All tests passed!` 含新增的 timeline_entries / timeline_horizontal / timeline_vertical 測試。

### Step 4: Manual smoke test(desktop)

- [ ] **手動驗證(若可在本機跑桌面)**

```
flutter run -d windows
```

或請使用者開啟並驗證:
1. **OverviewPage**:Row 2 第 3 個 ChartCard 顯示橫向時間軸(節點 + 軸線 + 名稱/MM-DD·N抽);**沒有**「現在」節點(跨卡池 A 不加)
2. **OverviewPage 下方**:顯示直向時間軸,軸線連續貫穿,左側 80px 為月份標籤,頂端有「現在」row(中空節點)
3. **BannerPage**(切到角色池):Row 2 顯示橫向時間軸,**最左**為「現在」中空節點
4. **i18n 切換**(zh-Hant / zh-Hans / en):
   - 月份標籤改變(`2025 / 04` 或 `04 / 2025`)
   - 「現在」標籤改變(現在 / 现在 / Now)
5. **空狀態**:刪除所有紀錄後(或抓一個全新帳號未同步),三處皆顯示 `timelineNoRecords` 字串

若任一未過,記下 bug 並決定是修還是分開為新 plan。

### Step 5: Final commit (only if dart format produced changes)

- [ ] **若 step 1 有改動才執行**

```
git add lib/ test/
git commit -m "style: dart format pass over timeline files"
```

---

## Self-review checklist(本人實作完一遍時自己回頭看)

- [ ] Spec 中 §4.1 列出的 4 個函式都有實作(Task 1)
- [ ] Spec 中 §4.2 `BannerColors.fromTokens` 對應正確(`accentPrimary` for chronicled, `threeStar` for standard, etc.)
- [ ] Spec 中 §4.3 `TimelineHorizontal` API、空狀態、Now marker 三條都有(Task 4)
- [ ] Spec 中 §4.4 `TimelineVertical` API(含 `isAcrossBanners`)、月份分組、Now row 都有(Task 5)
- [ ] Spec 中 §5.1 / §5.2 兩頁面整合都做(Task 6, 7)
- [ ] Spec 中 §6 i18n 變更四個 .arb 都改(Task 2)
- [ ] Spec 中 §7 邊界:`entries.isEmpty + nowPulls != null` 渲染單一 Now(兩個 widget 都有測)
- [ ] Spec 中 §8 測試覆蓋四群組(Task 1 + 4 + 5)
- [ ] 沒有引入未使用 import
- [ ] 沒有保留任何指向已刪除 `TimelineCard` / `FiveStarList` 的引用

---

## Notes for the implementer

- **不要 `git add -A` 或 `git add .`**:每個 task 只 add 該 task 觸及的檔案,避免誤入 `.superpowers/` 或 `docs/superpowers/`(雖然兩者都在 `.gitignore` 內,實務上明確 add 比較安全)。
- **不要 `--no-verify`**:若有 pre-commit hook 失敗,看訊息修。專案 CLAUDE.md 明確禁止。
- **`dart format` 不要對 `.` 跑**:會動到 `rust_builder/` vendored 程式碼;`lib/ test/` 是安全的目標。
- **`pullsSinceLastFiveStarAcrossBanners` 跨卡池語意**:本實作把「現在」視為「跨全部卡池自最新一筆 5★ 之後的累積 record 數」,並用 `timelineNowSinceCrossPool` i18n 明示;若實作中發現該文案在使用者場景中仍易混淆,可在另開 issue / plan 調整文案,不必動結構。
- **A 在 ChartCard 內部**:`ChartCard` 給 `chart` slot 用 `Expanded`,所以 `TimelineHorizontal` 的 `SingleChildScrollView` 會吃滿可用高度(預設 `ChartCard.height = 260`,扣標題與 padding,大約 ~180px 可用)。`TimelineHorizontal` 用 `SizedBox(height: double.infinity)` 撐滿;若視覺上節點高度感受不對,可在 Task 8 手動驗證時微調 `_colWidth` / 各 `AppSpacing.xs` 值。
