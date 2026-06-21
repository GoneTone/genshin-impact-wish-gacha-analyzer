import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';

void main() {
  Future<({ShareImageOptions options, ShareImageAction action})?>? captured;

  Widget host() => MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => captured = showShareImageDialog(
              ctx,
              initialBrightness: Brightness.dark,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('複製圖片回傳 copy + 預設選項', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.shareImageActionCopy));
    await t.pumpAndSettle();

    final r = await captured!;
    expect(r, isNotNull);
    expect(r!.action, ShareImageAction.copy);
    expect(r.options.brightness, Brightness.dark);
    expect(r.options.showFullUid, isFalse);
  });

  testWidgets('儲存圖片回傳 save', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.shareImageActionSave));
    await t.pumpAndSettle();

    final r = await captured!;
    expect(r, isNotNull);
    expect(r!.action, ShareImageAction.save);
  });

  testWidgets('取消回傳 null', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.actionCancel));
    await t.pumpAndSettle();

    expect(await captured!, isNull);
  });
}
