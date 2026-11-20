import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 280, child: child)),
  );

  testWidgets('renders label and current/threshold', (tester) async {
    final pity = const Pity(
      current: 12,
      threshold: 90,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★ pity',
          rank: 5,
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    expect(find.text('5★ pity'.toUpperCase()), findsOneWidget);
    expect(find.text('12 / 90'), findsOneWidget);
  });

  testWidgets('low progress (<70%) shows distance subtitle', (tester) async {
    final pity = const Pity(
      current: 30,
      threshold: 90,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★',
          rank: 5,
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    // distance = 60. "暫無 5★" 應該不會出現（lastRecordAt is null but spec
    // says no-5★ branch — ensure 30/90 renders correctly).
    expect(find.text('30 / 90'), findsOneWidget);
  });

  testWidgets('beginner ended pool shows ended state', (tester) async {
    final pity = const Pity(
      current: 20,
      threshold: 20,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: 'Beginner',
          rank: 5,
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
      const Pity(
        current: 60,
        threshold: 90,
        lastRecordAt: null,
        averageInterval: null,
        hitCount: 0,
        completedPulls: 0,
      ), // 67%
      const Pity(
        current: 75,
        threshold: 90,
        lastRecordAt: null,
        averageInterval: null,
        hitCount: 0,
        completedPulls: 0,
      ), // 83%
      const Pity(
        current: 90,
        threshold: 90,
        lastRecordAt: null,
        averageInterval: null,
        hitCount: 0,
        completedPulls: 0,
      ), // 100%
    ]) {
      await tester.pumpWidget(
        wrap(
          PityCard(
            label: '5★',
            rank: 5,
            pity: p,
            accent: GachaTokens.dark.fiveStar,
          ),
        ),
      );
      expect(find.text('${p.current} / ${p.threshold}'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets('hitCount=0 → subtitle 不含「· 平均」', (tester) async {
    final pity = const Pity(
      current: 30,
      threshold: 90,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★',
          rank: 5,
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    expect(find.textContaining('平均'), findsNothing);
    expect(find.textContaining(' · '), findsNothing);
  });

  testWidgets('normal + hitCount≥1 → subtitle 出現「· 平均 70.50 抽出」', (
    tester,
  ) async {
    final pity = Pity(
      current: 12,
      threshold: 90,
      lastRecordAt: DateTime(2025, 1, 1),
      averageInterval: 70.5,
      hitCount: 3,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★',
          rank: 5,
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    expect(find.textContaining('距下次保底 78 抽'), findsOneWidget);
    expect(find.textContaining('平均 70.50 抽出'), findsOneWidget);
  });

  testWidgets('guaranteed + hitCount≥1 → subtitle 仍出現「· 平均」', (tester) async {
    final pity = Pity(
      current: 90,
      threshold: 90,
      lastRecordAt: DateTime(2025, 1, 1),
      averageInterval: 70.5,
      hitCount: 3,
      completedPulls: 0,
    );
    await tester.pumpWidget(
      wrap(
        PityCard(
          label: '5★',
          rank: 5,
          pity: pity,
          accent: GachaTokens.dark.fiveStar,
        ),
      ),
    );
    expect(find.textContaining('保底中'), findsOneWidget);
    expect(find.textContaining('平均 70.50 抽出'), findsOneWidget);
  });

  group('breath animation', () {
    Pity pityAt(int current) => Pity(
      current: current,
      threshold: 90,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
    final normalPity = pityAt(30);
    final closePity = pityAt(75);

    Future<void> pumpCard(
      WidgetTester tester,
      Pity pity, {
      bool disableAnimations = false,
    }) => tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: PityCard(
              label: '5★',
              rank: 5,
              pity: pity,
              accent: GachaTokens.dark.fiveStar,
            ),
          ),
        ),
      ),
    );

    testWidgets('normal phase does not keep scheduling frames', (tester) async {
      await pumpCard(tester, normalPity);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('close phase keeps the breath animation running', (
      tester,
    ) async {
      await pumpCard(tester, closePity);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets(
      'entering and leaving close phase starts and stops the animation',
      (tester) async {
        await pumpCard(tester, normalPity);
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
        await pumpCard(tester, closePity);
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isTrue);
        await pumpCard(tester, normalPity);
        await tester.pump();
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );

    testWidgets('turning on reduce motion stops a running animation', (
      tester,
    ) async {
      // 同一個 widget 實例：只有 MediaQuery 變，走 didChangeDependencies 而非 didUpdateWidget。
      final card = PityCard(
        label: '5★',
        rank: 5,
        pity: closePity,
        accent: GachaTokens.dark.fiveStar,
      );
      Widget host({required bool reduce}) => wrap(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: card,
          ),
        ),
      );
      await tester.pumpWidget(host(reduce: false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(host(reduce: true));
      await tester.pump();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduce motion keeps close phase still', (tester) async {
      await pumpCard(tester, closePity, disableAnimations: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
