import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

GachaRecord _r(String id, String name, DateTime time) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: '角色',
  rankType: 5,
  time: time,
  lang: 'zh-tw',
);

Future<ProviderContainer> _container(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('five_star_overview_test_');
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
  return container;
}

Widget _wrap(ProviderContainer c, Widget child) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: buildDarkTheme(),
    home: Scaffold(body: SizedBox(width: 800, child: child)),
  ),
);

void main() {
  const emptyIndex = HoYoWikiIndex.empty();

  testWidgets('空清單 → SizedBox.shrink，不顯示任何 chip', (tester) async {
    final c = await _container(tester);
    await tester.pumpWidget(_wrap(c, const FiveStarOverview(items: [])));
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsNothing);
    expect(find.byType(GachaItemIcon), findsNothing); // 空清單不繪任何 chip
  });

  testWidgets('顯示每個物品的次數徽章', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
      _r('2', 'A', DateTime(2025, 1, 2)),
      _r('3', 'B', DateTime(2025, 1, 3)),
    ], index: emptyIndex);
    await tester.pumpWidget(_wrap(c, FiveStarOverview(items: items)));
    await tester.pump();
    expect(find.text('2'), findsOneWidget); // A 抽到 2 次
    expect(find.text('1'), findsOneWidget); // B 抽到 1 次
  });

  testWidgets('次數徽章在結束側：由左往右在右下、由右往左在左下', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        _wrap(
          c,
          Directionality(
            textDirection: direction,
            child: FiveStarOverview(items: items),
          ),
        ),
      );
      await tester.pump();
      final badgeX = tester.getCenter(find.text('1')).dx;
      final iconX = tester.getCenter(find.byType(GachaItemIcon)).dx;
      expect(
        badgeX > iconX,
        direction == TextDirection.ltr,
        reason: '$direction',
      );
    }
  });

  testWidgets('interactive=false → 不掛 GachaItemTapTarget', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    await tester.pumpWidget(
      _wrap(c, FiveStarOverview(items: items, interactive: false)),
    );
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsNothing);
  });

  testWidgets('interactive=true → 掛 GachaItemTapTarget', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    await tester.pumpWidget(_wrap(c, FiveStarOverview(items: items)));
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsOneWidget);
  });

  testWidgets('five-star item tooltip appears on long press', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    await tester.pumpWidget(_wrap(c, FiveStarOverview(items: items)));
    await tester.pump();
    await tester.longPress(find.byType(GachaItemIcon));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('SliverFiveStarOverview', () {
    List<FiveStarCollectionItem> manyItems(int n) => buildFiveStarCollection([
      for (var i = 0; i < n; i++)
        _r(
          '${5000 + i}',
          'Item $i',
          DateTime(2025, 1, 1).add(Duration(days: i)),
        ),
    ], index: emptyIndex);

    Widget host(ProviderContainer c, Widget child, {double height = 2000}) =>
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 400, height: height, child: child),
              ),
            ),
          ),
        );

    List<Offset> iconOffsets(WidgetTester tester) => [
      for (final e in find.byType(GachaItemIcon).evaluate())
        tester.getTopLeft(find.byWidget(e.widget)),
    ];

    testWidgets('lays chips out exactly like the wrap version', (tester) async {
      final c = await _container(tester);
      final items = manyItems(20);
      await tester.pumpWidget(
        host(c, SingleChildScrollView(child: FiveStarOverview(items: items))),
      );
      await tester.pump();
      final wrapOffsets = iconOffsets(tester);

      await tester.pumpWidget(
        host(
          c,
          CustomScrollView(slivers: [SliverFiveStarOverview(items: items)]),
        ),
      );
      await tester.pump();

      expect(wrapOffsets, hasLength(20));
      expect(iconOffsets(tester), wrapOffsets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling does not rebuild rows already on screen', (
      tester,
    ) async {
      final c = await _container(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          c,
          CustomScrollView(
            controller: controller,
            slivers: [SliverFiveStarOverview(items: manyItems(300))],
          ),
          height: 400,
        ),
      );
      await tester.pump();
      final rowBefore = tester.widget(find.byType(Row).at(1));

      controller.jumpTo(10);
      await tester.pump();

      expect(tester.widget(find.byType(Row).at(1)), same(rowBefore));
    });

    testWidgets('builds rows on demand', (tester) async {
      final c = await _container(tester);
      await tester.pumpWidget(
        host(
          c,
          CustomScrollView(
            slivers: [SliverFiveStarOverview(items: manyItems(300))],
          ),
          height: 200,
        ),
      );
      await tester.pump();
      expect(
        find.byType(GachaItemIcon, skipOffstage: false).evaluate().length,
        lessThan(100),
      );
    });
  });
}
