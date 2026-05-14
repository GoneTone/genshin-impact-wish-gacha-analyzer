import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';

TimelineEntry _e(String name, String gachaType, int pulls, DateTime time) =>
    TimelineEntry(
      name: name,
      gachaType: gachaType,
      time: time,
      pullsSincePrev: pulls,
    );

Widget _wrap(Widget Function(BuildContext, BannerColors) build) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (ctx) {
        final colors = BannerColors.of(Theme.of(ctx).brightness);
        return SizedBox(width: 600, child: build(ctx, colors));
      },
    ),
  ),
);

void main() {
  testWidgets('empty + no nowPulls → shows timelineNoRecords', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(entries: const [], colors: colors),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(find.text(l.timelineNoRecords), findsOneWidget);
  });

  testWidgets('renders entries with month tag per month group', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => TimelineVertical(
          entries: [
            _e('娜維婭', '301', 62, DateTime(2025, 4, 19)),
            _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
            _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
          ],
          colors: colors,
        ),
      ),
    );
    final ctx = tester.element(find.byType(TimelineVertical));
    final l = AppLocalizations.of(ctx)!;
    expect(find.text(l.timelineMonthLabel('2025', '04')), findsOneWidget);
    expect(find.text(l.timelineMonthLabel('2025', '03')), findsOneWidget);
    expect(find.text('娜維婭'), findsOneWidget);
    expect(find.text('夜蘭'), findsOneWidget);
    expect(find.text('流浪者'), findsOneWidget);
  });

  testWidgets(
    'nowPulls + isAcrossBanners=true → top row shows cross-pool i18n',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineVertical(
            entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
            colors: colors,
            nowPulls: 12,
            isAcrossBanners: true,
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(TimelineVertical)),
      )!;
      expect(find.text(l.timelineNowLabel), findsOneWidget);
      expect(find.text(l.timelineNowSinceCrossPool(12)), findsOneWidget);
      expect(find.text(l.timelineNowSinceLast(12)), findsNothing);
    },
  );

  testWidgets(
    'nowPulls + isAcrossBanners=false → top row shows single-pool i18n',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineVertical(
            entries: [_e('夜蘭', '301', 87, DateTime(2025, 4, 1))],
            colors: colors,
            nowPulls: 28,
          ),
        ),
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(TimelineVertical)),
      )!;
      expect(find.text(l.timelineNowSinceLast(28)), findsOneWidget);
    },
  );

  testWidgets('empty + nowPulls → renders only Now row, no NoRecords', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) =>
            TimelineVertical(entries: const [], colors: colors, nowPulls: 5),
      ),
    );
    final l = AppLocalizations.of(
      tester.element(find.byType(TimelineVertical)),
    )!;
    expect(find.text(l.timelineNowLabel), findsOneWidget);
    expect(find.text(l.timelineNoRecords), findsNothing);
  });
}
