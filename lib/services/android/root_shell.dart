import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';

/// 啟動外部程式；測試以替身取代 [Process.start]。
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// 常見 root 工具放 `su` 的位置。
const defaultSuPaths = [
  '/system/bin/su',
  '/system/xbin/su',
  '/sbin/su',
  '/su/bin/su',
  '/debug_ramdisk/su',
  '/system_ext/bin/su',
];

/// `su` 執行失敗（被拒絕、程序結束或逾時）。
class RootShellException implements Exception {
  /// 建立例外。
  RootShellException(this.message);

  /// 失敗原因。
  final String message;

  @override
  String toString() => 'RootShellException: $message';
}

/// 以一個常駐的 `su` 程序執行 root 指令。
///
/// 等待祈願紀錄時每秒要讀兩次檔，若每次都重新執行 `su -c`，root 工具每次都會跳授權提示、
/// 寫授權記錄；所以整個 session 只開一次 `su`，指令都從它的 stdin 送進去，
/// 每條指令後印一個隨機結束標記來切出輸出。
class RootShell {
  /// 建立 root shell；[start] 與 [suPaths] 僅供測試替換。
  RootShell({ProcessStarter? start, this.suPaths = defaultSuPaths})
    : _start = start ?? Process.start;

  /// 檢查 `su` 是否存在的路徑。
  final List<String> suPaths;

  /// 啟動外部程式的函式。
  final ProcessStarter _start;

  /// 讓指令一條一條送進 `su` 的鎖。
  final _lock = Lock();

  /// 本 session 的結束標記（隨機，避免和檔案內容撞到）。
  final _marker =
      '__genshin_end_${Random.secure().nextInt(1 << 32).toRadixString(16)}__';

  /// 常駐的 `su` 程序；尚未啟動或已結束時為 null。
  Process? _process;

  /// 尚未切出的 stdout 位元組。
  final _buffer = BytesBuilder(copy: false);

  /// 等待下一個結束標記的 completer。
  Completer<Uint8List>? _pending;

  /// 本類別的 logger。
  static final _log = Logger('capture.android');

  /// 第一條指令的等待上限（玩家要在 root 工具的授權視窗按允許）。
  static const _grantTimeout = Duration(seconds: 60);

  /// 之後每條指令的等待上限。
  static const _commandTimeout = Duration(seconds: 20);

  /// 裝置上是否有 `su` 執行檔；沒有時不呼叫 `su`，避免沒有 root 的裝置多等一次逾時。
  Future<bool> isSuPresent() async {
    for (final path in suPaths) {
      if (await File(path).exists()) return true;
    }
    return false;
  }

  /// 啟動常駐 `su` 並執行 `id` 確認拿得到 root（會跳出 root 工具的授權詢問）。
  Future<bool> verify() async {
    try {
      final out = utf8.decode(
        await _execInternal('id', _grantTimeout, spawn: true),
        allowMalformed: true,
      );
      final ok = out.contains('uid=0');
      _log.info('root verify ok=$ok');
      if (!ok) await close();
      return ok;
    } catch (e) {
      _log.info('root verify failed error=${e.runtimeType}');
      await close();
      return false;
    }
  }

  /// 以 root 執行 [command]，回傳 stdout 原始位元組；`su` 已結束或逾時時丟 [RootShellException]。
  Future<Uint8List> exec(String command) =>
      _execInternal(command, _commandTimeout);

  /// 送出 [command] 並等它的結束標記；[spawn] 為 true 時（只有 [verify]）才可以開新的 `su`。
  ///
  /// 一般指令不自己重開：session 被 [close] 後還在跑的輪詢若重開 `su`，會再跳一次 root 授權。
  Future<Uint8List> _execInternal(
    String command,
    Duration timeout, {
    bool spawn = false,
  }) => _lock.synchronized(() async {
    final current = _process;
    if (current == null && !spawn) {
      throw RootShellException('su session closed');
    }
    final process = current ?? await _spawn();
    final pending = Completer<Uint8List>();
    _pending = pending;
    process.stdin
      ..writeln(command)
      ..writeln("printf '\\n%s %d\\n' $_marker \$?");
    await process.stdin.flush();
    try {
      return await pending.future.timeout(timeout);
    } on TimeoutException {
      await close();
      throw RootShellException('su command timed out');
    } finally {
      _pending = null;
    }
  });

  /// 啟動常駐 `su`，接上 stdout 解析與結束偵測。
  Future<Process> _spawn() async {
    final process = await _start('su', const []);
    _process = process;
    _buffer.clear();
    _tail = Uint8List(0);
    process.stdout.listen(
      _onStdout,
      onDone: () => _onExit(process),
      cancelOnError: true,
    );
    unawaited(process.stderr.drain<void>());
    unawaited(process.exitCode.then((_) => _onExit(process)));
    _log.info('root su session started');
    return process;
  }

  /// 結束標記行的開頭（換行＋標記＋空白）。
  late final _head = utf8.encode('\n$_marker ');

  /// 上一批輸出的結尾（結束標記可能被切在兩批之間）；長度最多 [_head] 再加結束碼的幾個位元組。
  Uint8List _tail = Uint8List(0);

  /// 收到輸出時，找到結束標記就把標記前的內容交給等待中的指令。
  ///
  /// 大檔會分成很多批送來，每批只在「上一批結尾＋這一批」裡找標記；
  /// 每批都把整個緩衝區合併再從頭掃，讀幾 MB 就要花好幾秒。
  void _onStdout(List<int> data) {
    _buffer.add(data);
    final window = Uint8List(_tail.length + data.length)
      ..setAll(0, _tail)
      ..setAll(_tail.length, data);
    final keep = _head.length + 8;
    _tail = window.length > keep
        ? window.sublist(window.length - keep)
        : window;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final inWindow = _indexOf(window, _head);
    if (inWindow < 0 || window.indexOf(0x0A, inWindow + _head.length) < 0) {
      return;
    }
    final bytes = _buffer.toBytes();
    final at = _indexOf(bytes, _head);
    final lineEnd = bytes.indexOf(0x0A, at + _head.length);
    _buffer.clear();
    _tail = Uint8List(0);
    if (lineEnd + 1 < bytes.length) {
      _tail = bytes.sublist(lineEnd + 1);
      _buffer.add(_tail);
    }
    pending.complete(Uint8List.sublistView(bytes, 0, at));
  }

  /// `su` 結束（授權被拒、被 kill）時，讓等待中的指令失敗。
  void _onExit(Process process) {
    if (!identical(_process, process)) return;
    _process = null;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(RootShellException('su exited'));
    }
  }

  /// 結束常駐的 `su`。
  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      process.stdin.writeln('exit');
      await process.stdin.flush();
    } catch (_) {}
    process.kill();
    _log.info('root su session closed');
  }

  /// 在 [haystack] 中找 [needle] 第一次出現的位置。
  static int _indexOf(Uint8List haystack, List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
