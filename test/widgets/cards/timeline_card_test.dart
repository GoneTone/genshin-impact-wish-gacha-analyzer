import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_card.dart';

WishRecord _r({
  required String id,
  required int rank,
  required String name,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  Widget _wrap(Widget child) => MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SizedBox(width: 1000, height: 220, child: child)),
      );

  testWidgets('empty list shows no-records message', (tester) async {
    await tester.pumpWidget(_wrap(const TimelineCard(records: <WishRecord>[])));
    // Localized string for emptiness
    expect(find.byType(TimelineCard), findsOneWidget);
  });

  testWidgets('renders one chip per 5★ record', (tester) async {
    final records = [
      _r(id: '5', rank: 5, name: '夜蘭', time: DateTime(2025, 4, 1)),
      _r(id: '4', rank: 4, name: '煙緋', time: DateTime(2025, 3, 28)),
      _r(id: '3', rank: 3, name: 'x', time: DateTime(2025, 3, 27)),
      _r(id: '2', rank: 5, name: '流浪者', time: DateTime(2025, 3, 1)),
      _r(id: '1', rank: 3, name: 'y', time: DateTime(2025, 2, 1)),
    ];
    await tester.pumpWidget(_wrap(TimelineCard(records: records)));
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
    expect(find.text('煙緋'), findsNothing); // 4★ does not appear
  });
}
