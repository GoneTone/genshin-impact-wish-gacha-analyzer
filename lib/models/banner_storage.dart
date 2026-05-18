import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

class BannerStorage {
  const BannerStorage({
    required this.uid,
    required this.lastUpdated,
    required this.banners,
  });

  final String uid;
  final DateTime lastUpdated; // UTC
  final Map<String, List<GachaRecord>>
  banners; // gachaType → records desc by id

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

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'last_updated': lastUpdated.toUtc().toIso8601String(),
    'banners': banners.map(
      (k, v) =>
          MapEntry(k, v.map((r) => r.toStorageJson()).toList(growable: false)),
    ),
  };

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
