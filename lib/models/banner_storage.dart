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

  /// 全 banner 串成一條 list（OverviewPage 用）
  List<GachaRecord> get allRecords =>
      banners.values.expand((l) => l).toList(growable: false);
}
