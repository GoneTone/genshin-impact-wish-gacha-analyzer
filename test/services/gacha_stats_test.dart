import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';

GachaRecord _r({String id = '1', int rank = 5, String itemType = '角色'}) =>
    GachaRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: 'x',
      itemType: itemType,
      rankType: rank,
      time: DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  group('GachaStats', () {
    test('空 list 全 0', () {
      final s = computeGachaStats(const []);
      expect(s.total, 0);
      expect(s.fiveStarCount, 0);
      expect(s.byItemType, isEmpty);
      expect(s.fiveStarRate, 0.0);
    });

    test('混合 list 計數正確', () {
      final records = [
        _r(id: '1', rank: 5, itemType: '角色'),
        _r(id: '2', rank: 4, itemType: '武器'),
        _r(id: '3', rank: 4, itemType: '角色'),
        _r(id: '4', rank: 3, itemType: '武器'),
        _r(id: '5', rank: 3, itemType: '武器'),
      ];
      final s = computeGachaStats(records);
      expect(s.total, 5);
      expect(s.fiveStarCount, 1);
      expect(s.fourStarCount, 2);
      expect(s.threeStarCount, 2);
      expect(s.twoStarCount, 0);
      expect(s.byItemType, {'角色': 2, '武器': 3});
      expect(s.fiveStarRate, closeTo(0.2, 1e-9));
    });

    test('byItemType 累計每種 item_type 出現次數', () {
      final records = [
        _r(id: '1', rank: 5, itemType: '角色'),
        _r(id: '2', rank: 4, itemType: '角色'),
        _r(id: '3', rank: 5, itemType: '武器'),
        _r(id: '4', rank: 4, itemType: '裝扮'),
      ];
      final stats = computeGachaStats(records);
      expect(stats.byItemType, {'角色': 2, '武器': 1, '裝扮': 1});
    });

    test('twoStarCount 與 threeStarCount 分開計算', () {
      final records = [
        _r(id: '1', rank: 5),
        _r(id: '2', rank: 4),
        _r(id: '3', rank: 3),
        _r(id: '4', rank: 3),
        _r(id: '5', rank: 2),
      ];
      final stats = computeGachaStats(records);
      expect(stats.fiveStarCount, 1);
      expect(stats.fourStarCount, 1);
      expect(stats.threeStarCount, 2);
      expect(stats.twoStarCount, 1);
    });

    test('空字串 itemType 累計到 ""', () {
      final records = [_r(id: '1', rank: 5, itemType: '')];
      final stats = computeGachaStats(records);
      expect(stats.byItemType, {'': 1});
    });

    test('sortedItemTypes 依 count desc 排序', () {
      final records = <GachaRecord>[
        for (var i = 0; i < 5; i++) _r(id: 'w$i', itemType: '武器'),
        for (var i = 0; i < 3; i++) _r(id: 'c$i', itemType: '角色'),
        _r(id: 'd', itemType: '裝扮'),
      ];
      final stats = computeGachaStats(records);
      expect(stats.sortedItemTypes().map((e) => e.key).toList(), [
        '武器',
        '角色',
        '裝扮',
      ]);
    });
  });
}
