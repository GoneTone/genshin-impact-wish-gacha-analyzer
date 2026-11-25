import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

/// 單一 UID 的全卡池祈願存檔。
class BannerStorage {
  /// 建立 [BannerStorage]。
  const BannerStorage({
    required this.uid,
    required this.lastUpdated,
    required this.banners,
  });

  /// 帳號 UID。
  final String uid;

  /// 最後更新時間（UTC）。
  final DateTime lastUpdated;

  /// gacha_type → 該卡池紀錄（依 id 降序）。
  final Map<String, List<GachaRecord>> banners;

  /// 從本地存檔 JSON 還原 [BannerStorage]。
  factory BannerStorage.fromJson(Map<String, dynamic> json) {
    final bannersJson = json['banners'] as Map<String, dynamic>;
    return BannerStorage(
      uid: json['uid'] as String,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      banners: bannersJson.map(
        (k, v) => MapEntry(
          k,
          (v as List<dynamic>)
              .map(
                (e) => GachaRecord.fromStorageJson(e as Map<String, dynamic>),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  /// 序列化為本地存檔 JSON。
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'last_updated': lastUpdated.toUtc().toIso8601String(),
    'banners': banners.map(
      (k, v) =>
          MapEntry(k, v.map((r) => r.toStorageJson()).toList(growable: false)),
    ),
  };

  /// 複製並選擇性覆蓋欄位。
  BannerStorage copyWith({
    DateTime? lastUpdated,
    Map<String, List<GachaRecord>>? banners,
  }) => BannerStorage(
    uid: uid,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    banners: banners ?? this.banners,
  );

  /// 將 [incoming]（同一 UID 的另一份存檔）合併進本份，回傳新的 [BannerStorage]。
  ///
  /// 逐 banner 依 [GachaRecord.id] union 去重後降序排序；本機既有記錄一律保留，
  /// 同 id 時保留本機那筆（若本機 lang 為空、[incoming] 非空則回填 lang）。
  /// [lastUpdated] 取兩者較新者。
  BannerStorage mergeWith(BannerStorage incoming) {
    final keys = {...banners.keys, ...incoming.banners.keys};
    final mergedBanners = <String, List<GachaRecord>>{
      for (final key in keys)
        key: _mergeRecordsById(
          banners[key] ?? const [],
          incoming.banners[key] ?? const [],
        ),
    };
    final newer = incoming.lastUpdated.isAfter(lastUpdated)
        ? incoming.lastUpdated
        : lastUpdated;
    return BannerStorage(uid: uid, lastUpdated: newer, banners: mergedBanners);
  }

  /// 合併兩條同 banner 的記錄：依 id union 去重（同 id 保留 [local]，必要時以
  /// [incoming] 的非空 lang 回填）→ 依 id 降序排序（id 等長 19 碼，字典序＝數值序）。
  static List<GachaRecord> _mergeRecordsById(
    List<GachaRecord> local,
    List<GachaRecord> incoming,
  ) {
    final byId = <String, GachaRecord>{};
    for (final r in local) {
      byId[r.id] = r;
    }
    for (final r in incoming) {
      final existing = byId[r.id];
      if (existing == null) {
        byId[r.id] = r;
      } else if ((existing.lang.isEmpty && r.lang.isNotEmpty) ||
          (existing.gachaType == '301' && r.gachaType == '400')) {
        // 舊版把 API 回傳的 400 誤存成 301，這裡以傳入的 400 修正。
        byId[r.id] = existing.copyWith(
          lang: existing.lang.isEmpty && r.lang.isNotEmpty ? r.lang : null,
          gachaType: existing.gachaType == '301' && r.gachaType == '400'
              ? '400'
              : null,
        );
      }
    }
    return byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
  }

  /// 與 [other] 的內容（uid、更新時間、各卡池每筆記錄的所有欄位）是否完全相同。
  ///
  /// 合併後沒有任何變化時用來省掉寫檔與 state 替換；[GachaRecord] 刻意不定義 `==`。
  bool sameContentAs(BannerStorage other) {
    if (uid != other.uid ||
        lastUpdated != other.lastUpdated ||
        banners.length != other.banners.length) {
      return false;
    }
    for (final MapEntry(:key, :value) in banners.entries) {
      final theirs = other.banners[key];
      if (theirs == null || theirs.length != value.length) return false;
      for (var i = 0; i < value.length; i++) {
        if (!_sameRecord(value[i], theirs[i])) return false;
      }
    }
    return true;
  }

  /// 全 banner 串成一條 list（OverviewPage 用）
  List<GachaRecord> get allRecords =>
      banners.values.expand((l) => l).toList(growable: false);
}

/// 兩筆記錄的所有欄位是否相同。
bool _sameRecord(GachaRecord a, GachaRecord b) =>
    a.id == b.id &&
    a.uid == b.uid &&
    a.gachaType == b.gachaType &&
    a.name == b.name &&
    a.itemType == b.itemType &&
    a.rankType == b.rankType &&
    a.time == b.time &&
    a.lang == b.lang;
