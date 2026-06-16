import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

/// 以 HoYoWiki `get_entry_page_list` 抓取某語言的角色／武器全名冊。
class LangCatalogFetcher {
  /// 建立 [LangCatalogFetcher]，可調整分頁大小與逾時。
  LangCatalogFetcher({
    this.pageSize = 50,
    this.timeout = const Duration(seconds: 10),
  });

  /// 每頁筆數。
  final int pageSize;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// list API base URL（與 search 同 host）。
  static final _listBase = Uri.parse(
    'https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/get_entry_page_list',
  );

  /// 要抓的 menu_id：2＝角色、4＝武器。
  static const _menuIds = [2, 4];

  /// 單一 menu 分頁上限（安全閥，避免 API 異常時無限迴圈）。
  static const _maxPages = 50;

  /// 抓 [lang] 的角色＋武器名冊；retcode != 0 throw [ApiErrorException]。
  Future<LangCatalog> fetchCatalog({
    required String lang,
    required http.Client client,
  }) async {
    final byId = <String, ({String name, int kind})>{};
    for (final menuId in _menuIds) {
      var page = 1;
      while (page <= _maxPages) {
        final res = await client
            .post(
              _listBase,
              headers: {
                'Referer': 'https://wiki.hoyolab.com/',
                'X-Rpc-Language': lang,
                'X-Rpc-Wiki_app': 'genshin',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'filters': const [],
                'menu_id': '$menuId',
                'page_num': page,
                'page_size': pageSize,
                'use_es': true,
              }),
            )
            .timeout(timeout);
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final retcode = body['retcode'] as int;
        if (retcode != 0) {
          _log.warning('list retcode=$retcode lang=$lang menu=$menuId');
          throw ApiErrorException(retcode, body['message'] as String? ?? '');
        }
        final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
        for (final raw in list) {
          final m = raw as Map<String, dynamic>;
          final id = m['entry_page_id']?.toString();
          final name = m['name'] as String?;
          if (id == null || id.isEmpty || name == null || name.isEmpty) {
            continue;
          }
          byId[id] = (name: name, kind: menuId);
        }
        if (list.length < pageSize) break;
        page++;
      }
    }
    _log.info('lang catalog fetched lang=$lang items=${byId.length}');
    return LangCatalog.fromEntries(lang, byId);
  }
}
