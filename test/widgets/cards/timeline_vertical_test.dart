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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';

import '../../helpers/timeline_geometry.dart';

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

/// pump helper：封裝 [TimelineVertical] 所有常用參數，方便新測試用單行建立。
Future<void> pumpTimelineVertical(
  WidgetTester tester, {
  required List<TimelineEntry> entries,
  required int targetRank,
  int? nowPulls,
  bool showLuckLegend = false,
}) async {
  await tester.pumpWidget(
    _wrap(
      (ctx, colors) => TimelineVertical(
        entries: entries,
        colors: colors,
        targetRank: targetRank,
        nowPulls: nowPulls,
        showLuckLegend: showLuckLegend,
      ),
    ),
  );
  await tester.pump();
}

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

  testWidgets('fillHeight: true + 內容遠超有界高（300）→ 無 overflow、卡片恆 = 300、內容置頂', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => SizedBox(
          height: 300,
          child: TimelineVertical(
            fillHeight: true,
            entries: [
              for (var i = 0; i < 30; i++)
                _e(
                  '五星$i',
                  '301',
                  80,
                  DateTime(2026, 1, 1).subtract(Duration(days: 31 * i + 1)),
                ),
            ],
            colors: colors,
            targetRank: 5,
          ),
        ),
      ),
    );
    // 解開內部高約束 + clip → 不可有 RenderFlex overflow / 任何 error。
    expect(tester.takeException(), isNull);
    // 卡片外框恆 = 父給的有界高 300（不被內容撐大、也不縮小）。
    final boxFinder = find.descendant(
      of: find.byType(TimelineVertical),
      matching: find.byType(Container),
    );
    expect(tester.getSize(boxFinder.first).height, closeTo(300, 0.5));
    // fillHeight 分支應包一層 ClipRect 負責裁切超出內容。
    expect(
      find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.byType(ClipRect),
      ),
      findsWidgets,
    );
    // 最上方（最新）entry 仍可見（內容置頂、未被裁掉）。
    expect(find.text('五星0'), findsOneWidget);
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

  testWidgets('每筆 entry 名稱前顯示 GachaItemIcon', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('timeline_v_icon_test_');
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
            body: Builder(
              builder: (ctx) {
                final colors = BannerColors.of(Theme.of(ctx).brightness);
                return SizedBox(
                  width: 600,
                  child: TimelineVertical(
                    entries: entries,
                    colors: colors,
                    targetRank: 5,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GachaItemIcon), findsNWidgets(entries.length));
  });

  testWidgets(
    'Tooltip 不被 GachaItemTapTarget 包裝破壞：longPress 名稱會疊出 tooltip overlay',
    (tester) async {
      late Directory tempDir;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('timeline_v_tooltip_');
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
              body: Builder(
                builder: (ctx) {
                  final colors = BannerColors.of(Theme.of(ctx).brightness);
                  return SizedBox(
                    width: 600,
                    child: TimelineVertical(
                      entries: entries,
                      colors: colors,
                      targetRank: 5,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 初始：元件內 name 只應有一個。
      expect(find.text('夜蘭'), findsOneWidget);

      // 長按名稱 → 觸發 Tooltip。Tooltip 在 GachaItemTapTarget 外層,
      // 應該不被內層 GestureDetector(onTap) 吞掉。
      await tester.longPress(find.text('夜蘭'));
      await tester.pumpAndSettle();

      // Tooltip overlay 疊上後,name 應為 2 個（元件內 + overlay）。
      expect(find.text('夜蘭'), findsNWidgets(2));
    },
  );

  testWidgets('節點 tooltip 僅顯示物品名稱（不含分級／抽數）', (tester) async {
    final entry = TimelineEntry(
      name: '刻晴',
      gachaType: '301', // 90 池
      time: DateTime(2026, 6, 1),
      pullsSincePrev: 40, // 40/90 ≈ 0.44 → 歐
    );
    await pumpTimelineVertical(tester, entries: [entry], targetRank: 5);
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(find.byTooltip('刻晴'), findsWidgets);
    expect(
      find.byTooltip('刻晴 · ${l.luckTierLucky} · ${l.timelineSinceLast(40)}'),
      findsNothing,
    );
  });

  testWidgets('showLuckLegend 時顯示圖例', (tester) async {
    await pumpTimelineVertical(
      tester,
      entries: const [],
      targetRank: 5,
      nowPulls: 10,
      showLuckLegend: true,
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(find.text(l.luckTierLucky), findsOneWidget);
  });

  testWidgets('on phones a tap on the node or the date shows the name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          targetRank: 5,
        ),
      ),
    );
    final tips = find.descendant(
      of: find.byType(TimelineVertical),
      matching: find.byType(Tooltip),
    );
    for (final tip in [tips.first, tips.last]) {
      await tester.tap(tip);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('夜蘭'), findsNWidgets(2));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('showLuckLegend 時沒有記錄也沒有「現在」仍顯示圖例', (tester) async {
    await pumpTimelineVertical(
      tester,
      entries: const [],
      targetRank: 5,
      showLuckLegend: true,
    );
    expect(find.byType(LuckLegend), findsOneWidget);
  });

  for (final fillHeight in [false, true]) {
    testWidgets('vertical timeline geometry is unchanged by the refactor '
        '(fillHeight: $fillHeight)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => SizedBox(
            height: fillHeight ? 700 : null,
            child: TimelineVertical(
              entries: [
                _e('夜蘭', '301', 87, DateTime(2026, 1, 5)),
                _e('流浪者', '301', 74, DateTime(2026, 1, 2)),
                _e('納西妲', '301', 40, DateTime(2025, 12, 20)),
                _e('魈', '200', 90, DateTime(2025, 11, 30)),
                _e('刻晴', '302', 62, DateTime(2025, 11, 3)),
              ],
              colors: colors,
              targetRank: 5,
              nowPulls: 28,
              isAcrossBanners: true,
              showLuckLegend: true,
              fillHeight: fillHeight,
            ),
          ),
        ),
      );
      await tester.pump();
      final actual = timelineGeometry(
        tester,
        find.byType(TimelineVertical),
        exclude: find.byType(LuckLegend),
      );
      // 數值錄自重構前的原程式；圖例（Task 3 會改）不列入。
      expect(actual, <(String, Rect)>[
        ('Now', const Rect.fromLTRB(131.0, 19.0, 173.75, 39.0)),
        (
          '28 pulls since last 5★ across banners',
          const Rect.fromLTRB(131.0, 41.0, 583.0, 75.0),
        ),
        ('01 / 2026', const Rect.fromLTRB(17.0, 103.0, 89.0, 119.0)),
        ('夜蘭', const Rect.fromLTRB(131.0, 101.0, 159.5, 121.0)),
        (
          '01/05 · Character Event Wish · 87 pulls',
          const Rect.fromLTRB(131.0, 123.0, 583.0, 157.0),
        ),
        ('流浪者', const Rect.fromLTRB(131.0, 171.0, 173.75, 191.0)),
        (
          '01/02 · Character Event Wish · 74 pulls',
          const Rect.fromLTRB(131.0, 193.0, 583.0, 227.0),
        ),
        ('12 / 2025', const Rect.fromLTRB(17.0, 255.0, 89.0, 271.0)),
        ('納西妲', const Rect.fromLTRB(131.0, 253.0, 173.75, 273.0)),
        (
          '12/20 · Character Event Wish · 40 pulls',
          const Rect.fromLTRB(131.0, 275.0, 583.0, 309.0),
        ),
        ('11 / 2025', const Rect.fromLTRB(17.0, 337.0, 89.0, 353.0)),
        ('魈', const Rect.fromLTRB(131.0, 335.0, 145.25, 355.0)),
        (
          '11/30 · Standard Wish · 90 pulls',
          const Rect.fromLTRB(131.0, 357.0, 523.0, 374.0),
        ),
        ('刻晴', const Rect.fromLTRB(131.0, 388.0, 159.5, 408.0)),
        (
          '11/03 · Weapon Event Wish · 62 pulls',
          const Rect.fromLTRB(131.0, 410.0, 572.0, 427.0),
        ),
        ('node', const Rect.fromLTRB(97.0, 17.0, 119.0, 39.0)),
        ('node', const Rect.fromLTRB(97.0, 99.0, 119.0, 121.0)),
        ('node', const Rect.fromLTRB(97.0, 169.0, 119.0, 191.0)),
        ('node', const Rect.fromLTRB(97.0, 251.0, 119.0, 273.0)),
        ('node', const Rect.fromLTRB(97.0, 333.0, 119.0, 355.0)),
        ('node', const Rect.fromLTRB(97.0, 386.0, 119.0, 408.0)),
        // 卡片外框；fillHeight 時撐滿測試畫面高 600。
        ('border', Rect.fromLTRB(0, 0, 600, fillHeight ? 600 : 480)),
      ]);
    });
  }
}
