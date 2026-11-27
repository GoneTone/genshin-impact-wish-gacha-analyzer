import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_game_dir.dart';
import '../helpers/wait_until.dart';

/// 手動輸入的祈願 API 網址。
const _url =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?authkey=manualkey&authkey_ver=1&sign_type=2'
    '&game_biz=hk4e_global&lang=zh-tw&gacha_type=301&page=1&size=20&end_id=0';

/// 結果由測試以 [Completer] 控制的攔截 fake，記錄 `start` 與 `cancel` 次數。
class _FakeCapture implements GachaCapture {
  /// 攔截結果。
  final result = Completer<String?>();

  /// `start()` 被呼叫的次數。
  int starts = 0;

  /// `cancel()` 被呼叫的次數。
  int cancelCalls = 0;

  @override
  CaptureSession start() {
    starts++;
    return CaptureSession(
      result: result.future,
      cancel: () async {
        cancelCalls++;
        if (!result.isCompleted) result.complete(null);
      },
    );
  }
}

/// 第一個請求回一筆紀錄、其餘為空的祈願 API 回應。
http.Response _respond(int n) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {
      'list': n == 1
          ? [
              {
                'uid': '100000001',
                'gacha_type': '301',
                'item_id': '',
                'count': '1',
                'time': '2025-09-23 21:27:37',
                'name': 'x',
                'lang': 'zh-tw',
                'item_type': '武器',
                'rank_type': '3',
                'id': '1700000000000000001',
              },
            ]
          : <Object>[],
      'page': '1',
      'size': '20',
      'total': '0',
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_manual_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立 container 並等 bootstrap 完成；[hits] 收集所有送出的請求網址。
  ///
  /// [gate] 非 null 時，每個請求都等它完成才回應。
  Future<(GachaRepository, ProviderContainer, _FakeCapture, List<Uri>)> setup({
    Future<void>? gate,
  }) async {
    final capture = _FakeCapture();
    final hits = <Uri>[];
    final mock = MockClient((req) async {
      hits.add(req.url);
      await gate;
      return _respond(hits.length);
    });
    final container = ProviderContainer(
      overrides: [
        noGameDirOverride,
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(capture),
        gachaFetcherProvider.overrideWithValue(
          GachaFetcher(rateLimit: Duration.zero, retryBackoff: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: mock, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(gachaRepositoryProvider);
    final repo = container.read(gachaRepositoryProvider.notifier);
    await repo.waitForBootstrap();
    return (repo, container, capture, hits);
  }

  test(
    'manual url completes a pending capture wait via the cache-win path',
    () async {
      final (repo, container, capture, hits) = await setup();
      repo.debugSetCacheWinCaptureGrace(const Duration(milliseconds: 50));

      final done = repo.update();
      await waitUntil(
        () =>
            container.read(gachaRepositoryProvider).progress
                is WaitingForCapture &&
            capture.starts == 1,
      );
      await repo.submitManualUrl(_url);
      await done.timeout(const Duration(seconds: 5));

      expect(capture.cancelCalls, 1, reason: 'capture stopped after grace');
      expect(hits, isNotEmpty);
      expect(hits.first.queryParameters['authkey'], 'manualkey');
      expect(
        container.read(gachaRepositoryProvider).progress,
        isA<UpdateCompleted>(),
      );
    },
  );

  test(
    'manual url during the desktop wait cancels capture without grace',
    () async {
      final (repo, container, capture, hits) = await setup();
      repo.debugSetCacheWinCaptureGrace(const Duration(seconds: 30));

      final done = repo.update();
      await waitUntil(
        () =>
            container.read(gachaRepositoryProvider).progress
                is WaitingForCapture &&
            capture.starts == 1,
      );
      await repo.submitManualUrl(_url);
      await done.timeout(const Duration(seconds: 5));

      expect(capture.cancelCalls, 1);
      expect(hits, isNotEmpty);
    },
  );

  test('manual url while fetching is ignored', () async {
    final gate = Completer<void>();
    final (repo, _, capture, hits) = await setup(gate: gate.future);

    final first = repo.submitManualUrl(_url);
    await waitUntil(() => hits.length == 1);
    await repo.submitManualUrl('$_url&x=1');

    expect(hits, hasLength(1), reason: 'second submit did not start a fetch');
    expect(capture.starts, 0);
    gate.complete();
    await first.timeout(const Duration(seconds: 5));
  });

  test('manual url when idle starts an update with that url', () async {
    final (repo, container, capture, hits) = await setup();

    await repo.submitManualUrl(_url);

    expect(capture.starts, 0, reason: 'no capture on manual url');
    expect(hits.first.queryParameters['authkey'], 'manualkey');
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });
}
