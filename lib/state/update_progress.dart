import 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

export 'package:genshin_impact_wish_gacha_analyzer/state/update_error.dart';

/// 更新進度狀態：準備中、等待捕獲、拉取中、完成、失敗。
sealed class UpdateProgress {
  const UpdateProgress();
}

/// 準備階段（啟動更新、檢查快取 URL 前）。
class Preparing extends UpdateProgress {
  /// 建立 [Preparing]。
  const Preparing();
}

/// 等待 MITM 捕獲祈願 URL。
class WaitingForCapture extends UpdateProgress {
  /// 建立 [WaitingForCapture]；[isFallback] 表示 auth 過期後的二次捕獲。
  const WaitingForCapture({this.isFallback = false});

  /// 是否為 auth 過期後的二次捕獲。
  final bool isFallback;
}

/// 正在拉取指定 banner 的紀錄。
class FetchingBanner extends UpdateProgress {
  /// 建立 [FetchingBanner]。
  const FetchingBanner({
    required this.gachaType,
    required this.displayName,
    required this.pageIndex,
    required this.newRecordsSoFar,
  });

  /// 正在拉取的 gacha_type。
  final String gachaType;

  /// 顯示用的 banner 名稱 i18n key。
  final String displayName;

  /// 目前拉取的頁碼（從 1 開始）。
  final int pageIndex;

  /// 到目前為止累積的新紀錄數。
  final int newRecordsSoFar;
}

/// 更新完成。
class UpdateCompleted extends UpdateProgress {
  /// 建立 [UpdateCompleted]。
  const UpdateCompleted({
    required this.totalNewRecords,
    required this.failedBanners,
    required this.updatedAt,
  });

  /// 本次更新新增的總紀錄數。
  final int totalNewRecords;

  /// 拉取失敗的 banner 名稱 key 列表。
  final List<String> failedBanners;

  /// 更新完成時間（UTC）。
  final DateTime updatedAt;
}

/// 更新失敗。
class UpdateFailed extends UpdateProgress {
  /// 建立 [UpdateFailed]，[error] 為對應的錯誤類型。
  const UpdateFailed(this.error);

  /// 更新失敗的錯誤類型。
  final UpdateError error;
}

/// HoYoWiki 補圖階段的子步驟。
enum HoYoWikiPhase {
  /// 搜尋物品的 entry_page_id（HoYoWiki search API）。
  searching,

  /// 抓取物品詳情（HoYoWiki entry_page API）。
  fetchingEntries,

  /// 下載 icon 與 header 圖檔。
  downloading,
}

/// 主資料抓取完成後，正在補齊各物品的 HoYoWiki 圖示。
class FetchingHoYoWiki extends UpdateProgress {
  /// 建立 [FetchingHoYoWiki]。
  const FetchingHoYoWiki({
    required this.phase,
    required this.doneCount,
    required this.totalCount,
  });

  /// 目前所在的子步驟。
  final HoYoWikiPhase phase;

  /// 該子步驟目前已完成的工作項數。
  final int doneCount;

  /// 該子步驟的總工作項數。
  final int totalCount;
}
