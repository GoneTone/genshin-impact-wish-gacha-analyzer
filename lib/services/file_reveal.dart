import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// Logger 實例（檔案總管 reveal）。
final _log = Logger('ui.reveal');

/// reveal 的目標作業系統。把 [Platform] 判斷抽成 seam，讓三平台分支
/// 能在單一主機上被測試驗證。
enum RevealPlatform {
  /// Windows 桌面。
  windows,

  /// macOS 桌面。
  macos,

  /// 其他平台（退化成開父資料夾）。
  other,
}

/// 依 [Platform] 回傳當前作業系統對應的 [RevealPlatform]。
RevealPlatform _defaultPlatform() {
  if (Platform.isWindows) return RevealPlatform.windows;
  if (Platform.isMacOS) return RevealPlatform.macos;
  return RevealPlatform.other;
}

/// 以下三個 seam 預設指向真實實作；測試可覆寫成 fake 後用
/// [resetFileRevealSeams] 還原，避免測試間互相污染、也避免
/// `flutter test` 真的去開檔案總管。
@visibleForTesting
RevealPlatform Function() revealPlatform = _defaultPlatform;

/// Process.run seam，供測試注入 fake runner。
@visibleForTesting
Future<ProcessResult> Function(String exe, List<String> args)
revealProcessRunner = Process.run;

/// launchUrl seam，供測試注入 fake launcher。
@visibleForTesting
Future<bool> Function(Uri uri) revealUrlLauncher = launchUrl;

/// 還原三個 seam 到預設真實實作；測試 tearDown 使用。
@visibleForTesting
void resetFileRevealSeams() {
  revealPlatform = _defaultPlatform;
  revealProcessRunner = Process.run;
  revealUrlLauncher = launchUrl;
}

/// 開檔案總管並選中指定檔案。失敗回傳 false，呼叫端通常忽略即可
/// （reveal 是 UX 加分項，匯出本身的成功訊息應由呼叫端維持）。
///
/// - Windows：`explorer /select,<path>`
/// - macOS：`open -R <path>`
/// - 其他：沒有跨 DE 的 reveal API，退化成 [openFolder]（開父資料夾）
Future<bool> revealInFileManager(String filePath) async {
  final f = File(filePath);
  if (!await f.exists()) {
    _log.warning('reveal: file not found ${sanitizeFsPath(filePath)}');
    return false;
  }
  try {
    switch (revealPlatform()) {
      case RevealPlatform.windows:
        // /select, 後緊接路徑，逗號是語法不是分隔
        final r = await revealProcessRunner('explorer', ['/select,${f.path}']);
        // explorer.exe 即使成功也常回傳非 0；只要沒 throw 視為成功
        _log.info(
          'reveal: explorer exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
        );
        return true;
      case RevealPlatform.macos:
        final r = await revealProcessRunner('open', ['-R', f.path]);
        _log.info(
          'reveal: open -R exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
        );
        return r.exitCode == 0;
      case RevealPlatform.other:
        return openFolder(f.parent.path);
    }
  } catch (e, st) {
    _log.warning('reveal: failed ${sanitizeFsPath(filePath)}', e, st);
    return false;
  }
}

/// 純開資料夾，沿用 `launchUrl(Uri.file(...))`，跨平台。
Future<bool> openFolder(String dirPath) async {
  try {
    final ok = await revealUrlLauncher(Uri.file(dirPath));
    if (!ok) {
      _log.warning(
        'openFolder: launchUrl returned false ${sanitizeFsPath(dirPath)}',
      );
    } else {
      _log.info('openFolder: ${sanitizeFsPath(dirPath)}');
    }
    return ok;
  } catch (e, st) {
    _log.warning('openFolder: failed ${sanitizeFsPath(dirPath)}', e, st);
    return false;
  }
}
