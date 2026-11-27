import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('enabled=false 時按鈕為 disabled', (t) async {
    await t.pumpWidget(
      _host(ShareActionButton(enabled: false, onGenerate: () async {})),
    );
    final btn = t.widget<IconButton>(find.byType(IconButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('enabled=true 點擊觸發 onGenerate', (t) async {
    var called = false;
    await t.pumpWidget(
      _host(
        ShareActionButton(enabled: true, onGenerate: () async => called = true),
      ),
    );
    await t.tap(find.byType(IconButton));
    await t.pump();
    expect(called, isTrue);
  });

  testWidgets('busy state survives being scrolled out of a lazy list', (
    t,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    const listKey = Key('outer');
    await t.pumpWidget(
      _host(
        ListView(
          key: listKey,
          children: [
            ShareActionButton(
              enabled: true,
              onGenerate: () {
                calls++;
                return pending.future;
              },
            ),
            const SizedBox(height: 5000),
          ],
        ),
      ),
    );
    await t.tap(find.byType(IconButton));
    await t.pump();

    await t.drag(find.byKey(listKey), const Offset(0, -6000));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.drag(find.byKey(listKey), const Offset(0, 6000));
    await t.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(calls, 1);
    pending.complete();
    await t.pump();
  });
}
