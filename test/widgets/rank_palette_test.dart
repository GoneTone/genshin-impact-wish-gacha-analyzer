import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rank_palette.dart';

void main() {
  group('accentForRank', () {
    const tokens = GachaTokens.dark;

    test('rank 5 maps to fiveStar', () {
      expect(accentForRank(5, tokens), tokens.fiveStar);
    });

    test('rank 4 maps to fourStar', () {
      expect(accentForRank(4, tokens), tokens.fourStar);
    });

    test('rank 3 maps to threeStar', () {
      expect(accentForRank(3, tokens), tokens.threeStar);
    });

    test('rank 2 maps to twoStar', () {
      expect(accentForRank(2, tokens), tokens.twoStar);
    });

    test('rank 1 maps to oneStar', () {
      expect(accentForRank(1, tokens), tokens.oneStar);
    });

    test('rank 0 falls back to textMuted', () {
      expect(accentForRank(0, tokens), tokens.textMuted);
    });

    test('out-of-range rank 99 falls back to textMuted', () {
      expect(accentForRank(99, tokens), tokens.textMuted);
    });
  });
}
