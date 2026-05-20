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
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';

/// probeUid 回傳 null 時拋出，轉成 [UpdateErrorNoRecords]。
class _NoRecordsException implements Exception {
  const _NoRecordsException();
}

/// 帳號批次匯入的結果摘要。
class ImportResult {
  /// 建立 [ImportResult]。
  const ImportResult({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  /// 成功匯入的帳號數。
  final int successAccounts;

  /// 成功匯入的總紀錄數。
  final int totalRecords;

  /// 匯入失敗的 UID 列表。
  final List<String> failedUids;
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

  @override
  GachaState build() {
    _bootstrapLoad();
    return const GachaState();
  }

  /// 從本地存檔載入全部帳號資料，完成後設定 [GachaState.isBootstrapping] 為 false。
  Future<void> _bootstrapLoad() async {
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
  Future<String?> _runMitm({required bool isFallback}) async {
    state = state.copyWith(progress: WaitingForCapture(isFallback: isFallback));
    final session = ref.read(gachaCaptureProvider).start();
    _activeCancel = session.cancel;
    _log.info('MITM ${isFallback ? "fallback" : "primary"} session started');
    try {
      final result = await session.result;
      _log.info('MITM session done, hasUrl=${result != null}');
      return result;
    } finally {
      _activeCancel = null;
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
    final newData = BannerStorage(
      uid: uid,
      lastUpdated: updatedAt,
      banners: mergedBanners,
    );
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
    state = state.copyWith(
      byUid: newByUid,
      activeUid: uid,
      progress: UpdateCompleted(
        totalNewRecords: totalNew,
        failedBanners: failed,
        updatedAt: updatedAt,
      ),
    );
    if (!ref.mounted) return;
    await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
  }

  /// 防 re-entrancy 旗標，update 進行中為 true。
  bool _isUpdating = false;

  /// 使用者觸發取消時設為 true，避免將 ClientException 誤判為錯誤。
  bool _cancelTriggered = false;

  /// 目前 MITM 會話的取消函式。
  Future<void> Function()? _activeCancel;

  /// 目前 HTTP 請求的可取消 client，取消後關閉所有連線。
  CancellableHttpClient? _activeCancellable;

  /// 取消 Preparing 階段的 HTTP 請求。
  void cancelPreparing() {
    _cancelTriggered = true;
    _activeCancellable?.cancel();
  }

  /// 取消正在進行的 MITM 捕獲會話。
  Future<void> cancelCapture() async {
    final cancel = _activeCancel;
    if (cancel != null) {
      await cancel();
    }
  }

  /// 強制重新 MITM 捕獲並更新（忽略快取 URL）。
  Future<void> forceRecaptureAndUpdate() async {
    await _runUpdate(forceRecapture: true);
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
  Future<ImportResult> importAccounts(AccountsBundle bundle) async {
    final storage = ref.read(gachaStorageProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final newByUid = Map<String, BannerStorage>.from(state.byUid);
    final failed = <String>[];
    var totalRecords = 0;
    var successCount = 0;

    for (final account in bundle.accounts) {
      try {
        await storage.save(account.data);
        if (!ref.mounted) {
          return ImportResult(
            successAccounts: successCount,
            totalRecords: totalRecords,
            failedUids: failed,
          );
        }
        newByUid[account.data.uid] = account.data;
        successCount++;
        for (final list in account.data.banners.values) {
          totalRecords += list.length;
        }
      } catch (_) {
        failed.add(account.data.uid);
      }
    }

    final currentSettings = ref.read(settingsProvider);
    final mergedAliases = Map<String, String>.from(currentSettings.uidAliases);
    for (final account in bundle.accounts) {
      if (failed.contains(account.data.uid)) continue;
      final a = account.alias?.trim();
      if (a == null || a.isEmpty) {
        mergedAliases.remove(account.data.uid);
      } else {
        mergedAliases[account.data.uid] = a;
      }
    }

    final exportedOrder = bundle.accounts
        .where((a) => !failed.contains(a.data.uid))
        .map((a) => a.data.uid)
        .toList();
    final exportedSet = exportedOrder.toSet();
    final remaining = currentSettings.uidOrder
        .where((u) => !exportedSet.contains(u))
        .toList();
    final newOrder = [...exportedOrder, ...remaining];

    final desiredActive = bundle.lastActiveUid;
    final fallback =
        state.activeUid != null && newByUid.containsKey(state.activeUid)
        ? state.activeUid
        : (newByUid.isEmpty
              ? null
              : (newOrder.isEmpty ? newByUid.keys.first : newOrder.first));
    final newActive =
        (desiredActive != null && newByUid.containsKey(desiredActive))
        ? desiredActive
        : fallback;

    await settingsNotifier.applyImportedPreferences(
      aliases: mergedAliases,
      uidOrder: newOrder,
      lastActiveUid: newActive,
    );
    if (!ref.mounted) {
      return ImportResult(
        successAccounts: successCount,
        totalRecords: totalRecords,
        failedUids: failed,
      );
    }

    state = state.copyWith(
      byUid: newByUid,
      activeUid: newActive,
      clearActiveUid: newActive == null,
    );

    _log.info(
      'import: success=$successCount '
      'failed=[${failed.join(",")}] '
      'records=$totalRecords',
    );
    return ImportResult(
      successAccounts: successCount,
      totalRecords: totalRecords,
      failedUids: failed,
    );
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

  // ─── debug helpers，僅供測試用 ───
  @visibleForTesting
  void debugSetProgress(UpdateProgress p) {
    state = state.copyWith(progress: p);
  }
}
