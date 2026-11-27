import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';

void main() {
  Future<({ShareImageOptions options, ShareImageAction action})?>? captured;

  Widget host({bool android = false, Locale locale = const Locale('zh')}) =>
      ProviderScope(
        overrides: [isAndroidProvider.overrideWithValue(android)],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
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

  testWidgets('Android 才顯示「分享」鈕，按下 → action=share', (t) async {
    await t.pumpWidget(host(android: true));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.actionShare));
    await t.pumpAndSettle();

    expect((await captured!)!.action, ShareImageAction.share);
  });

  testWidgets('Windows 不顯示「分享」鈕', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.actionShare), findsNothing);
  });

  testWidgets('narrow Windows window still has no share button', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.actionShare), findsNothing);
  });

  for (final size in const [Size(360, 800), Size(800, 360)]) {
    for (final locale in const [
      Locale('zh', 'Hant'),
      Locale('en'),
      Locale('fr'),
    ]) {
      testWidgets('Android share image buttons fit $size in $locale', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(android: true, locale: locale));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();

        final l = lookupAppLocalizations(locale);
        expect(t.takeException(), isNull);
        for (final label in [
          l.actionCancel,
          l.shareImageActionCopy,
          l.actionShare,
          l.shareImageActionSave,
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      });
    }
  }
}
