import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';

WishRecord _r({
  required String id,
  required int rank,
  required WishItemKind kind,
  required String name,
  DateTime? time,
}) =>
    WishRecord(
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
      _r(id: '5', rank: 5, kind: WishItemKind.character, name: '夜蘭', time: DateTime(2025, 5, 1)),
      _r(id: '4', rank: 4, kind: WishItemKind.weapon, name: '匣裡龍吟', time: DateTime(2025, 4, 1)),
      _r(id: '3', rank: 3, kind: WishItemKind.weapon, name: '黑纓槍', time: DateTime(2025, 3, 1)),
      _r(id: '2', rank: 4, kind: WishItemKind.character, name: '煙緋', time: DateTime(2025, 2, 1)),
      _r(id: '1', rank: 5, kind: WishItemKind.weapon, name: '若水', time: DateTime(2025, 1, 1)),
    ];
  });

  group('filterRecords', () {
    test('預設不過濾', () {
      final out = filterRecords(records, const RecordFilter());
      expect(out.length, 5);
    });

    test('只看 5★', () {
      final out = filterRecords(records,
          const RecordFilter(rarity: RarityFilter.fiveStar));
      expect(out.map((r) => r.id), ['5', '1']);
    });

    test('只看 4★', () {
      final out = filterRecords(records,
          const RecordFilter(rarity: RarityFilter.fourStar));
      expect(out.map((r) => r.id), ['4', '2']);
    });

    test('只看角色', () {
      final out = filterRecords(records,
          const RecordFilter(kind: KindFilter.character));
      expect(out.map((r) => r.id), ['5', '2']);
    });

    test('組合 5★ + 武器', () {
      final out = filterRecords(
          records,
          const RecordFilter(
              rarity: RarityFilter.fiveStar, kind: KindFilter.weapon));
      expect(out.map((r) => r.id), ['1']);
    });

    test('搜尋名字（不分大小寫）', () {
      final out = filterRecords(records, const RecordFilter(query: '若'));
      expect(out.map((r) => r.id), ['1']);
    });

    test('空 query 等同沒篩', () {
      final out =
          filterRecords(records, const RecordFilter(query: '   '));
      expect(out.length, 5);
    });
  });

  group('sortRecords', () {
    test('預設時間 desc 維持原順序', () {
      final out = sortRecords(records, RecordSort.timeDesc);
      expect(out.map((r) => r.id), ['5', '4', '3', '2', '1']);
    });

    test('時間 asc', () {
      final out = sortRecords(records, RecordSort.timeAsc);
      expect(out.map((r) => r.id), ['1', '2', '3', '4', '5']);
    });

    test('稀有度 desc', () {
      final out = sortRecords(records, RecordSort.rarityDesc);
      expect(out.first.rankType, 5);
      expect(out.last.rankType, 3);
    });

    test('稀有度 asc', () {
      final out = sortRecords(records, RecordSort.rarityAsc);
      expect(out.first.rankType, 3);
      expect(out.last.rankType, 5);
    });

    test('名稱', () {
      final out = sortRecords(records, RecordSort.name);
      expect(out.length, records.length);
    });
  });
}
