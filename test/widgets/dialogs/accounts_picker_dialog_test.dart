import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';

final _entries = [
  AccountPickerEntry(
    uid: '100000001',
    alias: '主號',
    lastUpdated: DateTime.utc(2026, 5, 10, 12),
    recordCount: 1234,
  ),
  AccountPickerEntry(
    uid: '100000002',
    lastUpdated: DateTime.utc(2026, 5, 11, 8),
    recordCount: 567,
  ),
  AccountPickerEntry(
    uid: '100000003',
    alias: '小號',
    lastUpdated: DateTime.utc(2026, 5, 12, 9),
    recordCount: 0,
    badge: '覆蓋',
  ),
];

// 用 file-level 變數捕捉 dialog 結果。每個 test 跑前 _open 會重置。
// 直接從 async _open return Future 會被 Dart auto-unwrap，所以採用
// 捕捉變數模式（同 test/widgets/dialogs/confirm_dialog_test.dart）。
List<String>? _result;
bool _completed = false;

Future<void> _open(
  WidgetTester tester, {
  List<AccountPickerEntry>? entries,
}) async {
  _result = null;
  _completed = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh', 'Hant'),
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                _result = await showAccountsPickerDialog(
                  context: ctx,
                  title: '選擇要匯出的帳號',
                  confirmLabel: '匯出',
                  entries: entries ?? _entries,
                );
                _completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'initial state: all checked, select-all checked, confirm enabled',
    (tester) async {
      await _open(tester);

      // 3 個帳號 row 都顯示
      expect(find.text('100000001 (主號)'), findsOneWidget);
      expect(find.text('100000002'), findsOneWidget);
      expect(find.text('100000003 (小號)'), findsOneWidget);

      // 全選 checkbox 是 checked
      final selectAll = find.widgetWithText(CheckboxListTile, '全選');
      expect(selectAll, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(selectAll).value, isTrue);

      // 確認按鈕 enabled
      final confirmBtn = find.widgetWithText(FilledButton, '匯出');
      expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
    },
  );

  testWidgets('uncheck one entry → select-all becomes indeterminate (null)', (
    tester,
  ) async {
    await _open(tester);
    // 點第一個 row 的 checkbox（找它的 title）
    await tester.tap(find.text('100000001 (主號)'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isNull);

    // 確認按鈕仍 enabled（還有 2 個勾）
    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
  });

  testWidgets('uncheck all → select-all unchecked + confirm disabled', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('100000001 (主號)'));
    await tester.tap(find.text('100000002'));
    await tester.tap(find.text('100000003 (小號)'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isFalse);

    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
  });

  testWidgets('tap select-all when checked → all clear, confirm disabled', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('全選'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isFalse);

    final confirmBtn = find.widgetWithText(FilledButton, '匯出');
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);
  });

  testWidgets('tap select-all when indeterminate → all check', (tester) async {
    await _open(tester);
    // 先 uncheck 一個進 indeterminate
    await tester.tap(find.text('100000001 (主號)'));
    await tester.pump();
    // 再點全選
    await tester.tap(find.text('全選'));
    await tester.pump();

    final selectAll = find.widgetWithText(CheckboxListTile, '全選');
    expect(tester.widget<CheckboxListTile>(selectAll).value, isTrue);
  });

  testWidgets('alias rendering: with and without alias', (tester) async {
    await _open(tester);
    expect(find.text('100000001 (主號)'), findsOneWidget); // 有別名
    expect(find.text('100000002'), findsOneWidget); // 無別名（不附括號）
    expect(find.text('100000003 (小號)'), findsOneWidget);
  });

  testWidgets('overwrite badge shown only when entry.badge != null', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('覆蓋'), findsOneWidget);
  });

  testWidgets('subtitle shows lastUpdated + recordCount per locale', (
    tester,
  ) async {
    await _open(tester);
    // 第一個 entry：lastUpdated = 2026-05-10 12:00 UTC，本地時間轉換可能不同
    // 用 substring 斷言避開時區差異。
    expect(find.textContaining('1234 筆紀錄'), findsOneWidget);
    expect(find.textContaining('567 筆紀錄'), findsOneWidget);
    expect(find.textContaining('0 筆紀錄'), findsOneWidget);
  });

  testWidgets('cancel returns null', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, isNull);
  });

  testWidgets('confirm returns selected UIDs in entry order', (tester) async {
    await _open(tester);
    // 取消中間那個
    await tester.tap(find.text('100000002'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '匯出'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, ['100000001', '100000003']);
  });

  testWidgets('confirm returns all UIDs when nothing toggled', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, '匯出'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, ['100000001', '100000002', '100000003']);
  });
}
