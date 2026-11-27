import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';

/// 比對 `/banner/:type` 路由並擷取卡池 key。
final RegExp _bannerPathPattern = RegExp(r'^/banner/([^/]+)$');

/// 判斷路由 [path] 的頁面是否有內容可放原生廣告；資料未就緒、無記錄或未知路由時回傳 false。
bool pageHasAdContent({required String path, required GachaState gacha}) {
  if (gacha.isBootstrapping) return false;
  final data = gacha.activeData;
  if (data == null) return false;
  if (path == '/') {
    return data.banners.values.any((records) => records.isNotEmpty);
  }
  final match = _bannerPathPattern.firstMatch(path);
  if (match != null) {
    return (data.banners[match.group(1)!] ?? const []).isNotEmpty;
  }
  return false;
}

/// 判斷總覽頁 [category] 分區是否有記錄可放原生廣告；分區條件與 `buildOverviewSections` 一致。
bool overviewSectionHasAdContent({
  required GachaCategory category,
  required GachaState gacha,
}) {
  if (gacha.isBootstrapping) return false;
  final data = gacha.activeData;
  if (data == null) return false;
  return gachaTypes
      .where((t) => t.category == category)
      .any((t) => (data.banners[t.gachaType] ?? const []).isNotEmpty);
}
