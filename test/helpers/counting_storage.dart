import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';

/// 記錄 [save] 次數的 [GachaStorage]，用來斷言有沒有重寫記錄檔。
class CountingStorage extends GachaStorage {
  /// 建立 [CountingStorage]。
  CountingStorage(super.baseDir);

  /// [save] 被呼叫的次數。
  int saves = 0;

  /// 計數後交給父類別寫檔。
  @override
  Future<void> save(BannerStorage data) {
    saves++;
    return super.save(data);
  }
}
