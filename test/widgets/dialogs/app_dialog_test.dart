import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 統一在指定的視窗尺寸下開啟 dialog。
/// 使用 tester.view 設定視窗大小，確保 MediaQuery.size 正確反映。
Future<void> _pumpDialog(
  WidgetTester tester, {
  required Size surfaceSize,
  required AppDialogSize size,
  bool scrollable = false,
  Widget? content,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => AppDialog(
                  size: size,
                  scrollable: scrollable,
                  title: const Text('Title'),
                  content: content ?? const Text('Body'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('OK')),
                  ],
                ),
              ),
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

/// 從 dialog content 內部最外層 SizedBox 量寬。AppDialog 內部會包一層 SizedBox(width: ...)。
double _innerWidth(WidgetTester tester) {
  final sizedBox = find.descendant(
    of: find.byType(ConstrainedBox),
    matching: find.byType(SizedBox),
  );
  // 找到第一個有設 width 的 SizedBox
  final widths = tester
      .widgetList<SizedBox>(sizedBox)
      .where((s) => s.width != null)
      .map((s) => s.width!);
  return widths.first;
}

void main() {
  testWidgets('sm size uses 480 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.sm,
    );
    expect(_innerWidth(tester), 480);
  });

  testWidgets('md size uses 640 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.md,
    );
    expect(_innerWidth(tester), 640);
  });

  testWidgets('lg size uses 720 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.lg,
    );
    expect(_innerWidth(tester), 720);
  });

  testWidgets('narrow window falls back to mq.width - 80', (tester) async {
    // 視窗寬 400 → 所有 size 都應變成 320
    await _pumpDialog(
      tester,
      surfaceSize: const Size(400, 800),
      size: AppDialogSize.lg,
    );
    expect(_innerWidth(tester), 320);
  });

  testWidgets('maxHeight = min(720, mq.height - 120) — tall window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 1080),
      size: AppDialogSize.md,
    );
    final cb = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(cb.constraints.maxHeight, 720);
  });

  testWidgets('maxHeight = min(720, mq.height - 120) — short window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 600),
      size: AppDialogSize.md,
    );
    final cb = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(cb.constraints.maxHeight, 480);
  });

  testWidgets('scrollable: true wraps content in SingleChildScrollView', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.lg,
      scrollable: true,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('scrollable defaults to false — no SingleChildScrollView', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.sm,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('empty actions list → AlertDialog.actions is null', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const AppDialog(
                    title: Text('Title'),
                    content: Text('Body'),
                    // 不傳 actions，使用預設空陣列
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.actions, isNull);
  });
}
