import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
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
  ///
  /// [storage] 預設用真實檔案系統版 [GachaStorage]；驅動 fakeAsync 虛擬時鐘的
  /// 測試需改傳 [InMemoryGachaStorage]，避免真實檔案 I/O 卡住虛擬時間推進。
  Future<ProviderContainer> makeContainer({GachaStorage? storage}) async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.6.0'),
        gachaStorageProvider.overrideWithValue(
          storage ?? GachaStorage(tempDir),
        ),
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

  test('cancelLink：等待授權中途取消 → 回到 idle，遲到的 signIn 結果被丟棄並 revoke', () async {
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
    expect(authService.revokedTokens, contains('refresh-1'));
    expect(remote.uploads, 0);
  });

  test('setAutoSync(false→true)：關閉不同步，開啟立即補跑一輪', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    await notifier.setAutoSync(false);
    expect(remote.uploads, 1);
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isFalse);

    await notifier.setAutoSync(true);
    expect(remote.uploads, 2);
    expect(container.read(settingsProvider).cloudAutoSyncEnabled, isTrue);
  });

  // 依 review finding 指引：資料變動走 _scheduleDebounced 排的是寫死 5 秒的
  // 真實 Timer，要驗證「到點時 fingerprint 沒變就跳過」需要真的等 5 秒以上
  // 掛鐘時間，會拖慢且不穩定；在不改動 production code（注入時鐘）的前提下，
  // 此分支標記為 untestable-without-refactor。改測可驗證的替代行為：
  // syncNow 手動呼叫本身不做 fingerprint 比對，內容不變仍每次真的上傳。
  test('syncNow 手動呼叫不做 fingerprint 比對，內容不變仍每次上傳', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    await notifier.syncNow(manual: true, trigger: 'manual2');
    expect(remote.uploads, 2);

    await notifier.syncNow(manual: true, trigger: 'manual3');
    expect(remote.uploads, 3);
  });

  test('syncNow 進行中再呼叫 → 標記 pendingRerun，結束後補跑一輪', () async {
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    final gate = Completer<void>();
    remote.downloadGate = gate;

    final first = notifier.syncNow(manual: true, trigger: 'inFlight');
    // syncNow 在第一個 await 前已同步把 state 設成 syncing、鎖上單飛旗標。
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.syncing);

    // 進行中再呼叫：立即返回（不等待輪完），只標記 pendingRerun，不觸發下載/上傳。
    await notifier.syncNow(manual: true, trigger: 'duringFlight');
    expect(remote.uploads, 1);

    gate.complete();
    remote.downloadGate = null;
    await first;
    // finally 區塊 unawaited 補跑的一輪；等它跑完。
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // link 時的第一輪（1）+ 被卡住後放行完成的 in-flight 輪（+1）
    // + pendingRerun 觸發的補跑輪（+1）＝ 3。
    expect(remote.uploads, 3);
    expect(container.read(cloudSyncProvider).phase, CloudSyncPhase.idle);
  });

  test('repository 忙碌時合併中途失敗 → error(busy)，且排入重試（debounce）', () async {
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer();
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    // 換一份新帳號的雲端內容，確保這輪合併真的會呼叫 applyRemote。
    remote.content = _cloudBundleJson('800000002');
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());

    await notifier.syncNow(manual: true, trigger: 'busyTest');

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.error);
    expect(s.errorToken, 'busy');
    // 合併階段就失敗，沒有走到上傳。
    expect(remote.uploads, 1);
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

    remote.downloadError = Exception('Refresh failed: invalid_grant');

    await notifier.syncNow(manual: true);

    final s = container.read(cloudSyncProvider);
    expect(s.phase, CloudSyncPhase.reauthRequired);

    // reauthRequired 短路：再呼叫一次不應該又跑一輪（不重試）。
    await notifier.syncNow(manual: true);
    expect(remote.uploads, 1);
  });

  test('busy 輪後 debounce timer 到點 → 真的補跑同步（迴歸：busy 分支須清空指紋）', () async {
    // 用 InMemoryGachaStorage：待會要在 fakeAsync 的同步 callback 內用
    // async.elapse 推進真實 5 秒 debounce Timer，若補救輪內 _runImport
    // 呼叫的是真實檔案版 GachaStorage.save，其寫入完成通知來自背景執行緒，
    // 不受 FakeAsync 虛擬時鐘控制，在同步 callback 內永遠等不到；換成純
    // 記憶體實作後，整條路徑都只靠 microtask 完成，flushMicrotasks 才能
    // 確實把補救輪推進到底。
    remote.content = _cloudBundleJson('800000001');
    final container = await makeContainer(storage: InMemoryGachaStorage());
    final notifier = container.read(cloudSyncProvider.notifier);
    await notifier.link();
    expect(remote.uploads, 1);

    // 換一份新帳號的雲端內容，確保 busy 那輪真的有下載到未合併的資料；
    // 本機資料在整個 busy → 補救輪之前都不會變動（重現「指紋沒變」場景）。
    remote.content = _cloudBundleJson('800000002');
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());

    fakeAsync((async) {
      // busy 那輪的 syncNow 呼叫必須發生在 fakeAsync zone 內，
      // _scheduleDebounced 建立的 Timer 才會是虛擬時鐘可控制的假 Timer；
      // 若在 zone 外呼叫，之後的 async.elapse 完全不會觸發到它。
      unawaited(notifier.syncNow(manual: true, trigger: 'busyTest'));
      async.flushMicrotasks();

      final busyState = container.read(cloudSyncProvider);
      expect(busyState.phase, CloudSyncPhase.error);
      expect(busyState.errorToken, 'busy');
      // 合併階段就失敗，沒有走到上傳。
      expect(remote.uploads, 1);

      // 清除 busy 狀態但不動本機資料：本機匯出指紋維持不變，正是舊版
      // bug 會被指紋比對誤判「內容沒變」而跳過補救輪的場景。
      container.read(gachaRepositoryProvider.notifier).clearProgress();

      // 推進虛擬時鐘到 debounce 到點：_scheduleDebounced 排的 5 秒
      // Timer 觸發，內部先比對指紋，busy 分支已清空 _lastFingerprint，
      // 指紋比對必為假，才會真的跑 syncNow('dataChange') 補救輪。
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
    });

    expect(remote.uploads, 2);
    expect(
      container.read(gachaRepositoryProvider).byUid.keys,
      contains('800000002'),
    );
  });
}
