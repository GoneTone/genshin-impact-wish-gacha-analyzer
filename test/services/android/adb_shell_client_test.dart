import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/adb_shell_client.dart';

/// 依 [reply] 回應指令的假 ADB 連線。
class _FakeSession implements AdbSession {
  /// 建立假連線；[reply] 為 null 時一律回 `uid=2000(shell)`。
  _FakeSession(this.port, {this.reply});

  /// 這個連線的連接埠。
  final int port;

  /// 自訂回應；丟例外模擬串流開啟失敗。
  final FutureOr<String> Function(String command)? reply;

  /// 收到的指令。
  final commands = <String>[];

  /// 是否已關閉。
  bool closed = false;

  @override
  Future<Uint8List> shell(String command) async {
    commands.add(command);
    final out = reply == null ? 'uid=2000(shell)\n' : await reply!(command);
    return Uint8List.fromList(utf8.encode(out));
  }

  @override
  Future<void> close() async => closed = true;
}

/// 解碼成字串方便比對。
String _s(Uint8List b) => utf8.decode(b);

void main() {
  test('connectAny skips refused stale port and uses the next', () async {
    final sessions = <int, _FakeSession>{};
    final client = AdbShellClient(
      connect: (port) async =>
          port == 44091 ? null : (sessions[port] = _FakeSession(port)),
    );
    expect(await client.connectAny([44091, 38435]), isTrue);
    expect(client.isConnected, isTrue);
    await client.exec('echo hi');
    expect(sessions[38435]!.commands.last, 'echo hi');
  });

  test('connectAny rejects a session that is not the shell user', () async {
    final s = _FakeSession(1, reply: (_) => 'uid=10123(u0_a123)');
    final client = AdbShellClient(connect: (_) async => s);
    expect(await client.connectAny([1]), isFalse);
    expect(s.closed, isTrue);
  });

  test('exec retries once after a stream open failure', () async {
    var calls = 0;
    final s = _FakeSession(
      1,
      reply: (c) {
        if (c == 'id') return 'uid=2000(shell)';
        calls++;
        if (calls == 1) throw Exception('Stream open failed');
        return 'ok';
      },
    );
    final client = AdbShellClient(
      connect: (_) async => s,
      retryDelay: Duration.zero,
    );
    await client.connectAny([1]);
    expect(_s(await client.exec('x')), 'ok');
    expect(calls, 2);
  });

  test('exec reconnects via rediscover when retry also fails', () async {
    final dead = _FakeSession(
      1,
      reply: (c) => c == 'id' ? 'uid=2000(shell)' : throw Exception('closed'),
    );
    final fresh = _FakeSession(2, reply: (c) => c == 'id' ? 'uid=2000' : 'ok');
    var rediscovered = 0;
    final client = AdbShellClient(
      connect: (port) async => port == 1 ? dead : fresh,
      rediscover: () async {
        rediscovered++;
        return [2];
      },
      retryDelay: Duration.zero,
    );
    await client.connectAny([1]);
    expect(_s(await client.exec('x')), 'ok');
    expect(rediscovered, 1);
    expect(dead.closed, isTrue);
  });

  test('exec throws AdbShellException when everything fails', () async {
    final s = _FakeSession(
      1,
      reply: (c) => c == 'id' ? 'uid=2000' : throw Exception('closed'),
    );
    final client = AdbShellClient(
      connect: (_) async => s,
      retryDelay: Duration.zero,
    );
    await client.connectAny([1]);
    await expectLater(client.exec('x'), throwsA(isA<AdbShellException>()));
  });

  test('exec calls are serialized', () async {
    final log = <String>[];
    final s = _FakeSession(
      1,
      reply: (c) async {
        if (c == 'id') return 'uid=2000';
        log.add('in $c');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('out $c');
        return c;
      },
    );
    final client = AdbShellClient(connect: (_) async => s);
    await client.connectAny([1]);
    await Future.wait([client.exec('a'), client.exec('b')]);
    expect(log, ['in a', 'out a', 'in b', 'out b']);
  });

  test(
    'healthChanges emits false on final failure and true on recovery',
    () async {
      var broken = false;
      final s = _FakeSession(
        1,
        reply: (c) {
          if (c == 'id') return 'uid=2000';
          if (broken) throw Exception('closed');
          return 'ok';
        },
      );
      final client = AdbShellClient(
        connect: (_) async => s,
        retryDelay: Duration.zero,
      );
      final events = <bool>[];
      final sub = client.healthChanges.listen(events.add);
      await client.connectAny([1]);
      await client.exec('x');
      broken = true;
      await expectLater(client.exec('x'), throwsA(isA<AdbShellException>()));
      await expectLater(client.exec('x'), throwsA(isA<AdbShellException>()));
      broken = false;
      await client.exec('x');
      await client.exec('x');
      await Future<void>.delayed(Duration.zero);
      expect(events, [false, true]);
      await sub.cancel();
      await client.close();
    },
  );

  test('exec after close fails without reconnecting', () async {
    // 重連會順便重開無線偵錯；release 之後還在跑的指令不能這樣做。
    var rediscovered = 0;
    final client = AdbShellClient(
      connect: (port) async => _FakeSession(port),
      rediscover: () async {
        rediscovered++;
        return [2];
      },
      retryDelay: Duration.zero,
    );
    await client.connectAny([1]);
    await client.close();
    await expectLater(client.exec('x'), throwsA(isA<AdbShellException>()));
    expect(await client.connectAny([1]), isFalse);
    expect(rediscovered, 0);
  });

  test('keeps a minimum gap between shell streams', () async {
    final starts = <int>[];
    final ends = <int>[];
    final sw = Stopwatch()..start();
    final s = _FakeSession(
      1,
      reply: (c) {
        starts.add(sw.elapsedMilliseconds);
        ends.add(sw.elapsedMilliseconds);
        return 'uid=2000';
      },
    );
    final client = AdbShellClient(
      connect: (_) async => s,
      minGap: const Duration(milliseconds: 60),
    );
    await client.connectAny([1]);
    await client.exec('a');
    await client.exec('b');
    expect(starts[1] - ends[0], greaterThanOrEqualTo(55), reason: 'id → a');
    expect(starts[2] - ends[1], greaterThanOrEqualTo(55), reason: 'a → b');
  });
}
