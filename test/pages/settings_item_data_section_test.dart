import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('物品資料區字串已生成且可取用', (tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(l.settingsItemData, '物品資料');
    expect(l.settingsRefreshItemDataTitle, '更新物品資料');
    expect(l.confirmRefreshItemDataConfirm, '開始更新');
  });
}
