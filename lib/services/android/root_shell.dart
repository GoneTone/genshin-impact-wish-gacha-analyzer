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
///
/// [verify] 成功後 `su` 意外結束（逾時、被結束）時，下一條指令會重開一次（root 工具記得授權，通常不會再詢問）；
/// [close] 之後則不再重開。
class RootShell {
  /// 建立 root shell；[start]、[suPaths] 與 [commandTimeout] 僅供測試替換。
  RootShell({
    ProcessStarter? start,
    this.suPaths = defaultSuPaths,
    this.commandTimeout = const Duration(seconds: 20),
  }) : _start = start ?? Process.start;

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

  /// [verify] 成功後到 [close] 前為 true：這段期間 `su` 意外結束要由下一條指令重開。
  bool _keepAlive = false;

  /// 目前的連線是否正常；只在變化時送進 [healthChanges]。
  bool _healthy = true;

  /// 連線健康狀態變化的來源。
  final _health = StreamController<bool>.broadcast();

  /// 尚未切出的 stdout 位元組。
  final _buffer = BytesBuilder(copy: false);

  /// 等待下一個結束標記的 completer。
  Completer<Uint8List>? _pending;

  /// 本類別的 logger。
  static final _log = Logger('capture.android');

  /// 第一條指令的等待上限（玩家要在 root 工具的授權視窗按允許）。
  static const _grantTimeout = Duration(seconds: 60);

  /// 之後每條指令的等待上限。
  final Duration commandTimeout;

  /// 連線健康狀態變化（false＝`su` 意外結束、true＝重開成功）。
  Stream<bool> get healthChanges => _health.stream;

  /// 裝置上是否有 `su` 執行檔；沒有時不呼叫 `su`，避免沒有 root 的裝置多等一次逾時。
  Future<bool> isSuPresent() async {
    for (final path in suPaths) {
      if (await File(path).exists()) return true;
    }
    return false;
  }

  /// 啟動常駐 `su` 並執行 `id` 確認拿得到 root（會跳出 root 工具的授權詢問）。
  Future<bool> verify() async {
    final ok = await _open();
    if (ok) {
      _keepAlive = true;
      _healthy = true;
    } else {
      await close();
    }
    return ok;
  }

  /// 開 `su` 並執行 `id` 確認拿得到 root；失敗時結束程序，但不改變 [_keepAlive]。
  Future<bool> _open() async {
    try {
      final out = utf8.decode(
        await _execInternal('id', _grantTimeout, spawn: true),
        allowMalformed: true,
      );
      final ok = out.contains('uid=0');
      _log.info('root verify ok=$ok');
      if (!ok) _detach()?.kill();
      return ok;
    } catch (e, st) {
      _log.info('root verify failed', e, st);
      _detach()?.kill();
      return false;
    }
  }

  /// 以 root 執行 [command]，回傳 stdout 原始位元組；`su` 已結束或逾時時丟 [RootShellException]。
  ///
  /// session 意外結束時先重開一次；重開失敗就丟例外，留給下一條指令再試。
  Future<Uint8List> exec(String command) async {
    if (_process == null && _keepAlive) {
      _log.info('root su session lost, reopening');
      if (!await _open()) throw RootShellException('su reopen failed');
      _setHealthy(true);
    }
    return _execInternal(command, commandTimeout);
  }

  /// 送出 [command] 並等它的結束標記；[spawn] 為 true 時（只有 [_open]）才可以開新的 `su`。
  ///
  /// 被 [close] 後還在跑的輪詢不能重開 `su`，否則會再跳一次 root 授權；重開只由 [exec] 在 session 意外結束時做。
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
      _detach()?.kill();
      if (_keepAlive) _setHealthy(false);
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
      // 逾時被結束的舊 `su` 還可能送來輸出，結束標記相同，不能算進新 session 的指令。
      (data) {
        if (identical(_process, process)) _onStdout(data);
      },
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
    if (_keepAlive) {
      _log.info('root su session exited unexpectedly');
      _setHealthy(false);
    }
  }

  /// 健康狀態有變化時送出。
  void _setHealthy(bool healthy) {
    if (_healthy == healthy) return;
    _healthy = healthy;
    _health.add(healthy);
  }

  /// 結束常駐的 `su`，之後的指令不再重開；等授權中的 [verify] 會立刻失敗。
  Future<void> close() async {
    _keepAlive = false;
    final process = _detach();
    if (process == null) return;
    try {
      process.stdin.writeln('exit');
      await process.stdin.flush();
    } catch (_) {}
    process.kill();
    _log.info('root su session closed');
  }

  /// 放開目前的 `su`（之後的結束不再當成意外）並讓等待中的指令失敗；回傳原本的程序。
  Process? _detach() {
    final process = _process;
    _process = null;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(RootShellException('su session closed'));
    }
    return process;
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
