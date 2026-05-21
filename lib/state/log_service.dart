import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';

/// 必須在 `main()` 用 `overrideWithValue` 注入,跟 `gachaStorageProvider` 同模式。
final logServiceProvider = Provider<LogService>((ref) {
  throw UnimplementedError('logServiceProvider must be overridden in main()');
});
