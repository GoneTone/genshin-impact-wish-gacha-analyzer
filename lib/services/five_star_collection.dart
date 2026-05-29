import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// 五星一覽聚合的 logger。
final _log = Logger('gacha.fiveStar');

/// 五星一覽的單一條目：一個不重複的五星物品 + 其累計抽到次數。
@immutable
class FiveStarCollectionItem {
  /// 建立 [FiveStarCollectionItem]。
  const FiveStarCollectionItem({
    required this.representative,
    required this.count,
  });

  /// 該物品最近一次被抽到的紀錄；決定 icon 查找與 tooltip 顯示名稱。
  final GachaRecord representative;

  /// 該物品（同合併鍵）在來源中被抽到的總次數。
  final int count;
}

/// 內部累積桶：記住該合併鍵目前的代表 record（最近一次）與出現次數。
class _Bucket {
  /// 以首次遇到的 record 初始化，count 由呼叫端累加。
  _Bucket(this.representative) : count = 0;

  /// 目前該合併鍵最近一次的 record。
  GachaRecord representative;

  /// 出現次數。
  int count;
}

/// 計算合併鍵：優先用 HoYoWiki id（可跨語系合併），lookup miss 時退化以名稱為鍵。
String _mergeKey(GachaRecord r, HoYoWikiIndex index) =>
    index.lookupId(name: r.name, lang: r.lang) ?? r.name;

/// 由單一 records 來源建構五星一覽：取 5★，依合併鍵去重計數，
/// 依「次數降冪 → 最近抽到時間降冪」排序。
List<FiveStarCollectionItem> buildFiveStarCollection(
  List<GachaRecord> records, {
  required HoYoWikiIndex index,
}) {
  final buckets = <String, _Bucket>{};
  for (final r in records) {
    if (r.rankType != 5) continue;
    final b = buckets.putIfAbsent(_mergeKey(r, index), () => _Bucket(r));
    b.count++;
    if (r.time.isAfter(b.representative.time)) {
      b.representative = r;
    }
  }
  final items = buckets.values
      .map(
        (b) => FiveStarCollectionItem(
          representative: b.representative,
          count: b.count,
        ),
      )
      .toList();
  items.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return b.representative.time.compareTo(a.representative.time);
  });
  _log.info(
    'buildFiveStarCollection: ${items.length} unique five-star item(s)',
  );
  return items;
}

/// 跨卡池版：攤平所有卡池 records 後委派給 [buildFiveStarCollection]，
/// 同合併鍵跨卡池累加。
List<FiveStarCollectionItem> buildFiveStarCollectionAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required HoYoWikiIndex index,
}) {
  final all = banners.values.expand((r) => r).toList(growable: false);
  return buildFiveStarCollection(all, index: index);
}
