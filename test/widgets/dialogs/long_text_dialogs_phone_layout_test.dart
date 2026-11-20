import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';

/// 模擬長訊息（例如附上例外內容的失敗訊息）的內文。
final _longBody = List.filled(30, 'Lorem ipsum dolor sit amet,').join(' ');

void main() {
  /// 以 [open] 開啟 dialog 的測試宿主；按下「open」才呼叫。
  Widget host(void Function(BuildContext context) open) => MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  /// 要檢查的 dialog：名稱與開啟方式。
  final dialogs = <String, void Function(BuildContext context)>{
    'export result': (ctx) => showExportResultDialog(
      ctx,
      success: false,
      message: _longBody,
      revealPath: 'C:/a.json',
    ),
    'confirm': (ctx) => showConfirmDialog(
      context: ctx,
      title: 'Confirm',
      body: _longBody,
      cancelLabel: 'Cancel',
      confirmLabel: 'OK',
    ),
    'type confirm': (ctx) => showConfirmTypeDialog(
      context: ctx,
      title: 'Confirm',
      body: _longBody,
      expectedText: '800000001',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete_outline,
    ),
    'type confirm with checkbox': (ctx) => showConfirmTypeDialogWithCheckbox(
      context: ctx,
      title: 'Confirm',
      body: _longBody,
      expectedText: '800000001',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete_outline,
      checkboxLabel: 'Also remove from cloud',
    ),
  };

  for (final size in const [Size(360, 800), Size(800, 360)]) {
    for (final entry in dialogs.entries) {
      testWidgets('${entry.key} dialog with a long message fits $size', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(host(entry.value));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();

        expect(t.takeException(), isNull);
        // 文字被截掉時不會丟例外，要另外比對實際高度與完整排版所需高度。
        final body = t.renderObject<RenderBox>(find.text(_longBody));
        expect(
          body.size.height,
          greaterThanOrEqualTo(
            body.getMinIntrinsicHeight(body.size.width) - 0.5,
          ),
        );
      });
    }
  }
}
