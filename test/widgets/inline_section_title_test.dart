import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';

void main() {
  testWidgets('renders icon and title side by side', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: InlineSectionTitle(icon: Icons.timeline, title: '5★ 時間軸 (3)'),
        ),
      ),
    );
    expect(find.byIcon(Icons.timeline), findsOneWidget);
    expect(find.text('5★ 時間軸 (3)'), findsOneWidget);
  });

  testWidgets('title uses titleLarge style', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: InlineSectionTitle(
            icon: Icons.table_chart_outlined,
            title: '紀錄列表',
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('紀錄列表'));
    expect(text.style?.fontSize, 18); // AppFontSize.title
  });
}
