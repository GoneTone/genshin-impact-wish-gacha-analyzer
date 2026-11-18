import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/logcat_url_watch.dart';

import '../helpers/wait_until.dart';

/// 祈願頁網址（logcat 裡出現的形式）。
const _pageUrl =
    'https://gs.hoyoverse.com/genshin/event/e20190909gacha-v3/index.html?'
    'win_mode=fullscreen&authkey_ver=1&sign_type=2&auth_appid=webview_gacha&'
    'authkey=K1&game_biz=hk4e_global';

/// [_pageUrl] 轉成的 API 網址。
const _apiUrl =
    'https://public-operation-hk4e-sg.hoyoverse.com/gacha_info/api/getGachaLog?'
    'win_mode=fullscreen&authkey_ver=1&sign_type=2&auth_appid=webview_gacha&'
    'authkey=K1&game_biz=hk4e_global';

/// logcat 在第一筆輸出前先寫的分隔行（實機會出現）。
const _divider = '--------- beginning of main\n';

/// 監看程序寫進暫存檔的內容：分隔行加一行 logcat。
const _hitLine =
    '$_divider'
    '11-18 10:00:05.123  4321  4400 I UnityUtils.sendUnityMessage: '
    'func :OnGetWebViewPageFinish,message:$_pageUrl\n';

/// 監看程序還在時輪詢指令多印的標記行。
const _alive = '__GW_LOGCAT_ALIVE__\n';

/// 假的 shell：依指令種類回傳預設輸出，並記錄收到的每一條指令。
class _FakeShell {
  /// 收到的指令，依序。
  final commands = <String>[];

  /// 依序回傳的手機時間輸出；用完後一直回傳最後一個。
  List<String> times = ['11-18 10:00:00.000\n'];

  /// 依序回傳的 PID；用完後一直回傳最後一個。
  List<int> pids = [1234];

  /// 依序回傳的輪詢輸出；用完後一直回傳 [_alive]。
  List<String> polls = [];

  /// 非 null 時，下一次輪詢指令會等這個 future 完成才回傳。
  Completer<void>? pollGate;

  /// 依指令前綴決定是否丟例外。
  bool Function(String command) failWhen = (_) => false;

  int _time = 0;
  int _pid = 0;
  int _poll = 0;

  /// 作為 [ShellExec] 傳入的函式。
  Future<Uint8List> exec(String command) async {
    commands.add(command);
    if (failWhen(command)) throw StateError('shell closed');
    String out;
    if (command == deviceTimeCommand) {
      out = times[_time < times.length ? _time++ : times.length - 1];
    } else if (command == logcatCleanupCommand) {
      out = '';
    } else if (command.startsWith('umask 077; setsid logcat')) {
      out = '${pids[_pid < pids.length ? _pid++ : pids.length - 1]}\n';
    } else if (command.startsWith('cat ')) {
      final gate = pollGate;
      if (gate != null) {
        pollGate = null;
        await gate.future;
      }
      out = _poll < polls.length ? polls[_poll++] : _alive;
    } else {
      throw StateError('unexpected command: $command');
    }
    return Uint8List.fromList(utf8.encode(out));
  }

  /// 收到的啟動指令。
  List<String> get starts =>
      commands.where((c) => c.startsWith('umask 077; setsid logcat')).toList();
}

/// 等 [future] 完成，逾時視為測試失敗。
Future<String?> _await(Future<String?> future) =>
    future.timeout(const Duration(seconds: 5));

void main() {
  late _FakeShell shell;

  setUp(() => shell = _FakeShell());

  /// 以短間隔啟動監看。
  Future<CaptureSession> begin() => PollingLogcatUrlWatch(
    interval: const Duration(milliseconds: 10),
  ).start(shell.exec);

  test(
    'start runs cleanup, then launches the monitor from the device time',
    () async {
      final s = await begin();
      expect(shell.commands.take(3), [
        deviceTimeCommand,
        logcatCleanupCommand,
        logcatStartCommand('11-18 10:00:00.000'),
      ]);
      await s.cancel();
    },
  );

  test(
    'start command uses the narrowed rule and never contains the raw match text',
    () {
      final c = logcatStartCommand('11-18 10:00:00.000');
      expect(
        c,
        "umask 077; setsid logcat -T '11-18 10:00:00.000' -m 1 "
        "-e 'OnGetWebViewPageFinis[h],message:https://[^ ]*auth_appid=webview_gach[a]' "
        "> '/data/local/tmp/tw.reh.genshin.gacha.url' 2>/dev/null < /dev/null & "
        "p=\$!; i=0; while [ \$i -lt 20 ] && "
        "[ \"\$(cut -d' ' -f6 /proc/\$p/stat 2>/dev/null)\" != \"\$p\" ]; "
        r'do sleep 0.05; i=$((i+1)); done; echo $p',
      );
      expect(c, isNot(contains('OnGetWebViewPageFinish,')));
      expect(c, isNot(contains('webview_gacha')));
    },
  );

  test('start command rejects a malformed since', () {
    for (final bad in [
      '11-18 10:00:00',
      "11-18 10:00:00.000'; rm -rf /",
      '2026-11-18 10:00:00.000',
      '11-18 10:00:00.000\n',
      '',
    ]) {
      expect(() => logcatStartCommand(bad), throwsArgumentError, reason: bad);
    }
  });

  test('poll command reads the temp file and reports liveness', () {
    expect(
      logcatPollCommand(1234),
      "cat '/data/local/tmp/tw.reh.genshin.gacha.url' 2>/dev/null; "
      'kill -0 1234 2>/dev/null && echo __GW_LOGCAT_ALIVE__',
    );
  });

  test('cleanup matches the rule as a fixed string, never with pkill -f', () {
    expect(logcatCleanupCommand, contains("grep -qF 'webview_gach[a]'"));
    expect(logcatCleanupCommand, contains('pidof logcat'));
    expect(
      logcatCleanupCommand,
      contains("rm -f '/data/local/tmp/tw.reh.genshin.gacha.url'"),
    );
    expect(logcatCleanupCommand, isNot(contains('pkill')));
  });

  test('hit converts the page url to the api url and cleans up', () async {
    shell.polls = [_alive, _hitLine];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    await waitUntil(() => shell.commands.last == logcatCleanupCommand);
    final hit = shell.commands.lastIndexOf(logcatPollCommand(1234));
    expect(shell.commands.sublist(hit + 1), [logcatCleanupCommand]);
    await s.cancel();
    expect(
      shell.commands.where((c) => c == logcatCleanupCommand).length,
      2,
      reason: 'cancel after a hit does not clean up again',
    );
  });

  test('hit while the monitor is still exiting is still taken', () async {
    shell.polls = ['$_hitLine$_alive'];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    await s.cancel();
  });

  test('divider only while the monitor is alive keeps waiting', () async {
    shell.polls = ['$_divider$_alive', _hitLine];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, hasLength(1));
    await s.cancel();
  });

  test(
    'content without a valid url restarts from the current device time',
    () async {
      final warnings = <String>[];
      final sub = Logger('gacha.logcat').onRecord.listen((r) {
        if (r.level >= Level.WARNING) warnings.add(r.message);
      });
      shell.times = ['11-18 10:00:00.000\n', '11-18 10:05:00.000\n'];
      shell.pids = [1234, 5678];
      shell.polls = ['garbage line without a url\n', _alive, _hitLine];
      final s = await begin();
      expect(await _await(s.result), _apiUrl);
      expect(shell.starts, [
        logcatStartCommand('11-18 10:00:00.000'),
        logcatStartCommand('11-18 10:05:00.000'),
      ]);
      expect(shell.commands, contains(logcatPollCommand(5678)));
      expect(warnings, ['logcat hit without a valid url, restarting from now']);
      await s.cancel();
      await sub.cancel();
    },
  );

  test('dead monitor without content restarts from the same since', () async {
    final infos = <String>[];
    final sub = Logger('gacha.logcat').onRecord.listen((r) {
      infos.add(r.message);
    });
    shell.pids = [1234, 5678];
    shell.polls = ['', _alive, _hitLine];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, [
      logcatStartCommand('11-18 10:00:00.000'),
      logcatStartCommand('11-18 10:00:00.000'),
    ]);
    expect(
      shell.commands.where((c) => c == deviceTimeCommand).length,
      1,
      reason: 'the same since is reused',
    );
    expect(shell.commands, contains(logcatPollCommand(5678)));
    expect(infos, contains('logcat monitor gone, restarting restarts=1'));
    await s.cancel();
    await sub.cancel();
  });

  test('cleanup runs before every launch', () async {
    shell.pids = [1, 2, 3];
    shell.polls = ['', 'not a url\n', _hitLine];
    final s = await begin();
    await _await(s.result);
    expect(shell.starts, hasLength(3));
    for (var i = 0; i < shell.commands.length; i++) {
      if (shell.commands[i].startsWith('umask 077; setsid logcat')) {
        expect(shell.commands[i - 1], logcatCleanupCommand);
      }
    }
    await s.cancel();
  });

  test('exec failures keep waiting and recover', () async {
    final warnings = <String>[];
    final sub = Logger('gacha.logcat').onRecord.listen((r) {
      if (r.level >= Level.WARNING) warnings.add(r.message);
    });
    var failures = 3;
    shell.failWhen = (c) => c.startsWith('cat ') && failures-- > 0;
    shell.polls = [_hitLine];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, hasLength(1));
    expect(
      warnings.first,
      'logcat poll failed phase=check pid=1234 since=11-18 10:00:00.000 '
      'error=StateError',
    );
    await s.cancel();
    await sub.cancel();
  });

  test(
    'partial line with the marker glued on neither completes nor restarts',
    () async {
      final line = _hitLine.substring(_divider.length);
      final inAuthkey = line.substring(0, line.indexOf('authkey=K1') + 9);
      final beforeAppId = line.substring(0, line.indexOf('auth_appid'));
      shell.polls = [
        '$_divider$inAuthkey$_alive',
        '$_divider$beforeAppId$_alive',
        _hitLine,
      ];
      final s = await begin();
      expect(await _await(s.result), _apiUrl);
      expect(shell.starts, hasLength(1));
      await s.cancel();
    },
  );

  test('poll output with CRLF line endings is understood', () async {
    String crlf(String s) => s.replaceAll('\n', '\r\n');
    shell.polls = [crlf(_alive), crlf('$_divider$_alive'), crlf(_hitLine)];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, hasLength(1));
    await s.cancel();
  });

  test('a non-positive pid is rejected and the launch retried', () async {
    shell.pids = [0, -1, 1234];
    shell.polls = [_hitLine];
    final s = await begin();
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, hasLength(3));
    expect(shell.commands, isNot(contains(logcatPollCommand(0))));
    expect(shell.commands, isNot(contains(logcatPollCommand(-1))));
    await s.cancel();
  });

  test(
    'cancel during a poll that finds the monitor gone does not relaunch',
    () async {
      final gate = Completer<void>();
      shell.pollGate = gate;
      shell.polls = [''];
      final s = await begin();
      await waitUntil(() => shell.commands.last.startsWith('cat '));
      final at = shell.commands.length;
      final cancel = s.cancel();
      gate.complete();
      await cancel.timeout(const Duration(seconds: 5));
      expect(shell.commands.sublist(at), [logcatCleanupCommand]);
      expect(await _await(s.result), isNull);
    },
  );

  test('device time failure retries on the next poll', () async {
    var failures = 1;
    shell.failWhen = (c) => c == deviceTimeCommand && failures-- > 0;
    shell.times = ['date: bad format\n', '11-18 10:00:00.000\n'];
    shell.polls = [_hitLine];
    final s = await begin();
    expect(shell.starts, isEmpty);
    expect(await _await(s.result), _apiUrl);
    expect(shell.starts, [logcatStartCommand('11-18 10:00:00.000')]);
    await s.cancel();
  });

  test(
    'cancel waits for the in-flight poll, then cleans up and resolves null',
    () async {
      final gate = Completer<void>();
      shell.pollGate = gate;
      final s = await begin();
      await waitUntil(() => shell.commands.last.startsWith('cat '));
      var cancelled = false;
      final cancel = s.cancel().then((_) => cancelled = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cancelled, isFalse);
      expect(shell.commands.last, startsWith('cat '));
      gate.complete();
      await cancel.timeout(const Duration(seconds: 5));
      expect(shell.commands.last, logcatCleanupCommand);
      expect(await _await(s.result), isNull);
      final count = shell.commands.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        shell.commands,
        hasLength(count),
        reason: 'no polling after cancel',
      );
    },
  );

  test(
    'commands sent never contain OnGetWebViewPageFinish, or webview_gacha',
    () async {
      shell.times = ['11-18 10:00:00.000\n', '11-18 10:05:00.000\n'];
      shell.pids = [1, 2, 3];
      shell.polls = ['', 'not a url\n', _hitLine];
      final s = await begin();
      await _await(s.result);
      await s.cancel();
      expect(shell.commands, isNotEmpty);
      for (final c in shell.commands) {
        expect(c, isNot(contains('OnGetWebViewPageFinish,')));
        expect(c, isNot(contains('webview_gacha')));
      }
    },
  );
}
