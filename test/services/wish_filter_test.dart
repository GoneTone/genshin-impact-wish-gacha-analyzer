import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';

WishRecord _r({
  required String id,
  required int rank,
  required WishItemKind kind,
  required String name,
  DateTime? time,
}) => WishRecord(
  id: id,
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: kind == WishItemKind.character ? '角色' : '武器',
  kind: kind,
  rankType: rank,
  time: time ?? DateTime(2025),
  lang: 'zh-tw',
);

void main() {
  late List<WishRecord> records;
  setUp(() {
    records = [
      _r(
        id: '5',
        rank: 5,
        kind: WishItemKind.character,
        name: '夜蘭',
        time: DateTime(2025, 5, 1),
      ),
      _r(
        id: '4',
        rank: 4,
        kind: WishItemKind.weapon,
        name: '匣裡龍吟',
        time: DateTime(2025, 4, 1),
      ),
      _r(
        id: '3',
        rank: 3,
        kind: WishItemKind.weapon,
        name: '黑纓槍',
        time: DateTime(2025, 3, 1),
      ),
      _r(
        id: '2',
        rank: 4,
        kind: WishItemKind.character,
        name: '煙緋',
        time: DateTime(2025, 2, 1),
      ),
      _r(
        id: '1',
        rank: 5,
        kind: WishItemKind.weapon,
        name: '若水',
        time: DateTime(2025, 1, 1),
      ),
    ];
  });

  group('filterRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records);
    });

    test('5★ + 武器 → 只剩 1 row，且 totalIndex / pity 不變', () {
      final out = filterRecordRows(
        rows,
        const RecordFilter(
          rarity: RarityFilter.fiveStar,
          kind: KindFilter.weapon,
        ),
      );
      expect(out.length, 1);
      expect(out.first.record.id, '1');
      // id '1' 是最舊一筆 → totalIndex = 1
      expect(out.first.totalIndex, 1);
    });

    test('搜尋 query 過濾 row 集', () {
      final out = filterRecordRows(rows, const RecordFilter(query: '夜'));
      expect(out.map((r) => r.record.id), ['5']);
    });
  });

  group('sortRecordRows', () {
    late List<RecordRow> rows;
    setUp(() {
      rows = buildRecordRows(records);
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
          column: SortColumn.fiveStarPity,
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

    test('kind 排序（按 itemType）', () {
      final out = sortRecordRows(
        rows,
        const TableSort(column: SortColumn.kind, direction: SortDirection.asc),
      );
      expect(out.length, rows.length);
    });
  });
}
