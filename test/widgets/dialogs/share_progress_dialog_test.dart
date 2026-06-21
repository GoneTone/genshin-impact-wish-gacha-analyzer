import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_progress_dialog.dart';

void main() {
  Widget host() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showShareProgressDialog(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('顯示 LinearProgressIndicator 與進度文字', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l.shareImageGenerating), findsOneWidget);
  });

  testWidgets('可由呼叫端以 Navigator.pop 關閉', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final ctx = t.element(find.byType(LinearProgressIndicator));
    Navigator.of(ctx, rootNavigator: true).pop();
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
