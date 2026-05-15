// test/widgets/empty_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'Hant'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('EmptyState 滿屏版(compact = false)', () {
    testWidgets('renders 72px icon inside Center', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: Icons.inbox_outlined, title: '無資料')),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 72);
      // EmptyState 滿屏版 build 的最外層應該是 Center
      final firstDescendant = find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byWidgetPredicate((_) => true),
          )
          .first;
      expect(tester.widget(firstDescendant), isA<Center>());
    });

    testWidgets('title uses titleLarge style', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: Icons.inbox_outlined, title: '無資料')),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      expect(text.style?.fontSize, 18); // titleLarge = AppFontSize.title
    });
  });

  group('EmptyState compact 變體', () {
    testWidgets('renders 40px icon and bordered container', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);

      // compact 版本最外層應該是 Container,而不是 Center
      final firstDescendant = find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byWidgetPredicate((_) => true),
          )
          .first;
      expect(tester.widget(firstDescendant), isA<Container>());

      // 最外層 Container 帶 borderSubtle 邊框
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
    });

    testWidgets('title uses titleMedium style in compact mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      // compact 用 titleMedium、滿屏用 titleLarge (=18),兩者字級不同
      expect(text.style?.fontSize, isNot(18));
    });
  });

  group('EmptyState.noRecords factory', () {
    testWidgets('uses l.emptyNoRecords when title is omitted', (tester) async {
      await tester.pumpWidget(
        _wrap(Builder(builder: (context) => EmptyState.noRecords(context))),
      );
      expect(find.text('此卡池無紀錄'), findsOneWidget);
    });

    testWidgets('uses title override when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                EmptyState.noRecords(context, title: '自訂標題 XYZ'),
          ),
        ),
      );
      expect(find.text('自訂標題 XYZ'), findsOneWidget);
      expect(find.text('此卡池無紀錄'), findsNothing);
    });

    testWidgets('compact:true makes icon 40px', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => EmptyState.noRecords(context, compact: true),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);
    });
  });
}
