import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';

void main() {
  late Directory tempDir;
  late LogService svc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('log_service_test_');
  });

  tearDown(() async {
    await svc.dispose();
    await tempDir.delete(recursive: true);
    Logger.root.level = Level.INFO;
    Logger.root.clearListeners();
  });

  test('bootstrap creates logs/ subdirectory', () async {
    svc = await LogService.bootstrap(tempDir);
    expect(await Directory('${tempDir.path}/logs').exists(), isTrue);
  });

  test('INFO log appends to today file', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('hello world');
    await svc.flush();

    final files = await Directory('${tempDir.path}/logs').list().toList();
    final logFiles = files.whereType<File>().where(
      (f) => f.path.endsWith('.log'),
    );
    expect(logFiles, hasLength(1));
    final content = await logFiles.first.readAsString();
    expect(content, contains('hello world'));
    expect(content, contains('[test]'));
    expect(content, contains('INFO'));
  });

  test('level filter respects Logger.root.level', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger.root.level = Level.WARNING;
    Logger('test').info('should-not-appear');
    Logger('test').warning('should-appear');
    await svc.flush();

    final file = (await Directory('${tempDir.path}/logs').list().toList())
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.log'));
    final content = await file.readAsString();
    expect(content, isNot(contains('should-not-appear')));
    expect(content, contains('should-appear'));
  });

  test('ring buffer caps at capacity', () async {
    svc = await LogService.bootstrap(tempDir);
    for (var i = 0; i < 3000; i++) {
      Logger('test').info('line $i');
    }
    final snap = svc.snapshot();
    expect(snap.length, equals(2000));
    expect(snap.first, contains('line 1000'));
    expect(snap.last, contains('line 2999'));
  });

  test('live stream emits new records', () async {
    svc = await LogService.bootstrap(tempDir);
    final received = <String>[];
    final sub = svc.live.listen(received.add);
    Logger('test').info('streamed');
    await svc.flush();
    await sub.cancel();
    expect(received, hasLength(1));
    expect(received.first, contains('streamed'));
  });

  test('clearAll deletes all .log files and reopens sink', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('before clear');
    await svc.flush();

    await svc.clearAll();
    final after = await Directory('${tempDir.path}/logs').list().toList();
    final logFileListAfter = after
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
    // After clearAll, _openTodaySink has created a fresh empty file for today.
    // So exactly 1 file should exist, and it should be empty.
    expect(logFileListAfter.length, equals(1));
    expect(await logFileListAfter.first.readAsString(), isEmpty);

    Logger('test').info('after clear');
    await svc.flush();
    final reopened = (await Directory('${tempDir.path}/logs').list().toList())
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.log'));
    final content = await reopened.readAsString();
    expect(content, contains('after clear'));
    expect(content, isNot(contains('before clear')));
  });

  test('rotation deletes files older than retention', () async {
    final logsDir = Directory('${tempDir.path}/logs');
    await logsDir.create();
    final old = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final oldName =
        '${old.year.toString().padLeft(4, '0')}-${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}.log';
    await File('${logsDir.path}/$oldName').writeAsString('ancient');
    final recent = DateTime.now().toUtc().subtract(const Duration(days: 3));
    final recentName =
        '${recent.year.toString().padLeft(4, '0')}-${recent.month.toString().padLeft(2, '0')}-${recent.day.toString().padLeft(2, '0')}.log';
    await File('${logsDir.path}/$recentName').writeAsString('recent');

    svc = await LogService.bootstrap(tempDir);
    final remaining = (await logsDir.list().toList())
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(remaining, contains(recentName));
    expect(remaining, isNot(contains(oldName)));
  });

  test('buildExportBundle merges all log files with header', () async {
    svc = await LogService.bootstrap(tempDir);
    Logger('test').info('mark-line');
    await svc.flush();

    final bundle = await svc.buildExportBundle(
      appVersion: '9.9.9',
      osDescription: 'TestOS',
      localeTag: 'zh-Hant',
      themeMode: 'dark',
    );
    expect(bundle, contains('Genshin Wish Gacha Analyzer log bundle'));
    expect(bundle, contains('app_version: 9.9.9'));
    expect(bundle, contains('os: TestOS'));
    expect(bundle, contains('locale: zh-Hant'));
    expect(bundle, contains('theme: dark'));
    expect(bundle, contains('mark-line'));
  });
}
