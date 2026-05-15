import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// 應用層 log pipeline。在 `main()` 透過 [bootstrap] 啟動,
/// 訂閱 `Logger.root.onRecord` 並把每條紀錄分發到:
/// 1. `dart:developer.log()`(IDE / DevTools);
/// 2. 記憶體 ring buffer(設定頁即時 stream 用);
/// 3. `<applicationSupport>/logs/YYYY-MM-DD.log`(UTC 日期,append);
/// 4. `kDebugMode` 下額外 `debugPrint` 給 `flutter run` console。
class LogService {
  LogService._(this.logsDir);

  /// `<applicationSupport>/logs/`
  final Directory logsDir;

  static const int _retentionDays = 7;
  static const int _ringBufferCapacity = 2000;

  final Queue<String> _ringBuffer = Queue<String>();
  final StreamController<String> _liveController =
      StreamController<String>.broadcast();

  IOSink? _todaySink;
  DateTime? _todayDate; // UTC date

  StreamSubscription<LogRecord>? _rootSubscription;

  /// 建立 `logs/`、清舊檔、開今天的 sink、訂閱 root Logger。
  static Future<LogService> bootstrap(Directory baseDir) async {
    final logsDir = Directory('${baseDir.path}/logs');
    if (!await logsDir.exists()) await logsDir.create(recursive: true);

    final svc = LogService._(logsDir);
    await svc._rotate();
    await svc._openTodaySink();

    Logger.root.level = Level.INFO;
    svc._rootSubscription = Logger.root.onRecord.listen(svc._handle);
    return svc;
  }

  void _handle(LogRecord r) {
    final line = _format(r);

    developer.log(
      r.message,
      time: r.time,
      level: r.level.value,
      name: r.loggerName,
      error: r.error,
      stackTrace: r.stackTrace,
    );
    if (kDebugMode) {
      debugPrint(line);
    }

    _ringBuffer.addLast(line);
    while (_ringBuffer.length > _ringBufferCapacity) {
      _ringBuffer.removeFirst();
    }
    if (!_liveController.isClosed) _liveController.add(line);

    _appendToFile(line, r);
  }

  String _format(LogRecord r) {
    final buf = StringBuffer()
      ..write(r.time.toIso8601String())
      ..write(' [')
      ..write(r.level.name.padRight(7))
      ..write('] [')
      ..write(r.loggerName)
      ..write('] ')
      ..write(r.message);
    if (r.error != null) {
      buf
        ..write('\n  error: ')
        ..write(r.error);
    }
    if (r.stackTrace != null) {
      buf
        ..write('\n  stack:\n    ')
        ..write(r.stackTrace.toString().replaceAll('\n', '\n    '));
    }
    return buf.toString();
  }

  void _appendToFile(String line, LogRecord r) {
    final d = DateTime.utc(r.time.year, r.time.month, r.time.day);
    if (_todayDate != d) {
      _todayDate =
          d; // synchronous guard — prevents re-entry from later records
      unawaited(_rolloverTo(d));
    }
    _todaySink?.writeln(line);
  }

  Future<void> _openTodaySink() async {
    final now = DateTime.now().toUtc();
    _todayDate = DateTime.utc(now.year, now.month, now.day);
    final file = _fileFor(_todayDate!);
    _todaySink = file.openWrite(mode: FileMode.append, encoding: utf8);
  }

  Future<void> _rolloverTo(DateTime d) async {
    await _todaySink?.flush();
    await _todaySink?.close();
    _todayDate = d;
    final file = _fileFor(d);
    _todaySink = file.openWrite(mode: FileMode.append, encoding: utf8);
    await _rotate();
  }

  File _fileFor(DateTime d) {
    final yyyy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return File('${logsDir.path}/$yyyy-$mm-$dd.log');
  }

  Future<void> _rotate() async {
    if (!await logsDir.exists()) return;
    final entries = await logsDir.list().toList();
    final cutoff = DateTime.now().toUtc().subtract(
      const Duration(days: _retentionDays),
    );
    final namePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})\.log$');
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      final m = namePattern.firstMatch(name);
      if (m == null) continue;
      final fd = DateTime.utc(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      if (fd.isBefore(cutoff)) {
        try {
          await e.delete();
        } catch (_) {
          // 下次再試,不阻塞啟動
        }
      }
    }
  }

  /// 把 `logs/` 內所有 `.log` 合併成單一字串(含 header)。
  Future<String> buildExportBundle({
    required String appVersion,
    required String osDescription,
    required String localeTag,
    required String themeMode,
  }) async {
    await _todaySink?.flush();
    final entries =
        (await logsDir.list().toList())
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.endsWith('.log'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final buf = StringBuffer()
      ..writeln('=== Genshin Wish Gacha Analyzer log bundle ===')
      ..writeln('exported_at: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('app_version: $appVersion')
      ..writeln('os: $osDescription')
      ..writeln('locale: $localeTag')
      ..writeln('theme: $themeMode')
      ..writeln('retention_days: $_retentionDays')
      ..writeln(
        'files: ${entries.map((e) => e.uri.pathSegments.last).join(', ')}',
      )
      ..writeln('=== begin ===');

    for (final f in entries) {
      buf
        ..writeln()
        ..writeln('--- ${f.uri.pathSegments.last} ---');
      buf.write(await f.readAsString());
    }
    return buf.toString();
  }

  /// 清除所有 log 檔,並重新開啟今天的 sink。
  Future<void> clearAll() async {
    await _todaySink?.flush();
    await _todaySink?.close();
    _todaySink = null;
    final entries = await logsDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.log')) {
        try {
          await e.delete();
        } catch (_) {
          // ignore
        }
      }
    }
    await _openTodaySink();
  }

  /// 設定頁即時預覽用:目前 ring buffer 的快照。
  List<String> snapshot() => _ringBuffer.toList(growable: false);

  /// 新進 log 的 broadcast stream。
  Stream<String> get live => _liveController.stream;

  Future<void> dispose() async {
    await _rootSubscription?.cancel();
    await _todaySink?.flush();
    await _todaySink?.close();
    await _liveController.close();
  }

  /// Flush pending writes to disk. For tests / "before export" use.
  Future<void> flush() async {
    await _todaySink?.flush();
  }
}
