import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

class WishStats {
  const WishStats({
    required this.total,
    required this.fiveStarCount,
    required this.fourStarCount,
    required this.threeStarOrBelowCount,
    required this.characterCount,
    required this.weaponCount,
    required this.unknownCount,
  });

  final int total;
  final int fiveStarCount;
  final int fourStarCount;
  final int threeStarOrBelowCount;
  final int characterCount;
  final int weaponCount;
  final int unknownCount;

  double _rate(int n) => total == 0 ? 0.0 : n / total;

  double get fiveStarRate => _rate(fiveStarCount);
  double get fourStarRate => _rate(fourStarCount);
  double get threeStarOrBelowRate => _rate(threeStarOrBelowCount);
  double get characterRate => _rate(characterCount);
  double get weaponRate => _rate(weaponCount);
}

WishStats computeWishStats(List<WishRecord> records) {
  var five = 0, four = 0, three = 0;
  var ch = 0, wp = 0, un = 0;
  for (final r in records) {
    switch (r.rankType) {
      case 5:
        five++;
        break;
      case 4:
        four++;
        break;
      default:
        three++;
    }
    switch (r.kind) {
      case WishItemKind.character:
        ch++;
        break;
      case WishItemKind.weapon:
        wp++;
        break;
      case WishItemKind.unknown:
        un++;
    }
  }
  return WishStats(
    total: records.length,
    fiveStarCount: five,
    fourStarCount: four,
    threeStarOrBelowCount: three,
    characterCount: ch,
    weaponCount: wp,
    unknownCount: un,
  );
}
