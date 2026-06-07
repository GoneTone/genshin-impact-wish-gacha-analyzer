/// 分享圖專用 UID 遮罩：顯示前 3 碼，其餘逐字以 `•` 取代（長度保留）。
///
/// 用 `•`（U+2022）而非 `*`：星號在多數字體裡靠上緣繪製，與數字並排時會偏高；
/// 圓點垂直置中，與前 3 碼對齊較自然。
///
/// 刻意不重用 [sanitizeUid]（前 3 + 後 3）：公開分享情境不應洩漏末碼，
/// 故政策比 log 脫敏更嚴。長度 < 3 全遮 `•••`。
String maskUidForShare(String uid) {
  if (uid.length < 3) return '•••';
  if (uid.length == 3) return uid;
  return '${uid.substring(0, 3)}${'•' * (uid.length - 3)}';
}
