import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';

WishRecord _r({
  required String id,
  required int rank,
  required WishItemKind kind,
}) => WishRecord(
  id: id,
  uid: '1',
  gachaType: '301',
  name: 'x',
  itemType: kind == WishItemKind.character ? '角色' : '武器',
  kind: kind,
  rankType: rank,
  time: DateTime(2025),
  lang: 'zh-tw',
);

void main() {
  group('WishStats', () {
    test('空 list 全 0', () {
      final s = computeWishStats(const []);
      expect(s.total, 0);
      expect(s.fiveStarCount, 0);
      expect(s.characterCount, 0);
      expect(s.fiveStarRate, 0.0);
    });

    test('混合 list 計數正確', () {
      final records = [
        _r(id: '1', rank: 5, kind: WishItemKind.character),
        _r(id: '2', rank: 4, kind: WishItemKind.weapon),
        _r(id: '3', rank: 4, kind: WishItemKind.character),
        _r(id: '4', rank: 3, kind: WishItemKind.weapon),
        _r(id: '5', rank: 3, kind: WishItemKind.weapon),
      ];
      final s = computeWishStats(records);
      expect(s.total, 5);
      expect(s.fiveStarCount, 1);
      expect(s.fourStarCount, 2);
      expect(s.threeStarOrBelowCount, 2);
      expect(s.characterCount, 2);
      expect(s.weaponCount, 3);
      expect(s.unknownCount, 0);
      expect(s.fiveStarRate, closeTo(0.2, 1e-9));
      expect(s.characterRate, closeTo(0.4, 1e-9));
    });
  });
}
