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

class _NoRecordsException implements Exception {
  const _NoRecordsException();
}

class ImportResult {
  const ImportResult({
    required this.successAccounts,
    required this.totalRecords,
    required this.failedUids,
  });

  final int successAccounts;
  final int totalRecords;
  final List<String> failedUids;
}

@immutable
class GachaState {
  const GachaState({
    this.activeUid,
    this.byUid = const {},
    this.progress,
    this.isBootstrapping = true,
  });

  final String? activeUid;
  final Map<String, BannerStorage> byUid;
  final UpdateProgress? progress;
  final bool isBootstrapping;

  BannerStorage? get activeData => activeUid == null ? null : byUid[activeUid];
  Iterable<String> get knownUids => byUid.keys;

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

final gachaCaptureProvider = Provider<GachaCapture>(
  (ref) => RustGachaCapture(),
);

final gachaFetcherProvider = Provider<GachaFetcher>((ref) => GachaFetcher());

/// 每次 update 用一個獨立的 [CancellableHttpClient]（cancel 不會影響其他連線）。
final cancellableHttpClientFactoryProvider =
    Provider<CancellableHttpClientFactory>(
      (ref) => createIoCancellableHttpClient,
    );

final gachaRepositoryProvider = NotifierProvider<GachaRepository, GachaState>(
  GachaRepository.new,
);

// ─── Notifier ───

class GachaRepository extends Notifier<GachaState> {
  static final _log = Logger('gacha.repo');

  @override
  GachaState build() {
    _bootstrapLoad();
    return const GachaState();
  }

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

  Future<void> setActiveUid(String uid) async {
    if (!state.byUid.containsKey(uid)) return;
    state = state.copyWith(activeUid: uid);
    await ref.read(settingsProvider.notifier).setLastActiveUid(uid);
  }

  void clearProgress() {
    state = state.copyWith(clearProgress: true);
  }

  Future<void> update() async {
    await _runUpdate(forceRecapture: false);
  }

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

  bool _isUpdating = false;
  bool _cancelTriggered = false;
  Future<void> Function()? _activeCancel;
  CancellableHttpClient? _activeCancellable;

  void cancelPreparing() {
    _cancelTriggered = true;
    _activeCancellable?.cancel();
  }

  Future<void> cancelCapture() async {
    final cancel = _activeCancel;
    if (cancel != null) {
      await cancel();
    }
  }

  Future<void> forceRecaptureAndUpdate() async {
    await _runUpdate(forceRecapture: true);
  }

  Future<void> clearActive() async {
    final uid = state.activeUid;
    if (uid == null) return;
    await removeUid(uid);
  }

  Future<void> clearAll() async {
    final storage = ref.read(gachaStorageProvider);
    await storage.clearAll();
    if (!ref.mounted) return;
    await ref.read(settingsProvider.notifier).clearAllUidPreferences();
    if (!ref.mounted) return;
    state = const GachaState(isBootstrapping: false);
    _log.info('cleared all gacha data');
  }

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

  String? _pickFallbackActive(Map<String, BannerStorage> byUid) {
    if (byUid.isEmpty) return null;
    final order = ref.read(settingsProvider).uidOrder;
    return mergeUidOrder(
      knownUids: byUid.keys,
      customOrder: order,
      lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
    ).first;
  }

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
