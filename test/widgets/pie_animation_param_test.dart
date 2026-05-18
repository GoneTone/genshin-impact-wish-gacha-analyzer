import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';

const _stats = GachaStats(
  total: 10,
  fiveStarCount: 1,
  fourStarCount: 3,
  threeStarCount: 6,
  twoStarCount: 0,
  byItemType: {'角色': 4, '武器': 6},
);

Widget _host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Scaffold(body: SizedBox(width: 240, height: 240, child: child)),
);

void main() {
  testWidgets('RarityPie 接受 animationDuration: zero 並可立即 settle', (t) async {
    await t.pumpWidget(
      _host(const RarityPie(stats: _stats, animationDuration: Duration.zero)),
    );
    await t.pump();
    expect(find.byType(RarityPie), findsOneWidget);
  });

  testWidgets('ItemTypePie 接受 animationDuration: zero', (t) async {
    await t.pumpWidget(
      _host(const ItemTypePie(stats: _stats, animationDuration: Duration.zero)),
    );
    await t.pump();
    expect(find.byType(ItemTypePie), findsOneWidget);
  });
}
