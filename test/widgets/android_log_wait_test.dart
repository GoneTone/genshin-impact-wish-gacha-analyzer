import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/genshin_game_package.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';
import '../helpers/no_game_dir.dart';

/// 固定進度、記錄重試的 repository 替身。
class _Repo extends GachaRepository {
  _Repo(this._progress);

  /// 替身回報的固定進度。
  final UpdateProgress _progress;

  /// retryLogAccess 被呼叫的次數。
  int retries = 0;

  @override
  GachaState build() => GachaState(progress: _progress, isBootstrapping: false);

  @override
  Future<void> retryLogAccess() async => retries++;

  @override
  Future<void> cancelCapture() async {
    cancels++;
    state = const GachaState(isBootstrapping: false);
  }

  /// cancelCapture 被呼叫的次數。
  int cancels = 0;
}

/// 記錄呼叫的平台替身。
class _Platform extends LogAccessPlatform {
  /// 被呼叫過的方法。
  final calls = <String>[];

  /// 無線偵錯開關目前的狀態。
  bool adbWifiOn = false;

  @override
  Future<bool> isAdbWifiEnabled() async => adbWifiOn;

  @override
  Future<bool> launchGame(String package) async {
    calls.add('launchGame $package');
    return true;
  }

  @override
  Future<void> openWirelessDebugging() async =>
      calls.add('openWirelessDebugging');
}

void main() {
  late _Repo repo;
  late _Platform platform;

  Future<AppLocalizations> pump(
    WidgetTester tester,
    UpdateProgress progress, {
    bool android = true,
    Locale locale = const Locale('zh', 'Hant'),
  }) async {
    repo = _Repo(progress);
    platform = _Platform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noGameDirOverride,
          isAndroidProvider.overrideWithValue(android),
          logAccessPlatformProvider.overrideWithValue(platform),
          gachaRepositoryProvider.overrideWith(() => repo),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: const Scaffold(body: Center(child: UpdateProgressDialog())),
        ),
      ),
    );
    // LinearProgressIndicator 是無限動畫，不能 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 100));
    return AppLocalizations.of(
      tester.element(find.byType(UpdateProgressDialog)),
    )!;
  }

  testWidgets(
    'android wait shows open game and manual input, no game dir link',
    (tester) async {
      final l = await pump(
        tester,
        const WaitingForCapture(gamePackage: genshinGlobalPackage),
      );
      expect(find.text('等待祈願紀錄...'), findsOneWidget);
      expect(find.text('請開啟原神 → 祈願 → 歷史紀錄'), findsOneWidget);
      expect(find.text(l.progressNotDetectedLink), findsNothing);
      expect(find.text(l.manualUrlEntry), findsOneWidget);
      await tester.tap(find.text(l.actionOpenGame));
      expect(platform.calls, ['launchGame $genshinGlobalPackage']);
    },
  );

  testWidgets('checking log access offers only cancel', (tester) async {
    // 判斷完成前給「開啟原神」，玩家進遊戲後才看到「無法自動讀取」，要來回切換兩次。
    final l = await pump(
      tester,
      const WaitingForCapture(checkingLogAccess: true),
    );
    expect(find.text(l.progressCheckingLogAccess), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l.actionOpenGame), findsNothing);
    expect(find.text(l.manualUrlEntry), findsNothing);
    expect(find.text(l.actionCancel), findsOneWidget);
  });

  testWidgets('open game hidden until the game is known', (tester) async {
    final l = await pump(tester, const WaitingForCapture());
    expect(find.text(l.actionOpenGame), findsNothing);
  });

  testWidgets('game not installed offers check again and the store', (
    tester,
  ) async {
    final l = await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.gameNotInstalled,
      ),
    );
    expect(find.textContaining('這台裝置上找不到原神'), findsOneWidget);
    expect(find.text(l.updateOpenPlayStore), findsOneWidget);
    await tester.tap(find.text(l.actionRedetectGame));
    expect(repo.retries, 1);
  });

  testWidgets('unsupported explains the requirement', (tester) async {
    await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.unsupported,
      ),
    );
    expect(
      find.text('這台裝置無法自動讀取祈願紀錄網址（需要 Android 11 以上，或已 root），請改用手動輸入。'),
      findsOneWidget,
    );
  });

  testWidgets('desktop wait is unchanged', (tester) async {
    final l = await pump(tester, const WaitingForCapture(), android: false);
    expect(find.text(l.progressWaiting), findsOneWidget);
    expect(find.text(l.progressOpenGameHint), findsOneWidget);
    expect(find.text(l.progressNotDetectedLink), findsOneWidget);
    expect(find.text(l.actionOpenGame), findsNothing);
  });

  testWidgets('credential ready asks to return to the app', (tester) async {
    final l = await pump(
      tester,
      const WaitingForCapture(credentialReady: true),
    );
    expect(find.text(l.progressCredentialReady), findsOneWidget);
    expect(find.text(l.progressOpenGameHintAndroid), findsNothing);
    expect(find.text(l.actionOpenGame), findsNothing);
  });

  testWidgets('root denial explains how to allow it', (tester) async {
    final l = await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.notPaired,
        rootDenied: true,
      ),
    );
    expect(find.text(l.logRootDeniedHint), findsOneWidget);
  });

  testWidgets('no root denial hint otherwise', (tester) async {
    final l = await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.notPaired,
      ),
    );
    expect(find.text(l.logRootDeniedHint), findsNothing);
  });

  testWidgets('connection lost shows the warning', (tester) async {
    final l = await pump(
      tester,
      const WaitingForCapture(logConnectionLost: true),
    );
    expect(find.text(l.progressLogConnectionLost), findsOneWidget);
  });

  for (final reason in LogAccessUnavailable.values) {
    testWidgets(
      'unavailable ${reason.name} shows reason without progress bar',
      (tester) async {
        final l = await pump(
          tester,
          WaitingForCapture(logAccessUnavailable: reason),
        );
        expect(find.text(l.progressLogUnavailableTitle), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final text = switch (reason) {
          LogAccessUnavailable.notPaired => l.logUnavailableNotPaired,
          LogAccessUnavailable.noWifi => l.logUnavailableNoWifi,
          LogAccessUnavailable.adbConnectFailed => l.logUnavailableAdbFailed,
          LogAccessUnavailable.wirelessDebuggingOff =>
            l.logUnavailableWirelessOff,
          LogAccessUnavailable.unsupported => l.logUnavailableUnsupported,
          LogAccessUnavailable.networkNotAllowed =>
            l.logUnavailableNetworkNotAllowed,
          LogAccessUnavailable.gameNotInstalled =>
            l.logUnavailableGameNotInstalled,
        };
        expect(find.text(text), findsOneWidget);
        expect(find.text(l.manualUrlEntry), findsOneWidget);
      },
    );
  }

  testWidgets('wireless debugging off offers to open it', (tester) async {
    final l = await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.wirelessDebuggingOff,
      ),
    );
    await tester.tap(find.text(l.actionOpenWirelessDebugging));
    expect(platform.calls, ['openWirelessDebugging']);
  });

  testWidgets('network not allowed: resume retries only once allowed', (
    tester,
  ) async {
    // 玩家在系統視窗按「取消」也會回到本 App；這時重試會再跳一次詢問，變成關不掉的迴圈。
    final l = await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.networkNotAllowed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(repo.retries, 0);

    platform.adbWifiOn = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    expect(repo.retries, 1);

    await tester.tap(find.text(l.actionRetry));
    await tester.pump();
    expect(repo.retries, 2, reason: 'the button asks again');
  });

  testWidgets('resuming the app retries when unavailable', (tester) async {
    await pump(
      tester,
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.wirelessDebuggingOff,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repo.retries, 1);
  });

  for (final (label, progress) in [
    ('checking', const WaitingForCapture(checkingLogAccess: true)),
    ('waiting', const WaitingForCapture(gamePackage: genshinGlobalPackage)),
    (
      'game not installed',
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.gameNotInstalled,
      ),
    ),
    ('connection lost', const WaitingForCapture(logConnectionLost: true)),
    (
      'not paired',
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.notPaired,
      ),
    ),
    (
      'wireless off',
      const WaitingForCapture(
        logAccessUnavailable: LogAccessUnavailable.wirelessDebuggingOff,
      ),
    ),
  ]) {
    testWidgets('$label fits a landscape phone without overflow', (
      tester,
    ) async {
      // 實機橫向 2400×1080、dpr 2.75 → 約 873×393 邏輯像素。
      tester.view.physicalSize = const Size(873, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l = await pump(tester, progress);
      expect(tester.takeException(), isNull);
      // 手動輸入是一定要碰得到的退路。
      // shortcut: 目前的 AppDialog 在低視窗只留 mq.height - 120，要捲動才看得到；子專案 3 的手機版 AppDialog 上線後改回不捲動就看得到。
      if (label != 'checking') {
        await tester.ensureVisible(find.text(l.manualUrlEntry));
        await tester.pump();
        expect(
          find.text(l.manualUrlEntry).hitTestable(),
          findsOneWidget,
          reason: label,
        );
      }
    });
  }

  for (final reason in [
    LogAccessUnavailable.notPaired,
    LogAccessUnavailable.gameNotInstalled,
    LogAccessUnavailable.networkNotAllowed,
  ]) {
    testWidgets('long english ${reason.name} wraps on a narrow phone', (
      tester,
    ) async {
      // 實機直向 1080 寬、dpr 2.625 → 約 411 邏輯像素。
      tester.view.physicalSize = const Size(411, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        WaitingForCapture(logAccessUnavailable: reason),
        locale: const Locale('en'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('completed shows wireless left on hint', (tester) async {
    final l = await pump(
      tester,
      UpdateCompleted(
        totalNewRecords: 0,
        failedBanners: const [],
        updatedAt: DateTime.utc(2026),
        hoYoWikiImagesDownloaded: 0,
        wirelessDebuggingLeftOn: true,
      ),
    );
    expect(find.text(l.progressWirelessLeftOnHint), findsOneWidget);
  });
}
