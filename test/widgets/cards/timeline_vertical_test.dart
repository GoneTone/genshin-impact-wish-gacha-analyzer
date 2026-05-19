import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(
      name: name,
      gachaType: gachaType,
      time: time,
      pullsSincePrev: pulls,
    );

Widget _wrap(Widget Function(BuildContext, BannerColors) build) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (ctx) {
        final colors = BannerColors.of(Theme.of(ctx).brightness);
        return SizedBox(width: 600, child: build(ctx, colors));
      },
    ),
  ),
);

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            TimelineVertical(entries: const [], colors: colors, targetRank: 5),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsOneWidget,
    );
  });

  testWidgets('title 參數：顯示於 TimelineVertical 卡片子樹內', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          title: 'X標題',
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('X標題'),
      ),
      findsOneWidget,
    );
    // 既有內容仍正常顯示
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('title 參數：空資料分支也顯示標題於卡內', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          title: 'X標題',
          entries: const [],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('X標題'),
      ),
      findsOneWidget,
    );
    // 空資料文案仍存在
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsOneWidget,
    );
  });

  testWidgets('不傳 title（App 既有用法）：完全不顯示標題、行為不變', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(find.text('X標題'), findsNothing);
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('footerNote 參數：顯示於 TimelineVertical 卡片子樹內（有資料）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          footerNote: '註腳X',
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('註腳X'),
      ),
      findsOneWidget,
    );
    // 既有內容仍正常顯示
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('footerNote 參數：空資料分支也顯示於卡內', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          footerNote: '註腳X',
          entries: const [],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('註腳X'),
      ),
      findsOneWidget,
    );
    // 空資料文案仍存在
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsOneWidget,
    );
  });

  testWidgets('不傳 footerNote（App 既有用法）：完全不顯示、既有內容仍在', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(find.text('註腳X'), findsNothing);
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('同時傳 title + footerNote：兩者都在 TimelineVertical 子樹內', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          title: 'X標題',
          footerNote: '註腳X',
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('X標題'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.text('註腳X'),
      ),
      findsOneWidget,
    );
    // 既有內容仍正常顯示
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('fillHeight: true → 卡片外框撐滿父給的有界高度（600）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => SizedBox(
          height: 600,
          child: TimelineVertical(
            fillHeight: true,
            entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
            colors: colors,
            targetRank: 5,
          ),
        ),
      ),
    );
    // TimelineVertical 卡片容器（Container with decoration）的高度撐滿到 600。
    final boxFinder = find.descendant(
      of: find.byType(TimelineVertical),
      matching: find.byType(Container),
    );
    expect(tester.getSize(boxFinder.first).height, closeTo(600, 0.5));
    // 內容仍正常顯示（置頂，底部為卡內留白）
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('fillHeight: false（預設，App 既有用法）→ 卡片高依內容、未撐滿 600', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => SizedBox(
          height: 600,
          child: Align(
            alignment: Alignment.topCenter,
            child: TimelineVertical(
              entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
              colors: colors,
              targetRank: 5,
            ),
          ),
        ),
      ),
    );
    final boxFinder = find.descendant(
      of: find.byType(TimelineVertical),
      matching: find.byType(Container),
    );
    expect(tester.getSize(boxFinder.first).height, lessThan(600));
    expect(find.text('夜蘭'), findsOneWidget);
  });

  testWidgets('renders entries with month tag per month group', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: [
            _e('娜維婭', '301', 62, DateTime(2025, 4, 19)),
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;
    expect(find.text(l.timelineMonthLabel('2025', '04')), findsOneWidget);
    expect(find.text(l.timelineMonthLabel('2025', '03')), findsOneWidget);
    expect(find.text('娜維婭'), findsOneWidget);
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets(
    'nowPulls + isAcrossBanners=true → top row shows cross-pool i18n',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineVertical(
            entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
            colors: colors,
            targetRank: 5,
            nowPulls: 12,
            isAcrossBanners: true,
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(TimelineVertical)),
      )!;
      expect(find.text(l.timelineNowLabel), findsOneWidget);
      expect(
        find.text(l.timelineNowSinceCrossPool(l.rarityStar(5), 12)),
        findsOneWidget,
      );
      expect(
        find.text(l.timelineNowSinceLast(l.rarityStar(5), 12)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'nowPulls + isAcrossBanners=false → top row shows single-pool i18n',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineVertical(
            entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
            colors: colors,
            targetRank: 5,
            nowPulls: 28,
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(TimelineVertical)),
      )!;
      expect(
        find.text(l.timelineNowSinceLast(l.rarityStar(5), 28)),
        findsOneWidget,
      );
    },
  );

  testWidgets('empty + nowPulls → renders only Now row, no NoRecords', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: const [],
          colors: colors,
          targetRank: 5,
          nowPulls: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsNothing,
    );
  });

  testWidgets('entries=11 → defaults to first 10 entries only', (tester) async {
    final entries = List<TimelineEntry>.generate(
      11,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
        ),
      ),
    );
    expect(find.text('item-0'), findsOneWidget);
    expect(find.text('item-9'), findsOneWidget);
    expect(find.text('item-10'), findsNothing);
  });

  testWidgets('entries=11 → load more button shows; tap reveals all', (
    tester,
  ) async {
    final entries = List<TimelineEntry>.generate(
      11,
      (i) => _e('item-$i', '301', 10, DateTime(2025, 4, 20 - i)),
    );
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;

    // 預設 10 筆 + 按鈕（剩 1 筆）
    expect(find.text('item-10'), findsNothing);
    expect(find.text(l.timelineLoadMore(1)), findsOneWidget);

    // 捲動到按鈕再點擊 → 11 筆全顯示，按鈕消失
    await tester.ensureVisible(find.text(l.timelineLoadMore(1)));
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
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
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
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;

    // 預設 10 筆 + 按鈕（剩 15）
    expect(find.text(l.timelineLoadMore(15)), findsOneWidget);

    // 第一次點擊 → 20 筆 + 按鈕（剩 5）
    await tester.ensureVisible(find.text(l.timelineLoadMore(15)));
    await tester.tap(find.text(l.timelineLoadMore(15)));
    await tester.pumpAndSettle();
    expect(find.text('item-19'), findsOneWidget);
    expect(find.text('item-20'), findsNothing);
    expect(find.text(l.timelineLoadMore(5)), findsOneWidget);

    // 第二次點擊 → 25 筆全顯示，按鈕消失
    await tester.ensureVisible(find.text(l.timelineLoadMore(5)));
    await tester.tap(find.text(l.timelineLoadMore(5)));
    await tester.pumpAndSettle();
    expect(find.text('item-24'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });

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
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
        ),
      );

      await tester.pumpWidget(host(entriesA));
      final ctx = tester.element(find.byType(TimelineVertical));
      final l = AppLocalizations.of(ctx)!;

      // 點一次展開到 20
      await tester.ensureVisible(find.text(l.timelineLoadMore(15)));
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
        (ctx, colors) => SingleChildScrollView(
          child: TimelineVertical(
            entries: entries,
            colors: colors,
            targetRank: 5,
          ),
        ),
      );

      await tester.pumpWidget(host());
      final ctx = tester.element(find.byType(TimelineVertical));
      final l = AppLocalizations.of(ctx)!;

      // 展開到 20
      await tester.ensureVisible(find.text(l.timelineLoadMore(15)));
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
}
