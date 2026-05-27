# 綜合頁時間軸分頁載入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 綜合頁直向時間軸 (`TimelineVertical`) 預設只顯示最新 10 筆，超過則底部顯示「載入更多」按鈕，點擊一次追加 10 筆，clamp 到資料上限。

**Architecture:** `TimelineVertical` 從 `StatelessWidget` 改成 `StatefulWidget`，內部維護 `_visibleCount`（初值 10）。`build()` 取 `entries.take(_visibleCount)` 切片渲染，月份左欄標籤跟著切片重算。`didUpdateWidget` 比較 `entries.length + entries.firstOrNull?.time` 兩者同時不同就 reset 回 10，否則只 clamp。按鈕為 `TextButton.icon`、水平置中、位於時間軸卡片底部、Stack 外（避免背景軸線延伸過按鈕區）。對外 public API 完全不變、`overview_page.dart` 零更動。

**Tech Stack:** Flutter / Dart、`flutter_riverpod`（不直接動用）、`flutter_gen-l10n`（arb → `app_localizations.dart`）。

---

## 檔案結構

| 動作 | 路徑 | 角色 |
|---|---|---|
| 修改 | `lib/widgets/cards/timeline_vertical.dart` | `TimelineVertical` 轉 stateful，加分頁與按鈕。`_NowRow` / `_EntryRow` / `_Node` 不動。 |
| 修改 | `lib/l10n/app_zh_Hant.arb` | 新增 `timelineLoadMore` + metadata（模板檔，必須先加） |
| 修改 | `lib/l10n/app_zh_Hans.arb` | 新增 `timelineLoadMore` + metadata |
| 修改 | `lib/l10n/app_en.arb` | 新增 `timelineLoadMore` + metadata |
| 修改 | `test/widgets/cards/timeline_vertical_test.dart` | 新增分頁行為測試 case，既有 5 個 case 保留 |
| 不動 | `lib/pages/overview_page.dart` | 呼叫處與 5 個 named param 不變 |
| 不動 | `lib/services/timeline_entries.dart` | 純資料層 |
| 不動 | `lib/widgets/cards/timeline_horizontal.dart` | 不在綜合頁使用 |
| 不動 | `lib/l10n/app_ja.arb`、`app_fr.arb`、`app_es.arb`、`app_pt.arb`、`app_th.arb`、`app_vi.arb`、`app_zh.arb` | 跟既有 timeline-* 系列 key 翻譯範圍一致，fallback 到模板 |

---

## Task 1: i18n — 新增 `timelineLoadMore` key（3 個語言）

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`（模板檔，line ~249 `timelineScrollRight` 之後）
- Modify: `lib/l10n/app_zh_Hans.arb`（line ~195 `timelineScrollRight` 之後）
- Modify: `lib/l10n/app_en.arb`（line ~218 `timelineScrollRight` 之後）

- [ ] **Step 1: 在 `app_zh_Hant.arb` 的 `timelineScrollRight` 之後加上新 key**

找到這一段：

```json
  "timelineScrollLeft": "往左捲動",
  "timelineScrollRight": "往右捲動",
```

改為：

```json
  "timelineScrollLeft": "往左捲動",
  "timelineScrollRight": "往右捲動",

  "timelineLoadMore": "載入更多（剩餘 {n} 筆）",
  "@timelineLoadMore": {
    "placeholders": { "n": { "type": "int" } }
  },
```

- [ ] **Step 2: 在 `app_zh_Hans.arb` 的 `timelineScrollRight` 之後加上新 key**

找到：

```json
  "timelineScrollLeft": "往左滚动",
  "timelineScrollRight": "往右滚动",
```

改為：

```json
  "timelineScrollLeft": "往左滚动",
  "timelineScrollRight": "往右滚动",

  "timelineLoadMore": "加载更多（剩余 {n} 项）",
  "@timelineLoadMore": {
    "placeholders": { "n": { "type": "int" } }
  },
```

- [ ] **Step 3: 在 `app_en.arb` 的 `timelineScrollRight` 之後加上新 key**

找到：

```json
  "timelineScrollLeft": "Scroll left",
  "timelineScrollRight": "Scroll right",
```

改為：

```json
  "timelineScrollLeft": "Scroll left",
  "timelineScrollRight": "Scroll right",

  "timelineLoadMore": "Load more ({n} remaining)",
  "@timelineLoadMore": {
    "placeholders": { "n": { "type": "int" } }
  },
```

- [ ] **Step 4: 觸發 i18n 生成**

Run: `flutter pub get`
Expected: 成功完成，`lib/l10n/generated/app_localizations.dart` 內可看到 `timelineLoadMore(int n)` 方法新生成。

可直接以 grep 驗證：

```bash
grep -n "timelineLoadMore" lib/l10n/generated/app_localizations.dart
```

預期至少 4 筆命中（abstract method + zh_Hant/zh_Hans/en 各一個 override）。

- [ ] **Step 5: 跑靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 格式化**

Run: `dart format lib/ test/`
Expected: 印出 0 or 少數檔案的 reformat 訊息（無錯誤）。

- [ ] **Step 7: Commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/generated/app_localizations.dart lib/l10n/generated/app_localizations_en.dart lib/l10n/generated/app_localizations_zh.dart
git commit -m "i18n(timeline): add timelineLoadMore key for zh_Hant / zh_Hans / en"
```

> 若 `lib/l10n/generated/` 在 `.gitignore` 內則不會 stage，無需擔心；只 stage 實際被 git 追蹤的檔案即可。

---

## Task 2: TimelineVertical 改 stateful + 預設只顯示 10 筆（TDD）

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Test: `test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 寫失敗測試 — 11 筆 entries 預設只顯示前 10 筆**

在 `test/widgets/cards/timeline_vertical_test.dart` 的 `main()` 最後加上：

```dart
  testWidgets('entries=11 → defaults to first 10 entries only', (tester) async {
    final entries = List<TimelineEntry>.generate(
      11,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(find.text('item-0'), findsOneWidget);
    expect(find.text('item-9'), findsOneWidget);
    expect(find.text('item-10'), findsNothing);
  });
```

- [ ] **Step 2: 跑測試確認 FAIL**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 上述新測試 FAIL（找得到 `item-10`，但預期 findsNothing），既有 5 個測試保持 PASS。

- [ ] **Step 3: 把 `TimelineVertical` 改成 StatefulWidget**

開啟 `lib/widgets/cards/timeline_vertical.dart`，把第 18 行的 class 宣告：

```dart
class TimelineVertical extends StatelessWidget {
```

改成：

```dart
class TimelineVertical extends StatefulWidget {
```

並在 class 結尾（`build` 方法之前最後一個 final 欄位下方）替換掉 `build` 方法為 `createState`：

舊（從 `@override` 到 class `}` 結束的 `build` 整段）：

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ...
    return container(
      Stack(
        ...
      ),
    );
  }
}
```

新：

```dart
  @override
  State<TimelineVertical> createState() => _TimelineVerticalState();
}

class _TimelineVerticalState extends State<TimelineVertical> {
  static const int _initialPageSize = 10;
  static const int _pageStep = 10;

  int _visibleCount = _initialPageSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    Widget container(Widget child) => Container(
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

    final entries = widget.entries;
    final nowPulls = widget.nowPulls;
    final colors = widget.colors;
    final targetRank = widget.targetRank;
    final isAcrossBanners = widget.isAcrossBanners;

    if (entries.isEmpty && nowPulls == null) {
      return container(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: Text(
              l.timelineNoRecordsForRank(targetRank),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    final effectiveCount = _visibleCount.clamp(0, entries.length);
    final visibleEntries = entries.take(effectiveCount).toList(growable: false);

    // 計算每個 visible entry 是否為月份分組首 row
    final monthFlag = <bool>[];
    int? prevYearMonth;
    for (final entry in visibleEntries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthFlag.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }

    return container(
      Stack(
        children: [
          // 背景軸線
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
                  nowPulls: nowPulls,
                  targetRank: targetRank,
                  isAcrossBanners: isAcrossBanners,
                  tokens: tokens,
                ),
              for (var i = 0; i < visibleEntries.length; i++)
                _EntryRow(
                  entry: visibleEntries[i],
                  showMonthTag: monthFlag[i],
                  colors: colors,
                  tokens: tokens,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

> 注意：所有原本直接讀的欄位（`entries`、`colors` 等）改成讀 `widget.<field>`。`_NowRow(nowPulls: nowPulls!)` 的 `!` 拿掉，改為 `nowPulls: nowPulls`，因 local 變數已型別判定為非 null（前面已有 `if (nowPulls != null)` guard 加上 effective promote）。如果型別 promote 不生效，保留 `nowPulls!` 也可。

- [ ] **Step 4: 跑剛剛的測試確認 PASS**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 新測試 PASS，既有 5 個測試也保持 PASS。

- [ ] **Step 5: 跑全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 靜態分析 + 格式化**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: 兩者都成功，`flutter analyze` 印出 `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "refactor(timeline): make TimelineVertical stateful with default page size 10"
```

---

## Task 3: 載入更多按鈕（TDD）

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Test: `test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 寫失敗測試 — 11 筆顯示按鈕、點擊後 11 筆全顯示**

在 test 檔案的 `main()` 最後加上：

```dart
  testWidgets('entries=11 → load more button shows; tap reveals all', (tester) async {
    final entries = List<TimelineEntry>.generate(
      11,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;

    // 預設 10 筆 + 按鈕（剩 1 筆）
    expect(find.text('item-10'), findsNothing);
    expect(find.text(l.timelineLoadMore(1)), findsOneWidget);

    // 點擊按鈕 → 11 筆全顯示，按鈕消失
    await tester.tap(find.text(l.timelineLoadMore(1)));
    await tester.pumpAndSettle();
    expect(find.text('item-10'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('entries=10 → no load more button', (tester) async {
    final entries = List<TimelineEntry>.generate(
      10,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

  testWidgets('entries=25 → two taps fully expand', (tester) async {
    final entries = List<TimelineEntry>.generate(
      25,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;

    // 預設 10 筆 + 按鈕（剩 15）
    expect(find.text(l.timelineLoadMore(15)), findsOneWidget);

    // 第一次點擊 → 20 筆 + 按鈕（剩 5）
    await tester.tap(find.text(l.timelineLoadMore(15)));
    await tester.pumpAndSettle();
    expect(find.text('item-19'), findsOneWidget);
    expect(find.text('item-20'), findsNothing);
    expect(find.text(l.timelineLoadMore(5)), findsOneWidget);

    // 第二次點擊 → 25 筆全顯示，按鈕消失
    await tester.tap(find.text(l.timelineLoadMore(5)));
    await tester.pumpAndSettle();
    expect(find.text('item-24'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });
```

需要在檔案頂部 import 加 `Icons`（如未 import）。實際上 `import 'package:flutter/material.dart'` 已涵蓋。

- [ ] **Step 2: 跑測試確認 FAIL**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 新加的 3 個測試 FAIL（找不到 `timelineLoadMore` 文字、按鈕不存在），既有測試保持 PASS。

- [ ] **Step 3: 加上 `_loadMore` 方法與按鈕渲染**

在 `_TimelineVerticalState` 內 `build` 方法**之前**，新增 `_loadMore`：

```dart
  void _loadMore() {
    setState(() {
      _visibleCount = (_visibleCount + _pageStep).clamp(0, widget.entries.length);
    });
  }
```

接著修改 `build` 方法：把原本回傳 `container(Stack(...))` 的整段改為「Stack 包 entries + Stack 外加按鈕」結構。

找到 build 內這段：

```dart
    return container(
      Stack(
        children: [
          // 背景軸線
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
                  nowPulls: nowPulls,
                  targetRank: targetRank,
                  isAcrossBanners: isAcrossBanners,
                  tokens: tokens,
                ),
              for (var i = 0; i < visibleEntries.length; i++)
                _EntryRow(
                  entry: visibleEntries[i],
                  showMonthTag: monthFlag[i],
                  colors: colors,
                  tokens: tokens,
                ),
            ],
          ),
        ],
      ),
    );
```

改為：

```dart
    final remaining = entries.length - effectiveCount;

    return container(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              // 背景軸線
              Positioned(
                left: _railLeft,
                top: 0,
                bottom: 0,
                width: 2,
                child: Container(
                  color: tokens.textMuted.withValues(alpha: 0.3),
                ),
              ),
              // 前景:Column of rows
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (nowPulls != null)
                    _NowRow(
                      nowPulls: nowPulls,
                      targetRank: targetRank,
                      isAcrossBanners: isAcrossBanners,
                      tokens: tokens,
                    ),
                  for (var i = 0; i < visibleEntries.length; i++)
                    _EntryRow(
                      entry: visibleEntries[i],
                      showMonthTag: monthFlag[i],
                      colors: colors,
                      tokens: tokens,
                    ),
                ],
              ),
            ],
          ),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Center(
                child: TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: Text(l.timelineLoadMore(remaining)),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
```

> 設計重點：按鈕放在外層 Column（與 Stack 同層），不在 Stack 內 — 這樣背景軸線（Stack 內 Positioned `top:0 bottom:0`）只覆蓋 entries 區，不會延伸到按鈕區。

- [ ] **Step 4: 跑測試確認 PASS**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 全部測試 PASS。

- [ ] **Step 5: 跑全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 靜態分析 + 格式化**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "feat(timeline): add load-more button to TimelineVertical (10 entries per step)"
```

---

## Task 4: `didUpdateWidget` — signature reset / clamp（TDD）

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Test: `test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 寫失敗測試 — reset / clamp 兩個情境**

在 test 檔案的 `main()` 最後加上：

```dart
  testWidgets(
    'signature changed (different dataset) → resets visibleCount to 10',
    (tester) async {
      final entriesA = List<TimelineEntry>.generate(
        25,
        (i) => _e('a-$i', '301', 10, DateTime(2025, 4, 20 - i)),
      );
      final entriesB = List<TimelineEntry>.generate(
        15,
        (i) => _e('b-$i', '301', 10, DateTime(2024, 12, 20 - i)),
      );
      Widget host(List<TimelineEntry> entries) => _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      );

      await tester.pumpWidget(host(entriesA));
      final ctx = tester.element(find.byType(TimelineVertical));
      final l = AppLocalizations.of(ctx)!;

      // 點一次展開到 20
      await tester.tap(find.text(l.timelineLoadMore(15)));
      await tester.pumpAndSettle();
      expect(find.text('a-19'), findsOneWidget);

      // 換 dataset B（length 與 firstTime 都不同）→ reset
      await tester.pumpWidget(host(entriesB));
      await tester.pumpAndSettle();

      expect(find.text('b-9'), findsOneWidget); // 第 10 筆
      expect(find.text('b-10'), findsNothing); // 第 11 筆已不顯示
      expect(find.text(l.timelineLoadMore(5)), findsOneWidget); // 剩 15-10=5
    },
  );

  testWidgets(
    'same entries reference / signature → keeps expanded state, only clamps',
    (tester) async {
      final entries = List<TimelineEntry>.generate(
        25,
        (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
      );
      Widget host() => _wrap(
        (ctx, colors) => TimelineVertical(
          entries: entries,
          colors: colors,
          targetRank: 5,
        ),
      );

      await tester.pumpWidget(host());
      final ctx = tester.element(find.byType(TimelineVertical));
      final l = AppLocalizations.of(ctx)!;

      // 展開到 20
      await tester.tap(find.text(l.timelineLoadMore(15)));
      await tester.pumpAndSettle();
      expect(find.text('item-19'), findsOneWidget);

      // 用同樣 entries rebuild — 視為純視覺更新（signature 不變）→ 保持 20
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('item-19'), findsOneWidget);
      expect(find.text(l.timelineLoadMore(5)), findsOneWidget);
    },
  );
```

- [ ] **Step 2: 跑測試確認 FAIL**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 兩個新測試 FAIL（reset 測試會看到 `b-10` 還顯示；clamp 測試實際上會自然 PASS 因預設不 reset — 但因 reset 邏輯尚未實作、若狀態被意外 reset 也會 fail；總之至少 reset 那個會 fail）。

> 註：第二個測試本來就 PASS 也 OK — 它驗證的是「不應 reset」這個 invariant，加上去是防止後續實作把邏輯做錯時能立刻 catch。

- [ ] **Step 3: 加上 `didUpdateWidget`**

在 `_TimelineVerticalState` class 內、`_loadMore` 方法**之前**，加上：

```dart
  @override
  void didUpdateWidget(TimelineVertical oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFirstTime = oldWidget.entries.isNotEmpty
        ? oldWidget.entries.first.time
        : null;
    final newFirstTime = widget.entries.isNotEmpty
        ? widget.entries.first.time
        : null;
    final lengthChanged = oldWidget.entries.length != widget.entries.length;
    final firstTimeChanged = oldFirstTime != newFirstTime;
    if (lengthChanged && firstTimeChanged) {
      // length + firstTime 同時不同 → 視為不同資料集，reset
      setState(() {
        _visibleCount = _initialPageSize;
      });
    } else {
      // 同資料集（或局部變動）→ 只做 clamp
      final clamped = _visibleCount.clamp(0, widget.entries.length);
      if (clamped != _visibleCount) {
        setState(() {
          _visibleCount = clamped;
        });
      }
    }
  }
```

- [ ] **Step 4: 跑測試確認 PASS**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: 全部測試 PASS。

- [ ] **Step 5: 跑全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 6: 靜態分析 + 格式化**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "feat(timeline): reset paginated count on dataset change, clamp otherwise"
```

---

## Task 5: 手動驗收 + release smoke test

**Files:** none（驗證 only）

- [ ] **Step 1: 確認最終品質檢查全綠**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Run: `flutter test`
Expected: 全部成功；`flutter analyze` 印出 `No issues found!`、`flutter test` 印出 `All tests passed!`。

- [ ] **Step 2: 手動驗收（debug 啟動）**

Run: `flutter run -d windows`（或目前慣用平台）

切到綜合頁，分別驗證：

- 有資料的帳號（祈願 5★ 多於 10 筆）：時間軸只顯示前 10 筆，底部有「載入更多（剩餘 N 筆）」置中按鈕，點一次 +10、剩餘數字遞減；展到底按鈕消失。
- 頌願段（如有資料）：同樣行為。
- 5★ ≤ 10 筆的帳號：無按鈕，行為跟改動前一致。
- 5★ = 0 筆：仍顯示「暫無 5★ 紀錄」/「現在」row（依 nowPulls 而定）。
- 切換帳號（多帳號情境）：切到不同 uid 後，時間軸 reset 回前 10 筆。

關閉應用。

- [ ] **Step 3:（選用）release 模式驗證**

跟著 memory `feedback_perf_check_release_first.md`，如果 debug 模式手動驗收時感受到延遲，跑一次 release 對照：

Run: `flutter run -d windows --release`

- [ ] **Step 4: 無需 commit**

本 task 純驗證，前面 4 個 task 已涵蓋所有檔案 commit。

---

## 完成標準

- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`
- `dart format lib/ test/` → 0 reformat needed
- Git log 上有 4 個新 commit（i18n / refactor / feat / feat）
- 綜合頁時間軸（祈願與頌願兩段）皆套用「預設 10、載入更多每次 +10」行為
- `TimelineVertical` 對外 API 未變、`overview_page.dart` 未動
