import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
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
  double? maxHeight,
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => AppDialog(
                  size: size,
                  scrollable: scrollable,
                  maxHeight: maxHeight,
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

/// 量 dialog 面板（[Dialog] 內的 [Material]）的實際大小；[Dialog] 本身含四周留白。
Size _panelSize(WidgetTester tester) => tester.getSize(
  find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first,
);

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

  testWidgets('xl size uses 960 width in wide window', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 800),
      size: AppDialogSize.xl,
    );
    expect(_innerWidth(tester), 960);
  });

  testWidgets('xl size falls back to mq.width - 80 in a 1000 window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1000, 800),
      size: AppDialogSize.xl,
    );
    expect(_innerWidth(tester), 920);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('narrow window falls back to mq.width - 80', (tester) async {
    // 視窗寬 700（還不是手機排版）→ lg 應變成 620
    await _pumpDialog(
      tester,
      surfaceSize: const Size(700, 800),
      size: AppDialogSize.lg,
    );
    expect(_innerWidth(tester), 620);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('compact dialog leaves 12dp around it', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(360, 800),
      size: AppDialogSize.md,
    );
    expect(_innerWidth(tester), 336);
    expect(_panelSize(tester).width, 336);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('compact dialog uses almost all the height', (tester) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(800, 360),
      size: AppDialogSize.md,
      scrollable: true,
      content: const SizedBox(height: 2000),
    );
    expect(_panelSize(tester).height, 336);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('compact dialog wraps long action buttons', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => AppDialog(
                    title: const Text('Title'),
                    content: const Text('Body'),
                    actions: [
                      for (final t in [
                        'Open in the encyclopedia',
                        'Save image to device',
                        'Close this dialog',
                      ])
                        TextButton(onPressed: () {}, child: Text(t)),
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
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('null title renders no title area', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: AppDialog(content: Text('Body'), showCloseButton: false),
        ),
      ),
    );
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
  });

  testWidgets('wide title content is clamped to dialog width, not widening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const AppDialog(
                    size: AppDialogSize.md,
                    // 內在寬度遠大於 md(640)：未約束時會把整個 dialog 撐寬。
                    title: SizedBox(
                      key: Key('wide-title'),
                      width: 1400,
                      height: 24,
                    ),
                    content: Text('Body'),
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

    // title 應被約束到 md 的 640 扣掉右側 ✕（44），而非渲染成內在的 1400。
    expect(tester.getSize(find.byKey(const Key('wide-title'))).width, 640 - 44);
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

  testWidgets('explicit maxHeight overrides default 720 in tall window', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      surfaceSize: const Size(1280, 1080),
      size: AppDialogSize.md,
      maxHeight: 880,
    );
    final cb = tester.widget<ConstrainedBox>(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(cb.constraints.maxHeight, 880);
  });

  testWidgets(
    'explicit maxHeight still capped by mq.height - 120 in short window',
    (tester) async {
      await _pumpDialog(
        tester,
        surfaceSize: const Size(1280, 600),
        size: AppDialogSize.md,
        maxHeight: 880,
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
    },
  );

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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
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

  group('close button', () {
    /// 以 [dialog] 開啟對話框並回傳結果 Future，讓測試在對話框開著時操作。
    Future<Future<Object?>> open(
      WidgetTester tester,
      Widget dialog, {
      Size surfaceSize = const Size(1280, 800),
      Locale locale = const Locale('zh'),
    }) async {
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const Scaffold(body: Text('host')),
        ),
      );
      final result = showDialog<Object>(
        context: tester.element(find.text('host')),
        builder: (_) => dialog,
      );
      await tester.pumpAndSettle();
      return result;
    }

    /// 對話框面板（[Dialog] 內的 [Material]）的位置。
    Rect panel(WidgetTester tester) => tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );

    final close = find.byType(AppDialogCloseButton);

    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      testWidgets('shows at the right end of the title row and returns null '
          '(${platform.name})', (tester) async {
        final result = await open(
          tester,
          AppDialog(
            title: const Text('Title'),
            content: const Text('Body'),
            actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
          ),
        );
        expect(close, findsOneWidget);
        expect(find.byTooltip('關閉'), findsOneWidget);
        final rect = tester.getRect(close);
        final title = tester.getRect(find.text('Title'));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(rect.left, greaterThanOrEqualTo(title.right));
        expect(rect.top, lessThan(title.bottom));
        expect(panel(tester).right - rect.right, lessThan(32));

        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        expect(await result, isNull);
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('absent when turned off', (tester) async {
      await open(
        tester,
        const AppDialog(
          title: Text('Title'),
          content: Text('Body'),
          showCloseButton: false,
        ),
      );
      expect(close, findsNothing);
    });

    testWidgets('sits top-right without a title', (tester) async {
      final result = await open(tester, const AppDialog(content: Text('Body')));
      final rect = tester.getRect(close);
      expect(
        rect.bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Body')).top),
      );
      expect(panel(tester).right - rect.right, lessThan(32));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });

    for (final locale in [const Locale('en'), const Locale('ja')]) {
      testWidgets(
        'long title wraps beside it at 1.3x text (${locale.languageCode})',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await open(
            tester,
            AppDialog(
              title: Text('A rather long dialog title ' * 3),
              content: const Text('Body'),
            ),
            surfaceSize: const Size(360, 800),
            locale: locale,
          );
          expect(tester.takeException(), isNull);
          expect(close, findsOneWidget);
          expect(
            tester.getRect(close).right,
            lessThanOrEqualTo(panel(tester).right),
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }

    /// ✕ 圖示中心的 y。
    double iconCentreY(WidgetTester tester) => tester
        .getCenter(
          find.descendant(of: close, matching: find.byIcon(Icons.close)),
        )
        .dy;

    /// [text] 第一行的垂直中心（全域座標）。
    double firstLineCentreY(WidgetTester tester, Finder text) {
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final lineHeight = paragraph.getFullHeightForCaret(
        const TextPosition(offset: 0),
      );
      return tester.getTopLeft(text).dy + lineHeight / 2;
    }

    /// 以相同標題開關 ✕ 各開一次，回傳（標題頂、內容頂）供比對版面是否被撐開。
    Future<(double, double)> titleAndBodyTop(
      WidgetTester tester, {
      required bool showCloseButton,
    }) async {
      await open(
        tester,
        AppDialog(
          title: const Text('Title'),
          content: const Text('Body'),
          showCloseButton: showCloseButton,
        ),
        surfaceSize: const Size(360, 800),
      );
      final tops = (
        tester.getTopLeft(find.text('Title')).dy,
        tester.getTopLeft(find.text('Body')).dy,
      );
      Navigator.of(tester.element(find.text('Body'))).pop();
      await tester.pumpAndSettle();
      return tops;
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      testWidgets('single-line title: X centred on it without moving the title '
          'or content (${platform.name})', (tester) async {
        final without = await titleAndBodyTop(tester, showCloseButton: false);
        final withX = await titleAndBodyTop(tester, showCloseButton: true);
        expect(withX.$1, closeTo(without.$1, 1));
        expect(withX.$2, closeTo(without.$2, 1));

        await open(
          tester,
          const AppDialog(title: Text('Title'), content: Text('Body')),
          surfaceSize: const Size(360, 800),
        );
        expect(
          (iconCentreY(tester) - tester.getCenter(find.text('Title')).dy).abs(),
          lessThanOrEqualTo(2),
        );
      }, variant: TargetPlatformVariant.only(platform));
    }

    for (final edge in const [
      Offset(0, -20),
      Offset(0, 20),
      Offset(-20, 0),
      Offset(20, 0),
    ]) {
      testWidgets('whole 44dp hit area closes the dialog ($edge)', (
        tester,
      ) async {
        final result = await open(
          tester,
          const AppDialog(title: Text('Title'), content: Text('Body')),
          surfaceSize: const Size(360, 800),
        );
        expect(tester.getSize(close), const Size(44, 44));
        await tester.tapAt(tester.getCenter(close) + edge);
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);
        expect(await result, isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }

    testWidgets('wrapped title: X centred on the first line', (tester) async {
      final text = 'A rather long dialog title ' * 3;
      await open(
        tester,
        AppDialog(title: Text(text), content: const Text('Body')),
        surfaceSize: const Size(360, 800),
      );
      final title = find.text(text);
      expect(tester.getSize(title).height, greaterThan(60));
      expect(
        (iconCentreY(tester) - firstLineCentreY(tester, title)).abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        tester.getRect(close).left,
        greaterThanOrEqualTo(tester.getRect(title).right),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
