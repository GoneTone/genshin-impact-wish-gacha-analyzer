import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCapture implements WishCapture {
  _FakeCapture(this._url);
  final String? _url;

  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(_url), cancel: () async {});
}

class _CountingCapture implements WishCapture {
  _CountingCapture(this._inner, this._onCall);
  final WishCapture _inner;
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
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
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

    // 觸發 build
    final initial = container.read(wishRepositoryProvider);
    expect(initial.activeUid, isNull);
    expect(initial.byUid, isEmpty);

    // 等 bootstrap fire-and-forget 完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final after = container.read(wishRepositoryProvider);
    expect(after.activeUid, isNull);
  });

  test('bootstrap load 有 2 個 UID 檔 → activeUid = 較新者', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: 'B',
        lastUpdated: DateTime.utc(2026, 5, 9), // 較新
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(wishRepositoryProvider);
    expect(state.knownUids.toSet(), {'A', 'B'});
    expect(state.activeUid, 'B');
  });

  test('AuthExpired 連續 2 次 → UpdateFailed with exact message', () async {
    final storage = WishStorage(tempDir);
    // 先 seed 一個 cached URL，讓 update 直接走 fetch path（跳過 MITM 階段）
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      'A',
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
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWith((ref) {
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
    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(wishRepositoryProvider).activeUid, 'A');

    // 觸發 update
    await container.read(wishRepositoryProvider.notifier).update();

    final progress = container.read(wishRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect((progress as UpdateFailed).error, isA<UpdateErrorAuthExpired>());
    // capture 應該被叫 1 次（fallback MITM）；cached URL 第一次直接用，沒 MITM
    expect(captureCalls, 1);
    // fetcher 至少被叫過（兩次嘗試都打 mock）
    expect(fetcherCalls, greaterThan(0));
  });

  test('update() 立刻設定 Preparing（在第一個 await 之前）', () async {
    final storage = WishStorage(tempDir);
    // seed cached URL，update 走 fetch 路徑（不進 MITM）
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      'A',
      'https://example.com/getGachaLog?authkey=x',
    );

    // 用一個永遠不 complete 的 Completer 阻塞 HTTP，這樣 _runUpdate
    // 在進到 probe 階段時會卡住，state 維持在 Preparing
    final block = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
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

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // bootstrap

    final notifier = container.read(wishRepositoryProvider.notifier);
    final updateFut = notifier.update();

    // 把 microtask 跑一輪，讓 loadCapturedUrl 完成、進到 probe 並 await
    // mock client 的 future（永遠不 complete），此刻 state.progress 應該是 Preparing
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(
      container.read(wishRepositoryProvider).progress,
      isA<Preparing>(),
      reason: '進入 probe 階段時 state 應該維持在 Preparing',
    );

    // cleanup
    notifier.cancelPreparing();
    await updateFut;
  });

  test('cancelPreparing → 中斷 HTTP → progress 回到 null', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      'A',
      'https://example.com/getGachaLog?authkey=x',
    );

    final block = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
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

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final notifier = container.read(wishRepositoryProvider.notifier);
    final updateFut = notifier.update();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // act：呼叫 cancelPreparing
    notifier.cancelPreparing();
    await updateFut;

    // assert：progress 應為 null（取消），不是 UpdateFailed
    expect(container.read(wishRepositoryProvider).progress, isNull);
    // 既有資料保留
    expect(container.read(wishRepositoryProvider).activeUid, 'A');
  });

  test('probe 階段真實 ClientException（非取消） → UpdateFailed', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl(
      'A',
      'https://example.com/getGachaLog?authkey=x',
    );

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
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

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await container.read(wishRepositoryProvider.notifier).update();

    final progress = container.read(wishRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect((progress as UpdateFailed).error, isA<UpdateErrorOther>());
  });

  test('clearProgress 把 progress 重設為 null', () async {
    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(WishStorage(tempDir)),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(wishRepositoryProvider.notifier);
    // 等 bootstrap 完成，避免 async 工作洩漏到測試邊界後
    await Future<void>.delayed(const Duration(milliseconds: 50));

    notifier.debugSetProgress(const UpdateFailed(UpdateErrorOther('test')));
    expect(
      container.read(wishRepositoryProvider).progress,
      isA<UpdateFailed>(),
    );

    notifier.clearProgress();
    expect(container.read(wishRepositoryProvider).progress, isNull);
  });

  test('bootstrap：lastActiveUid 命中 → 用它（不用最新）', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: 'B',
        lastUpdated: DateTime.utc(2026, 5, 9), // 較新
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({'pref.lastActiveUid': 'A'});

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(wishRepositoryProvider).activeUid, 'A');
  });

  test(
    'bootstrap：lastActiveUid 失效 → fallback 為 mergeUidOrder.first 並寫回',
    () async {
      final storage = WishStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: 'A',
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
          uid: 'B',
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
          wishStorageProvider.overrideWithValue(storage),
          wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(wishRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(wishRepositoryProvider).activeUid, 'B'); // 較新
      // 寫回 settings
      final reloaded = await SettingsStorage.load();
      expect(reloaded.lastActiveUid, 'B');
    },
  );

  test('bootstrap：lastActiveUid 為 null → fallback 為最新並寫回', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(wishRepositoryProvider).activeUid, 'A');
    final reloaded = await SettingsStorage.load();
    expect(reloaded.lastActiveUid, 'A');
  });

  test('bootstrap：uidOrder 影響 fallback 順序', () async {
    final storage = WishStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: 'A',
        lastUpdated: DateTime.utc(2026, 1, 1),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.save(
      BannerStorage(
        uid: 'B',
        lastUpdated: DateTime.utc(2026, 5, 9),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    SharedPreferences.setMockInitialValues({
      'pref.uidOrder': '["A","B"]', // 自訂 A 在前
    });

    final container = ProviderContainer(
      overrides: [
        wishStorageProvider.overrideWithValue(storage),
        wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: MockClient((_) async => http.Response('{}', 200)),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(wishRepositoryProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // lastActiveUid 為 null → fallback 走 mergeUidOrder.first → 自訂順序的第一個 = A
    expect(container.read(wishRepositoryProvider).activeUid, 'A');
  });

  test(
    'cancelPreparing 在 FetchingBanner 階段也應 clearProgress (非 UpdateCompleted)',
    () async {
      final storage = WishStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: 'A',
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
        'A',
        'https://example.com/getGachaLog?authkey=x',
      );

      // 第一次 request（probe 第一個 banner，命中 → primer，state 還在 Preparing）
      // 第二次 request 起會卡住（fetchBannerWithMerge 第二頁的 HTTP），這時 state
      // 已經被 onProgress 推進到 FetchingBanner。
      var hits = 0;
      final block = Completer<http.Response>();
      final container = ProviderContainer(
        overrides: [
          wishStorageProvider.overrideWithValue(storage),
          wishCaptureProvider.overrideWithValue(_FakeCapture(null)),
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
                              'uid': 'A',
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
          wishFetcherProvider.overrideWithValue(
            WishFetcher(rateLimit: Duration.zero, retryBackoff: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(wishRepositoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final notifier = container.read(wishRepositoryProvider.notifier);
      final updateFut = notifier.update();

      // 等更長一點，讓 probe 完成（命中第一個 banner）、進入 fetchBannerWithMerge、
      // 處理 primer（onProgress → state=FetchingBanner）、再 await 第二頁 HTTP（block.future）
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // 確認此刻已經是 FetchingBanner
      expect(
        container.read(wishRepositoryProvider).progress,
        isA<FetchingBanner>(),
        reason: '應該已進入 banner fetch 階段',
      );

      // act：取消
      notifier.cancelPreparing();
      await updateFut;

      // assert：progress 應為 null（clean cancel），不是 UpdateCompleted with failedBanners
      final finalProgress = container.read(wishRepositoryProvider).progress;
      expect(
        finalProgress,
        isNull,
        reason:
            'cancel during FetchingBanner 應 clearProgress，不應產生 UpdateCompleted',
      );
    },
  );
}
