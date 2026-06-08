import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/dialog_toast.dart';

void main() {
  testWidgets('toast 顯示訊息並在停留後自動消失', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialogToast(ctx, 'hello toast'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // 淡入完成
    expect(find.text('hello toast'), findsOneWidget);

    // 停留 2200ms + 淡出 200ms 後移除。
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('hello toast'), findsNothing);
  });

  testWidgets('toast 可從 dialog 內叫出（疊在 dialog 之上）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (dctx) => AlertDialog(
                  content: ElevatedButton(
                    onPressed: () => showDialogToast(dctx, 'over dialog'),
                    child: const Text('toast'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // 在 dialog（modal barrier）之上仍可見：證明用 overlay 而非 app Scaffold 的
    // SnackBar（後者會被 barrier 蓋住）。
    expect(find.text('over dialog'), findsOneWidget);

    // 清掉 toast 計時器，避免 timer pending。
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  });

  testWidgets('連續兩次 toast：先前的被移除，只剩最新一則', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => showDialogToast(ctx, 'first'),
                  child: const Text('a'),
                ),
                ElevatedButton(
                  onPressed: () => showDialogToast(ctx, 'second'),
                  child: const Text('b'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('first'), findsOneWidget);

    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  });
}
