import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_progress_dialog.dart';

void main() {
  /// 最近一次開啟的進度 dialog 的關閉函式。
  CloseProgressDialog? close;

  Widget host() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => close = showShareProgressDialog(ctx),
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
    expect(find.byType(AppDialogCloseButton), findsNothing);
    expect(find.text(l.shareImageGenerating), findsOneWidget);
  });

  testWidgets('可由呼叫端以回傳的函式關閉，重複呼叫不出錯', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    close!();
    close!();
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('上面疊了別的 dialog 時只關掉進度 dialog', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();
    final ctx = t.element(find.byType(LinearProgressIndicator));
    unawaited(
      showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(content: Text('other')),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));

    close!();
    await t.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('other'), findsOneWidget);
  });
}
