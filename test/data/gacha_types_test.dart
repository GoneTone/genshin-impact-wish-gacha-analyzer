import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';

void main() {
  test('convertibleGachaTypes is all non-odes gacha types', () {
    expect(convertibleGachaTypes, {'301', '302', '500', '200', '100'});
    expect(convertibleGachaTypes.contains('2000'), isFalse);
    expect(convertibleGachaTypes.contains('1000'), isFalse);
  });

  group('gachaTypes registry', () {
    test('每個 type 至少有一條 pity rule', () {
      for (final t in gachaTypes) {
        expect(t.pities, isNotEmpty, reason: t.gachaType);
      }
    });

    test('primaryPity 是 pities[0]', () {
      for (final t in gachaTypes) {
        expect(t.primaryPity, same(t.pities.first));
      }
    });

    test('secondaryPity 在 pities 有第二筆時非 null', () {
      for (final t in gachaTypes) {
        if (t.pities.length >= 2) {
          expect(t.secondaryPity, same(t.pities[1]));
        } else {
          expect(t.secondaryPity, isNull);
        }
      }
    });

    test('5 個卡池 type 都是 gacha category', () {
      const gachaTypeIds = {'301', '302', '500', '200', '100'};
      for (final t in gachaTypes) {
        if (gachaTypeIds.contains(t.gachaType)) {
          expect(t.category, GachaCategory.gacha);
        }
      }
    });

    test('既有保底值保留', () {
      final character = gachaTypes.firstWhere((t) => t.gachaType == '301');
      expect(character.primaryPity.rank, 5);
      expect(character.primaryPity.threshold, 90);
      expect(character.secondaryPity!.rank, 4);
      expect(character.secondaryPity!.threshold, 10);

      final weapon = gachaTypes.firstWhere((t) => t.gachaType == '302');
      expect(weapon.primaryPity.threshold, 80);

      final beginner = gachaTypes.firstWhere((t) => t.gachaType == '100');
      expect(beginner.primaryPity.threshold, 20);
    });

    test('2 個頌願 type 是 odes category', () {
      const odesTypes = {'2000', '1000'};
      for (final t in gachaTypes) {
        if (odesTypes.contains(t.gachaType)) {
          expect(t.category, GachaCategory.odes);
        }
      }
    });

    test('活動頌願 (2000): 5★ 70 / 4★ 10', () {
      final t = gachaTypes.firstWhere((g) => g.gachaType == '2000');
      expect(t.primaryPity.rank, 5);
      expect(t.primaryPity.threshold, 70);
      expect(t.secondaryPity!.rank, 4);
      expect(t.secondaryPity!.threshold, 10);
    });

    test('常駐頌願 (1000): 4★ 70 / 3★ 5（無 5★）', () {
      final t = gachaTypes.firstWhere((g) => g.gachaType == '1000');
      expect(t.primaryPity.rank, 4);
      expect(t.primaryPity.threshold, 70);
      expect(t.secondaryPity!.rank, 3);
      expect(t.secondaryPity!.threshold, 5);
    });

    test('總共 7 個 type (5 gacha + 2 odes)', () {
      expect(gachaTypes.length, 7);
      expect(
        gachaTypes.where((t) => t.category == GachaCategory.gacha).length,
        5,
      );
      expect(
        gachaTypes.where((t) => t.category == GachaCategory.odes).length,
        2,
      );
    });
  });
}
