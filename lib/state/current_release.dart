import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart'
    show httpClientProvider;

/// Logger 實例（當期版本 release notes 抓取）。
final _log = Logger('release.notes');

/// 依 version key 抓對應的 GitHub Release，自帶 in-memory cache。
///
/// 同一 `version` 重複 watch 不會重打 API；要強制重新 fetch，呼叫
/// `ref.invalidate(currentReleaseProvider(version))`。
///
/// 失敗時 future 會拋 [ReleaseCheckError] 的具體子類，UI 端用
/// `AsyncValue.when(error: ...)` 處理。
//
// Riverpod 3 預設指數退避自動重試（200ms → 6.4s），會在 dialog 顯示
// [重試] 按鈕的同時偷偷重打 API、把 AsyncError 翻成 AsyncData，違反「使用者
// 主動按重試才重 fetch」的 UX 設計（spec § 快取）。重試一律走
// ref.invalidate(currentReleaseProvider(version))。
final currentReleaseProvider = FutureProvider.family<AppRelease, String>((
  ref,
  version,
) async {
  _log.info('fetch start version=$version');
  final client = ref.read(httpClientProvider);
  try {
    final release = await fetchReleaseByVersion(
      version: version,
      client: client,
    );
    _log.info('fetch success tag=${release.tagName}');
    return release;
  } on ReleaseCheckError catch (e) {
    _log.warning('fetch failed version=$version: $e');
    rethrow;
  }
}, retry: (_, _) => null);
