import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

void main() {
  final time = DateTime(2026, 1, 2, 12, 30);

  /// 以手機大小開出一段 [RelativeTimeText]。
  Future<void> pump(WidgetTester tester, {bool tooltipOnTap = true}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RelativeTimeText(
              time: time,
              templateBuilder: (s) => 'updated $s',
              tooltipOnTap: tooltipOnTap,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a tap shows the absolute time on phones', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Tooltip));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(formatAbsoluteDateTime(time)), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('tooltipOnTap false leaves the tap to the parent', (
    tester,
  ) async {
    await pump(tester, tooltipOnTap: false);
    await tester.tap(find.byType(Tooltip));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(formatAbsoluteDateTime(time)), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
