import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';

void main() {
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

    test('5 個祈願 type 都是 wish category', () {
      const wishTypes = {'301', '302', '500', '200', '100'};
      for (final t in gachaTypes) {
        if (wishTypes.contains(t.gachaType)) {
          expect(t.category, GachaCategory.wish);
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
  });
}
