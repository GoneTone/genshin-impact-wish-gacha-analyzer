import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/alias_merge.dart';

void main() {
  final t1 = DateTime.utc(2026, 11, 24, 1);
  final t2 = DateTime.utc(2026, 11, 24, 2);

  group('incomingAliasWins', () {
    test('兩邊都有時間：較新的勝出，時間相同保留本機', () {
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: t1,
          incomingAlias: 'B',
          incomingUpdatedAt: t2,
        ),
        isTrue,
      );
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: t2,
          incomingAlias: 'B',
          incomingUpdatedAt: t1,
        ),
        isFalse,
      );
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: t1,
          incomingAlias: 'B',
          incomingUpdatedAt: t1,
        ),
        isFalse,
      );
    });

    test('匯入方較新的清空也算勝出', () {
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: t1,
          incomingAlias: null,
          incomingUpdatedAt: t2,
        ),
        isTrue,
      );
    });

    test('只有一邊有時間：有時間的那邊勝出', () {
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: null,
          incomingAlias: null,
          incomingUpdatedAt: t1,
        ),
        isTrue,
      );
      expect(
        incomingAliasWins(
          localAlias: null,
          localUpdatedAt: t1,
          incomingAlias: 'B',
          incomingUpdatedAt: null,
        ),
        isFalse,
      );
    });

    test('兩邊都沒有時間：沿用舊規則，本機有別名就保留', () {
      expect(
        incomingAliasWins(
          localAlias: 'A',
          localUpdatedAt: null,
          incomingAlias: 'B',
          incomingUpdatedAt: null,
        ),
        isFalse,
      );
      expect(
        incomingAliasWins(
          localAlias: null,
          localUpdatedAt: null,
          incomingAlias: 'B',
          incomingUpdatedAt: null,
        ),
        isTrue,
      );
      expect(
        incomingAliasWins(
          localAlias: null,
          localUpdatedAt: null,
          incomingAlias: null,
          incomingUpdatedAt: null,
        ),
        isFalse,
      );
    });
  });

  group('parseAliasUpdatedAt', () {
    test('ISO 8601 字串解析成 UTC', () {
      expect(parseAliasUpdatedAt('2026-11-24T01:00:00.000Z'), t1);
      expect(parseAliasUpdatedAt('2026-11-24T01:00:00.000Z')!.isUtc, isTrue);
    });

    test('格式或型別不對時回傳 null', () {
      expect(parseAliasUpdatedAt('not a date'), isNull);
      expect(parseAliasUpdatedAt(123), isNull);
      expect(parseAliasUpdatedAt(null), isNull);
    });
  });
}
