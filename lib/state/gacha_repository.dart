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
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/concurrent_pool.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';

/// probeUid 回傳 null 時拋出，轉成 [UpdateErrorNoRecords]。
class _NoRecordsException implements Exception {
  const _NoRecordsException();
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
  }

  /// 啟動祈願資料更新，優先使用快取 URL，無快取則觸發 MITM 捕獲。
  Future<void> update() async {
    await _runUpdate(forceRecapture: false);
  }

  /// 實際執行更新流程；[forceRecapture] 為 true 時強制重新 MITM 捕獲。
  Future<void> _runUpdate({required bool forceRecapture}) async {
    if (_isUpdating) return; // 防止重入
    _isUpdating = true;
    _cancelTriggered = false;
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

      String? capturedUrl;

      if (!forceRecapture && initialActiveUid != null) {
        capturedUrl = await storage.loadCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
        if (capturedUrl != null) {
          _log.info(
            'using cached url for uid=${sanitizeUid(initialActiveUid)}',
          );
        }
      }

      if (capturedUrl == null) {
        capturedUrl = await _runMitm(isFallback: false);
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
        _log.warning('auth expired, falling back to MITM recapture');
        if (initialActiveUid != null) {
          await storage.deleteCapturedUrl(initialActiveUid);
          if (!ref.mounted) return;
        }
        final newUrl = await _runMitm(isFallback: true);
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
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
      _cancelTriggered = false;
      _isUpdating = false;
    }
  }

  /// 啟動 MITM 捕獲會話並等候 URL；[isFallback] 為 auth 過期後的二次捕獲。
  ///
  /// 等待用 `Future.any([session.result, backstop])`：正常經 onDone 由 `result`
  /// 回；若 onDone 失靈（Rust 拆除未 drop sink），則由 [cancelCapture] 完成的
  /// [_captureBackstop] 解開，確保等待一定有界、不會永久卡在 `WaitingForCapture`。
  Future<String?> _runMitm({required bool isFallback}) async {
    state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
    final session = ref.read(gachaCaptureProvider).start();
    _activeCancel = session.cancel;
    final backstop = Completer<String?>();
    _captureBackstop = backstop;
    _log.info('MITM ${isFallback ? "fallback" : "primary"} session started');
    try {
      final result = await Future.any([session.result, backstop.future]);
      _log.info('MITM session done, hasUrl=${result != null}');
      return result;
    } finally {
      _activeCancel = null;
      _captureBackstop = null;
    }
  }

  /// 依序拉取所有 banner 的新紀錄並合併存檔。
  Future<void> _fetchAllBanners({
    required String url,
    required GachaFetcher fetcher,
    required GachaStorage storage,
    required http.Client client,
  }) async {
    final gachaUrl = GachaUrl.parse(url);

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
      } catch (e) {
        _log.warning('banner=${t.nameKey} failed: $e');
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
      hoYoWikiImagesDownloaded = await _fetchHoYoWiki(client);
    } catch (e, st) {
      _log.warning('hoyowiki stage threw (ignored)', e, st);
    }
    if (!ref.mounted) return;
    if (_cancelTriggered) {
      // 使用者在 HoYoWiki 階段取消；清掉 progress 不要 emit UpdateCompleted
      state = state.copyWith(clearProgress: true);
      return;
    }
    state = state.copyWith(
      progress: UpdateCompleted(
        totalNewRecords: totalNew,
        failedBanners: failed,
        updatedAt: updatedAt,
        hoYoWikiImagesDownloaded: hoYoWikiImagesDownloaded,
      ),
    );
  }

  /// 防 re-entrancy 旗標，update 進行中為 true。
  bool _isUpdating = false;

  /// 使用者觸發取消時設為 true，避免將 ClientException 誤判為錯誤。
  bool _cancelTriggered = false;

  /// 目前 MITM 會話的取消函式。
  Future<void> Function()? _activeCancel;

  /// 目前 HTTP 請求的可取消 client，取消後關閉所有連線。
  CancellableHttpClient? _activeCancellable;

  /// 取消／逾時時用來強制解開 [_runMitm] 等待的 backstop completer。
  Completer<String?>? _captureBackstop;

  /// `cancelCapture` 等待 Rust MITM 拆除回應的上限（比 L1 的 2 秒寬鬆）。
  Duration _cancelTeardownTimeout = const Duration(seconds: 8);

  /// 取消 Preparing 階段的 HTTP 請求。
  void cancelPreparing() {
    _cancelTriggered = true;
    _activeCancellable?.cancel();
  }

  /// 取消正在進行的 MITM 捕獲會話。
  ///
  /// 有界：最多等 [_cancelTeardownTimeout] 讓 Rust 拆除回應；逾時則 severe-log、
  /// best-effort 還原系統 proxy，並一律完成 [_captureBackstop] 解開 [_runMitm] 的
  /// 等待（即使 onDone 未觸發），確保 dialog 一定能關閉。
  Future<void> cancelCapture() async {
    _cancelTriggered = true;
    final cancel = _activeCancel;
    if (cancel == null) return;
    try {
      await cancel().timeout(_cancelTeardownTimeout);
    } on TimeoutException {
      _log.severe(
        'cancelCapture: stopCapture exceeded '
        '${_cancelTeardownTimeout.inSeconds}s; forcing cleanup',
      );
      unawaited(_bestEffortStaleProxyCleanup());
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
        hoYoWikiImagesDownloaded = await _fetchHoYoWiki(cancellable.client);
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
        images = await _fetchHoYoWiki(cancellable.client);
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
        final toSave = await _convertAccountToDataLanguage(merged);
        await storage.save(toSave);
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

    state = state.copyWith(
      byUid: newByUid,
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
          await storage.save(outcome.data);
          for (final h in outcome.hints) {
            allHints.add((
              name: h.name,
              lang: h.lang,
              id: h.id,
              menuId: h.menuId,
            ));
          }
          newByUid[uid] = outcome.data;
          agg = agg + outcome.result;
        } catch (e, st) {
          Logger(
            'wish.langconvert',
          ).warning('unify skip uid=${sanitizeUid(uid)}', e, st);
        }
      }
      await indexNotifier.setSearches(allHints);
      if (ref.mounted) state = state.copyWith(byUid: newByUid);
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
  /// 回傳本次成功寫入磁碟的圖片張數（icon + header 各算一張）。
  Future<int> _fetchHoYoWiki(
    http.Client client, {
    bool forceEntryRefetch = false,
  }) async {
    var downloaded = 0;
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
    if (totalInitial == 0) return downloaded;

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
              if (!entryTodo.contains((id: hit.id, lang: pair.$2)) &&
                  needRefetchEntry(
                    ref.read(hoyowikiIndexProvider).lookupEntry(hit.id),
                    hit.menuId,
                    pair.$2,
                  )) {
                entryTodo.add((id: hit.id, lang: pair.$2));
              }
            }
          } catch (e) {
            _log.warning('hoyowiki search failed name=${pair.$1} err=$e');
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
      if (isAborted()) return downloaded;
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
            // enqueueDownloadsForEntry 會處理 icon + 各 lang 的 gallery 圖（URL 去重）。
            final entry = ref.read(hoyowikiIndexProvider).lookupEntry(pair.id);
            if (entry != null) enqueueDownloadsForEntry(pair.id, entry);
          } catch (e) {
            _log.warning(
              'hoyowiki entry failed id=${pair.id} lang=${pair.lang} err=$e',
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
      if (isAborted()) return downloaded;
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
          } catch (e) {
            _log.warning(
              'hoyowiki download failed url=${sanitizeUrl(item.url)} err=$e',
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
      if (isAborted()) return downloaded;
    }
    return downloaded;
  }

  /// 測試用：略過 banner fetch 直接跑 hoyowiki 階段（用既有 state.byUid）。
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
