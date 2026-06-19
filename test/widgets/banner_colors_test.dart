import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

void main() {
  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, GachaTokens.dark),
    ('light', Brightness.light, GachaTokens.light),
  ]) {
    test('$label：任一卡池色不得等於歐非三色', () {
      final colors = BannerColors.of(brightness);
      final luck = {
        tokens.stateSuccess,
        tokens.stateWarning,
        tokens.stateDanger,
      };
      for (final t in gachaTypes) {
        expect(
          luck.contains(colors.colorFor(t.gachaType)),
          isFalse,
          reason: '${t.gachaType} 撞歐非色',
        );
      }
      expect(luck.contains(colors.fallback), isFalse);
    });
  }
}
