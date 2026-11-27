import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/manual_url_dialog.dart';

/// 記錄 [submitManualUrl] 呼叫的 [GachaRepository] 替身。
class _FakeGachaRepository extends GachaRepository {
  /// 收到的網址。
  final submitted = <String>[];

  @override
  GachaState build() => const GachaState(isBootstrapping: false);

  @override
  Future<void> submitManualUrl(String apiUrl) async => submitted.add(apiUrl);
}

/// 渲染一個按鈕，按下後開啟手動輸入對話框。
Future<_FakeGachaRepository> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeGachaRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gachaRepositoryProvider.overrideWith(() => repo)],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'Hant'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManualUrlDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('manual dialog shows hint and an error for text without a url', (
    tester,
  ) async {
    final repo = await _pump(tester);
    expect(
      find.text('如果已經用其他方式（例如電腦上的工具）取得祈願記錄網址，可以貼在這裡；整段文字也可以，App 會自動找出網址。'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'no url here');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(find.text('找不到祈願記錄網址，請確認貼上的內容。'), findsOneWidget);
    expect(repo.submitted, isEmpty);
  });

  testWidgets('manual dialog submits the api url and closes', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(
      find.byType(TextField),
      '「https://gs.hoyoverse.com/a/index.html?auth_appid=webview_gacha&authkey=K1」',
    );
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(repo.submitted, hasLength(1));
    expect(repo.submitted.single, contains('/gacha_info/api/getGachaLog?'));
    expect(find.byType(TextField), findsNothing);
  });
}
