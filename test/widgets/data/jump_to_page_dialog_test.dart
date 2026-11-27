import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/jump_to_page_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開啟對話框並回傳「結果 Future」，讓測試在對話框開著時操作。
Future<Future<int?>> _open(
  WidgetTester tester, {
  int totalPages = 367,
  int? totalItems,
  Locale locale = const Locale('zh'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(builder: (context) => const Scaffold(body: Text('host'))),
    ),
  );
  final ctx = tester.element(find.text('host'));
  final result = showJumpToPageDialog(
    context: ctx,
    currentPage: 0,
    totalPages: totalPages,
    totalItems: totalItems,
  );
  await tester.pumpAndSettle();
  return result;
}

/// 「前往」按鈕。
Finder get _go => find.byType(FilledButton);

void main() {
  testWidgets('輸入 128 按前往回傳 127', (tester) async {
    final result = await _open(tester);
    await tester.enterText(find.byType(TextField), '128');
    await tester.pump();
    await tester.tap(_go);
    await tester.pumpAndSettle();
    expect(await result, 127);
  });

  testWidgets('按 Enter 等同前往', (tester) async {
    final result = await _open(tester);
    await tester.enterText(find.byType(TextField), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await result, 4);
  });

  testWidgets('取消回傳 null', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('close button returns null', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.byType(AppDialogCloseButton));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('帶 totalItems 時顯示目前頁與總筆數', (tester) async {
    await _open(tester, totalItems: 7340);
    expect(find.text('目前在第 1 頁，共 7340 筆'), findsOneWidget);
  });

  testWidgets('英文的目前頁與總筆數不會讀成「第幾筆」', (tester) async {
    await _open(tester, totalItems: 1620, locale: const Locale('en'));
    expect(find.text('Currently on page 1 · 1620 records'), findsOneWidget);
  });

  for (final (typed, kept) in [('12a', '12'), (' 5 ', '5'), ('-3', '3')]) {
    testWidgets('輸入框只留數字："$typed" → "$kept"', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        kept,
      );
    });
  }

  for (final (text, total) in [
    ('0', 367),
    ('368', 367),
    ('12a', 10),
    ('', 367),
    (' ', 367),
  ]) {
    testWidgets('非法輸入 "$text" 時前往 disabled 並顯示提示', (tester) async {
      final result = await _open(tester, totalPages: total);
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      expect(tester.widget<FilledButton>(_go).onPressed, isNull);
      expect(find.text('請輸入 1–$total 的頁碼'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget, reason: 'Enter 不可關閉對話框');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  }
}
