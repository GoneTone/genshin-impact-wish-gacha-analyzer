import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 1000, child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders rows and rarity pills', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'),
      _r(id: '4', rank: 4, name: 'B'),
      _r(id: '3', rank: 3, name: 'C'),
    ];
    await tester.pumpWidget(_wrap(SortableTable(records: records)));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
  });

  testWidgets('paginates with 20 per page', (tester) async {
    final records = List.generate(
      45,
      (i) => _r(id: '$i', rank: 4, name: 'r$i'),
    );
    await tester.pumpWidget(_wrap(SortableTable(records: records)));
    expect(find.text('1 / 3'), findsOneWidget);
  });
}
