import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';

Future<AppLocalizations> _loadL10n() async {
  return AppLocalizations.delegate.load(const Locale('zh', 'Hant'));
}

void main() {
  group('itemTypeDistributionEntries', () {
    test('依 byItemType count desc 動態建立 entries', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 100,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {'角色': 38, '武器': 62},
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(2));
      // count desc → 武器 (62) 在前
      expect(entries[0].name, '武器');
      expect(entries[0].count, 62);
      expect(entries[0].rate, closeTo(0.62, 1e-9));
      expect(entries[0].color, GachaTokens.dark.character);
      expect(entries[1].name, '角色');
      expect(entries[1].count, 38);
      expect(entries[1].color, GachaTokens.dark.weapon);
    });

    test('未知（空字串）itemType 顯示為 l.kindUnknown', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 10,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {'角色': 4, '武器': 5, '': 1},
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(3));
      // 排序 desc by count: 武器 (5), 角色 (4), '' (1)
      expect(entries.last.name, l.kindUnknown);
      expect(entries.last.count, 1);
      expect(entries.last.rate, closeTo(0.1, 1e-9));
    });

    test('total=0 → entries 全部 rate=0（不除以零）', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {},
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, isEmpty);
    });

    test('項目數 > palette 大小 → 顏色循環使用 palette', () async {
      final l = await _loadL10n();
      // palette 有 7 種顏色，這裡放 8 種讓最後一筆走回 index 0
      const stats = WishStats(
        total: 36,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {
          'a': 8,
          'b': 7,
          'c': 6,
          'd': 5,
          'e': 4,
          'f': 3,
          'g': 2,
          'h': 1,
        },
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(8));
      // 第 0 筆與第 7 筆顏色相同（palette index 0 與 7 % 7 = 0）
      expect(entries[0].color, entries[7].color);
    });
  });
}
