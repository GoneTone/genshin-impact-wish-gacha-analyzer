import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;

/// 依 version key 抓對應的 GitHub Release，自帶 in-memory cache。
///
/// 同一 `version` 重複 watch 不會重打 API；要強制重新 fetch，呼叫
/// `ref.invalidate(currentReleaseProvider(version))`。
///
/// 失敗時 future 會拋 [ReleaseCheckError] 的具體子類，UI 端用
/// `AsyncValue.when(error: ...)` 處理。
final currentReleaseProvider = FutureProvider.family<AppRelease, String>((
  ref,
  version,
) async {
  Logger('release.notes').info('fetch start version=$version');
  final client = ref.read(httpClientProvider);
  try {
    final release = await fetchReleaseByVersion(
      version: version,
      client: client,
    );
    Logger('release.notes').info('fetch success tag=${release.tagName}');
    return release;
  } on ReleaseCheckError catch (e) {
    Logger('release.notes').warning('fetch failed version=$version: $e');
    rethrow;
  }
});
