import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_fetcher.dart'
    show ApiErrorException;
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// HoYoWiki search API 的命中結果。
class HoYoWikiSearchHit {
  /// 建立 [HoYoWikiSearchHit]。
  const HoYoWikiSearchHit({required this.id, required this.menuId});

  /// entry_page_id。
  final String id;

  /// 物品 menu_id（2＝角色，4＝武器）。
  final int menuId;
}

/// HoYoWiki entry_page API 抓到的 icon URL 與該 lang 的整組 page 資料。
class HoYoWikiEntryFetched {
  /// 建立 [HoYoWikiEntryFetched]；icon 可能為空字串；`page.gallery` 可能為
  /// null（entry 無 `gallery_character` module），`page.desc` / `page.tags`
  /// 可能為空。
  const HoYoWikiEntryFetched({required this.iconUrl, required this.page});

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 該 lang 的整組 page 資料（gallery + desc + tags）。
  final HoYoWikiPageData page;
}

/// 與 HoYoLab Wiki API 互動的 fetcher，涵蓋 search / entry_page / image download。
class HoYoWikiFetcher {
  /// 建立 [HoYoWikiFetcher]，可調整各階段並行度與逾時。
  HoYoWikiFetcher({
    this.searchConcurrency = 8,
    this.entryConcurrency = 8,
    this.downloadConcurrency = 8,
    this.timeout = const Duration(seconds: 10),
  });

  /// search 階段 worker-pool 同時 in-flight 上限。
  final int searchConcurrency;

  /// entry_page 階段 worker-pool 同時 in-flight 上限。
  final int entryConcurrency;

  /// download 階段 worker-pool 同時 in-flight 上限。
  final int downloadConcurrency;

  /// 單次 HTTP 請求超時。
  final Duration timeout;

  /// Logger 實例（gacha.hoyowiki 命名空間，對齊既有 `gacha.fetcher`）。
  static final _log = Logger('gacha.hoyowiki');

  /// search API base URL。
  static final _searchBase = Uri.parse(
    'https://sg-act-public-api.hoyolab.com/hoyowiki/genshin/wapi/search',
  );

  /// entry_page API base URL（static 端點，不需 headers）。
  static final _entryBase = Uri.parse(
    'https://sg-act-public-api-static.hoyolab.com/hoyowiki/genshin/wapi/entry_page',
  );

  /// 以 [name] 走 HoYoLab Wiki search API 取得對應的 entry_page_id 與 menu_id。
  ///
  /// 命中需同時滿足：`data.list[].name == name` 且
  /// `data.list[].menu.sub_menus[0].id ∈ {2, 4}`。回傳第一筆符合的
  /// [HoYoWikiSearchHit]（含 id 與 menuId）；若無回 null；
  /// retcode != 0 throw [ApiErrorException]。
  Future<HoYoWikiSearchHit?> searchEntryId({
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
      final subMenuIdRaw = (subMenus.first as Map<String, dynamic>)['id'];
      final subMenuId = subMenuIdRaw is int
          ? subMenuIdRaw
          : subMenuIdRaw is String
          ? int.tryParse(subMenuIdRaw)
          : null;
      if (subMenuId == null || (subMenuId != 2 && subMenuId != 4)) continue;
      final entryRaw = item['entry_page_id'];
      final id = entryRaw is String ? entryRaw : entryRaw?.toString();
      if (id == null || id.isEmpty) continue;
      _log.info('search hit name=$name lang=$lang id=$id menuId=$subMenuId');
      return HoYoWikiSearchHit(id: id, menuId: subMenuId);
    }
    _log.warning('search miss name=$name lang=$lang');
    return null;
  }

  /// 從 entry_page response 的 `data.page.filter_values` 攤平所有 group 的
  /// `values[]`，保留首次出現順序去重後回傳。例：
  ///
  ///   {character_property: {values: ['生命之契']},
  ///    character_rarity: {values: ['4星']},
  ///    character_region: {values: ['蒙德']}}
  ///   → ['生命之契', '4星', '蒙德']
  ///
  /// Map 遍歷順序：Dart `Map` 保證 insertion order，`jsonDecode` 回傳的是
  /// `LinkedHashMap`，所以「filter_values 出現順序」對同一份 JSON 穩定。
  static List<String> _parseTags(Object? filterValues) {
    if (filterValues is! Map) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final v in filterValues.values) {
      if (v is! Map) continue;
      final values = v['values'];
      if (values is! List) continue;
      for (final s in values) {
        if (s is! String) continue;
        final t = s.trim();
        if (t.isEmpty) continue;
        if (seen.add(t)) out.add(t);
      }
    }
    return List.unmodifiable(out);
  }

  /// 測試用：暴露 [_parseTags] 給單元測試。生產勿用。
  @visibleForTesting
  static List<String> parseTagsDebug(Object? filterValues) =>
      _parseTags(filterValues);

  /// 從 entry_page response 的 `modules[]` 找出 `gallery_character`
  /// component 並 JSON 解析其 `data` 字串。失敗或空回 null。
  static HoYoWikiGalleryData? _parseGalleryCharacterModule(
    List<dynamic> modules,
  ) {
    for (final m in modules) {
      final components =
          (m as Map<String, dynamic>)['components'] as List<dynamic>?;
      if (components == null) continue;
      for (final c in components) {
        final comp = c as Map<String, dynamic>;
        if (comp['component_id'] != 'gallery_character') continue;
        final dataStr = comp['data'] as String?;
        if (dataStr == null || dataStr.isEmpty) return null;
        try {
          final data = jsonDecode(dataStr) as Map<String, dynamic>;
          final picUrl = (data['pic'] as String?) ?? '';
          final listJson = (data['list'] as List<dynamic>?) ?? const [];
          final list = <HoYoWikiGalleryItem>[];
          for (final item in listJson) {
            final mi = item as Map<String, dynamic>;
            final gid = mi['id'] as String?;
            final key = mi['key'] as String?;
            final img = mi['img'] as String?;
            if (gid == null ||
                gid.isEmpty ||
                key == null ||
                key.isEmpty ||
                img == null ||
                img.isEmpty) {
              _log.warning(
                'gallery item missing fields id=$gid key=$key imgEmpty=${img == null || img.isEmpty}',
              );
              continue;
            }
            list.add(
              HoYoWikiGalleryItem(
                id: gid,
                key: key,
                imgUrl: img,
                imgDescHtml: (mi['imgDesc'] as String?) ?? '',
              ),
            );
          }
          if (picUrl.isEmpty && list.isEmpty) return null;
          return HoYoWikiGalleryData(picUrl: picUrl, list: list);
        } catch (e, st) {
          _log.warning('gallery data parse failed', e, st);
          return null;
        }
      }
    }
    return null;
  }

  /// 以 [id] 與 [lang] 拉 entry_page，回 icon_url 與該 lang 的 gallery 整組。
  /// 必送 `X-Rpc-Language: $lang` header 以拿到對應語言的 gallery 文字。
  /// retcode != 0 throw [ApiErrorException]。
  Future<HoYoWikiEntryFetched> fetchEntryPage({
    required String id,
    required String lang,
    required http.Client client,
  }) async {
    final url = _entryBase.replace(queryParameters: {'entry_page_id': id});
    _log.fine('entry id=$id lang=$lang url=${sanitizeUrl(url.toString())}');
    final res = await client
        .get(url, headers: {'X-Rpc-Language': lang})
        .timeout(timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final retcode = body['retcode'] as int;
    if (retcode != 0) {
      _log.warning(
        'entry retcode=$retcode id=$id lang=$lang msg=${body['message']}',
      );
      throw ApiErrorException(retcode, body['message'] as String? ?? '');
    }
    final page = body['data']?['page'] as Map<String, dynamic>?;
    final iconUrl = (page?['icon_url'] as String?) ?? '';
    final modules = (page?['modules'] as List<dynamic>?) ?? const [];
    final gallery = _parseGalleryCharacterModule(modules);
    final descRaw = page?['desc'];
    final desc = descRaw is String ? descRaw : '';
    final tags = _parseTags(page?['filter_values']);
    _log.info(
      'entry id=$id lang=$lang icon=${iconUrl.isNotEmpty} '
      'gallery=${gallery != null} '
      'pic=${gallery?.picUrl.isNotEmpty == true} '
      'list=${gallery?.list.length ?? 0} '
      'desc=${desc.isNotEmpty} tags=${tags.length}',
    );
    return HoYoWikiEntryFetched(
      iconUrl: iconUrl,
      page: HoYoWikiPageData(gallery: gallery, desc: desc, tags: tags),
    );
  }

  /// GET [url] 的圖檔 bytes；任何失敗（非 2xx / 例外）回 null，caller 不寫檔
  /// 並於下次更新重試。
  Future<Uint8List?> downloadImage(String url, http.Client client) async {
    try {
      final res = await client.get(Uri.parse(url)).timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return res.bodyBytes;
      }
      _log.warning(
        'download non-2xx status=${res.statusCode} url=${sanitizeUrl(url)}',
      );
      return null;
    } catch (e) {
      _log.warning('download failed url=${sanitizeUrl(url)} err=$e');
      return null;
    }
  }
}
