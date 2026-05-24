import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

void main() {
  group('HoyoWikiIndex.lookupId', () {
    test('命中回 id', () {
      final index = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
        menuIds: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), isNull);
    });

    test('lang 不同 → 不命中', () {
      final index = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
        menuIds: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'zh-tw'), isNull);
    });
  });

  group('HoyoWikiIndex.lookupEntry', () {
    test('命中回 entry', () {
      final entry = HoyoWikiEntry(
        iconUrl: 'https://x/icon.png',
        headerImgUrl: 'https://x/header.png',
        fetchedAt: DateTime.utc(2026, 5, 23),
      );
      final index = HoyoWikiIndex(
        searchMap: const {},
        entries: {'5125428': entry},
        menuIds: const {},
      );
      expect(index.lookupEntry('5125428'), entry);
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupEntry('5125428'), isNull);
    });
  });

  group('HoyoWikiIndex.lookupMenuId', () {
    test('命中回 menu_id', () {
      final index = HoyoWikiIndex(
        searchMap: const {},
        entries: const {},
        menuIds: const {'5125428': 2, '9001': 4},
      );
      expect(index.lookupMenuId('5125428'), 2);
      expect(index.lookupMenuId('9001'), 4);
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupMenuId('5125428'), isNull);
    });
  });

  group('HoyoWikiIndexStorage', () {
    late Directory tempDir;
    late HoyoWikiIndexStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_index_test_');
      storage = HoyoWikiIndexStorage(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('load 缺檔回空 index', () async {
      final index = await storage.load();
      expect(index.searchMap, isEmpty);
      expect(index.entries, isEmpty);
    });

    test('save → load roundtrip（含 menu_ids）', () async {
      final original = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: {
          '5125428': HoyoWikiEntry(
            iconUrl: 'https://x/icon.png',
            headerImgUrl: '',
            fetchedAt: DateTime.utc(2026, 5, 23, 8),
          ),
        },
        menuIds: const {'5125428': 2},
      );
      await storage.save(original);
      final loaded = await storage.load();
      expect(loaded.searchMap, original.searchMap);
      expect(loaded.entries['5125428']!.iconUrl, 'https://x/icon.png');
      expect(loaded.entries['5125428']!.headerImgUrl, '');
      expect(
        loaded.entries['5125428']!.fetchedAt,
        DateTime.utc(2026, 5, 23, 8),
      );
      expect(loaded.menuIds, {'5125428': 2});
    });

    test('load 無 menu_ids 欄位（舊格式）→ 空 map（向後相容）', () async {
      // 直接寫一個不含 menu_ids 的舊格式 JSON
      final f = File('${tempDir.path}/hoyowiki_index.json');
      await f.writeAsString(
        '{"version":1,"search":{"en-us::Hu Tao":"5125428"},"entries":{}}',
      );
      final loaded = await storage.load();
      expect(loaded.searchMap, {'en-us::Hu Tao': '5125428'});
      expect(loaded.menuIds, isEmpty);
    });

    test('atomic write 不留 .tmp 殘檔', () async {
      await storage.save(const HoyoWikiIndex.empty());
      final tmp = File('${tempDir.path}/hoyowiki_index.json.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('save 兩次 → 後者覆蓋', () async {
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'a::1': 'id1'},
          entries: const {},
          menuIds: const {},
        ),
      );
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'b::2': 'id2'},
          entries: const {},
          menuIds: const {},
        ),
      );
      final loaded = await storage.load();
      expect(loaded.searchMap, {'b::2': 'id2'});
    });
  });

  group('HoyoWikiIndexStorage.clearAll', () {
    test('既有 index 檔被覆寫為空殼', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'en-us::Hu Tao': '111'},
          entries: {
            '111': HoyoWikiEntry(
              iconUrl: 'https://x/icon.png',
              headerImgUrl: 'https://x/header.png',
              fetchedAt: DateTime.utc(2026, 5, 23),
            ),
          },
          menuIds: const {'111': 2},
        ),
      );

      await storage.clearAll();

      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });

    test('index 檔不存在時不爆，仍寫入空殼', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);

      await storage.clearAll();

      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });
  });

  group('hoyowikiCacheFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_cache_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('icon kind + URL .png → <id>_icon.png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x.example/path/icon.png',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('header kind + URL .jpg → <id>_header.jpg', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.header,
        url: 'https://x.example/path/header.jpg',
      );
      expect(f.path, endsWith('5125428_header.jpg'));
    });

    test('URL 帶 query string → 仍取得乾淨副檔名', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x/icon.png?v=1&w=80',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 無副檔名 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: 'https://x/icon',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 為空字串 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoyoWikiImageKind.icon,
        url: '',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });
  });
}
