import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(
      name: name,
      gachaType: gachaType,
      time: time,
      pullsSincePrev: pulls,
    );

Widget _wrap(Widget Function(BuildContext ctx, BannerColors colors) build) =>
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 160,
          child: Builder(
            builder: (ctx) {
              final colors = BannerColors.fromTokens(Theme.of(ctx).gacha);
              return build(ctx, colors);
            },
          ),
        ),
      ),
    );

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(entries: const [], colors: colors),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineNoRecords), findsOneWidget);
  });

  testWidgets('renders one column per entry', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
        ),
      ),
    );
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets('nowPulls != null → adds Now column at the leftmost', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineHorizontal(
          entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
          colors: colors,
          nowPulls: 28,
        ),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNowPulls(28)), findsOneWidget);
  });

  testWidgets('empty + nowPulls != null → renders only the Now column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            TimelineHorizontal(entries: const [], colors: colors, nowPulls: 5),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineHorizontal)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNoRecords), findsNothing);
  });
}
