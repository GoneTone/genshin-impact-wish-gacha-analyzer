import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gallery_chip_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 400, child: child)),
  ),
);

ScrollArrowButton _btn(WidgetTester tester, IconData icon) =>
    tester.widget<ScrollArrowButton>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(ScrollArrowButton),
      ),
    );

void main() {
  testWidgets('selectedIndex=0 → left arrow disabled, right enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_left).onPressed, isNull);
    expect(_btn(tester, Icons.arrow_right).onPressed, isNotNull);
  });

  testWidgets('selectedIndex=last → right arrow disabled, left enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 2,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_right).onPressed, isNull);
    expect(_btn(tester, Icons.arrow_left).onPressed, isNotNull);
  });

  testWidgets('selectedIndex=middle → both arrows enabled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_left).onPressed, isNotNull);
    expect(_btn(tester, Icons.arrow_right).onPressed, isNotNull);
  });

  testWidgets('tap right arrow → onSelected(selectedIndex + 1)', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_right));
    await tester.pump();
    expect(picked, 1);
  });

  testWidgets('tap left arrow → onSelected(selectedIndex - 1)', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 2,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_left));
    await tester.pump();
    expect(picked, 1);
  });

  testWidgets('tap a chip → onSelected(that index)', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('C'));
    await tester.pump();
    expect(picked, 2);
  });
}
