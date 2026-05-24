import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(
      name: name,
      gachaType: gachaType,
      time: time,
      pullsSincePrev: pulls,
    );

Widget _wrap(Widget Function(BuildContext ctx, BannerColors colors) build) =>
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 160,
          child: Builder(
            builder: (ctx) {
              final colors = BannerColors.of(Theme.of(ctx).brightness);
              return build(ctx, colors);
            },
          ),
        ),
      ),
    );

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: const [],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsOneWidget,
    );
  });

  testWidgets('renders one column per entry', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets('nowPulls != null → adds Now column at the leftmost', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 28,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNowPulls(28)), findsOneWidget);
  });

  testWidgets('empty + nowPulls != null → renders only the Now column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: const [],
          colors: colors,
          nowPulls: 5,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsNothing,
    );
  });

  testWidgets('Now column appears leftmost (before entry columns)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 28,
          targetRank: 5,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    final nowLeft = tester.getTopLeft(find.text(l.timelineNowLabel)).dx;
    final entryLeft = tester.getTopLeft(find.text('夜蘭')).dx;
    expect(nowLeft, lessThan(entryLeft));
  });

  testWidgets('overflowing content is horizontally scrollable', (tester) async {
    // 20 entries × 90px = 1800px content; viewport is 1000px → must overflow.
    final entries = [
      for (var i = 19; i >= 0; i--)
        _e(
          'E$i',
          '301',
          60 + (19 - i),
          DateTime(2025, 1, 1).add(Duration(days: i)),
        ),
    ];
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            TimelineHorizontal(entries: entries, colors: colors, targetRank: 5),
      ),
    );
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollableState.position.axis, Axis.horizontal);
    expect(
      scrollableState.position.maxScrollExtent,
      greaterThan(0),
      reason:
          '20 entries × 90px (1800px) must overflow the test viewport (800px) '
          'so scroll is enabled. If this fails the timeline lost its '
          'scrollability.',
    );
  });

  // ---- Scroll affordance (fade + arrows) ----

  List<TimelineEntry> manyEntries(int n) => [
    for (var i = n - 1; i >= 0; i--)
      _e(
        'E$i',
        '301',
        60 + (n - 1 - i),
        DateTime(2025, 1, 1).add(Duration(days: i)),
      ),
  ];

  testWidgets('overflow + offset=0 → right arrow visible, left hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: manyEntries(20),
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('overflow + offset=middle → both arrows visible', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: manyEntries(20),
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('overflow + offset=max → left arrow visible, right hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: manyEntries(20),
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('no overflow (2 entries) → no arrows on either side', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('tap right arrow → scrolls by one column (90 px)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: manyEntries(20),
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, 0);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, closeTo(90, 0.5));
  });

  testWidgets(
    'tap right arrow repeatedly → clamps at maxScrollExtent and hides right arrow',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: manyEntries(20),
            colors: colors,
            targetRank: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(Scrollable),
        ),
      );
      // 1800 - 1000 = 800 px max; 90 px/tap → 10 taps is plenty
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
      }
      expect(
        scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, 0.5),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    },
  );

  testWidgets(
    'entries shrink from overflow to non-overflow → arrows disappear',
    (tester) async {
      Widget makeWidget(List<TimelineEntry> entries) => _wrap(
        (ctx, colors) =>
            TimelineHorizontal(entries: entries, colors: colors, targetRank: 5),
      );
      await tester.pumpWidget(makeWidget(manyEntries(20)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.pumpWidget(
        makeWidget([
          _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
          _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    },
  );

  testWidgets(
    'empty + no nowPulls → no scroll affordance even if widget renders',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: const [],
            colors: colors,
            targetRank: 5,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('每欄名稱上方顯示 GachaItemIcon', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('timeline_h_icon_test_');
    });
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
    );

    final records = [
      GachaRecord(
        id: '1',
        uid: '100000001',
        gachaType: '301',
        name: '夜蘭',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 4, 1),
        lang: 'zh-tw',
      ),
      GachaRecord(
        id: '2',
        uid: '100000001',
        gachaType: '301',
        name: '納西妲',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 3, 1),
        lang: 'zh-tw',
      ),
    ];
    final entries = buildTimelineEntries(records, targetRank: 5);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 160,
              child: Builder(
                builder: (ctx) {
                  final colors = BannerColors.of(Theme.of(ctx).brightness);
                  return TimelineHorizontal(
                    entries: entries,
                    colors: colors,
                    targetRank: 5,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GachaItemIcon), findsNWidgets(entries.length));
  });
}
