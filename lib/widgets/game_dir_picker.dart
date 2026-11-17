import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 選擇遊戲資料夾的結果。
enum GameDirPickOutcome {
  /// 已驗證並存進設定。
  saved,

  /// 使用者取消選擇。
  cancelled,

  /// 選到的資料夾裡找不到遊戲。
  invalid,
}

/// 選資料夾流程的 logger。
final Logger _log = Logger('gacha.webCache');

/// 開啟選資料夾視窗，用 [GameDirLocator.normalize] 驗證後存進設定。
///
/// [pickDirectory] 預設為系統選資料夾視窗，測試可注入替身。
Future<GameDirPickOutcome> pickAndSaveGameDir(
  WidgetRef ref, {
  Future<String?> Function()? pickDirectory,
}) async {
  final locator = ref.read(gameDirLocatorProvider);
  final settings = ref.read(settingsProvider.notifier);
  final picked = await (pickDirectory ?? getDirectoryPath)();
  if (picked == null) return GameDirPickOutcome.cancelled;
  final dir = await locator.normalize(picked);
  if (dir == null) {
    _log.info('game dir pick rejected path=${sanitizeFsPath(picked)}');
    return GameDirPickOutcome.invalid;
  }
  // 使用者已明確選好資料夾；即使 widget 已卸載仍存檔，只是呼叫端不再有 UI 可更新。
  await settings.setGameDir(dir);
  if (!ref.context.mounted) {
    _log.info(
      'game dir saved after host unmounted path=${sanitizeFsPath(dir)}',
    );
  }
  return GameDirPickOutcome.saved;
}

/// 等待攔截期間選擇遊戲資料夾：存檔成功後重啟網頁快取監看（基準點從此刻起算）。
Future<GameDirPickOutcome> pickGameDirAndRewatch(
  WidgetRef ref, {
  Future<String?> Function()? pickDirectory,
}) async {
  final repository = ref.read(gachaRepositoryProvider.notifier);
  final outcome = await pickAndSaveGameDir(ref, pickDirectory: pickDirectory);
  if (outcome == GameDirPickOutcome.saved) {
    await repository.restartWebCacheWatch();
  }
  return outcome;
}
