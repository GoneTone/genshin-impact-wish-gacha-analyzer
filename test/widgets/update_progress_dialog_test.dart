import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

import '../helpers/no_game_dir.dart';

/// [GachaRepository] 測試替身：build 回傳固定進度，不做任何真實 I/O。
class _FakeGachaRepository extends GachaRepository {
  /// 建立固定進度為 [_progress] 的替身。
  _FakeGachaRepository(this._progress);

  final UpdateProgress? _progress;

  @override
  GachaState build() => GachaState(progress: _progress, isBootstrapping: false);

  @override
  Future<void> cancelCapture() async {}
}

/// 以 [width] 寬的視窗渲染 [UpdateProgressDialog]，進度固定為 [progress]。
Future<void> _pumpDialog(
  WidgetTester tester, {
  required UpdateProgress progress,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noGameDirOverride,
        gachaRepositoryProvider.overrideWith(
          () => _FakeGachaRepository(progress),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'Hant'),
        home: const Scaffold(body: Center(child: UpdateProgressDialog())),
      ),
    ),
  );
  // LinearProgressIndicator 是無限動畫，不能 pumpAndSettle。
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  const link = '已經開啟祈願歷史紀錄，卻一直沒有反應？';
  const unavailable = '無法啟動攔截程式（可能是憑證被拒絕或連接埠被佔用），改為只從遊戲網頁快取偵測。請開啟祈願歷史紀錄。';
  const unavailableNoDir =
      '無法啟動攔截程式（可能是憑證被拒絕或連接埠被佔用），也找不到遊戲資料夾。請按下方「選擇遊戲資料夾」手動指定。';
  const chooseGameDir = '選擇遊戲資料夾';

  testWidgets(
    'waiting shows the not-detected link that opens the help dialog',
    (tester) async {
      await _pumpDialog(tester, progress: const WaitingForCapture());
      expect(find.text(unavailable), findsNothing);
      expect(find.text(chooseGameDir), findsNothing);
      await tester.tap(find.text(link));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('偵測不到祈願歷史紀錄'), findsOneWidget);
    },
  );

  testWidgets('captureUnavailable shows the warning and keeps the link', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      progress: const WaitingForCapture(captureUnavailable: true),
    );
    expect(find.text(unavailable), findsOneWidget);
    expect(find.text(link), findsOneWidget);
    expect(find.text(chooseGameDir), findsNothing);
  });

  testWidgets(
    'captureUnavailable without game dir swaps the link for a button',
    (tester) async {
      await _pumpDialog(
        tester,
        progress: const WaitingForCapture(
          captureUnavailable: true,
          gameDirMissing: true,
        ),
      );
      expect(find.text(unavailableNoDir), findsOneWidget);
      expect(find.text(unavailable), findsNothing);
      expect(find.text(chooseGameDir), findsOneWidget);
      expect(find.text(link), findsNothing);
    },
  );

  for (final progress in const [
    WaitingForCapture(isFallback: true, captureUnavailable: true),
    WaitingForCapture(captureUnavailable: true, gameDirMissing: true),
  ]) {
    testWidgets('does not overflow at 360 px wide ($progress)', (tester) async {
      await _pumpDialog(tester, progress: progress, width: 360);
      expect(tester.takeException(), isNull);
    });
  }
}
