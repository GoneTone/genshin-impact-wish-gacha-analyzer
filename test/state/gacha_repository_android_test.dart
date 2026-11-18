import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/genshin_game_package.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/root_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/shell_exec.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_foreground.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/logcat_url_watch.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import '../helpers/no_game_dir.dart';
import '../helpers/wait_until.dart';

/// 監看命中的祈願 API 網址。
const _url =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?authkey=logcatkey&authkey_ver=1&sign_type=2'
    '&game_biz=hk4e_global&lang=zh-tw&gacha_type=301&page=1&size=20&end_id=0';

/// 依序回傳預先排好結果的 resolver 替身；結果可以是 gate（測試決定何時完成）。
class _FakeResolver extends LogAccessResolver {
  _FakeResolver()
    : super(
        platform: LogAccessPlatform(),
        root: RootShell(),
        keyStore: AdbKeyStore(),
        makeConnector: () => throw UnimplementedError(),
      );

  /// 每次 resolve 的結果，依呼叫順序取用；用完後重複最後一個。
  final results = <FutureOr<LogAccessOutcome> Function()>[];

  /// 每次 resolve 收到的參數。
  final calls = <({LogAccessMethod? preferred, bool force})>[];

  /// 每次 resolve 收到的 abort。
  final aborts = <Future<void>?>[];

  @override
  Future<LogAccessOutcome> resolve({
    LogAccessMethod? preferred,
    bool forceDisableAfterUse = false,
    Future<void>? abort,
  }) async {
    aborts.add(abort);
    calls.add((preferred: preferred, force: forceDisableAfterUse));
    final f = results[(calls.length - 1).clamp(0, results.length - 1)];
    return f();
  }
}

/// 記錄 release 次數、可控制 health stream 的 ready 結果。
class _Ready {
  _Ready({this.leftOn = false, this.events});

  /// release 回傳值。
  final bool leftOn;

  /// 與監看共用的事件順序紀錄（驗證先停監看再 release）。
  final List<String>? events;

  /// release 被呼叫的次數。
  int released = 0;

  /// 健康狀態事件來源。
  final health = StreamController<bool>.broadcast();

  /// shell 執行函式（不會被真正呼叫，watch 是替身）。
  Future<Uint8List> exec(String command) async => Uint8List(0);

  /// 產生 [LogAccessReady]。
  LogAccessReady outcome() => LogAccessReady(
    exec: exec,
    method: LogAccessMethod.wirelessDebugging,
    game: genshinGlobalPackage,
    healthChanges: health.stream,
    release: () async {
      released++;
      events?.add('release');
      return leftOn;
    },
  );
}

/// 記錄每次 start 的監看替身。
class _FakeWatch implements LogcatUrlWatch {
  _FakeWatch([this.events]);

  /// 與 ready 共用的事件順序紀錄。
  final List<String>? events;

  /// 每次 start 的命中結果。
  final hits = <Completer<String?>>[];

  /// 每次 start 收到的 shell 執行函式。
  final execs = <ShellExec>[];

  /// 被取消的 session 編號。
  final cancelled = <int>[];

  /// 設定後 cancel 會等它完成才返回，模擬還在讀取的輪詢。
  Completer<void>? cancelGate;

  /// 設定後 start 會等它完成才回傳 session，模擬第一輪還在跑。
  Completer<void>? startGate;

  @override
  Future<CaptureSession> start(ShellExec exec) async {
    final i = hits.length;
    final c = Completer<String?>();
    hits.add(c);
    execs.add(exec);
    await startGate?.future;
    return CaptureSession(
      result: c.future,
      cancel: () async {
        cancelled.add(i);
        await cancelGate?.future;
        events?.add('cancel');
        if (!c.isCompleted) c.complete(null);
      },
    );
  }
}

/// 記錄無線偵錯開關寫入的系統功能替身。
class _FakePlatform extends LogAccessPlatform {
  /// 每次 setAdbWifiEnabled 收到的值。
  final writes = <bool>[];

  /// 是否有權限開關無線偵錯。
  bool canWrite = true;

  @override
  Future<bool> setAdbWifiEnabled(bool enabled) async {
    writes.add(enabled);
    return canWrite;
  }
}

/// 前景狀態可控制的替身。
class _Foreground extends AppForeground {
  /// 目前是否在前景。
  bool foreground = true;

  /// 回到前景時完成。
  Completer<void> resumed = Completer<void>();

  @override
  bool get isForeground => foreground;
  @override
  Future<void> untilForeground() => resumed.future;
}

/// 永不結束的攔截（Android 不該被呼叫）。
class _NoCapture implements GachaCapture {
  /// `start()` 被呼叫的次數。
  int starts = 0;

  @override
  CaptureSession start() {
    starts++;
    return CaptureSession(
      result: Completer<String?>().future,
      cancel: () async {},
    );
  }
}

/// 祈願 API 回應：[expired] 時回 authkey 失效，否則只有角色活動祈願首頁有一筆紀錄。
http.Response _respond(Uri url, {required bool expired}) {
  final first =
      url.queryParameters['gacha_type'] == '301' &&
      url.queryParameters['end_id'] == '0';
  return http.Response(
    jsonEncode(
      expired
          ? {'retcode': -101, 'message': 'authkey timeout', 'data': null}
          : {
              'retcode': 0,
              'message': 'OK',
              'data': {
                'list': first
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
            },
    ),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late Directory tempDir;
  late _FakeResolver resolver;
  late _FakeWatch watch;
  late _NoCapture capture;
  late List<Uri> fetches;
  late ProviderContainer container;
  late bool expireFirst;
  late bool expireNext;
  late _FakePlatform platform;
  late _Foreground foreground;
  late List<String> events;
  late ProviderContainer Function({bool android}) makeContainer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repo_android_');
    SharedPreferences.setMockInitialValues({});
    resolver = _FakeResolver();
    events = [];
    watch = _FakeWatch(events);
    capture = _NoCapture();
    fetches = [];
    expireFirst = false;
    expireNext = false;
    platform = _FakePlatform();
    foreground = _Foreground();
    final mock = MockClient((req) async {
      fetches.add(req.url);
      final expired = expireNext || (expireFirst && fetches.length == 1);
      expireNext = false;
      return _respond(req.url, expired: expired);
    });
    makeContainer = ({bool android = true}) => ProviderContainer(
      overrides: [
        noGameDirOverride,
        isAndroidProvider.overrideWithValue(android),
        appForegroundProvider.overrideWithValue(foreground),
        logAccessResolverProvider.overrideWithValue(resolver),
        logAccessPlatformProvider.overrideWithValue(platform),
        logcatUrlWatchProvider.overrideWithValue(watch),
        gachaCaptureProvider.overrideWithValue(capture),
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaFetcherProvider.overrideWithValue(
          GachaFetcher(rateLimit: Duration.zero, retryBackoff: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: mock, cancel: () {}),
        ),
      ],
    );
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<GachaRepository> repo() async {
    container.read(gachaRepositoryProvider);
    final n = container.read(gachaRepositoryProvider.notifier);
    await n.waitForBootstrap();
    return n;
  }

  UpdateProgress? progress() =>
      container.read(gachaRepositoryProvider).progress;

  test(
    'ready: watches with the shell, persists method, releases after hit',
    () async {
      final ready = _Ready();
      resolver.results.add(ready.outcome);
      final r = await repo();

      final done = r.update();
      await waitUntil(() => watch.hits.isNotEmpty);
      expect(watch.execs.single, equals(ready.exec));
      expect(progress(), isA<WaitingForCapture>());
      watch.hits[0].complete(_url);
      await done;

      expect(capture.starts, 0, reason: 'android never starts the capture');
      expect(ready.released, 1);
      expect(fetches.first.queryParameters['authkey'], 'logcatkey');
      expect(
        container.read(settingsProvider).logAccessMethod,
        LogAccessMethod.wirelessDebugging,
      );
      expect(progress(), isA<UpdateCompleted>());
      expect((progress()! as UpdateCompleted).wirelessDebuggingLeftOn, isFalse);
    },
  );

  test('ready: waiting state names the game to open', () async {
    final ready = _Ready();
    resolver.results.add(ready.outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    expect(
      (progress()! as WaitingForCapture).gamePackage,
      genshinGlobalPackage,
    );
    ready.health.add(false);
    await waitUntil(() => (progress()! as WaitingForCapture).logConnectionLost);
    expect(
      (progress()! as WaitingForCapture).gamePackage,
      genshinGlobalPackage,
    );
    await r.cancelCapture();
    await done;
  });

  test('blocked: root denial is shown in the waiting state', () async {
    resolver.results.add(
      () => const LogAccessBlocked(
        LogAccessUnavailable.notPaired,
        rootDenied: true,
      ),
    );
    final r = await repo();
    final done = r.update();
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
    );
    expect((progress()! as WaitingForCapture).rootDenied, isTrue);
    await r.cancelCapture();
    await done;
  });

  test('game not installed is a blocked reason', () async {
    resolver.results.add(
      () => const LogAccessBlocked(LogAccessUnavailable.gameNotInstalled),
    );
    final r = await repo();
    final done = r.update();
    await waitUntil(
      () =>
          (progress() as WaitingForCapture?)?.logAccessUnavailable ==
          LogAccessUnavailable.gameNotInstalled,
    );
    expect(watch.hits, isEmpty);
    await r.cancelCapture();
    await done;
    expect(progress(), isNull);
  });

  test(
    'retry after the app had turned wireless on turns it off after use',
    () async {
      // 玩家在系統視窗按「允許」後是系統把無線偵錯打開的；重試時不能當成玩家原本就開著而留著。
      final ready = _Ready();
      resolver.results
        ..add(
          () => const LogAccessBlocked(
            LogAccessUnavailable.networkNotAllowed,
            enabledWireless: true,
          ),
        )
        ..add(ready.outcome);
      final r = await repo();
      final done = r.update();
      await waitUntil(
        () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
      );
      await r.retryLogAccess();
      await waitUntil(() => watch.hits.isNotEmpty);
      expect(resolver.calls[0].force, isFalse);
      expect(resolver.calls[1].force, isTrue);
      await r.cancelCapture();
      await done;
    },
  );

  test('blocked: waits for manual input without watching', () async {
    resolver.results.add(
      () => const LogAccessBlocked(LogAccessUnavailable.notPaired),
    );
    final r = await repo();

    final done = r.update();
    await waitUntil(
      () =>
          (progress() as WaitingForCapture?)?.logAccessUnavailable ==
          LogAccessUnavailable.notPaired,
    );
    expect(watch.hits, isEmpty);
    await r.submitManualUrl(_url);
    await done;
    expect(progress(), isA<UpdateCompleted>());
  });

  test('manual input while watching completes the wait', () async {
    final ready = _Ready(events: events);
    resolver.results.add(ready.outcome);
    final r = await repo();

    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    await r.submitManualUrl(_url);
    await done;
    expect(capture.starts, 0);
    expect(events, ['cancel', 'release']);
    expect(progress(), isA<UpdateCompleted>());
  });

  test('cancel releases only after the in-flight poll stops', () async {
    // 輪詢還在讀取時就 release，讀取失敗會觸發重連、把無線偵錯又打開。
    final ready = _Ready(events: events);
    resolver.results.add(ready.outcome);
    watch.cancelGate = Completer<void>();
    final r = await repo();

    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    unawaited(r.cancelCapture());
    await waitUntil(() => watch.cancelled.isNotEmpty);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(ready.released, 0);
    watch.cancelGate!.complete();
    await done;
    await waitUntil(() => ready.released == 1);
    expect(events, ['cancel', 'release']);
    expect(capture.starts, 0);
    expect(progress(), isNull);
  });

  test(
    'cancel while the watch is starting returns at once, then stops it before release',
    () async {
      // 監看第一輪（取時間、清殘留、啟動）跑完才拿得到 session；這段期間取消要立刻有反應。
      final ready = _Ready(events: events);
      resolver.results.add(ready.outcome);
      final gate = watch.startGate = Completer<void>();
      final r = await repo();

      final done = r.update();
      await waitUntil(() => watch.hits.isNotEmpty);
      await r.cancelCapture();
      await done;
      expect(progress(), isNull);
      expect(ready.released, 0, reason: 'the watch is still starting');

      gate.complete();
      await waitUntil(() => ready.released == 1);
      expect(watch.cancelled, [0]);
      expect(events, ['cancel', 'release']);
    },
  );

  test(
    'cancel while resolving returns at once and releases a late ready',
    () async {
      // root 授權視窗最多等 60 秒；這段期間按取消要立刻有反應。
      final ready = _Ready();
      final gate = Completer<LogAccessOutcome>();
      resolver.results.add(() => gate.future);
      final r = await repo();
      final done = r.update();
      await waitUntil(() => resolver.calls.isNotEmpty);
      await r.cancelCapture();
      await done;
      expect(progress(), isNull);
      var aborted = false;
      unawaited(resolver.aborts.single!.then((_) => aborted = true));
      await waitUntil(() => aborted);
      gate.complete(ready.outcome());
      await waitUntil(() => ready.released == 1);
      expect(watch.hits, isEmpty);
    },
  );

  test('checking state lasts until the resolver answers', () async {
    // 判斷完成前不能引導玩家開遊戲，否則進遊戲後才發現不能自動讀取。
    bool checking() => (progress()! as WaitingForCapture).checkingLogAccess;
    final first = Completer<LogAccessOutcome>();
    final second = Completer<LogAccessOutcome>();
    final ready = _Ready();
    resolver.results
      ..add(() => first.future)
      ..add(() => second.future);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => resolver.calls.isNotEmpty);
    expect(checking(), isTrue);

    first.complete(const LogAccessBlocked(LogAccessUnavailable.notPaired));
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
    );
    expect(checking(), isFalse);

    await r.retryLogAccess();
    await waitUntil(() => resolver.calls.length == 2);
    expect(checking(), isTrue);
    expect((progress()! as WaitingForCapture).logAccessUnavailable, isNull);

    second.complete(ready.outcome());
    await waitUntil(() => watch.hits.isNotEmpty);
    expect(checking(), isFalse);
    watch.hits[0].complete(_url);
    await done;
  });

  test('manual input while resolving is used at once', () async {
    final gate = Completer<LogAccessOutcome>();
    resolver.results.add(() => gate.future);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => resolver.calls.isNotEmpty);
    await r.submitManualUrl(_url);
    await done;
    expect(progress(), isA<UpdateCompleted>());
    gate.complete(const LogAccessBlocked(LogAccessUnavailable.notPaired));
  });

  test('blocked: cancel clears progress', () async {
    resolver.results.add(
      () => const LogAccessBlocked(LogAccessUnavailable.noWifi),
    );
    final r = await repo();
    final done = r.update();
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
    );
    await r.cancelCapture();
    await done;
    expect(progress(), isNull);
    expect(fetches, isEmpty);
  });

  test('retryLogAccess switches blocked wait to watching', () async {
    final ready = _Ready();
    resolver.results
      ..add(
        () => const LogAccessBlocked(LogAccessUnavailable.wirelessDebuggingOff),
      )
      ..add(ready.outcome);
    final r = await repo();

    final done = r.update();
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
    );
    await r.retryLogAccess();
    await waitUntil(() => watch.hits.isNotEmpty);
    expect((progress()! as WaitingForCapture).logAccessUnavailable, isNull);
    watch.hits[0].complete(_url);
    await done;
    expect(progress(), isA<UpdateCompleted>());
  });

  test(
    'cancel during slow resolve releases access and never watches',
    () async {
      final gate = Completer<LogAccessOutcome>();
      final ready = _Ready();
      resolver.results.add(() => gate.future);
      final r = await repo();

      final done = r.update();
      await waitUntil(() => resolver.calls.isNotEmpty);
      await r.cancelCapture();
      gate.complete(ready.outcome());
      await done;

      expect(watch.hits, isEmpty);
      await waitUntil(() => ready.released == 1);
      expect(progress(), isNull);
    },
  );

  test('auth expired waits again on android', () async {
    expireFirst = true;
    final first = _Ready();
    final second = _Ready();
    resolver.results
      ..add(first.outcome)
      ..add(second.outcome);
    final r = await repo();

    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await waitUntil(() => watch.hits.length == 2);
    expect((progress()! as WaitingForCapture).isFallback, isTrue);
    watch.hits[1].complete(_url);
    await done;
    expect(first.released, 1);
    expect(second.released, 1);
    expect(capture.starts, 0);
    expect(progress(), isA<UpdateCompleted>());
  });

  test('expired manual url falls back to the android wait', () async {
    expireFirst = true;
    final ready = _Ready();
    resolver.results.add(ready.outcome);
    final r = await repo();

    final done = r.submitManualUrl(_url);
    await waitUntil(() => watch.hits.isNotEmpty);
    expect(resolver.calls, hasLength(1));
    expect(capture.starts, 0);
    watch.hits[0].complete(_url);
    await done;
    expect(progress(), isA<UpdateCompleted>());
  });

  test('afterPairing passes forceDisableAfterUse', () async {
    resolver.results.add(_Ready().outcome);
    final r = await repo();
    final done = r.update(afterPairing: true);
    await waitUntil(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await done;
    expect(resolver.calls.single.force, isTrue);
  });

  test('preferred method comes from settings', () async {
    final settings = container.read(settingsProvider.notifier);
    await settings.waitForLoad();
    await settings.setLogAccessMethod(LogAccessMethod.root);
    resolver.results.add(_Ready().outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await done;
    expect(resolver.calls.single.preferred, LogAccessMethod.root);
  });

  test('release left wireless debugging on is reported', () async {
    resolver.results.add(_Ready(leftOn: true).outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await done;
    expect((progress()! as UpdateCompleted).wirelessDebuggingLeftOn, isTrue);
  });

  test('health false shows connection lost, true clears it', () async {
    final ready = _Ready();
    resolver.results.add(ready.outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);

    ready.health.add(false);
    await waitUntil(() => (progress()! as WaitingForCapture).logConnectionLost);
    ready.health.add(true);
    await waitUntil(
      () => !(progress()! as WaitingForCapture).logConnectionLost,
    );

    watch.hits[0].complete(_url);
    await done;
    expect(progress(), isA<UpdateCompleted>());
  });

  test('hit while in background waits for the app before fetching', () async {
    final ready = _Ready();
    resolver.results.add(ready.outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    foreground.foreground = false;
    watch.hits[0].complete(_url);
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.credentialReady ?? false,
    );
    expect(fetches, isEmpty, reason: 'background network is blocked');
    foreground.resumed.complete();
    await done;
    expect(fetches, isNotEmpty);
    expect(progress(), isA<UpdateCompleted>());
  });

  test('cancel during teardown after a hit discards the url', () async {
    // 命中後停監看、release 會跨越事件迴圈，這段期間畫面仍有「取消」，按下要生效。
    resolver.results.add(_Ready().outcome);
    watch.cancelGate = Completer<void>();
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    watch.hits[0].complete(_url);
    await waitUntil(() => watch.cancelled.isNotEmpty);
    await r.cancelCapture();
    watch.cancelGate!.complete();
    await done;
    expect(fetches, isEmpty);
    expect(progress(), isNull);
  });

  test('cancel while waiting for the app clears progress', () async {
    resolver.results.add(_Ready().outcome);
    final r = await repo();
    final done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    foreground.foreground = false;
    watch.hits[0].complete(_url);
    await waitUntil(
      () => (progress() as WaitingForCapture?)?.credentialReady ?? false,
    );
    await r.cancelCapture();
    await done;
    expect(fetches, isEmpty);
    expect(progress(), isNull);
  });

  test('resolver error fails the update instead of hanging', () async {
    resolver.results.add(() => throw StateError('secure storage broken'));
    final r = await repo();
    await r.update().timeout(const Duration(seconds: 5));
    expect(progress(), isA<UpdateFailed>());
  });

  test(
    'retry after asking the player to turn wireless on turns it off after use',
    () async {
      // 手動開關模式：開始時是關的，玩家照引導打開；用完要關回去，沒權限關時完成畫面提示。
      final ready = _Ready(leftOn: true);
      resolver.results
        ..add(
          () =>
              const LogAccessBlocked(LogAccessUnavailable.wirelessDebuggingOff),
        )
        ..add(ready.outcome);
      final r = await repo();
      final done = r.update();
      await waitUntil(
        () => (progress() as WaitingForCapture?)?.logAccessUnavailable != null,
      );
      await r.retryLogAccess();
      await waitUntil(() => watch.hits.isNotEmpty);
      expect(resolver.calls.map((c) => c.force), [false, true]);
      watch.hits[0].complete(_url);
      await done;
      expect((progress()! as UpdateCompleted).wirelessDebuggingLeftOn, isTrue);
    },
  );

  test('url source is logged as logcat or manual', () async {
    final sources = <String>[];
    final sub = Logger('capture.android').onRecord.listen((r) {
      if (r.loggerName == 'capture.android' &&
          r.message.startsWith('url source=')) {
        sources.add(r.message);
      }
    });
    addTearDown(sub.cancel);
    resolver.results.add(_Ready().outcome);
    final r = await repo();
    var done = r.update();
    await waitUntil(() => watch.hits.isNotEmpty);
    await r.submitManualUrl(_url);
    await done;
    done = r.forceRecaptureAndUpdate();
    await waitUntil(() => watch.hits.length == 2);
    watch.hits[1].complete(_url);
    await done;
    expect(sources, ['url source=manual', 'url source=logcat']);
  });

  group('after pairing without an android wait', () {
    /// 先跑一次更新，讓作用中帳號有可用的快取網址。
    Future<GachaRepository> withCachedUrl() async {
      resolver.results.add(_Ready().outcome);
      final r = await repo();
      final done = r.update();
      await waitUntil(() => watch.hits.isNotEmpty);
      watch.hits[0].complete(_url);
      await done;
      return r;
    }

    test('a valid cached url turns wireless debugging off', () async {
      // 設定前沒開、為了配對才打開的無線偵錯，沒跑等待也要關回去。
      final r = await withCachedUrl();
      await r.update(afterPairing: true);
      expect(resolver.calls, hasLength(1), reason: 'the cached url is used');
      expect(platform.writes, [false]);
      expect((progress()! as UpdateCompleted).wirelessDebuggingLeftOn, isFalse);
    });

    test('no permission to turn it off shows the completion hint', () async {
      final r = await withCachedUrl();
      platform.canWrite = false;
      await r.update(afterPairing: true);
      expect(platform.writes, [false]);
      expect((progress()! as UpdateCompleted).wirelessDebuggingLeftOn, isTrue);
    });

    test('an expired cached url leaves it to the android wait', () async {
      // 快取失效時改跑等待，由它依 forceDisableAfterUse 處理，這裡不能重複開關。
      final r = await withCachedUrl();
      expireNext = true;
      final done = r.update(afterPairing: true);
      await waitUntil(() => watch.hits.length == 2);
      watch.hits[1].complete(_url);
      await done;
      expect(resolver.calls.last.force, isTrue);
      expect(platform.writes, isEmpty);
      expect(progress(), isA<UpdateCompleted>());
    });
  });

  group('a cancelled wait finishes its teardown before the next one', () {
    // root shell 與無線偵錯是共用的；上一次晚到的 release 不能關掉下一次剛拿到的連線。
    test('late release of an abandoned resolve', () async {
      final gate = Completer<LogAccessOutcome>();
      final first = _Ready(events: events);
      final second = _Ready();
      resolver.results
        ..add(() => gate.future)
        ..add(second.outcome);
      final r = await repo();
      var done = r.update();
      await waitUntil(() => resolver.calls.isNotEmpty);
      await r.cancelCapture();
      await done;

      done = r.update();
      await waitUntil(
        () => (progress() as WaitingForCapture?)?.checkingLogAccess ?? false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolver.calls, hasLength(1));
      gate.complete(first.outcome());
      await waitUntil(() => watch.hits.isNotEmpty);
      expect(first.released, 1);
      expect(resolver.calls, hasLength(2));
      watch.hits[0].complete(_url);
      await done;
      expect(progress(), isA<UpdateCompleted>());
    });

    test('late teardown of a watch that was still starting', () async {
      final first = _Ready(events: events);
      final second = _Ready();
      resolver.results
        ..add(first.outcome)
        ..add(second.outcome);
      final gate = watch.startGate = Completer<void>();
      final r = await repo();
      var done = r.update();
      await waitUntil(() => watch.hits.isNotEmpty);
      await r.cancelCapture();
      await done;

      done = r.update();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolver.calls, hasLength(1));
      gate.complete();
      await waitUntil(() => watch.hits.length == 2);
      expect(events, ['cancel', 'release']);
      expect(resolver.calls, hasLength(2));
      watch.hits[1].complete(_url);
      await done;
      expect(progress(), isA<UpdateCompleted>());
    });

    test('a second cancel keeps the earlier pending teardown', () async {
      final gate = Completer<LogAccessOutcome>();
      final first = _Ready();
      resolver.results
        ..add(() => gate.future)
        ..add(_Ready().outcome);
      final r = await repo();
      var done = r.update();
      await waitUntil(() => resolver.calls.isNotEmpty);
      await r.cancelCapture();
      await done;

      done = r.update();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await r.cancelCapture();
      await done;
      expect(progress(), isNull);

      done = r.update();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolver.calls, hasLength(1));
      gate.complete(first.outcome());
      await waitUntil(() => watch.hits.isNotEmpty);
      expect(first.released, 1);
      watch.hits[0].complete(_url);
      await done;
      expect(progress(), isA<UpdateCompleted>());
    });

    test(
      'cancel during a stuck poll ends at once, then tears down in order',
      () async {
        // 輪詢卡在重連時（最多 20 秒逾時加重新找連接埠），取消不能跟著卡住。
        final first = _Ready(events: events);
        resolver.results
          ..add(first.outcome)
          ..add(_Ready().outcome);
        watch.cancelGate = Completer<void>();
        final r = await repo();
        var done = r.update();
        await waitUntil(() => watch.hits.isNotEmpty);
        await r.cancelCapture();
        await done.timeout(const Duration(seconds: 1));
        expect(progress(), isNull);
        expect(first.released, 0, reason: 'the poll has not stopped yet');

        done = r.update();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(resolver.calls, hasLength(1));
        watch.cancelGate!.complete();
        await waitUntil(() => watch.hits.length == 2);
        expect(events.take(2), ['cancel', 'release']);
        watch.hits[1].complete(_url);
        await done;
        expect(progress(), isA<UpdateCompleted>());
      },
    );
  });

  test('desktop path still uses capture and web cache', () async {
    final c = makeContainer(android: false);
    addTearDown(c.dispose);
    c.read(gachaRepositoryProvider);
    final r = c.read(gachaRepositoryProvider.notifier);
    await r.waitForBootstrap();
    final done = r.update();
    await waitUntil(() => capture.starts == 1);
    expect(resolver.calls, isEmpty);
    expect(watch.hits, isEmpty);
    await r.cancelCapture();
    await done;
  });
}
