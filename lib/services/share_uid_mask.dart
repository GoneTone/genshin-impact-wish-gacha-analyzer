/// 分享圖專用 UID 遮罩：顯示前 3 碼，其餘逐字以 `x` 取代（長度保留）。
///
/// 刻意不重用 [sanitizeUid]（前 3 + 後 3）：公開分享情境不應洩漏末碼，
/// 故政策比 log 脫敏更嚴。長度 < 3 全遮 `xxx`。
String maskUidForShare(String uid) {
  if (uid.length < 3) return 'xxx';
  if (uid.length == 3) return uid;
  return '${uid.substring(0, 3)}${'x' * (uid.length - 3)}';
}
