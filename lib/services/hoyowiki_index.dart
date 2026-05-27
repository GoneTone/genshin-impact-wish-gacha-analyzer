import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:logging/logging.dart';

/// HoYoWiki entry_page API 抓到的 icon URL 與各語言整組 page 資料。
class HoYoWikiEntry {
  /// 建立 [HoYoWikiEntry]；`iconUrl` 可能為空字串。
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.pageByLang,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。lang-agnostic。
  final String iconUrl;

  /// 各語言整組 page 資料；key 為 `record.lang`（zh-tw / en / ja / ...）。
  /// 某 lang 不在 map 內 = 該 lang 還沒抓過。`gallery` 可能為 null（entry 無
  /// `gallery_character` module，如武器頁），但 `desc` / `tags` 仍可能有值。
  final Map<String, HoYoWikiPageData> pageByLang;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}

/// 單一 lang 的整組 gallery（pic 卡片 + list 圖文），對應 HoYoWiki entry_page
/// `gallery_character` component 解出的內容。
class HoYoWikiGalleryData {
  /// 建立 [HoYoWikiGalleryData]。
  const HoYoWikiGalleryData({required this.picUrl, required this.list});

  /// 卡片大圖 URL；可能為空字串（API 未提供）。
  final String picUrl;

  /// gallery 內所有圖片條目，依 API 順序。
  final List<HoYoWikiGalleryItem> list;
}

/// gallery 內單一圖片條目（對應 list[i]）。
class HoYoWikiGalleryItem {
  /// 建立 [HoYoWikiGalleryItem]。
  const HoYoWikiGalleryItem({
    required this.id,
    required this.key,
    required this.imgUrl,
    required this.imgDescHtml,
  });

  /// HoYoWiki 給的條目 ID（如 `gallery_character8511`）。
  final String id;

  /// chip 顯示標籤（lang-specific，如「原畫」／「閒置動作１」）。
  final String key;

  /// 圖片 URL（png/jpg/webp/gif；跨 lang 可能不同）。
  final String imgUrl;

  /// 圖片描述（HTML，含 `<p>` 段落；可能為空字串）。
  final String imgDescHtml;
}

/// 某一個 lang 抓到的整組 entry_page 資料（gallery + desc + tags）。
/// 三個欄位永遠來自同一次 entry_page API 呼叫，原子性寫入。
class HoYoWikiPageData {
  /// 建立 [HoYoWikiPageData]。
  const HoYoWikiPageData({
    required this.gallery,
    required this.desc,
    required this.tags,
  });

  /// 該 lang 的 gallery_character 整組（pic + list）；entry 無
  /// `gallery_character` module 時為 null（例：武器頁）。
  final HoYoWikiGalleryData? gallery;

  /// 該 lang 的 `data.page.desc`；可能為純文字或含 HTML，可能為空字串。
  final String desc;

  /// 該 lang 的 `data.page.filter_values.*.values[]` 全部攤平後去重、保留
  /// 首次出現順序的 tag list；可能為空 list。
  final List<String> tags;
}

/// 跨 UID 共用的 HoYoWiki lookup index。
class HoYoWikiIndex {
  /// 建立 [HoYoWikiIndex]。
  const HoYoWikiIndex({
    required this.searchMap,
    required this.entries,
    required this.menuIds,
  });

  /// 建立空 index（無任何 search / entry）。
  const HoYoWikiIndex.empty()
    : searchMap = const {},
      entries = const {},
      menuIds = const {};

  /// `"<lang>::<name>"` → `hoyowiki_id`；只記錄成功命中的。
  final Map<String, String> searchMap;

  /// `hoyowiki_id` → [HoYoWikiEntry]；URL 可能為空字串。
  final Map<String, HoYoWikiEntry> entries;

  /// `hoyowiki_id` → `menu_id`（2＝角色，4＝武器）；search API 命中時寫入。
  final Map<String, int> menuIds;

  /// 以 [name] + [lang] 查 hoyowiki_id；查無回 null。
  String? lookupId({required String name, required String lang}) =>
      searchMap['$lang::$name'];

  /// 以 [id] 查 entry；查無回 null。
  HoYoWikiEntry? lookupEntry(String id) => entries[id];

  /// 以 [id] 查 menu_id；查無回 null。
  int? lookupMenuId(String id) => menuIds[id];
}

/// 負責 `hoyowiki_index.json` 的讀寫（atomic write，跨 UID 共用）。
class HoYoWikiIndexStorage {
  /// 建立 [HoYoWikiIndexStorage]，需指定資料根目錄 [baseDir]（通常與
  /// `gachaStorageProvider` 共用 `<appSupport>/gacha_data/`）。
  HoYoWikiIndexStorage(this.baseDir);

  /// Logger 實例（hoyowiki 儲存）。
  static final _log = Logger('gacha.hoyowiki.storage');

  /// 資料根目錄。
  final Directory baseDir;

  /// index 檔路徑。
  File get _file => File('${baseDir.path}/hoyowiki_index.json');

  /// 讀取 index；檔案不存在或解析失敗回空 index。
  Future<HoYoWikiIndex> load() async {
    final f = _file;
    if (!await f.exists()) return const HoYoWikiIndex.empty();
    try {
      final text = await f.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      final version = json['version'] as int? ?? 1;
      final searchJson = (json['search'] as Map<String, dynamic>?) ?? const {};
      final entriesJson =
          (json['entries'] as Map<String, dynamic>?) ?? const {};
      final menuIdsJson =
          (json['menu_ids'] as Map<String, dynamic>?) ?? const {};

      final isV3 = version >= 3;
      var droppedLegacy = 0;
      final entries = entriesJson.map((k, v) {
        final m = v as Map<String, dynamic>;
        final iconUrl = (m['icon_url'] as String?) ?? '';
        final fetchedAt = DateTime.parse(m['fetched_at'] as String);
        Map<String, HoYoWikiPageData> pageByLang;
        if (isV3 && m['page_by_lang'] is Map) {
          final pJson = m['page_by_lang'] as Map<String, dynamic>;
          pageByLang = pJson.map((lang, raw) {
            final pm = raw as Map<String, dynamic>;
            HoYoWikiGalleryData? gallery;
            final gJson = pm['gallery'];
            if (gJson is Map) {
              final listJson = (gJson['list'] as List<dynamic>?) ?? const [];
              gallery = HoYoWikiGalleryData(
                picUrl: (gJson['pic_url'] as String?) ?? '',
                list: listJson
                    .map((e) {
                      final em = e as Map<String, dynamic>;
                      return HoYoWikiGalleryItem(
                        id: (em['id'] as String?) ?? '',
                        key: (em['key'] as String?) ?? '',
                        imgUrl: (em['img_url'] as String?) ?? '',
                        imgDescHtml: (em['img_desc_html'] as String?) ?? '',
                      );
                    })
                    .toList(growable: false),
              );
            }
            final tagsJson = (pm['tags'] as List<dynamic>?) ?? const [];
            return MapEntry(
              lang,
              HoYoWikiPageData(
                gallery: gallery,
                desc: (pm['desc'] as String?) ?? '',
                tags: tagsJson.whereType<String>().toList(growable: false),
              ),
            );
          });
        } else {
          // v1（header）／ v2（gallery_by_lang）→ v3：reset page_by_lang，
          // 下次 update 由 needRefetchEntry 觸發 per-lang 重抓補齊。
          pageByLang = const {};
          droppedLegacy++;
        }
        return MapEntry(
          k,
          HoYoWikiEntry(
            iconUrl: iconUrl,
            pageByLang: pageByLang,
            fetchedAt: fetchedAt,
          ),
        );
      });

      if (!isV3 && droppedLegacy > 0) {
        final droppedField = version == 1
            ? 'header_img_url'
            : 'gallery_by_lang';
        _log.info(
          'migrate v$version → v3: $droppedLegacy entries reset '
          '($droppedField dropped)',
        );
      }

      return HoYoWikiIndex(
        searchMap: searchJson.map((k, v) => MapEntry(k, v as String)),
        entries: entries,
        menuIds: menuIdsJson.map((k, v) => MapEntry(k, v as int)),
      );
    } catch (e, st) {
      _log.warning('load failed, return empty index', e, st);
      return const HoYoWikiIndex.empty();
    }
  }

  /// 將 [index] 寫回磁碟（atomic rename）。
  Future<void> save(HoYoWikiIndex index) async {
    final json = {
      'version': 3,
      'search': index.searchMap,
      'entries': index.entries.map(
        (k, v) => MapEntry(k, {
          'icon_url': v.iconUrl,
          'fetched_at': v.fetchedAt.toUtc().toIso8601String(),
          'page_by_lang': v.pageByLang.map(
            (lang, p) => MapEntry(lang, {
              if (p.gallery != null)
                'gallery': {
                  'pic_url': p.gallery!.picUrl,
                  'list': p.gallery!.list
                      .map(
                        (it) => {
                          'id': it.id,
                          'key': it.key,
                          'img_url': it.imgUrl,
                          'img_desc_html': it.imgDescHtml,
                        },
                      )
                      .toList(),
                },
              'desc': p.desc,
              'tags': p.tags,
            }),
          ),
        }),
      ),
      'menu_ids': index.menuIds,
    };
    await baseDir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(_file.path);
    _log.fine(
      'saved search=${index.searchMap.length} '
      'entries=${index.entries.length} '
      'menuIds=${index.menuIds.length}',
    );
  }

  /// 將 index 重設為空（searchMap / entries / menuIds 全空），用於「強制重抓
  /// 所有物品圖片」操作。覆寫策略與 [save] 相同（atomic rename），原檔不存在
  /// 時直接寫入空殼。
  Future<void> clearAll() async {
    await save(const HoYoWikiIndex.empty());
    _log.info('clearAll: index reset to empty');
  }

  /// 刪除 [baseDir] 內所有 `*_gallery_*` 圖檔。Icon 檔與 `hoyowiki_index.json`
  /// 保留 — gallery URL metadata 仍在 index，下次打開物品詳情可 lazy 重抓。
  /// 目錄不存在直接 no-op。失敗（權限被鎖等）會 rethrow,此時已刪除的檔案不會
  /// 復原（per-file 操作,失敗點之前已成功的留下、之後的未嘗試）。
  Future<void> deleteGalleryCacheFiles() async {
    if (!await baseDir.exists()) {
      _log.fine('deleteGalleryCacheFiles: dir not exist, no-op');
      return;
    }
    final candidates = await baseDir
        .list()
        .where((e) => e is File && e.path.contains('_gallery_'))
        .cast<File>()
        .toList();
    var deleted = 0;
    for (final file in candidates) {
      try {
        await file.delete();
        deleted++;
      } catch (e, st) {
        _log.warning(
          'deleteGalleryCacheFiles: delete failed path=${sanitizeFsPath(file.path)}',
          e,
          st,
        );
        rethrow;
      }
    }
    _log.info('deleteGalleryCacheFiles: removed $deleted gallery file(s)');
  }

  /// 刪除 [baseDir] 內所有 HoYoWiki cache 圖檔並重建空目錄。
  /// 目錄不存在時直接建立；失敗（權限被鎖等）直接拋給呼叫方處理。
  Future<void> wipeCacheDirectory() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
    await baseDir.create(recursive: true);
    _log.info(
      'wipeCacheDirectory: cache cleared at ${sanitizeFsPath(baseDir.path)}',
    );
  }
}

/// 推導 icon 的 cache 路徑：`<id>_icon.<ext>`。
File hoyowikiIconCacheFile({
  required Directory baseDir,
  required String id,
  required String url,
}) {
  return File('${baseDir.path}/${id}_icon.${_extFromUrl(url)}');
}

/// 推導 gallery 圖片（pic 或 list[].img）的 cache 路徑：
/// `<id>_gallery_<sha1Hex前12碼>.<ext>`。同 URL 自然同檔，跨 lang 同 URL 共用。
File hoyowikiGalleryCacheFile({
  required Directory baseDir,
  required String id,
  required String url,
}) {
  final hash = sha1.convert(utf8.encode(url)).toString().substring(0, 12);
  return File('${baseDir.path}/${id}_gallery_$hash.${_extFromUrl(url)}');
}

/// 從 [url] 推導副檔名（無則回 `png`）。
String _extFromUrl(String url) {
  if (url.isEmpty) return 'png';
  final qIdx = url.indexOf('?');
  final clean = qIdx >= 0 ? url.substring(0, qIdx) : url;
  final dotIdx = clean.lastIndexOf('.');
  final slashIdx = clean.lastIndexOf('/');
  if (dotIdx <= slashIdx || dotIdx == clean.length - 1) return 'png';
  final ext = clean.substring(dotIdx + 1).toLowerCase();
  // 安全檢查：副檔名只能是常見 image 格式，避免 URL 怪異字串污染檔名。
  const allowed = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
  return allowed.contains(ext) ? ext : 'png';
}
