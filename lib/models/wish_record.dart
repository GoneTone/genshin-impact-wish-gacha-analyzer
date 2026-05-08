enum WishItemKind {
  character,
  weapon,
  unknown;

  static const _characterStrings = {
    '角色',
    'Character',
    'キャラクター',
    '캐릭터',
  };

  static const _weaponStrings = {
    '武器',
    'Weapon',
    '무기',
  };

  static WishItemKind fromItemType(String itemType, String lang) {
    if (_characterStrings.contains(itemType)) return WishItemKind.character;
    if (_weaponStrings.contains(itemType)) return WishItemKind.weapon;
    return WishItemKind.unknown;
  }
}

class WishRecord {
  const WishRecord({
    required this.id,
    required this.uid,
    required this.gachaType,
    required this.name,
    required this.itemType,
    required this.kind,
    required this.rankType,
    required this.time,
    required this.lang,
  });

  final String id;
  final String uid;
  final String gachaType;
  final String name;
  final String itemType;
  final WishItemKind kind;
  final int rankType;
  final DateTime time;
  final String lang;

  /// 從 hoyoverse getGachaLog API 回傳的 list 元素解析
  factory WishRecord.fromApiJson(Map<String, dynamic> json) {
    final lang = json['lang'] as String;
    final itemType = json['item_type'] as String;
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: json['gacha_type'] as String,
      name: json['name'] as String,
      itemType: itemType,
      kind: WishItemKind.fromItemType(itemType, lang),
      rankType: int.parse(json['rank_type'] as String),
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: lang,
    );
  }

  /// 從本地存檔的 JSON 還原（kind 重新推導，不從 JSON 讀）
  factory WishRecord.fromStorageJson(Map<String, dynamic> json) {
    final lang = json['lang'] as String;
    final itemType = json['item_type'] as String;
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: json['gacha_type'] as String,
      name: json['name'] as String,
      itemType: itemType,
      kind: WishItemKind.fromItemType(itemType, lang),
      rankType: json['rank_type'] as int,
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: lang,
    );
  }

  /// 寫入本地存檔（不存 kind，因為可從 itemType+lang 重新推導）
  Map<String, dynamic> toStorageJson() {
    final t = time;
    final timeStr =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'uid': uid,
      'gacha_type': gachaType,
      'name': name,
      'item_type': itemType,
      'rank_type': rankType,
      'time': timeStr,
      'lang': lang,
    };
  }
}
