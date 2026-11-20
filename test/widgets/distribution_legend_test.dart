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
  });
}
