// lib/data/gacha_types.dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

class GachaType {
  const GachaType({
    required this.gachaType,
    required this.nameKey,
    required this.fiveStarPity,
    required this.fourStarPity,
  });

  /// 對應 getGachaLog API 的 query string `gacha_type=...`，String 型別跟 query 對齊。
  final String gachaType;

  /// i18n key（透過 [resolveName] 取顯示字串）。
  final String nameKey;

  /// 5★ 保底閾值（新手池為 20 = 池子總抽數，已結束）。
  final int fiveStarPity;

  /// 4★ 保底閾值（新手池無 4★ 機制，仍給 10 作 fallback）。
  final int fourStarPity;

  String resolveName(AppLocalizations l) => switch (nameKey) {
    'gachaTypeCharacter' => l.gachaTypeCharacter,
    'gachaTypeWeapon' => l.gachaTypeWeapon,
    'gachaTypeChronicled' => l.gachaTypeChronicled,
    'gachaTypeStandard' => l.gachaTypeStandard,
    'gachaTypeBeginner' => l.gachaTypeBeginner,
    _ => nameKey,
  };
}

const gachaTypes = <GachaType>[
  GachaType(
    gachaType: '301',
    nameKey: 'gachaTypeCharacter',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '302',
    nameKey: 'gachaTypeWeapon',
    fiveStarPity: 80,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '500',
    nameKey: 'gachaTypeChronicled',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '200',
    nameKey: 'gachaTypeStandard',
    fiveStarPity: 90,
    fourStarPity: 10,
  ),
  GachaType(
    gachaType: '100',
    nameKey: 'gachaTypeBeginner',
    fiveStarPity: 20,
    fourStarPity: 10,
  ),
];
