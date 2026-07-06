import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

import '../helpers/cloud_sync_fakes.dart';

/// 產生雲端側 bundle JSON；[withRecord] 為 true 時帶一筆 301 五星記錄。
String _cloudBundleJson(String uid, {bool withRecord = false}) => jsonEncode({
  'schema_version': AccountsBundle.currentSchemaVersion,
  'app': accountsBundleAppId,
  'exported_at': '2026-07-06T00:00:00.000Z',
  'app_version': '1.6.0',
  'last_active_uid': uid,
  'accounts': [
    {
      'uid': uid,
      'last_updated': '2026-07-01T00:00:00.000Z',
      'banners': {
        '301': withRecord
            ? [
                {
                  'id': '1900000000000000001',
                  'uid': uid,
                  'gacha_type': '301',
                  'name': '測試角色',
                  'item_type': '角色',
                  'rank_type': 5,
                  'time': '2026-06-30 12:00:00',
                  'lang': 'zh-tw',
                },
              ]
            : <Object>[],
      },
    },
  ],
});

void main() {
  late Directory tempDir;
  late InMemoryTokenStore tokenStore;
  late FakeAuthService authService;
  late FakeRemote remote;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_sync_test_');
    SharedPreferences.setMockInitialValues({});
    tokenStore = InMemoryTokenStore();
    authService = FakeAuthService(tokenStore);
    remote = FakeRemote();
    debugCloudSyncConfiguredOverride = true;
  });

  tearDown(() async {
    debugCloudSyncConfiguredOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立完成載入的 container（HoYoWiki API 一律回 500，補抓 best-effort 空跑）。
  Future<ProviderContainer> makeContainer() async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
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
        tokenStoreProvider.overrideWithValue(tokenStore),
        googleAuthServiceProvider.overrideWithValue(authService),
        cloudSyncRemoteFactoryProvider.overrideWithValue((_) => remote),
        cloudSyncUrlOpenerProvider.overrideWithValue((_) {}),
        windowForegroundProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    return container;
  }

  test('link 成功 → 寫 email、存 token、跑第一輪同步', () async {
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    expect(container.read(settingsProvider).cloudAccountEmail, 'u@example.com');
    expect(tokenStore.token, 'refresh-1');
    expect(remote.uploads, 1);
    expect(container.read(settingsProvider).cloudLastSyncedAt, isNotNull);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('syncNow 把雲端帳號合併進本機並上傳', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();

    expect(
      container.read(gachaRepositoryProvider).byUid.keys,
      contains('800000001'),
    );
    final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
    final uids = (uploaded['accounts'] as List)
        .map((a) => (a as Map<String, dynamic>)['uid'])
        .toList();
    expect(uids, contains('800000001'));
  });

  test('雲端 schema 過新 → error(schemaTooNew)、不上傳', () async {
    final map =
        jsonDecode(_cloudBundleJson('800000001')) as Map<String, dynamic>;
    map['schema_version'] = AccountsBundle.currentSchemaVersion + 1;
    remote.content = jsonEncode(map);
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.error);
    expect(s.errorToken, 'schemaTooNew');
    expect(remote.uploads, 0);
  });

  test('start：token 失效 → reauthRequired、不跑同步', () async {
    SharedPreferences.setMockInitialValues({
      'pref.cloudAccountEmail': 'u@example.com',
    });
    authService.restoreThrowsReauth = true;
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).start();

    expect(
      container.read(cloudSyncProvider).phase,
      CloudSyncPhase.reauthRequired,
    );
    expect(remote.uploads, 0);
  });

  test('unlink → 清 email、刪 token、雲端檔保留', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();

    await container.read(cloudSyncProvider.notifier).unlink();

    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(tokenStore.token, isNull);
    expect(remote.content, isNotNull);
  });

  test('queueCloudRemoval → 上傳內容剔除該 UID、清 pendingRemovals', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();
    // 模擬本機已刪：直接從 repo 移除
    await container
        .read(gachaRepositoryProvider.notifier)
        .removeUid('800000001');

    await container
        .read(cloudSyncProvider.notifier)
        .queueCloudRemoval('800000001');

    final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
    final uids = (uploaded['accounts'] as List)
        .map((a) => (a as Map<String, dynamic>)['uid'])
        .toList();
    expect(uids, isNot(contains('800000001')));
    expect(container.read(settingsProvider).cloudPendingRemovals, isEmpty);
  });

  test('合併出新記錄 → 觸發補抓並 emit UpdateCompleted 不帶 importSummary', () async {
    remote.content = _cloudBundleJson('800000001', withRecord: true);
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    // fetchItemImagesForCloudSync 為 fire-and-forget，等它跑完
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    expect((progress as UpdateCompleted).importSummary, isNull);
  });

  test('無新增記錄的同步輪 → 不觸發補抓', () async {
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(container.read(gachaRepositoryProvider).progress, isNull);
  });
}
