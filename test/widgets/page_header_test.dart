import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

void main() {
  testWidgets('renders title only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(body: PageHeader(title: 'Overview')),
      ),
    );
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('renders subtitle when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: PageHeader(title: 'Overview', subtitle: 'all banners'),
        ),
      ),
    );
    expect(find.text('all banners'), findsOneWidget);
  });

  testWidgets('renders leading icon when icon is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: PageHeader(title: 'Overview', icon: Icons.dashboard_outlined),
        ),
      ),
    );
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('renders no icon when icon is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(body: PageHeader(title: 'Overview')),
      ),
    );
    expect(find.byType(Icon), findsNothing);
  });

  for (final entry in <(String, ThemeData)>[
    ('dark', buildDarkTheme()),
    ('light', buildLightTheme()),
  ]) {
    final themeName = entry.$1;
    final theme = entry.$2;

    testWidgets('title renders at pageTitle font size (22 px) [$themeName]', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: PageHeader(title: 'Overview')),
        ),
      );

      final titleText = tester.widget<Text>(find.text('Overview'));
      expect(titleText.style?.fontSize, 22);
    });
  }

  testWidgets('long title keeps full width and moves the trailing below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final title = 'A very long banner title ' * 3;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: PageHeader(
            title: title,
            icon: Icons.dashboard_outlined,
            trailing: const Text('Last updated: 1 days ago'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.text(title));
    final trailing = tester.getRect(find.text('Last updated: 1 days ago'));
    expect(titleRect.width, greaterThan(200));
    expect(trailing.top, greaterThanOrEqualTo(titleRect.bottom));
  });
}
