import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/landscape_input_field.dart';

/// 在 [size] 的畫面放一個 [LandscapeInputField]，回傳它的 controller 與 onChanged 收到的文字。
Future<(TextEditingController, List<String>)> _pump(
  WidgetTester tester,
  Size size, {
  bool autofocus = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  final changes = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: LandscapeInputField(
            controller: controller,
            autofocus: autofocus,
            decoration: const InputDecoration(hintText: 'Paste here'),
            onChanged: changes.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller, changes);
}

/// 放一個有送出動作、只收數字、只有 labelText 的欄位（像跳頁對話框），回傳 onSubmitted 收到的文字。
Future<List<String>> _pumpSubmitting(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 411);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  final submits = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: LandscapeInputField(
            controller: controller,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Page'),
            onSubmitted: submits.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(_visibleField);
  await tester.pumpAndSettle();
  return submits;
}

/// 畫面上看得到的文字欄位（不含被全螢幕輸入頁蓋住的那個）。
Finder get _visibleField => find.byType(TextField);

void main() {
  testWidgets('portrait phone types straight into the field', (tester) async {
    final (controller, changes) = await _pump(tester, const Size(411, 800));
    await tester.enterText(_visibleField, 'abc');
    await tester.pump();
    expect(controller.text, 'abc');
    expect(changes, ['abc']);
    expect(find.text('OK'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop types straight into the field', (tester) async {
    final (controller, _) = await _pump(tester, const Size(800, 411));
    await tester.enterText(_visibleField, 'abc');
    expect(controller.text, 'abc');
    expect(find.text('OK'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('landscape phone edits on a full-screen page and comes back', (
    tester,
  ) async {
    final (controller, changes) = await _pump(tester, const Size(800, 411));
    expect(
      tester.widget<TextField>(_visibleField).readOnly,
      isTrue,
      reason: 'the dialog field must not raise the keyboard itself',
    );
    await tester.tap(_visibleField);
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Paste here'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.enterText(_visibleField, 'abc');
    expect(controller.text, 'abc');
    expect(changes, ['abc']);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
    expect(find.text('abc'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('keyboard done and system back also return', (tester) async {
    final (controller, _) = await _pump(tester, const Size(800, 411));
    await tester.tap(_visibleField);
    await tester.pumpAndSettle();
    await tester.enterText(_visibleField, 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);

    await tester.tap(_visibleField);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
    expect(controller.text, 'x');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('full-screen page fits above the landscape keyboard', (
    tester,
  ) async {
    await _pump(tester, const Size(800, 411));
    await tester.tap(_visibleField);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('OK')).bottom, lessThanOrEqualTo(131));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('autofocus does not open the page in landscape', (tester) async {
    await _pump(tester, const Size(800, 411), autofocus: true);
    expect(find.text('OK'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('turning to landscape while typing drops the focus', (
    tester,
  ) async {
    await _pump(tester, const Size(411, 800));
    await tester.tap(_visibleField);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    tester.view.physicalSize = const Size(800, 411);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('OK'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('OK and the done key submit like the native extract mode', (
    tester,
  ) async {
    final submits = await _pumpSubmitting(tester);
    expect(find.text('Page'), findsOneWidget, reason: 'label used as hint');
    await tester.enterText(_visibleField, '1a2');
    expect(find.text('12'), findsOneWidget, reason: 'formatters apply');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(submits, ['12']);

    await tester.tap(_visibleField);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submits, ['12', '12']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('back returns without submitting', (tester) async {
    final submits = await _pumpSubmitting(tester);
    await tester.enterText(_visibleField, '3');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
    expect(submits, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
