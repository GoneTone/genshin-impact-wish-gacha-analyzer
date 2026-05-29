import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';

/// 建立測試用 [GachaRecord]；name／lang 必填，itemType 預設「角色」。
GachaRecord _r({
  required String name,
  required String lang,
  String itemType = '角色',
}) => GachaRecord(
  id: '1',
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: itemType,
  rankType: 5,
  time: DateTime(2025),
  lang: lang,
);

void main() {
  // 迪希雅(zh-tw) 與 Dehya(en) 對到同一 hoyowiki id c1（menu_id 2＝角色）；
  // 天空之翼 對到 w1（menu_id 4＝武器）。
  final index = HoYoWikiIndex(
    searchMap: const {
      'zh-tw::迪希雅': 'c1',
      'en::Dehya': 'c1',
      'zh-tw::天空之翼': 'w1',
    },
    entries: const {},
    menuIds: const {'c1': 2, 'w1': 4},
  );

  group('itemTypeKeyOf', () {
    test('menu_id 2 → kind:character', () {
      expect(
        itemTypeKeyOf(_r(name: '迪希雅', lang: 'zh-tw'), index),
        'kind:character',
      );
    });

    test('menu_id 4 → kind:weapon', () {
      expect(
        itemTypeKeyOf(_r(name: '天空之翼', lang: 'zh-tw', itemType: '武器'), index),
        'kind:weapon',
      );
    });

    test('跨語系同物品合併成同一 key', () {
      final zh = itemTypeKeyOf(
        _r(name: '迪希雅', lang: 'zh-tw', itemType: '角色'),
        index,
      );
      final en = itemTypeKeyOf(
        _r(name: 'Dehya', lang: 'en', itemType: 'Character'),
        index,
      );
      expect(zh, en);
      expect(zh, 'kind:character');
    });

    test('查無 menu_id → fallback 原始 itemType', () {
      expect(
        itemTypeKeyOf(
          _r(name: '未知物', lang: 'zh-tw', itemType: 'Character'),
          index,
        ),
        'Character',
      );
    });

    test('查無且原始字串為空 → 回空字串', () {
      expect(
        itemTypeKeyOf(_r(name: '未知物', lang: 'zh-tw', itemType: ''), index),
        '',
      );
    });
  });

  group('itemTypeKeyLabel', () {
    test('canonical key 轉在地化標籤；fallback 原樣', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(itemTypeKeyLabel('kind:character', l), 'Character');
      expect(itemTypeKeyLabel('kind:weapon', l), 'Weapon');
      expect(itemTypeKeyLabel('', l), l.kindUnknown);
      expect(itemTypeKeyLabel('裝扮', l), '裝扮');
    });
  });
}
