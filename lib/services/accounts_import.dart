import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';

/// Logger 實例（帳號匯入/匯出）。
final _log = Logger('accounts.io');

/// 把 JSON 文字解析回 [AccountsBundle]。
/// 版本號過新時拋出 [UnsupportedSchemaVersionException]；
/// 其餘結構／型別不符時統一拋出 [FormatException]，給 UI 顯示用。
AccountsBundle importAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (e) {
    _log.warning('import failed: invalid JSON ($e)');
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    _log.warning('import failed: top-level not an object');
    throw const FormatException('Top-level value must be an object');
  }
  try {
    return AccountsBundle.fromJson(raw);
  } on UnsupportedSchemaVersionException catch (e) {
    _log.warning('import failed: unsupported schema version ${e.version}');
    rethrow;
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
}
