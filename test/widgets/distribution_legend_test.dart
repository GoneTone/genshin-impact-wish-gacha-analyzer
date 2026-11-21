import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDarkTheme(),
    home: Scaffold(body: SizedBox(width: 320, child: child)),
  );

  testWidgets('renders name, count, and rate for each entry', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFFD4A64A),
              name: '5★',
              count: 12,
              rate: 0.0123,
            ),
            DistributionEntry(
              color: Color(0xFFB48CD6),
              name: '4★',
              count: 88,
              rate: 0.0907,
            ),
          ],
        ),
      ),
    );
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('1.23%'), findsOneWidget);
    expect(find.text('4★'), findsOneWidget);
    expect(find.text('88'), findsOneWidget);
    expect(find.text('9.07%'), findsOneWidget);
  });

  testWidgets('hides entries with count == 0', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFFD4A64A),
              name: '5★',
              count: 12,
              rate: 0.0123,
            ),
            DistributionEntry(
              color: Color(0xFF9E9E9E),
              name: '未知',
              count: 0,
              rate: 0.0,
            ),
          ],
        ),
      ),
    );
    expect(find.text('5★'), findsOneWidget);
    expect(find.text('未知'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('formats rate with two decimals', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DistributionLegend(
          entries: [
            DistributionEntry(
              color: Color(0xFF7EC0D8),
              name: '角色',
              count: 1,
              rate: 0.5,
            ),
            DistributionEntry(
              color: Color(0xFFE6C389),
              name: '武器',
              count: 1,
              rate: 0.5000999,
            ),
          ],
        ),
      ),
    );
    expect(find.text('50.00%'), findsOneWidget);
    // 0.5000999 * 100 = 50.00999 → toStringAsFixed(2) = "50.01"
    expect(find.text('50.01%'), findsOneWidget);
  });

  testWidgets('one-line compact row centres children in a taller tight box', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 60,
            child: CompactLegendRow(
              name: const SizedBox(key: Key('name'), width: 20, height: 10),
              numbers: const SizedBox(
                key: Key('numbers'),
                width: 30,
                height: 16,
              ),
            ),
          ),
        ),
      ),
    );
    final row = tester.getRect(find.byType(CompactLegendRow));
    expect(row.height, 60);
    for (final key in ['name', 'numbers']) {
      expect(
        tester.getRect(find.byKey(Key(key))).center.dy,
        closeTo(row.center.dy, 0.01),
      );
    }
    expect(tester.getRect(find.byKey(const Key('numbers'))).right, row.right);
  });

  group('compact columns with the real phone font', () {
    // 測試預設字型每個字都是正方形，量不出實機寬度；載入 SDK 附的 Roboto（Android 預設字型）。
    setUpAll(() async {
      // 各平台 SDK 的檔名大小寫不同（Linux 是 Roboto-Regular.ttf、Windows 是小寫），Linux 又區分大小寫，不寫死。
      final dir = Directory(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts',
      );
      final font = dir
          .listSync()
          .whereType<File>()
          .firstWhere(
            (f) =>
                f.uri.pathSegments.last.toLowerCase() == 'roboto-regular.ttf',
          )
          .readAsBytesSync();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('keep 100.00% and 12345 on one line at ${scale}x', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          wrap(
            const DistributionLegend(
              compact: true,
              entries: [
                DistributionEntry(
                  color: Color(0xFFD4A64A),
                  name: 'A',
                  count: 12345,
                  rate: 1,
                ),
              ],
            ),
          ),
        );
        final lineHeight = tester.getSize(find.text('A')).height;
        expect(tester.getSize(find.text('100.00%')).height, lineHeight);
        expect(tester.getSize(find.text('12345')).height, lineHeight);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }

    testWidgets('columns follow the text under nonlinear Android scaling', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const _NonlinearScaler()),
            child: child!,
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: DistributionLegend(
                compact: true,
                entries: [
                  DistributionEntry(
                    color: Color(0xFFD4A64A),
                    name: 'A',
                    count: 12345,
                    rate: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final lineHeight = tester.getSize(find.text('A')).height;
      expect(tester.getSize(find.text('100.00%')).height, lineHeight);
      expect(tester.getSize(find.text('12345')).height, lineHeight);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    // 360dp 手機直向的精簡圓餅卡：360 − 頁面內距 12×2 − 卡片內距 12×2 − 圓餅 112 − 間距 12。
    const phoneLegendWidth = 188.0;

    for (final (lang, name) in [
      ('en', 'Character'),
      ('ja', 'キャラクター'),
      ('fr', 'Personnage'),
    ]) {
      testWidgets('long name stays on one line at 360dp and 1.3x ($lang)', (
        tester,
      ) async {
        // 名稱欄只剩約 30dp 時會逐字斷行；放不下就把件數與百分比移到名稱下一行。
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: phoneLegendWidth,
                  child: DistributionLegend(
                    compact: true,
                    entries: [
                      DistributionEntry(
                        color: const Color(0xFF7EC0D8),
                        name: name,
                        count: 1234,
                        rate: 0.6543,
                      ),
                      const DistributionEntry(
                        color: Color(0xFFE6C389),
                        name: '5★',
                        count: 56,
                        rate: 0.3457,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final lineHeight = tester.getSize(find.text('1234')).height;
        expect(tester.getSize(find.text(name)).height, lineHeight);
        expect(find.text('65.43%'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('1234')).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.text(name)).dy),
        );
        // 換行的數字仍靠右，與其他列的右緣對齊；名稱留在起始側（色塊 10 ＋ 間距 8 之後）。
        expect(
          tester.getRect(find.text('65.43%')).right,
          closeTo(phoneLegendWidth, 0.5),
        );
        expect(tester.getRect(find.text(name)).left, closeTo(18, 0.5));
        // 放得下的列維持原本的單行排法：數字靠右、與名稱同一行。
        final short = tester.getRect(find.text('5★'));
        final count = tester.getRect(find.text('56'));
        expect(count.center.dy, closeTo(short.center.dy, 1));
        expect(
          tester.getRect(find.text('34.57%')).right,
          closeTo(phoneLegendWidth, 0.5),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }

    /// 360dp、1.3 倍字級下含一個放不下的長名稱的精簡圖例。
    const longNameLegend = DistributionLegend(
      compact: true,
      entries: [
        DistributionEntry(
          color: Color(0xFF7EC0D8),
          name: 'Character',
          count: 1234,
          rate: 0.6543,
        ),
        DistributionEntry(
          color: Color(0xFFE6C389),
          name: '5★',
          count: 56,
          rate: 0.3457,
        ),
      ],
    );

    testWidgets('wrapped row works under IntrinsicHeight', (tester) async {
      // 橫向總覽頁把圓餅卡排在 IntrinsicHeight 裡，會向圖例查詢 intrinsic 尺寸。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 112 + 12 + phoneLegendWidth,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(width: 112),
                      const SizedBox(width: 12),
                      Expanded(child: longNameLegend),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final legend = tester.getRect(find.byType(DistributionLegend));
      expect(
        tester.getTopLeft(find.text('1234')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Character')).dy),
      );
      expect(
        tester.getRect(find.text('65.43%')).right,
        closeTo(legend.right, 0.5),
      );
      // IntrinsicHeight 量到的高度要剛好容納換行後的內容。
      expect(
        tester.getRect(find.text('34.57%')).bottom,
        lessThanOrEqualTo(legend.bottom),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('RTL mirrors: name at the start (right), numbers at the end', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Widget app(TextDirection direction) => MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: phoneLegendWidth, child: longNameLegend),
            ),
          ),
        ),
      );
      // 先以 LTR 建好再切到 RTL，確認既有 render object 會跟著更新方向。
      await tester.pumpWidget(app(TextDirection.ltr));
      await tester.pumpWidget(app(TextDirection.rtl));
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('Character')).right,
        closeTo(phoneLegendWidth - 18, 0.5),
      );
      for (final rate in ['65.43%', '34.57%']) {
        expect(tester.getRect(find.text(rate)).left, closeTo(0, 0.5));
      }
      expect(
        tester.getTopLeft(find.text('1234')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Character')).dy),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}

/// 模擬 Android 14 起的非線性字級：一般字放大 1.35 倍，20 以上的大字只放大 1.1 倍。
class _NonlinearScaler extends TextScaler {
  /// 建立 [_NonlinearScaler]。
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 1.35 : 1.1);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.35;

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = 9}) =>
      this;
}
