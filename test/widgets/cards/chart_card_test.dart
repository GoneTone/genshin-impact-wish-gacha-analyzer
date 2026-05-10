// test/widgets/cards/chart_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';

void main() {
  testWidgets('renders title and chart child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: ChartCard(
            title: 'Rarity',
            chart: Center(child: Text('chart-content')),
          ),
        ),
      ),
    );
    expect(find.text('Rarity'), findsOneWidget);
    expect(find.text('chart-content'), findsOneWidget);
  });
}
