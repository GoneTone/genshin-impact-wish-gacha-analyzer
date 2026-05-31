import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 認證過期（retcode -100 / -101）。
class AuthExpiredException implements Exception {
  /// 建立 [AuthExpiredException]，需提供 API 回傳的 [retcode]。
  AuthExpiredException(this.retcode);

  /// API 回傳的 retcode。
  final int retcode;

  @override
  String toString() => 'AuthExpiredException(retcode=$retcode)';
}

/// 請求頻率超限（retcode -110）且重試已達上限。
class RateLimitedException implements Exception {
  @override
  String toString() => 'RateLimitedException';
}

/// API 回傳非預期的錯誤 retcode。
class ApiErrorException implements Exception {
  /// 建立 [ApiErrorException]，需提供 API 的 [retcode] 與 [message]。
  ApiErrorException(this.retcode, this.message);

  /// API 回傳的 retcode。
  final int retcode;

  /// API 回傳的 message 字串。
  final String message;

  @override
  String toString() => 'ApiErrorException(retcode=$retcode, $message)';
}

/// 單頁 API 回應包裝。
class FetchedPage {
  /// 建立 [FetchedPage]，需提供本頁紀錄列表。
  const FetchedPage(this.records);

  /// 本頁紀錄列表。
  final List<GachaRecord> records;

  /// 本頁是否無紀錄。
  bool get isEmpty => records.isEmpty;

  /// 本頁紀錄數。
  int get length => records.length;
}

/// 抓取進度回報。
class FetchProgress {
  /// 建立 [FetchProgress]，帶 [gachaType]、[pageIndex]、[newRecordsSoFar] 三個進度欄位。
  const FetchProgress({
    required this.gachaType,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });

  /// 當前正在抓的卡池類型。
  final String gachaType;

  /// 目前已抓到第幾頁（1-based）。
  final int pageIndex;

  /// 目前新增紀錄累計數。
  final int newRecordsSoFar;
}

/// 負責呼叫 Hoyoverse 祈願 log API、處理分頁與新舊合併。
class GachaFetcher {
  /// 建立 [GachaFetcher]，可調整速率限制、退避時間與逾時設定。
  GachaFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.retryBackoff = const Duration(seconds: 5),
    this.timeout = const Duration(seconds: 10),
  });

  /// 兩次 API 呼叫之間的最短間隔。
  final Duration rateLimit;

  /// rate-limit 退避等待時間。
  final Duration retryBackoff;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例（gacha 抓取）。
  static final _log = Logger('gacha.fetcher');

  /// 每頁最大紀錄數（API 上限）。
  static const _pageSize = 20;

  /// rate-limit 自動退避的最大重試次數。
  static const _maxRetryOnRateLimit = 3;

  /// 抓單頁，retcode 處理：0=ok / -101,-100=AuthExpired / -110=自動退避 / 其他=ApiError
  Future<FetchedPage> fetchPage(Uri url, http.Client client) async {
    final queryGachaType = url.queryParameters['gacha_type'] ?? '';
    final queryLang = url.queryParameters['lang'] ?? '';
    var attempt = 0;
    _log.fine(
      'fetchPage gachaType=$queryGachaType url=${sanitizeUrl(url.toString())}',
    );
    while (true) {
      final res = await client.get(url).timeout(timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final retcode = body['retcode'] as int;
      if (retcode == 0) {
        final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
        return FetchedPage(
          list
              .map(
                (e) => GachaRecord.fromApiJson(
                  e as Map<String, dynamic>,
                  gachaType: queryGachaType,
                  fallbackLang: queryLang,
                ),
              )
              .toList(growable: false),
        );
      }
      if (retcode == -101 || retcode == -100) {
        _log.warning('auth expired retcode=$retcode');
        throw AuthExpiredException(retcode);
      }
      if (retcode == -110) {
        attempt++;
        _log.warning(
          'rate-limited (retcode=-110), backoff ${retryBackoff.inMilliseconds}ms, '
          'attempt=$attempt/$_maxRetryOnRateLimit',
        );
        if (attempt > _maxRetryOnRateLimit) throw RateLimitedException();
        await Future<void>.delayed(retryBackoff);
        continue;
      }
      _log.severe('ApiError retcode=$retcode message=${body['message']}');
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
  }

  /// 對指定 banner 走完分頁 + merge：existing 是該 banner 的舊 desc list
  /// primer 若不為 null 則作為第一頁（避免 UID 探測重抓）
  Future<List<GachaRecord>> fetchBannerWithMerge({
    required GachaUrl url,
    required String gachaType,
    required GachaEndpoint endpoint,
    required List<GachaRecord> existing,
    required FetchedPage? primer,
    required void Function(FetchProgress) onProgress,
    required http.Client client,
  }) async {
    final existingMaxId = existing.isEmpty ? '0' : existing.first.id;
    _log.info('banner=$gachaType start, existing=${existing.length}');
    final fresh = <GachaRecord>[];
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
          url.build(gachaType: gachaType, endId: endId, endpoint: endpoint),
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
    _log.info('banner=$gachaType done, fresh=${fresh.length} pages=$pageIndex');
    return [...fresh, ...existing];
  }

  /// 字串字典序比對；id 等長 19 字元 → 字典序 = 數值序
  bool _idGreater(String a, String b) => a.compareTo(b) > 0;

  /// UID 探測：先掃所有 gacha banner，若全部空白再掃所有 odes banner。
  /// 第一筆非空者回傳該 UID + 已累積的 primer pages。
  Future<UidProbeResult> probeUid({
    required GachaUrl url,
    required http.Client client,
  }) async {
    final primers = <String, FetchedPage>{};

    Future<UidProbeResult?> tryCategory(GachaCategory cat) async {
      final endpoint = switch (cat) {
        GachaCategory.gacha => GachaEndpoint.gacha,
        GachaCategory.odes => GachaEndpoint.odes,
      };
      for (final type in gachaTypes.where((t) => t.category == cat)) {
        if (primers.isNotEmpty) {
          await Future<void>.delayed(rateLimit);
        }
        final page = await fetchPage(
          url.build(gachaType: type.gachaType, endId: '0', endpoint: endpoint),
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
      return null;
    }

    final gachaHit = await tryCategory(GachaCategory.gacha);
    if (gachaHit != null) {
      _log.info('probe gacha: hit uid=${sanitizeUid(gachaHit.uid ?? "")}');
      return gachaHit;
    }
    final odesHit = await tryCategory(GachaCategory.odes);
    if (odesHit != null) {
      _log.info('probe odes: hit uid=${sanitizeUid(odesHit.uid ?? "")}');
      return odesHit;
    }
    _log.info('probe: no records in any banner');
    return UidProbeResult(uid: null, primerPages: primers);
  }
}

/// [GachaFetcher.probeUid] 的回傳值。
class UidProbeResult {
  /// 建立 [UidProbeResult]，包含 [uid]（可為 null）與 [primerPages] 欄位。
  const UidProbeResult({required this.uid, required this.primerPages});

  /// 探測到的 UID；若所有卡池皆無紀錄則為 null。
  final String? uid;

  /// 探測過程中已抓到的第一頁（primer），key = gachaType，供後續抓取重用避免重抓。
  final Map<String, FetchedPage> primerPages;
}
