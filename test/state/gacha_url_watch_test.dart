import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url_extract.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/web_cache_reader.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_url_watch.dart';

/// 直接讀檔的 reader；頂層函式才能送進背景 isolate。
Uint8List _plainRead(String path) => File(path).readAsBytesSync();

/// 同目錄存在 `fail.flag` 時丟 [FileSystemException]，模擬檔案暫時讀不到。
Uint8List _flakyRead(String path) {
  final sep = Platform.pathSeparator;
  final dir = path.substring(0, path.lastIndexOf(sep));
  if (File('$dir${sep}fail.flag').existsSync()) {
    throw const FileSystemException('locked');
  }
  return File(path).readAsBytesSync();
}

/// 頁面網址。
String _page(String key) =>
    'https://webstatic.hoyoverse.com/genshin/event/e20190909gacha-v3/index.html'
    '?auth_appid=webview_gacha&authkey=$key&gacha_type=301#/log';

/// API 網址。
String _api(String key) =>
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog'
    '?auth_appid=webview_gacha&authkey=$key&gacha_type=301&size=5';

/// 把網址以二進位雜訊包起來寫成假的 data_2。
void _writeCache(Directory versionDir, List<String> urls) {
  final sep = Platform.pathSeparator;
  final file = File('${versionDir.path}${sep}Cache${sep}Cache_Data${sep}data_2')
    ..createSync(recursive: true);
  final text = urls.map((u) => '\u0000\u0001ÿ$u\u0000').join('\u0002');
  file.writeAsBytesSync(latin1.encode(text));
}

/// 等到 [cond] 成立，最多 5 秒。
Future<bool> _waitUntil(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return cond();
}

void main() {
  late Directory tmp;
  late String gameDir;
  late Directory webCaches;
  CaptureSession? session;

  Directory ver(String name) =>
      Directory('${webCaches.path}${Platform.pathSeparator}$name');

  final records = <LogRecord>[];
  StreamSubscription<LogRecord>? logSub;

  /// 等到 baseline 建立完成的 log 出現。
  Future<void> waitStarted() async {
    expect(
      await _waitUntil(
        () =>
            records.any((r) => r.message.startsWith('web cache watch started')),
      ),
      isTrue,
    );
  }

  setUp(() {
    records.clear();
    logSub = Logger.root.onRecord
        .where((r) => r.loggerName == 'gacha.webCache')
        .listen(records.add);
    tmp = Directory.systemTemp.createTempSync('url_watch_');
    gameDir = '${tmp.path}${Platform.pathSeparator}game';
    webCaches = Directory(GameDirLocator.webCachesPath(gameDir))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    await session?.cancel();
    session = null;
    await logSub?.cancel();
    tmp.deleteSync(recursive: true);
  });

  CaptureSession startWatch({CacheFileReader read = _plainRead}) =>
      session = WebCacheUrlWatch(
        interval: const Duration(milliseconds: 20),
        read: read,
      ).start(gameDir);

  test('ignores authkeys present at start', () async {
    _writeCache(ver('2.57.0.0'), [_page('K1'), _api('K1')]);
    final s = startWatch();
    await waitStarted();
    var done = false;
    final result = s.result.whenComplete(() => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(done, isFalse);
    await s.cancel();
    expect(await result, isNull);
  });

  test('prefers api url for a new authkey', () async {
    _writeCache(ver('2.57.0.0'), [_page('K1'), _api('K1')]);
    final s = startWatch();
    await waitStarted();
    _writeCache(ver('2.57.0.0'), [
      _page('K1'),
      _api('K1'),
      _page('K2'),
      _api('K2'),
    ]);
    expect(await s.result, toApiUrl(_api('K2')));
  });

  test('converts page-only url', () async {
    _writeCache(ver('2.57.0.0'), [_api('K1')]);
    final s = startWatch();
    await waitStarted();
    _writeCache(ver('2.57.0.0'), [_api('K1'), _page('K3')]);
    expect(await s.result, toApiUrl(_page('K3')));
  });

  test('new version folder counts as new, old keys stay ignored', () async {
    _writeCache(ver('2.57.0.0'), [_api('K1')]);
    final s = startWatch();
    await waitStarted();
    _writeCache(ver('2.58.0.0'), [_api('K4'), _api('K1')]);
    expect(await s.result, toApiUrl(_api('K4')));
  });

  test('missing webCaches then created', () async {
    webCaches.deleteSync(recursive: true);
    final s = startWatch();
    await waitStarted();
    _writeCache(ver('2.57.0.0'), [_api('K5')]);
    expect(await s.result, toApiUrl(_api('K5')));
  });

  test('numeric version ordering and non-version folders', () async {
    _writeCache(ver('2.57.0.0'), [_api('K0')]);
    _writeCache(ver('2.9.0.0'), [_api('K0')]);
    final s = startWatch();
    await waitStarted();
    _writeCache(ver('2.9.0.0'), [_api('K0'), _api('K6')]);
    _writeCache(ver('2.57.0.0'), [_api('K0'), _api('K7')]);
    _writeCache(ver('tmp'), [_api('K8')]);
    expect(await s.result, toApiUrl(_api('K7')));
  });

  /// 在 [v] 的快取資料夾放置／移除 `fail.flag`，讓 [_flakyRead] 失敗或恢復。
  File flagOf(Directory v) {
    final sep = Platform.pathSeparator;
    return File('${v.path}${sep}Cache${sep}Cache_Data${sep}fail.flag');
  }

  bool hasWarning() => records.any((r) => r.level >= Level.WARNING);

  test('read failure after baseline keeps watching', () async {
    final v = ver('2.57.0.0');
    _writeCache(v, [_api('K1')]);
    final s = startWatch(read: _flakyRead);
    var done = false;
    final result = s.result.whenComplete(() => done = true);
    await waitStarted();
    final flag = flagOf(v)..createSync();
    expect(await _waitUntil(hasWarning), isTrue);
    expect(done, isFalse);
    _writeCache(v, [_api('K1'), _api('K9')]);
    flag.deleteSync();
    expect(await result, toApiUrl(_api('K9')));
  });

  test('baseline read failure is retried, old keys never returned', () async {
    final v = ver('2.57.0.0');
    _writeCache(v, [_api('K2'), _api('K1')]);
    final flag = flagOf(v)..createSync();
    final s = startWatch(read: _flakyRead);
    var done = false;
    final result = s.result.whenComplete(() => done = true);
    expect(await _waitUntil(hasWarning), isTrue);
    flag.deleteSync();
    await waitStarted();
    expect(done, isFalse);
    _writeCache(v, [_api('K2'), _api('K1'), _api('K10')]);
    expect(await result, toApiUrl(_api('K10')));
  });
}
