import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/concurrent_pool.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_foreground.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/logcat_url_watch.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_url_watch.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';

/// probeUid 回傳 null 時拋出，轉成 [UpdateErrorNoRecords]。
class _NoRecordsException implements Exception {
  const _NoRecordsException();
}

/// 雲端同步請求匯入時，已有更新或匯入進行中而無法執行時拋出；呼叫端應稍後重試。
class CloudSyncBusyException implements Exception {
  /// 建立 [CloudSyncBusyException]。
  const CloudSyncBusyException();

  @override
  String toString() => 'CloudSyncBusyException';
}

/// 祈願資料整體狀態，包含帳號資料、更新進度與 bootstrap 旗標。
@immutable
class GachaState {
  /// 建立 [GachaState]。
  const GachaState({
    this.activeUid,
    this.byUid = const {},
    this.progress,
    this.isBootstrapping = true,
  });

  /// 目前作用中的帳號 UID；null 表示無帳號。
  final String? activeUid;

  /// UID → 該帳號存檔資料。
  final Map<String, BannerStorage> byUid;

  /// 目前更新進度；null 表示無進行中的更新。
  final UpdateProgress? progress;

  /// true 表示首次從本地存檔載入尚未完成。
  final bool isBootstrapping;

  /// 作用中帳號的存檔資料；無作用中帳號時為 null。
  BannerStorage? get activeData => activeUid == null ? null : byUid[activeUid];

  /// 所有已知 UID。
  Iterable<String> get knownUids => byUid.keys;

  /// 複製並選擇性覆蓋欄位；[clearActiveUid] / [clearProgress] 為 true 時強制清除對應欄位。
  GachaState copyWith({
    String? activeUid,
    bool clearActiveUid = false,
    Map<String, BannerStorage>? byUid,
    UpdateProgress? progress,
    bool clearProgress = false,
    bool? isBootstrapping,
  }) => GachaState(
    activeUid: clearActiveUid ? null : (activeUid ?? this.activeUid),
    byUid: byUid ?? this.byUid,
    progress: clearProgress ? null : (progress ?? this.progress),
    isBootstrapping: isBootstrapping ?? this.isBootstrapping,
  );
}

// ─── Providers ───

/// 必須在 main.dart 用 overrideWithValue 注入（baseDir 需要 async 取得）
final gachaStorageProvider = Provider<GachaStorage>((ref) {
  throw UnimplementedError('gachaStorageProvider must be overridden in main()');
});

/// [GachaCapture] 實作，預設為 [RustGachaCapture]。
final gachaCaptureProvider = Provider<GachaCapture>(
  (ref) => RustGachaCapture(),
);

/// [GachaFetcher] provider，負責從 Hoyoverse API 拉取祈願紀錄。
final gachaFetcherProvider = Provider<GachaFetcher>((ref) => GachaFetcher());

/// 每次 update 用一個獨立的 [CancellableHttpClient]（cancel 不會影響其他連線）。
final cancellableHttpClientFactoryProvider =
    Provider<CancellableHttpClientFactory>(
      (ref) => createIoCancellableHttpClient,
    );

/// [GachaRepository] 的 Riverpod provider。
final gachaRepositoryProvider = NotifierProvider<GachaRepository, GachaState>(
  GachaRepository.new,
);

// ─── Notifier ───

/// 祈願資料狀態管理，統一處理 bootstrap、更新、匯入與刪除。
class GachaRepository extends Notifier<GachaState> {
  static final _log = Logger('gacha.repo');

  /// Logger 實例（force-refetch 流程，獨立子樹以利日誌過濾）。
  static final _refetchLog = Logger('gacha.hoyowiki.refetch');

  /// Logger 實例（匯入流程，獨立子樹以利日誌過濾）。
  static final _importLog = Logger('gacha.import');

  /// Logger 實例（非破壞性 metadata 更新流程）。
  static final _refreshMetaLog = Logger('gacha.hoyowiki.refreshMetadata');

  /// 手動輸入網址流程的 logger（與對話框同一棵樹）。
  static final _manualLog = Logger('capture.manual');

  /// Logger 實例（雲端同步觸發的匯入與補抓）。
  static final _cloudSyncLog = Logger('cloudsync.sync');

  /// 網頁快取 URL 來源 logger（與監看器、locator 同一棵樹）。
  static final _webCacheLog = Logger('gacha.webCache');

  /// Android 讀取系統記錄流程的 logger。
  static final _androidLog = Logger('capture.android');

  /// build() 內 `_bootstrapLoad()` 完成的 future，供測試 await。
  Completer<void>? _bootstrapCompleter;

  /// 等待初次 bootstrap 完成（load 既有 UID 與 settings）。
  Future<void> waitForBootstrap() =>
      _bootstrapCompleter?.future ?? Future.value();

  @override
  GachaState build() {
    _bootstrapLoad();
    return const GachaState();
  }

  /// 從本地存檔載入全部帳號資料，完成後設定 [GachaState.isBootstrapping] 為 false。
  Future<void> _bootstrapLoad() async {
    _bootstrapCompleter = Completer<void>();
    try {
      final storage = ref.read(gachaStorageProvider);
      final settingsNotifier = ref.read(settingsProvider.notifier);
      await settingsNotifier.waitForLoad();
      if (!ref.mounted) return;

      final uids = await storage.listKnownUids();
      if (!ref.mounted) return;

      final byUid = <String, BannerStorage>{};
      for (final uid in uids) {
        final data = await storage.load(uid);
        if (!ref.mounted) return;
        if (data != null) byUid[uid] = data;
      }

      if (byUid.isEmpty) {
        state = state.copyWith(byUid: byUid, isBootstrapping: false);
        return;
      }

      final settings = ref.read(settingsProvider);
      final ordered = mergeUidOrder(
        knownUids: byUid.keys,
        customOrder: settings.uidOrder,
        lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
      );

      final saved = settings.lastActiveUid;
      final activeUid = (saved != null && byUid.containsKey(saved))
          ? saved
          : ordered.first;

      state = state.copyWith(
        byUid: byUid,
        activeUid: activeUid,
        isBootstrapping: false,
      );

      if (saved != activeUid) {
        await settingsNotifier.setLastActiveUid(activeUid);
        if (!ref.mounted) return;
      }

      BannerStorage? newest;
      for (final d in byUid.values) {
        if (newest == null || d.lastUpdated.isAfter(newest.lastUpdated)) {
          newest = d;
        }
      }
      if (newest != null) {
        final seedLang = _seedLangFromData(newest);
        if (seedLang != null) {
          await settingsNotifier.seedDataLanguageIfUnset(seedLang);
          if (!ref.mounted) return;
        }
      }
    } finally {
      _bootstrapCompleter?.complete();
    }
  }

  /// 切換作用中帳號並持久化 lastActiveUid。
  Future<void> setActiveUid(String uid) async {
    if (!state.byUid.containsKey(uid)) return;
    state = state.copyWith(activeUid: uid);
    await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
  }

  /// 清除目前的更新進度狀態。
  void clearProgress() {
    state = state.copyWith(clearProgress: true);
    if (_imageFetchPending) {
      _cloudSyncLog.info('post-sync item fetch resumed: result dialog closed');
      unawaited(fetchItemImagesForCloudSync());
    }
  }

  /// 啟動祈願資料更新，優先使用快取 URL，無快取則等待取得網址（電腦版攔截＋網頁快取，Android 讀系統記錄）。
  ///
  /// [afterPairing] 為 true 表示剛完成無線偵錯配對、且開始設定前無線偵錯沒開：這次用完一律關閉（玩家照引導打開的也算 App 開的）。
  Future<void> update({bool afterPairing = false}) async {
    await _runUpdate(forceRecapture: false, afterPairing: afterPairing);
  }

  /// 使用者手動貼上的祈願 API 網址：正在等待取得網址時直接完成這次等待，沒有進行中的更新時用它跑一次更新，正在抓資料時忽略。
  ///
  /// 完成等待走和網頁快取命中相同的路，但電腦版會立即收尾攔截，不給寬限。
  Future<void> submitManualUrl(String apiUrl) async {
    final hit = _cacheHit;
    if (hit != null && !hit.isCompleted) {
      _manualLog.info('url source=manual (completing wait)');
      _manualHit = true;
      hit.complete(apiUrl);
      return;
    }
    if (_isUpdating) {
      _manualLog.info('manual url ignored: update in progress');
      return;
    }
    _manualLog.info('url source=manual (new update)');
    await _runUpdate(forceRecapture: false, manualUrl: apiUrl);
  }

  /// 實際執行更新流程；[forceRecapture] 為 true 時強制重新 MITM 捕獲，[manualUrl] 非 null 時直接用它。
  Future<void> _runUpdate({
    required bool forceRecapture,
    String? manualUrl,
    bool afterPairing = false,
  }) async {
    if (_isUpdating) return; // 防止重入
    _isUpdating = true;
    _cancelTriggered = false;
    _afterPairing = afterPairing;
    _androidWaitRan = false;
    _wirelessLeftOn = false;
    _log.info('update start, forceRecapture=$forceRecapture');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;

    // 立刻 set Preparing → ref.listen 立刻觸發 dialog
    state = state.copyWith(progress: const Preparing());

    try {
      final initialActiveUid = state.activeUid;
      final storage = ref.read(gachaStorageProvider);
      final fetcher = ref.read(gachaFetcherProvider);

      if (forceRecapture && initialActiveUid != null) {
        await storage.deleteCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
      }

      String? capturedUrl = manualUrl;

      if (manualUrl == null && !forceRecapture && initialActiveUid != null) {
        capturedUrl = await storage.loadCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
        if (capturedUrl != null) {
          _log.info(
            'using cached url for uid=${sanitizeUid(initialActiveUid)}',
          );
        }
      }

      if (capturedUrl == null) {
        capturedUrl = await _acquireUrl(isFallback: false);
        if (!ref.mounted) return;
        if (capturedUrl == null) {
          _log.info('update aborted (user cancelled capture)');
          state = state.copyWith(clearProgress: true);
          return;
        }
      }

      try {
        await _fetchAllBanners(
          url: capturedUrl,
          fetcher: fetcher,
          storage: storage,
          client: cancellable.client,
        );
      } on AuthExpiredException {
        if (!ref.mounted) return;
        _log.warning('auth expired, falling back to recapture');
        if (initialActiveUid != null) {
          await storage.deleteCapturedUrl(initialActiveUid);
          if (!ref.mounted) return;
        }
        final newUrl = await _acquireUrl(isFallback: true);
        if (!ref.mounted) return;
        if (newUrl == null) {
          state = state.copyWith(clearProgress: true);
          return;
        }
        try {
          await _fetchAllBanners(
            url: newUrl,
            fetcher: fetcher,
            storage: storage,
            client: cancellable.client,
          );
        } on AuthExpiredException {
          if (!ref.mounted) return;
          state = state.copyWith(
            progress: const UpdateFailed(UpdateErrorAuthExpired()),
          );
        } on http.ClientException catch (e) {
          if (!ref.mounted) return;
          if (_cancelTriggered) {
            state = state.copyWith(clearProgress: true);
          } else {
            state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
          }
        } catch (e) {
          if (!ref.mounted) return;
          state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
        }
      } on http.ClientException catch (e) {
        if (!ref.mounted) return;
        if (_cancelTriggered) {
          _log.info('update cancelled (http client closed)');
          state = state.copyWith(clearProgress: true);
        } else {
          _log.warning(
            'http client error: ${e.message}'
            '${e.uri != null ? " uri=${sanitizeUrl(e.uri!.toString())}" : ""}',
          );
          state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
        }
      } catch (e, st) {
        if (!ref.mounted) return;
        _log.severe('update unexpected error', e, st);
        state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
      }
    } catch (e, st) {
      // 取得網址時的錯誤（例如 Android 讀不到配對金鑰）原本會逃出 update()、讓等待畫面卡住，在此轉成更新失敗。
      if (!ref.mounted) return;
      _log.severe('update failed while acquiring url', e, st);
      state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
    } finally {
      await _disableWirelessIfPairingUnused();
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 啟動 MITM 捕獲並同時監看遊戲網頁快取，回傳先拿到的 URL；null 代表使用者取消。
  ///
  /// [isFallback] 為 auth 過期後的二次捕獲。快取先拿到時先給攔截寬限自行結束、逾時才停掉，
  /// 並等它收尾（MITM proxy 已停、系統代理已還原）才回傳，收尾錯誤只記 warning。快取勝出前
  /// 攔截就失效（丟錯，或非使用者取消卻沒攔到）時先停掉攔截（還原系統代理），再改為只等快取並在畫面提示；找不到
  /// 遊戲資料夾時提示改成請使用者選資料夾，選好即接上監看。只有使用者取消會結束等待。
  ///
  /// 每段等待都和 [_captureBackstop] 比快：onDone 失靈（Rust 拆除未 drop sink）或
  /// `cancel()` 卡在根憑證確認視窗時，由 [cancelCapture] 完成它解開等待，確保一定有界。
  Future<String?> _runMitm({required bool isFallback}) async {
    state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
    final session = ref.read(gachaCaptureProvider).start();
    _activeCancel = session.cancel;
    _captureCancelRequested = false;
    final cacheHit = Completer<String>();
    _cacheHit = cacheHit;
    _manualHit = false;
    final backstop = Completer<String?>();
    _captureBackstop = backstop;
    _log.info('MITM ${isFallback ? "fallback" : "primary"} session started');
    final watchStart = _startWebCacheWatch();
    String? url;
    try {
      // 攔截已自行結束（出錯、沒攔到或被 backstop 解開）時為 true；此時快取勝出不需再收尾攔截。
      var captureFinished = false;
      var fromCache = false;
      try {
        (url, fromCache) = await Future.any([
          session.result.then((u) => (u, false)),
          cacheHit.future.then((u) => (u, true)),
          backstop.future.then((u) => (u, false)),
        ]);
        captureFinished = !fromCache;
      } catch (e, st) {
        // 攔截出錯（例如根憑證被拒絕、18080 埠被佔用）不判定失敗，改為只等快取。
        _webCacheLog.warning('capture failed', e, st);
        captureFinished = true;
        if (await _canWaitCacheOnly(watchStart, backstop)) {
          (url, fromCache) = await _waitCacheOnly(
            isFallback,
            session,
            cacheHit,
            backstop,
          );
        }
      }
      if (!fromCache &&
          url == null &&
          !_captureCancelRequested &&
          await _canWaitCacheOnly(watchStart, backstop)) {
        _webCacheLog.warning('capture ended without url');
        (url, fromCache) = await _waitCacheOnly(
          isFallback,
          session,
          cacheHit,
          backstop,
        );
      }
      if (fromCache && !captureFinished) {
        await _stopCaptureAfterCacheWin(
          session,
          backstop,
          skipGrace: _manualHit,
        );
      }
      if (!fromCache) _log.info('MITM session done, hasUrl=${url != null}');
      if (url != null) {
        _webCacheLog.info(
          'url source=${fromCache ? (_manualHit ? "manual" : "cache") : "capture"}',
        );
      }
    } finally {
      _cacheHit = null;
      _watchGeneration++;
      _activeCancel = null;
      _captureBackstop = null;
      await _stopWebCacheWatch();
    }
    // 收尾（攔截 teardown、停監看）可能跨越事件迴圈，期間按下的取消仍要生效。
    if (url != null && _captureCancelRequested) {
      _webCacheLog.info('user cancelled before fetch, discarding url');
      return null;
    }
    return url;
  }

  /// 依平台取得祈願 API 網址：Android 讀系統記錄，其他平台走攔截與網頁快取競速。null 代表使用者取消。
  Future<String?> _acquireUrl({required bool isFallback}) async {
    if (!ref.read(isAndroidProvider)) return _runMitm(isFallback: isFallback);
    final url = await _runAndroidWait(isFallback: isFallback);
    // 收尾（停監看、release）可能跨越事件迴圈，期間按下的取消仍要生效（同 _runMitm）。
    if (url != null && _captureCancelRequested) {
      _androidLog.info('user cancelled before fetch, discarding url');
      return null;
    }
    return url;
  }

  /// Android 沒有自動讀取方式而等待時重新判斷（玩家打開了無線偵錯、授權了權限、切回 App 時呼叫）；其他時候為 no-op。
  Future<void> retryLogAccess() async {
    final retry = _logAccessRetry;
    if (retry == null || retry.isCompleted) return;
    _androidLog.info('log access retry requested');
    retry.complete();
  }

  /// Android 的等待流程：決定讀取方式、監看系統記錄，等命中、手動輸入或取消。null 代表使用者取消。
  ///
  /// 沒有自動讀取方式時改顯示原因並只等手動輸入，[retryLogAccess] 可以重新判斷。手動輸入走 [_cacheHit]，
  /// 取消走 [_captureBackstop]，與電腦版相同。結束時一律先停監看再 release（中斷連線、依規則關閉無線偵錯）；
  /// 沒拿到網址（取消）時這段收尾改在背景做、接到 [_androidTeardown]，取消才不會卡在重連中的輪詢。
  Future<String?> _runAndroidWait({required bool isFallback}) async {
    _androidWaitRan = true;
    _manualHit = false;
    state = state.copyWith(
      progress: WaitingForCapture(
        isFallback: isFallback,
        checkingLogAccess: true,
      ),
    );
    final hit = Completer<String>();
    _cacheHit = hit;
    final cancelled = Completer<String?>();
    _captureBackstop = cancelled;
    _captureCancelRequested = false;
    // 判斷途中玩家取消或手動送出就不等了（root 授權視窗最多等 60 秒）。
    final stop = Future.any<String?>([hit.future, cancelled.future]);
    LogAccessReady? ready;
    Future<CaptureSession>? starting;
    var gotUrl = false;
    // 最後一次判斷沒有讀取方式、又沒權限關掉無線偵錯；之後拿到讀取方式就交給 release 決定。
    var blockedLeftOn = false;
    StreamSubscription<bool>? healthSub;
    try {
      final previous = _androidTeardown;
      if (previous != null) {
        _androidLog.info('waiting for the previous android teardown');
        await Future.any<Object?>([previous, stop]);
        if (_captureCancelRequested || !ref.mounted) return null;
        if (hit.isCompleted) return await hit.future;
      }
      var forceDisableAfterUse = _afterPairing;
      while (true) {
        final resolving = ref
            .read(logAccessResolverProvider)
            .resolve(
              preferred: ref.read(settingsProvider).logAccessMethod,
              forceDisableAfterUse: forceDisableAfterUse,
              abort: stop,
            );
        final first = await Future.any<Object?>([resolving, stop]);
        if (first is! LogAccessOutcome) {
          _androidLog.info('log access resolve abandoned');
          // 晚到的結果也要 release，否則連線或打開的無線偵錯會留著。
          _queueAndroidTeardown(
            resolving.then((late) async {
              if (late is LogAccessReady) await late.release();
            }),
            'late log access release',
          );
          if (first is String && !_captureCancelRequested) return first;
          return null;
        }
        final outcome = first;
        blockedLeftOn = outcome is LogAccessBlocked && outcome.wirelessLeftOn;
        if (outcome is LogAccessReady) {
          ready = outcome;
          if (_captureCancelRequested || !ref.mounted) return null;
          state = state.copyWith(
            progress: WaitingForCapture(
              isFallback: isFallback,
              gamePackage: outcome.game,
            ),
          );
          break;
        }
        if (_captureCancelRequested || !ref.mounted) return null;
        if (hit.isCompleted) return await hit.future;
        final blocked = outcome as LogAccessBlocked;
        // App 這次打開過無線偵錯，或請玩家自己打開；之後重試看到它開著，是系統（玩家按了允許）或玩家照引導開的，用完要關回去。
        if (blocked.enabledWireless ||
            blocked.reason == LogAccessUnavailable.wirelessDebuggingOff) {
          forceDisableAfterUse = true;
        }
        state = state.copyWith(
          progress: WaitingForCapture(
            isFallback: isFallback,
            logAccessUnavailable: blocked.reason,
            rootDenied: blocked.rootDenied,
          ),
        );
        final retry = Completer<void>();
        _logAccessRetry = retry;
        final next = await Future.any<Object?>([
          stop,
          retry.future.then((_) => retry),
        ]);
        _logAccessRetry = null;
        if (next is String) return next;
        if (next == null || !ref.mounted) return null;
        state = state.copyWith(
          progress: WaitingForCapture(
            isFallback: isFallback,
            checkingLogAccess: true,
          ),
        );
      }
      await ref
          .read(settingsProvider.notifier)
          .setLogAccessMethod(ready.method);
      final game = ready.game;
      healthSub = ready.healthChanges.listen((healthy) {
        final p = state.progress;
        if (p is! WaitingForCapture || p.logConnectionLost == !healthy) return;
        _androidLog.info('log connection healthy=$healthy');
        state = state.copyWith(
          progress: WaitingForCapture(
            isFallback: p.isFallback,
            logConnectionLost: !healthy,
            gamePackage: game,
          ),
        );
      });
      final start = ref.read(logcatUrlWatchProvider).start(ready.exec);
      starting = start;
      // start 要跑完第一輪（取時間、清殘留、啟動監看程序）才回傳；這段期間的取消與手動輸入要立刻生效。
      final session = await Future.any<Object?>([start, stop]);
      if (session is! CaptureSession) {
        _androidLog.info('logcat watch start abandoned');
        if (session is String && !_captureCancelRequested) return session;
        return null;
      }
      if (_captureCancelRequested || !ref.mounted) return null;
      unawaited(
        session.result.then((u) {
          if (u != null && !hit.isCompleted) hit.complete(u);
        }),
      );
      final url = await stop;
      if (url == null || _captureCancelRequested) return null;
      _androidLog.info('url source=${_manualHit ? "manual" : "logcat"}');
      final foreground = ref.read(appForegroundProvider);
      if (!foreground.isForeground) {
        _androidLog.info('url ready, waiting for the app to return');
        state = state.copyWith(
          progress: WaitingForCapture(
            isFallback: isFallback,
            credentialReady: true,
            gamePackage: game,
          ),
        );
        final resumed = await Future.any([
          foreground.untilForeground().then((_) => true),
          cancelled.future.then((_) => false),
        ]);
        if (!resumed || _captureCancelRequested || !ref.mounted) return null;
      }
      gotUrl = true;
      return url;
    } finally {
      _cacheHit = null;
      _captureBackstop = null;
      _logAccessRetry = null;
      await healthSub?.cancel();
      if (blockedLeftOn) _wirelessLeftOn = true;
      final r = ready;
      if (r != null) {
        final teardown = _stopWatchThenRelease(starting, r);
        if (gotUrl) {
          if (await teardown) _wirelessLeftOn = true;
        } else {
          // 監看可能還在跑第一輪或卡在重連中的輪詢：不讓取消卡在這裡，照樣先停監看再 release。
          _queueAndroidTeardown(
            teardown.then((leftOn) {
              if (leftOn) {
                _androidLog.info(
                  'wireless debugging left on after a cancelled wait',
                );
              }
            }),
            'android teardown',
          );
        }
      }
    }
  }

  /// 等背景還在做的 Android 收尾（停監看、release）做完；沒有時立刻返回。
  ///
  /// 設定頁的設定與解除配對要先等它，否則晚到的 release 可能關掉剛為了配對打開的無線偵錯。
  Future<void> waitAndroidTeardown() async => _androidTeardown;

  /// 把背景收尾接到 [_androidTeardown] 後面（不取代還沒做完的前一段）；錯誤只記 warning，不讓下一次更新失敗。
  void _queueAndroidTeardown(Future<void> teardown, String what) {
    final chained = Future.wait<void>([
      ?_androidTeardown,
      teardown.catchError(
        (Object e, StackTrace st) => _androidLog.warning('$what failed', e, st),
      ),
    ]);
    _androidTeardown = chained;
    unawaited(
      chained.then((_) {
        if (identical(_androidTeardown, chained)) _androidTeardown = null;
      }),
    );
  }

  /// 剛配對完、這次卻沒跑 Android 等待（快取或手動網址直接可用）時，關掉為了配對打開的無線偵錯；沒有權限關時讓完成畫面提示。
  ///
  /// 只做一次；有跑等待時改由無線偵錯的 release 依 [_afterPairing] 關閉，這裡不重複（等待改用 root 或手動輸入結束時不會關）。
  Future<void> _disableWirelessIfPairingUnused() async {
    if (!_afterPairing || _androidWaitRan || !ref.mounted) return;
    _afterPairing = false;
    final off = await ref
        .read(logAccessPlatformProvider)
        .setAdbWifiEnabled(false);
    _androidLog.info(
      'wireless debugging off after pairing without a wait ok=$off',
    );
    if (!off) _wirelessLeftOn = true;
  }

  /// 停掉 [starting] 的監看（還在啟動時等它回來）再 release [ready]；回傳無線偵錯是否因沒有權限關而留著開。
  ///
  /// 進行中的輪詢停下前就 release，讀取失敗會觸發重連、把剛關掉的無線偵錯又打開。
  Future<bool> _stopWatchThenRelease(
    Future<CaptureSession>? starting,
    LogAccessReady ready,
  ) async {
    try {
      await (await starting)?.cancel();
    } catch (e, st) {
      _androidLog.warning('logcat watch stop failed', e, st);
    }
    final leftOn = await ready.release();
    // 連上時可能順便補回授權，設定頁的配對狀態要重讀。
    if (ref.mounted) ref.invalidate(wirelessPairingStatusProvider);
    return leftOn;
  }

  /// 快取勝出後收尾攔截：先給 [_cacheWinCaptureGrace] 寬限讓它自行結束，逾時才 `cancel()`；一律等 `result` 完成才返回。
  ///
  /// 快取通常只比 MITM 晚幾十毫秒看到網址，此時遊戲的祈願 API 請求可能還在經代理轉送，
  /// 立刻 `cancel()` 會切斷它，遊戲紀錄頁顯示無法取得數據；Rust 端收到上游回應後會自行停止。
  /// 每段等待都和 [backstop] 比快（使用者取消立即生效）；收尾錯誤只記 warning。
  ///
  /// [skipGrace] 為 true（手動輸入網址）時沒有遊戲請求要等，直接 `cancel()`。
  Future<void> _stopCaptureAfterCacheWin(
    CaptureSession session,
    Completer<String?> backstop, {
    bool skipGrace = false,
  }) async {
    if (skipGrace) {
      _webCacheLog.info('manual url, cancelling capture without grace');
    } else {
      _webCacheLog.info(
        'cache won, waiting up to ${_cacheWinCaptureGrace.inMilliseconds}ms '
        'for capture to stop',
      );
      try {
        await Future.any([
          session.result,
          backstop.future,
        ]).timeout(_cacheWinCaptureGrace);
        if (!backstop.isCompleted) {
          _webCacheLog.info('capture stopped within grace after cache win');
        }
        return;
      } on TimeoutException {
        _webCacheLog.info('capture still running after grace, cancelling');
      } catch (e, st) {
        _webCacheLog.warning('capture teardown error after cache win', e, st);
        return;
      }
    }
    // cancel() 丟錯也要等 result：它完成才代表系統代理已還原，之後拉取才不會誤走代理。
    for (final step in <Future<Object?> Function()>[
      session.cancel,
      () => session.result,
    ]) {
      try {
        await Future.any([step(), backstop.future]);
      } catch (e, st) {
        _webCacheLog.warning('capture teardown error after cache win', e, st);
      }
    }
  }

  /// 等 [watchStart]（監看啟動流程）跑完後，判斷攔截失效時能否改為只等快取。
  ///
  /// 沒有監看 session（找不到遊戲資料夾）也照樣等：畫面會提示使用者選資料夾，選好就能接上。
  Future<bool> _canWaitCacheOnly(
    Future<void> watchStart,
    Completer<String?> backstop,
  ) async {
    await Future.any([watchStart, backstop.future]);
    return ref.mounted && !_captureCancelRequested;
  }

  /// 攔截失效後只等快取：先停掉攔截 session，再把等待畫面切到提示狀態，回傳快取命中的 URL，使用者取消時為 null。
  Future<(String?, bool)> _waitCacheOnly(
    bool isFallback,
    CaptureSession session,
    Completer<String> cacheHit,
    Completer<String?> backstop,
  ) async {
    // MITM 在背景 task 才 bind 埠，bind 失敗時系統代理已設好；只有 cancel()（Rust stop_capture）會還原它。
    try {
      await Future.any([
        session.cancel(),
        backstop.future,
      ]).timeout(_cancelTeardownTimeout);
    } catch (e, st) {
      _webCacheLog.warning('failed capture stop', e, st);
      if (e is TimeoutException) unawaited(_bestEffortStaleProxyCleanup());
    }
    _webCacheLog.info(
      'waiting on web cache only, gameDirMissing=${_webCacheSession == null}',
    );
    state = state.copyWith(
      progress: WaitingForCapture(
        isFallback: isFallback,
        captureUnavailable: true,
        gameDirMissing: _webCacheSession == null,
      ),
    );
    // 攔截已結束，取消只需由 cancelCapture 完成 backstop 結束這段等待。
    _activeCancel = null;
    final url = await Future.any<String?>([cacheHit.future, backstop.future]);
    return (url, true);
  }

  /// 定位遊戲資料夾並啟動網頁快取監看，命中時完成目前等待中的 [_cacheHit]。
  ///
  /// 只有最新一次呼叫的定位結果會生效；找不到資料夾時不監看。任何失敗只記 log，不影響更新。
  Future<void> _startWebCacheWatch() async {
    final hit = _cacheHit;
    if (hit == null) return;
    final generation = ++_watchGeneration;
    try {
      final location = await ref
          .read(gameDirLocatorProvider)
          .locate(settingDir: ref.read(settingsProvider).gameDir);
      if (!ref.mounted || generation != _watchGeneration || hit.isCompleted) {
        return;
      }
      if (location == null) {
        _webCacheLog.warning('web cache watch disabled: game dir not found');
        _syncCacheOnlyNotice();
        return;
      }
      final watch = ref.read(gachaUrlWatchProvider).start(location.path);
      _webCacheSession = watch;
      unawaited(
        watch.result.then((u) {
          if (u != null && !hit.isCompleted) hit.complete(u);
        }),
      );
      _syncCacheOnlyNotice();
    } catch (e, st) {
      // FileSystemException 的字串會帶原始路徑，只記型別。
      _webCacheLog.warning('web cache watch start failed', e, st);
    }
  }

  /// 只靠快取等待時，依目前有沒有監看 session 切換「找不到遊戲資料夾」提示。
  void _syncCacheOnlyNotice() {
    final p = state.progress;
    if (p is! WaitingForCapture || !p.captureUnavailable) return;
    final missing = _webCacheSession == null;
    if (p.gameDirMissing == missing) return;
    state = state.copyWith(
      progress: WaitingForCapture(
        isFallback: p.isFallback,
        captureUnavailable: true,
        gameDirMissing: missing,
      ),
    );
  }

  /// 停掉目前的網頁快取監看 session（若有）；失敗只記 log。
  Future<void> _stopWebCacheWatch() async {
    final watch = _webCacheSession;
    _webCacheSession = null;
    try {
      await watch?.cancel();
    } catch (e, st) {
      _webCacheLog.warning('web cache watch stop failed', e, st);
    }
  }

  /// 等待攔截期間停掉目前的網頁快取監看，重新定位後再啟動（baseline 從此刻重算）；其他時候為 no-op。
  Future<void> restartWebCacheWatch() async {
    if (state.progress is! WaitingForCapture) return;
    _webCacheLog.info('web cache watch restart requested');
    unawaited(_stopWebCacheWatch());
    await _startWebCacheWatch();
  }

  /// 依序拉取所有 banner 的新紀錄並合併存檔。
  Future<void> _fetchAllBanners({
    required String url,
    required GachaFetcher fetcher,
    required GachaStorage storage,
    required http.Client client,
  }) async {
    final gachaUrl = GachaUrl.parse(url);

    // 捕獲／快取取得 URL 後 probe 要數秒，期間不能還顯示「等待攔截」
    state = state.copyWith(progress: const Preparing());
    final probe = await fetcher.probeUid(url: gachaUrl, client: client);
    if (!ref.mounted) return;
    if (probe.uid == null) {
      throw const _NoRecordsException();
    }
    final uid = probe.uid!;

    final existing =
        state.byUid[uid] ??
        BannerStorage(
          uid: uid,
          lastUpdated: DateTime.utc(1970),
          banners: {for (final t in gachaTypes) t.gachaType: <GachaRecord>[]},
        );

    final mergedBanners = <String, List<GachaRecord>>{};
    final failed = <String>[];
    var totalNew = 0;

    for (final t in gachaTypes) {
      final endpoint = switch (t.category) {
        GachaCategory.gacha => GachaEndpoint.gacha,
        GachaCategory.odes => GachaEndpoint.odes,
      };
      try {
        final merged = await fetcher.fetchBannerWithMerge(
          url: gachaUrl,
          gachaType: t.gachaType,
          endpoint: endpoint,
          existing: existing.banners[t.gachaType] ?? const [],
          primer: probe.primerPages[t.gachaType],
          client: client,
          onProgress: (p) {
            if (!ref.mounted) return;
            state = state.copyWith(
              progress: FetchingBanner(
                gachaType: t.gachaType,
                displayName: t.nameKey,
                pageIndex: p.pageIndex,
                newRecordsSoFar: p.newRecordsSoFar,
              ),
            );
          },
        );
        if (!ref.mounted) return;
        final newCount =
            merged.length - (existing.banners[t.gachaType]?.length ?? 0);
        totalNew += newCount;
        mergedBanners[t.gachaType] = merged;
      } on AuthExpiredException {
        rethrow;
      } on http.ClientException {
        rethrow;
      } catch (e, st) {
        _log.warning('banner=${t.nameKey} failed', e, st);
        mergedBanners[t.gachaType] = existing.banners[t.gachaType] ?? const [];
        failed.add(t.nameKey);
      }
    }

    final updatedAt = DateTime.now().toUtc();
    final builtData = BannerStorage(
      uid: uid,
      lastUpdated: updatedAt,
      banners: mergedBanners,
    );
    final newData = await _convertAccountToDataLanguage(builtData);
    if (!ref.mounted) return;
    await storage.save(newData);
    if (!ref.mounted) return;
    await storage.saveCapturedUrl(uid, url);
    if (!ref.mounted) return;

    final newByUid = Map<String, BannerStorage>.from(state.byUid)
      ..[uid] = newData;
    _log.info(
      'update completed: uid=${sanitizeUid(uid)} '
      'totalNew=$totalNew failed=[${failed.join(",")}]',
    );
    state = state.copyWith(byUid: newByUid, activeUid: uid);
    if (!ref.mounted) return;
    await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
    if (!ref.mounted) return;
    final seedLang = _seedLangFromData(newData);
    if (seedLang != null) {
      await ref
          .read(settingsProvider.notifier)
          .seedDataLanguageIfUnset(seedLang);
      if (!ref.mounted) return;
    }
    // HoYoWiki 補圖階段（best-effort，不影響 UpdateCompleted）
    var hoYoWikiImagesDownloaded = 0;
    try {
      final result = await _fetchHoYoWiki(client);
      hoYoWikiImagesDownloaded = result.imagesDownloaded;
    } catch (e, st) {
      _log.warning('hoyowiki stage threw (ignored)', e, st);
    }
    if (!ref.mounted) return;
    if (_cancelTriggered) {
      // 使用者在 HoYoWiki 階段取消；清掉 progress 不要 emit UpdateCompleted
      state = state.copyWith(clearProgress: true);
      return;
    }
    await _disableWirelessIfPairingUnused();
    if (!ref.mounted) return;
    state = state.copyWith(
      progress: UpdateCompleted(
        totalNewRecords: totalNew,
        failedBanners: failed,
        updatedAt: updatedAt,
        hoYoWikiImagesDownloaded: hoYoWikiImagesDownloaded,
        wirelessDebuggingLeftOn: _wirelessLeftOn,
      ),
    );
  }

  /// 本次更新是否剛完成配對、且設定前無線偵錯沒開（用完一律關閉無線偵錯）。
  bool _afterPairing = false;

  /// 本次更新讀完後無線偵錯是否因沒有權限而留著開（完成畫面要提示）。
  bool _wirelessLeftOn = false;

  /// 本次更新是否跑過 Android 等待（[_afterPairing] 已交給它處理）。
  bool _androidWaitRan = false;

  /// 沒拿到網址的 Android 等待還在背景做的收尾（停監看、release）；下一次等待開始前先等它做完。
  ///
  /// root shell 與無線偵錯是共用的：下一次等待若搶先開始，晚到的 release 會關掉它剛拿到的 `su` 或剛打開的無線偵錯。
  Future<void>? _androidTeardown;

  /// Android 沒有自動讀取方式而等待時，[retryLogAccess] 會完成它以重新判斷。
  Completer<void>? _logAccessRetry;

  /// 防 re-entrancy 旗標，update 進行中為 true。
  bool _isUpdating = false;

  /// 雲端同步合併時結果視窗還開著而延後的補圖；視窗關閉（[clearProgress]）時補跑一次。
  bool _imageFetchPending = false;

  /// 使用者觸發取消時設為 true，避免將 ClientException 誤判為錯誤。
  bool _cancelTriggered = false;

  /// 目前 MITM 會話的取消函式。
  Future<void> Function()? _activeCancel;

  /// 本次等待期間由其他來源先拿到的網址（網頁快取、手動輸入；Android 為系統記錄）；不在等待時為 null。
  Completer<String>? _cacheHit;

  /// 本次等待是否由 [submitManualUrl] 完成；為 true 時收尾攔截不給寬限。
  bool _manualHit = false;

  /// 目前的網頁快取監看 session。
  CaptureSession? _webCacheSession;

  /// 本次等待期間使用者按過取消（含快取勝出後的攔截收尾、停監看期間）。
  bool _captureCancelRequested = false;

  /// 網頁快取監看的啟動世代；只有最新世代的定位結果會啟動 session。
  int _watchGeneration = 0;

  /// 目前 HTTP 請求的可取消 client，取消後關閉所有連線。
  CancellableHttpClient? _activeCancellable;

  /// 取消／逾時時用來強制解開 [_runMitm] 各段等待（含只等快取、快取勝出後收尾）與 [_runAndroidWait] 的 backstop completer。
  Completer<String?>? _captureBackstop;

  /// `cancelCapture` 等待 Rust MITM 拆除回應的上限（比 L1 的 2 秒寬鬆）。
  Duration _cancelTeardownTimeout = const Duration(seconds: 8);

  /// 快取勝出後等攔截自行結束的寬限；逾時才 `cancel()`。
  Duration _cacheWinCaptureGrace = const Duration(seconds: 3);

  /// 取消 Preparing 階段的 HTTP 請求。
  void cancelPreparing() {
    _cancelTriggered = true;
    _activeCancellable?.cancel();
  }

  /// 取消正在進行的 MITM 捕獲會話與網頁快取監看（含只等快取、快取勝出後的攔截收尾期間）。
  ///
  /// 有界：最多等 [_cancelTeardownTimeout] 讓 Rust 拆除回應；逾時則 severe-log、
  /// best-effort 還原系統 proxy，並一律完成 [_captureBackstop] 解開 [_runMitm] 的
  /// 等待（即使 onDone 未觸發），確保 dialog 一定能關閉。Android 沒有攔截，只完成 backstop，
  /// 由 [_runAndroidWait] 收尾停監看與 release。
  Future<void> cancelCapture() async {
    _cancelTriggered = true;
    _captureCancelRequested = true;
    unawaited(_stopWebCacheWatch());
    final cancel = _activeCancel;
    if (cancel != null) {
      try {
        await cancel().timeout(_cancelTeardownTimeout);
      } on TimeoutException {
        _log.severe(
          'cancelCapture: stopCapture exceeded '
          '${_cancelTeardownTimeout.inSeconds}s; forcing cleanup',
        );
        unawaited(_bestEffortStaleProxyCleanup());
      } catch (e, st) {
        _log.warning('cancelCapture: stopCapture failed', e, st);
      }
    }
    final backstop = _captureBackstop;
    if (backstop != null && !backstop.isCompleted) {
      backstop.complete(null);
    }
  }

  /// Best-effort 還原殘留的系統 proxy（取消逾時時呼叫），失敗只 warn-log，不拋。
  Future<void> _bestEffortStaleProxyCleanup() async {
    try {
      final cleared = await rust_capture.cleanupStaleProxy();
      _log.info('stale proxy cleanup after cancel timeout: cleared=$cleared');
    } catch (e, st) {
      _log.warning('stale proxy cleanup failed', e, st);
    }
  }

  /// 強制重新 MITM 捕獲並更新（忽略快取 URL）。
  Future<void> forceRecaptureAndUpdate() async {
    await _runUpdate(forceRecapture: true);
  }

  /// 強制重抓所有 UID 祈願紀錄聯集物品的 HoYoWiki 圖檔。
  ///
  /// 流程：
  ///   1. 互斥檢查：`state.progress != null` 直接 no-op（UI 應已 disable 按鈕）。
  ///   2. emit `Preparing`、建 cancellable client。
  ///   3. `hoyowikiIndexProvider.notifier.resetAll()` 清 index + 刪 cache 目錄。
  ///   4. 呼叫 [_fetchHoYoWiki] 跑既有三階段管線（它本就跨 UID 聚合 pairs）。
  ///   5. 結束依取消狀態 emit `UpdateCompleted` 或清 progress。
  ///   6. 清檔失敗時 emit `UpdateFailed(UpdateErrorWipeHoYoWikiCache)`。
  Future<void> forceRefetchAllHoYoWikiImages() async {
    if (state.progress != null) {
      _refetchLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;

    final totalUids = state.byUid.length;
    _refetchLog.info('start, totalUids=$totalUids');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      try {
        await ref.read(hoyowikiIndexProvider.notifier).resetAll();
        if (!ref.mounted) return;
        _refetchLog.info('wiped (index+cache cleared)');
      } catch (e, st) {
        _refetchLog.severe('wipeFailed', e, st);
        if (!ref.mounted) return;
        state = state.copyWith(
          progress: UpdateFailed(
            UpdateErrorWipeHoYoWikiCache(sanitizeFsPath(e.toString())),
          ),
        );
        return;
      }

      var hoYoWikiImagesDownloaded = 0;
      try {
        final result = await _fetchHoYoWiki(cancellable.client);
        hoYoWikiImagesDownloaded = result.imagesDownloaded;
      } catch (e, st) {
        _refetchLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _refetchLog.warning('cancelled');
        state = state.copyWith(clearProgress: true);
        return;
      }

      _refetchLog.info('done');
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: hoYoWikiImagesDownloaded,
        ),
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 非破壞性更新所有物品的 HoYoWiki metadata（強制重抓已解析條目的 entry 階段）。
  ///
  /// 與 [forceRefetchAllHoYoWikiImages] 不同：**不** `resetAll()`，保留既有 index
  /// 與快取圖。重抓後 [HoYoWikiIndexNotifier.mergeEntry] 覆蓋各 lang page，新增的
  /// gallery 圖只更新 index、不在此下載（維持 lazy，由詳情頁開啟時補）；icon 僅在
  /// 本地缺檔時才下載。
  ///
  /// 流程：互斥檢查 → emit `Preparing` → `_fetchHoYoWiki(forceEntryRefetch: true)`
  /// → 依取消狀態 emit `UpdateCompleted` 或 `clearProgress`。
  Future<void> refreshAllHoYoWikiMetadata() async {
    if (state.progress != null) {
      _refreshMetaLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;
    _refreshMetaLog.info('start, totalUids=${state.byUid.length}');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      var result = (
        imagesDownloaded: 0,
        itemsRefreshed: 0,
        staleLangItemsPruned: 0,
      );
      try {
        result = await _fetchHoYoWiki(
          cancellable.client,
          forceEntryRefetch: true,
          pruneStaleLangs: true,
        );
      } catch (e, st) {
        _refreshMetaLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _refreshMetaLog.warning('cancelled');
        state = state.copyWith(clearProgress: true);
        return;
      }

      _refreshMetaLog.info(
        'done, images=${result.imagesDownloaded} items=${result.itemsRefreshed} '
        'stalePruned=${result.staleLangItemsPruned}',
      );
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: result.imagesDownloaded,
          hoyoWikiEntriesRefreshed: result.itemsRefreshed,
          hoyoWikiStaleItemsPruned: result.staleLangItemsPruned,
        ),
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 匯入帳號 bundle，並接續以增量方式抓取 HoYoWiki 圖片。
  ///
  /// 流程：
  ///   1. 互斥檢查：`state.progress != null` 直接 no-op。
  ///   2. emit `Preparing`、建 cancellable client。
  ///   3. 跑 [_runImport] 寫入 storage 與更新 settings。
  ///   4. 跑 [_fetchHoYoWiki] 三階段（best-effort，例外 warn-log）。
  ///   5. 結束一律 emit `UpdateCompleted(importSummary: ...)`，不論取消與否。
  ///      取消時 import 已寫入 storage 無法回滾，仍透過 dialog 告知使用者
  ///      「資料已匯入、圖片下載被略過」。
  Future<void> importAccountsAndFetchHoYoWiki(AccountsBundle bundle) async {
    if (state.progress != null) {
      _importLog.info('skip: another progress in-flight');
      return;
    }
    if (_isUpdating) return;
    _isUpdating = true;
    _cancelTriggered = false;
    _importLog.info('start, accounts=${bundle.accounts.length}');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    state = state.copyWith(progress: const Preparing());

    try {
      final result = await _runImport(bundle);
      if (!ref.mounted) return;
      _importLog.info(
        'import done: success=${result.successAccounts} '
        'failed=[${result.failedUids.map(sanitizeUid).join(",")}] '
        'added=${result.addedRecords} duplicate=${result.duplicateRecords}',
      );

      var images = 0;
      try {
        final fetchResult = await _fetchHoYoWiki(cancellable.client);
        images = fetchResult.imagesDownloaded;
      } catch (e, st) {
        _importLog.warning('hoyowiki stage threw (ignored)', e, st);
      }
      if (!ref.mounted) return;

      if (_cancelTriggered) {
        _importLog.info('cancelled during hoyowiki, still emitting completed');
      }
      state = state.copyWith(
        progress: UpdateCompleted(
          totalNewRecords: 0,
          failedBanners: const [],
          updatedAt: DateTime.now().toUtc(),
          hoYoWikiImagesDownloaded: images,
          importSummary: result,
        ),
      );
      _importLog.info('done, images=$images');
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 雲端同步專用的靜默匯入：純資料合併（寫入 storage＋整併偏好），
  /// 不啟動 progress UI、不抓物品圖片。
  ///
  /// 已有更新或匯入進行中時拋 [CloudSyncBusyException]，由雲端同步層重排。
  /// 進度停在 [UpdateCompleted]／[UpdateFailed] 只是結果視窗還沒關，不算忙碌：
  /// 否則視窗開著期間同步會每輪重下載雲端檔再被擋下。
  Future<ImportResult> importBundleForCloudSync(AccountsBundle bundle) async {
    final progress = state.progress;
    final inFlight =
        progress != null &&
        progress is! UpdateCompleted &&
        progress is! UpdateFailed;
    if (inFlight || _isUpdating) {
      _cloudSyncLog.info('cloud import rejected: busy');
      throw const CloudSyncBusyException();
    }
    _isUpdating = true;
    try {
      _cloudSyncLog.info(
        'cloud import start, accounts=${bundle.accounts.length}',
      );
      return await _runImport(bundle);
    } finally {
      _isUpdating = false;
      if (_imageFetchPending && state.progress == null) {
        unawaited(fetchItemImagesForCloudSync());
      }
    }
  }

  /// 雲端同步合併出新記錄後的補抓：補抓缺漏的物品圖示與詳情，走與
  /// 「更新物品資料」相同的 progress 呈現，結束顯示物品資料／補圖張數
  /// 摘要（不帶 importSummary，避免顯示成手動匯入的結果文案）。
  ///
  /// 刻意**不**先 emit `Preparing`：合併進來的物品若本機圖示／詳情皆已
  /// 齊全，整段沒有工作可做，不該彈任何視窗——有工作時 [_fetchHoYoWiki]
  /// 會自行 emit 進度（對話框屆時才彈出）；結束時三個計數全零就靜默清掉
  /// progress，不顯示「更新完成」。
  ///
  /// best-effort：補抓失敗僅記 log，仍照常收尾；更新／匯入進行中或
  /// bootstrap 未完成時直接略過，缺圖留待下次「更新」自然補齊。
  Future<void> fetchItemImagesForCloudSync() async {
    final progress = state.progress;
    if (progress != null) {
      // 只是結果視窗還開著（合併可在此時進行）：等視窗關閉（[clearProgress]）再補。
      if ((progress is UpdateCompleted || progress is UpdateFailed) &&
          !_isUpdating &&
          !state.isBootstrapping) {
        _imageFetchPending = true;
        _cloudSyncLog.info(
          'post-sync item fetch deferred: result dialog still open',
        );
        return;
      }
      _cloudSyncLog.info(
        'post-sync item fetch skipped: progress=${progress.runtimeType} '
        'updating=$_isUpdating bootstrapping=${state.isBootstrapping}',
      );
      return;
    }
    if (_isUpdating || state.isBootstrapping) {
      _cloudSyncLog.info('post-sync item fetch skipped: busy or bootstrapping');
      return;
    }
    _imageFetchPending = false;
    _isUpdating = true;
    _cancelTriggered = false;
    _cloudSyncLog.info('post-sync item fetch start');

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;
    var result = (
      imagesDownloaded: 0,
      itemsRefreshed: 0,
      staleLangItemsPruned: 0,
    );
    try {
      try {
        result = await _fetchHoYoWiki(cancellable.client);
      } catch (e, st) {
        _cloudSyncLog.warning(
          'post-sync hoyowiki stage threw (ignored)',
          e,
          st,
        );
      }
      if (!ref.mounted) return;

      final didWork =
          result.imagesDownloaded > 0 ||
          result.itemsRefreshed > 0 ||
          result.staleLangItemsPruned > 0;
      if (didWork) {
        state = state.copyWith(
          progress: UpdateCompleted(
            totalNewRecords: 0,
            failedBanners: const [],
            updatedAt: DateTime.now().toUtc(),
            hoYoWikiImagesDownloaded: result.imagesDownloaded,
            hoyoWikiEntriesRefreshed: result.itemsRefreshed,
            hoyoWikiStaleItemsPruned: result.staleLangItemsPruned,
          ),
        );
      } else {
        // 沒有實際成果：清掉過程中可能已 emit 的進度，讓對話框自動關閉。
        state = state.copyWith(clearProgress: true);
      }
      _cloudSyncLog.info(
        'post-sync item fetch done, items=${result.itemsRefreshed} '
        'images=${result.imagesDownloaded} '
        'dialog=${didWork ? 'shown' : 'suppressed'}',
      );
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 刪除目前作用中帳號的所有資料。
  Future<void> clearActive() async {
    final uid = state.activeUid;
    if (uid == null) return;
    await removeUid(uid);
  }

  /// 刪除所有帳號資料並重置設定。
  Future<void> clearAll() async {
    final storage = ref.read(gachaStorageProvider);
    await storage.clearAll();
    if (!ref.mounted) return;
    await ref.read(settingsProvider.notifier).clearAllUidPreferences();
    if (!ref.mounted) return;
    state = const GachaState(isBootstrapping: false);
    _log.info('cleared all gacha data');
  }

  /// 批次匯入 [AccountsBundle]，合併現有帳號資料與偏好設定。
  ///
  /// 純資料層操作，**不**啟動 progress 或 HoYoWiki 圖片抓取。
  /// 對外入口請用 [importAccountsAndFetchHoYoWiki]。
  Future<ImportResult> _runImport(AccountsBundle bundle) async {
    final storage = ref.read(gachaStorageProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final newByUid = Map<String, BannerStorage>.from(state.byUid);
    final failed = <String>[];
    var addedRecords = 0;
    var duplicateRecords = 0;
    var successCount = 0;

    for (final account in bundle.accounts) {
      final incoming = account.data;
      try {
        final localBefore = newByUid[incoming.uid];
        final merged = localBefore == null
            ? incoming
            : localBefore.mergeWith(incoming);
        var toSave = await _convertAccountToDataLanguage(merged);
        // 合併後與本機完全相同（例如雲端同步重抓到同一份）就沿用原物件、不重寫檔案：
        // 寫檔的 JSON 編碼在主 isolate 實機量到數十毫秒。
        if (localBefore != null && toSave.sameContentAs(localBefore)) {
          toSave = localBefore;
        } else {
          await storage.save(toSave);
        }
        if (!ref.mounted) {
          return ImportResult(
            successAccounts: successCount,
            addedRecords: addedRecords,
            duplicateRecords: duplicateRecords,
            failedUids: failed,
          );
        }
        final added =
            toSave.allRecords.length - (localBefore?.allRecords.length ?? 0);
        addedRecords += added;
        duplicateRecords += incoming.allRecords.length - added;
        newByUid[incoming.uid] = toSave;
        successCount++;
      } catch (_) {
        failed.add(incoming.uid);
      }
    }

    final currentSettings = ref.read(settingsProvider);
    final mergedAliases = Map<String, String>.from(currentSettings.uidAliases);
    for (final account in bundle.accounts) {
      final uid = account.data.uid;
      if (failed.contains(uid)) continue;
      if (mergedAliases.containsKey(uid)) continue; // 本機已有別名 → 保留
      final a = account.alias?.trim();
      if (a != null && a.isNotEmpty) {
        mergedAliases[uid] = a;
      }
    }

    final localOrder = currentSettings.uidOrder;
    final localSet = localOrder.toSet();
    final appended = bundle.accounts
        .where((a) => !failed.contains(a.data.uid))
        .map((a) => a.data.uid)
        .where((uid) => !localSet.contains(uid))
        .toList(growable: false);
    final newOrder = [...localOrder, ...appended];

    final localActive = state.activeUid;
    final desiredActive = bundle.lastActiveUid;
    final newActive = (localActive != null && newByUid.containsKey(localActive))
        ? localActive
        : (desiredActive != null && newByUid.containsKey(desiredActive))
        ? desiredActive
        : (newByUid.isEmpty
              ? null
              : (newOrder.isEmpty ? newByUid.keys.first : newOrder.first));

    await settingsNotifier.applyImportedPreferences(
      aliases: mergedAliases,
      uidOrder: newOrder,
      lastActiveUid: newActive,
    );
    if (!ref.mounted) {
      return ImportResult(
        successAccounts: successCount,
        addedRecords: addedRecords,
        duplicateRecords: duplicateRecords,
        failedUids: failed,
      );
    }

    // 沒有任何帳號換物件就保留原 Map：頁面與「本機資料變動」監聽都不必重跑。
    final byUidChanged =
        newByUid.length != state.byUid.length ||
        newByUid.entries.any((e) => !identical(state.byUid[e.key], e.value));
    state = state.copyWith(
      byUid: byUidChanged ? newByUid : null,
      activeUid: newActive,
      clearActiveUid: newActive == null,
    );

    BannerStorage? newest;
    for (final account in bundle.accounts) {
      final d = newByUid[account.data.uid];
      if (d == null) continue;
      if (newest == null || d.lastUpdated.isAfter(newest.lastUpdated)) {
        newest = d;
      }
    }
    if (newest != null) {
      final seedLang = _seedLangFromData(newest);
      if (seedLang != null) {
        await settingsNotifier.seedDataLanguageIfUnset(seedLang);
        if (!ref.mounted) {
          return ImportResult(
            successAccounts: successCount,
            addedRecords: addedRecords,
            duplicateRecords: duplicateRecords,
            failedUids: failed,
          );
        }
      }
    }

    _log.info(
      'import: success=$successCount '
      'failed=[${failed.map(sanitizeUid).join(",")}] '
      'added=$addedRecords duplicate=$duplicateRecords',
    );
    return ImportResult(
      successAccounts: successCount,
      addedRecords: addedRecords,
      duplicateRecords: duplicateRecords,
      failedUids: failed,
    );
  }

  /// 測試用：直接塞一筆帳號到 state.byUid（不走 bootstrap/storage）。生產勿用。
  @visibleForTesting
  void debugSeedAccount(BannerStorage data) {
    final next = Map<String, BannerStorage>.from(state.byUid)
      ..[data.uid] = data;
    state = state.copyWith(byUid: next, activeUid: data.uid);
  }

  /// 測試用：暴露 [_runImport] 給單元測試（驗證純 import 邏輯，
  /// 不必 mock HoYoWiki fetcher）。生產勿用。
  @visibleForTesting
  Future<ImportResult> debugImportOnly(AccountsBundle bundle) =>
      _runImport(bundle);

  /// 把所有帳號的卡池資料統一成目前設定的資料語言；回傳聚合計數。
  /// 立即彈出進度（[Preparing]），結尾主動清進度。未設定資料語言時回零結果。
  Future<LangConvertResult> unifyDataLanguage() async {
    final targetLang = ref.read(dataLanguageProvider);
    if (targetLang == null) return const LangConvertResult();
    if (_isUpdating) return const LangConvertResult();
    _isUpdating = true;
    _cancelTriggered = false;
    // 點擊當下即彈進度框（與更新／匯入流程一致）。
    state = state.copyWith(progress: const ConvertingDataLanguage());
    try {
      final storage = ref.read(gachaStorageProvider);
      final converter = ref.read(gachaLanguageConverterProvider);
      final indexNotifier = ref.read(hoyowikiIndexProvider.notifier);
      var agg = const LangConvertResult();
      final newByUid = Map<String, BannerStorage>.from(state.byUid);
      // 累積所有帳號的 hints，最後只套一次 setSearches（逐筆 setSearch 會各自
      // 整份重寫 hoyowiki_index.json，數百~數千筆 record 會嚴重拖慢）。
      final allHints = <({String name, String lang, String id, int menuId})>[];
      for (final uid in state.byUid.keys.toList()) {
        final data = state.byUid[uid]!;
        try {
          final outcome = await converter.convert(data, targetLang);
          // 沒有任何記錄需要轉換時不重寫檔案、不換物件：寫檔與整份 state 替換都會卡住畫面。
          if (!outcome.data.sameContentAs(data)) {
            await storage.save(outcome.data);
            newByUid[uid] = outcome.data;
          }
          for (final h in outcome.hints) {
            allHints.add((
              name: h.name,
              lang: h.lang,
              id: h.id,
              menuId: h.menuId,
            ));
          }
          agg = agg + outcome.result;
        } catch (e, st) {
          Logger(
            'wish.langconvert',
          ).warning('unify skip uid=${sanitizeUid(uid)}', e, st);
        }
      }
      await indexNotifier.setSearches(allHints);
      if (ref.mounted &&
          newByUid.entries.any(
            (e) => !identical(state.byUid[e.key], e.value),
          )) {
        state = state.copyWith(byUid: newByUid);
      }
      // best-effort：補抓目標語言的 icon／詳情（`pageByLang[target]`），讓轉換後
      // 角色說明與 gallery 頁籤即時可看；失敗不影響已完成的轉換。首次轉某語言會抓
      // 該語言全部 entry_page（一次性、會快取，期間由 _fetchHoYoWiki emit
      // FetchingHoYoWiki 進度）；切回已抓過的語言則 needRefetchEntry 全 false、
      // 近乎瞬間。
      final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
      try {
        await _fetchHoYoWiki(cancellable.client);
      } catch (e, st) {
        Logger(
          'wish.langconvert',
        ).warning('unify prewarm failed (ignored)', e, st);
      } finally {
        cancellable.client.close();
      }
      return agg;
    } finally {
      _isUpdating = false;
      if (ref.mounted) state = state.copyWith(clearProgress: true);
    }
  }

  /// 依 uidOrder 與最後更新時間挑選 fallback 作用中 UID。
  String? _pickFallbackActive(Map<String, BannerStorage> byUid) {
    if (byUid.isEmpty) return null;
    final order = ref.read(settingsProvider).uidOrder;
    return mergeUidOrder(
      knownUids: byUid.keys,
      customOrder: order,
      lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
    ).first;
  }

  /// 刪除指定 UID 的帳號資料並更新設定。
  Future<void> removeUid(String uid) async {
    final storage = ref.read(gachaStorageProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    await storage.delete(uid);
    if (!ref.mounted) return;
    await settingsNotifier.removeUidFromSettings(uid);
    if (!ref.mounted) return;

    final newByUid = Map<String, BannerStorage>.from(state.byUid)..remove(uid);
    if (state.activeUid == uid) {
      final next = _pickFallbackActive(newByUid);
      state = next == null
          ? state.copyWith(byUid: newByUid, clearActiveUid: true)
          : state.copyWith(byUid: newByUid, activeUid: next);
      if (!ref.mounted) return;
      await settingsNotifier.setLastActiveUid(next);
    } else {
      state = state.copyWith(byUid: newByUid);
    }
    _log.info('cleared uid=${sanitizeUid(uid)}');
  }

  /// 若已設定資料語言則轉換 [data] 並把 hints 寫回 HoYoWikiIndex；
  /// 任何例外吞掉、回原 [data]（絕不中斷更新／匯入、絕不毀資料）。
  Future<BannerStorage> _convertAccountToDataLanguage(
    BannerStorage data,
  ) async {
    final targetLang = ref.read(dataLanguageProvider);
    if (targetLang == null) return data;
    try {
      final converter = ref.read(gachaLanguageConverterProvider);
      final outcome = await converter.convert(data, targetLang);
      if (outcome.hints.isNotEmpty) {
        await ref
            .read(hoyowikiIndexProvider.notifier)
            .setSearches(
              outcome.hints.map(
                (h) => (name: h.name, lang: h.lang, id: h.id, menuId: h.menuId),
              ),
            );
      }
      return outcome.data;
    } catch (e, st) {
      Logger('wish.langconvert').warning(
        'convert account failed uid=${sanitizeUid(data.uid)} (kept original)',
        e,
        st,
      );
      return data;
    }
  }

  /// 取 [data] 中非頌願、有語言的「最新」一筆 record 的 lang（供 seeding）；無則 null。
  String? _seedLangFromData(BannerStorage data) {
    GachaRecord? latest;
    for (final e in data.banners.entries) {
      if (!convertibleGachaTypes.contains(e.key)) continue;
      for (final r in e.value) {
        if (r.lang.isEmpty) continue;
        if (latest == null || r.id.compareTo(latest.id) > 0) latest = r;
      }
    }
    return latest?.lang;
  }

  /// 補齊所有 UID 中祈願類 record 的 HoYoWiki icon / header。
  ///
  /// 流程：
  ///   1. 收集所有 UID 的祈願類 record（gachaType ∈ {301, 302, 500, 200, 100}）
  ///      取 unique (name, lang)。
  ///   2. 對 index.search 缺對應的跑 search；命中時寫 index.search 並把 id 加入
  ///      entry worklist。
  ///   3. 對 index.entries 缺或任一 URL 為空字串的 id 跑 entry_page；成功時寫
  ///      index.entries 並把非空 URL 加入 download worklist。
  ///   4. 對 cache 檔不存在的 (id, kind, url) 下載寫檔；成功後呼叫
  ///      [HoYoWikiIndexNotifier.bumpCacheRevision] 觸發 UI rebuild。
  ///
  /// 每筆獨立 try/catch：單筆失敗不終止整段。每筆完成更新 progress。整段失敗
  /// 不影響 `UpdateCompleted`。取消（`_cancelTriggered` 或 `!ref.mounted`）早退。
  ///
  /// `forceEntryRefetch` 為 true 時，entry 階段強制納入所有已解析的 (id, lang)，
  /// 用於設定頁手動更新物品資料。
  ///
  /// 回傳本次成功寫入磁碟的圖片張數（`imagesDownloaded`）、成功刷新 metadata
  /// 的相異物品數（`itemsRefreshed`），以及 `pageByLang` 被縮減的相異物品數
  /// （`staleLangItemsPruned`）。
  Future<({int imagesDownloaded, int itemsRefreshed, int staleLangItemsPruned})>
  _fetchHoYoWiki(
    http.Client client, {
    bool forceEntryRefetch = false,
    bool pruneStaleLangs = false,
  }) async {
    var downloaded = 0;
    final refreshedIds = <String>{};
    var staleLangItemsPruned = 0;
    final fetcher = ref.read(hoyowikiFetcherProvider);
    final indexNotifier = ref.read(hoyowikiIndexProvider.notifier);
    final cacheDir = ref.read(hoyowikiCacheDirProvider);
    await indexNotifier.waitForLoad();

    const hoyoWikiTargetGachaTypes = {'301', '302', '500', '200', '100'};

    // 收集所有 UID 全部卡池 record 的 unique (name, lang)
    final uniquePairs = <(String name, String lang)>{};
    for (final data in state.byUid.values) {
      for (final entry in data.banners.entries) {
        if (!hoyoWikiTargetGachaTypes.contains(entry.key)) continue;
        for (final r in entry.value) {
          if (r.name.isEmpty || r.lang.isEmpty) continue;
          uniquePairs.add((r.name, r.lang));
        }
      }
    }

    // 切三段 worklist
    var index = ref.read(hoyowikiIndexProvider);
    final searchTodo = <(String, String)>[];
    for (final pair in uniquePairs) {
      if (index.lookupId(name: pair.$1, lang: pair.$2) == null) {
        searchTodo.add(pair);
      }
    }

    /// 重抓判定：entry 或 menuId 缺失，或該 lang 還沒有 page → true。
    bool needRefetchEntry(HoYoWikiEntry? entry, int? menuId, String lang) {
      if (entry == null) return true;
      if (menuId == null) return true;
      if (!entry.pageByLang.containsKey(lang)) return true;
      return false;
    }

    // entryTodo 初始：走過所有 record lang+name，蒐集需要重抓的 (id, lang) pair
    final allLangs = uniquePairs.map((p) => p.$2).toSet();

    // 針對性清理：移除已不再被任何記錄使用的語言殘留頁面（非破壞性，僅 index 內 pageByLang）。
    // allLangs 為空（無記錄）時略過，避免誤清全部。
    if (pruneStaleLangs && allLangs.isNotEmpty) {
      staleLangItemsPruned = await indexNotifier.pruneLanguages(allLangs);
      if (!ref.mounted || _cancelTriggered) {
        return (
          imagesDownloaded: 0,
          itemsRefreshed: 0,
          staleLangItemsPruned: staleLangItemsPruned,
        );
      }
      index = ref.read(hoyowikiIndexProvider); // 重讀 prune 後的 index 快照
    }

    final namesByLang = <String, Set<String>>{};
    for (final pair in uniquePairs) {
      namesByLang.putIfAbsent(pair.$2, () => {}).add(pair.$1);
    }
    final entryTodo = <({String id, String lang})>{};
    for (final lang in allLangs) {
      for (final name in namesByLang[lang] ?? const <String>{}) {
        final id = index.lookupId(name: name, lang: lang);
        if (id == null) continue;
        if (forceEntryRefetch ||
            needRefetchEntry(
              index.lookupEntry(id),
              index.lookupMenuId(id),
              lang,
            )) {
          entryTodo.add((id: id, lang: lang));
        }
      }
    }

    // downloadTodo 初始：現有 entry 的非空 URL 中，cache 檔不存在的
    final downloadTodo = <_HoYoWikiDownloadItem>[];
    final seenUrls = <String>{}; // 跨 entry/lang 去重，避免重複 enqueue

    void enqueueDownloadsForEntry(String id, HoYoWikiEntry entry) {
      // gallery 大圖改 lazy：由 GachaItemDetailDialog 打開時下載。
      // 此處僅 enqueue icon — icon 在祈願列表常駐顯示，維持預下載。
      if (entry.iconUrl.isEmpty) return;
      final iconFile = hoyowikiIconCacheFile(
        baseDir: cacheDir,
        id: id,
        url: entry.iconUrl,
      );
      if (!iconFile.existsSync() && seenUrls.add('icon::${entry.iconUrl}')) {
        downloadTodo.add(_HoYoWikiDownloadItem(id: id, url: entry.iconUrl));
      }
    }

    final initialIds = uniquePairs
        .map((p) => index.lookupId(name: p.$1, lang: p.$2))
        .whereType<String>()
        .toSet();
    for (final id in initialIds) {
      final e = index.lookupEntry(id);
      if (e != null) enqueueDownloadsForEntry(id, e);
    }

    // 三段加起來都沒工作就直接結束。
    final totalInitial =
        searchTodo.length + entryTodo.length + downloadTodo.length;
    if (totalInitial == 0) {
      return (
        imagesDownloaded: downloaded,
        itemsRefreshed: refreshedIds.length,
        staleLangItemsPruned: staleLangItemsPruned,
      );
    }

    bool isAborted() => !ref.mounted || _cancelTriggered;

    // (1) search 階段
    if (searchTodo.isNotEmpty) {
      var doneSearch = 0;
      await runConcurrent<(String, String)>(
        items: searchTodo,
        concurrency: fetcher.searchConcurrency,
        shouldAbort: isAborted,
        worker: (pair) async {
          try {
            final hit = await fetcher.searchEntryId(
              name: pair.$1,
              lang: pair.$2,
              client: client,
            );
            if (hit != null) {
              await indexNotifier.setSearch(
                name: pair.$1,
                lang: pair.$2,
                id: hit.id,
                menuId: hit.menuId,
              );
              // 此處不需判 forceEntryRefetch：剛 search 命中的 id 其 entry 尚為 null，
              // needRefetchEntry(null, ...) 必為 true，force 與非 force 行為一致。
              if (!entryTodo.contains((id: hit.id, lang: pair.$2)) &&
                  needRefetchEntry(
                    ref.read(hoyowikiIndexProvider).lookupEntry(hit.id),
                    hit.menuId,
                    pair.$2,
                  )) {
                entryTodo.add((id: hit.id, lang: pair.$2));
              }
            }
          } catch (e, st) {
            _log.warning('hoyowiki search failed name=${pair.$1}', e, st);
          }
          if (!ref.mounted) return;
          doneSearch++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.searching,
              doneCount: doneSearch,
              totalCount: searchTodo.length,
            ),
          );
        },
      );
      if (isAborted()) {
        return (
          imagesDownloaded: downloaded,
          itemsRefreshed: refreshedIds.length,
          staleLangItemsPruned: staleLangItemsPruned,
        );
      }
    }

    // (2) entry 階段
    if (entryTodo.isNotEmpty) {
      final entryList = entryTodo.toList();
      var doneEntry = 0;
      await runConcurrent<({String id, String lang})>(
        items: entryList,
        concurrency: fetcher.entryConcurrency,
        shouldAbort: isAborted,
        worker: (pair) async {
          try {
            final fetched = await fetcher.fetchEntryPage(
              id: pair.id,
              lang: pair.lang,
              client: client,
            );
            await indexNotifier.mergeEntry(
              id: pair.id,
              lang: pair.lang,
              fetched: fetched,
            );
            refreshedIds.add(pair.id);
            // enqueueDownloadsForEntry 會處理 icon + 各 lang 的 gallery 圖（URL 去重）。
            final entry = ref.read(hoyowikiIndexProvider).lookupEntry(pair.id);
            if (entry != null) enqueueDownloadsForEntry(pair.id, entry);
          } catch (e, st) {
            _log.warning(
              'hoyowiki entry failed id=${pair.id} lang=${pair.lang}',
              e,
              st,
            );
          }
          if (!ref.mounted) return;
          doneEntry++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.fetchingEntries,
              doneCount: doneEntry,
              totalCount: entryList.length,
            ),
          );
        },
      );
      if (isAborted()) {
        return (
          imagesDownloaded: downloaded,
          itemsRefreshed: refreshedIds.length,
          staleLangItemsPruned: staleLangItemsPruned,
        );
      }
    }

    // (3) download 階段
    if (downloadTodo.isNotEmpty) {
      var doneDownload = 0;
      await runConcurrent<_HoYoWikiDownloadItem>(
        items: downloadTodo,
        concurrency: fetcher.downloadConcurrency,
        shouldAbort: isAborted,
        worker: (item) async {
          try {
            final bytes = await fetcher.downloadImage(item.url, client);
            if (bytes != null) {
              final file = hoyowikiIconCacheFile(
                baseDir: cacheDir,
                id: item.id,
                url: item.url,
              );
              await writeHoYoWikiCacheImage(file: file, bytes: bytes);
              indexNotifier.bumpCacheRevision();
              downloaded++;
            }
          } catch (e, st) {
            _log.warning(
              'hoyowiki download failed url=${sanitizeUrl(item.url)}',
              e,
              st,
            );
          }
          if (!ref.mounted) return;
          doneDownload++;
          state = state.copyWith(
            progress: FetchingHoYoWiki(
              phase: HoYoWikiPhase.downloading,
              doneCount: doneDownload,
              totalCount: downloadTodo.length,
            ),
          );
        },
      );
      if (isAborted()) {
        return (
          imagesDownloaded: downloaded,
          itemsRefreshed: refreshedIds.length,
          staleLangItemsPruned: staleLangItemsPruned,
        );
      }
    }
    // 有圖檔被重新下載＝磁碟快取曾與記憶體索引分歧（快取目錄可能在執行中
    // 被外部清掉，index 檔也一併遺失）。此時若這輪沒有任何 search／entry
    // 寫入，index 檔不會被重建，重啟後所有圖示將失效——主動重新落盤一次。
    if (downloaded > 0) {
      try {
        await indexNotifier.persistNow();
      } catch (e, st) {
        _log.warning('index re-persist failed (ignored)', e, st);
      }
    }
    return (
      imagesDownloaded: downloaded,
      itemsRefreshed: refreshedIds.length,
      staleLangItemsPruned: staleLangItemsPruned,
    );
  }

  /// 測試用：略過 banner fetch 直接跑 hoyowiki 階段（用既有 state.byUid）；`forceEntryRefetch` 透傳給 [_fetchHoYoWiki]。
  ///
  /// WHY clearProgress：_fetchHoYoWiki 跑完後 state.progress 停留在最後一個
  /// FetchingHoYoWiki phase，若不清除，後續呼叫帶互斥檢查的 public method
  ///（例如 [refreshAllHoYoWikiMetadata]）會因 progress != null 而直接跳過。
  @visibleForTesting
  Future<void> debugRunHoYoWikiOnly({bool forceEntryRefetch = false}) async {
    _cancelTriggered = false;
    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    try {
      await _fetchHoYoWiki(
        cancellable.client,
        forceEntryRefetch: forceEntryRefetch,
      );
    } finally {
      cancellable.client.close();
      if (ref.mounted) state = state.copyWith(clearProgress: true);
    }
  }

  /// 將各種 exception 轉換成對應的 [UpdateError] 子類，供 UI 顯示。
  UpdateError _friendlyError(Object e) => switch (e) {
    _NoRecordsException() => const UpdateErrorNoRecords(),
    FormatException(:final message) => UpdateErrorOther(message),
    RateLimitedException() => const UpdateErrorRateLimited(),
    ApiErrorException(:final message) => UpdateErrorServer(message),
    AuthExpiredException() => const UpdateErrorAuthExpired(),
    http.ClientException(:final message, :final uri) => UpdateErrorOther(
      uri != null ? '$message ($uri)' : message,
    ),
    _ => UpdateErrorOther(e.toString()),
  };

  /// 強制覆寫 progress 狀態，僅供測試使用。
  @visibleForTesting
  void debugSetProgress(UpdateProgress p) {
    state = state.copyWith(progress: p);
  }

  /// 測試用：縮短取消拆除逾時，避免真實掛鐘等待。生產勿用。
  @visibleForTesting
  void debugSetCancelTeardownTimeout(Duration timeout) {
    _cancelTeardownTimeout = timeout;
  }

  /// 測試用：縮短快取勝出後等攔截自行結束的寬限，避免真實掛鐘等待。生產勿用。
  @visibleForTesting
  void debugSetCacheWinCaptureGrace(Duration grace) {
    _cacheWinCaptureGrace = grace;
  }
}

/// HoYoWiki 下載佇列的單一工作項。
class _HoYoWikiDownloadItem {
  /// 建立 [_HoYoWikiDownloadItem]。
  const _HoYoWikiDownloadItem({required this.id, required this.url});

  /// HoYoWiki entry_page_id。
  final String id;

  /// 圖片 URL。
  final String url;
}
