/// 將 bytes 數值轉成易讀字串，依大小自動選 KB / MB / GB，皆保留 1 位小數。
///
/// 規則（底數 1024，對齊 Windows 檔案總管）：
///   - `< 1 MB`           → `XXX.X KB`
///   - `1 MB ~ < 1 GB`    → `XXX.X MB`
///   - `>= 1 GB`          → `XXX.X GB`
///
/// 注意：1023 B 顯示為 `1.0 KB`（無條件先除 1024 後保留 1 位小數）；
/// 邊界以「除完是否 >= 1024.0」判定是否進位。
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes < mb) {
    return '${(bytes / kb).toStringAsFixed(1)} KB';
  }
  if (bytes < gb) {
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}
