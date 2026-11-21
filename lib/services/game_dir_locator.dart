import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:win32_registry/win32_registry.dart';

import 'log_sanitize.dart';

/// 遊戲資料夾的來源。
enum GameDirSource {
  /// 使用者在設定中指定。
  setting,

  /// 從遊戲 output_log.txt 內的資源路徑推得。
  outputLog,

  /// 從登錄檔的啟動器安裝路徑推得。
  registry,

  /// 常見預設安裝路徑。
  common,
}

/// 已確認有效的遊戲資料夾與其來源。
class GameDirLocation {
  /// 建立定位結果。
  const GameDirLocation(this.path, this.source);

  /// 遊戲資料夾（內含 `GenshinImpact_Data`）。
  final String path;

  /// 該資料夾是從哪裡找到的。
  final GameDirSource source;
}

/// 讀取登錄檔中所有 hk4e_global 解除安裝項目的 InstallPath／InstallLocation（可注入以利測試）。
typedef RegistryInstallPathReader = Future<List<String>> Function();

/// 讀取 output_log.txt 內容的函式，檔案不存在回傳 null（可注入以利測試）。
typedef OutputLogReader = Future<String?> Function();

/// 尋找並驗證原神遊戲資料夾（設定 → output_log → 登錄檔 → 常見路徑）。
class GameDirLocator {
  /// 建立 locator；各 reader 與 [commonDirs] 預設為真實登錄檔、output_log 與常見路徑。
  GameDirLocator({
    RegistryInstallPathReader? readInstallPaths,
    OutputLogReader? readOutputLog,
    List<String>? commonDirs,
  }) : _readInstallPaths = readInstallPaths ?? _readRegistryInstallPaths,
       _readOutputLog = readOutputLog ?? _readDefaultOutputLog,
       _commonDirs = commonDirs ?? _defaultCommonDirs;

  /// 網頁快取定位流程的 logger。
  static final Logger _log = Logger('gacha.webCache');

  /// 遊戲資料夾內的資料目錄名稱，同時是「有效遊戲資料夾」的判準。
  static const String _dataDirName = 'GenshinImpact_Data';

  /// 啟動器資料夾底下的遊戲子資料夾名稱。
  static const String _gameSubDir = 'Genshin Impact game';

  /// 預設常見安裝路徑（Epic 等路徑無法查證，故不列入）。
  static const List<String> _defaultCommonDirs = [
    r'C:\Program Files\Genshin Impact\games\Genshin Impact game',
    r'C:\Program Files\HoYoPlay\games\Genshin Impact game',
  ];

  /// 解除安裝項目在登錄檔的子路徑。
  static const String _uninstallPath =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

  /// 依序查詢的（hive，Uninstall 路徑）。
  static const List<(RegistryHive, String)> _registryRoots = [
    (RegistryHive.localMachine, _uninstallPath),
    (RegistryHive.currentUser, _uninstallPath),
    (
      RegistryHive.localMachine,
      r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    ),
  ];

  /// 從 output_log 抓遊戲資料夾的樣式：到 `GenshinImpact_Data` 為止的磁碟機路徑。
  static final RegExp _logPathPattern = RegExp(r'.:/.+?GenshinImpact_Data');

  /// 讀取登錄檔安裝路徑的函式。
  final RegistryInstallPathReader _readInstallPaths;

  /// 讀取 output_log 的函式。
  final OutputLogReader _readOutputLog;

  /// 常見安裝路徑清單。
  final List<String> _commonDirs;

  /// 列舉各 Uninstall 底下名稱含 `hk4e_global` 的子鍵，回傳其 InstallPath（缺則 InstallLocation）；單一 key 失敗只略過。
  static Future<List<String>> _readRegistryInstallPaths() async {
    final paths = <String>[];
    for (final (hive, path) in _registryRoots) {
      try {
        final root = Registry.openPath(hive, path: path);
        try {
          for (final name in root.subkeyNames.where(
            (n) => n.contains('hk4e_global'),
          )) {
            final value = _readInstallValue(hive, '$path\\$name');
            if (value != null) paths.add(value);
          }
        } finally {
          root.close();
        }
      } on Exception catch (e) {
        _log.warning('registry enumerate failed hive=${hive.name}', e);
      }
    }
    return paths;
  }

  /// 讀單一子鍵的 InstallPath，沒有就讀 InstallLocation；失敗回傳 null。
  static String? _readInstallValue(RegistryHive hive, String path) {
    try {
      final key = Registry.openPath(hive, path: path);
      try {
        for (final name in const ['InstallPath', 'InstallLocation']) {
          final value = key.getStringValue(name)?.trim();
          if (value != null && value.isNotEmpty) return value;
        }
      } finally {
        key.close();
      }
    } on Exception catch (e) {
      _log.warning('registry value read failed hive=${hive.name}', e);
    }
    return null;
  }

  /// 讀 `%USERPROFILE%\AppData\LocalLow\miHoYo\Genshin Impact\output_log.txt`；不存在或讀取失敗回傳 null。
  static Future<String?> _readDefaultOutputLog() async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return null;
    final file = File(
      '$home\\AppData\\LocalLow\\miHoYo\\Genshin Impact\\output_log.txt',
    );
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } on Exception catch (e) {
      _log.warning('output_log read failed', e);
      return null;
    }
  }

  /// 從 output_log 內容取第一筆資源路徑，還原成遊戲資料夾（反斜線）；沒有則 null。
  static String? gameDirFromOutputLog(String content) {
    final m = _logPathPattern.firstMatch(content);
    if (m == null) return null;
    final path = m.group(0)!.replaceAll('/', '\\');
    return path.substring(0, path.length - _dataDirName.length - 1);
  }

  /// `<gameDir>\GenshinImpact_Data\webCaches` 的路徑。
  static String webCachesPath(String gameDir) =>
      '$gameDir\\$_dataDirName\\webCaches';

  /// 有效遊戲資料夾 ⇔ `GenshinImpact_Data` 存在。
  Future<bool> _isValid(String dir) =>
      Directory('$dir\\$_dataDirName').exists();

  /// 驗證 [picked]：本身有效回傳自身；選到 `GenshinImpact_Data` 則回上一層；選到安裝根目錄則修正為遊戲子資料夾；否則 null。
  Future<String?> normalize(String picked) async {
    final dir = picked.endsWith('\\$_dataDirName')
        ? picked.substring(0, picked.length - _dataDirName.length - 1)
        : picked;
    for (final candidate in [
      dir,
      '$dir\\games\\$_gameSubDir',
      '$dir\\$_gameSubDir',
    ]) {
      if (await _isValid(candidate)) return candidate;
    }
    return null;
  }

  /// 依 [settingDir] → output_log → 登錄檔 → 常見路徑的順序找第一個有效的遊戲資料夾。
  Future<GameDirLocation?> locate({String? settingDir}) async {
    final found =
        await _firstValid(GameDirSource.setting, [?settingDir]) ??
        await _firstValid(GameDirSource.outputLog, await _safeOutputLog()) ??
        await _firstValid(GameDirSource.registry, await _safeRegistry()) ??
        await _firstValid(GameDirSource.common, _commonDirs);
    if (found == null) {
      _log.warning('game dir not found');
    } else {
      _log.info(
        'game dir resolved source=${found.source.name} '
        'path=${sanitizeFsPath(found.path)}',
      );
    }
    return found;
  }

  /// 讀 output_log 並解析出候選路徑；任何例外只記 log 並視為空清單。
  Future<List<String>> _safeOutputLog() async {
    try {
      final content = await _readOutputLog();
      final dir = content == null ? null : gameDirFromOutputLog(content);
      return [?dir];
    } catch (e) {
      _log.warning('output_log read failed', e);
      return const [];
    }
  }

  /// 讀登錄檔；任何例外只記 log 並視為空清單。
  Future<List<String>> _safeRegistry() async {
    try {
      return await _readInstallPaths();
    } catch (e) {
      _log.warning('registry read failed', e);
      return const [];
    }
  }

  /// 回傳 [candidates] 中第一個經 normalize 有效者。
  Future<GameDirLocation?> _firstValid(
    GameDirSource source,
    List<String> candidates,
  ) async {
    for (final c in candidates) {
      final dir = await normalize(c);
      if (dir != null) return GameDirLocation(dir, source);
    }
    return null;
  }
}

/// 提供 [GameDirLocator] 單例。
final gameDirLocatorProvider = Provider<GameDirLocator>(
  (ref) => GameDirLocator(),
);
