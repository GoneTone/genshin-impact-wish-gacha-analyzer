import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

GachaRecord _r({required String id, required int rank, required String name}) =>
    GachaRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: '角色',
      rankType: rank,
      time: DateTime(2025, 1, int.parse(id)),
      lang: 'zh-tw',
    );

/// 建立含 [UncontrolledProviderScope] 的測試包裝 widget。
Widget _wrap(
  Widget child, {
  Locale locale = const Locale('zh'),
  required ProviderContainer container,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 1200, child: child)),
    ),
  ),
);

/// 以指定寬度包住 [child]（測試卡片列與表格的切換）。
Widget _wrapWidth(
  Widget child, {
  required double width,
  required ProviderContainer container,
  Locale locale = const Locale('zh'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  ),
);

/// 建立測試用 [ProviderContainer]，override 需要 main() 注入的 provider。
ProviderContainer _makeContainer(Directory tempDir) => ProviderContainer(
  overrides: [
    hoyowikiIndexStorageProvider.overrideWithValue(
      HoYoWikiIndexStorage(tempDir),
    ),
    hoyowikiCacheDirProvider.overrideWithValue(tempDir),
  ],
);

/// 建立指定欄位的 [RecordRow]（直接構造，略過 [buildRecordRows] 累計邏輯）。
RecordRow makeRow({
  required String gachaType,
  required int rankType,
  required int mainPityIndex,
  int totalIndex = 1,
}) => RecordRow(
  record: GachaRecord(
    id: '1',
    uid: '1',
    gachaType: gachaType,
    name: 'TestItem',
    itemType: '角色',
    rankType: rankType,
    time: DateTime(2025, 1, 1),
    lang: 'zh-tw',
  ),
  totalIndex: totalIndex,
  mainPityIndex: mainPityIndex,
  itemTypeKey: 'kind:character',
);

/// 將 [SortableTable] 搭配給定的 [rows] 和 [mainRank] pump 進測試環境。
Future<void> pumpSortableTable(
  WidgetTester tester, {
  required List<RecordRow> rows,
  required int mainRank,
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    _wrap(
      SortableTable(
        rows: rows,
        sort: null,
        mainRank: mainRank,
        onSortColumnTapped: (_) {},
      ),
      container: container,
    ),
  );
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sortable_table_test_');
    container = _makeContainer(tempDir);
  });

  tearDown(() async {
    container.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('ja locale → rank cell uses ★N order (pill + plain)', (
    tester,
  ) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'), // accent != null → _Pill
      _r(id: '4', rank: 4, name: 'B'), // accent != null → _Pill
      _r(id: '3', rank: 3, name: 'C'), // accent == null → 純 Text 分支
    ];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        locale: const Locale('ja'),
        container: container,
      ),
    );
    expect(find.text('★5'), findsOneWidget);
    expect(find.text('★4'), findsOneWidget);
    expect(find.text('★3'), findsOneWidget);
    expect(find.text('5★'), findsNothing);
    expect(find.text('4★'), findsNothing);
    expect(find.text('3★'), findsNothing);
  });

  testWidgets('renders rows, rarity pills, totalIndex/pity columns', (
    tester,
  ) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        container: container,
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    // totalIndex 顯示（rows desc by time → id 5 是最新 → totalIndex=3）
    expect(find.text('3'), findsWidgets); // totalIndex of A
    expect(find.text('1'), findsWidgets); // totalIndex of C
  });

  testWidgets('paginates with 20 per page (page button shows 1 / 3)', (
    tester,
  ) async {
    final records = List.generate(
      45,
      (i) => _r(id: '${i + 1}', rank: 4, name: 'r$i'),
    );
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        container: container,
      ),
    );
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('page survives being scrolled out of a lazy list', (
    tester,
  ) async {
    final records = List.generate(
      45,
      (i) => _r(id: '${i + 1}', rank: 4, name: 'r$i'),
    );
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    const listKey = Key('outer');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              key: listKey,
              children: [
                SortableTable(
                  rows: rows,
                  sort: null,
                  mainRank: 5,
                  onSortColumnTapped: (_) {},
                ),
                const SizedBox(height: 5000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Pager>(find.byType(Pager)).page, 1);

    await tester.drag(find.byKey(listKey), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.byType(Pager), findsNothing);
    await tester.drag(find.byKey(listKey), const Offset(0, 6000));
    await tester.pumpAndSettle();

    expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
  });

  testWidgets('表頭點擊呼叫 onSortColumnTapped(對應欄)', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    SortColumn? tapped;
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (c) => tapped = c,
        ),
        container: container,
      ),
    );
    await tester.tap(find.text('時間'));
    expect(tapped, SortColumn.time);

    await tester.tap(find.text('名稱'));
    expect(tapped, SortColumn.name);

    await tester.tap(find.text('總抽數'));
    expect(tapped, SortColumn.totalIndex);

    await tester.tap(find.text('保底內'));
    expect(tapped, SortColumn.mainPity);
  });

  testWidgets('當前排序欄顯示 arrow_downward；其他欄維持 unfold_more', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: const TableSort(
            column: SortColumn.rarity,
            direction: SortDirection.desc,
          ),
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        container: container,
      ),
    );
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    // 其餘 5 個欄位都顯示 unfold_more
    expect(find.byIcon(Icons.unfold_more), findsNWidgets(5));
  });

  testWidgets('類型欄顯示 itemTypeKeyLabel 結果（fallback 原始字串）', (tester) async {
    // _r 產的 record.itemType = '角色'；empty index → itemTypeKey = '角色'（fallback）
    // itemTypeKeyLabel('角色', l) 原樣回傳 '角色'
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        container: container,
      ),
    );
    // 類型欄應顯示 itemTypeKeyLabel(row.itemTypeKey='角色', l) = '角色'
    expect(find.text('角色'), findsOneWidget);
  });

  testWidgets('每列名稱欄前顯示 GachaItemIcon', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
        container: container,
      ),
    );

    // 三筆 record → 三個 GachaItemIcon
    expect(find.byType(GachaItemIcon), findsNWidgets(3));
  });

  testWidgets('保底內欄依抽數呈歐非色', (tester) async {
    // 角色池（301）5★：85 抽 → 85/90 ≈ 0.944 > 0.8 → 非（stateDanger）
    await pumpSortableTable(
      tester,
      rows: [makeRow(gachaType: '301', rankType: 5, mainPityIndex: 85)],
      mainRank: 5,
      container: container,
    );
    final tokens = buildDarkTheme().gacha;
    final text = tester.widget<Text>(find.text('85'));
    expect(text.style?.color, tokens.stateDanger);
  });

  group('narrow layout', () {
    /// 45 筆記錄（第 5、20 筆為 5★），時間遞增。
    List<RecordRow> rows45({String Function(int i)? nameOf}) {
      final records = [
        for (var i = 45; i >= 1; i--)
          GachaRecord(
            id: '$i',
            uid: '1',
            gachaType: '301',
            name: nameOf?.call(i) ?? 'N$i',
            itemType: '角色',
            rankType: i == 5 || i == 20 ? 5 : 3,
            time: DateTime(2025, 1, 1).add(Duration(days: i)),
            lang: 'zh-tw',
          ),
      ];
      return buildRecordRows(records, index: const HoYoWikiIndex.empty());
    }

    Future<AppLocalizations> pumpTable(
      WidgetTester tester, {
      required double width,
      TableSort? sort,
      ValueChanged<SortColumn>? onTap,
      Locale locale = const Locale('zh'),
      List<RecordRow>? rows,
      bool showSortButton = true,
      ValueChanged<int>? onPageChanged,
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrapWidth(
          SortableTable(
            rows: rows ?? rows45(),
            sort: sort,
            mainRank: 5,
            onSortColumnTapped: onTap ?? (_) {},
            showSortButton: showSortButton,
            onPageChanged: onPageChanged,
          ),
          width: width,
          container: container,
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(SortableTable)))!;
    }

    testWidgets('narrow width shows record cards instead of the table', (
      tester,
    ) async {
      final l = await pumpTable(tester, width: 360);
      expect(find.text(l.tableTotalIndex), findsNothing);
      expect(find.text('N45'), findsOneWidget);
      expect(find.textContaining('#45', findRichText: true), findsOneWidget);
      for (final card in tester.widgetList(find.byType(GachaItemTapTarget))) {
        expect(
          tester.getSize(find.byWidget(card)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('record cards show the item type like the table', (
      tester,
    ) async {
      // 排序選單可以依類型排序，卡片上就要看得到類型（和桌面表格一致）。
      await pumpTable(tester, width: 360);
      final card = find.ancestor(
        of: find.text('N45'),
        matching: find.byType(GachaItemTapTarget),
      );
      expect(
        find.descendant(of: card, matching: find.text('角色')),
        findsOneWidget,
      );
    });

    testWidgets('long press on a card explains the pity count', (tester) async {
      // 桌面表頭有保底說明，卡片沒有表頭，要在卡片上看得到。
      final l = await pumpTable(tester, width: 360);
      await tester.longPress(find.textContaining('#45', findRichText: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(l.tableMainPityTooltip(l.rarityStar(5))),
        findsOneWidget,
      );
    });

    testWidgets('wide width keeps the table', (tester) async {
      final l = await pumpTable(tester, width: 900);
      expect(find.text(l.tableTotalIndex), findsOneWidget);
    });

    testWidgets('sort sheet calls cycleSort with the tapped column', (
      tester,
    ) async {
      SortColumn? tapped;
      final l = await pumpTable(tester, width: 360, onTap: (c) => tapped = c);
      await tester.tap(find.text(l.tableSortDefault));
      await tester.pumpAndSettle();
      expect(find.text(l.tableSortSheetTitle), findsOneWidget);
      for (final label in [
        l.tableTime,
        l.tableName,
        l.tableKind,
        l.tableRarity,
        l.tableTotalIndex,
        l.tableMainPity,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text(l.tableName));
      await tester.pumpAndSettle();
      expect(tapped, SortColumn.name);
      expect(find.text(l.tableSortSheetTitle), findsNothing);
    });

    testWidgets('sort sheet opens above the whole app, not the page', (
      tester,
    ) async {
      // 頁面在外殼的內層導覽器裡；開在內層會被外殼的底部狀態列蓋住。
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final inner = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Navigator(
                key: inner,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: SingleChildScrollView(
                      child: SortableTable(
                        rows: rows45(),
                        sort: null,
                        mainRank: 5,
                        onSortColumnTapped: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = AppLocalizations.of(
        tester.element(find.byType(SortableTable)),
      )!;
      await tester.tap(find.text(l.tableSortDefault));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(inner),
          matching: find.byType(BottomSheet),
        ),
        findsNothing,
      );
    });

    testWidgets('sort button shows the current column and direction', (
      tester,
    ) async {
      final l = await pumpTable(
        tester,
        width: 360,
        sort: const TableSort(
          column: SortColumn.time,
          direction: SortDirection.desc,
        ),
      );
      expect(find.text(l.tableSortButton('${l.tableTime} ↓')), findsOneWidget);
    });

    testWidgets('tapping a card opens item detail', (tester) async {
      await pumpTable(tester, width: 360);
      expect(
        find.ancestor(
          of: find.text('N45'),
          matching: find.byType(GachaItemTapTarget),
        ),
        findsOneWidget,
      );
    });

    testWidgets('switching between cards and table keeps the page', (
      tester,
    ) async {
      final rows = rows45();
      await pumpTable(tester, width: 360, rows: rows);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
      await tester.pumpWidget(
        _wrapWidth(
          SortableTable(
            rows: rows,
            sort: null,
            mainRank: 5,
            onSortColumnTapped: (_) {},
          ),
          width: 900,
          container: container,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
    });

    for (final locale in [const Locale('en'), const Locale('ja')]) {
      testWidgets(
        'cards do not overflow with long names and large text (${locale.languageCode})',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpTable(
            tester,
            width: 360,
            locale: locale,
            rows: rows45(nameOf: (_) => 'Mistsplitter Reforged'),
          );
          expect(tester.takeException(), isNull);
          final name = tester.widget<Text>(
            find.text('Mistsplitter Reforged').first,
          );
          expect(name.overflow, TextOverflow.ellipsis);
        },
      );
    }
  });

  group('record list cards and page change', () {
    /// 回傳 [recordListUsesCards] 在目前視窗與 [width] 下的結果。
    Future<bool> usesCards(WidgetTester tester, Size view, double width) async {
      tester.view.physicalSize = view;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = recordListUsesCards(context, width);
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('phone landscape uses cards even when wide', (tester) async {
      expect(await usesCards(tester, const Size(800, 360), 776), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('desktop wide window keeps the table', (tester) async {
      expect(await usesCards(tester, const Size(1200, 800), 900), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('desktop narrow width uses cards', (tester) async {
      expect(await usesCards(tester, const Size(1200, 800), 500), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    /// 45 筆記錄分 3 頁、寬 360 的卡片列表格。
    Future<void> pumpPaged(
      WidgetTester tester, {
      ValueChanged<int>? onPageChanged,
      bool showSortButton = true,
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final records = [
        for (var i = 45; i >= 1; i--)
          GachaRecord(
            id: '$i',
            uid: '1',
            gachaType: '301',
            name: 'N$i',
            itemType: '角色',
            rankType: 3,
            time: DateTime(2025, 1, 1).add(Duration(days: i)),
            lang: 'zh-tw',
          ),
      ];
      await tester.pumpWidget(
        _wrapWidth(
          SortableTable(
            rows: buildRecordRows(records, index: const HoYoWikiIndex.empty()),
            sort: null,
            mainRank: 5,
            onSortColumnTapped: (_) {},
            showSortButton: showSortButton,
            onPageChanged: onPageChanged,
          ),
          width: 360,
          container: container,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('onPageChanged receives the new page', (tester) async {
      final pages = <int>[];
      await pumpPaged(tester, onPageChanged: pages.add);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.last_page));
      await tester.pumpAndSettle();
      expect(pages, [1, 2]);
    });

    testWidgets('onPageChanged is silent when the page stays the same', (
      tester,
    ) async {
      final pages = <int>[];
      await pumpPaged(tester, onPageChanged: pages.add);
      await tester.tap(find.byIcon(Icons.first_page), warnIfMissed: false);
      await tester.ensureVisible(find.text('1 / 3'));
      await tester.tap(find.text('1 / 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(pages, isEmpty);
    });

    testWidgets('jumping via the dialog fires onPageChanged', (tester) async {
      final pages = <int>[];
      await pumpPaged(tester, onPageChanged: pages.add);
      await tester.ensureVisible(find.text('1 / 3'));
      await tester.tap(find.text('1 / 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(pages, [2]);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('showSortButton false hides the sort button', (tester) async {
      await pumpPaged(tester, showSortButton: false);
      expect(find.byType(RecordSortButton), findsNothing);
    });

    testWidgets('showSortButton defaults to showing it in card mode', (
      tester,
    ) async {
      await pumpPaged(tester);
      expect(find.byType(RecordSortButton), findsOneWidget);
    });
  });
}
