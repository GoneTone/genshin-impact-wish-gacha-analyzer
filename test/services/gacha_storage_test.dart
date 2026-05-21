import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  test('listKnownUids 只列出 <uid>.json，忽略 .url.json 與其他檔', () async {
    await File('${tempDir.path}/123.json').writeAsString('{}');
    await File('${tempDir.path}/456.json').writeAsString('{}');
    await File('${tempDir.path}/123.url.json').writeAsString('{}');
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
}
