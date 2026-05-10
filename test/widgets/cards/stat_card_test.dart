// test/widgets/cards/stat_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(wrap(const StatCard(label: 'TOTAL', value: '428')));
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('428'), findsOneWidget);
  });

  testWidgets('renders subtitle and trailing when provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        const StatCard(
          label: 'PITY',
          value: '73 / 90',
          subtitle: 'distance 17',
          trailing: Icon(Icons.trending_up, key: Key('t')),
        ),
      ),
    );
    expect(find.text('distance 17'), findsOneWidget);
    expect(find.byKey(const Key('t')), findsOneWidget);
  });

  testWidgets('accent color shows as left border', (tester) async {
    await tester.pumpWidget(
      wrap(const StatCard(label: 'L', value: 'V', accent: Color(0xFFE6C477))),
    );
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });
}
