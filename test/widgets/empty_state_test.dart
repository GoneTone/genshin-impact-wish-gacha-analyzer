import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations_zh.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('zh', 'Hant')}) {
  return MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  );
}

void main() {
  group('EmptyState 滿屏版(compact = false)', () {
    testWidgets('renders 72px icon inside Center', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: Icons.inbox_outlined, title: '無資料')),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 72);
      // EmptyState 滿屏版 build 的最外層應該是 Center
      final firstDescendant = find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byWidgetPredicate((_) => true),
          )
          .first;
      expect(tester.widget(firstDescendant), isA<Center>());
    });

    testWidgets('title uses titleLarge style', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyState(icon: Icons.inbox_outlined, title: '無資料')),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      expect(text.style?.fontSize, 18); // titleLarge = AppFontSize.title
    });
  });

  group('EmptyState compact 變體', () {
    testWidgets('renders 40px icon and bordered container', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);

      // compact 版本最外層應該是 Container,而不是 Center
      final firstDescendant = find
          .descendant(
            of: find.byType(EmptyState),
            matching: find.byWidgetPredicate((_) => true),
          )
          .first;
      expect(tester.widget(firstDescendant), isA<Container>());

      // 最外層 Container 帶 borderSubtle 邊框
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.md));
    });

    testWidgets('title uses titleMedium style in compact mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: '無資料',
            compact: true,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('無資料'));
      // compact 用 titleMedium、滿屏用 titleLarge (=18),兩者字級不同
      expect(text.style?.fontSize, isNot(18));
    });
  });

  group('EmptyState.noRecords factory', () {
    testWidgets('uses l.emptyNoRecords when title is omitted', (tester) async {
      await tester.pumpWidget(
        _wrap(Builder(builder: (context) => EmptyState.noRecords(context))),
      );
      expect(find.text('此卡池無紀錄'), findsOneWidget);
    });

    testWidgets('uses title override when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) =>
                EmptyState.noRecords(context, title: '自訂標題 XYZ'),
          ),
        ),
      );
      expect(find.text('自訂標題 XYZ'), findsOneWidget);
      expect(find.text('此卡池無紀錄'), findsNothing);
    });

    testWidgets('compact:true makes icon 40px', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => EmptyState.noRecords(context, compact: true),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
      expect(icon.size, 40);
    });
  });
  noSyncTests();
}

/// 把 [emptyNoSyncMessage] 換成不含 `{icon}` 的替身字串。
class _NoMarkerL10n extends AppLocalizationsZh {
  _NoMarkerL10n() : super('zh_Hant');

  @override
  String emptyNoSyncMessage(String icon) => '純文字提示';
}

/// 提供 [_NoMarkerL10n] 的 delegate。
class _NoMarkerDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _NoMarkerDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async => _NoMarkerL10n();

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

/// 找出空白提示內含 [WidgetSpan] 的 `Text.rich`。
Finder _spanText() => find.byWidgetPredicate((w) {
  if (w is! Text || w.textSpan == null) return false;
  var found = false;
  w.textSpan!.visitChildren((s) {
    if (s is WidgetSpan) found = true;
    return true;
  });
  return found;
});

/// 在指定視窗大小、語系與字級下渲染 [EmptyState.noSync]。
Future<void> _pumpNoSync(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('zh', 'Hant'),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: _wrap(
        Builder(builder: (context) => EmptyState.noSync(context)),
        locale: locale,
      ),
    ),
  );
}

/// [EmptyState.noSync] 內嵌更新按鈕圖案的測試。
void noSyncTests() {
  group('EmptyState.noSync 嵌入更新按鈕圖案', () {
    testWidgets('Android 360x800：圓形底 refresh 圖示', (tester) async {
      await _pumpNoSync(tester, size: const Size(360, 800));
      expect(_spanText(), findsOneWidget);
      final icon = find.descendant(
        of: _spanText(),
        matching: find.byIcon(Icons.refresh),
      );
      expect(icon, findsOneWidget);
      final circle = find.descendant(
        of: _spanText(),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(circle, findsOneWidget);
      expect(
        find.descendant(of: _spanText(), matching: find.text('更新資料')),
        findsNothing,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('放大字級時圖案只放大一次（與文字同倍率）', (tester) async {
      /// [scale] 字級下圓形圖案實際畫出的高度（含 WidgetSpan 外層的縮放變換）。
      Future<double> glyphHeight(double scale) async {
        await _pumpNoSync(tester, size: const Size(360, 800), textScale: scale);
        final circle = find.descendant(
          of: _spanText(),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        return tester.getRect(circle).height;
      }

      final normal = await glyphHeight(1.0);
      final large = await glyphHeight(1.5);
      expect(large, closeTo(normal * 1.5, 0.5));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Windows 1280x800：refresh 圖示加 actionUpdate 文字', (tester) async {
      await _pumpNoSync(tester, size: const Size(1280, 800));
      expect(
        find.descendant(of: _spanText(), matching: find.byIcon(Icons.refresh)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _spanText(), matching: find.text('更新資料')),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('翻譯沒有 {icon} 時整段純文字、不拋錯', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (outer) => Localizations.override(
              context: outer,
              delegates: const [_NoMarkerDelegate()],
              child: Builder(builder: (context) => EmptyState.noSync(context)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('純文字提示'), findsOneWidget);
      expect(_spanText(), findsNothing);
    });

    for (final locale in const [
      Locale('zh', 'Hant'),
      Locale('zh', 'Hans'),
      Locale('en'),
      Locale('es'),
      Locale('fr'),
      Locale('ja'),
      Locale('pt', 'BR'),
      Locale('th'),
      Locale('vi'),
    ]) {
      testWidgets('$locale 的提示恰有一個圖案、沒有字面 {icon}，1.3 倍字級不溢出', (tester) async {
        await _pumpNoSync(
          tester,
          size: const Size(360, 800),
          locale: locale,
          textScale: 1.3,
        );
        expect(_spanText(), findsOneWidget);
        expect(
          find.descendant(
            of: _spanText(),
            matching: find.byIcon(Icons.refresh),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('{icon}'), findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

      testWidgets('$locale 電腦版按鈕圖案在 1.3 倍字級不溢出', (tester) async {
        // 電腦版嵌的是「圖示＋文字」的縮小按鈕，比圓形圖示寬，放大字級時最容易撐破。
        await _pumpNoSync(
          tester,
          size: const Size(600, 800),
          locale: locale,
          textScale: 1.3,
        );
        final e = tester.takeException();
        expect(e, isNull, reason: e is FlutterError ? e.toStringDeep() : '$e');
        final context = tester.element(_spanText());
        expect(MediaQuery.textScalerOf(context).scale(10), 13);
        expect(
          find.descendant(
            of: _spanText(),
            matching: find.text(AppLocalizations.of(context)!.actionUpdate),
          ),
          findsOneWidget,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  });
}
