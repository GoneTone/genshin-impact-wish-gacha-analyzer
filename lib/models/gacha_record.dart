/// 單筆祈願紀錄，支援 API 與本地存檔兩種來源。
class GachaRecord {
  /// 建立 [GachaRecord]。
  const GachaRecord({
    required this.id,
    required this.uid,
    required this.gachaType,
    required this.name,
    required this.itemType,
    required this.rankType,
    required this.time,
    required this.lang,
  });

  /// 紀錄唯一 ID（API 回傳的流水號字串）。
  final String id;

  /// 帳號 UID。
  final String uid;

  /// 查詢用的卡池 gacha_type（如 `'301'`、`'2000'`）。
  final String gachaType;

  /// 道具名稱。
  final String name;

  /// 道具類型（原始字串，如 `'角色'`）。
  final String itemType;

  /// 星級（3 / 4 / 5）。
  final int rankType;

  /// 抽到的時間（本地時間）。
  final DateTime time;

  /// 紀錄的語言 tag（頌願 API 無此欄位時由 fallbackLang 補上，未知時為空字串）。
  final String lang;

  /// 從 hoyoverse getGachaLog / getBeyondGachaLog API 回傳的 list 元素解析。
  ///
  /// 兩個 endpoint 的 schema 不一致：
  /// - 卡池 (getGachaLog): `name` / `gacha_type` / `lang`
  /// - 頌願 (getBeyondGachaLog): `item_name` / `op_gacha_type`（值為 schedule 級
  ///   ID 如 20021，跟我們查詢的 banner 級 gacha_type 2000/1000 不同）；
  ///   無 `lang`，故由呼叫端傳入的 [fallbackLang]（擷取 URL 的 lang）補上。
  ///
  /// 為了讓存檔 schema 對齊查詢的 banner（mergedBanners key 是 query 用的
  /// gacha_type），這裡用呼叫端傳入的 [gachaType] 覆寫，不取回傳的 op_gacha_type。
  factory GachaRecord.fromApiJson(
    Map<String, dynamic> json, {
    required String gachaType,
    String fallbackLang = '',
  }) {
    final apiLang = json['lang'] as String?;
    return GachaRecord(
      id: json['id'] as String,
      uid: json['uid'] as String,
      gachaType: gachaType,
      name: (json['name'] ?? json['item_name']) as String,
      itemType: json['item_type'] as String,
      rankType: int.parse(json['rank_type'] as String),
      time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
      lang: (apiLang == null || apiLang.isEmpty) ? fallbackLang : apiLang,
    );
  }

  /// 從本地存檔的 JSON 還原
  factory GachaRecord.fromStorageJson(Map<String, dynamic> json) {
    return GachaRecord(
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

  /// 複製本 record，可覆寫 [lang]（其餘欄位沿用原值）。
  GachaRecord copyWith({String? lang}) => GachaRecord(
    id: id,
    uid: uid,
    gachaType: gachaType,
    name: name,
    itemType: itemType,
    rankType: rankType,
    time: time,
    lang: lang ?? this.lang,
  );
}
