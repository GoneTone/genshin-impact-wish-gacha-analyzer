# 「更新資料」按鈕立即回饋 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 點下「更新資料」立刻跳出 dialog，並讓「準備中」階段支援透過 `dart:io HttpClient.close(force: true)` 真正中斷 in-flight HTTP request。

**Architecture:** 在 `WishRepository._runUpdate()` 進入時立刻設定新的 `Preparing` progress 狀態 → `app_shell.dart` 既有 `ref.listen` 偵測非 null progress 立刻 `showDialog`。為了支援真正中斷 HTTP request，每次 `_runUpdate` 透過 `CancellableHttpClient` factory 建立一個短命的 `IOClient(HttpClient())`，取消時對底層 `HttpClient` 呼叫 `close(force: true)`。`WishFetcher` 同時重構為 stateless 配置容器（client 改為 per-call 參數）。

**Tech Stack:** Flutter, Riverpod (`NotifierProvider`), `dart:io HttpClient`, `package:http` `IOClient`, `package:http/testing` `MockClient`, flutter_test。

**Spec:** `docs/superpowers/specs/2026-05-11-update-button-immediate-feedback-design.md`

---

## File Structure

**新增：**
- `lib/services/cancellable_http_client.dart` — 包裝 `IOClient` + 底層 `HttpClient` reference，提供 `cancel()` 方法

**修改：**
- `lib/state/update_progress.dart` — 新增 `Preparing` sealed 子類別
- `lib/state/wish_repository.dart` — 移除 `httpClientProvider`、新增 `cancellableHttpClientFactoryProvider`、`_runUpdate` 立刻 set Preparing + cancellable client lifecycle、新增 `cancelPreparing()`、`_friendlyError` 補 `ClientException` case
- `lib/services/wish_fetcher.dart` — 建構式移除 `_client`、`fetchPage` / `probeUid` / `fetchBannerWithMerge` 加 `client` 參數
- `lib/widgets/update_progress_dialog.dart` — `_Title` / `_Body` / `_actions` 三處 switch 補 `Preparing()` case
- `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hant.arb` — 各新增 `progressPreparing`、`progressPreparingHint`
- `test/services/wish_fetcher_test.dart` — 適配 client per-call
- `test/state/wish_repository_test.dart` — 既有測試替換 provider override、新增 3 個 Preparing 相關測試

**自動產生（不手寫）：**
- `lib/l10n/generated/app_localizations.dart`、`_en.dart`、`_zh.dart` — 由 `flutter gen-l10n` 重新產出

---

## Task 1：新增 `Preparing` UpdateProgress 子類別

**Files:**
- Modify: `lib/state/update_progress.dart`

- [ ] **Step 1：新增 `Preparing` sealed 子類別**

在 `lib/state/update_progress.dart` 的 `class WaitingForCapture` 之前加入：

```dart
class Preparing extends UpdateProgress {
  const Preparing();
}
```

完整檔案結構應為：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

sealed class UpdateProgress {
  const UpdateProgress();
}

class Preparing extends UpdateProgress {
  const Preparing();
}

class WaitingForCapture extends UpdateProgress {
  const WaitingForCapture({this.isFallback = false});
  final bool isFallback;
}

class FetchingBanner extends UpdateProgress {
  const FetchingBanner({
    required this.gachaType,
    required this.displayName,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final String displayName;
  final int pageIndex;
  final int newRecordsSoFar;
}

class UpdateCompleted extends UpdateProgress {
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
  });
  final int totalNewRecords;
  final List<String> failedBanners;
  final DateTime updatedAt;
}

class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.error);
  final UpdateError error;
}
```

- [ ] **Step 2：執行 `flutter analyze`**

Run: `flutter analyze`

Expected: 出現「The type 'Preparing' is not exhaustively matched」之類的 switch 警告，因為 `UpdateProgressDialog` 內三個 switch 還沒處理 `Preparing`。**這是預期的，下一個 task 才會處理**。

也可能因為 Dart 還允許非 sealed exhaustive（會給 warning 而非 error）而通過。任一結果都可接受，繼續下一個 Task。

- [ ] **Step 3：暫時不 commit**

這個改動沒有對應的行為改變，等 Task 8（Dialog 補 Preparing case）一起 commit。

---

## Task 2：新增 `CancellableHttpClient` 抽象

**Files:**
- Create: `lib/services/cancellable_http_client.dart`

- [ ] **Step 1：建立 `CancellableHttpClient` 類別與 production factory**

寫入 `lib/services/cancellable_http_client.dart`：

```dart
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 包裝一個 [http.Client] 與「強制中斷其底層連線」的能力。
///
/// 用於需要在發出 HTTP request 後立刻取消的場景：
/// production 實作建立 [io.HttpClient] 並用 [IOClient] 包裝，
/// [cancel] 呼叫底層 `HttpClient.close(force: true)` 強制中斷所有
/// in-flight request（會讓 await 中的 request 拋 [http.ClientException]）。
class CancellableHttpClient {
  CancellableHttpClient({required this.client, required this.cancel});

  final http.Client client;
  final void Function() cancel;
}

typedef CancellableHttpClientFactory = CancellableHttpClient Function();

/// Production factory：建立可強制中斷的 [CancellableHttpClient]。
CancellableHttpClient createIoCancellableHttpClient() {
  final ioClient = io.HttpClient();
  return CancellableHttpClient(
    client: IOClient(ioClient),
    cancel: () => ioClient.close(force: true),
  );
}
```

- [ ] **Step 2：執行 `flutter analyze`**

Run: `flutter analyze`

Expected: `No issues found!`（新檔案語法正確、imports 都有用到）。先前 Task 1 的 switch 警告可能仍在，等 Task 8 處理。

- [ ] **Step 3：暫時不 commit**

等下一個 Task 把 `WishRepository` 接上來再一起 commit。

---

## Task 3：重構 `WishFetcher` 為 stateless（client per-call）

**Files:**
- Modify: `lib/services/wish_fetcher.dart`
- Modify: `test/services/wish_fetcher_test.dart`

- [ ] **Step 1：先改測試呼叫端，預期失敗**

更新 `test/services/wish_fetcher_test.dart`，把 `WishFetcher(mock, ...)` 改成 `WishFetcher(...)` 並把 `mock` 傳給 `fetchPage` 第二個參數：

```dart
void main() {
  group('WishFetcher.fetchPage', () {
    test('retcode=0 解析 list', () async {
      final mock = MockClient(
        (req) async => _ok([_record(id: '1', type: '301')]),
      );
      final fetcher = WishFetcher(rateLimit: Duration.zero);
      final page = await fetcher.fetchPage(
        GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0'),
        mock,
      );
      expect(page.records, hasLength(1));
      expect(page.records.first.id, '1');
    });

    test('retcode=-101 throw AuthExpiredException', () async {
      final mock = MockClient((req) async => _err(-101));
      final fetcher = WishFetcher(rateLimit: Duration.zero);
      expect(
        () => fetcher.fetchPage(
          GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0'),
          mock,
        ),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('retcode=-110 退避後 throw RateLimitedException', () async {
      var hits = 0;
      final mock = MockClient((req) async {
        hits++;
        return _err(-110);
      });
      final fetcher = WishFetcher(
        rateLimit: Duration.zero,
        retryBackoff: Duration.zero,
      );
      await expectLater(
        () => fetcher.fetchPage(
          GachaUrl.parse(_baseUrl).build(gachaType: '301', endId: '0'),
          mock,
        ),
        throwsA(isA<RateLimitedException>()),
      );
      expect(hits, greaterThan(1));
    });
  });
}
```

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/services/wish_fetcher_test.dart`

Expected: 編譯錯誤，因為 `WishFetcher` 建構式仍要求 `_client` positional 參數、`fetchPage` 仍是單參數簽名。

- [ ] **Step 3：重構 `WishFetcher` 為 stateless**

完整改寫 `lib/services/wish_fetcher.dart`：

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';

class AuthExpiredException implements Exception {
  AuthExpiredException(this.retcode);
  final int retcode;
  @override
  String toString() => 'AuthExpiredException(retcode=$retcode)';
}

class RateLimitedException implements Exception {
  @override
  String toString() => 'RateLimitedException';
}

class ApiErrorException implements Exception {
  ApiErrorException(this.retcode, this.message);
  final int retcode;
  final String message;
  @override
  String toString() => 'ApiErrorException(retcode=$retcode, $message)';
}

class FetchedPage {
  const FetchedPage(this.records);
  final List<WishRecord> records;
  bool get isEmpty => records.isEmpty;
  int get length => records.length;
}

class FetchProgress {
  const FetchProgress({
    required this.gachaType,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });
  final String gachaType;
  final int pageIndex;
  final int newRecordsSoFar;
}

class WishFetcher {
  WishFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.retryBackoff = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 10),
  });

  final Duration rateLimit;
  final Duration retryBackoff;
  final Duration timeout;

  static const _pageSize = 20;
  static const _maxRetryOnRateLimit = 3;

  /// 抓單頁，retcode 處理：0=ok / -101,-100=AuthExpired / -110=自動退避 / 其他=ApiError
  Future<FetchedPage> fetchPage(Uri url, http.Client client) async {
    var attempt = 0;
    while (true) {
      final res = await client.get(url).timeout(timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final retcode = body['retcode'] as int;
      if (retcode == 0) {
        final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
        return FetchedPage(
          list
              .map((e) => WishRecord.fromApiJson(e as Map<String, dynamic>))
              .toList(growable: false),
        );
      }
      if (retcode == -101 || retcode == -100) {
        throw AuthExpiredException(retcode);
      }
      if (retcode == -110) {
        attempt++;
        if (attempt > _maxRetryOnRateLimit) throw RateLimitedException();
        await Future<void>.delayed(retryBackoff);
        continue;
      }
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
  }

  /// 對指定 banner 走完分頁 + merge：existing 是該 banner 的舊 desc list
  /// primer 若不為 null 則作為第一頁（避免 UID 探測重抓）
  Future<List<WishRecord>> fetchBannerWithMerge({
    required GachaUrl url,
    required String gachaType,
    required List<WishRecord> existing,
    required FetchedPage? primer,
    required void Function(FetchProgress) onProgress,
    required http.Client client,
  }) async {
    final existingMaxId = existing.isEmpty ? '0' : existing.first.id;
    final fresh = <WishRecord>[];
    var endId = '0';
    var isFirstPage = true;
    var pageIndex = 1;

    while (true) {
      final FetchedPage page;
      if (isFirstPage && primer != null) {
        page = primer;
      } else {
        if (!isFirstPage) {
          await Future<void>.delayed(rateLimit);
        }
        page = await fetchPage(
          url.build(gachaType: gachaType, endId: endId),
          client,
        );
      }
      isFirstPage = false;

      if (page.isEmpty) break;

      // 從頭往後吃直到碰到 existingMaxId 或頁尾
      var hitOld = false;
      for (final r in page.records) {
        if (_idGreater(r.id, existingMaxId)) {
          fresh.add(r);
        } else {
          hitOld = true;
          break;
        }
      }
      onProgress(
        FetchProgress(
          gachaType: gachaType,
          pageIndex: pageIndex,
          newRecordsSoFar: fresh.length,
        ),
      );

      if (hitOld) break;
      if (page.length < _pageSize) break;
      endId = page.records.last.id;
      pageIndex++;
    }

    // fresh + existing 都是 desc
    return [...fresh, ...existing];
  }

  /// 字串字典序比對；id 等長 19 字元 → 字典序 = 數值序
  bool _idGreater(String a, String b) => a.compareTo(b) > 0;

  /// UID 探測：依 gachaTypes 順序對每個 banner 抓 1 頁，第一筆非空者回傳
  Future<UidProbeResult> probeUid({
    required GachaUrl url,
    required http.Client client,
  }) async {
    final primers = <String, FetchedPage>{};
    for (final type in gachaTypes) {
      if (primers.isNotEmpty) {
        await Future<void>.delayed(rateLimit);
      }
      final page = await fetchPage(
        url.build(gachaType: type.gachaType, endId: '0'),
        client,
      );
      primers[type.gachaType] = page;
      if (page.records.isNotEmpty) {
        return UidProbeResult(
          uid: page.records.first.uid,
          primerPages: primers,
        );
      }
    }
    return const UidProbeResult(uid: null, primerPages: {});
  }
}

class UidProbeResult {
  const UidProbeResult({required this.uid, required this.primerPages});
  final String? uid;
  final Map<String, FetchedPage> primerPages;
}
```

- [ ] **Step 4：執行 fetcher 測試，確認通過**

Run: `flutter test test/services/wish_fetcher_test.dart`

Expected: 全部 3 個測試 PASS。

- [ ] **Step 5：執行 `flutter analyze`**

Run: `flutter analyze`

Expected：仍會有 `wish_repository.dart` 內 `probeUid` / `fetchBannerWithMerge` 呼叫缺少 `client` 參數的編譯錯誤。**這是預期的**，下一個 Task 處理。

- [ ] **Step 6：暫時不 commit**

等 Task 4 把 repository 接上來才一起 commit。

---

## Task 4：`WishRepository` 接上 `CancellableHttpClient`（不加新行為，僅 plumbing）

此 Task 只做「接上 client lifecycle 與 provider 替換」，**不**加 Preparing 初始 set、**不**加 cancelPreparing、**不**加 ClientException 分支。讓所有既有測試先過。

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `test/state/wish_repository_test.dart`

- [ ] **Step 1：先改既有 repository 測試的 provider override**

把 `test/state/wish_repository_test.dart` 內所有 `httpClientProvider.overrideWithValue(MockClient(...))` 替換為 `cancellableHttpClientFactoryProvider.overrideWithValue(() => CancellableHttpClient(client: MockClient(...), cancel: () {}))`。

頂端 import 加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
```

四處 override 改成：

```dart
// bootstrap test：
cancellableHttpClientFactoryProvider.overrideWithValue(
  () => CancellableHttpClient(
    client: MockClient((_) async {
      throw 'unreachable';
    }),
    cancel: () {},
  ),
),
```

```dart
// bootstrap 2 UIDs：
cancellableHttpClientFactoryProvider.overrideWithValue(
  () => CancellableHttpClient(
    client: MockClient((_) async => http.Response('{}', 200)),
    cancel: () {},
  ),
),
```

```dart
// AuthExpired 2x：
cancellableHttpClientFactoryProvider.overrideWithValue(
  () => CancellableHttpClient(client: mock, cancel: () {}),
),
```

```dart
// clearProgress：
cancellableHttpClientFactoryProvider.overrideWithValue(
  () => CancellableHttpClient(
    client: MockClient((_) async => http.Response('{}', 200)),
    cancel: () {},
  ),
),
```

- [ ] **Step 2：執行測試，確認因為 provider 不存在而失敗**

Run: `flutter test test/state/wish_repository_test.dart`

Expected: 編譯錯誤「`cancellableHttpClientFactoryProvider` is undefined」。

- [ ] **Step 3：重寫 `WishRepository` 引入 cancellable client 流程**

完整改寫 `lib/state/wish_repository.dart`：

```dart
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

    final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
    _activeCancellable = cancellable;

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
        } catch (e) {
          if (!ref.mounted) return;
          state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
        }
      } catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(progress: UpdateFailed(_friendlyError(e)));
      }
    } finally {
      _activeCancellable?.client.close();
      _activeCancellable = null;
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
  Future<void> Function()? _activeCancel;
  CancellableHttpClient? _activeCancellable;

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
    _ => UpdateErrorOther(e.toString()),
  };

  // ─── debug helpers，僅供測試用 ───
  @visibleForTesting
  void debugSetProgress(UpdateProgress p) {
    state = state.copyWith(progress: p);
  }
}
```

注意：本 Task **沒有**加 Preparing 初始 set、**沒有**加 cancelPreparing、**沒有**加 ClientException 分支。這些行為改動留到 Task 5、6。

- [ ] **Step 4：執行既有測試，確認全部通過**

Run: `flutter test test/state/wish_repository_test.dart`

Expected: 既有 4 個測試 PASS。

- [ ] **Step 5：執行全測試 + analyze + format**

```bash
flutter analyze
dart format lib/ test/
flutter test
```

Expected：
- `flutter analyze`：仍可能有 `update_progress_dialog.dart` 對 `Preparing` 不 exhaustive 的 switch 警告（Task 8 修），其他無誤
- `dart format`：可能 reformat 些檔案
- `flutter test`：全 PASS

- [ ] **Step 6：Commit plumbing 重構**

```bash
git add lib/services/cancellable_http_client.dart \
        lib/services/wish_fetcher.dart \
        lib/state/wish_repository.dart \
        lib/state/update_progress.dart \
        test/services/wish_fetcher_test.dart \
        test/state/wish_repository_test.dart
git commit -m "refactor(fetcher,repository): introduce CancellableHttpClient, make WishFetcher stateless"
```

---

## Task 5：TDD — `update()` 立刻設定 `Preparing`

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `test/state/wish_repository_test.dart`

- [ ] **Step 1：在 repository 測試新增「立刻 set Preparing」測試**

在 `test/state/wish_repository_test.dart` 內加入：

```dart
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
```

頂端 import 補上 `dart:async`：

```dart
import 'dart:async';
```

也補上：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
```

（若 Task 4 已加過則略）

- [ ] **Step 2：執行測試，確認失敗**

Run: `flutter test test/state/wish_repository_test.dart -p vm --name "update() 立刻設定 Preparing"`

Expected: 失敗。錯誤訊息類似「expected Preparing but state.progress was null」或「`cancelPreparing` is undefined」。

- [ ] **Step 3：實作 — `_runUpdate` 進入時立刻 set Preparing；補 `cancelPreparing` stub**

在 `lib/state/wish_repository.dart` `_runUpdate` 方法內、`_activeCancellable = cancellable;` 後面新增一行：

```dart
state = state.copyWith(progress: const Preparing());
```

並在 `WishRepository` class 內（建議放在 `cancelCapture` 下方）新增臨時 `cancelPreparing` 方法（Task 6 會擴充）：

```dart
void cancelPreparing() {
  _activeCancellable?.cancel();
}
```

完整片段（`_runUpdate` 開頭）：

```dart
Future<void> _runUpdate({required bool forceRecapture}) async {
  if (_isUpdating) return;
  _isUpdating = true;

  final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
  _activeCancellable = cancellable;

  // 立刻 set Preparing → ref.listen 立刻觸發 dialog
  state = state.copyWith(progress: const Preparing());

  try {
    // ...
```

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/state/wish_repository_test.dart`

Expected: 包含新測試在內全部 PASS。

- [ ] **Step 5：暫時不 commit**

等 Task 6 把 ClientException 分支與 _cancelTriggered 加完一起 commit。

---

## Task 6：TDD — `cancelPreparing` 與 `ClientException` 分流

**Files:**
- Modify: `lib/state/wish_repository.dart`
- Modify: `test/state/wish_repository_test.dart`

- [ ] **Step 1：新增「cancelPreparing → clearProgress」與「ClientException 非取消 → UpdateFailed」兩個測試**

加在 `test/state/wish_repository_test.dart`：

```dart
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
```

- [ ] **Step 2：執行兩個新測試，確認失敗**

Run: `flutter test test/state/wish_repository_test.dart`

Expected: 兩個新測試失敗。「cancelPreparing → clearProgress」會得到 `UpdateFailed`（被泛 `catch (e)` 攔住設成 failed），「probe 真實 ClientException → UpdateFailed」可能恰好通過（因為泛 catch 已會設 failed），但測試斷言 `UpdateErrorOther` 的 message 應與 `e.toString()` 一致——目前 fallback 是 `_ => UpdateErrorOther(e.toString())` 會回 `ClientException: network down, uri=...`，可接受。第一個測試一定失敗。

- [ ] **Step 3：實作 — 加 `_cancelTriggered` flag、`on http.ClientException` 兩處攔截、`_friendlyError` 補 case**

修改 `lib/state/wish_repository.dart`：

A. 在 `_isUpdating` 旁加 `_cancelTriggered`：

```dart
bool _isUpdating = false;
bool _cancelTriggered = false;
Future<void> Function()? _activeCancel;
CancellableHttpClient? _activeCancellable;
```

B. `_runUpdate` 在進入 try 之前重置 flag，finally 內也重置：

```dart
Future<void> _runUpdate({required bool forceRecapture}) async {
  if (_isUpdating) return;
  _isUpdating = true;
  _cancelTriggered = false;

  final cancellable = ref.read(cancellableHttpClientFactoryProvider)();
  _activeCancellable = cancellable;

  state = state.copyWith(progress: const Preparing());

  try {
    // ...既有邏輯
  } finally {
    _activeCancellable?.client.close();
    _activeCancellable = null;
    _cancelTriggered = false;
    _isUpdating = false;
  }
}
```

C. 在 `_runUpdate` 兩處 `catch (e)` 之前各加一個 `on http.ClientException catch (e)`。**初始 fetch 區塊**：

```dart
try {
  await _fetchAllBanners(
    url: capturedUrl,
    fetcher: fetcher,
    storage: storage,
    client: cancellable.client,
  );
} on AuthExpiredException {
  // ...既有 fallback
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
```

**Fallback 內層 fetch 區塊**（在 `on AuthExpiredException { ... try { await _fetchAllBanners(...); }` 內的 try）也照樣補：

```dart
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
```

D. 升級 `cancelPreparing`（Task 5 的 stub）：

```dart
void cancelPreparing() {
  _cancelTriggered = true;
  _activeCancellable?.cancel();
}
```

E. `_friendlyError` 加 `http.ClientException` case：

```dart
UpdateError _friendlyError(Object e) => switch (e) {
  _NoRecordsException() => const UpdateErrorNoRecords(),
  FormatException(:final message) => UpdateErrorOther(message),
  RateLimitedException() => const UpdateErrorRateLimited(),
  ApiErrorException(:final message) => UpdateErrorServer(message),
  AuthExpiredException() => const UpdateErrorAuthExpired(),
  http.ClientException(:final message) => UpdateErrorOther(message),
  _ => UpdateErrorOther(e.toString()),
};
```

- [ ] **Step 4：執行測試，確認通過**

Run: `flutter test test/state/wish_repository_test.dart`

Expected: 全部測試（既有 4 + 新增 3 = 7 個）PASS。

- [ ] **Step 5：Commit**

```bash
git add lib/state/wish_repository.dart test/state/wish_repository_test.dart
git commit -m "feat(repository): show Preparing immediately, support cancelling in-flight HTTP via force close"
```

---

## Task 7：`UpdateProgressDialog` 補 `Preparing` 三處 switch

**Files:**
- Modify: `lib/widgets/update_progress_dialog.dart`

- [ ] **Step 1：在 `_Title` switch 加 `Preparing()` case**

`lib/widgets/update_progress_dialog.dart` 內 `_Title.build` 的 `switch (progress)`：

```dart
final (icon, color, text) = switch (progress) {
  Preparing() => (
    Icons.hourglass_empty,
    tokens.textPrimary,
    l.progressPreparing,
  ),
  WaitingForCapture() => (
    Icons.hourglass_top,
    tokens.textPrimary,
    l.progressWaiting,
  ),
  // ...其他 case
};
```

- [ ] **Step 2：在 `_Body` switch 加 `Preparing()` case**

`_Body.build` 的 `switch (progress)`：

```dart
return switch (progress) {
  Preparing() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LinearProgressIndicator(),
      const SizedBox(height: AppSpacing.l),
      Text(l.progressPreparingHint),
    ],
  ),
  WaitingForCapture(:final isFallback) => Column(
    // ...
  ),
  // ...其他 case
};
```

- [ ] **Step 3：在 `_actions` switch 加 `Preparing()` case**

`UpdateProgressDialog._actions` 的 `switch (p)`：

```dart
return switch (p) {
  Preparing() => [
    TextButton(
      onPressed: r.cancelPreparing,
      child: Text(l.actionCancel),
    ),
  ],
  WaitingForCapture() => [
    TextButton(
      onPressed: () async {
        await r.cancelCapture();
      },
      child: Text(l.actionCancel),
    ),
  ],
  // ...其他 case
};
```

- [ ] **Step 4：執行 `flutter analyze`**

Run: `flutter analyze`

Expected: 此時可能會抱怨 `l.progressPreparing` / `l.progressPreparingHint` getter 不存在。這是預期的，下一個 Task 補 i18n 字串。

- [ ] **Step 5：暫時不 commit**

等 Task 8 加完 i18n 字串、執行 `flutter gen-l10n`，三檔一起 commit。

---

## Task 8：新增 i18n 字串 + 重新產生 generated

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Regenerate: `lib/l10n/generated/*.dart`

- [ ] **Step 1：在 `app_zh_Hant.arb` 的 `progressWaiting` 之前加 2 個字串**

把 `lib/l10n/app_zh_Hant.arb` 的：

```json
  "progressWaiting": "等待攔截…",
```

替換為：

```json
  "progressPreparing": "準備中…",
  "progressPreparingHint": "正在準備資料來源…",
  "progressWaiting": "等待攔截…",
```

- [ ] **Step 2：在 `app_zh.arb` 的 `progressWaiting` 之前加 2 個字串**

替換：

```json
  "progressWaiting": "等待攔截…",
```

為：

```json
  "progressPreparing": "准备中…",
  "progressPreparingHint": "正在准备数据源…",
  "progressWaiting": "等待攔截…",
```

- [ ] **Step 3：在 `app_en.arb` 的 `progressWaiting` 之前加 2 個字串**

替換：

```json
  "progressWaiting": "Waiting for capture…",
```

為：

```json
  "progressPreparing": "Preparing…",
  "progressPreparingHint": "Preparing data source…",
  "progressWaiting": "Waiting for capture…",
```

- [ ] **Step 4：執行 `flutter gen-l10n`**

Run: `flutter gen-l10n`

Expected: 無錯誤輸出。`lib/l10n/generated/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart` 會被自動更新，新增 `progressPreparing` 與 `progressPreparingHint` getter。

- [ ] **Step 5：執行 analyze + format + 全測試**

```bash
flutter analyze
dart format lib/ test/
flutter test
```

Expected：
- `flutter analyze`：`No issues found!`
- `flutter test`：`All tests passed!`

- [ ] **Step 6：Commit Dialog + i18n**

```bash
git add lib/widgets/update_progress_dialog.dart \
        lib/l10n/app_en.arb \
        lib/l10n/app_zh.arb \
        lib/l10n/app_zh_Hant.arb \
        lib/l10n/generated/
git commit -m "feat(dialog,i18n): render Preparing state with cancel action and localized strings"
```

---

## Task 9：手動驗證 + 最終 commit gate

**Files:** 無檔案改動，純驗證。

- [ ] **Step 1：執行 `flutter run -d windows` 手動驗證**

Run: `flutter run -d windows`

Expected：
1. App 啟動到主畫面
2. 點右上「更新資料」→ **dialog 立刻跳出**（標題「準備中…」，下方 LinearProgressIndicator + 「正在準備資料來源…」，底部「取消」按鈕）
3. 等 1–2 秒（無 cached URL 路徑下會切到「等待攔截」）或在 cached URL 路徑下繼續到 fetching
4. 若有 cached URL，在 Preparing 期間點「取消」→ dialog 立刻關閉，footer 顯示既有最後更新時間

若 app 還沒有任何 UID 資料（fresh install），第 4 步無法直接驗證 cancel 路徑——可以先做一次完整更新後重來，或在 settings page 用 import 注入一份測試資料。

- [ ] **Step 2：確認 build 設定齊全（`pubspec.yaml` 沒有改動）**

執行：

```bash
git diff --stat HEAD~3..HEAD
```

Expected：只包含 `lib/`、`test/`、`docs/superpowers/` 內檔案，無 `pubspec.yaml` 改動（`http`、`http/io_client` 與 `dart:io` 都在現有依賴 / SDK 內）。

若 `flutter analyze` / `flutter test` 對 `package:http/io_client.dart` import 報「target of URI doesn't exist」，回頭檢查 `pubspec.yaml` 內 `http` 套件版本（應已存在於既有依賴）。`io_client.dart` 是 `http` 套件內建子 library，無需額外依賴。

- [ ] **Step 3：CLAUDE.md commit gate 三件套最後一次跑**

```bash
dart format lib/ test/
flutter analyze
flutter test
```

Expected：
- `dart format`：no files changed（或極少 formatting）
- `flutter analyze`：`No issues found!`
- `flutter test`：`All tests passed!`

- [ ] **Step 4：若 format 有改動，追加一個 commit**

只有 `dart format` 改了任何檔案時做：

```bash
git add lib/ test/
git commit -m "style: dart format"
```

否則 plan 結束。

---

## 自我檢查（已執行）

**Spec coverage：**
- §1 Preparing → Task 1
- §2 WishFetcher per-call client → Task 3
- §3 Repository cancellable client + Preparing 初始 set + ClientException catch + cancelPreparing → Task 4 (plumbing) + Task 5 (Preparing 立刻 set) + Task 6 (cancel + ClientException 分流)
- §4 Dialog 補 case → Task 7
- §5 移除 httpClientProvider → Task 4 (用 cancellableHttpClientFactoryProvider 取代)
- §6 i18n 字串 → Task 8
- §7 測試（fetcher 適配 + 三個 repository 測試）→ Task 3、Task 5、Task 6
- §8 提交前檢查 → Task 9

**Placeholder scan：** 無 TBD / TODO / 「filled in later」。所有 code step 含完整程式碼或精準替換指示。

**Type consistency：**
- `CancellableHttpClient({required this.client, required this.cancel})` 一致用於 Task 2 定義、Task 4 / 5 / 6 測試 override
- `cancellableHttpClientFactoryProvider` 名稱一致
- `cancelPreparing()` 在 Task 5（stub）和 Task 6（升級含 flag）名稱一致
- `_activeCancellable`（CancellableHttpClient field）vs `_activeCancel`（既有 MITM cancel callback field）兩個欄位刻意分名，避免混淆，貫穿全文一致
