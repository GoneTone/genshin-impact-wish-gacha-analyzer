import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url_extract.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/web_cache_reader.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

/// 監看遊戲網頁快取、等待新祈願網址出現的抽象介面。
abstract class GachaUrlWatch {
  /// 對 [gameDir] 開始監看；`result` 命中時為 API 網址，取消為 null，不會 completeError。
  CaptureSession start(String gameDir);
}

/// 版本資料夾名稱格式：`2.57.0.0`。
final RegExp _versionName = RegExp(r'^\d+(\.\d+)*$');

/// 一輪掃描的可傳送結果：最新版本資料夾名稱、其內的比對結果、讀檔錯誤描述。
typedef _ScanResult = ({
  String? version,
  List<GachaUrlMatch> matches,
  String? error,
});

/// 依數字逐段比較兩個版本名稱。
int _compareVersion(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < x.length || i < y.length; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

/// 掃描 webCaches：[allVersions] 為真時讀所有版本資料夾，否則只讀版本最大的那個。
Future<_ScanResult> _scan(
  String gameDir,
  CacheFileReader read,
  bool allVersions,
) async {
  final sep = Platform.pathSeparator;
  final dir = Directory(GameDirLocator.webCachesPath(gameDir));
  final matches = <GachaUrlMatch>[];
  String? latest;
  String? error;
  try {
    if (!dir.existsSync()) {
      return (version: null, matches: matches, error: null);
    }
    final versions = <String, String>{};
    await for (final e in dir.list()) {
      final name = e.path.split(sep).last;
      if (e is Directory && _versionName.hasMatch(name)) {
        versions[name] = e.path;
      }
    }
    final names = versions.keys.toList()..sort(_compareVersion);
    if (names.isEmpty) return (version: null, matches: matches, error: null);
    latest = names.last;
    for (final name in allVersions ? names : [latest]) {
      final file = '${versions[name]}${sep}Cache${sep}Cache_Data${sep}data_2';
      try {
        matches.addAll(findGachaUrls(latin1.decode(read(file))));
      } on FileSystemException catch (e) {
        error = 'read failed: ${e.osError?.errorCode ?? e.message}';
      }
    }
  } on FileSystemException catch (e) {
    error = 'list failed: ${e.osError?.errorCode ?? e.message}';
  }
  return (version: latest, matches: matches, error: error);
}

/// 背景 isolate 內執行 [_scan]。
Future<_ScanResult> _scanInBackground(
  String gameDir,
  CacheFileReader read,
  bool allVersions,
) => Isolate.run(() => _scan(gameDir, read, allVersions));

/// 輪詢遊戲 `data_2` 網頁快取，等到出現開始監看後才新增的 authkey。
class WebCacheUrlWatch implements GachaUrlWatch {
  /// 建立監看器，[interval] 為輪詢間隔，[read] 為讀檔函式。
  WebCacheUrlWatch({
    this.interval = const Duration(seconds: 1),
    this.read = readSharedFile,
  });

  /// 輪詢間隔。
  final Duration interval;

  /// 讀檔函式，在背景 isolate 內呼叫。
  final CacheFileReader read;

  static final _log = Logger('gacha.webCache');

  @override
  CaptureSession start(String gameDir) {
    final completer = Completer<String?>();
    _run(gameDir, completer);
    return CaptureSession(
      result: completer.future,
      cancel: () async {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
  }

  /// 建立 baseline 後輪詢，直到 [completer] 完成；任何失敗只記 log。
  Future<void> _run(String gameDir, Completer<String?> completer) async {
    try {
      final baselineScan = await _scanInBackground(gameDir, read, true);
      final baseline = {for (final m in baselineScan.matches) m.authkey};
      _log.info('web cache watch started baseline=${baseline.length}');
      String? lastVersion;
      String? lastError;
      while (!completer.isCompleted) {
        await Future<void>.delayed(interval);
        if (completer.isCompleted) return;
        final scan = await _scanInBackground(gameDir, read, false);
        if (scan.version != lastVersion) {
          lastVersion = scan.version;
          _log.info('web cache version dir=${scan.version}');
        }
        if (scan.error != lastError) {
          lastError = scan.error;
          if (lastError != null) _log.warning('web cache ${scan.error}');
        }
        final hit = _pickNew(scan.matches, baseline);
        if (hit != null && !completer.isCompleted) {
          _log.info(
            'web cache hit api=${hit.isApi} url=${sanitizeUrl(hit.url)}',
          );
          completer.complete(toApiUrl(hit.url));
        }
      }
    } catch (e, st) {
      _log.severe('web cache watch crashed', e, st);
      if (!completer.isCompleted) completer.complete(null);
    }
  }

  /// 取 baseline 之外 offset 最大的 authkey；同 key 優先 API 網址。
  GachaUrlMatch? _pickNew(List<GachaUrlMatch> matches, Set<String> baseline) {
    final fresh = matches.where((m) => !baseline.contains(m.authkey)).toList();
    if (fresh.isEmpty) return null;
    final key = fresh.last.authkey;
    final same = fresh.where((m) => m.authkey == key);
    return same.lastWhere((m) => m.isApi, orElse: () => same.last);
  }
}

/// 提供 [GachaUrlWatch]，測試可覆寫。
final gachaUrlWatchProvider = Provider<GachaUrlWatch>(
  (ref) => WebCacheUrlWatch(),
);
