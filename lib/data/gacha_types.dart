// lib/data/gacha_types.dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

enum GachaCategory { wish, odes }

class PityRule {
  const PityRule({required this.rank, required this.threshold});

  final int rank;
  final int threshold;
}

class GachaType {
  const GachaType({
    required this.gachaType,
    required this.nameKey,
    required this.category,
    required this.pities,
  });

  /// 對應 getGachaLog / getBeyondGachaLog API 的 query string `gacha_type=...`。
  final String gachaType;

  /// i18n key（透過 [resolveName] 取顯示字串）。
  final String nameKey;

  /// wish = getGachaLog，odes = getBeyondGachaLog。
  final GachaCategory category;

  /// 由高 rank 到低 rank。[0] 為主保底，[1] 為副保底（若有）。
  final List<PityRule> pities;

  PityRule get primaryPity => pities.first;
  PityRule? get secondaryPity => pities.length > 1 ? pities[1] : null;

  String resolveName(AppLocalizations l) => switch (nameKey) {
    'gachaTypeCharacter' => l.gachaTypeCharacter,
    'gachaTypeWeapon' => l.gachaTypeWeapon,
    'gachaTypeChronicled' => l.gachaTypeChronicled,
    'gachaTypeStandard' => l.gachaTypeStandard,
    'gachaTypeBeginner' => l.gachaTypeBeginner,
    'gachaTypeOdesEvent' => l.gachaTypeOdesEvent,
    'gachaTypeOdesStandard' => l.gachaTypeOdesStandard,
    _ => nameKey,
  };
}

const _pityFive90 = PityRule(rank: 5, threshold: 90);
const _pityFive80 = PityRule(rank: 5, threshold: 80);
const _pityFive70 = PityRule(rank: 5, threshold: 70);
const _pityFive20 = PityRule(rank: 5, threshold: 20);
const _pityFour70 = PityRule(rank: 4, threshold: 70);
const _pityFour10 = PityRule(rank: 4, threshold: 10);
const _pityThree5 = PityRule(rank: 3, threshold: 5);

const gachaTypes = <GachaType>[
  GachaType(
    gachaType: '301',
    nameKey: 'gachaTypeCharacter',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '302',
    nameKey: 'gachaTypeWeapon',
    category: GachaCategory.wish,
    pities: [_pityFive80, _pityFour10],
  ),
  GachaType(
    gachaType: '500',
    nameKey: 'gachaTypeChronicled',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '200',
    nameKey: 'gachaTypeStandard',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '100',
    nameKey: 'gachaTypeBeginner',
    category: GachaCategory.wish,
    pities: [_pityFive20, _pityFour10],
  ),
  GachaType(
    gachaType: '2000',
    nameKey: 'gachaTypeOdesEvent',
    category: GachaCategory.odes,
    pities: [_pityFive70, _pityFour10],
  ),
  GachaType(
    gachaType: '1000',
    nameKey: 'gachaTypeOdesStandard',
    category: GachaCategory.odes,
    pities: [_pityFour70, _pityThree5],
  ),
];
