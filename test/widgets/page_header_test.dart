// test/widgets/page_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

void main() {
  testWidgets('renders title only', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: PageHeader(title: 'Overview'),
      ),
    ));
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('renders subtitle when provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: PageHeader(title: 'Overview', subtitle: 'all banners'),
      ),
    ));
    expect(find.text('all banners'), findsOneWidget);
  });
}
