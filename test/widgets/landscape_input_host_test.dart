import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/landscape_input_host.dart';

/// 手機橫向的畫面大小。
const _landscape = Size(800, 411);

/// 手機直向的畫面大小。
const _portrait = Size(411, 800);

/// 在 [size] 的畫面、包了 [LandscapeInputHost] 的 App 裡放 [field]。
Future<void> _pump(WidgetTester tester, Size size, Widget field) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      builder: (context, child) => LandscapeInputHost(child: child!),
      home: Scaffold(body: Center(child: field)),
    ),
  );
  await tester.pumpAndSettle();
}

/// 全螢幕輸入頁是否開著（輸入頁才有確定按鈕）。
bool _pageOpen() => find.text('OK').evaluate().isNotEmpty;

/// 畫面上看得到的文字欄位；輸入頁開著時是輸入頁的欄位。
Finder get _field => find.byType(TextField);

void main() {
  group('phone landscape', () {
    testWidgets('focusing a field opens the page and OK submits', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      final submits = <String>[];
      await _pump(
        tester,
        _landscape,
        TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Paste here'),
          onChanged: changes.add,
          onSubmitted: submits.add,
        ),
      );
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isTrue);
      expect(find.text('Paste here'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(_field, 'abc');
      expect(controller.text, 'abc');
      expect(changes, ['abc']);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(submits, ['abc']);
      expect(find.text('abc'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('the done key submits, back does not', (tester) async {
      final submits = <String>[];
      await _pump(tester, _landscape, TextField(onSubmitted: submits.add));
      await tester.tap(_field);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(submits, ['x']);

      await tester.tap(_field);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'y');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(submits, ['x']);
      expect(find.text('y'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a field that saves on blur still saves after back', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'old');
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final saved = <String>[];
      focus.addListener(() {
        if (!focus.hasFocus) saved.add(controller.text);
      });
      await _pump(
        tester,
        _landscape,
        TextField(controller: controller, focusNode: focus),
      );
      await tester.tap(_field);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'new');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(saved.last, 'new');
      expect(focus.hasFocus, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('formatters apply and the label stands in for a hint', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        _landscape,
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Page'),
        ),
      );
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(find.text('Page'), findsOneWidget);
      await tester.enterText(_field, '1a2');
      expect(controller.text, '12');
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('autofocus opens the page right away', (tester) async {
      await _pump(
        tester,
        _landscape,
        const TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: '800020450'),
        ),
      );
      expect(_pageOpen(), isTrue);
      expect(find.text('800020450'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('the keyboard comes back if a hide lands mid-transition', (
      tester,
    ) async {
      tester.view.physicalSize = _landscape;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          builder: (context, child) => LandscapeInputHost(child: child!),
          home: const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await tester.pump();
      // 實機上原欄位關閉連線的隱藏會晚於輸入頁的顯示送達。
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('hiding the keyboard closes the page like back', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'old');
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final saved = <String>[];
      final submits = <String>[];
      focus.addListener(() {
        if (!focus.hasFocus) saved.add(controller.text);
      });
      await _pump(
        tester,
        _landscape,
        TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: submits.add,
        ),
      );
      await tester.tap(_field);
      await tester.pumpAndSettle();
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'new');
      expect(_pageOpen(), isTrue);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(_pageOpen(), isTrue, reason: 'waits in case the keyboard returns');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(submits, isEmpty);
      expect(controller.text, 'new');
      expect(saved.last, 'new');
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a hide during the transition does not close the page', (
      tester,
    ) async {
      await _pump(tester, _landscape, const TextField());
      addTearDown(tester.view.resetViewInsets);
      // 實機順序：點原欄位鍵盤先出來，輸入頁打開途中原欄位的隱藏才到，換頁結束後鍵盤再出來。
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.tap(_field);
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(_pageOpen(), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('the page stays while the keyboard has not shown yet', (
      tester,
    ) async {
      await _pump(tester, _landscape, const TextField());
      await tester.tap(_field);
      await tester.pumpAndSettle();
      // 鍵盤還沒出來過（viewInsets 一直是 0），不能當成玩家收起鍵盤。
      await tester.pump(const Duration(seconds: 1));
      expect(_pageOpen(), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('turning back to portrait closes the page', (tester) async {
      await _pump(tester, _landscape, const TextField());
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isTrue);

      tester.view.physicalSize = _portrait;
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a field in a dialog opens the page too', (tester) async {
      tester.view.physicalSize = _landscape;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          builder: (context, child) => LandscapeInputHost(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: TextField()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isTrue);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('submitting while the keyboard closes keeps the dialog', (
      tester,
    ) async {
      tester.view.physicalSize = _landscape;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final submits = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          builder: (context, child) => LandscapeInputHost(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      AlertDialog(content: TextField(onSubmitted: submits.add)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(_field);
      await tester.pumpAndSettle();
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.enterText(_field, 'x');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      expect(submits, ['x']);
      expect(find.byType(AlertDialog), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('read-only fields do not open the page', (tester) async {
      await _pump(tester, _landscape, const TextField(readOnly: true));
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('the page fits above the landscape keyboard', (tester) async {
      await _pump(tester, _landscape, const TextField());
      await tester.tap(_field);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('OK')).bottom, lessThanOrEqualTo(131));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  testWidgets('turning to landscape while typing opens the page', (
    tester,
  ) async {
    await _pump(tester, _portrait, const TextField());
    await tester.tap(_field);
    await tester.pump();
    expect(_pageOpen(), isFalse);

    tester.view.physicalSize = _landscape;
    await tester.pumpAndSettle();
    expect(_pageOpen(), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, size, platform) in [
    ('portrait phone', _portrait, TargetPlatform.android),
    ('landscape tablet', const Size(960, 600), TargetPlatform.android),
    ('desktop', _landscape, TargetPlatform.windows),
  ]) {
    testWidgets('$name types straight into the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(tester, size, TextField(controller: controller));
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(_pageOpen(), isFalse);
      await tester.enterText(_field, 'abc');
      expect(controller.text, 'abc');
    }, variant: TargetPlatformVariant.only(platform));
  }
}
