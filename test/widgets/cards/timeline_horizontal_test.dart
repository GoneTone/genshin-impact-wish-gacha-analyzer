import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_node.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

import '../../helpers/timeline_geometry.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(
      name: name,
      gachaType: gachaType,
      time: time,
      pullsSincePrev: pulls,
    );

/// 將 [TimelineHorizontal] 包在標準測試 scaffold 內並 pump。
Future<void> pumpTimelineHorizontal(
  WidgetTester tester, {
  required List<TimelineEntry> entries,
  required int targetRank,
  int? nowPulls,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 160,
          child: TimelineHorizontal(
            entries: entries,
            targetRank: targetRank,
            nowPulls: nowPulls,
          ),
        ),
      ),
    ),
  );
}

Widget _wrap(Widget Function(BuildContext ctx) build) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(width: 1000, height: 160, child: Builder(builder: build)),
  ),
);

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await pumpTimelineHorizontal(tester, entries: const [], targetRank: 5);
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(
      find.text(l.timelineNoRecordsForRank(l.rarityStar(5))),
      findsOneWidget,
    );
  });

  testWidgets('renders one column per entry', (tester) async {
    await pumpTimelineHorizontal(
      tester,
      entries: [
        _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
        _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
      ],
      targetRank: 5,
    );
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets('nowPulls != null → adds Now column at the leftmost', (
    tester,
  ) async {
    await pumpTimelineHorizontal(
      tester,
      entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
      nowPulls: 28,
      targetRank: 5,
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
    await pumpTimelineHorizontal(
      tester,
      entries: const [],
      nowPulls: 5,
      targetRank: 5,
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
    await pumpTimelineHorizontal(
      tester,
      entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
      nowPulls: 28,
      targetRank: 5,
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
    await pumpTimelineHorizontal(tester, entries: entries, targetRank: 5);
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
    await pumpTimelineHorizontal(
      tester,
      entries: manyEntries(20),
      targetRank: 5,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('overflow + offset=middle → both arrows visible', (tester) async {
    await pumpTimelineHorizontal(
      tester,
      entries: manyEntries(20),
      targetRank: 5,
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
    await pumpTimelineHorizontal(
      tester,
      entries: manyEntries(20),
      targetRank: 5,
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
    await pumpTimelineHorizontal(
      tester,
      entries: [
        _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
        _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
      ],
      targetRank: 5,
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('drag cursor only shows over columns, not empty space', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx) =>
            const TimelineHorizontal(entries: [], targetRank: 5, nowPulls: 3),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    addTearDown(mouse.removePointer);
    final origin = tester.getTopLeft(find.byType(TimelineHorizontal));

    await mouse.addPointer(location: origin + const Offset(45, 80));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeLeftRight,
    );

    await mouse.moveTo(origin + const Offset(500, 80));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
  });

  testWidgets('only builds the columns near the viewport', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx) => TimelineHorizontal(entries: manyEntries(300), targetRank: 5),
      ),
    );
    expect(find.text('E299'), findsOneWidget);
    expect(find.text('E0', skipOffstage: false), findsNothing);
  });

  testWidgets('scroll offset survives being scrolled out of a lazy list', (
    tester,
  ) async {
    const listKey = Key('outer');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            key: listKey,
            children: [
              SizedBox(
                height: 160,
                child: TimelineHorizontal(
                  entries: manyEntries(60),
                  targetRank: 5,
                ),
              ),
              const SizedBox(height: 5000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(listKey), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineHorizontal), findsNothing);
    await tester.drag(find.byKey(listKey), const Offset(0, 6000));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, closeTo(180, 0.5));
  });

  testWidgets('tap right arrow → scrolls by one column (90 px)', (
    tester,
  ) async {
    await pumpTimelineHorizontal(
      tester,
      entries: manyEntries(20),
      targetRank: 5,
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
      await pumpTimelineHorizontal(
        tester,
        entries: manyEntries(20),
        targetRank: 5,
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
      Widget makeWidget(List<TimelineEntry> entries) =>
          _wrap((ctx) => TimelineHorizontal(entries: entries, targetRank: 5));
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
      await pumpTimelineHorizontal(tester, entries: const [], targetRank: 5);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('橫向節點 tooltip 僅顯示物品名稱（不含分級／抽數）', (tester) async {
    final entry = TimelineEntry(
      name: '魈',
      gachaType: '301',
      time: DateTime(2026, 6, 1),
      pullsSincePrev: 85, // 85/90 ≈ 0.94 → 非
    );
    await pumpTimelineHorizontal(tester, entries: [entry], targetRank: 5);
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.byTooltip('魈'), findsOneWidget);
    expect(
      find.byTooltip('魈 · ${l.luckTierUnlucky} · ${l.timelineSinceLast(85)}'),
      findsNothing,
    );
  });

  testWidgets('跨月顯示年/月標籤', (tester) async {
    final entries = [
      TimelineEntry(
        name: 'A',
        gachaType: '301',
        time: DateTime(2026, 6, 2),
        pullsSincePrev: 10,
      ),
      TimelineEntry(
        name: 'B',
        gachaType: '301',
        time: DateTime(2026, 5, 20),
        pullsSincePrev: 10,
      ),
    ];
    await pumpTimelineHorizontal(tester, entries: entries, targetRank: 5);
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineMonthLabel('2026', '06')), findsOneWidget);
    expect(find.text(l.timelineMonthLabel('2026', '05')), findsOneWidget);
  });

  /// 呈現帶圖示的兩欄時間軸（夜蘭、納西妲），回傳其條目；[height] 為 null 時高度不受限（依內容），
  /// [gachaType] 為頌願時兩筆紀錄沒有圖示。
  Future<List<TimelineEntry>> pumpIconTimeline(
    WidgetTester tester, {
    double? height = 240,
    String gachaType = '301',
  }) async {
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
        gachaType: gachaType,
        name: '夜蘭',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 4, 1),
        lang: 'zh-tw',
      ),
      GachaRecord(
        id: '2',
        uid: '100000001',
        gachaType: gachaType,
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
            body: SingleChildScrollView(
              child: SizedBox(
                width: 1000,
                height: height,
                child: TimelineHorizontal(entries: entries, targetRank: 5),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return entries;
  }

  testWidgets('每欄名稱上方顯示 GachaItemIcon', (tester) async {
    final entries = await pumpIconTimeline(tester);
    expect(find.byType(GachaItemIcon), findsNWidgets(entries.length));
  });

  testWidgets('nodes with an icon above stay on the axis line', (tester) async {
    final entries = await pumpIconTimeline(tester);
    expect(find.byType(TimelineNode), findsNWidgets(entries.length));
    final axisY = tester.getCenter(find.byType(TimelineHorizontal)).dy;
    for (final node in find.byType(TimelineNode).evaluate()) {
      expect(
        tester.getCenter(find.byWidget(node.widget)).dy,
        closeTo(axisY, 0.5),
      );
    }
    expect(tester.takeException(), isNull);
  });

  /// 時間軸背景軸線（2dp 高的 Container）。
  Finder axisLine() => find.descendant(
    of: find.byType(TimelineHorizontal),
    matching: find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 2,
    ),
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('now and entry nodes sit on the axis line at ${scale}x', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTimelineHorizontal(
        tester,
        entries: [_e('A', '301', 70, DateTime(2026, 6, 2))],
        targetRank: 5,
        nowPulls: 5,
      );
      final axisY = tester.getCenter(axisLine()).dy;
      expect(find.byType(TimelineNode), findsNWidgets(2));
      for (final node in find.byType(TimelineNode).evaluate()) {
        expect(
          tester.getCenter(find.byWidget(node.widget)).dy,
          closeTo(axisY, 0.5),
        );
      }
    });
  }

  for (final height in <double?>[240, null]) {
    testWidgets('odes nodes without an icon stay on the axis line '
        '(height=$height)', (tester) async {
      await pumpIconTimeline(tester, height: height, gachaType: '2000');
      final axisY = tester.getCenter(axisLine()).dy;
      expect(find.byType(GachaItemIcon), findsNothing);
      // 不限高度時另有一個撐高度用的隱形欄，同樣置中在軸線上。
      for (final node in find.byType(TimelineNode).evaluate()) {
        expect(
          tester.getCenter(find.byWidget(node.widget)).dy,
          closeTo(axisY, 0.5),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unbounded height leaves no blank band under the date row', (
    tester,
  ) async {
    await pumpIconTimeline(tester, height: null);
    final timeline = tester.getRect(find.byType(TimelineHorizontal));
    final lowestText = find
        .descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(RichText),
        )
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
        .reduce((a, b) => a > b ? a : b);
    expect(timeline.bottom - lowestText, lessThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unbounded height keeps the nodes on the axis line', (
    tester,
  ) async {
    await pumpIconTimeline(tester, height: null);
    final axisY = tester.getCenter(axisLine()).dy;
    for (final node in find.byType(TimelineNode).evaluate()) {
      expect(
        tester.getCenter(find.byWidget(node.widget)).dy,
        closeTo(axisY, 0.5),
      );
    }
  });

  testWidgets('timeline scrolls with a finger drag', (tester) async {
    final entries = [
      for (var i = 19; i >= 0; i--)
        _e(
          'E$i',
          '301',
          60 + (19 - i),
          DateTime(2025, 1, 1).add(Duration(days: i)),
        ),
    ];
    await pumpTimelineHorizontal(tester, entries: entries, targetRank: 5);
    await tester.drag(find.byType(TimelineHorizontal), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(TimelineHorizontal),
        matching: find.byType(Scrollable),
      ),
    );
    expect(state.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal timeline geometry matches the sister layout', (
    tester,
  ) async {
    await pumpTimelineHorizontal(
      tester,
      entries: [
        _e('夜蘭', '301', 87, DateTime(2026, 1, 5)),
        _e('流浪者', '301', 74, DateTime(2026, 1, 2)),
        _e('納西妲', '301', 40, DateTime(2025, 12, 20)),
        _e('魈', '200', 90, DateTime(2025, 11, 30)),
        _e('刻晴', '302', 62, DateTime(2025, 11, 3)),
      ],
      nowPulls: 28,
      targetRank: 5,
    );
    final actual = timelineGeometry(tester, find.byType(TimelineHorizontal));
    // 數值為實測；分隔線欄的 1px 左框線吃進欄寬，所以每欄都是 90。
    expect(actual, <(String, Rect)>[
      ('Now', const Rect.fromLTRB(26.625, 48.0, 63.375, 65.0)),
      ('28 pulls', const Rect.fromLTRB(4.0, 95.0, 86.0, 112.0)),
      ('01 / 2026', const Rect.fromLTRB(90.0, 22.0, 180.0, 38.0)),
      ('夜蘭', const Rect.fromLTRB(122.75, 48.0, 147.25, 65.0)),
      ('01/05 · 87 pulls', const Rect.fromLTRB(90.0, 95.0, 180.0, 112.0)),
      ('流浪者', const Rect.fromLTRB(206.625, 48.0, 243.375, 65.0)),
      ('01/02 · 74 pulls', const Rect.fromLTRB(180.0, 95.0, 270.0, 112.0)),
      ('12 / 2025', const Rect.fromLTRB(271.0, 22.0, 360.0, 38.0)),
      ('納西妲', const Rect.fromLTRB(297.125, 48.0, 333.875, 65.0)),
      ('12/20 · 40 pulls', const Rect.fromLTRB(271.0, 95.0, 360.0, 112.0)),
      ('11 / 2025', const Rect.fromLTRB(361.0, 22.0, 450.0, 38.0)),
      ('魈', const Rect.fromLTRB(399.375, 48.0, 411.625, 65.0)),
      ('11/30 · 90 pulls', const Rect.fromLTRB(361.0, 95.0, 450.0, 112.0)),
      ('刻晴', const Rect.fromLTRB(482.75, 48.0, 507.25, 65.0)),
      ('11/03 · 62 pulls', const Rect.fromLTRB(450.0, 95.0, 540.0, 112.0)),
      ('node', const Rect.fromLTRB(34.0, 69.0, 56.0, 91.0)),
      ('node', const Rect.fromLTRB(124.0, 69.0, 146.0, 91.0)),
      ('node', const Rect.fromLTRB(214.0, 69.0, 236.0, 91.0)),
      ('node', const Rect.fromLTRB(304.5, 69.0, 326.5, 91.0)),
      ('node', const Rect.fromLTRB(394.5, 69.0, 416.5, 91.0)),
      ('node', const Rect.fromLTRB(484.0, 69.0, 506.0, 91.0)),
      ('border', const Rect.fromLTRB(270.0, 22.0, 360.0, 138.0)),
      ('border', const Rect.fromLTRB(360.0, 22.0, 450.0, 138.0)),
    ]);
  });
}
