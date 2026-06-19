import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';

void main() {
  group('luckTierFor — 90 池', () {
    test(
      '45 抽（ratio 0.5）= 歐',
      () => expect(luckTierFor(45, 90), LuckTier.lucky),
    );
    test('46 抽 = 普通', () => expect(luckTierFor(46, 90), LuckTier.average));
    test(
      '72 抽（ratio 0.8）= 普通',
      () => expect(luckTierFor(72, 90), LuckTier.average),
    );
    test('73 抽 = 非', () => expect(luckTierFor(73, 90), LuckTier.unlucky));
    test('90 抽 = 非', () => expect(luckTierFor(90, 90), LuckTier.unlucky));
    test(
      '91 抽（ratio > 1）= 非',
      () => expect(luckTierFor(91, 90), LuckTier.unlucky),
    );
  });

  group('luckTierFor — 80 池', () {
    test('40 抽 = 歐', () => expect(luckTierFor(40, 80), LuckTier.lucky));
    test('41 抽 = 普通', () => expect(luckTierFor(41, 80), LuckTier.average));
    test('64 抽 = 普通', () => expect(luckTierFor(64, 80), LuckTier.average));
    test('65 抽 = 非', () => expect(luckTierFor(65, 80), LuckTier.unlucky));
  });

  group('luckTierFor — 20 池', () {
    test('10 抽 = 歐', () => expect(luckTierFor(10, 20), LuckTier.lucky));
    test('11 抽 = 普通', () => expect(luckTierFor(11, 20), LuckTier.average));
    test('16 抽 = 普通', () => expect(luckTierFor(16, 20), LuckTier.average));
    test('17 抽 = 非', () => expect(luckTierFor(17, 20), LuckTier.unlucky));
  });

  group('luckTierFor — 70 池', () {
    test('35 抽 = 歐', () => expect(luckTierFor(35, 70), LuckTier.lucky));
    test('36 抽 = 普通', () => expect(luckTierFor(36, 70), LuckTier.average));
    test('56 抽 = 普通', () => expect(luckTierFor(56, 70), LuckTier.average));
    test('57 抽 = 非', () => expect(luckTierFor(57, 70), LuckTier.unlucky));
  });

  test('pityThreshold <= 0 防呆 = 非', () {
    expect(luckTierFor(1, 0), LuckTier.unlucky);
  });

  group('luckColorFor 對應既有語意色', () {
    const t = GachaTokens.dark;
    test(
      '歐 → stateSuccess',
      () => expect(luckColorFor(LuckTier.lucky, t), t.stateSuccess),
    );
    test(
      '普通 → stateWarning',
      () => expect(luckColorFor(LuckTier.average, t), t.stateWarning),
    );
    test(
      '非 → stateDanger',
      () => expect(luckColorFor(LuckTier.unlucky, t), t.stateDanger),
    );
  });
}
