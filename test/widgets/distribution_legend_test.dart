import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    home: Scaffold(body: SizedBox(width: 320, child: child)),
  );

  testWidgets('renders name, count, and rate for each entry', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFFD4A64A),
              name: '5★',
              count: 12,
              rate: 0.0123,
            ),
            DistributionEntry(
              color: Color(0xFFB48CD6),
              name: '4★',
              count: 88,
              rate: 0.0907,
            ),
          ],
        ),
      ),
    );
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1.23%'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('9.07%'), findsOneWidget);
  });

  testWidgets('hides entries with count == 0', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFFD4A64A),
              name: '5★',
              count: 12,
              rate: 0.0123,
            ),
            DistributionEntry(
              color: Color(0xFF9E9E9E),
              name: '未知',
              count: 0,
              rate: 0.0,
            ),
          ],
        ),
      ),
    );
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('未知'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('formats rate with two decimals', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFF7EC0D8),
              name: '角色',
              count: 1,
              rate: 0.5,
            ),
            DistributionEntry(
              color: Color(0xFFE6C389),
              name: '武器',
              count: 1,
              rate: 0.5000999,
            ),
          ],
        ),
      ),
    );
    expect(find.text('50.00%'), findsOneWidget);
    // 0.5000999 * 100 = 50.00999 → toStringAsFixed(2) = "50.01"
    expect(find.text('50.01%'), findsOneWidget);
  });
}
