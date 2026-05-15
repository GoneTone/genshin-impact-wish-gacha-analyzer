import 'dart:convert';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';

final _log = Logger('accounts.io');

/// 把 JSON 文字解析回 [AccountsBundle]。任何結構或型別不符都會
/// 統一拋出 [FormatException]，給 UI 顯示用。
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
  } on FormatException catch (e) {
    _log.warning('import failed: ${e.message}');
    rethrow;
  } catch (e, st) {
    _log.warning('import failed: parse error', e, st);
    throw FormatException('Failed to parse: $e');
  }
}
