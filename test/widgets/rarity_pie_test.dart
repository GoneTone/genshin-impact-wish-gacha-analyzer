import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

void main() {
  group('rarityDistributionEntries', () {
    test('returns 5★/4★/3★ entries with correct counts and rates', () {
      const stats = WishStats(
        total: 100,
        fiveStarCount: 1,
        fourStarCount: 9,
        threeStarOrBelowCount: 90,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries, hasLength(3));
      expect(entries[0].name, '5★');
      expect(entries[0].count, 1);
      expect(entries[0].rate, closeTo(0.01, 1e-9));
      expect(entries[0].color, GachaTokens.dark.fiveStar);
      expect(entries[1].name, '4★');
      expect(entries[1].count, 9);
      expect(entries[2].name, '3★');
      expect(entries[2].count, 90);
    });

    test('keeps zero-count entries (legend filters them itself)', () {
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries, hasLength(3));
      expect(entries.every((e) => e.count == 0), isTrue);
    });
  });
}
