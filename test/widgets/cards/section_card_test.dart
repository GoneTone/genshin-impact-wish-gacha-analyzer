import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';

void main() {
  testWidgets('renders title and child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: SectionCard(title: 'Theme', child: Text('inside')),
        ),
      ),
    );
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('renders leading icon when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: SectionCard(
            title: 'Theme',
            icon: Icons.palette_outlined,
            child: Text('inside'),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
  });

  testWidgets('renders no icon when icon is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: SectionCard(title: 'Theme', child: Text('inside')),
        ),
      ),
    );
    expect(find.byType(Icon), findsNothing);
  });
}
