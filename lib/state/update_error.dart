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
