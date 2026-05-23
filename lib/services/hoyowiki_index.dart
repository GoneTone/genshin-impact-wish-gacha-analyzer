/// HoyoWiki entry_page API 抓到的 icon 與 header 大圖 URL，以及抓取時間。
class HoyoWikiEntry {
  /// 建立 [HoyoWikiEntry]；兩個 URL 均可能為空字串。
  const HoyoWikiEntry({
    required this.iconUrl,
    required this.headerImgUrl,
    required this.fetchedAt,
  });

  /// 物品 icon CDN URL；HoyoWiki 未上傳時為空字串。
  final String iconUrl;

  /// 物品 header（banner）CDN URL；HoyoWiki 未上傳時為空字串。
  final String headerImgUrl;

  /// 抓取時間（僅供 debug，不參與邏輯）。
  final DateTime fetchedAt;
}

/// 跨 UID 共用的 HoyoWiki lookup index。
class HoyoWikiIndex {
  /// 建立 [HoyoWikiIndex]。
  const HoyoWikiIndex({required this.searchMap, required this.entries});

  /// 建立空 index（無任何 search / entry）。
  const HoyoWikiIndex.empty() : searchMap = const {}, entries = const {};

  /// `"<lang>::<name>"` → `hoyowiki_id`；只記錄成功命中的。
  final Map<String, String> searchMap;

  /// `hoyowiki_id` → [HoyoWikiEntry]；URL 可能為空字串。
  final Map<String, HoyoWikiEntry> entries;

  /// 以 [name] + [lang] 查 hoyowiki_id；查無回 null。
  String? lookupId({required String name, required String lang}) =>
      searchMap['$lang::$name'];

  /// 以 [id] 查 entry；查無回 null。
  HoyoWikiEntry? lookupEntry(String id) => entries[id];
}
