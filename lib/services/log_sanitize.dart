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
