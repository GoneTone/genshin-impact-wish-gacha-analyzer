import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCapture implements GachaCapture {
  _FakeCapture(this._url);
  final String? _url;

  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(_url), cancel: () async {});
}

class _CountingCapture implements GachaCapture {
  _CountingCapture(this._inner, this._onCall);
  final GachaCapture _inner;
  final void Function() _onCall;

  @override
  CaptureSession start() {
    _onCall();
    return _inner.start();
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_test_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('bootstrap load 空目錄 → state 為空', () async {
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async {
              throw 'unreachable';
            }),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initial = container.read(gachaRepositoryProvider);
    expect(initial.activeUid, isNull);
    expect(initial.byUid, isEmpty);

    // 等 bootstrap fire-and-forget 完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = container.read(gachaRepositoryProvider);
    expect(after.activeUid, isNull);
  });

  test('bootstrap load 有 2 個 UID 檔 → activeUid = 較新者', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 5, 9), // 較新
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(gachaRepositoryProvider);
    expect(state.knownUids.toSet(), {'100000001', '100000002'});
    expect(state.activeUid, '100000002');
  });

  test('AuthExpired 連續 2 次 → UpdateFailed with exact message', () async {
    final storage = GachaStorage(tempDir);
    // 先 seed 一個 cached URL，讓 update 直接走 fetch path（跳過 MITM 階段）
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      '100000001',
      'https://example.com/getGachaLog?authkey=expired',
    );

    var fetcherCalls = 0;
    final mock = MockClient((req) async {
      fetcherCalls++;
      // 永遠回 -101 認證失效
      return http.Response(
        '{"retcode":-101,"message":"authkey timeout","data":null}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    var captureCalls = 0;
    final fakeCapture = _FakeCapture(
      'https://example.com/getGachaLog?authkey=alsoexpired',
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWith((ref) {
          // 計數 capture 被呼叫幾次
          return _CountingCapture(fakeCapture, () => captureCalls++);
        }),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: mock, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 等 bootstrap 完成
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');

    await container.read(gachaRepositoryProvider.notifier).update();

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect((progress as UpdateFailed).error, isA<UpdateErrorAuthExpired>());
    // capture 應該被叫 1 次（fallback MITM）；cached URL 第一次直接用，沒 MITM
    expect(captureCalls, 1);
    // fetcher 至少被叫過（兩次嘗試都打 mock）
    expect(fetcherCalls, greaterThan(0));
  });

  test('update() 立刻設定 Preparing（在第一個 await 之前）', () async {
    final storage = GachaStorage(tempDir);
    // seed cached URL，update 走 fetch 路徑（不進 MITM）
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      '100000001',
      'https://example.com/getGachaLog?authkey=x',
    );

    // 用一個永遠不 complete 的 Completer 阻塞 HTTP，這樣 _runUpdate
    // 在進到 probe 階段時會卡住，state 維持在 Preparing
    final block = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) => block.future),
            cancel: () {
              if (!block.isCompleted) {
                block.completeError(http.ClientException('cancelled'));
              }
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // bootstrap

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final updateFut = notifier.update();

    // 把 microtask 跑一輪，讓 loadCapturedUrl 完成、進到 probe 並 await
    // mock client 的 future（永遠不 complete），此刻 state.progress 應該是 Preparing
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<Preparing>(),
      reason: '進入 probe 階段時 state 應該維持在 Preparing',
    );

    // cleanup
    notifier.cancelPreparing();
    await updateFut;
  });

  test('cancelPreparing → 中斷 HTTP → progress 回到 null', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      '100000001',
      'https://example.com/getGachaLog?authkey=x',
    );

    final block = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) => block.future),
            cancel: () {
              if (!block.isCompleted) {
                block.completeError(http.ClientException('cancelled by test'));
              }
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final updateFut = notifier.update();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    notifier.cancelPreparing();
    await updateFut;

    // progress 應為 null（取消），不是 UpdateFailed
    expect(container.read(gachaRepositoryProvider).progress, isNull);
    // 既有資料保留
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
  });

  test('probe 階段真實 ClientException（非取消） → UpdateFailed', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      '100000001',
      'https://example.com/getGachaLog?authkey=x',
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((req) {
              throw http.ClientException('network down', req.url);
            }),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(gachaRepositoryProvider.notifier).update();

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect((progress as UpdateFailed).error, isA<UpdateErrorOther>());
  });

  test('clearProgress 把 progress 重設為 null', () async {
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);
    // 等 bootstrap 完成，避免 async 工作洩漏到測試邊界後
    await Future<void>.delayed(const Duration(milliseconds: 50));

    notifier.debugSetProgress(const UpdateFailed(UpdateErrorOther('test')));
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateFailed>(),
    );

    notifier.clearProgress();
    expect(container.read(gachaRepositoryProvider).progress, isNull);
  });

  test('bootstrap：lastActiveUid 命中 → 用它（不用最新）', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 5, 9), // 較新
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': '100000001'});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
  });

  test(
    'bootstrap：lastActiveUid 失效 → fallback 為 mergeUidOrder.first 並寫回',
    () async {
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      await storage.save(
        BannerStorage(
          uid: '100000002',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'GHOST'});

      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(gachaRepositoryProvider).activeUid,
        '100000002',
      ); // 較新
      // 寫回 settings
      final reloaded = await SettingsStorage.load();
      expect(reloaded.lastActiveUid, '100000002');
    },
  );

  test('bootstrap：lastActiveUid 為 null → fallback 為最新並寫回', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, '100000001');
  });

  test('bootstrap：uidOrder 影響 fallback 順序', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({
      'pref.uidOrder': '["100000001","100000002"]', // 自訂 100000001 在前
    });

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // lastActiveUid 為 null → fallback 走 mergeUidOrder.first → 自訂順序的第一個 = 100000001
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
  });

  test(
    'cancelPreparing 在 FetchingBanner 階段也應 clearProgress (非 UpdateCompleted)',
    () async {
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      await storage.saveCapturedUrl(
        '100000001',
        'https://example.com/getGachaLog?authkey=x',
      );

      // 第一次 request（probe 第一個 banner，命中 → primer，state 還在 Preparing）
      // 第二次 request 起會卡住（fetchBannerWithMerge 第二頁的 HTTP），這時 state
      // 已經被 onProgress 推進到 FetchingBanner。
      var hits = 0;
      final block = Completer<http.Response>();
      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((req) {
                hits++;
                if (hits == 1) {
                  // primer：20 筆紀錄迫使 fetchBannerWithMerge 進入第二頁
                  return Future.value(
                    http.Response(
                      jsonEncode({
                        'retcode': 0,
                        'message': 'OK',
                        'data': {
                          'list': List.generate(
                            20,
                            (i) => {
                              'uid': '100000001',
                              'gacha_type': '301',
                              'item_id': '',
                              'count': '1',
                              'time': '2025-09-23 21:27:37',
                              'name': 'x',
                              'lang': 'zh-tw',
                              'item_type': '武器',
                              'rank_type': '3',
                              // 19 字元 id，遞減確保 desc 順序
                              'id': '17${(99 - i).toString().padLeft(17, '0')}',
                            },
                          ),
                          'page': '1',
                          'size': '20',
                          'total': '0',
                        },
                      }),
                      200,
                      headers: {'content-type': 'application/json'},
                    ),
                  );
                }
                // 後續 request 永遠不 complete
                return block.future;
              }),
              cancel: () {
                if (!block.isCompleted) {
                  block.completeError(
                    http.ClientException('cancelled by test'),
                  );
                }
              },
            ),
          ),
          // 加快 rate limit，免得測試太慢
          gachaFetcherProvider.overrideWithValue(
            GachaFetcher(rateLimit: Duration.zero, retryBackoff: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(gachaRepositoryProvider.notifier);
      final updateFut = notifier.update();

      // 等更長一點，讓 probe 完成（命中第一個 banner）、進入 fetchBannerWithMerge、
      // 處理 primer（onProgress → state=FetchingBanner）、再 await 第二頁 HTTP（block.future）
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 確認此刻已經是 FetchingBanner
      expect(
        container.read(gachaRepositoryProvider).progress,
        isA<FetchingBanner>(),
        reason: '應該已進入 banner fetch 階段',
      );

      notifier.cancelPreparing();
      await updateFut;

      // progress 應為 null（clean cancel），不是 UpdateCompleted with failedBanners
      final finalProgress = container.read(gachaRepositoryProvider).progress;
      expect(
        finalProgress,
        isNull,
        reason:
            'cancel during FetchingBanner 應 clearProgress，不應產生 UpdateCompleted',
      );
    },
  );

  test('setActiveUid 寫入 settings.lastActiveUid', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container
        .read(gachaRepositoryProvider.notifier)
        .setActiveUid('100000001');
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, '100000001');
  });

  test('removeUid（非 active）→ 清 alias/order，lastActiveUid 不變', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({
      'pref.lastActiveUid': '100000001',
      'pref.uidAliases': '{"100000001":"主","100000002":"小"}',
      'pref.uidOrder': '["100000001","100000002"]',
    });

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container
        .read(gachaRepositoryProvider.notifier)
        .removeUid('100000002');
    expect(container.read(gachaRepositoryProvider).activeUid, '100000001');
    final s = await SettingsStorage.load();
    expect(s.lastActiveUid, '100000001');
    expect(s.uidAliases, {'100000001': '主'});
    expect(s.uidOrder, ['100000001']);
  });

  test('removeUid（active）→ fallback 新 active 並寫回 lastActiveUid', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': '100000001'});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container
        .read(gachaRepositoryProvider.notifier)
        .removeUid('100000001');
    expect(container.read(gachaRepositoryProvider).activeUid, '100000002');
    final s = await SettingsStorage.load();
    expect(s.lastActiveUid, '100000002');
  });

  test('removeUid（最後一個）→ activeUid = null 且 lastActiveUid = null', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': '100000001'});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container
        .read(gachaRepositoryProvider.notifier)
        .removeUid('100000001');
    expect(container.read(gachaRepositoryProvider).activeUid, isNull);
    final s = await SettingsStorage.load();
    expect(s.lastActiveUid, isNull);
  });

  test('clearActive 委派給 removeUid', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': '100000001'});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(gachaRepositoryProvider.notifier).clearActive();
    expect(container.read(gachaRepositoryProvider).activeUid, '100000002');
    final s = await SettingsStorage.load();
    expect(s.lastActiveUid, '100000002');
  });

  test('clearAll 清掉所有 UID 偏好', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({
      'pref.lastActiveUid': '100000001',
      'pref.uidAliases': '{"100000001":"主"}',
      'pref.uidOrder': '["100000001"]',
    });

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(gachaRepositoryProvider.notifier).clearAll();
    expect(container.read(gachaRepositoryProvider).activeUid, isNull);
    final s = await SettingsStorage.load();
    expect(s.lastActiveUid, isNull);
    expect(s.uidAliases, isEmpty);
    expect(s.uidOrder, isEmpty);
  });

  test('setActiveUid 不存在的 UID → 不變、不寫 settings', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final beforeReload = await SettingsStorage.load();
    await container
        .read(gachaRepositoryProvider.notifier)
        .setActiveUid('GHOST');
    expect(
      container.read(gachaRepositoryProvider).activeUid,
      '100000001',
    ); // 不變
    final afterReload = await SettingsStorage.load();
    expect(afterReload.lastActiveUid, beforeReload.lastActiveUid);
  });

  test(
    'importAccounts: per-UID overwrite preserves non-imported accounts',
    () async {
      final storage = GachaStorage(tempDir);
      // Existing: 100000001 (old data), 100000003 (untouched)
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {'301': []},
        ),
      );
      await storage.save(
        BannerStorage(
          uid: '100000003',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {'301': []},
        ),
      );
      SharedPreferences.setMockInitialValues({
        'pref.uidAliases': jsonEncode({'100000003': '另一支'}),
      });

      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final newA = BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026, 5, 12),
        banners: const {'301': [], '302': []},
      );
      final newB = BannerStorage(
        uid: '100000002',
        lastUpdated: DateTime.utc(2026, 5, 12),
        banners: const {'301': []},
      );
      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: '100000001',
        accounts: [
          ExportedAccount(data: newA, alias: '主號'),
          ExportedAccount(data: newB),
        ],
      );

      final result = await container
          .read(gachaRepositoryProvider.notifier)
          .importAccounts(bundle);

      expect(result.failedUids, isEmpty);
      expect(result.successAccounts, 2);

      final state = container.read(gachaRepositoryProvider);
      expect(state.byUid.keys.toSet(), {'100000001', '100000002', '100000003'});
      // 100000001 overwritten
      expect(state.byUid['100000001']!.lastUpdated, DateTime.utc(2026, 5, 12));
      // 100000003 preserved
      expect(state.byUid['100000003']!.lastUpdated, DateTime.utc(2026, 1, 1));
      expect(state.activeUid, '100000001');

      // Settings: alias on 100000001 (from bundle), alias on 100000003 (pre-existing, preserved)
      final settings = container.read(settingsProvider);
      expect(settings.uidAliases, {'100000001': '主號', '100000003': '另一支'});
      expect(settings.uidOrder.take(2).toList(), ['100000001', '100000002']);
      expect(settings.lastActiveUid, '100000001');
    },
  );

  test(
    'importAccounts: uidOrder merges imported order first, then remaining',
    () async {
      final storage = GachaStorage(tempDir);
      for (final uid in ['100000001', '100000003', '100000004']) {
        await storage.save(
          BannerStorage(
            uid: uid,
            lastUpdated: DateTime.utc(2026, 1, 1),
            banners: const {'301': []},
          ),
        );
      }

      SharedPreferences.setMockInitialValues({
        'pref.uidOrder': jsonEncode(['100000004', '100000001', '100000003']),
      });

      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: null,
        accounts: [
          ExportedAccount(
            data: BannerStorage(
              uid: '100000002',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
          ),
          ExportedAccount(
            data: BannerStorage(
              uid: '100000001',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
          ),
        ],
      );

      await container
          .read(gachaRepositoryProvider.notifier)
          .importAccounts(bundle);

      final order = container.read(settingsProvider).uidOrder;
      // imported [100000002, 100000001] first, then remaining custom order minus imported = [100000004, 100000003]
      expect(order, ['100000002', '100000001', '100000004', '100000003']);
    },
  );

  test(
    'importAccounts: storage write failure marks UID failed and skips it',
    () async {
      // Inject a storage that fails on UID == "100000002"
      final storage = _FailingStorage(tempDir, failOnUid: '100000002');
      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: '100000002',
        accounts: [
          ExportedAccount(
            data: BannerStorage(
              uid: '100000001',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
            alias: '主號',
          ),
          ExportedAccount(
            data: BannerStorage(
              uid: '100000002',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
          ),
        ],
      );

      final result = await container
          .read(gachaRepositoryProvider.notifier)
          .importAccounts(bundle);

      expect(result.failedUids, ['100000002']);
      expect(result.successAccounts, 1);

      final state = container.read(gachaRepositoryProvider);
      expect(state.byUid.keys, ['100000001']);
      // lastActiveUid asked for 100000002 (failed) → falls back to 100000001
      expect(state.activeUid, '100000001');
      // uidOrder doesn't contain failed 100000002
      expect(
        container.read(settingsProvider).uidOrder.contains('100000002'),
        isFalse,
      );
    },
  );

  test(
    'importAccounts: bundle lastActiveUid switches active to it when imported',
    () async {
      final storage = GachaStorage(tempDir);
      // Existing active = 200000001 (will remain after import)
      await storage.save(
        BannerStorage(
          uid: '200000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {'301': []},
        ),
      );
      SharedPreferences.setMockInitialValues({
        'pref.lastActiveUid': '200000001',
      });

      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(gachaRepositoryProvider).activeUid, '200000001');

      final bundle = AccountsBundle(
        exportedAt: DateTime.utc(2026, 5, 12),
        appVersion: 'x',
        lastActiveUid: '200000002',
        accounts: [
          ExportedAccount(
            data: BannerStorage(
              uid: '200000002',
              lastUpdated: DateTime.utc(2026, 5, 12),
              banners: const {'301': []},
            ),
          ),
        ],
      );

      await container
          .read(gachaRepositoryProvider.notifier)
          .importAccounts(bundle);

      expect(container.read(gachaRepositoryProvider).activeUid, '200000002');
      expect(container.read(settingsProvider).lastActiveUid, '200000002');
    },
  );
  group('logging instrumentation', () {
    setUp(() {
      Logger.root.level = Level.ALL;
    });

    tearDown(() {
      Logger.root.clearListeners();
    });

    test('emits update start and update completed on happy path', () async {
      final records = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(sub.cancel);

      // Reuse happy-path setup from the FetchingBanner cancel test:
      // primer page returns 20 records (forcing fetchBannerWithMerge into
      // page 2), but here the second and subsequent pages return an empty
      // list so the fetch completes successfully.
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      await storage.saveCapturedUrl(
        '100000001',
        'https://hk4e-api-os.hoyoverse.com/event/gacha_info/api/getGachaLog'
            '?authkey=fakekey&authkey_ver=1&sign_type=2'
            '&game_biz=hk4e_global&lang=zh-tw&gacha_type=301&page=1&size=20&end_id=0',
      );

      var hits = 0;
      final container = ProviderContainer(
        overrides: [
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((req) async {
                hits++;
                if (hits == 1) {
                  // primer: 20 records causes fetchBannerWithMerge to page 2
                  return http.Response(
                    jsonEncode({
                      'retcode': 0,
                      'message': 'OK',
                      'data': {
                        'list': List.generate(
                          20,
                          (i) => {
                            'uid': '100000001',
                            'gacha_type': '301',
                            'item_id': '',
                            'count': '1',
                            'time': '2025-09-23 21:27:37',
                            'name': 'x',
                            'lang': 'zh-tw',
                            'item_type': '武器',
                            'rank_type': '3',
                            'id': '17${(99 - i).toString().padLeft(17, '0')}',
                          },
                        ),
                        'page': '1',
                        'size': '20',
                        'total': '0',
                      },
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                // All subsequent pages return empty list → fetch completes
                return http.Response(
                  jsonEncode({
                    'retcode': 0,
                    'message': 'OK',
                    'data': {
                      'list': <dynamic>[],
                      'page': '2',
                      'size': '20',
                      'total': '0',
                    },
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
              cancel: () {},
            ),
          ),
          gachaFetcherProvider.overrideWithValue(
            GachaFetcher(rateLimit: Duration.zero, retryBackoff: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(gachaRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await container.read(gachaRepositoryProvider.notifier).update();

      expect(
        records.where(
          (r) =>
              r.loggerName == 'gacha.repo' &&
              r.message.startsWith('update start'),
        ),
        isNotEmpty,
        reason: 'expected `update start` log',
      );
      expect(
        records.where(
          (r) =>
              r.loggerName == 'gacha.repo' &&
              r.message.startsWith('update completed'),
        ),
        isNotEmpty,
        reason: 'expected `update completed` log',
      );
    });
  });
}

class _FailingStorage extends GachaStorage {
  _FailingStorage(super.baseDir, {required this.failOnUid});
  final String failOnUid;

  @override
  Future<void> save(BannerStorage data) async {
    if (data.uid == failOnUid) {
      throw Exception('simulated failure');
    }
    return super.save(data);
  }
}
