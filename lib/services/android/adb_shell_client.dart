import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';

/// 一條已連上的 ADB 連線，可以執行一次性 shell 指令。
abstract interface class AdbSession {
  /// 執行 [command]，回傳 stdout 原始位元組；串流開不起來時丟例外。
  Future<Uint8List> shell(String command);

  /// 中斷連線。
  Future<void> close();
}

/// 連到本機指定連接埠的 ADB；連不上時回 null。
typedef AdbConnector = Future<AdbSession?> Function(int port);

/// ADB shell 指令在重試、重連後仍失敗。
class AdbShellException implements Exception {
  /// 建立例外，[message] 說明原因（不含指令內容以外的敏感資料）。
  AdbShellException(this.message);

  /// 失敗原因。
  final String message;

  @override
  String toString() => 'AdbShellException: $message';
}

/// 透過無線偵錯的 shell（`uid=2000`）執行指令。
///
/// 處理實機上遇到的三個狀況：NSD 常回傳已關閉的舊連接埠（逐一嘗試）、
/// 前一個串流剛結束就開下一個偶爾會失敗（排隊並延遲重試一次）、
/// 玩家切去遊戲期間連線斷掉（重新找連接埠並重連）。
class AdbShellClient {
  /// 建立用戶端；[rediscover] 在重試也失敗時提供新的連接埠清單（必要時順便重開無線偵錯）。
  AdbShellClient({
    required AdbConnector connect,
    Future<List<int>> Function()? rediscover,
    this.retryDelay = const Duration(milliseconds: 300),
    this.minGap = const Duration(milliseconds: 250),
  }) : _connect = connect,
       _rediscover = rediscover;

  /// 失敗後重試前等待的時間。
  final Duration retryDelay;

  /// 兩個 shell 串流之間至少間隔多久。
  ///
  /// 前一個串流剛結束就開下一個，`flutter_adb` 常會等滿 10 秒才回 `Stream open failed`
  /// （實機上連上後的第一條指令就踩到），所以每條指令前先補足間隔。
  final Duration minGap;

  /// 上一個 shell 串流結束的時間。
  final _sinceLast = Stopwatch();

  /// 連線函式。
  final AdbConnector _connect;

  /// 重新取得連接埠清單的函式；null 時不重連。
  final Future<List<int>> Function()? _rediscover;

  /// 讓指令一條一條執行的鎖。
  final _lock = Lock();

  /// 連線健康狀態的變化（false＝連線中斷，true＝恢復）。
  final _health = StreamController<bool>.broadcast();

  /// 目前的連線。
  AdbSession? _session;

  /// 上一次回報的健康狀態。
  bool _healthy = true;

  /// 是否已 [close]；關閉後不再連線，避免重連時又把無線偵錯打開。
  bool _closed = false;

  /// 本用戶端的 logger。
  static final _log = Logger('capture.adb');

  /// 目前是否有連線。
  bool get isConnected => _session != null;

  /// 健康狀態變化：重試、重連都失敗時發 false，之後第一次成功時發 true。
  Stream<bool> get healthChanges => _health.stream;

  /// 依序嘗試 [ports]，連上且確認是 shell 使用者就停；全部失敗回 false。
  Future<bool> connectAny(List<int> ports) async {
    if (_closed) return false;
    for (final port in ports) {
      AdbSession? session;
      try {
        session = await _connect(port);
        if (session == null) {
          _log.info('adb connect refused port=$port');
          continue;
        }
        final id = utf8.decode(
          await _shell(session, 'id'),
          allowMalformed: true,
        );
        if (_closed) break;
        if (id.contains('uid=2000')) {
          await _session?.close();
          _session = session;
          _log.info('adb connected port=$port');
          return true;
        }
        _log.warning('adb session is not the shell user port=$port');
      } catch (e) {
        _log.info('adb connect failed port=$port error=${e.runtimeType}');
      }
      await session?.close();
    }
    return false;
  }

  /// 執行 [command]；失敗時延遲重試一次，再失敗就重新找連接埠重連後再試。
  Future<Uint8List> exec(String command) => _lock.synchronized(() async {
    try {
      final out = await _run(command);
      _report(true);
      return out;
    } on AdbShellException {
      _report(false);
      rethrow;
    }
  });

  /// [exec] 的實際流程（已在鎖內）。
  Future<Uint8List> _run(String command) async {
    if (_closed) throw AdbShellException('client closed');
    final session = _session;
    if (session != null) {
      try {
        return await _shell(session, command);
      } catch (e) {
        _log.info('adb shell failed, retrying error=${e.runtimeType}');
      }
      await Future<void>.delayed(retryDelay);
      try {
        return await _shell(session, command);
      } catch (e) {
        _log.warning('adb shell retry failed error=${e.runtimeType}');
      }
    }
    final rediscover = _rediscover;
    if (rediscover == null || _closed) {
      throw AdbShellException('shell unavailable');
    }
    await _session?.close();
    _session = null;
    final ports = await rediscover();
    if (!await connectAny(ports)) {
      throw AdbShellException('reconnect failed ports=${ports.length}');
    }
    try {
      return await _shell(_session!, command);
    } catch (e) {
      throw AdbShellException('shell failed after reconnect ${e.runtimeType}');
    }
  }

  /// 補足與上一個串流的間隔後在 [session] 執行 [command]。
  Future<Uint8List> _shell(AdbSession session, String command) async {
    if (_sinceLast.isRunning) {
      final wait = minGap - _sinceLast.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    try {
      return await session.shell(command);
    } finally {
      _sinceLast
        ..reset()
        ..start();
    }
  }

  /// 健康狀態有變化時才發事件。
  void _report(bool healthy) {
    if (healthy == _healthy) return;
    _healthy = healthy;
    if (!_health.isClosed) _health.add(healthy);
  }

  /// 中斷連線並關閉健康狀態 stream。
  Future<void> close() async {
    _closed = true;
    await _session?.close();
    _session = null;
    await _health.close();
  }
}
