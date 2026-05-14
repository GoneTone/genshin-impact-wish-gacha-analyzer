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
        threeStarCount: 90,
        twoStarCount: 0,
        byItemType: {},
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

    test('包含 2★ 當 twoStarCount > 0', () {
      const stats = WishStats(
        total: 10,
        fiveStarCount: 1,
        fourStarCount: 2,
        threeStarCount: 5,
        twoStarCount: 2,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★', '2★']);
      expect(entries.last.count, 2);
      expect(entries.last.rate, closeTo(0.2, 1e-9));
      expect(entries.last.color, GachaTokens.dark.twoStar);
    });

    test('略過 2★ 當 twoStarCount == 0', () {
      const stats = WishStats(
        total: 8,
        fiveStarCount: 1,
        fourStarCount: 2,
        threeStarCount: 5,
        twoStarCount: 0,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★']);
    });

    test('threeStarCount 不再包含 2★（獨立計算）', () {
      // 之前是 threeStarCount + twoStarCount 合併渲染 — 現在獨立
      const stats = WishStats(
        total: 6,
        fiveStarCount: 0,
        fourStarCount: 1,
        threeStarCount: 3,
        twoStarCount: 2,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark);
      final three = entries.firstWhere((e) => e.name == '3★');
      expect(three.count, 3); // 不是 5
      expect(three.rate, closeTo(3 / 6, 1e-9));
      final two = entries.firstWhere((e) => e.name == '2★');
      expect(two.count, 2);
      expect(two.rate, closeTo(2 / 6, 1e-9));
    });

    test(
      'keeps zero-count entries when twoStar absent (legend filters them itself)',
      () {
        const stats = WishStats(
          total: 0,
          fiveStarCount: 0,
          fourStarCount: 0,
          threeStarCount: 0,
          twoStarCount: 0,
          byItemType: {},
        );
        final entries = rarityDistributionEntries(stats, GachaTokens.dark);
        // twoStarCount == 0 不應該出現
        expect(entries, hasLength(3));
        expect(entries.every((e) => e.count == 0), isTrue);
      },
    );
  });
}
