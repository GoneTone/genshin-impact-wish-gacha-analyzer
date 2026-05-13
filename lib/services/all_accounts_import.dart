import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';

/// 把 JSON 文字解析回 [AccountsBundle]。任何結構或型別不符都會
/// 統一拋出 [FormatException]，給 UI 顯示用。
AccountsBundle importAllAccounts(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Top-level value must be an object');
  }
  try {
    return AccountsBundle.fromJson(raw);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Failed to parse: $e');
  }
}
