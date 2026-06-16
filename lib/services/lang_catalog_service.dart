import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

/// 解析某語言名冊：memo → 本地快取 → 抓取落地。同實例以 memo 避免單次轉換內
/// 重複讀檔／抓取。`forceRefresh` 供「未命中刷新」略過快取強制重抓。
class LangCatalogService {
  /// 建立 [LangCatalogService]。
  LangCatalogService({
    required this.storage,
    required this.fetcher,
    required this.clientFactory,
  });

  /// 名冊持久化。
  final LangCatalogStorage storage;

  /// 名冊抓取器。
  final LangCatalogFetcher fetcher;

  /// 建立 http client 的工廠（每次抓取用後即關）。
  final http.Client Function() clientFactory;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// 單次執行的記憶體快取；無時間過期（disk 為真相）。
  final Map<String, LangCatalog> _memo = {};

  /// 取得 [lang] 名冊：memo → 本地 → 抓取落地。網路失敗時拋出（呼叫端決定處理）。
  ///
  /// [forceRefresh] 為 true 時略過 memo／本地快取，強制重抓並覆寫（供未命中刷新）。
  Future<LangCatalog> ensure(String lang, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final memo = _memo[lang];
      if (memo != null) return memo;
      final cached = await storage.load(lang);
      if (cached != null) {
        _memo[lang] = cached;
        _log.fine('lang catalog from disk lang=$lang');
        return cached;
      }
    }
    final client = clientFactory();
    try {
      final c = await fetcher.fetchCatalog(lang: lang, client: client);
      await storage.save(c, fetchedAt: DateTime.now().toUtc());
      _memo[lang] = c;
      return c;
    } finally {
      client.close();
    }
  }
}
