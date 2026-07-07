import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

void main() {
  /// 打開帶 checkbox 的打字確認 dialog 並回傳結果讀取函式。
  Future<ConfirmTypeResult? Function()> open(WidgetTester tester) async {
    ConfirmTypeResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showConfirmTypeDialogWithCheckbox(
                context: context,
                title: '確認',
                body: '刪除帳號 800000001？',
                expectedText: '800000001',
                cancelLabel: '取消',
                confirmLabel: '刪除',
                confirmIcon: Icons.delete_outline,
                checkboxLabel: '同時從雲端移除',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('打字正確＋勾選 → confirmed=true, checked=true', (tester) async {
    final read = await open(tester);
    await tester.enterText(find.byType(TextField), '800000001');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    final result = read();
    expect(result, isNotNull);
    expect(result!.confirmed, isTrue);
    expect(result.checkboxChecked, isTrue);
  });

  testWidgets('不勾選＋取消 → confirmed=false, checked=false', (tester) async {
    final read = await open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final result = read();
    expect(result!.confirmed, isFalse);
    expect(result.checkboxChecked, isFalse);
  });
}
