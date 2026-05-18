import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

class GachaStats {
  const GachaStats({
    required this.total,
    required this.fiveStarCount,
    required this.fourStarCount,
    required this.threeStarCount,
    required this.twoStarCount,
    required this.byItemType,
  });

  final int total;
  final int fiveStarCount;
  final int fourStarCount;
  final int threeStarCount;
  final int twoStarCount;
  final Map<String, int> byItemType;

  double _rate(int n) => total == 0 ? 0.0 : n / total;

  double get fiveStarRate => _rate(fiveStarCount);
  double get fourStarRate => _rate(fourStarCount);
  double get threeStarRate => _rate(threeStarCount);
  double get twoStarRate => _rate(twoStarCount);

  /// 依 count desc 排序的 entries（給 pie / legend 用）。
  List<MapEntry<String, int>> sortedItemTypes() {
    final list = byItemType.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

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
