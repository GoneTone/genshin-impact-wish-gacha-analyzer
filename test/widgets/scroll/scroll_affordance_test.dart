import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

Widget _wrap(Widget Function(GachaTokens tokens) build) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(
    body: Builder(builder: (ctx) => Center(child: build(Theme.of(ctx).gacha))),
  ),
);

void main() {
  testWidgets('onPressed != null → tappable, fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_left));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('onPressed == null → renders icon but tap does nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_left), findsOneWidget);
    final inkWell = tester.widget<InkWell>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_left),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNull);
  });

  testWidgets('arrow hit area is 48dp on phones and its edge is tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: () => taps++,
        ),
      ),
    );
    final size = tester.getSize(find.byType(ScrollArrowButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // 點在 24dp 圓圈外、48dp 觸控區內。
    await tester.tapAt(
      tester.getCenter(find.byType(ScrollArrowButton)) + const Offset(20, 0),
    );
    await tester.pump();
    expect(taps, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('arrow stays 24dp on desktop', (tester) async {
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: () {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(ScrollArrowButton)).width, 24);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
