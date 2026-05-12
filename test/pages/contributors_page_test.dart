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

  testWidgets('專案負責人 SectionCard 顯示 GoneTone 並包成 InkWell', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('GoneTone'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('GoneTone'), matching: find.byType(InkWell)),
      findsOneWidget,
    );
  });

  testWidgets('測試人員 SectionCard 顯示兩位 testers', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('世界へいわ'), findsWidgets);
    expect(find.text('Zhi'), findsOneWidget);
  });

  testWidgets('翻譯審稿人 SectionCard 顯示三人；pan93412 / Lemon7777 為純文字（無 url）', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('pan93412'), findsOneWidget);
    expect(find.text('Lemon7777'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('pan93412'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('Lemon7777'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('GitHub 貢獻者 SectionCard 顯示完整 URL', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors',
      ),
      findsOneWidget,
    );
  });

  testWidgets('已翻譯語言 SectionCard 顯示繁體中文 / 簡體中文 / English', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.textContaining('English'), findsWidgets);
  });

  testWidgets('已翻譯語言 SectionCard 含協助翻譯說明與 Crowdin 連結', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒有您的語言嗎'), findsOneWidget);
    expect(
      find.text(
        'https://crowdin.com/project/genshin-impact-wish-gacha-analyzer',
      ),
      findsOneWidget,
    );
  });

  testWidgets('專案授權 SectionCard 顯示「MIT License」', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('MIT License'), findsOneWidget);
  });
}
