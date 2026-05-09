// lib/state/update_error.dart

/// 更新流程的錯誤類型，dialog 端用 i18n 解析顯示。
sealed class UpdateError {
  const UpdateError();
}

class UpdateErrorAuthExpired extends UpdateError {
  const UpdateErrorAuthExpired();
}

class UpdateErrorRateLimited extends UpdateError {
  const UpdateErrorRateLimited();
}

class UpdateErrorServer extends UpdateError {
  const UpdateErrorServer(this.details);
  final String details;
}

class UpdateErrorNoRecords extends UpdateError {
  const UpdateErrorNoRecords();
}

/// fallback：訊息已是 user-readable（多半來自 FormatException 等），直接顯示。
class UpdateErrorOther extends UpdateError {
  const UpdateErrorOther(this.message);
  final String message;
}
