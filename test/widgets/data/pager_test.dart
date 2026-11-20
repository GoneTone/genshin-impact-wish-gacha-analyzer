import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 800, child: child)),
  ),
);

void main() {
  testWidgets('totalPages == 1 顯示頁碼按鈕但 disabled，且沒有 dropdown', (tester) async {
    await tester.pumpWidget(
      _wrap(Pager(page: 0, totalPages: 1, onChanged: (_) {})),
    );
    expect(find.byType(DropdownButton<int>), findsNothing);
    final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(btn.onPressed, isNull);
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('點頁碼按鈕開出跳頁對話框，確認後回呼 onChanged', (tester) async {
    int? received;
    await tester.pumpWidget(
      _wrap(
        Pager(
          page: 1,
          totalPages: 5,
          totalItems: 90,
          onChanged: (p) => received = p,
        ),
      ),
    );
    expect(find.byType(DropdownButton<int>), findsNothing);
    await tester.tap(find.text('2 / 5'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '4');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(received, 3);
  });

  testWidgets('closing the jump dialog with X keeps the page', (tester) async {
    int? received;
    await tester.pumpWidget(
      _wrap(Pager(page: 1, totalPages: 5, onChanged: (p) => received = p)),
    );
    await tester.tap(find.text('2 / 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppDialogCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(received, isNull);
  });

  testWidgets('取消跳頁不回呼 onChanged', (tester) async {
    int? received;
    await tester.pumpWidget(
      _wrap(Pager(page: 1, totalPages: 5, onChanged: (p) => received = p)),
    );
    await tester.tap(find.text('2 / 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(received, isNull);
  });

  for (final locale in const [Locale('zh'), Locale('en'), Locale('ja')]) {
    testWidgets('320dp 寬、1.3 倍字級（${locale.languageCode}）不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(
            body: Pager(
              page: 127,
              totalPages: 367,
              totalItems: 7340,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      final e = tester.takeException();
      expect(e, isNull, reason: e is FlutterError ? e.toStringDeep() : '$e');
      expect(tester.getSize(find.byType(Pager)).width, 320);
      expect(find.text('128 / 367'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(Pager))).scale(10),
        13,
      );
    });
  }

  testWidgets('首頁 / 上一頁 在第 0 頁 disable', (tester) async {
    await tester.pumpWidget(
      _wrap(Pager(page: 0, totalPages: 3, onChanged: (_) {})),
    );
    final first = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.first_page),
    );
    final prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(first.onPressed, isNull);
    expect(prev.onPressed, isNull);
  });

  testWidgets('末頁 / 下一頁 在最後一頁 disable', (tester) async {
    await tester.pumpWidget(
      _wrap(Pager(page: 2, totalPages: 3, onChanged: (_) {})),
    );
    final last = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.last_page),
    );
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(last.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('chevron_right tap fires onChanged with page+1', (tester) async {
    int? received;
    await tester.pumpWidget(
      _wrap(Pager(page: 1, totalPages: 5, onChanged: (p) => received = p)),
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pump();
    expect(received, 2);
  });

  testWidgets('first_page tap fires onChanged with 0', (tester) async {
    int? received;
    await tester.pumpWidget(
      _wrap(Pager(page: 3, totalPages: 5, onChanged: (p) => received = p)),
    );
    await tester.tap(find.widgetWithIcon(IconButton, Icons.first_page));
    await tester.pump();
    expect(received, 0);
  });
}
