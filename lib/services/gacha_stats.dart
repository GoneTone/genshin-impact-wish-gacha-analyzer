import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

/// 單一卡池的祈願統計摘要。
class GachaStats {
  const GachaStats({
    required this.total,
    required this.fiveStarCount,
    required this.fourStarCount,
    required this.threeStarCount,
    required this.twoStarCount,
    required this.byItemType,
  });

  /// 總抽數。
  final int total;

  /// 5★ 數量。
  final int fiveStarCount;

  /// 4★ 數量。
  final int fourStarCount;

  /// 3★ 數量。
  final int threeStarCount;

  /// 2★ 數量。
  final int twoStarCount;

  /// 各物品類型的抽數，key = itemType 字串。
  final Map<String, int> byItemType;

  /// 計算 [n] 在總抽數中的占比；總抽數為 0 時回傳 0.0。
  double _rate(int n) => total == 0 ? 0.0 : n / total;

  /// 5★ 出率。
  double get fiveStarRate => _rate(fiveStarCount);

  /// 4★ 出率。
  double get fourStarRate => _rate(fourStarCount);

  /// 3★ 出率。
  double get threeStarRate => _rate(threeStarCount);

  /// 2★ 出率。
  double get twoStarRate => _rate(twoStarCount);

  /// 依 count desc 排序的 entries（給 pie / legend 用）。
  List<MapEntry<String, int>> sortedItemTypes() {
    final list = byItemType.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

/// 從 [records] 計算統計摘要。
GachaStats computeGachaStats(List<GachaRecord> records) {
  var five = 0, four = 0, three = 0, two = 0;
  final byItemType = <String, int>{};
  for (final r in records) {
    switch (r.rankType) {
      case 5:
        five++;
      case 4:
        four++;
      case 3:
        three++;
      case 2:
        two++;
    }
    byItemType[r.itemType] = (byItemType[r.itemType] ?? 0) + 1;
  }
  return GachaStats(
    total: records.length,
    fiveStarCount: five,
    fourStarCount: four,
    threeStarCount: three,
    twoStarCount: two,
    byItemType: byItemType,
  );
}
