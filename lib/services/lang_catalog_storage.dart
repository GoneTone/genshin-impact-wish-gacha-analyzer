import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// 單一語言的物品名冊：`id → {name, kind}`（kind = HoYoWiki menu_id，2＝角色、
/// 4＝武器），附 `name → id` 反查表（同名多 id 者剔除以免誤判）。
class LangCatalog {
  /// 建立 [LangCatalog]。
  const LangCatalog({
    required this.lang,
    required this.byId,
    required this.idByName,
  });

  /// 此名冊的語言代碼。
  final String lang;

  /// `hoyowiki_id → {name, kind}`。
  final Map<String, ({String name, int kind})> byId;

  /// `name → id`；由 [byId] 推導，歧義（同名對多 id）者剔除。
  final Map<String, String> idByName;

  /// 由 [byId] 建構並推導 [idByName]（同名多 id 剔除）。
  factory LangCatalog.fromEntries(
    String lang,
    Map<String, ({String name, int kind})> byId,
  ) {
    final nameToIds = <String, Set<String>>{};
    byId.forEach((id, e) => nameToIds.putIfAbsent(e.name, () => {}).add(id));
    final idByName = <String, String>{};
    nameToIds.forEach((name, ids) {
      if (ids.length == 1) idByName[name] = ids.first;
    });
    return LangCatalog(lang: lang, byId: byId, idByName: idByName);
  }
}

/// 負責 `lang_catalog/<lang>.json` 的原子化讀寫。
class LangCatalogStorage {
  /// 建立 [LangCatalogStorage]，需指定資料根目錄 [baseDir]
  /// （通常為 `<hoyowikiCacheDir>/lang_catalog`）。
  LangCatalogStorage(this.baseDir);

  /// Logger 實例。
  static final _log = Logger('wish.langconvert.catalog');

  /// 資料根目錄。
  final Directory baseDir;

  /// 回傳 [lang] 對應的名冊檔。
  File _file(String lang) => File('${baseDir.path}/$lang.json');

  /// 讀取 [lang] 名冊；不存在或解析失敗回 null（後者 log warning 視為缺檔重抓）。
  Future<LangCatalog?> load(String lang) async {
    final f = _file(lang);
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final items = json['items'] as Map<String, dynamic>;
      final byId = items.map((id, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(id, (
          name: m['name'] as String,
          kind: m['kind'] as int,
        ));
      });
      return LangCatalog.fromEntries(lang, byId);
    } catch (e, st) {
      _log.warning('lang catalog load failed lang=$lang', e, st);
      return null;
    }
  }

  /// 原子化寫入 [c]；[fetchedAt] 記錄抓取時間。
  Future<void> save(LangCatalog c, {required DateTime fetchedAt}) async {
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    final json = {
      'lang': c.lang,
      'fetched_at': fetchedAt.toUtc().toIso8601String(),
      'items': {
        for (final e in c.byId.entries)
          e.key: {'name': e.value.name, 'kind': e.value.kind},
      },
    };
    final target = _file(c.lang);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(target.path);
  }
}
