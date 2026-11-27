import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/cloud_sync_section.dart';

import '../helpers/cloud_sync_fakes.dart';
import '../helpers/no_game_dir.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_section_test_');
    SharedPreferences.setMockInitialValues({});
    debugCloudSyncConfiguredOverride = true;
  });

  tearDown(() async {
    debugCloudSyncConfiguredOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立測試用 [ProviderContainer]，覆寫全部依賴並完成 settings／repository bootstrap。
  Future<ProviderContainer> setupContainer(
    Directory hoyowikiDir, {
    List<Override> extra = const [],
    VoidCallback? onForeground,
  }) async {
    final container = ProviderContainer(
      overrides: [
        ...extra,
        appVersionProvider.overrideWithValue('1.6.0'),
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        noGameDirOverride,
        gachaCaptureProvider.overrideWithValue(FakeCapture()),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(hoyowikiDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('', 500)),
            cancel: () {},
          ),
        ),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        cloudSyncRemoteFactoryProvider.overrideWithValue((_) => FakeRemote()),
        cloudSyncUrlOpenerProvider.overrideWithValue((_) {}),
        windowForegroundProvider.overrideWithValue(() async {
          onForeground?.call();
        }),
      ],
    );
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return container;
  }

  /// 包裝待測 widget 與 provider container。
  Widget wrap(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: buildDarkTheme(),
      home: const Scaffold(
        body: SingleChildScrollView(child: CloudSyncSection()),
      ),
    ),
  );

  /// 建立 hoyowiki 暫存目錄。
  Future<Directory> makeHoyowikiDir() async {
    final dir = Directory('${tempDir.path}/hoyowiki');
    await dir.create();
    return dir;
  }

  /// 啟動 container 與待測 widget；bootstrap 走真實 async（runAsync），
  /// pump 有界避免 FakeAsync 下 pumpAndSettle 等不到真實 I/O 而卡死。
  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    List<Override> extra = const [],
    VoidCallback? onForeground,
  }) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await setupContainer(
        await makeHoyowikiDir(),
        extra: extra,
        onForeground: onForeground,
      );
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  testWidgets('未連結：顯示說明與連結按鈕', (tester) async {
    await pumpSection(tester);

    expect(find.text('Link Google account'), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('已連結：顯示 email、開關、立即同步與中斷連結', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudAccountEmail': 'u@example.com',
    });
    await pumpSection(tester);

    expect(find.textContaining('u@example.com'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Unlink'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('未設定憑證：只顯示未設定說明', (tester) async {
    debugCloudSyncConfiguredOverride = false;
    await pumpSection(tester);

    expect(find.text('Link Google account'), findsNothing);
    expect(find.textContaining('cloud sync is unavailable'), findsOneWidget);
  });

  testWidgets('android: awaiting consent shows the Google window hint', (
    tester,
  ) async {
    await pumpSection(
      tester,
      extra: [
        isAndroidProvider.overrideWithValue(true),
        cloudAuthProvider.overrideWithValue(_FakeCloudAuth(hang: true)),
      ],
    );

    await tester.tap(find.text('Link Google account'));
    await tester.pump();

    final l = AppLocalizations.of(
      tester.element(find.byType(CloudSyncSection)),
    )!;
    expect(find.text(l.cloudSyncAwaitingConsentAndroid), findsOneWidget);
    expect(find.text(l.cloudSyncAwaitingConsent), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('android: leaving consent does not bring the window to front', (
    tester,
  ) async {
    var foregroundCalls = 0;
    await pumpSection(
      tester,
      extra: [
        isAndroidProvider.overrideWithValue(true),
        cloudAuthProvider.overrideWithValue(_FakeCloudAuth(hang: false)),
      ],
      onForeground: () => foregroundCalls++,
    );

    await tester.tap(find.text('Link Google account'));
    await tester.pumpAndSettle();

    expect(foregroundCalls, 0);
  });

  testWidgets('桌面：離開等待授權時把視窗帶回前景', (tester) async {
    var foregroundCalls = 0;
    await pumpSection(
      tester,
      extra: [
        isAndroidProvider.overrideWithValue(false),
        cloudAuthProvider.overrideWithValue(_FakeCloudAuth(hang: false)),
      ],
      onForeground: () => foregroundCalls++,
    );

    await tester.tap(find.text('Link Google account'));
    await tester.pumpAndSettle();

    expect(foregroundCalls, 1);
  });
}

/// 測試用 [CloudAuth]：link 依 [hang] 永不完成或拋 scope 缺失。
class _FakeCloudAuth implements CloudAuth {
  /// 建立 [_FakeCloudAuth]。
  _FakeCloudAuth({required this.hang});

  /// true 時 link 永不完成（停在等待授權）。
  final bool hang;

  @override
  bool get keepsClientAcrossRounds => false;

  @override
  Future<CloudLinkResult> link({
    required void Function(String url) openUrl,
    String? postAuthPage,
  }) => hang
      ? Completer<CloudLinkResult>().future
      : Future.error(const CloudScopeMissingException());

  @override
  Future<http.Client?> restoreClient({required String expectedEmail}) async =>
      null;

  @override
  Future<void> unlink() async {}
}
