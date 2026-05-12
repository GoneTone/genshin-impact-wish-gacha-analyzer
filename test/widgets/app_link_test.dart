import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

void main() {
  testWidgets('預設樣式：primary color + underline', (tester) async {
    final theme = buildDarkTheme();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    );

    final textWidget = tester.widget<Text>(find.text('hi'));
    final effectiveStyle = DefaultTextStyle.of(
      tester.element(find.text('hi')),
    ).style.merge(textWidget.style);

    expect(effectiveStyle.color, theme.colorScheme.primary);
    expect(effectiveStyle.decoration, TextDecoration.underline);
  });

  testWidgets('hover 時 cursor 為 SystemMouseCursors.click', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    );

    final region = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byType(AppLink),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
  });

  testWidgets('hover 時文字顏色與未 hover 時不同', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: AppLink(url: 'https://example.test', child: Text('hi')),
          ),
        ),
      ),
    );

    Color? readColor() {
      final ctx = tester.element(find.text('hi'));
      return DefaultTextStyle.of(ctx).style.color;
    }

    final before = readColor();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('hi')));
    await tester.pump();

    final after = readColor();

    expect(before, isNotNull);
    expect(after, isNotNull);
    expect(after, isNot(equals(before)));
  });

  testWidgets('點擊 AppLink 不會拋例外', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    );

    await tester.tap(find.text('hi'));
    await tester.pumpAndSettle();
  });

  testWidgets('AppLink 內的 GestureDetector 有連上 onTap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: AppLink(url: 'https://example.test', child: Text('hi')),
        ),
      ),
    );

    final detector = tester.widget<GestureDetector>(
      find
          .descendant(
            of: find.byType(AppLink),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(detector.onTap, isNotNull);
  });
}
