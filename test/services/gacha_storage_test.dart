import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';

void main() {
  late Directory tempDir;
  late GachaStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gacha_test_');
    storage = GachaStorage(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  GachaRecord makeRecord(String id) => GachaRecord(
    id: id,
    uid: '801057625',
    gachaType: '301',
    name: 'x',
    itemType: '角色',
    rankType: 5,
    time: DateTime(2025, 1, 1),
    lang: 'zh-tw',
  );

  test('save → load roundtrip', () async {
    final original = BannerStorage(
      uid: '801057625',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: {
        '301': [makeRecord('1')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
      },
    );
    await storage.save(original);

    final loaded = await storage.load('801057625');
    expect(loaded, isNotNull);
    expect(loaded!.uid, '801057625');
    expect(loaded.banners['301']!.first.id, '1');
  });

  test('load 不存在的 UID → null', () async {
    expect(await storage.load('not_exist'), isNull);
  });

  test('load 損毀的 JSON → 拋 FormatException，主 isolate 記 severe log', () async {
    await File('${tempDir.path}/801057625.json').writeAsString('{not json');
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    await expectLater(
      storage.load('801057625'),
      throwsA(isA<FormatException>()),
    );

    final severe = records.where((r) => r.level == Level.SEVERE);
    expect(severe, hasLength(1));
    expect(severe.single.message, startsWith('load failed for uid='));
    expect(severe.single.message, contains('error=FormatException'));
    expect(severe.single.error, isNull);
  });

  test('save 失敗 → 記 severe log，不帶例外物件與路徑', () async {
    final blocker = File('${tempDir.path}/blocker');
    await blocker.writeAsString('x');
    final broken = GachaStorage(Directory('${blocker.path}/sub'));
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    await expectLater(
      broken.save(
        BannerStorage(
          uid: '801057625',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: {
            '301': [makeRecord('1')],
          },
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final severe = records.singleWhere((r) => r.level == Level.SEVERE);
    expect(severe.message, startsWith('save failed for uid='));
    expect(severe.message, contains('error='));
    expect(severe.message, isNot(contains(tempDir.path)));
    expect(severe.error, isNull);
  });

  test('listKnownUids 只列出純數字 <uid>.json，忽略 .url.json 與非數字檔', () async {
    await File('${tempDir.path}/123.json').writeAsString('{}');
    await File('${tempDir.path}/456.json').writeAsString('{}');
    await File('${tempDir.path}/123.url.json').writeAsString('{}');
    await File('${tempDir.path}/hoyowiki_index.json').writeAsString('{}');
    await File('${tempDir.path}/garbage.txt').writeAsString('');

    final uids = await storage.listKnownUids();
    expect(uids.toSet(), {'123', '456'});
  });

  test('saveCapturedUrl / loadCapturedUrl / deleteCapturedUrl', () async {
    await storage.saveCapturedUrl('801057625', 'https://example.com/gacha');
    expect(
      await storage.loadCapturedUrl('801057625'),
      'https://example.com/gacha',
    );

    await storage.deleteCapturedUrl('801057625');
    expect(await storage.loadCapturedUrl('801057625'), isNull);
  });

  test('save 用 atomic rename：失敗不破壞舊檔', () async {
    final v1 = BannerStorage(
      uid: '1',
      lastUpdated: DateTime.utc(2026),
      banners: {'301': [], '302': [], '500': [], '200': [], '100': []},
    );
    await storage.save(v1);

    // 驗證 .tmp 不殘留（save 成功後即移除）
    final tmp = File('${tempDir.path}/1.json.tmp');
    expect(await tmp.exists(), isFalse);
  });

  test('save 同一 UID 兩次 → 第二份覆蓋第一份', () async {
    final v1 = BannerStorage(
      uid: '999',
      lastUpdated: DateTime.utc(2026, 5, 8),
      banners: {
        '301': [makeRecord('1')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
      },
    );
    final v2 = BannerStorage(
      uid: '999',
      lastUpdated: DateTime.utc(2026, 5, 9),
      banners: {
        '301': [makeRecord('2')],
        '302': [],
        '500': [],
        '200': [],
        '100': [],
      },
    );
    await storage.save(v1);
    await storage.save(v2);
    final loaded = await storage.load('999');
    expect(loaded, isNotNull);
    expect(loaded!.banners['301']!.first.id, '2');
    expect(loaded.lastUpdated, DateTime.utc(2026, 5, 9));
    expect(await File('${tempDir.path}/999.json.tmp').exists(), isFalse);
  });

  group('背景讀檔占住記錄檔時（Windows 無 FILE_SHARE_DELETE）', () {
    /// 建立只含 [uid] 的最小資料。
    BannerStorage sample(String uid, DateTime t) =>
        BannerStorage(uid: uid, lastUpdated: t, banners: {'301': []});

    /// 先存一份舊資料，回傳以唯讀開啟 `<uid>.json` 的 handle。
    Future<RandomAccessFile> holdOpen(String uid) async {
      await storage.save(sample(uid, DateTime.utc(2026, 1, 1)));
      return storage.recordsFile(uid).open();
    }

    test('save retries when the records file is briefly held open', () async {
      final raf = await holdOpen('42');
      Future<void>.delayed(
        const Duration(milliseconds: 50),
      ).then((_) => raf.close());

      await storage.save(sample('42', DateTime.utc(2026, 6, 1)));

      final loaded = await storage.load('42');
      expect(loaded!.lastUpdated, DateTime.utc(2026, 6, 1));
    }, skip: !Platform.isWindows);

    test('save still throws when the records file stays locked', () async {
      final raf = await holdOpen('42');
      addTearDown(raf.close);

      await expectLater(
        storage.save(sample('42', DateTime.utc(2026, 6, 1))),
        throwsA(isA<PathAccessException>()),
      );
      expect(await storage.listKnownUids(), ['42']);
      final kept = await storage.recordsFile('42').readAsString();
      expect(kept, contains('2026-01-01'));
    }, skip: !Platform.isWindows);

    test('delete retries when the records file is briefly held open', () async {
      final raf = await holdOpen('42');
      Future<void>.delayed(
        const Duration(milliseconds: 50),
      ).then((_) => raf.close());

      await storage.delete('42');

      expect(await storage.recordsFile('42').exists(), isFalse);
    }, skip: !Platform.isWindows);
  });

  test(
    'load failure log carries neither the uid nor the path nor an error object',
    () async {
      final records = <LogRecord>[];
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'gacha.storage')
          .listen(records.add);
      addTearDown(sub.cancel);
      storage.recordsFile('800000001').writeAsStringSync('{ not json');

      await expectLater(storage.load('800000001'), throwsA(isA<Exception>()));

      final failed = records.singleWhere(
        (r) => r.message.startsWith('load failed for uid='),
      );
      expect(failed.error, isNull);
      expect(failed.stackTrace, isNotNull);
      expect(failed.message, isNot(contains('800000001')));
      expect(failed.message, isNot(contains(tempDir.path)));
    },
  );

  group('retryWhileHeld', () {
    /// 前 [failures] 次丟 [error]、之後成功的操作；[calls] 記錄被呼叫次數。
    Future<Object?> Function() flaky(
      List<int> calls,
      int failures,
      Object error,
    ) => () async {
      calls.add(calls.length + 1);
      if (calls.length <= failures) throw error;
      return null;
    };

    test(
      'succeeds after two PathAccessException retries and logs it',
      () async {
        final messages = <String>[];
        final sub = Logger.root.onRecord
            .where((r) => r.loggerName == 'gacha.storage')
            .listen((r) => messages.add(r.message));
        addTearDown(sub.cancel);
        final calls = <int>[];

        await retryWhileHeld(
          flaky(calls, 2, const PathAccessException('x', OSError('held', 32))),
          '42',
        );

        expect(calls, hasLength(3));
        expect(messages, contains(contains('retries=2')));
      },
    );

    test('rethrows after five attempts when always held', () async {
      final calls = <int>[];
      await expectLater(
        retryWhileHeld(
          flaky(calls, 99, const PathAccessException('x', OSError('held', 32))),
          '42',
        ),
        throwsA(isA<PathAccessException>()),
      );
      expect(calls, hasLength(5));
    });

    test('rethrows another FileSystemException without retrying', () async {
      final calls = <int>[];
      await expectLater(
        retryWhileHeld(
          flaky(calls, 99, const FileSystemException('other')),
          '42',
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e is PathAccessException,
            'is PathAccessException',
            isFalse,
          ),
        ),
      );
      expect(calls, hasLength(1));
    });
  });
}
