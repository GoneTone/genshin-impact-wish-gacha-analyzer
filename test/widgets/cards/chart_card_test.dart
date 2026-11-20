import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

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

  testWidgets('renders leading icon when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: ChartCard(
            title: 'Rarity',
            icon: Icons.pie_chart_outline,
            chart: Center(child: Text('chart-content')),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.pie_chart_outline), findsOneWidget);
    expect(find.text('Rarity'), findsOneWidget);
  });

  testWidgets('renders no icon when icon is null', (tester) async {
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
    expect(find.byType(Icon), findsNothing);
  });

  /// 以 [layout] 呈現的卡片；[rows] 為圖例列數，[width] 為卡片寬。
  Widget card(ChartCardLayout layout, {int rows = 3, double width = 340}) =>
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ChartCard(
                key: ValueKey('card-$rows'),
                title: 'Rarity',
                layout: layout,
                chart: const ColoredBox(
                  key: ValueKey('chart'),
                  color: Colors.red,
                ),
                legend: DistributionLegend(
                  compact: true,
                  entries: [
                    for (var i = 0; i < rows; i++)
                      DistributionEntry(
                        color: Colors.blue,
                        name: 'Name $i',
                        count: 10 + i,
                        rate: 0.25,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('compact puts a 112 square chart left of the legend', (
    tester,
  ) async {
    await tester.pumpWidget(card(ChartCardLayout.compact));
    expect(tester.getSize(find.byType(ChartCard)).height, lessThan(260));
    expect(
      tester.getSize(find.byKey(const ValueKey('chart'))),
      const Size(112, 112),
    );
    expect(
      tester.getTopLeft(find.byType(DistributionLegend)).dx,
      greaterThan(tester.getTopRight(find.byKey(const ValueKey('chart'))).dx),
    );
    for (final t in ['Name 0', '10', '25.00%', 'Name 2', '12']) {
      expect(find.text(t), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('compactTitleBeside stacks title above the legend', (
    tester,
  ) async {
    await tester.pumpWidget(card(ChartCardLayout.compactTitleBeside));
    expect(
      tester.getSize(find.byKey(const ValueKey('chart'))),
      const Size(96, 96),
    );
    expect(
      tester.getTopLeft(find.text('Rarity')).dx,
      tester.getTopLeft(find.byType(DistributionLegend)).dx,
    );
    expect(
      tester.getTopLeft(find.text('Rarity')).dy,
      lessThan(tester.getTopLeft(find.byType(DistributionLegend)).dy),
    );
  });

  testWidgets('compactTitleBeside cards top-align across legend lengths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final rows in [3, 2])
                Expanded(
                  child: ChartCard(
                    key: ValueKey('c$rows'),
                    title: 'T$rows',
                    layout: ChartCardLayout.compactTitleBeside,
                    chart: const SizedBox(),
                    legend: DistributionLegend(
                      compact: true,
                      entries: [
                        for (var i = 0; i < rows; i++)
                          DistributionEntry(
                            color: Colors.blue,
                            name: 'N$rows-$i',
                            count: 1,
                            rate: 0.5,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('T3')).dy,
      tester.getTopLeft(find.text('T2')).dy,
    );
    expect(
      tester.getTopLeft(find.text('N3-0')).dy,
      tester.getTopLeft(find.text('N2-0')).dy,
    );
  });
}
