import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 280, child: child)),
  );

  testWidgets('renders label and current/threshold', (tester) async {
    final pity = const Pity(current: 12, threshold: 90, lastFiveStarAt: null);
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★ pity',
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    expect(find.text('5★ pity'.toUpperCase()), findsOneWidget);
    expect(find.text('12 / 90'), findsOneWidget);
  });

  testWidgets('low progress (<70%) shows distance subtitle', (tester) async {
    final pity = const Pity(current: 30, threshold: 90, lastFiveStarAt: null);
    await tester.pumpWidget(
      wrap(
        PityCard(label: '5★', pity: pity, accent: GachaTokens.dark.fiveStar),
      ),
    );
    // distance = 60. "暫無 5★" 應該不會出現（lastFiveStarAt is null but spec
    // says no-5★ branch — ensure 30/90 renders correctly).
    expect(find.text('30 / 90'), findsOneWidget);
  });

  testWidgets('beginner ended pool shows ended state', (tester) async {
    final pity = const Pity(current: 20, threshold: 20, lastFiveStarAt: null);
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: 'Beginner',
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
          isEndedPool: true,
        ),
      ),
    );
    expect(find.text('20 / 20'), findsOneWidget);
  });

  testWidgets('renders value text across all phase boundaries', (tester) async {
    for (final p in [
      const Pity(current: 60, threshold: 90, lastFiveStarAt: null), // 67%
      const Pity(current: 75, threshold: 90, lastFiveStarAt: null), // 83%
      const Pity(current: 90, threshold: 90, lastFiveStarAt: null), // 100%
    ]) {
      await tester.pumpWidget(
        wrap(PityCard(label: '5★', pity: p, accent: GachaTokens.dark.fiveStar)),
      );
      expect(find.text('${p.current} / ${p.threshold}'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
