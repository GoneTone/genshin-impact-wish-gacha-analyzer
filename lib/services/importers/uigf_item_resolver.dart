import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/platform_import.dart';

/// Logger 實例（第三方平台匯入）。
final _log = Logger('wish.import.platform');

/// App 資料語言 → UIGF 字典代碼（`https://api.uigf.org/dict/genshin/{code}.json`）。
const _uigfDictCodes = {
  'zh-tw': 'cht',
  'zh-cn': 'chs',
  'en-us': 'en',
  'ja-jp': 'jp',
  'ko-kr': 'kr',
  'es-es': 'es',
  'fr-fr': 'fr',
  'ru-ru': 'ru',
  'th-th': 'th',
  'vi-vn': 'vi',
  'de-de': 'de',
  'id-id': 'id',
  'pt-pt': 'pt',
};

/// UIGF 沒有字典（實測 403）的資料語言，改用 en-us 字典。
const _noDictLangs = {'tr-tr', 'it-it'};

/// 中文（zh-tw／zh-cn）的星級標籤。
const _zhRanks = {'三星': 3, '四星': 4, '五星': 5};

/// 其他語言的星級標籤（整個標籤完全符合，`N` 為 3～5）：en-us `N-Star`；ja-jp、
/// ko-kr `★N`；es-es、fr-fr、ru-ru、id-id `N★`；it-it `N ★`；th-th `N ดาว`；
/// vi-vn `N sao`；de-de `N Sterne`；pt-pt `N estrelas`；tr-tr `N Yıldızlı`。
final _rankTag = RegExp(
  r'^(?:★([345])|([345])(?:-Star|★| ★| ดาว| sao| Sterne| estrelas| Yıldızlı))$',
);

/// 把單一 HoYoWiki 標籤解析成星級；不是星級標籤回 null。
int? _rankOfTag(String tag) {
  if (_zhRanks[tag] case final rank?) return rank;
  final m = _rankTag.firstMatch(tag);
  return m == null ? null : int.parse(m[1] ?? m[2]!);
}

/// 用 UIGF 字典補名稱、用 HoYoWiki 補星級的 [ItemResolver]。
///
/// 名稱：以 [targetLang] 對應的 UIGF 字典（內容是「名稱 → `item_id`」的扁平物件，
/// 反轉後查）；tr-tr、it-it 沒有字典，改查 en 字典並回傳 `en-us`。
///
/// 星級：HoYoWiki search → entry_page，從 `page.tags`（攤平的 `filter_values`；
/// 角色在 `character_rarity`、武器在 `weapon_rarity`）找星級標籤。2026-11-25 對香菱、
/// 七七、天空之刃、西風劍、冷刃實測 15 種語言，格式只有 [_zhRanks] 與 [_rankTag]
/// 列出的幾種（中文是國字「四星」，不是「4星」）；必須恰好解析出一種星級，否則丟
/// [ItemResolveException]。
///
/// 字典與星級查詢都以 Future 快取在實例內（失敗也會留著），所以每次匯入建一個新實例。
class UigfItemResolver implements ItemResolver {
  /// 建立 [UigfItemResolver]；[targetLang] 是 App 資料語言代碼（如 `zh-tw`）。
  UigfItemResolver({
    required http.Client client,
    required HoYoWikiFetcher hoyowiki,
    required String targetLang,
  }) : _client = client,
       _hoyowiki = hoyowiki,
       _targetLang = targetLang;

  /// 抓字典與 HoYoWiki 用的 HTTP client。
  final http.Client _client;

  /// 查星級用的 HoYoWiki fetcher（字典請求也沿用它的逾時）。
  final HoYoWikiFetcher _hoyowiki;

  /// 補名稱的目標資料語言。
  final String _targetLang;

  /// UIGF 字典代碼 → 反轉後的字典（`item_id` → 名稱）；每個代碼只抓一次。
  final _dicts = <String, Future<Map<String, String>>>{};

  /// （名稱, 語言）→ 星級；同名只查一次。
  final _ranks = <(String, String), Future<int>>{};

  @override
  Future<({String name, String lang})> nameFor(String itemId) async {
    final lang = _noDictLangs.contains(_targetLang) ? 'en-us' : _targetLang;
    final code = _uigfDictCodes[lang];
    if (code == null) {
      _log.warning('uigf dict unsupported lang=$_targetLang item_id=$itemId');
      throw ItemResolveException(
        'No UIGF dictionary for language $_targetLang',
        itemId,
      );
    }
    final dict = await (_dicts[code] ??= _fetchDict(code, itemId));
    final name = dict[itemId];
    if (name == null) {
      _log.warning('uigf dict missing item_id=$itemId code=$code');
      throw ItemResolveException('item_id not in UIGF dictionary', itemId);
    }
    return (name: name, lang: lang);
  }

  /// 抓 [code] 的 UIGF 字典並反轉成 `item_id` → 名稱；任何失敗丟
  /// [ItemResolveException]，`item` 帶觸發請求的 [itemId]。
  Future<Map<String, String>> _fetchDict(String code, String itemId) async {
    final url = Uri.https('api.uigf.org', '/dict/genshin/$code.json');
    _log.info('uigf dict request code=$code');
    final http.Response res;
    try {
      res = await _client.get(url).timeout(_hoyowiki.timeout);
    } catch (e, st) {
      _log.warning('uigf dict request failed code=$code', e, st);
      throw ItemResolveException('UIGF dictionary request failed', itemId);
    }
    if (res.statusCode != 200) {
      _log.warning('uigf dict http status=${res.statusCode} code=$code');
      throw ItemResolveException(
        'UIGF dictionary HTTP ${res.statusCode}',
        itemId,
      );
    }
    try {
      // 實測回應的 content-type 沒有 charset，要自己用 UTF-8 解。
      final json =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final dict = {
        for (final MapEntry(:key, :value) in json.entries)
          '${value as int}': key,
      };
      _log.info(
        'uigf dict loaded code=$code status=200 entries=${dict.length}',
      );
      return dict;
    } catch (e, st) {
      _log.warning('uigf dict malformed code=$code', e, st);
      throw ItemResolveException('UIGF dictionary malformed', itemId);
    }
  }

  @override
  Future<int> rankFor(String name, String lang) =>
      _ranks[(name, lang)] ??= _fetchRank(name, lang);

  /// 走 HoYoWiki search → entry_page 取 [name] 的星級；查無、請求失敗或標籤
  /// 解析不出恰好一種星級時丟 [ItemResolveException]。
  Future<int> _fetchRank(String name, String lang) async {
    final List<String> tags;
    try {
      final hit = await _hoyowiki.searchEntryId(
        name: name,
        lang: lang,
        client: _client,
      );
      if (hit == null) {
        _log.warning('hoyowiki rank lookup: no entry name=$name lang=$lang');
        throw ItemResolveException('Item not found on HoYoWiki', name);
      }
      final entry = await _hoyowiki.fetchEntryPage(
        id: hit.id,
        lang: lang,
        client: _client,
      );
      tags = entry.page.tags;
    } on ItemResolveException {
      rethrow;
    } catch (e, st) {
      _log.warning('hoyowiki rank lookup failed name=$name lang=$lang', e, st);
      throw ItemResolveException('HoYoWiki request failed', name);
    }
    final ranks = tags.map(_rankOfTag).nonNulls.toSet();
    if (ranks.length != 1) {
      _log.warning('hoyowiki rank unparsable name=$name lang=$lang tags=$tags');
      throw ItemResolveException('No single rarity tag on HoYoWiki', name);
    }
    _log.info(
      'hoyowiki rank resolved name=$name lang=$lang rank=${ranks.single}',
    );
    return ranks.single;
  }
}
