import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_url_watch.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 測試用的祈願 API 網址。
const _url =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?authkey=fakekey&authkey_ver=1&sign_type=2'
    '&game_biz=hk4e_global&lang=zh-tw&gacha_type=301&page=1&size=20&end_id=0';

/// 測試用的遊戲資料夾。
const _gameDir = r'D:\Games\Genshin Impact game';

/// 測試用的定位結果。
const _loc = GameDirLocation(_gameDir, GameDirSource.setting);

/// 結果與取消都由測試以 [Completer] 控制的攔截 fake。
class _FakeCapture implements GachaCapture {
  /// 建立 fake；[completeOnCancel] 為 true 時 `cancel()` 會以 null 完成結果。
  _FakeCapture({
    this.completeOnCancel = false,
    this.hangCancel = false,
    this.failCancel = false,
  });

  /// 為 true 時 `cancel()` 會以 null 完成 [result]。
  final bool completeOnCancel;

  /// 為 true 時 `cancel()` 永不返回（模擬根憑證確認視窗開著時 stop 卡住）。
  final bool hangCancel;

  /// 為 true 時 `cancel()` 丟錯（模擬 Rust `stop_capture` 失敗）。
  final bool failCancel;

  /// 攔截結果，由測試決定何時完成。
  final result = Completer<String?>();

  /// `cancel()` 被呼叫的次數。
  int cancelCalls = 0;

  @override
  CaptureSession start() => CaptureSession(
    result: result.future,
    cancel: () async {
      cancelCalls++;
      if (hangCancel) return Completer<void>().future;
      if (failCancel) throw Exception('stop failed');
      if (completeOnCancel && !result.isCompleted) result.complete(null);
    },
  );
}

/// 記錄每次 `start` 的快取監看 fake；命中與取消都由測試控制。
class _FakeWatch implements GachaUrlWatch {
  /// 每個 session 的結果，依 `start` 順序排列。
  final hits = <Completer<String?>>[];

  /// 每次 `start` 收到的遊戲資料夾。
  final dirs = <String>[];

  /// 被 `cancel()` 的 session 索引。
  final cancelled = <int>[];

  @override
  CaptureSession start(String gameDir) {
    final i = hits.length;
    final c = Completer<String?>();
    hits.add(c);
    dirs.add(gameDir);
    return CaptureSession(
      result: c.future,
      cancel: () async {
        cancelled.add(i);
        if (!c.isCompleted) c.complete(null);
      },
    );
  }
}

/// 回傳可變的固定定位結果並計數的 locator fake。
class _FakeLocator extends GameDirLocator {
  /// 建立 fake，[location] 為 `locate` 的回傳值。
  _FakeLocator(this.location);

  /// `locate` 的回傳值；null 代表找不到遊戲資料夾。
  GameDirLocation? location;

  /// `locate` 被呼叫的次數。
  int calls = 0;

  @override
  Future<GameDirLocation?> locate({String? settingDir}) async {
    calls++;
    return location;
  }
}

/// 反覆讓出事件迴圈直到 [cond] 成立，最多等 5 秒。
Future<void> _until(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition never became true within 5s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// 組出 retcode 0 的祈願 API 回應，[list] 為紀錄列表。
http.Response _ok(List<Map<String, dynamic>> list) => http.Response(
  jsonEncode({
    'retcode': 0,
    'message': 'OK',
    'data': {'list': list, 'page': '1', 'size': '20', 'total': '0'},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// probe 用的單筆紀錄。
final Map<String, dynamic> _record = {
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
};

/// 比快測試的 container 與觀測點。
typedef _Race = ({
  ProviderContainer container,
  GachaRepository repo,
  List<Uri> hits,
  List<bool> captureDoneAtHit,
});

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_web_cache_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立比快用的 container 並等 bootstrap 完成。
  ///
  /// [respond] 依請求序號（從 1 起算）決定回應；預設第一個請求回一筆紀錄、其餘為空。
  Future<_Race> race({
    required _FakeCapture capture,
    required _FakeWatch watch,
    required _FakeLocator locator,
    GachaStorage? storage,
    http.Response Function(int hit)? respond,
  }) async {
    final hits = <Uri>[];
    final captureDoneAtHit = <bool>[];
    final mock = MockClient((req) async {
      hits.add(req.url);
      captureDoneAtHit.add(capture.result.isCompleted);
      return respond?.call(hits.length) ??
          (hits.length == 1 ? _ok([_record]) : _ok(const []));
    });
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(
          storage ?? GachaStorage(tempDir),
        ),
        gachaCaptureProvider.overrideWithValue(capture),
        gachaUrlWatchProvider.overrideWithValue(watch),
        gameDirLocatorProvider.overrideWithValue(locator),
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
    return (
      container: container,
      repo: repo,
      hits: hits,
      captureDoneAtHit: captureDoneAtHit,
    );
  }

  /// 收集測試期間所有 log 紀錄，測試結束時自動取消訂閱。
  List<LogRecord> recordLogs() {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    return records;
  }

  /// 是否為快取勝出後開始等攔截自行結束的 log。
  bool isGraceStart(LogRecord r) =>
      r.loggerName == 'gacha.webCache' &&
      r.message.startsWith('cache won, waiting');

  /// 目前的更新進度。
  UpdateProgress? progressOf(_Race t) =>
      t.container.read(gachaRepositoryProvider).progress;

  /// 目前進度為 [WaitingForCapture] 時回傳它，否則為 null。
  WaitingForCapture? waitingOf(_Race t) => switch (progressOf(t)) {
    final WaitingForCapture w => w,
    _ => null,
  };

  /// 回傳一個 list，在等待畫面首次切到「攔截失效」時記下 [capture] 當下的 `cancel()` 次數。
  List<int> cancelsAtUnavailable(_Race t, _FakeCapture capture) {
    final seen = <int>[];
    t.container.listen(gachaRepositoryProvider, (_, s) {
      final p = s.progress;
      if (seen.isEmpty && p is WaitingForCapture && p.captureUnavailable) {
        seen.add(capture.cancelCalls);
      }
    });
    return seen;
  }

  test(
    'cache wins: capture stops by itself within grace, not cancelled',
    () async {
      final records = recordLogs();
      final capture = _FakeCapture();
      final watch = _FakeWatch();
      final t = await race(
        capture: capture,
        watch: watch,
        locator: _FakeLocator(_loc),
      );

      final done = t.repo.update();
      await _until(() => watch.hits.isNotEmpty);
      expect(watch.dirs.single, _gameDir);
      watch.hits[0].complete(_url);

      await _until(() => records.any(isGraceStart));
      expect(t.hits, isEmpty, reason: 'no fetch before capture stops');
      expect(capture.cancelCalls, 0);

      capture.result.complete(null);
      await done.timeout(const Duration(seconds: 5));

      expect(capture.cancelCalls, 0);
      expect(t.hits, isNotEmpty);
      expect(t.captureDoneAtHit, everyElement(isTrue));
      expect(progressOf(t), isA<UpdateCompleted>());
    },
  );

  test('cache wins: capture still running after grace is cancelled', () async {
    const grace = Duration(milliseconds: 100);
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    t.repo.debugSetCacheWinCaptureGrace(grace);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    final sinceHit = Stopwatch()..start();
    watch.hits[0].complete(_url);

    await _until(() => capture.cancelCalls > 0);
    expect(sinceHit.elapsed, greaterThanOrEqualTo(grace));
    expect(t.hits, isEmpty, reason: 'no fetch before capture teardown');

    capture.result.complete(null);
    await done.timeout(const Duration(seconds: 5));

    expect(capture.cancelCalls, 1);
    expect(t.hits, isNotEmpty);
    expect(t.captureDoneAtHit, everyElement(isTrue));
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('user cancel during cache-won grace aborts promptly', () async {
    final records = recordLogs();
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await _until(() => records.any(isGraceStart));
    await t.repo.cancelCapture();
    // 預設寬限 3 秒；1 秒內結束代表取消沒等寬限跑完。
    await done.timeout(const Duration(seconds: 1));

    expect(capture.cancelCalls, 1);
    expect(t.hits, isEmpty);
    expect(progressOf(t), isNull);
  });

  test('cache wins: capture teardown error is ignored', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    t.repo.debugSetCacheWinCaptureGrace(Duration.zero);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await _until(() => capture.cancelCalls > 0);
    capture.result.completeError(Exception('proxy restore failed'));
    await done.timeout(const Duration(seconds: 5));

    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('cache wins: capture result error within grace is ignored', () async {
    final records = recordLogs();
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await _until(() => records.any(isGraceStart));
    capture.result.completeError(Exception('proxy restore failed'));
    await done.timeout(const Duration(seconds: 5));

    expect(capture.cancelCalls, 0);
    expect(
      records.any(
        (r) =>
            r.loggerName == 'gacha.webCache' &&
            r.level == Level.WARNING &&
            r.message ==
                'capture teardown error after cache win error=_Exception',
      ),
      isTrue,
    );
    expect(t.hits, isNotEmpty);
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('capture wins: cache watch cancelled', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    capture.result.complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(watch.cancelled, [0]);
    expect(capture.cancelCalls, 0);
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('capture error: stops capture, then waits on cache only', () async {
    final records = recordLogs();
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    final cancels = cancelsAtUnavailable(t, capture);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    capture.result.completeError(Exception('certificate rejected'));
    await _until(() => waitingOf(t)?.captureUnavailable ?? false);

    expect(cancels, [1], reason: 'capture stopped before cache-only wait');
    expect(waitingOf(t)!.gameDirMissing, isFalse);
    expect(watch.cancelled, isEmpty);
    expect(
      records.any(
        (r) =>
            r.loggerName == 'gacha.webCache' &&
            r.level == Level.WARNING &&
            r.message == 'capture failed error=_Exception',
      ),
      isTrue,
    );

    watch.hits[0].complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(capture.cancelCalls, 1);
    expect(t.hits, isNotEmpty);
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('capture ended without url (not user cancel): stops capture, '
      'then waits on cache only', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    final cancels = cancelsAtUnavailable(t, capture);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    capture.result.complete(null);
    await _until(() => waitingOf(t)?.captureUnavailable ?? false);
    expect(cancels, [1], reason: 'capture stopped before cache-only wait');
    expect(waitingOf(t)!.gameDirMissing, isFalse);

    watch.hits[0].complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(capture.cancelCalls, 1);
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('failed capture stop error is ignored, still waits on cache', () async {
    final records = recordLogs();
    final capture = _FakeCapture(failCancel: true);
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    capture.result.complete(null);
    await _until(() => waitingOf(t)?.captureUnavailable ?? false);
    expect(capture.cancelCalls, 1);
    expect(
      records.any(
        (r) =>
            r.loggerName == 'gacha.webCache' &&
            r.level == Level.WARNING &&
            r.message == 'failed capture stop error=_Exception',
      ),
      isTrue,
    );

    watch.hits[0].complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('failed capture stop hangs: times out, still waits on cache', () async {
    final records = recordLogs();
    final capture = _FakeCapture(hangCancel: true);
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    t.repo.debugSetCancelTeardownTimeout(const Duration(milliseconds: 20));

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    capture.result.complete(null);
    await _until(() => waitingOf(t)?.captureUnavailable ?? false);
    expect(capture.cancelCalls, 1);
    expect(
      records.any(
        (r) =>
            r.loggerName == 'gacha.webCache' &&
            r.level == Level.WARNING &&
            r.message == 'failed capture stop error=TimeoutException',
      ),
      isTrue,
    );

    watch.hits[0].complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('capture error and no game dir: shows picker, cancel works', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final locator = _FakeLocator(null);
    final t = await race(capture: capture, watch: watch, locator: locator);

    final done = t.repo.update();
    await _until(() => locator.calls > 0);
    capture.result.completeError(Exception('port in use'));
    await _until(() => waitingOf(t)?.gameDirMissing ?? false);
    expect(waitingOf(t)!.captureUnavailable, isTrue);

    await t.repo.cancelCapture();
    await done.timeout(const Duration(seconds: 5));

    expect(watch.hits, isEmpty);
    expect(t.hits, isEmpty);
    expect(progressOf(t), isNull);
  });

  test('user cancel stops both', () async {
    final capture = _FakeCapture(completeOnCancel: true);
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    await t.repo.cancelCapture();
    await done.timeout(const Duration(seconds: 5));

    expect(capture.cancelCalls, greaterThan(0));
    expect(watch.cancelled, contains(0));
    expect(t.hits, isEmpty);
    expect(progressOf(t), isNull);
  });

  test(
    'user cancel with failing capture stop still releases the wait',
    () async {
      final capture = _FakeCapture(failCancel: true);
      final watch = _FakeWatch();
      final t = await race(
        capture: capture,
        watch: watch,
        locator: _FakeLocator(_loc),
      );

      final done = t.repo.update();
      await _until(() => watch.hits.isNotEmpty);
      await t.repo.cancelCapture();
      await done.timeout(const Duration(seconds: 5));

      expect(capture.cancelCalls, greaterThan(0));
      expect(progressOf(t), isNull);
    },
  );

  test('user cancel during cache-won teardown aborts', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    t.repo.debugSetCacheWinCaptureGrace(Duration.zero);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await _until(() => capture.cancelCalls > 0);
    await t.repo.cancelCapture();
    await done.timeout(const Duration(seconds: 5));
    capture.result.complete(null);

    expect(t.hits, isEmpty);
    expect(progressOf(t), isNull);
  });

  test('user cancel works while cache-won cancel() hangs', () async {
    final capture = _FakeCapture(hangCancel: true);
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
    );
    t.repo.debugSetCancelTeardownTimeout(const Duration(milliseconds: 20));
    t.repo.debugSetCacheWinCaptureGrace(Duration.zero);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await _until(() => capture.cancelCalls > 0);
    await t.repo.cancelCapture();
    await done.timeout(const Duration(seconds: 5));

    expect(t.hits, isEmpty);
    expect(progressOf(t), isNull);
  });

  test('no game dir: capture only', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final locator = _FakeLocator(null);
    final t = await race(capture: capture, watch: watch, locator: locator);

    final done = t.repo.update();
    await _until(() => locator.calls > 0);
    capture.result.complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(watch.hits, isEmpty);
    expect(t.hits, isNotEmpty);
    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('restartWebCacheWatch re-locates and restarts', () async {
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final locator = _FakeLocator(null);
    final t = await race(capture: capture, watch: watch, locator: locator);

    await t.repo.restartWebCacheWatch();
    expect(locator.calls, 0, reason: 'no-op outside WaitingForCapture');

    final done = t.repo.update();
    await _until(() => locator.calls > 0);
    capture.result.completeError(Exception('certificate rejected'));
    await _until(() => waitingOf(t)?.gameDirMissing ?? false);

    // 使用者在說明視窗選好資料夾 → 監看接上，提示換回只等快取。
    locator.location = _loc;
    await t.repo.restartWebCacheWatch();
    expect(watch.hits, hasLength(1));
    expect(waitingOf(t)!.captureUnavailable, isTrue);
    expect(waitingOf(t)!.gameDirMissing, isFalse);

    await t.repo.restartWebCacheWatch();
    expect(locator.calls, 3);
    expect(watch.hits, hasLength(2));
    expect(watch.cancelled, [0]);

    watch.hits[1].complete(_url);
    await done.timeout(const Duration(seconds: 5));

    expect(progressOf(t), isA<UpdateCompleted>());
  });

  test('fallback recapture also races', () async {
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '100000001',
        lastUpdated: DateTime.utc(2026),
        banners: const {'301': [], '302': [], '500': [], '200': [], '100': []},
      ),
    );
    await storage.saveCapturedUrl('100000001', _url);
    final capture = _FakeCapture();
    final watch = _FakeWatch();
    final t = await race(
      capture: capture,
      watch: watch,
      locator: _FakeLocator(_loc),
      storage: storage,
      // 第一個請求 auth 過期 → 重新取得網址；第二輪 probe 拿到紀錄、其餘為空。
      respond: (hit) => switch (hit) {
        1 => http.Response(
          '{"retcode":-101,"message":"authkey timeout","data":null}',
          200,
          headers: {'content-type': 'application/json'},
        ),
        2 => _ok([_record]),
        _ => _ok(const []),
      },
    );
    t.repo.debugSetCacheWinCaptureGrace(Duration.zero);

    final done = t.repo.update();
    await _until(() => watch.hits.isNotEmpty);
    expect(waitingOf(t)!.isFallback, isTrue);
    watch.hits[0].complete(_url);
    await _until(() => capture.cancelCalls > 0);
    capture.result.complete(null);
    await done.timeout(const Duration(seconds: 5));

    expect(progressOf(t), isA<UpdateCompleted>());
  });
}
