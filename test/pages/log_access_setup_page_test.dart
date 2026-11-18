import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/log_access_setup_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import '../helpers/no_game_dir.dart';

/// 固定階段、記錄呼叫的控制器替身。
class _Ctl extends AdbPairingController {
  _Ctl(this.initial);

  final AdbPairingState initial;
  final calls = <String>[];

  @override
  AdbPairingState build() => initial;
  @override
  Future<void> startSetup() async => calls.add('startSetup');
  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  Future<void> openWirelessDebugging() async => calls.add('openWireless');
  @override
  Future<void> requestNotifications() async =>
      calls.add('requestNotifications');
  @override
  Future<void> retryGrant() async => calls.add('retryGrant');
  @override
  void skipGrant() => state = state.to(PairingPhase.doneManual);

  /// 測試直接切換階段。
  void go(PairingPhase p) => state = state.to(p);
}

/// 記錄 update 呼叫的 repository 替身。
class _Repo extends GachaRepository {
  final updates = <bool>[];

  @override
  GachaState build() => const GachaState(isBootstrapping: false);
  @override
  Future<void> update({bool afterPairing = false}) async =>
      updates.add(afterPairing);
}

/// 記錄跳轉的平台替身。
class _Platform extends LogAccessPlatform {
  final calls = <String>[];

  @override
  Future<void> openDeviceInfoSettings() async => calls.add('about');
  @override
  Future<void> openAppNotificationSettings() async => calls.add('notif');
  @override
  Future<void> openDeveloperOptions() async => calls.add('dev');
}

void main() {
  late _Ctl ctl;
  late _Repo repo;
  late _Platform platform;

  Future<AppLocalizations> pump(
    WidgetTester tester,
    AdbPairingState initial,
  ) async {
    ctl = _Ctl(initial);
    repo = _Repo();
    platform = _Platform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noGameDirOverride,
          adbPairingProvider.overrideWith(() => ctl),
          gachaRepositoryProvider.overrideWith(() => repo),
          logAccessPlatformProvider.overrideWithValue(platform),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => openLogAccessSetup(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(LogAccessSetupPage)),
    )!;
  }

  testWidgets('disclosure shows what the app does and starts setup', (
    tester,
  ) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.disclosure),
    );
    expect(find.text(l.setupWhatBody), findsOneWidget);
    await tester.tap(find.text(l.setupStart));
    expect(ctl.calls, contains('startSetup'));
  });

  testWidgets('dev options step opens the about page', (tester) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.needDevOptions),
    );
    expect(find.text(l.setupStepDevOptionsBody), findsOneWidget);
    expect(find.text(l.setupStepPairBody), findsNothing);
    await tester.tap(find.text(l.setupOpenAbout));
    expect(platform.calls, ['about']);
  });

  testWidgets('notifications step asks, then offers settings when denied', (
    tester,
  ) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.needNotifications),
    );
    expect(find.text(l.setupStepDevOptionsDone), findsOneWidget);
    await tester.tap(find.text(l.setupAllowNotifications));
    expect(ctl.calls, contains('requestNotifications'));

    ctl.state = const AdbPairingState(
      PairingPhase.needNotifications,
      notificationsDenied: true,
    );
    await tester.pump();
    await tester.tap(find.text(l.setupOpenNotificationSettings));
    expect(platform.calls, ['notif']);
  });

  testWidgets('ready step opens wireless debugging', (tester) async {
    final l = await pump(tester, const AdbPairingState(PairingPhase.ready));
    await tester.tap(find.text(l.actionOpenWirelessDebugging));
    expect(ctl.calls, contains('openWireless'));
  });

  testWidgets('waiting step explains the notification input', (tester) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.waitingCode),
    );
    expect(find.text(l.setupWaitingCode), findsOneWidget);
    expect(find.text(l.setupOpenWirelessAgain), findsOneWidget);
  });

  testWidgets('grant failed offers retry and skip', (tester) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.grantFailed),
    );
    expect(find.text(l.setupGrantHowBody), findsOneWidget);
    await tester.tap(find.text(l.setupRetry));
    expect(ctl.calls, contains('retryGrant'));
    await tester.tap(find.text(l.setupOpenDeveloperOptions));
    expect(platform.calls, ['dev']);
  });

  testWidgets('done pops and starts an update after pairing', (tester) async {
    final l = await pump(tester, const AdbPairingState(PairingPhase.ready));
    ctl.go(PairingPhase.done);
    await tester.pump();
    expect(find.text(l.setupDoneTitle), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(LogAccessSetupPage), findsNothing);
    expect(repo.updates, [true]);
  });

  testWidgets('keeps wireless debugging on when it was on before setup', (
    tester,
  ) async {
    await pump(tester, const AdbPairingState(PairingPhase.ready));
    ctl
      ..wirelessWasOnAtStart = true
      ..go(PairingPhase.done);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(repo.updates, [false]);
  });

  testWidgets('skipping the grant also returns and updates', (tester) async {
    final l = await pump(
      tester,
      const AdbPairingState(PairingPhase.grantFailed),
    );
    await tester.tap(find.text(l.setupSkipGrant));
    await tester.pump();
    expect(find.text(l.setupDoneManualBody), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(LogAccessSetupPage), findsNothing);
    expect(repo.updates, [true]);
  });

  testWidgets('resuming the app refreshes the steps', (tester) async {
    await pump(tester, const AdbPairingState(PairingPhase.waitingCode));
    ctl.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ctl.calls, contains('refresh'));
  });
}
