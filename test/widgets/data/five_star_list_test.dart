import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/five_star_list.dart';

WishRecord _r({
  required String id,
  required int rank,
  required String name,
  required String gachaType,
  DateTime? time,
}) =>
    WishRecord(
      id: id,
      uid: '1',
      gachaType: gachaType,
      name: name,
      itemType: '角色',
      kind: WishItemKind.character,
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  Widget wrap(Widget child, {double width = 800}) => MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: width, height: 600, child: child),
        ),
      );

  testWidgets('shows empty state when no 5★', (tester) async {
    await tester.pumpWidget(wrap(const FiveStarList(banners: <String, List<WishRecord>>{})));
    expect(find.byType(FiveStarList), findsOneWidget);
  });

  testWidgets('renders 5★ across banners', (tester) async {
    final banners = <String, List<WishRecord>>{
      '301': [
        _r(id: '301-2', rank: 5, name: '夜蘭', gachaType: '301', time: DateTime(2025, 4, 1)),
        _r(id: '301-1', rank: 4, name: 'x', gachaType: '301', time: DateTime(2025, 3, 1)),
      ],
      '302': [
        _r(id: '302-1', rank: 5, name: '若水', gachaType: '302', time: DateTime(2025, 3, 15)),
      ],
    };
    await tester.pumpWidget(wrap(FiveStarList(banners: banners)));
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('若水'), findsOneWidget);
  });

  testWidgets('renders 5★ when only one banner has data', (tester) async {
    final banners = <String, List<WishRecord>>{
      '301': [_r(id: '1', rank: 5, name: 'A', gachaType: '301')],
    };
    await tester.pumpWidget(wrap(FiveStarList(banners: banners)));
    expect(find.byType(FiveStarList), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  test('FiveStarListColors.colorFor maps known gachaTypes', () {
    final tokens = const FiveStarListColors(
      character: Color(0xFF000001),
      weapon: Color(0xFF000002),
      chronicled: Color(0xFF000003),
      standard: Color(0xFF000004),
      beginner: Color(0xFF000005),
      fallback: Color(0xFF000000),
    );
    expect(tokens.colorFor('301'), const Color(0xFF000001));
    expect(tokens.colorFor('302'), const Color(0xFF000002));
    expect(tokens.colorFor('500'), const Color(0xFF000003));
    expect(tokens.colorFor('200'), const Color(0xFF000004));
    expect(tokens.colorFor('100'), const Color(0xFF000005));
    expect(tokens.colorFor('999'), const Color(0xFF000000));
  });
}
