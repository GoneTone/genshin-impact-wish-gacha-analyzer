import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';

/// 把 JSON 文字解析回 [AllAccountsBundle]。任何結構或型別不符都會
/// 統一拋出 [FormatException]，給 UI 顯示用。
AllAccountsBundle importAllAccounts(String text) {
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
    return AllAccountsBundle.fromJson(raw);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Failed to parse: $e');
  }
}
