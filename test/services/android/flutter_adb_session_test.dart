import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/adb_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/flutter_adb_session.dart';

/// 開出的串流永遠不回應的連線替身，記錄送出的訊息。
class _SilentConnection implements AdbConnection {
  /// 送出的訊息。
  final sent = <Uint8List>[];

  @override
  Future<AdbStream> open(String destination) async =>
      AdbStream(1, this)..remoteId = 9;

  @override
  Future<void> sendMessage(Uint8List messageData, {bool flush = false}) async =>
      sent.add(messageData);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 中斷連線永遠不回來的連線替身（連線已斷時 flush 卡住）。
class _HangingConnection implements AdbConnection {
  @override
  Future<bool> disconnect() => Completer<bool>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('timed-out shell closes its stream on the device side', () async {
    // 不送 CLSE 的話裝置端串流一直開著，下一個串流可能拿到相同的 localId。
    final conn = _SilentConnection();
    final session = FlutterAdbSession(
      conn,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(session.shell('id'), throwsA(anything));
    expect(conn.sent, [AdbProtocol.generateClose(1, 9)]);
  });

  test('close gives up when disconnect hangs', () async {
    // 連線斷掉後中斷連線不回來，會讓取消等待、重連整個卡住。
    final session = FlutterAdbSession(_HangingConnection());
    await session.close().timeout(const Duration(seconds: 5));
  });

  test('guarded zone logs stray socket errors and still returns', () async {
    // flutter_adb 寫入已斷線的 socket 時錯誤沒人接（Broken pipe），不能變成未處理錯誤。
    final records = <LogRecord>[];
    final sub = Logger('capture.adb').onRecord.listen(records.add);
    final value = await guardAdbZone(() async {
      unawaited(Future<void>.error(const SocketExceptionStub()));
      return 7;
    });
    await Future<void>.delayed(Duration.zero);
    expect(value, 7);
    expect(records.map((r) => r.message), ['adb socket error']);
    await sub.cancel();
  });

  test('guarded zone passes errors of the body to the caller', () async {
    await expectLater(
      guardAdbZone<int>(() async => throw StateError('x')),
      throwsStateError,
    );
  });
}

/// 模擬 socket 寫入失敗的例外。
class SocketExceptionStub implements Exception {
  /// 建立例外。
  const SocketExceptionStub();
}
