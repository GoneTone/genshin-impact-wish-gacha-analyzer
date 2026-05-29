import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// 角色類型聚合鍵；以 `kind:` 前綴與遊戲原始 itemType 字串（角色／Character…）區隔，
/// 永不碰撞。
const kItemKindCharacter = 'kind:character';

/// 武器類型聚合鍵。
const kItemKindWeapon = 'kind:weapon';

/// 解析單筆 [r] 的類型聚合鍵：以 HoYoWiki [index] 的 menu_id 判定（2＝角色、
/// 4＝武器），跨語系自然合併；查不到時 fallback 回原始 `itemType` 字串（含空字串）。
String itemTypeKeyOf(GachaRecord r, HoYoWikiIndex index) {
  final id = index.lookupId(name: r.name, lang: r.lang);
  final menuId = id == null ? null : index.lookupMenuId(id);
  return switch (menuId) {
    2 => kItemKindCharacter,
    4 => kItemKindWeapon,
    _ => r.itemType,
  };
}

/// 將 [key]（[itemTypeKeyOf] 產物）轉成顯示用在地化標籤：canonical 鍵套
/// [l] 譯名、空字串顯示「未知」、其餘原始字串 fallback 原樣顯示。
String itemTypeKeyLabel(String key, AppLocalizations l) => switch (key) {
  kItemKindCharacter => l.kindCharacter,
  kItemKindWeapon => l.kindWeapon,
  '' => l.kindUnknown,
  _ => key,
};
