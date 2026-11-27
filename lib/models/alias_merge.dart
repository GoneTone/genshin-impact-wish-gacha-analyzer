/// 解析帳號別名的修改時間（`alias_updated_at`）；不是合法的 ISO 8601 字串時回傳 null。
DateTime? parseAliasUpdatedAt(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// 合併帳號時，匯入方（雲端或備份檔）的別名是否該取代本機的。
///
/// 兩邊都有修改時間時較新的勝出，相同時保留本機；只有一邊有時間時以有時間的為準；
/// 都沒有（舊版留下的資料）時沿用舊規則：本機有別名就保留，沒有才用匯入方的。
/// 匯入方勝出且沒有別名，代表它的最新狀態是「已清空」。
/// 只用 `dart:core`，雲端同步會在背景 isolate 呼叫。
bool incomingAliasWins({
  required String? localAlias,
  required DateTime? localUpdatedAt,
  required String? incomingAlias,
  required DateTime? incomingUpdatedAt,
}) {
  if (localUpdatedAt != null && incomingUpdatedAt != null) {
    return incomingUpdatedAt.isAfter(localUpdatedAt);
  }
  if (incomingUpdatedAt != null) return true;
  if (localUpdatedAt != null) return false;
  final hasLocal = localAlias != null && localAlias.trim().isNotEmpty;
  final hasIncoming = incomingAlias != null && incomingAlias.trim().isNotEmpty;
  return !hasLocal && hasIncoming;
}
