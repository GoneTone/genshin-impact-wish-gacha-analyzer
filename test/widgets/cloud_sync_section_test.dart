import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/cloud_sync_section.dart';

import '../helpers/cloud_sync_fakes.dart';

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
  Future<ProviderContainer> setupContainer(Directory hoyowikiDir) async {
    final container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.6.0'),
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
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
        windowForegroundProvider.overrideWithValue(() async {}),
      ],
    );
    await container.read(settingsProvider.notifier).waitForLoad();
    container.read(gachaRepositoryProvider);
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
  Future<ProviderContainer> pumpSection(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await setupContainer(await makeHoyowikiDir());
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
}
