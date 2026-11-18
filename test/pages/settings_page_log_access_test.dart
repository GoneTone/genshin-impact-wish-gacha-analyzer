import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/log_access_setup_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/log_access_section.dart';
import '../helpers/no_game_dir.dart';

/// 空 [GachaCapture] 替身。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 背景收尾由測試決定何時做完的 [GachaRepository] 替身。
class _TeardownRepo extends GachaRepository {
  /// 非 null 時 [waitAndroidTeardown] 等它完成。
  static Completer<void>? gate;

  @override
  Future<void> waitAndroidTeardown() async => gate?.future;
}

/// 記錄「前往無線偵錯」被呼叫次數的 [LogAccessPlatform] 替身。
class _FakePlatform extends LogAccessPlatform {
  /// [openWirelessDebugging] 被呼叫的次數。
  int opens = 0;

  @override
  Future<void> openWirelessDebugging() async => opens++;
}

void main() {
  late Directory tempDir;
  late _FakePlatform platform;
  late int unpairs;
  late bool unpairReachable;
  Completer<void>? unpairGate;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('settings_log_access_');
    unpairs = 0;
    unpairReachable = true;
    unpairGate = null;
    _TeardownRepo.gate = null;
    platform = _FakePlatform();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<(ProviderContainer, AppLocalizations)> pump(
    WidgetTester tester, {
    bool android = true,
    LogAccessMethod? method,
    bool paired = true,
    bool canToggle = true,
  }) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = ProviderContainer(
        overrides: [
          noGameDirOverride,
          gachaRepositoryProvider.overrideWith(_TeardownRepo.new),
          isAndroidProvider.overrideWithValue(android),
          logAccessPlatformProvider.overrideWithValue(platform),
          wirelessPairingStatusProvider.overrideWith(
            (ref) async => (paired: paired, canToggle: canToggle),
          ),
          unpairWirelessDebuggingProvider.overrideWithValue(() async {
            unpairs++;
            await unpairGate?.future;
            await container
                .read(settingsProvider.notifier)
                .setLogAccessMethod(null);
            return unpairReachable;
          }),
          gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
          gachaCaptureProvider.overrideWithValue(_NullCapture()),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
          appVersionProvider.overrideWithValue('0.0.0-test'),
        ],
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      await container
          .read(settingsProvider.notifier)
          .setLogAccessMethod(method);
      await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    });
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: buildDarkTheme(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (
      container,
      AppLocalizations.of(tester.element(find.byType(SettingsPage)))!,
    );
  }

  testWidgets('android shows log access section and hides game dir', (
    tester,
  ) async {
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    expect(find.text(l.settingsLogAccess), findsOneWidget);
    expect(find.text(l.settingsGameDir), findsNothing);
    expect(find.text(l.logAccessMethodWireless), findsOneWidget);
    expect(find.text(l.settingsPaired), findsOneWidget);
  });

  testWidgets('values are aligned to the end of the row', (tester) async {
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    final sectionRight = tester.getTopRight(find.byType(LogAccessSection)).dx;
    for (final value in [l.logAccessMethodWireless, l.settingsPaired]) {
      expect(
        tester.getTopRight(find.text(value)).dx,
        moreOrLessEquals(sectionRight, epsilon: 1),
      );
    }
  });

  testWidgets('windows hides log access section', (tester) async {
    final (_, l) = await pump(tester, android: false);
    expect(find.text(l.settingsLogAccess), findsNothing);
    expect(find.text(l.settingsGameDir), findsOneWidget);
  });

  testWidgets('not set up offers setup', (tester) async {
    final (_, l) = await pump(tester, paired: false);
    expect(find.text(l.logAccessMethodNone), findsOneWidget);
    await tester.tap(
      find.widgetWithText(OutlinedButton, l.settingsSetupLogAccess),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LogAccessSetupPage), findsOneWidget);
  });

  testWidgets('wireless method without a key counts as not set up', (
    tester,
  ) async {
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
      paired: false,
    );
    expect(find.text(l.logAccessMethodNone), findsOneWidget);
  });

  testWidgets('root shows the method without pairing rows', (tester) async {
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.root,
      paired: false,
    );
    expect(find.text(l.logAccessMethodRoot), findsOneWidget);
    expect(find.text(l.settingsPairingStatus), findsNothing);
  });

  testWidgets('manual-toggle mode shows the badge and retry grant', (
    tester,
  ) async {
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
      canToggle: false,
    );
    expect(find.text(l.settingsPairedManual), findsOneWidget);
    await tester.tap(find.text(l.settingsRetryGrant));
    await tester.pumpAndSettle();
    expect(find.byType(LogAccessSetupPage), findsOneWidget);
  });

  testWidgets('unpair asks first, then removes and clears the method', (
    tester,
  ) async {
    final (container, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    await tester.tap(find.text(l.settingsUnpair));
    await tester.pumpAndSettle();
    expect(find.text(l.settingsUnpairConfirmTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l.settingsUnpair));
    await tester.pumpAndSettle();
    expect(unpairs, 1);
    expect(container.read(settingsProvider).logAccessMethod, isNull);
    expect(find.text(l.settingsUnpairDone), findsOneWidget);
    expect(
      find.text(
        '${l.settingsUnpairDoneBody}\n\n'
        '${l.settingsUnpairLeftover(AdbKeyStore.keyName)}',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, l.actionOpenWirelessDebugging),
    );
    await tester.pumpAndSettle();
    expect(platform.opens, 1);
    expect(find.text(l.settingsUnpairDone), findsNothing);
  });

  testWidgets('unpair when unreachable shows the system settings hint', (
    tester,
  ) async {
    unpairReachable = false;
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    await tester.tap(find.text(l.settingsUnpair));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.settingsUnpair));
    await tester.pumpAndSettle();
    expect(find.text(l.settingsUnpairUnreachableTitle), findsOneWidget);
    expect(
      find.textContaining(l.settingsUnpairUnreachableRevokeHint),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, l.actionClose));
    await tester.pumpAndSettle();
    expect(platform.opens, 0);
    expect(find.text(l.settingsUnpairUnreachableTitle), findsNothing);
  });

  testWidgets('unpair waits for a pending android teardown', (tester) async {
    // 取消後背景的 release 還沒做完時解除配對，release 可能關掉解除配對要用的無線偵錯。
    final gate = _TeardownRepo.gate = Completer<void>();
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    await tester.tap(find.text(l.settingsUnpair));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.settingsUnpair));
    await tester.pump();
    await tester.pump();
    expect(unpairs, 0);
    expect(
      find.descendant(
        of: find.byType(LogAccessSection),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(unpairs, 1);
  });

  testWidgets('setup waits for a pending android teardown', (tester) async {
    final gate = _TeardownRepo.gate = Completer<void>();
    final (_, l) = await pump(tester, paired: false);
    await tester.tap(
      find.widgetWithText(OutlinedButton, l.settingsSetupLogAccess),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(LogAccessSetupPage), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LogAccessSetupPage), findsOneWidget);
  });

  testWidgets('unpair shows progress and cannot be started twice', (
    tester,
  ) async {
    unpairGate = Completer<void>();
    final (_, l) = await pump(
      tester,
      method: LogAccessMethod.wirelessDebugging,
    );
    await tester.tap(find.text(l.settingsUnpair));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.settingsUnpair));
    await tester.pump();
    await tester.pump();
    final section = find.byType(LogAccessSection);
    expect(
      find.descendant(
        of: section,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, l.settingsUnpair),
    );
    expect(button.onPressed, isNull);
    unpairGate!.complete();
    await tester.pumpAndSettle();
    expect(unpairs, 1);
  });
}
