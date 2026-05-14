import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
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
      final entries = itemTypeDistributionEntries(stats, Brightness.dark, l);
      expect(entries, hasLength(2));
      // count desc → 武器 (62) 在前
      expect(entries[0].name, '武器');
      expect(entries[0].count, 62);
      expect(entries[0].rate, closeTo(0.62, 1e-9));
      expect(entries[1].name, '角色');
      expect(entries[1].count, 38);
      // 兩個 entry 顏色不同（palette index 0 vs 1）
      expect(entries[0].color, isNot(equals(entries[1].color)));
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
      final entries = itemTypeDistributionEntries(stats, Brightness.dark, l);
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
      final entries = itemTypeDistributionEntries(stats, Brightness.dark, l);
      expect(entries, isEmpty);
    });

    test('項目數 > palette 大小 → 顏色循環使用 palette', () async {
      final l = await _loadL10n();
      // palette 有 6 種顏色，這裡放 7 種讓最後一筆走回 index 0
      const stats = WishStats(
        total: 28,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {'a': 7, 'b': 6, 'c': 5, 'd': 4, 'e': 3, 'f': 2, 'g': 1},
      );
      final entries = itemTypeDistributionEntries(stats, Brightness.dark, l);
      expect(entries, hasLength(7));
      // 第 0 筆與第 6 筆顏色相同（palette index 0 與 6 % 6 = 0）
      expect(entries[0].color, entries[6].color);
    });

    test('dark / light 兩種 brightness 使用不同 palette', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 2,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {'角色': 2},
      );
      final dark = itemTypeDistributionEntries(stats, Brightness.dark, l);
      final light = itemTypeDistributionEntries(stats, Brightness.light, l);
      expect(dark.first.color, isNot(equals(light.first.color)));
    });
  });
}
