import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/paimon_moe_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/importers/uigf_importer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/platform_picker_dialog.dart';

// 用 file-level 變數捕捉 dialog 結果（同 accounts_picker_dialog_test.dart 模式）。
PlatformImporter? _result;
bool _completed = false;

Future<void> _open(WidgetTester tester) async {
  _result = null;
  _completed = false;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'Hant'),
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  _result = await showPlatformPickerDialog(context: ctx);
                  _completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists UIGF and Paimon.moe and returns UIGF on tap', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('選擇匯入來源平台'), findsOneWidget);
    expect(find.text('UIGF'), findsOneWidget);
    expect(find.text('genshin-wish-export 等工具・JSON'), findsOneWidget);
    expect(find.text('Paimon.moe'), findsOneWidget);
    expect(find.text('Paimon.moe・Excel'), findsOneWidget);

    await tester.tap(find.text('UIGF'));
    await tester.pumpAndSettle();

    expect(_completed, isTrue);
    expect(_result, isA<UigfImporter>());
  });

  testWidgets('returns Paimon.moe on tap', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Paimon.moe'));
    await tester.pumpAndSettle();

    expect(_completed, isTrue);
    expect(_result, isA<PaimonMoeImporter>());
  });

  testWidgets('shows each platform icon asset', (tester) async {
    await _open(tester);

    for (final importer in kPlatformImporters) {
      expect(
        find.image(AssetImage(importer.iconAsset)),
        findsOneWidget,
        reason: importer.id,
      );
      expect(await rootBundle.load(importer.iconAsset), isNotNull);
    }
  });

  testWidgets('cancel returns null', (tester) async {
    await _open(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(_completed, isTrue);
    expect(_result, isNull);
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(1280, 800)]) {
    testWidgets('fits without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Paimon.moe・Excel'), findsOneWidget);
    });
  }
}
