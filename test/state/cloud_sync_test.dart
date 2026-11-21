import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/android_cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_authorization_gateway.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

import '../helpers/cloud_sync_fakes.dart';
import '../helpers/counting_storage.dart';
import '../helpers/no_game_dir.dart';
import '../helpers/wait_until.dart';

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

/// 產生本機側只有一筆 301 五星記錄的存檔。
BannerStorage _localBannerStorage(String uid) => BannerStorage(
  uid: uid,
  lastUpdated: DateTime.utc(2026, 7, 2),
  banners: {
    '301': [
      GachaRecord(
        id: '1900000000000000002',
        uid: uid,
        gachaType: '301',
        name: '本機角色',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2026, 7, 1, 12),
        lang: 'zh-tw',
      ),
    ],
  },
);

/// 記錄 [convert] 次數的 converter；轉換一律失敗（被 repository 吞掉、保留原資料）。
class _CountingConverter extends GachaLanguageConverter {
  /// 建立 [_CountingConverter]。
  _CountingConverter()
    : super(ensureCatalog: (lang, {forceRefresh = false}) async => throw 0);

  /// [convert] 被呼叫的次數。
  int converts = 0;

  /// 計數後拋錯。
  @override
  Future<
    ({BannerStorage data, LangConvertResult result, List<IndexHint> hints})
  >
  convert(BannerStorage data, String targetLang) async {
    converts++;
    throw StateError('not under test');
  }
}

/// 記錄是否已 close 的 fake client。
class _ClosableClient extends FakeAuthClient {
  /// 是否已被 close。
  bool closed = false;

  /// 標記為已 close。
  @override
  void close() => closed = true;
}

/// 不跨輪沿用 client 的 fake 授權，記錄 restoreClient 收到的 email。
class _NonPersistentAuth implements CloudAuth {
  /// restoreClient 每次收到的 expectedEmail。
  final restoredEmails = <String>[];

  /// restoreClient 回傳過的 client。
  final clients = <_ClosableClient>[];

  /// link 要回傳的結果；null 代表不支援 link。
  CloudLinkResult? linkResult;

  /// 不跨輪沿用。
  @override
  bool get keepsClientAcrossRounds => false;

  /// 回傳 [linkResult]；未設定時拋 [UnimplementedError]。
  @override
  Future<CloudLinkResult> link({
    required void Function(String url) openUrl,
    String? postAuthPage,
  }) async => linkResult ?? (throw UnimplementedError());

  /// 記錄 [expectedEmail] 並回傳新的 [_ClosableClient]。
  @override
  Future<http.Client?> restoreClient({required String expectedEmail}) async {
    restoredEmails.add(expectedEmail);
    final client = _ClosableClient();
    clients.add(client);
    return client;
  }

  /// 不做任何事。
  @override
  Future<void> unlink() async {}
}

/// 所有步驟都拋錯的 gateway，模擬 Play services 清理失敗。
class _ThrowingGateway implements GoogleAuthorizationGateway {
  /// 一律拋錯。
  @override
  Future<String?> silentToken() async => throw StateError('down');

  /// 一律拋錯。
  @override
  Future<String> interactiveToken() async => throw StateError('down');

  /// 一律拋錯。
  @override
  Future<void> clearToken(String token) async => throw StateError('down');

  /// 一律拋錯。
  @override
  Future<void> signOut() async => throw StateError('down');
}

void main() {
  late Directory tempDir;
  late InMemoryTokenStore tokenStore;
  late FakeAuthService authService;
  late FakeRemote remote;

  /// 補抓管線建立 cancellable HTTP client 的次數；同步輪本身不經過此
  /// factory，計數 >0 即證明補抓確實啟動過（結果被靜默壓掉時仍可斷言）。
  var httpFactoryCalls = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_sync_test_');
    SharedPreferences.setMockInitialValues({});
    tokenStore = InMemoryTokenStore();
    authService = FakeAuthService(tokenStore);
    remote = FakeRemote();
    httpFactoryCalls = 0;
    debugCloudSyncConfiguredOverride = true;
  });

  tearDown(() async {
    debugCloudSyncConfiguredOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立完成載入的 container（HoYoWiki API 一律回 500，補抓 best-effort 空跑）；
  /// 給 [auth] 時直接以它取代平台授權實作。
  Future<ProviderContainer> makeContainer({
    CloudAuth? auth,
    GachaStorage? storage,
    GachaLanguageConverter? converter,
  }) async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.6.0'),
        gachaStorageProvider.overrideWithValue(
          storage ?? GachaStorage(tempDir),
        ),
        noGameDirOverride,
        gachaCaptureProvider.overrideWithValue(FakeCapture()),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(hoyowikiDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(() {
          httpFactoryCalls++;
          return CancellableHttpClient(
            client: MockClient((_) async => http.Response('', 500)),
            cancel: () {},
          );
        }),
        tokenStoreProvider.overrideWithValue(tokenStore),
        googleAuthServiceProvider.overrideWithValue(authService),
        if (auth != null) cloudAuthProvider.overrideWithValue(auth),
        if (converter != null)
          gachaLanguageConverterProvider.overrideWithValue(converter),
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

  test('合併出新記錄 → 觸發補抓；無實際成果時不留完成訊息', () async {
    remote.content = _cloudBundleJson('800000001', withRecord: true);
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    // fetchItemImagesForCloudSync 為 fire-and-forget，等它跑完
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(httpFactoryCalls, greaterThan(0));
    // 測試環境抓不到任何圖（HTTP 全 500）→ 三個計數全零 → 不該留下
    // 完成訊息（progress 保持 null，對話框不彈或自動關閉）。
    expect(container.read(gachaRepositoryProvider).progress, isNull);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('無新增記錄的同步輪 → 不觸發補抓', () async {
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(httpFactoryCalls, 0);
    expect(container.read(gachaRepositoryProvider).progress, isNull);
  });

  test('合併一份與本機相同的資料 → 不重寫記錄檔、不替換記憶體中的記錄', () async {
    remote.content = _cloudBundleJson('800000001', withRecord: true);
    final container = await makeContainer();
    await container.read(cloudSyncProvider.notifier).link();

    final file = GachaStorage(tempDir).recordsFile('800000001');
    final modifiedBefore = file.lastModifiedSync();
    final byUidBefore = container.read(gachaRepositoryProvider).byUid;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container
        .read(gachaRepositoryProvider.notifier)
        .importBundleForCloudSync(importAccounts(remote.content!));

    expect(container.read(gachaRepositoryProvider).byUid, same(byUidBefore));
    expect(file.lastModifiedSync(), modifiedBefore);
  });

  test('雲端與本機相同 → 一輪同步不寫記錄檔、不轉換資料語言', () async {
    final storage = CountingStorage(tempDir);
    final converter = _CountingConverter();
    await GachaStorage(tempDir).save(_localBannerStorage('800000001'));
    final container = await makeContainer(
      storage: storage,
      converter: converter,
    );
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);
    await container.read(settingsProvider.notifier).setDataLanguage('en-us');
    final byUidBefore = container.read(gachaRepositoryProvider).byUid;

    await notifier.syncNow(manual: true, trigger: 'manual2');

    expect(remote.downloads, 2);
    expect(storage.saves, 0);
    expect(converter.converts, 0);
    expect(
      identical(container.read(gachaRepositoryProvider).byUid, byUidBefore),
      isTrue,
    );
  });

  test('雲端只有 lastUpdated 較新（新增 0 筆）→ 照常寫檔、不觸發補抓', () async {
    final storage = CountingStorage(tempDir);
    final cloudOnly = _cloudBundleJson('800000001', withRecord: true);
    final cloudBundle = jsonDecode(cloudOnly) as Map<String, dynamic>;
    final local = BannerStorage.fromJson(
      (cloudBundle['accounts'] as List).first as Map<String, dynamic>,
    ).copyWith(lastUpdated: DateTime.utc(2026, 6, 1));
    await GachaStorage(tempDir).save(local);
    remote.content = cloudOnly;
    final container = await makeContainer(storage: storage);

    await container.read(cloudSyncProvider.notifier).link();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(storage.saves, 1);
    expect(
      container.read(gachaRepositoryProvider).byUid['800000001']!.lastUpdated,
      DateTime.utc(2026, 7, 1),
    );
    expect(httpFactoryCalls, 0);
  });

  test('cancelLink：等待授權中途取消 → 回到 idle，遲到的 signIn 結果被丟棄、不撤銷', () async {
    var baseClientCalls = 0;
    authService = FakeAuthService(
      tokenStore,
      baseClientFactory: () {
        baseClientCalls++;
        return MockClient((_) async => http.Response('', 500));
      },
    );
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    final gate = Completer<void>();
    authService.signInGate = gate.future;

    final linkFuture = notifier.link();
    // link() 在第一個 await（auth.signIn）前已同步把 state 設成 awaitingConsent。
    expect(
      container.read(cloudSyncProvider).phase,
      CloudSyncPhase.awaitingConsent,
    );

    notifier.cancelLink();
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);

    gate.complete();
    await linkFuture;

    expect(tokenStore.token, isNull);
    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(authService.revokedTokens, isEmpty);
    expect(baseClientCalls, 0);
    expect(remote.uploads, 0);
  });

  test('link：授權未含 drive.appdata → error(scopeMissing)、不寫入任何狀態、不撤銷', () async {
    authService.signInThrowsScopeMissing = true;
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.error);
    expect(s.errorToken, 'scopeMissing');
    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(tokenStore.token, isNull);
    expect(authService.revokedTokens, isEmpty);
    expect(remote.uploads, 0);
  });

  test('Android unlink → Play services 清理失敗仍清掉 email 並回 idle', () async {
    final container = await makeContainer(
      auth: AndroidCloudAuth(
        gateway: _ThrowingGateway(),
        baseClientFactory: () =>
            MockClient((_) async => http.Response('', 500)),
      ),
    );
    await container
        .read(settingsProvider.notifier)
        .setCloudAccount('u@example.com');

    await container.read(cloudSyncProvider.notifier).unlink();

    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('link cancelled by the user → idle without error', () async {
    authService.signInThrowsCancelled = true;
    final container = await makeContainer();

    await container.read(cloudSyncProvider.notifier).link();

    final state = container.read(cloudSyncProvider);
    expect(state.phase, CloudSyncPhase.idle);
    expect(state.errorToken, isNull);
    expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    expect(tokenStore.token, isNull);
  });

  test(
    'non-persistent auth → client restored again on the next round',
    () async {
      final auth = _NonPersistentAuth();
      final container = await makeContainer(auth: auth);
      await container
          .read(settingsProvider.notifier)
          .setCloudAccount('u@example.com');

      final notifier = container.read(cloudSyncProvider.notifier);
      await notifier.syncNow(manual: true);
      await notifier.syncNow(manual: true);

      expect(auth.restoredEmails, ['u@example.com', 'u@example.com']);
      expect(auth.clients.every((c) => c.closed), isTrue);
    },
  );

  test(
    'persistent auth → start keeps the client a completed link established',
    () async {
      final container = await makeContainer();
      final notifier = container.read(cloudSyncProvider.notifier);
      await notifier.link();
      expect(authService.restoreCalls, 0);

      await notifier.start();

      expect(authService.restoreCalls, 0);
    },
  );

  test(
    'link: commit throws → client closed, authFailed, no email saved',
    () async {
      final client = _ClosableClient();
      final auth = _NonPersistentAuth()
        ..linkResult = CloudLinkResult(
          client: client,
          email: 'u@example.com',
          commit: () async => throw StateError('commit failed'),
        );
      final container = await makeContainer(auth: auth);

      await container.read(cloudSyncProvider.notifier).link();

      final state = container.read(cloudSyncProvider);
      expect(client.closed, isTrue);
      expect(state.phase, CloudSyncPhase.error);
      expect(state.errorToken, 'authFailed');
      expect(container.read(settingsProvider).cloudAccountEmail, isNull);
    },
  );

  test(
    'non-persistent auth + auto-sync on → start restores exactly once',
    () async {
      final auth = _NonPersistentAuth();
      final container = await makeContainer(auth: auth);
      await container
          .read(settingsProvider.notifier)
          .setCloudAccount('u@example.com');
      await container
          .read(settingsProvider.notifier)
          .setCloudAutoSyncEnabled(true);

      await container.read(cloudSyncProvider.notifier).start();

      expect(auth.restoredEmails, hasLength(1));
      expect(remote.uploads, 1);
    },
  );

  test(
    'non-persistent auth + auto-sync off → start validates and closes the client',
    () async {
      final auth = _NonPersistentAuth();
      final container = await makeContainer(auth: auth);
      await container
          .read(settingsProvider.notifier)
          .setCloudAccount('u@example.com');
      await container
          .read(settingsProvider.notifier)
          .setCloudAutoSyncEnabled(false);

      await container.read(cloudSyncProvider.notifier).start();

      expect(auth.restoredEmails, hasLength(1));
      expect(auth.clients.single.closed, isTrue);
      expect(remote.uploads, 0);
    },
  );

  test(
    'non-persistent auth + sync round running → start skips the restore',
    () async {
      final gate = Completer<void>();
      remote.downloadGate = gate;
      final auth = _NonPersistentAuth();
      final container = await makeContainer(auth: auth);
      await container
          .read(settingsProvider.notifier)
          .setCloudAccount('u@example.com');
      await container
          .read(settingsProvider.notifier)
          .setCloudAutoSyncEnabled(false);

      final notifier = container.read(cloudSyncProvider.notifier);
      final round = notifier.syncNow(manual: true);
      await Future<void>.delayed(Duration.zero);
      await notifier.start();
      gate.complete();
      await round;

      expect(auth.restoredEmails, hasLength(1));
      expect(auth.clients.single.closed, isTrue);
    },
  );

  test('cloudAuthProvider picks the implementation by platform', () {
    ProviderContainer make(bool android) {
      final c = ProviderContainer(
        overrides: [
          isAndroidProvider.overrideWithValue(android),
          googleAuthServiceProvider.overrideWithValue(authService),
          googleAuthorizationGatewayProvider.overrideWithValue(
            _ThrowingGateway(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    expect(make(true).read(cloudAuthProvider), isA<AndroidCloudAuth>());
    expect(make(false).read(cloudAuthProvider), same(authService));
  });

  test('setAutoSync(false→true)：關閉不同步，開啟立即補跑一輪', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.downloads, 1);

    await notifier.setAutoSync(false);
    expect(remote.downloads, 1);
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isFalse);

    await notifier.setAutoSync(true);
    expect(remote.downloads, 2);
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isTrue);
  });

  // 依 review finding 指引：資料變動走 _scheduleDebounced 排的是寫死 5 秒的
  // 真實 Timer，要驗證「到點時 fingerprint 沒變就跳過」需要真的等 5 秒以上
  // 掛鐘時間，會拖慢且不穩定；在不改動 production code（注入時鐘）的前提下，
  // 此分支標記為 untestable-without-refactor。改測可驗證的替代行為：
  // syncNow 手動呼叫本身不做 fingerprint 比對，每次都真的跑一輪；但雲端已與
  // 本機內容相同時，該輪會跳過上傳。
  test('syncNow 手動呼叫每次都跑一輪，雲端已是最新則不重複上傳', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    await notifier.syncNow(manual: true, trigger: 'manual2');
    expect(remote.downloads, 2);
    expect(remote.uploads, 1);

    await notifier.syncNow(manual: true, trigger: 'manual3');
    expect(remote.downloads, 3);
    expect(remote.uploads, 1);
  });

  test('syncNow 進行中再呼叫 → 標記 pendingRerun，結束後補跑一輪', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.downloads, 1);

    final gate = Completer<void>();
    remote.downloadGate = gate;

    final first = notifier.syncNow(manual: true, trigger: 'inFlight');
    // syncNow 在第一個 await 前已同步把 state 設成 syncing、鎖上單飛旗標。
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.syncing);

    // 進行中再呼叫：立即返回（不等待輪完），只標記 pendingRerun，不另外觸發下載
    // （downloads 仍是 link 那輪加上被卡住的這輪）。
    await notifier.syncNow(manual: true, trigger: 'duringFlight');
    expect(remote.downloads, 2);

    gate.complete();
    remote.downloadGate = null;
    await first;
    // finally 區塊 unawaited 補跑的一輪（含背景 isolate 的 JSON 工作）；等它跑完。
    await waitUntil(
      () =>
          remote.downloads == 3 &&
          container.read(cloudSyncProvider).phase == CloudSyncPhase.idle,
    );

    // link 時的第一輪（1）+ 被卡住後放行完成的 in-flight 輪（+1）
    // + pendingRerun 觸發的補跑輪（+1）＝ 3 次下載（雲端已是最新，不再上傳）。
    expect(remote.downloads, 3);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('repository 忙碌時合併中途失敗 → error(busy)，且排入重試（debounce）', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.downloads, 1);

    // 換一份新帳號的雲端內容，確保這輪合併真的會呼叫 applyRemote。
    remote.content = _cloudBundleJson('800000002');
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());

    await notifier.syncNow(manual: true, trigger: 'busyTest');

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.error);
    expect(s.errorToken, 'busy');
    // 合併階段就失敗，沒有走到上傳（link 那輪雲端已是最新，同樣沒上傳）。
    expect(remote.uploads, 0);
  });

  test('同步中途缺 Drive scope（既存 token）→ reauthRequired(scopeMissing)', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    remote.downloadError = Exception('ACCESS_TOKEN_SCOPE_INSUFFICIENT');

    await notifier.syncNow(manual: true, trigger: 'scopeTest');

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.reauthRequired);
    expect(s.errorToken, 'scopeMissing');
  });

  test('同步中途 invalid_grant（client 已建立）→ reauthRequired，且不再重試', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    // link 成功後 _client 已建立，之後的呼叫不會再經過 GoogleAuthService.restore()。
    await notifier.link();
    expect(remote.uploads, 1);

    remote.downloadError = Exception(
      'ServerRequestFailedException: Failed to refresh access token: '
      'invalid_grant',
    );

    await notifier.syncNow(manual: true);

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.reauthRequired);

    // reauthRequired 短路：再呼叫一次不應該又跑一輪（不重試）。
    await notifier.syncNow(manual: true);
    expect(remote.uploads, 1);
  });

  test('busy 重排不做指紋跳過：本機沒變也會補跑並合併雲端新資料', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.downloads, 1);

    // 模擬該輪撞上更新／匯入 busy 被擋；換一份新帳號的雲端內容，
    // 確保被擋的那輪確實下載到了未合併的雲端資料。
    notifier.debounceDelay = Duration.zero;
    remote.content = _cloudBundleJson('800000002');
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());
    await notifier.syncNow(manual: false, trigger: 'busyTest');
    expect(container.read(cloudSyncProvider).errorToken, 'busy');

    // busy 解除；本機完全沒變（匯出指紋與上輪相同），正是舊版 bug 會被
    // 指紋比對誤判「內容沒變」而跳過補救輪的場景。
    container.read(gachaRepositoryProvider.notifier).clearProgress();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 重排的補跑必須執行並把雲端新記錄合併進本機。
    expect(
      container.read(gachaRepositoryProvider).byUid.keys,
      contains('800000002'),
    );
  });

  test('the sync round merge does not schedule a dataChange check', () async {
    final messages = <String>[];
    final sub = Logger.root.onRecord.listen((r) {
      if (r.loggerName == 'cloudsync.sync') messages.add(r.message);
    });
    addTearDown(sub.cancel);

    remote.content = _cloudBundleJson('800000001', withRecord: true);
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    notifier.debounceDelay = const Duration(milliseconds: 10);
    await notifier.link();
    expect(
      container.read(gachaRepositoryProvider).byUid.keys,
      contains('800000001'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(messages.where((m) => m.startsWith('dataChange check')), isEmpty);
  });

  test(
    'a dataChange check that comes due mid-round waits for the round instead of queueing a rerun',
    () async {
      final messages = <String>[];
      final sub = Logger.root.onRecord.listen((r) {
        if (r.loggerName == 'cloudsync.sync') messages.add(r.message);
      });
      addTearDown(sub.cancel);

      await GachaStorage(tempDir).save(_localBannerStorage('800000001'));
      remote.content = _cloudBundleJson('800000001');
      SharedPreferences.setMockInitialValues({
        'pref.cloudAccountEmail': 'u@example.com',
      });
      tokenStore.token = 'refresh-1';
      final container = await makeContainer();
      final notifier = container.read(cloudSyncProvider.notifier);
      notifier.debounceDelay = const Duration(milliseconds: 10);

      // 啟動那輪卡在下載時，本機出現一次內容沒變的變動（換成同內容的新 Map），
      // 變動檢查在該輪還沒跑完時到點；此時還沒有上一輪的指紋可比。
      remote.downloadGate = Completer<void>();
      final round = notifier.start();
      await waitUntil(() => remote.downloads == 1);
      container
          .read(gachaRepositoryProvider.notifier)
          .debugSeedAccount(
            container.read(gachaRepositoryProvider).byUid['800000001']!,
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      remote.downloadGate!.complete();
      await round;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(remote.downloads, 1);
      expect(messages.any((m) => m.contains('trigger=rerun')), isFalse);
    },
  );

  test(
    'upload contains both an account read from its records file and an in-memory-only one',
    () async {
      final onDisk = _localBannerStorage('800000001');
      await GachaStorage(tempDir).save(onDisk);
      final container = await makeContainer();
      container
          .read(gachaRepositoryProvider.notifier)
          .debugSeedAccount(_localBannerStorage('800000002'));
      await container.read(cloudSyncProvider.notifier).link();

      final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
      final accounts = (uploaded['accounts'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        accounts.map((a) => a['uid']),
        containsAll(['800000001', '800000002']),
      );
      final fromDisk = accounts.firstWhere((a) => a['uid'] == '800000001');
      expect(fromDisk, onDisk.toJson());
    },
  );

  test(
    'export includes an account whose records file does not exist yet',
    () async {
      final memoryOnly = _localBannerStorage('800000003');
      final container = await makeContainer();
      container
          .read(gachaRepositoryProvider.notifier)
          .debugSeedAccount(memoryOnly);
      expect(File('${tempDir.path}/800000003.json').existsSync(), isFalse);

      await container.read(cloudSyncProvider.notifier).link();

      final uploaded = jsonDecode(remote.content!) as Map<String, dynamic>;
      final accounts = (uploaded['accounts'] as List)
          .cast<Map<String, dynamic>>();
      expect(accounts, hasLength(1));
      expect(accounts.single, memoryOnly.toJson());
    },
  );
}
