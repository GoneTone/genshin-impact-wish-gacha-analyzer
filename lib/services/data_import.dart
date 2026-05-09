import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

/// 把 JSON 字串還原為 [BannerStorage]。任何結構或型別不符都丟 [FormatException]。
BannerStorage importJson(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    throw const FormatException('Invalid JSON');
  }
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Top-level value must be an object');
  }
  if (raw['uid'] is! String) {
    throw const FormatException('Missing or invalid "uid"');
  }
  if (raw['last_updated'] is! String) {
    throw const FormatException('Missing or invalid "last_updated"');
  }
  if (raw['banners'] is! Map) {
    throw const FormatException('Missing or invalid "banners"');
  }
  try {
    return BannerStorage.fromJson(raw);
  } catch (e) {
    throw FormatException('Failed to parse: $e');
  }
}
