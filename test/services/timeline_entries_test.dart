import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

WishRecord _r({
  required String id,
  required String gachaType,
  required int rank,
  required DateTime time,
  String name = 'x',
}) => WishRecord(
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
      final result = buildTimelineEntriesAcrossBanners(banners);
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
      final result = buildTimelineEntriesAcrossBanners(banners);
      expect(result.every((e) => e.pullsSincePrev == 1), isTrue);
    });
  });

  group('pullsSinceLastFiveStar', () {
    test('no 5★ → returns total records count', () {
      final records = [
        _r(id: '1', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '2', gachaType: '301', rank: 4, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastFiveStar(records), 2);
    });

    test('counts records newer than latest 5★', () {
      final records = [
        _r(id: '3', gachaType: '301', rank: 3, time: DateTime(2025, 1, 3)),
        _r(id: '2', gachaType: '301', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '1', gachaType: '301', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      expect(pullsSinceLastFiveStar(records), 2);
    });

    test('empty records → 0', () {
      expect(pullsSinceLastFiveStar(const []), 0);
    });
  });

  group('pullsSinceLastFiveStarAcrossBanners', () {
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
      expect(pullsSinceLastFiveStarAcrossBanners(banners), 1);
    });

    test('no 5★ anywhere → total cross-pool record count', () {
      final banners = {
        '301': [
          _r(id: 'a', gachaType: '301', rank: 3, time: DateTime(2025, 1, 1)),
        ],
        '302': [
          _r(id: 'b', gachaType: '302', rank: 4, time: DateTime(2025, 1, 1)),
          _r(id: 'c', gachaType: '302', rank: 3, time: DateTime(2025, 1, 2)),
        ],
      };
      expect(pullsSinceLastFiveStarAcrossBanners(banners), 3);
    });

    test('empty banners → 0', () {
      expect(pullsSinceLastFiveStarAcrossBanners(const {}), 0);
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
        expect(pullsSinceLastFiveStarAcrossBanners(banners), 5);
      },
    );
  });
}
