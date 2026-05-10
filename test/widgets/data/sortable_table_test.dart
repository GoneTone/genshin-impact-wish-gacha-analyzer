import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';

WishRecord _r({required String id, required int rank, required String name}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: DateTime(2025, 1, int.parse(id)),
      lang: 'zh-tw',
    );

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 1200, child: child)),
  ),
);

void main() {
  testWidgets('renders rows, rarity pills, totalIndex/pity columns', (
    tester,
  ) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    final rows = buildRecordRows(records);
    await tester.pumpWidget(
      _wrap(SortableTable(rows: rows, sort: null, onSortColumnTapped: (_) {})),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    // totalIndex 顯示（rows desc by time → id 5 是最新 → totalIndex=3）
    expect(find.text('3'), findsWidgets); // totalIndex of A
    expect(find.text('1'), findsWidgets); // totalIndex of C
  });

  testWidgets('paginates with 20 per page (always shows dropdown)', (
    tester,
  ) async {
    final records = List.generate(
      45,
      (i) => _r(id: '${i + 1}', rank: 4, name: 'r$i'),
    );
    final rows = buildRecordRows(records);
    await tester.pumpWidget(
      _wrap(SortableTable(rows: rows, sort: null, onSortColumnTapped: (_) {})),
    );
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect(dropdown.items, hasLength(3));
    expect(dropdown.value, 0);
  });

  testWidgets('表頭點擊呼叫 onSortColumnTapped(對應欄)', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records);
    SortColumn? tapped;
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: null,
          onSortColumnTapped: (c) => tapped = c,
        ),
      ),
    );
    await tester.tap(find.text('時間'));
    expect(tapped, SortColumn.time);

    await tester.tap(find.text('名稱'));
    expect(tapped, SortColumn.name);

    await tester.tap(find.text('總抽數'));
    expect(tapped, SortColumn.totalIndex);

    await tester.tap(find.text('保底內'));
    expect(tapped, SortColumn.fiveStarPity);
  });

  testWidgets('當前排序欄顯示 arrow_downward；其他欄維持 unfold_more', (tester) async {
    final records = [_r(id: '1', rank: 5, name: 'A')];
    final rows = buildRecordRows(records);
    await tester.pumpWidget(
      _wrap(
        SortableTable(
          rows: rows,
          sort: const TableSort(
            column: SortColumn.rarity,
            direction: SortDirection.desc,
          ),
          onSortColumnTapped: (_) {},
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    // 其餘 5 個欄位都顯示 unfold_more
    expect(find.byIcon(Icons.unfold_more), findsNWidgets(5));
  });
}
