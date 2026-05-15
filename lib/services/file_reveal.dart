import 'dart:io';

import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

final _log = Logger('ui.reveal');

/// 開檔案總管並選中指定檔案。失敗回傳 false，呼叫端通常忽略即可
/// （reveal 是 UX 加分項，匯出本身的成功訊息應由呼叫端維持）。
///
/// - Windows：`explorer /select,<path>`
/// - macOS：`open -R <path>`
/// - Linux：沒有跨 DE 的 reveal API，退化成 [openFolder]（開父資料夾）
Future<bool> revealInFileManager(String filePath) async {
  final f = File(filePath);
  if (!await f.exists()) {
    _log.warning('reveal: file not found ${sanitizeFsPath(filePath)}');
    return false;
  }
  try {
    if (Platform.isWindows) {
      // /select, 後緊接路徑，逗號是語法不是分隔
      final r = await Process.run('explorer', ['/select,${f.path}']);
      // explorer.exe 即使成功也常回傳非 0；只要沒 throw 視為成功
      _log.info(
        'reveal: explorer exit=${r.exitCode} ${sanitizeFsPath(f.path)}',
      );
      return true;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('open', ['-R', f.path]);
      _log.info('reveal: open -R exit=${r.exitCode} ${sanitizeFsPath(f.path)}');
      return r.exitCode == 0;
    }
    // Linux / 其他：fallback 到開資料夾
    return openFolder(f.parent.path);
  } catch (e, st) {
    _log.warning('reveal: failed ${sanitizeFsPath(filePath)}', e, st);
    return false;
  }
}

/// 純開資料夾，沿用 `launchUrl(Uri.file(...))`，跨平台。
Future<bool> openFolder(String dirPath) async {
  try {
    final ok = await launchUrl(Uri.file(dirPath));
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
