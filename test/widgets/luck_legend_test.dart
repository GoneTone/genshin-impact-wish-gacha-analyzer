import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';

void main() {
  testWidgets('LuckLegend 顯示三個分級標籤', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: LuckLegend()),
      ),
    );
    await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.luckTierLucky), findsOneWidget);
    expect(find.text(l.luckTierAverage), findsOneWidget);
    expect(find.text(l.luckTierUnlucky), findsOneWidget);
  });
}
