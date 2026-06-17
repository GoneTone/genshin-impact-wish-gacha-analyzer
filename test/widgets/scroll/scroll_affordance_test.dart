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
}
