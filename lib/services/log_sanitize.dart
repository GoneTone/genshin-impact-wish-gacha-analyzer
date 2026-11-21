import 'dart:io' show FileSystemException, SocketException;

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException;
import 'package:googleapis/drive/v3.dart' show DetailedApiRequestError;

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

/// 掃描自由文字 log 訊息中內嵌的 http(s) URL,逐段套 [sanitizeUrl] 後原位替換,
/// 非 URL 內容原樣保留。Rust log 跨橋進 Dart 時統一呼叫,作為單一脫敏匣道,
/// 避免在 Rust 端複製脫敏邏輯。
String sanitizeLogMessage(String message) {
  // log 訊息中 URL 皆為末段或後接空白,以非空白序列界定 token 邊界即足夠。
  final urlPattern = RegExp(r'https?://\S+', caseSensitive: false);
  return message.replaceAllMapped(urlPattern, (m) => sanitizeUrl(m.group(0)!));
}

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

/// 回傳可安全寫進 log 的錯誤摘要：型別，加上少數已知型別的非敏感代碼
/// （檔案／socket 的系統錯誤碼、Drive API 狀態碼、Google 授權與 platform channel 的錯誤代碼）。
///
/// 例外訊息可能帶完整檔案路徑（含使用者名稱、uid）、檔案內容片段或網址，不可直接寫進 log。
String describeErrorForLog(Object e) {
  final detail = switch (e) {
    FileSystemException(:final osError?) => 'os=${osError.errorCode}',
    SocketException(:final osError?) => 'os=${osError.errorCode}',
    DetailedApiRequestError(:final status?) => 'status=$status',
    GoogleSignInException(:final code) => 'code=${code.name}',
    PlatformException(:final code) => 'code=$code',
    _ => null,
  };
  return 'error=${e.runtimeType}${detail == null ? '' : ' $detail'}';
}
