import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

GachaRecord _r({required String id, required int rank, DateTime? time}) =>
    GachaRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: 'x',
      itemType: '角色',
      rankType: rank,
      time: time ?? DateTime(2025, 1, int.parse(id)),
      lang: 'zh-tw',
    );

void main() {
  group('buildRecordRows', () {
    test('空 list → const []', () {
      expect(
        buildRecordRows(const [], index: const HoYoWikiIndex.empty()),
        isEmpty,
      );
    });

    test('totalIndex 從 1 開始累計，最舊=1、最新=N，且輸出順序與輸入一致 (desc by time)', () {
      // input desc by time: id 5,4,3,2,1（time 2025-01-05 ... 01-01）
      final records = [
        _r(id: '5', rank: 3),
        _r(id: '4', rank: 3),
        _r(id: '3', rank: 3),
        _r(id: '2', rank: 3),
        _r(id: '1', rank: 3),
      ];
      final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
      expect(rows.map((r) => r.record.id).toList(), ['5', '4', '3', '2', '1']);
      expect(rows.map((r) => r.totalIndex).toList(), [5, 4, 3, 2, 1]);
    });

    test('全無 5★ → mainPityIndex == totalIndex', () {
      final records = [
        _r(id: '3', rank: 4),
        _r(id: '2', rank: 3),
        _r(id: '1', rank: 4),
      ];
      final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
      expect(rows.map((r) => r.mainPityIndex).toList(), [3, 2, 1]);
    });

    test('5★ 那一抽 = 抵達該 5★ 的累積值，下一抽從 1 重新累計', () {
      // asc 順序視角：1(3★) 2(3★) 3(5★) 4(3★) 5(5★)
      // pity asc:        1    2    3    1    2
      // input desc by time: id 5..1
      final records = [
        _r(id: '5', rank: 5), // pity = 2 (距上一個 5★ 後第 2 抽)
        _r(id: '4', rank: 3), // pity = 1
        _r(id: '3', rank: 5), // pity = 3 (前面 1,2 是 3★，這一抽是 5★)
        _r(id: '2', rank: 3), // pity = 2
        _r(id: '1', rank: 3), // pity = 1
      ];
      final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
      // 以 id 對應驗證 pity
      final byId = {for (final r in rows) r.record.id: r};
      expect(byId['1']!.mainPityIndex, 1);
      expect(byId['2']!.mainPityIndex, 2);
      expect(byId['3']!.mainPityIndex, 3);
      expect(byId['4']!.mainPityIndex, 1);
      expect(byId['5']!.mainPityIndex, 2);
    });

    test('首抽即 5★ → 該抽 pity = 1', () {
      final records = [_r(id: '1', rank: 5)];
      final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
      expect(rows.first.totalIndex, 1);
      expect(rows.first.mainPityIndex, 1);
    });

    test('itemTypeKey: menu_id 命中用 canonical，miss fallback 原始字串', () {
      final index = HoYoWikiIndex(
        searchMap: const {'zh-tw::迪希雅': 'c1'},
        entries: const {},
        menuIds: const {'c1': 2},
      );
      final records = [
        GachaRecord(
          id: '1',
          uid: '1',
          gachaType: '301',
          name: '迪希雅',
          itemType: '角色',
          rankType: 5,
          time: DateTime(2025, 1, 2),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '2',
          uid: '1',
          gachaType: '301',
          name: '某武器',
          itemType: '武器',
          rankType: 4,
          time: DateTime(2025, 1, 1),
          lang: 'zh-tw',
        ),
      ];
      final rows = buildRecordRows(records, index: index);
      expect(rows[0].itemTypeKey, 'kind:character'); // 迪希雅命中
      expect(rows[1].itemTypeKey, '武器'); // 未命中 → 原始字串
    });
  });
}
