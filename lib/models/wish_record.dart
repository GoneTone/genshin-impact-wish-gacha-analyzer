class WishRecord {
  const WishRecord({
    required this.id,
    required this.uid,
    required this.gachaType,
    required this.name,
    required this.itemType,
    required this.rankType,
    required this.time,
    required this.lang,
  });

  final String id;
  final String uid;
  final String gachaType;
  final String name;
  final String itemType;
  final int rankType;
  final DateTime time;
  final String lang;

  /// 從 hoyoverse getGachaLog / getBeyondGachaLog API 回傳的 list 元素解析。
  ///
  /// 兩個 endpoint 的 schema 不一致：
  /// - 祈願 (getGachaLog): `name` / `gacha_type` / `lang`
  /// - 頌願 (getBeyondGachaLog): `item_name` / `op_gacha_type`（值為 schedule 級
  ///   ID 如 20021，跟我們查詢的 banner 級 gacha_type 2000/1000 不同）；無 `lang`
  ///
  /// 為了讓存檔 schema 對齊查詢的 banner（mergedBanners key 是 query 用的
  /// gacha_type），這裡用呼叫端傳入的 [gachaType] 覆寫，不取回傳的 op_gacha_type。
  factory WishRecord.fromApiJson(
    Map<String, dynamic> json, {
    required String gachaType,
  }) {
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: gachaType,
      name: (json['name'] ?? json['item_name']) as String,
      itemType: json['item_type'] as String,
      rankType: int.parse(json['rank_type'] as String),
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: (json['lang'] as String?) ?? '',
    );
  }

  /// 從本地存檔的 JSON 還原
  factory WishRecord.fromStorageJson(Map<String, dynamic> json) {
    return WishRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: json['gacha_type'] as String,
      name: json['name'] as String,
      itemType: json['item_type'] as String,
      rankType: json['rank_type'] as int,
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: json['lang'] as String,
    );
  }

  /// 寫入本地存檔
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
