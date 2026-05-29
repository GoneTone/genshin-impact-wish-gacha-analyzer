import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

GachaRecord _r({
  required String id,
  required int rank,
  required DateTime time,
  String gachaType = '301',
  String name = 'x',
  String lang = 'zh-tw',
}) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: gachaType,
  name: name,
  itemType: '角色',
  rankType: rank,
  time: time,
  lang: lang,
);

void main() {
  const emptyIndex = HoYoWikiIndex.empty();

  group('buildFiveStarCollection', () {
    test('empty records → empty list', () {
      expect(buildFiveStarCollection(const [], index: emptyIndex), isEmpty);
    });

    test('只取 5★，排除 4★／3★', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 4, name: 'B', time: DateTime(2025, 1, 2)),
        _r(id: '3', rank: 3, name: 'C', time: DateTime(2025, 1, 3)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(1));
      expect(result.single.representative.name, 'A');
      expect(result.single.count, 1);
    });

    test('同名去重計數，代表 record 取最近一次', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 5, name: 'A', time: DateTime(2025, 3, 1)),
        _r(id: '3', rank: 5, name: 'A', time: DateTime(2025, 2, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(1));
      expect(result.single.count, 3);
      expect(result.single.representative.id, '2'); // 2025-03-01 最近
    });

    test('排序：次數降冪，同次數以最近時間降冪', () {
      final records = [
        _r(id: 'a1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: 'a2', rank: 5, name: 'A', time: DateTime(2025, 1, 2)),
        _r(id: 'b1', rank: 5, name: 'B', time: DateTime(2025, 5, 1)),
        _r(id: 'c1', rank: 5, name: 'C', time: DateTime(2025, 4, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      // A=2 → 最前；B/C 各 1，B(5/1) 比 C(4/1) 新 → B 在 C 前
      expect(result.map((e) => e.representative.name).toList(), [
        'A',
        'B',
        'C',
      ]);
    });

    test('跨語系：同 id 不同語系名稱合併為一', () {
      const index = HoYoWikiIndex(
        searchMap: {'zh-tw::雷電將軍': '10000052', 'en::Raiden Shogun': '10000052'},
        entries: {},
        menuIds: {},
      );
      final records = [
        _r(
          id: '1',
          rank: 5,
          name: '雷電將軍',
          lang: 'zh-tw',
          time: DateTime(2025, 1, 1),
        ),
        _r(
          id: '2',
          rank: 5,
          name: 'Raiden Shogun',
          lang: 'en',
          time: DateTime(2025, 2, 1),
        ),
      ];
      final result = buildFiveStarCollection(records, index: index);
      expect(result, hasLength(1));
      expect(result.single.count, 2);
      expect(result.single.representative.lang, 'en'); // 最近一筆
    });

    test('fallback：index lookup miss 時以名稱為鍵，不誤併不同物', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 5, name: 'B', time: DateTime(2025, 2, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(2));
    });
  });

  group('buildFiveStarCollectionAcrossBanners', () {
    test('同物品跨卡池合併、次數相加', () {
      const index = HoYoWikiIndex(
        searchMap: {'zh-tw::琴': '10000003'},
        entries: {},
        menuIds: {},
      );
      final banners = {
        '301': [_r(id: 'c1', rank: 5, name: '琴', time: DateTime(2025, 1, 1))],
        '200': [
          _r(
            id: 's1',
            rank: 5,
            name: '琴',
            gachaType: '200',
            time: DateTime(2025, 3, 1),
          ),
          _r(
            id: 's2',
            rank: 5,
            name: '琴',
            gachaType: '200',
            time: DateTime(2025, 2, 1),
          ),
        ],
      };
      final result = buildFiveStarCollectionAcrossBanners(
        banners,
        index: index,
      );
      expect(result, hasLength(1));
      expect(result.single.count, 3);
      expect(result.single.representative.id, 's1'); // 2025-03-01 最近
    });

    test('empty banners → empty list', () {
      expect(
        buildFiveStarCollectionAcrossBanners(const {}, index: emptyIndex),
        isEmpty,
      );
    });
  });
}
