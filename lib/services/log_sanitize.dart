/// 把 authkey / authkey_ver / sign_type / game_biz 等敏感 query value 改成 `***`,
/// 其餘 query 保留。malformed URL 回 `<malformed url>`。
String sanitizeUrl(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return '<malformed url>';
  }
  if (uri.host.isEmpty && uri.scheme.isEmpty) {
    return '<malformed url>';
  }
  const redactKeys = {'authkey', 'authkey_ver', 'sign_type', 'game_biz'};
  if (uri.queryParameters.isEmpty) return uri.toString();
  // Build query string manually to avoid Uri percent-encoding the `*` markers.
  final parts = uri.queryParameters.entries.map((e) {
    final v = redactKeys.contains(e.key) ? '***' : e.value;
    return '${e.key}=$v';
  });
  final base = uri.replace(query: '').toString();
  // uri.replace(query:'') leaves a trailing '?', strip it if present.
  final baseNoQ = base.endsWith('?')
      ? base.substring(0, base.length - 1)
      : base;
  return '$baseNoQ?${parts.join('&')}';
}

/// UID 中段遮蔽:`123****890`(前 3 + 後 3)。長度 < 6 全遮 `***`。
String sanitizeUid(String uid) {
  if (uid.length < 6) return '***';
  return '${uid.substring(0, 3)}****${uid.substring(uid.length - 3)}';
}

/// log 文字中的 http(s) 網址；網址皆為末段或後接空白，以非空白序列界定邊界即足夠。
final _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

/// log 文字中任意位置的家目錄路徑：group(1) 是保留的前綴，group(2) 是使用者名稱。
///
/// 涵蓋 `C:\Users\<name>`、`file:///C:/Users/<name>`、`/Users/<name>`、`/home/<name>`；
/// 斜線開頭的形式要求前面不是網址或路徑片段，避免誤遮 `https://host/home/...`。
final _homeDirPattern = RegExp(
  r'''((?:[A-Za-z]:|(?<![\w.%:-]))[\\/](?:Users|home)[\\/])([^\\/'"\r\n]+)''',
  caseSensitive: false,
);

/// 卡池記錄檔名（`<uid>.json`、`<uid>.url.json`、`<uid>.json.tmp`）裡的 uid：group(1) 是路徑分隔符號。
final _uidFilePattern = RegExp(r'([\\/])(\d{6,})(?=\.(?:url\.)?json)');

/// 把要寫進 log 的整段文字脫敏：網址套 [sanitizeUrl]、家目錄的使用者名稱換成 `***`、
/// 卡池記錄檔名裡的 uid 套 [sanitizeUid]，其餘內容原樣保留。
///
/// `LogService` 寫入每一筆 log 前統一呼叫，涵蓋訊息、例外物件與 stack trace，
/// 呼叫端照常把例外物件傳給 `Logger` 即可。
String sanitizeLogMessage(String message) => message
    .replaceAllMapped(_urlPattern, (m) => sanitizeUrl(m.group(0)!))
    .replaceAllMapped(_homeDirPattern, (m) => '${m.group(1)}***')
    .replaceAllMapped(
      _uidFilePattern,
      (m) => '${m.group(1)}${sanitizeUid(m.group(2)!)}',
    );

/// 把檔案路徑內的 home 段 username 換成 `***`，避免 log 洩漏使用者名稱。
///
/// - Windows：`C:\Users\<name>\...` → `C:\Users\***\...`（drive letter 大小寫不敏感）
/// - macOS：`/Users/<name>/...` → `/Users/***/...`
/// - Linux：`/home/<name>/...` → `/home/***/...`
/// - 其他路徑（如 `C:\Tools\...`、`/tmp/...`）原樣返回。
String sanitizeFsPath(String raw) {
  // 三種 home prefix 各對一個 anchored regex；group(1) = prefix（保留），group(2) = username（換成 ***）
  for (final re in [
    RegExp(r'^([A-Za-z]:\\Users\\)([^\\]+)'),
    RegExp(r'^(/Users/)([^/]+)'),
    RegExp(r'^(/home/)([^/]+)'),
  ]) {
    if (re.hasMatch(raw)) {
      return raw.replaceFirstMapped(re, (m) => '${m.group(1)}***');
    }
  }
  return raw;
}
