// test/pages/contributors_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/contributors_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('PageHeader 顯示 contributorsTitle', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('貢獻名單'), findsOneWidget);
  });

  testWidgets('渲染 6 張 SectionCard 標題', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('專案負責人'), findsOneWidget);
    expect(find.text('測試人員'), findsOneWidget);
    expect(find.text('GitHub 貢獻者'), findsOneWidget);
    expect(find.text('翻譯審稿人'), findsOneWidget);
    expect(find.text('已翻譯語言'), findsOneWidget);
    expect(find.text('專案授權'), findsOneWidget);
  });
}
