import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/root_shell.dart';

/// 模擬常駐 `su` 的程序：讀 stdin 的每一行指令，依 [reply] 產生輸出後印出結束標記。
class _FakeSu implements Process {
  _FakeSu(this.reply, {this.chunkSize}) {
    _stdinCtl.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
  }

  /// 指令 → 輸出位元組；回傳 null 代表 `su` 直接結束（例如授權被拒）。
  final List<int>? Function(String command) reply;

  /// 每批 stdout 的位元組數；null 時整段一次送出。
  final int? chunkSize;

  final _stdinCtl = StreamController<List<int>>();
  final _stdoutCtl = StreamController<List<int>>();
  final _exit = Completer<int>();

  /// 收到的指令（不含框架用的 echo）。
  final commands = <String>[];

  /// 是否被 kill。
  bool killed = false;

  String? _pending;

  void _onLine(String line) {
    if (line.startsWith('echo') || line.startsWith('printf')) {
      final marker = RegExp(r'__genshin_end_\w+__').firstMatch(line)!.group(0)!;
      final out = reply(_pending!);
      if (out == null) {
        _stdoutCtl.close();
        if (!_exit.isCompleted) _exit.complete(1);
        return;
      }
      final all = [...out, 0x0A, ...utf8.encode('$marker 0\n')];
      final size = chunkSize ?? all.length;
      for (var i = 0; i < all.length; i += size) {
        _stdoutCtl.add(all.sublist(i, math.min(i + size, all.length)));
      }
      return;
    }
    if (line == 'exit') {
      _stdoutCtl.close();
      if (!_exit.isCompleted) _exit.complete(0);
      return;
    }
    commands.add(line);
    _pending = line;
  }

  late final IOSink _stdin = IOSink(_stdinCtl.sink);

  @override
  IOSink get stdin => _stdin;
  @override
  Stream<List<int>> get stdout => _stdoutCtl.stream;
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-9);
    _stdoutCtl.close();
    return true;
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('root_shell'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// 建一個假的 su 執行檔路徑。
  String fakeSuPath() {
    final f = File('${tmp.path}/su')..writeAsStringSync('');
    return f.path;
  }

  test('su absent means no process is spawned', () async {
    var starts = 0;
    final shell = RootShell(
      suPaths: ['${tmp.path}/nope'],
      start: (exe, args) async {
        starts++;
        return _FakeSu((_) => []);
      },
    );
    expect(await shell.isSuPresent(), isFalse);
    expect(starts, 0);
  });

  test('verify requires uid=0', () async {
    for (final (out, want) in [
      ('uid=2000(shell)', false),
      ('uid=0(root)', true),
    ]) {
      final shell = RootShell(
        suPaths: [fakeSuPath()],
        start: (exe, args) async => _FakeSu((_) => utf8.encode(out)),
      );
      expect(await shell.verify(), want, reason: out);
    }
  });

  test('verify is false when su is denied or cannot start', () async {
    final denied = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async => _FakeSu((_) => null),
    );
    expect(await denied.verify(), isFalse);
    final broken = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) => throw const ProcessException('su', []),
    );
    expect(await broken.verify(), isFalse);
  });

  test('one su process serves verify and every exec', () async {
    var starts = 0;
    late _FakeSu su;
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async {
        starts++;
        return su = _FakeSu(
          (c) => c == 'id' ? utf8.encode('uid=0(root)') : utf8.encode('out:$c'),
        );
      },
    );
    expect(await shell.verify(), isTrue);
    for (var i = 0; i < 3; i++) {
      expect(utf8.decode(await shell.exec('stat $i')), 'out:stat $i');
    }
    expect(starts, 1, reason: 'only one su grant per session');
    expect(su.commands, ['id', 'stat 0', 'stat 1', 'stat 2']);
  });

  test(
    'exec returns raw bytes including ones that look like newlines',
    () async {
      final shell = RootShell(
        suPaths: [fakeSuPath()],
        start: (exe, args) async => _FakeSu(
          (c) => c == 'id' ? utf8.encode('uid=0') : [0xAF, 0x0A, 0x00, 0x0A],
        ),
      );
      await shell.verify();
      expect(
        await shell.exec('tail'),
        Uint8List.fromList([0xAF, 0x0A, 0x00, 0x0A]),
      );
    },
  );

  test('large output in many small chunks is read in linear time', () async {
    // 每批都重掃整個緩衝區的話，8 MB 分成 2 KB 一批要掃好幾 GB。
    final big = List<int>.filled(8 << 20, 0x61);
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async => _FakeSu(
        (c) => c == 'id' ? utf8.encode('uid=0') : big,
        chunkSize: 2048,
      ),
    );
    await shell.verify();
    final sw = Stopwatch()..start();
    final out = await shell.exec('tail');
    expect(out.length, big.length);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('marker split across chunks is still found', () async {
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async => _FakeSu(
        (c) => c == 'id' ? utf8.encode('uid=0') : utf8.encode('hello'),
        chunkSize: 3,
      ),
    );
    expect(await shell.verify(), isTrue);
    expect(utf8.decode(await shell.exec('x')), 'hello');
  });

  test('exec fails when the su process died', () async {
    var calls = 0;
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async => _FakeSu((c) {
        calls++;
        return calls == 1 ? utf8.encode('uid=0') : null;
      }),
    );
    await shell.verify();
    await expectLater(shell.exec('x'), throwsA(isA<RootShellException>()));
  });

  test('exec after close fails instead of starting another su', () async {
    // release 之後還在跑的輪詢不能再開 su（會再跳一次 root 授權）。
    var starts = 0;
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async {
        starts++;
        return _FakeSu((_) => utf8.encode('uid=0'));
      },
    );
    await shell.verify();
    await shell.close();
    await expectLater(shell.exec('x'), throwsA(isA<RootShellException>()));
    expect(starts, 1);
    expect(await shell.verify(), isTrue, reason: 'next update starts again');
    expect(starts, 2);
  });

  test('close kills the su process', () async {
    late _FakeSu su;
    final shell = RootShell(
      suPaths: [fakeSuPath()],
      start: (exe, args) async => su = _FakeSu((_) => utf8.encode('uid=0')),
    );
    await shell.verify();
    await shell.close();
    expect(su.killed, isTrue);
  });
}
