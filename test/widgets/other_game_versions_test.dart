import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/other_game_versions.dart';

/// 將 [OtherGameVersions] 包進英文語系的 [MaterialApp]，套用提供 `theme.gacha`
/// 的暗色主題。
Widget _wrap() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  theme: buildDarkTheme(),
  home: const Scaffold(body: OtherGameVersions()),
);

void main() {
  testWidgets('renders title, Wuthering Waves link, future note and icon', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('Versions for Other Games'), findsOneWidget);
    expect(find.text('Wuthering Waves'), findsOneWidget);
    expect(
      find.text('More games may be supported in the future...'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('Wuthering Waves link points to the related project url', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    final link = tester.widget<AppLink>(
      find.ancestor(
        of: find.text('Wuthering Waves'),
        matching: find.byType(AppLink),
      ),
    );
    expect(link.url, RelatedProjects.wutheringWavesAnalyzer);
  });

  testWidgets('game name wraps instead of overflowing on a narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: buildDarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(width: 120, child: OtherGameVersions()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
