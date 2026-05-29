import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_row.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

GachaRecord _r({
  required String id,
  required int rank,
  required String itemType,
  required String name,
  DateTime? time,
}) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: itemType,
  rankType: rank,
  time: time ?? DateTime(2025),
  lang: 'zh-tw',
);

void main() {
  late List<GachaRecord> records;
  setUp(() {
    records = [
      _r(
        id: '5',
        rank: 5,
        itemType: '角色',
        name: '夜蘭',
        time: DateTime(2025, 5, 1),
      ),
      _r(
        id: '4',
        rank: 4,
        itemType: '武器',
        name: '匣裡龍吟',
        time: DateTime(2025, 4, 1),
      ),
      _r(
        id: '3',
        rank: 3,
        itemType: '武器',
        name: '黑纓槍',
        time: DateTime(2025, 3, 1),
      ),
      _r(
        id: '2',
        rank: 4,
        itemType: '角色',
        name: '煙緋',
        time: DateTime(2025, 2, 1),
      ),
      _r(
        id: '1',
        rank: 5,
        itemType: '武器',
        name: '若水',
        time: DateTime(2025, 1, 1),
      ),
    ];
  });

  group('RecordFilter', () {
    test('預設 itemType 為 null，hasAny=false', () {
      const f = RecordFilter();
      expect(f.itemType, isNull);
      expect(f.hasAny, isFalse);
    });

    test('itemType 非 null → hasAny=true', () {
      const f = RecordFilter(itemType: '角色');
      expect(f.hasAny, isTrue);
    });

    test('copyWith：itemType=null 真的把它清掉（用 sentinel 區分）', () {
      const original = RecordFilter(itemType: '武器');
      final cleared = original.copyWith(itemType: null);
      expect(cleared.itemType, isNull);
    });

    test('copyWith：未傳 itemType 時保留原值', () {
      const original = RecordFilter(itemType: '武器', query: 'x');
      final updated = original.copyWith(query: 'y');
      expect(updated.itemType, '武器');
      expect(updated.query, 'y');
    });
  });

  group('filterRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    });

    test('5★ + 武器 → 只剩 1 row，且 totalIndex / pity 不變', () {
      final out = filterRecordRows(
        rows,
        const RecordFilter(rarity: RarityFilter.fiveStar, itemType: '武器'),
      );
      expect(out.length, 1);
      expect(out.first.record.id, '1');
      // id '1' 是最舊一筆 → totalIndex = 1
      expect(out.first.totalIndex, 1);
    });

    test('itemType="角色" → 只剩 character 條目', () {
      final out = filterRecordRows(rows, const RecordFilter(itemType: '角色'));
      expect(out.map((r) => r.record.id).toSet(), {'5', '2'});
    });

    test('itemType=null → 不過濾 itemType', () {
      final out = filterRecordRows(rows, const RecordFilter());
      expect(out.length, rows.length);
    });

    test('filterRecordRows 依 itemTypeKey 過濾', () {
      final kindRows = [
        RecordRow(
          record: _r(id: 'a', rank: 4, itemType: '角色', name: '煙緋'),
          totalIndex: 1,
          mainPityIndex: 1,
          itemTypeKey: 'kind:character',
        ),
        RecordRow(
          record: _r(id: 'b', rank: 4, itemType: '武器', name: '匣裡龍吟'),
          totalIndex: 2,
          mainPityIndex: 2,
          itemTypeKey: 'kind:weapon',
        ),
      ];
      final out = filterRecordRows(
        kindRows,
        const RecordFilter(itemType: 'kind:character'),
      );
      expect(out.length, 1);
      expect(out.first.itemTypeKey, 'kind:character');
    });

    test('搜尋 query 過濾 row 集', () {
      final out = filterRecordRows(rows, const RecordFilter(query: '夜'));
      expect(out.map((r) => r.record.id), ['5']);
    });
  });

  group('sortRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
    });

    test('null → 不排序，保持輸入順序', () {
      final out = sortRecordRows(rows, null);
      expect(out.map((r) => r.record.id), ['5', '4', '3', '2', '1']);
    });

    test('time desc / asc', () {
      final desc = sortRecordRows(
        rows,
        const TableSort(column: SortColumn.time, direction: SortDirection.desc),
      );
      expect(desc.map((r) => r.record.id), ['5', '4', '3', '2', '1']);

      final asc = sortRecordRows(
        rows,
        const TableSort(column: SortColumn.time, direction: SortDirection.asc),
      );
      expect(asc.map((r) => r.record.id), ['1', '2', '3', '4', '5']);
    });

    test('rarity desc：5★ 在前，二級鍵以 time desc', () {
      final out = sortRecordRows(
        rows,
        const TableSort(
          column: SortColumn.rarity,
          direction: SortDirection.desc,
        ),
      );
      expect(out.first.record.rankType, 5);
      expect(out.last.record.rankType, 3);
      // 兩個 5★（id 5 time 2025-05-01、id 1 time 2025-01-01）→ id 5 在前
      final fives = out.where((r) => r.record.rankType == 5).toList();
      expect(fives.map((r) => r.record.id), ['5', '1']);
    });

    test('rarity asc', () {
      final out = sortRecordRows(
        rows,
        const TableSort(
          column: SortColumn.rarity,
          direction: SortDirection.asc,
        ),
      );
      expect(out.first.record.rankType, 3);
      expect(out.last.record.rankType, 5);
    });

    test('totalIndex asc / desc', () {
      final asc = sortRecordRows(
        rows,
        const TableSort(
          column: SortColumn.totalIndex,
          direction: SortDirection.asc,
        ),
      );
      expect(asc.map((r) => r.totalIndex), [1, 2, 3, 4, 5]);
      final desc = sortRecordRows(
        rows,
        const TableSort(
          column: SortColumn.totalIndex,
          direction: SortDirection.desc,
        ),
      );
      expect(desc.map((r) => r.totalIndex), [5, 4, 3, 2, 1]);
    });

    test('fiveStarPity asc', () {
      final out = sortRecordRows(
        rows,
        const TableSort(
          column: SortColumn.mainPity,
          direction: SortDirection.asc,
        ),
      );
      // buildRecordRows 由 asc 視角 (id 1..5) 累計，ranks = 5,4,3,4,5：
      //   id 1 pity=1 (寫後重置 0), id 2 pity=1, id 3 pity=2, id 4 pity=3, id 5 pity=4
      // asc by pity → [pity=1 兩個, 2, 3, 4]
      // 二級鍵 time desc → 兩個 pity=1 中 id 2 (02-01) 比 id 1 (01-01) 新
      // 最終：[2, 1, 3, 4, 5]
      expect(out.map((r) => r.record.id), ['2', '1', '3', '4', '5']);
    });

    test('name 排序', () {
      final out = sortRecordRows(
        rows,
        const TableSort(column: SortColumn.name, direction: SortDirection.asc),
      );
      expect(out.length, rows.length);
    });

    test('SortColumn.kind 依 itemTypeKey 排序', () {
      final rows = [
        RecordRow(
          record: _r(id: 'a', rank: 4, itemType: '武器', name: '匣裡龍吟'),
          totalIndex: 1,
          mainPityIndex: 1,
          itemTypeKey: 'kind:weapon',
        ),
        RecordRow(
          record: _r(id: 'b', rank: 5, itemType: '角色', name: '夜蘭'),
          totalIndex: 2,
          mainPityIndex: 2,
          itemTypeKey: 'kind:character',
        ),
      ];
      final sorted = sortRecordRows(
        rows,
        const TableSort(column: SortColumn.kind, direction: SortDirection.asc),
      );
      // 'kind:character' < 'kind:weapon' 字典序，asc 時 character 在前
      expect(sorted.first.itemTypeKey, 'kind:character');
      expect(sorted.last.itemTypeKey, 'kind:weapon');
    });
  });
}
