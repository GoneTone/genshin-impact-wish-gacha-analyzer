import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

GachaRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'x',
}) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: gachaType,
  name: name,
  itemType: '角色',
  rankType: rank,
  time: time,
  lang: 'zh-tw',
);

void main() {
  group('buildTimelineEntries', () {
    test('empty records → empty list', () {
      expect(buildTimelineEntries(const []), isEmpty);
    });

    test('records without 5★ → empty list', () {
      final records = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        _r(id: '2', gachaType: '301', rank: 4, time: DateTime(2025, 1, 2)),
      ];
      expect(buildTimelineEntries(records.reversed.toList()), isEmpty);
    });

    test('computes pullsSincePrev counting from start', () {
      final asc = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        _r(id: '2', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(
          id: '3',
          gachaType: '301',
          rank: 5,
          name: 'A',
          time: DateTime(2025, 1, 3),
        ),
        _r(id: '4', gachaType: '301', rank: 3, time: DateTime(2025, 1, 4)),
        _r(
          id: '5',
          gachaType: '301',
          rank: 5,
          name: 'B',
          time: DateTime(2025, 1, 5),
        ),
      ];
      final desc = asc.reversed.toList();
      final result = buildTimelineEntries(desc);
      expect(result, hasLength(2));
      expect(result[0].name, 'B');
      expect(result[0].pullsSincePrev, 2);
      expect(result[1].name, 'A');
      expect(result[1].pullsSincePrev, 3);
    });

    test('targetRank=4 萃取 4★ 條目', () {
      // desc by time
      final records = [
        _r(id: '8', gachaType: '301', rank: 5, time: DateTime(2026, 5, 5)),
        _r(
          id: '7',
          gachaType: '301',
          rank: 4,
          name: 'Four-B',
          time: DateTime(2026, 5, 4),
        ),
        _r(id: '6', gachaType: '301', rank: 3, time: DateTime(2026, 5, 3)),
        _r(
          id: '5',
          gachaType: '301',
          rank: 4,
          name: 'Four-A',
          time: DateTime(2026, 5, 2),
        ),
        _r(id: '4', gachaType: '301', rank: 3, time: DateTime(2026, 5, 1)),
      ];
      final entries = buildTimelineEntries(records, targetRank: 4);
      expect(entries.length, 2);
      // entries 依時間 desc(最新在前)
      expect(entries.first.time, DateTime(2026, 5, 4));
      expect(entries.last.time, DateTime(2026, 5, 2));
    });
  });

  group('buildTimelineEntriesAcrossBanners', () {
    test('merges multiple banners and sorts by time desc', () {
      final banners = {
        '301': [
          _r(
            id: 'c2',
            gachaType: '301',
            rank: 5,
            name: 'CharB',
            time: DateTime(2025, 3, 1),
          ),
          _r(
            id: 'c1',
            gachaType: '301',
            rank: 5,
            name: 'CharA',
            time: DateTime(2025, 1, 1),
          ),
        ],
        '302': [
          _r(
            id: 'w1',
            gachaType: '302',
            rank: 5,
            name: 'WepA',
            time: DateTime(2025, 2, 1),
          ),
        ],
      };
      final result = buildTimelineEntriesAcrossBanners(
        banners,
        rankFor: (_) => 5,
      );
      expect(result.map((e) => e.name).toList(), ['CharB', 'WepA', 'CharA']);
    });

    test('per-pool pullsSincePrev preserved (not recomputed across pools)', () {
      final banners = {
        '301': [
          _r(id: 'a', gachaType: '301', rank: 5, time: DateTime(2025, 2, 1)),
        ],
        '302': [
          _r(id: 'b', gachaType: '302', rank: 5, time: DateTime(2025, 1, 1)),
        ],
      };
      final result = buildTimelineEntriesAcrossBanners(
        banners,
        rankFor: (_) => 5,
      );
      expect(result.every((e) => e.pullsSincePrev == 1), isTrue);
    });

    test('rankFor callback 給各卡池不同主稀有度', () {
      final banners = <String, List<GachaRecord>>{
        '301': [
          _r(
            id: 'a',
            gachaType: '301',
            rank: 5,
            name: 'Char5',
            time: DateTime(2026, 5, 5),
          ),
        ],
        '1000': [
          _r(
            id: 'b',
            gachaType: '1000',
            rank: 4,
            name: 'Ode4',
            time: DateTime(2026, 5, 6),
          ),
        ],
      };
      final entries = buildTimelineEntriesAcrossBanners(
        banners,
        rankFor: (gt) => gt == '1000' ? 4 : 5,
      );
      expect(entries.length, 2);
      // desc by time → 1000 的 4★(5/6) 在前
      expect(entries.first.gachaType, '1000');
      expect(entries.last.gachaType, '301');
    });
  });

  group('pullsSinceLastRanked', () {
    test('no matching rank → returns total records count', () {
      final records = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '2', gachaType: '301', rank: 4, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastRanked(records, rank: 5), 2);
    });

    test('counts records newer than latest matching rank', () {
      final records = [
        _r(id: '3', gachaType: '301', rank: 3, time: DateTime(2025, 1, 3)),
        _r(id: '2', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '1', gachaType: '301', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastRanked(records, rank: 5), 2);
    });

    test('empty records → 0', () {
      expect(pullsSinceLastRanked(const [], rank: 5), 0);
    });

    test('rank=4 counts records newer than latest 4★', () {
      // desc by time
      final records = [
        _r(id: '5', gachaType: '301', rank: 5, time: DateTime(2025, 1, 5)),
        _r(id: '4', gachaType: '301', rank: 3, time: DateTime(2025, 1, 4)),
        _r(id: '3', gachaType: '301', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', gachaType: '301', rank: 5, time: DateTime(2025, 1, 2)),
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      // 從 records[0] 開始算到 rank=4 出現的位置 → 2 筆在前
      expect(pullsSinceLastRanked(records, rank: 4), 2);
    });
  });

  group('pullsSinceLastRankedAcrossBanners', () {
    test('counts across all pools after cross-pool latest 5★', () {
      final banners = {
        '301': [
          _r(id: 'c3', gachaType: '301', rank: 3, time: DateTime(2025, 3, 1)),
          _r(id: 'c2', gachaType: '301', rank: 5, time: DateTime(2025, 2, 1)),
          _r(id: 'c1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        ],
        '302': [
          _r(id: 'w1', gachaType: '302', rank: 5, time: DateTime(2025, 2, 15)),
        ],
      };
      expect(pullsSinceLastRankedAcrossBanners(banners, rankFor: (_) => 5), 1);
    });

    test('no matching rank anywhere → total cross-pool record count', () {
      final banners = {
        '301': [
          _r(id: 'a', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        ],
        '302': [
          _r(id: 'b', gachaType: '302', rank: 4, time: DateTime(2025, 1, 1)),
          _r(id: 'c', gachaType: '302', rank: 3, time: DateTime(2025, 1, 2)),
        ],
      };
      expect(pullsSinceLastRankedAcrossBanners(banners, rankFor: (_) => 5), 3);
    });

    test('empty banners → 0', () {
      expect(pullsSinceLastRankedAcrossBanners(const {}, rankFor: (_) => 5), 0);
    });

    test(
      'same-pool same-second: counts records pulled after the 5★ within the same 10-pull',
      () {
        // 10-pull at 2025-04-19 14:32:00, 5★ is record #5 of the 10.
        // In desc-by-time + id-desc order, the array is: r10, r9, r8, r7, r6, 5★, r4, r3, r2, r1
        // Records pulled AFTER the 5★: r6, r7, r8, r9, r10 → count == 5
        final sameSec = DateTime(2025, 4, 19, 14, 32, 0);
        final banners = {
          '301': [
            _r(id: '10', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '9', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '8', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '7', gachaType: '301', rank: 4, time: sameSec),
            _r(id: '6', gachaType: '301', rank: 3, time: sameSec),
            _r(
              id: '5',
              gachaType: '301',
              rank: 5,
              name: 'FiveStar',
              time: sameSec,
            ),
            _r(id: '4', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '3', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '2', gachaType: '301', rank: 3, time: sameSec),
            _r(id: '1', gachaType: '301', rank: 3, time: sameSec),
          ],
        };
        expect(
          pullsSinceLastRankedAcrossBanners(banners, rankFor: (_) => 5),
          5,
        );
      },
    );

    test('rankFor 各卡池用不同稀有度', () {
      // 301 用 5★、1000 用 4★
      final banners = <String, List<GachaRecord>>{
        '301': [
          _r(id: 'c2', gachaType: '301', rank: 3, time: DateTime(2026, 5, 10)),
          _r(id: 'c1', gachaType: '301', rank: 5, time: DateTime(2026, 5, 5)),
        ],
        '1000': [
          _r(id: 'o3', gachaType: '1000', rank: 3, time: DateTime(2026, 5, 12)),
          _r(id: 'o2', gachaType: '1000', rank: 4, time: DateTime(2026, 5, 11)),
          _r(id: 'o1', gachaType: '1000', rank: 3, time: DateTime(2026, 5, 1)),
        ],
      };
      // 跨卡池最新主稀有度 = 1000 卡池的 4★ o2(5/11)
      // 比 o2 晚的:1000 的 o3(5/12)、301 的 c2(5/10 比 5/11 早,不算)
      // → 1
      expect(
        pullsSinceLastRankedAcrossBanners(
          banners,
          rankFor: (gt) => gt == '1000' ? 4 : 5,
        ),
        1,
      );
    });
  });
}
