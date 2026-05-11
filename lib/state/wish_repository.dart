import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_capture.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_progress.dart';

class _NoRecordsException implements Exception {
  const _NoRecordsException();
}

@immutable
class WishState {
  const WishState({
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

  WishState copyWith({
    String? activeUid,
    bool clearActiveUid = false,
    Map<String, BannerStorage>? byUid,
    UpdateProgress? progress,
    bool clearProgress = false,
    bool? isBootstrapping,
  }) => WishState(
    activeUid: clearActiveUid ? null : (activeUid ?? this.activeUid),
    byUid: byUid ?? this.byUid,
    progress: clearProgress ? null : (progress ?? this.progress),
    isBootstrapping: isBootstrapping ?? this.isBootstrapping,
  );
}

// ─── Providers ───

/// 必須在 main.dart 用 overrideWithValue 注入（baseDir 需要 async 取得）
final wishStorageProvider = Provider<WishStorage>((ref) {
  throw UnimplementedError('wishStorageProvider must be overridden in main()');
});

final wishCaptureProvider = Provider<WishCapture>((ref) => RustWishCapture());

final wishFetcherProvider = Provider<WishFetcher>((ref) => WishFetcher());

/// 每次 update 用一個獨立的 [CancellableHttpClient]（cancel 不會影響其他連線）。
final cancellableHttpClientFactoryProvider =
    Provider<CancellableHttpClientFactory>(
      (ref) => createIoCancellableHttpClient,
    );

final wishRepositoryProvider = NotifierProvider<WishRepository, WishState>(
  WishRepository.new,
);

// ─── Notifier ───

class WishRepository extends Notifier<WishState> {
  @override
  WishState build() {
    _bootstrapLoad();
    return const WishState();
  }

  Future<void> _bootstrapLoad() async {
    final storage = ref.read(wishStorageProvider);
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
    final newest = byUid.values.reduce(
      (a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b,
    );
    state = state.copyWith(
      byUid: byUid,
      activeUid: newest.uid,
      isBootstrapping: false,
    );
  }

  Future<void> setActiveUid(String uid) async {
    if (!state.byUid.containsKey(uid)) return;
    state = state.copyWith(activeUid: uid);
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

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;

    // 立刻 set Preparing → ref.listen 立刻觸發 dialog
    state = state.copyWith(progress: const Preparing());

    try {
      final initialActiveUid = state.activeUid;
      final storage = ref.read(wishStorageProvider);
      final fetcher = ref.read(wishFetcherProvider);

      if (forceRecapture && initialActiveUid != null) {
        await storage.deleteCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
      }

      String? capturedUrl;

      if (!forceRecapture && initialActiveUid != null) {
        capturedUrl = await storage.loadCapturedUrl(initialActiveUid);
        if (!ref.mounted) return;
      }

      if (capturedUrl == null) {
        capturedUrl = await _runMitm(isFallback: false);
        if (!ref.mounted) return;
        if (capturedUrl == null) {
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
          state = state.copyWith(clearProgress: true);
        } else {
          state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
        }
      } catch (e) {
        if (!ref.mounted) return;
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
    final session = ref.read(wishCaptureProvider).start();
    _activeCancel = session.cancel;
    try {
      return await session.result;
    } finally {
      _activeCancel = null;
    }
  }

  Future<void> _fetchAllBanners({
    required String url,
    required WishFetcher fetcher,
    required WishStorage storage,
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
          banners: {for (final t in gachaTypes) t.gachaType: <WishRecord>[]},
        );

    final mergedBanners = <String, List<WishRecord>>{};
    final failed = <String>[];
    var totalNew = 0;

    for (final t in gachaTypes) {
      try {
        final merged = await fetcher.fetchBannerWithMerge(
          url: gachaUrl,
          gachaType: t.gachaType,
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
    state = state.copyWith(
      byUid: newByUid,
      activeUid: uid,
      progress: UpdateCompleted(
        totalNewRecords: totalNew,
        failedBanners: failed,
        updatedAt: updatedAt,
      ),
    );
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
    final storage = ref.read(wishStorageProvider);
    await storage.delete(uid);
    if (!ref.mounted) return;
    final newByUid = Map<String, BannerStorage>.from(state.byUid)..remove(uid);
    if (newByUid.isEmpty) {
      state = state.copyWith(byUid: newByUid, clearActiveUid: true);
    } else {
      final newest = newByUid.values.reduce(
        (a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b,
      );
      state = state.copyWith(byUid: newByUid, activeUid: newest.uid);
    }
  }

  Future<void> clearAll() async {
    final storage = ref.read(wishStorageProvider);
    await storage.clearAll();
    if (!ref.mounted) return;
    state = const WishState(isBootstrapping: false);
  }

  Future<void> importData(BannerStorage data) async {
    final storage = ref.read(wishStorageProvider);
    await storage.save(data);
    if (!ref.mounted) return;
    final newByUid = Map<String, BannerStorage>.from(state.byUid)
      ..[data.uid] = data;
    state = state.copyWith(byUid: newByUid, activeUid: data.uid);
  }

  Future<void> removeUid(String uid) async {
    final storage = ref.read(wishStorageProvider);
    await storage.delete(uid);
    if (!ref.mounted) return;
    final newByUid = Map<String, BannerStorage>.from(state.byUid)..remove(uid);
    if (state.activeUid == uid) {
      if (newByUid.isEmpty) {
        state = state.copyWith(byUid: newByUid, clearActiveUid: true);
      } else {
        final newest = newByUid.values.reduce(
          (a, b) => a.lastUpdated.isAfter(b.lastUpdated) ? a : b,
        );
        state = state.copyWith(byUid: newByUid, activeUid: newest.uid);
      }
    } else {
      state = state.copyWith(byUid: newByUid);
    }
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
