import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/shell_exec.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_url_extract.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

/// 在手機上啟動 logcat 監看程序、等待祈願紀錄網址的抽象介面。
abstract class LogcatUrlWatch {
  /// 透過 [exec] 開始監看；`result` 命中時為 API 網址，取消為 null，永不 completeError。
  Future<CaptureSession> start(ShellExec exec);
}

/// logcat 比對規則；`[h]`、`[a]` 讓指令原文不含要比對的連續字樣，adbd 記下的指令才不會觸發自己。
const String _rule =
    'OnGetWebViewPageFinis[h],message:https://[^ ]*auth_appid=webview_gach[a]';

/// 監看程序寫入命中行的暫存檔。
const String _tempFile = '/data/local/tmp/tw.reh.genshin.gacha.url';

/// 監看程序還在時輪詢指令多印的標記行。
const String _aliveMarker = '__GW_LOGCAT_ALIVE__';

/// logcat `-T` 起點格式。
final RegExp _sincePattern = RegExp(r'^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}$');

/// 取手機目前時間作為 logcat 起點。
const String deviceTimeCommand = 'date "+%m-%d %H:%M:%S.000"';

/// 結束命令列含比對規則的 logcat 程序並刪掉暫存檔；`-F` 以固定字串比對規則原文。
///
/// 命令列先經 `tr` 再交給 grep：舊版 toybox（Android 13 的 0.8.6）grep 直接讀 `/proc/<pid>/cmdline` 會讀不到內容。
const String logcatCleanupCommand =
    'for p in \$(pidof logcat); do '
    "tr '\\0' ' ' < /proc/\$p/cmdline 2>/dev/null | grep -qF 'webview_gach[a]' && kill \$p 2>/dev/null; "
    "done; rm -f '$_tempFile'";

/// 從 [since] 起啟動監看程序並印出其 PID；[since] 不符合起點格式時丟 [ArgumentError]。
String logcatStartCommand(String since) {
  if (!_sincePattern.hasMatch(since)) {
    throw ArgumentError.value(since, 'since', 'not MM-DD hh:mm:ss.mmm');
  }
  // 啟動的 shell 若在子程序 setsid() 完成前結束，串流關閉會連同原 process group 一起結束它；等到它自成 session（/proc/<pid>/stat 第 6 欄）才印 PID
  return "umask 077; setsid logcat -T '$since' -m 1 -e '$_rule' "
      "> '$_tempFile' 2>/dev/null < /dev/null & "
      "p=\$!; i=0; while [ \$i -lt 20 ] && "
      "[ \"\$(cut -d' ' -f6 /proc/\$p/stat 2>/dev/null)\" != \"\$p\" ]; "
      r'do sleep 0.05; i=$((i+1)); done; echo $p';
}

/// 讀暫存檔，監看程序 [pid] 還在時多印一行 [_aliveMarker]。
String logcatPollCommand(int pid) =>
    "cat '$_tempFile' 2>/dev/null; "
    'kill -0 $pid 2>/dev/null && echo $_aliveMarker';

/// 以固定間隔輪詢暫存檔、必要時重啟監看程序的 [LogcatUrlWatch]。
class PollingLogcatUrlWatch implements LogcatUrlWatch {
  /// 建立 [PollingLogcatUrlWatch]，[interval] 為輪詢間隔。
  PollingLogcatUrlWatch({this.interval = const Duration(seconds: 1)});

  /// 輪詢間隔。
  final Duration interval;

  /// 本監看器的 logger。
  static final _log = Logger('gacha.logcat');

  @override
  Future<CaptureSession> start(ShellExec exec) async {
    final completer = Completer<String?>();
    String? since;
    int? pid;
    var restarts = 0;
    var polling = false;
    var cleaned = false;

    /// 執行指令並以 UTF-8 解碼輸出。
    Future<String> run(String command) async =>
        utf8.decode(await exec(command), allowMalformed: true);

    /// 結束監看程序並刪掉暫存檔。
    Future<void> cleanup() async {
      await run(logcatCleanupCommand);
      cleaned = true;
    }

    /// 沒有起點就先取手機時間，再清掉殘留並啟動監看程序；失敗留給下一輪。
    Future<void> launch() async {
      if (completer.isCompleted) return;
      if (since == null) {
        final now = (await run(deviceTimeCommand)).trim();
        if (!_sincePattern.hasMatch(now)) {
          _log.warning('device time unexpected output=$now');
          return;
        }
        since = now;
      }
      if (completer.isCompleted) return;
      await run(logcatCleanupCommand);
      if (completer.isCompleted) return;
      final out = (await run(logcatStartCommand(since!))).trim();
      final parsed = int.tryParse(out);
      if (parsed == null || parsed <= 0) {
        _log.warning('logcat start returned no pid output=$out');
        return;
      }
      pid = parsed;
      cleaned = false;
      _log.info('logcat watch started since=$since pid=$pid');
    }

    /// 讀暫存檔：命中就完成，內容不合法或監看程序不在就重啟。
    Future<void> check(int p) async {
      final out = (await run(logcatPollCommand(p))).trimRight();
      if (completer.isCompleted) return;
      // 檔案沒以換行結尾時標記會黏在最後一行，所以比對結尾而不是整行
      final alive = out.endsWith(_aliveMarker);
      final content = alive
          ? out.substring(0, out.length - _aliveMarker.length)
          : out;
      // 程序還在且最後一行沒寫完：網址可能被切斷，等下一輪
      if (alive && content.isNotEmpty && !content.endsWith('\n')) return;
      if (content.trim().isEmpty) {
        if (alive) return;
        restarts++;
        _log.info('logcat monitor gone, restarting restarts=$restarts');
        pid = null;
        return launch();
      }
      final url = latestApiUrlIn(content);
      if (url == null) {
        // logcat 先寫分隔行再寫命中行；程序還在代表還沒寫完，等它寫完自行結束
        if (alive) return;
        _log.warning('logcat hit without a valid url, restarting from now');
        since = null;
        pid = null;
        return launch();
      }
      _log.info('logcat hit url=${sanitizeUrl(url)}');
      if (!completer.isCompleted) completer.complete(url);
      await cleanup();
    }

    /// 單輪輪詢；同一時間只跑一輪，任何失敗只記 log。
    Future<void> step() async {
      if (polling || completer.isCompleted) return;
      polling = true;
      final p = pid;
      try {
        await (p == null ? launch() : check(p));
      } on Object catch (e) {
        _log.warning(
          'logcat poll failed phase=${p == null ? 'launch' : 'check'} '
          'pid=$p since=$since error=${e.runtimeType}',
        );
      } finally {
        polling = false;
      }
    }

    Future<void>? inFlight = step();
    await inFlight;
    final timer = Timer.periodic(interval, (_) {
      if (polling || completer.isCompleted) return;
      inFlight = step();
    });
    unawaited(completer.future.whenComplete(timer.cancel));

    return CaptureSession(
      result: completer.future,
      cancel: () async {
        if (!completer.isCompleted) completer.complete(null);
        timer.cancel();
        await inFlight;
        if (cleaned) return;
        try {
          await cleanup();
        } on Object catch (e) {
          _log.warning('logcat cleanup failed error=${e.runtimeType}');
        }
      },
    );
  }
}

/// 提供 [LogcatUrlWatch]，測試可覆寫。
final logcatUrlWatchProvider = Provider<LogcatUrlWatch>(
  (ref) => PollingLogcatUrlWatch(),
);
