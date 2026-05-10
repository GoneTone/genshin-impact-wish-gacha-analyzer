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
    test('returns character + weapon when no unknown', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 100,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 38,
        weaponCount: 62,
        unknownCount: 0,
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(2));
      expect(entries[0].name, l.kindCharacter);
      expect(entries[0].count, 38);
      expect(entries[0].rate, closeTo(0.38, 1e-9));
      expect(entries[1].name, l.kindWeapon);
      expect(entries[1].count, 62);
    });

    test('appends unknown row when unknownCount > 0', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 10,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 4,
        weaponCount: 5,
        unknownCount: 1,
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(3));
      expect(entries.last.name, l.kindUnknown);
      expect(entries.last.count, 1);
      expect(entries.last.rate, closeTo(0.1, 1e-9));
    });

    test('zero total → unknown rate is 0 (no division)', () async {
      final l = await _loadL10n();
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarOrBelowCount: 0,
        characterCount: 0,
        weaponCount: 0,
        unknownCount: 0,
      );
      final entries = itemTypeDistributionEntries(stats, GachaTokens.dark, l);
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.rate == 0.0), isTrue);
    });
  });
}
