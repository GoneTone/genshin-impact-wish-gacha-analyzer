import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 卡池分類：一般祈願或頌願。
enum GachaCategory {
  /// 一般祈願（getGachaLog API）。
  gacha,

  /// 頌願（getBeyondGachaLog API）。
  odes,
}

/// 保底規則：指定 rank 的抽數門檻。
class PityRule {
  /// 建立 [PityRule]。
  const PityRule({required this.rank, required this.threshold});

  /// 觸發保底的星級。
  final int rank;

  /// 觸發保底所需的抽數。
  final int threshold;
}

/// 卡池類型定義，含 API gacha_type、名稱 i18n key、分類與保底規則。
class GachaType {
  /// 建立 [GachaType]。
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

  /// gacha = getGachaLog，odes = getBeyondGachaLog。
  final GachaCategory category;

  /// 由高 rank 到低 rank。[0] 為主保底，[1] 為副保底（若有）。
  final List<PityRule> pities;

  /// 主保底（[pities] 第一條）。
  PityRule get primaryPity => pities.first;

  /// 副保底（若 [pities] 長度 > 1），否則 null。
  PityRule? get secondaryPity => pities.length > 1 ? pities[1] : null;

  /// 將 [nameKey] 對應到目前語言的顯示字串。
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

/// 五星保底 90 抽（角色、綜合、常駐、無暇）。
const _pityFive90 = PityRule(rank: 5, threshold: 90);

/// 五星保底 80 抽（武器）。
const _pityFive80 = PityRule(rank: 5, threshold: 80);

/// 五星保底 70 抽（頌願活動）。
const _pityFive70 = PityRule(rank: 5, threshold: 70);

/// 五星保底 20 抽（新手）。
const _pityFive20 = PityRule(rank: 5, threshold: 20);

/// 四星保底 70 抽（頌願常駐）。
const _pityFour70 = PityRule(rank: 4, threshold: 70);

/// 四星保底 10 抽（一般祈願）。
const _pityFour10 = PityRule(rank: 4, threshold: 10);

/// 三星保底 5 抽（頌願常駐）。
const _pityThree5 = PityRule(rank: 3, threshold: 5);

/// 全部支援的卡池類型定義，順序對應側欄顯示順序。
const gachaTypes = <GachaType>[
  GachaType(
    gachaType: '301',
    nameKey: 'gachaTypeCharacter',
    category: GachaCategory.gacha,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '302',
    nameKey: 'gachaTypeWeapon',
    category: GachaCategory.gacha,
    pities: [_pityFive80, _pityFour10],
  ),
  GachaType(
    gachaType: '500',
    nameKey: 'gachaTypeChronicled',
    category: GachaCategory.gacha,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '200',
    nameKey: 'gachaTypeStandard',
    category: GachaCategory.gacha,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '100',
    nameKey: 'gachaTypeBeginner',
    category: GachaCategory.gacha,
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

/// 可做資料語言轉換的 gacha_type 集合（非頌願；物品落在 HoYoWiki menu 2／4）。
/// 由 [gachaTypes] 依 category 衍生（DRY），與 `_fetchHoYoWiki` 的
/// `hoyoWikiTargetGachaTypes` 一致。
final Set<String> convertibleGachaTypes = {
  for (final t in gachaTypes)
    if (t.category == GachaCategory.gacha) t.gachaType,
};
