import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// HoyoWiki entry_page API 抓到的 icon 與 header URL。
class HoyoWikiEntryFetched {
  /// 建立 [HoyoWikiEntryFetched]；URL 均可能為空字串。
  const HoyoWikiEntryFetched({
    required this.iconUrl,
    required this.headerImgUrl,
  });

  /// 物品 icon CDN URL；HoyoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 物品 header CDN URL；HoyoWiki 未上傳時為空字串。
  final String headerImgUrl;
}

/// 與 HoyoLab Wiki API 互動的 fetcher，涵蓋 search / entry_page / image download。
class HoyoWikiFetcher {
  /// 建立 [HoyoWikiFetcher]，可調整速率限制與逾時。
  HoyoWikiFetcher({
    this.rateLimit = const Duration(milliseconds: 600),
    this.timeout = const Duration(seconds: 10),
  });

  /// 兩次 API 呼叫之間的最短間隔（由 caller 透過 `Future.delayed` 控制，
  /// fetcher 本身不主動 delay）。
  final Duration rateLimit;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例（wish.hoyowiki 命名空間，對齊既有 `gacha.fetcher`）。
  static final _log = Logger('wish.hoyowiki');

  /// search API base URL。
  static final _searchBase = Uri.parse(
    'https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/search',
  );

  /// 以 [name] 走 HoyoLab Wiki search API 取得對應的 entry_page_id。
  ///
  /// 命中需同時滿足：`data.list[].name == name` 且
  /// `data.list[].menu.sub_menus[0].id ∈ {2, 4}`。回傳第一筆符合的
  /// `entry_page_id`；若無回 null；retcode != 0 throw [ApiErrorException]。
  Future<String?> searchEntryId({
    required String name,
    required String lang,
    required http.Client client,
  }) async {
    final url = _searchBase.replace(queryParameters: {'keyword': name});
    _log.fine(
      'search name=$name lang=$lang url=${sanitizeUrl(url.toString())}',
    );
    final res = await client
        .get(
          url,
          headers: {
            'Referer': 'https://wiki.hoyolab.com/',
            'X-Rpc-Language': lang,
            'X-Rpc-Wiki_app': 'genshin',
          },
        )
        .timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode != 0) {
      _log.warning(
        'search retcode=$retcode name=$name lang=$lang msg=${body['message']}',
      );
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
    final list = (body['data']?['list'] as List<dynamic>?) ?? const [];
    for (final raw in list) {
      final item = raw as Map<String, dynamic>;
      if (item['name'] != name) continue;
      final menu = item['menu'] as Map<String, dynamic>?;
      final subMenus = menu?['sub_menus'] as List<dynamic>?;
      if (subMenus == null || subMenus.isEmpty) continue;
      final subMenuId = (subMenus.first as Map<String, dynamic>)['id'] as int?;
      if (subMenuId != 2 && subMenuId != 4) continue;
      final id = item['entry_page_id'] as String?;
      if (id == null || id.isEmpty) continue;
      _log.info('search hit name=$name lang=$lang id=$id');
      return id;
    }
    _log.warning('search miss name=$name lang=$lang');
    return null;
  }
}
