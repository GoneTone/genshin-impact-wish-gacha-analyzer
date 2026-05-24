/// 更新流程的錯誤類型，dialog 端用 i18n 解析顯示。
sealed class UpdateError {
  const UpdateError();
}

/// 認證已過期（需重新捕獲 URL）。
class UpdateErrorAuthExpired extends UpdateError {
  /// 建立 [UpdateErrorAuthExpired]。
  const UpdateErrorAuthExpired();
}

/// 觸發 API rate limit。
class UpdateErrorRateLimited extends UpdateError {
  /// 建立 [UpdateErrorRateLimited]。
  const UpdateErrorRateLimited();
}

/// API 伺服器回傳錯誤。
class UpdateErrorServer extends UpdateError {
  /// 建立 [UpdateErrorServer]，[details] 為伺服器回傳的錯誤訊息。
  const UpdateErrorServer(this.details);

  /// 伺服器回傳的錯誤訊息。
  final String details;
}

/// 帳號無任何祈願紀錄。
class UpdateErrorNoRecords extends UpdateError {
  /// 建立 [UpdateErrorNoRecords]。
  const UpdateErrorNoRecords();
}

/// fallback：訊息已是 user-readable（多半來自 FormatException 等），直接顯示。
class UpdateErrorOther extends UpdateError {
  /// 建立 [UpdateErrorOther]，[message] 為直接顯示給使用者的錯誤訊息。
  const UpdateErrorOther(this.message);

  /// 直接顯示給使用者的錯誤訊息。
  final String message;
}

/// 強制重抓 HoYoWiki 圖片時，清空 index 或 cache 目錄階段失敗。
/// 通常是檔案被其他 process 鎖住（防毒掃描中等）。
class UpdateErrorWipeHoYoWikiCache extends UpdateError {
  /// 建立 [UpdateErrorWipeHoYoWikiCache]，[detail] 為例外訊息（已脫敏路徑）。
  const UpdateErrorWipeHoYoWikiCache(this.detail);

  /// 例外訊息；絕對路徑應在外層 emit 前以 `sanitizeFsPath` 處理。
  final String detail;
}
