import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';

void main() {
  testWidgets('delete button disabled until input matches', (tester) async {
    bool confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  confirmed =
                      await showConfirmTypeDialog(
                        context: ctx,
                        title: 'Confirm',
                        body: 'Type X to confirm',
                        expectedText: 'X',
                        cancelLabel: 'Cancel',
                        confirmLabel: 'Delete',
                        confirmIcon: Icons.delete_outline,
                      ) ??
                      false;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final deleteBtn = find.widgetWithText(FilledButton, 'Delete');
    expect(tester.widget<FilledButton>(deleteBtn).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'X');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteBtn).onPressed, isNotNull);

    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('action buttons render with icons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showConfirmTypeDialog(
                  context: ctx,
                  title: 'Confirm',
                  body: 'Type X',
                  expectedText: 'X',
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Delete',
                  confirmIcon: Icons.delete_outline,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('confirmIcon controls the confirm button icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showConfirmTypeDialog(
                  context: ctx,
                  title: 'Confirm',
                  body: 'Type X',
                  expectedText: 'X',
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Import',
                  confirmIcon: Icons.check,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
