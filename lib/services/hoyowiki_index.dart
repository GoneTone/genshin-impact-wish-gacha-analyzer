import 'dart:convert';
import 'dart:io';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:logging/logging.dart';

/// HoYoWiki entry_page API 抓到的 icon 與 header 大圖 URL，以及抓取時間。
class HoYoWikiEntry {
  /// 建立 [HoYoWikiEntry]；兩個 URL 均可能為空字串。
  const HoYoWikiEntry({
    required this.iconUrl,
    required this.headerImgUrl,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoYoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 物品 header（banner）CDN URL；HoYoWiki 未上傳時為空字串。
  final String headerImgUrl;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
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
      final searchJson = (json['search'] as Map<String, dynamic>?) ?? const {};
      final entriesJson =
          (json['entries'] as Map<String, dynamic>?) ?? const {};
      // 向後相容：舊 JSON 缺 menu_ids 欄位時回空 map。
      final menuIdsJson =
          (json['menu_ids'] as Map<String, dynamic>?) ?? const {};
      return HoYoWikiIndex(
        searchMap: searchJson.map((k, v) => MapEntry(k, v as String)),
        entries: entriesJson.map((k, v) {
          final m = v as Map<String, dynamic>;
          return MapEntry(
            k,
            HoYoWikiEntry(
              iconUrl: (m['icon_url'] as String?) ?? '',
              headerImgUrl: (m['header_img_url'] as String?) ?? '',
              fetchedAt: DateTime.parse(m['fetched_at'] as String),
            ),
          );
        }),
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
      'version': 1,
      'search': index.searchMap,
      'entries': index.entries.map(
        (k, v) => MapEntry(k, {
          'icon_url': v.iconUrl,
          'header_img_url': v.headerImgUrl,
          'fetched_at': v.fetchedAt.toUtc().toIso8601String(),
        }),
      ),
      'menu_ids': index.menuIds,
    };
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

/// HoYoWiki 圖片種類（對應 icon_url 與 header_img_url）。
enum HoYoWikiImageKind {
  /// 物品方形 icon。
  icon,

  /// 物品 header（banner 大圖）。
  header,
}

/// 推導出 hoyowiki 圖檔在 [baseDir] 的快取路徑。
///
/// 檔名格式：`<id>_<kind>.<ext>`。`<ext>` 從 [url] 解析（去掉 query 後取
/// 最後一個 `.` 之後）；無副檔名或 URL 為空字串時 default `png`。
File hoyowikiCacheFile({
  required Directory baseDir,
  required String id,
  required HoYoWikiImageKind kind,
  required String url,
}) {
  final ext = _extFromUrl(url);
  return File('${baseDir.path}/${id}_${kind.name}.$ext');
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
