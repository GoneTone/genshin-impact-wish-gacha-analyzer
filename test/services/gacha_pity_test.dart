import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';

GachaRecord _r({required String id, required int rank, DateTime? time}) =>
    GachaRecord(
      id: id,
      uid: '1',
      gachaType: '301',
      name: 'x',
      itemType: '角色',
      rankType: rank,
      time: time ?? DateTime(2025),
      lang: 'zh-tw',
    );

void main() {
  group('computePity', () {
    test('空 list → current=0、lastRecordAt=null', () {
      final p = computePity(const [], threshold: 90);
      expect(p.current, 0);
      expect(p.threshold, 90);
      expect(p.lastRecordAt, isNull);
    });

    test('從未抽中 5★ → current = total 抽數', () {
      final records = [
        _r(id: '3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 3, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 3);
      expect(p.lastRecordAt, isNull);
    });

    test('上次 5★ 之後 N 抽 → current=N', () {
      final records = [
        _r(id: '5', rank: 4, time: DateTime(2025, 1, 5)),
        _r(id: '4', rank: 4, time: DateTime(2025, 1, 4)),
        _r(id: '3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 5, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 3);
      expect(p.lastRecordAt, DateTime(2025, 1, 2));
    });

    test('首抽即 5★ → current=0、lastRecordAt 為該筆時間', () {
      final records = [_r(id: '1', rank: 5, time: DateTime(2025, 1, 1))];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.lastRecordAt, DateTime(2025, 1, 1));
    });

    test('最新即 5★ → current=0', () {
      final records = [
        _r(id: '3', rank: 5, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 4, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.lastRecordAt, DateTime(2025, 1, 3));
    });

    test('剛好 threshold-1 抽未保底 → progress 接近 1.0', () {
      final records = List.generate(
        89,
        (i) => _r(id: '$i', rank: 4, time: DateTime(2025, 1, 1 + i)),
      ).reversed.toList(growable: false);
      final p = computePity(records, threshold: 90);
      expect(p.current, 89);
      expect(p.progress, closeTo(89 / 90, 0.001));
      expect(p.distance, 1);
    });

    test('progress 永遠在 0..1 之間，超過 threshold 也 clamp', () {
      final records = List.generate(
        100,
        (i) => _r(id: '$i', rank: 4, time: DateTime(2025, 1, 1 + i)),
      ).reversed.toList(growable: false);
      final p = computePity(records, threshold: 90);
      expect(p.progress, 1.0);
      expect(p.distance, 0);
    });

    test('rank=4 → counts to last 4★ ignoring 5★', () {
      // records: 4★, 3★, 5★, 4★, 3★ (newest first)
      final records = [
        GachaRecord(
          id: '5',
          uid: '1',
          gachaType: '301',
          name: 'a',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 5),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '4',
          uid: '1',
          gachaType: '301',
          name: 'b',
          itemType: '角色',
          rankType: 5,
          time: DateTime(2025, 1, 4),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '3',
          uid: '1',
          gachaType: '301',
          name: 'c',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 3),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '2',
          uid: '1',
          gachaType: '301',
          name: 'd',
          itemType: '角色',
          rankType: 4,
          time: DateTime(2025, 1, 2),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '1',
          uid: '1',
          gachaType: '301',
          name: 'e',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 1),
          lang: 'zh-tw',
        ),
      ];
      final p = computePity(records, threshold: 10, rank: 4);
      // 上次 4★ 是 id '2'；之後是 3★ + 5★ + 3★ = 3 抽
      expect(p.current, 3);
      expect(p.lastRecordAt, DateTime(2025, 1, 2));
    });

    test('空 list → hitCount=0、averageInterval=null', () {
      final p = computePity(const [], threshold: 90);
      expect(p.hitCount, 0);
      expect(p.averageInterval, isNull);
    });

    test('有抽但無命中 → hitCount=0、averageInterval=null', () {
      final records = List.generate(
        10,
        (i) => _r(id: '$i', rank: 4, time: DateTime(2025, 1, 1 + i)),
      ).reversed.toList(growable: false);
      final p = computePity(records, threshold: 90, rank: 5);
      expect(p.hitCount, 0);
      expect(p.averageInterval, isNull);
    });

    test('最舊抽即 5★ → averageInterval=1.0', () {
      // records (新→舊): 4×未中, 5★
      final records = [
        _r(id: '5', rank: 4, time: DateTime(2025, 1, 5)),
        _r(id: '4', rank: 4, time: DateTime(2025, 1, 4)),
        _r(id: '3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 4, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 4);
      expect(p.hitCount, 1);
      expect(p.averageInterval, 1.0);
    });

    test('兩件命中 → averageInterval=4.5', () {
      // records (新→舊): 未中×3, 5★, 未中×7, 5★
      final records = [
        for (var i = 0; i < 3; i++)
          _r(id: 'top-$i', rank: 4, time: DateTime(2025, 2, 12 - i)),
        _r(id: 'hit-new', rank: 5, time: DateTime(2025, 2, 9)),
        for (var i = 0; i < 7; i++)
          _r(id: 'mid-$i', rank: 4, time: DateTime(2025, 2, 8 - i)),
        _r(id: 'hit-old', rank: 5, time: DateTime(2025, 2, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 3);
      expect(p.hitCount, 2);
      expect(p.averageInterval, 4.5);
    });

    test('最新抽即 5★ + 5 抽歷史 → averageInterval=6.0', () {
      // records (新→舊): 5★, 未中×5
      final records = [
        _r(id: 'hit', rank: 5, time: DateTime(2025, 1, 6)),
        for (var i = 0; i < 5; i++)
          _r(id: 'old-$i', rank: 4, time: DateTime(2025, 1, 5 - i)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.hitCount, 1);
      expect(p.averageInterval, 6.0);
    });

    test('rank=4 查詢 → 只算 4★ 命中', () {
      // records (新→舊): 未中×3, 4★, 未中×2, 5★
      // 對 rank=4: current=3, hitCount=1, completed=4, avg=4.0
      final records = [
        for (var i = 0; i < 3; i++)
          _r(id: 'top-$i', rank: 3, time: DateTime(2025, 2, 7 - i)),
        _r(id: 'four', rank: 4, time: DateTime(2025, 2, 4)),
        for (var i = 0; i < 2; i++)
          _r(id: 'mid-$i', rank: 3, time: DateTime(2025, 2, 3 - i)),
        _r(id: 'five', rank: 5, time: DateTime(2025, 2, 1)),
      ];
      final p = computePity(records, threshold: 10, rank: 4);
      expect(p.current, 3);
      expect(p.hitCount, 1);
      expect(p.averageInterval, 4.0);
    });

    test('帶小數 → averageInterval≈3.333…', () {
      // records (新→舊): 5★, 未中×3, 5★, 未中×4, 5★
      // current=0, hitCount=3, completed=10, avg=10/3
      final records = [
        _r(id: 'hit3', rank: 5, time: DateTime(2025, 2, 10)),
        for (var i = 0; i < 3; i++)
          _r(id: 'mid-${9 - i}', rank: 4, time: DateTime(2025, 2, 9 - i)),
        _r(id: 'hit2', rank: 5, time: DateTime(2025, 2, 6)),
        for (var i = 0; i < 4; i++)
          _r(id: 'mid-${5 - i}', rank: 4, time: DateTime(2025, 2, 5 - i)),
        _r(id: 'hit1', rank: 5, time: DateTime(2025, 2, 1)),
      ];
      final p = computePity(records, threshold: 90);
      expect(p.current, 0);
      expect(p.hitCount, 3);
      expect(p.averageInterval, closeTo(10 / 3, 1e-9));
      expect(p.averageInterval!.toStringAsFixed(2), '3.33');
    });
  });

  group('averageIntervalAcrossBanners', () {
    test('全空 banners → null', () {
      final result = averageIntervalAcrossBanners(const {
        '301': <GachaRecord>[],
        '302': <GachaRecord>[],
      }, rankFor: (_) => 5);
      expect(result, isNull);
    });

    test('單卡池有命中 → 與 single-banner averageInterval 相同', () {
      // '301': 未中×3, 5★, 未中×7, 5★ → completed=9, hits=2 → 4.5
      final records = [
        for (var i = 0; i < 3; i++)
          _r(id: 'top-$i', rank: 4, time: DateTime(2025, 2, 12 - i)),
        _r(id: 'hit-new', rank: 5, time: DateTime(2025, 2, 9)),
        for (var i = 0; i < 7; i++)
          _r(id: 'mid-$i', rank: 4, time: DateTime(2025, 2, 8 - i)),
        _r(id: 'hit-old', rank: 5, time: DateTime(2025, 2, 1)),
      ];
      final result = averageIntervalAcrossBanners({
        '301': records,
      }, rankFor: (_) => 5);
      expect(result, 4.5);
    });

    test('多卡池合併分子分母 → (1+9)/(1+2)≈3.333', () {
      // '301': 未中×4, 5★ → completed=1, hits=1
      // '302': 未中×3, 5★, 未中×7, 5★ → completed=9, hits=2
      final r301 = [
        for (var i = 0; i < 4; i++)
          _r(id: '301-mid-$i', rank: 4, time: DateTime(2025, 1, 5 - i)),
        _r(id: '301-hit', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      final r302 = [
        for (var i = 0; i < 3; i++)
          _r(id: '302-top-$i', rank: 4, time: DateTime(2025, 2, 12 - i)),
        _r(id: '302-hit-new', rank: 5, time: DateTime(2025, 2, 9)),
        for (var i = 0; i < 7; i++)
          _r(id: '302-mid-$i', rank: 4, time: DateTime(2025, 2, 8 - i)),
        _r(id: '302-hit-old', rank: 5, time: DateTime(2025, 2, 1)),
      ];
      final result = averageIntervalAcrossBanners({
        '301': r301,
        '302': r302,
      }, rankFor: (_) => 5);
      expect(result, closeTo(10 / 3, 1e-9));
    });

    test('空卡池被略過 → 只計入有資料的卡池', () {
      final r302 = [
        for (var i = 0; i < 4; i++)
          _r(id: 'mid-$i', rank: 4, time: DateTime(2025, 1, 5 - i)),
        _r(id: 'hit', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      final result = averageIntervalAcrossBanners({
        '301': const <GachaRecord>[],
        '302': r302,
      }, rankFor: (_) => 5);
      expect(result, 1.0);
    });

    test('rankFor 切換 rank → 無命中時回傳 null', () {
      final r301 = [
        for (var i = 0; i < 4; i++)
          _r(id: 'mid-$i', rank: 4, time: DateTime(2025, 1, 5 - i)),
        _r(id: 'hit', rank: 5, time: DateTime(2025, 1, 1)),
      ];
      // 該 records 沒有 rank=3 命中
      final result = averageIntervalAcrossBanners({
        '301': r301,
      }, rankFor: (_) => 3);
      expect(result, isNull);
    });
  });
}
