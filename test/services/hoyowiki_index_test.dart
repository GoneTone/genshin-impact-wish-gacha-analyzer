import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

void main() {
  group('HoYoWikiIndex.lookupId', () {
    test('命中回 id', () {
      final index = HoYoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
        menuIds: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
    });

    test('未命中回 null', () {
      const index = HoYoWikiIndex.empty();
      expect(index.lookupId(name: 'Hu Tao', lang: 'en-us'), isNull);
    });

    test('lang 不同 → 不命中', () {
      final index = HoYoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
        menuIds: const {},
      );
      expect(index.lookupId(name: 'Hu Tao', lang: 'zh-tw'), isNull);
    });
  });

  group('HoYoWikiIndex.lookupEntry', () {
    test('命中回 entry', () {
      final entry = HoYoWikiEntry(
        iconUrl: 'https://x/icon.png',
        headerImgUrl: 'https://x/header.png',
        fetchedAt: DateTime.utc(2026, 5, 23),
      );
      final index = HoYoWikiIndex(
        searchMap: const {},
        entries: {'5125428': entry},
        menuIds: const {},
      );
      expect(index.lookupEntry('5125428'), entry);
    });

    test('未命中回 null', () {
      const index = HoYoWikiIndex.empty();
      expect(index.lookupEntry('5125428'), isNull);
    });
  });

  group('HoYoWikiIndex.lookupMenuId', () {
    test('命中回 menu_id', () {
      final index = HoYoWikiIndex(
        searchMap: const {},
        entries: const {},
        menuIds: const {'5125428': 2, '9001': 4},
      );
      expect(index.lookupMenuId('5125428'), 2);
      expect(index.lookupMenuId('9001'), 4);
    });

    test('未命中回 null', () {
      const index = HoYoWikiIndex.empty();
      expect(index.lookupMenuId('5125428'), isNull);
    });
  });

  group('HoYoWikiIndexStorage', () {
    late Directory tempDir;
    late HoYoWikiIndexStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_index_test_');
      storage = HoYoWikiIndexStorage(tempDir);
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
      final original = HoYoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: {
          '5125428': HoYoWikiEntry(
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
      await storage.save(const HoYoWikiIndex.empty());
      final tmp = File('${tempDir.path}/hoyowiki_index.json.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('save 兩次 → 後者覆蓋', () async {
      await storage.save(
        HoYoWikiIndex(
          searchMap: const {'a::1': 'id1'},
          entries: const {},
          menuIds: const {},
        ),
      );
      await storage.save(
        HoYoWikiIndex(
          searchMap: const {'b::2': 'id2'},
          entries: const {},
          menuIds: const {},
        ),
      );
      final loaded = await storage.load();
      expect(loaded.searchMap, {'b::2': 'id2'});
    });
  });

  group('HoYoWikiIndexStorage.clearAll', () {
    test('既有 index 檔被覆寫為空殼', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoYoWikiIndexStorage(dir);
      await storage.save(
        HoYoWikiIndex(
          searchMap: const {'en-us::Hu Tao': '111'},
          entries: {
            '111': HoYoWikiEntry(
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
      final storage = HoYoWikiIndexStorage(dir);

      await storage.clearAll();

      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });
  });

  group('HoYoWikiIndexStorage.wipeCacheDirectory', () {
    test('既有 cache 檔被刪光且目錄重建', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_cache_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      // 放兩個 dummy cache 檔
      await File('${dir.path}/111_icon.png').writeAsBytes([1, 2, 3]);
      await File('${dir.path}/111_header.png').writeAsBytes([4, 5, 6]);

      final storage = HoYoWikiIndexStorage(dir);
      await storage.wipeCacheDirectory();

      expect(await dir.exists(), isTrue, reason: '目錄應重建');
      final remaining = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg'))
          .toList();
      expect(remaining, isEmpty, reason: 'cache 圖檔應全被刪');
    });

    test('cache 目錄不存在時不爆，直接建空目錄', () async {
      final parent = await Directory.systemTemp.createTemp('hoyowiki_cache_');
      addTearDown(() async {
        if (await parent.exists()) await parent.delete(recursive: true);
      });
      // 用一個不存在的子目錄做 baseDir
      final dir = Directory('${parent.path}/missing');
      expect(await dir.exists(), isFalse);
      final storage = HoYoWikiIndexStorage(dir);

      await storage.wipeCacheDirectory();

      expect(await dir.exists(), isTrue);
      expect(dir.listSync(), isEmpty);
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
        kind: HoYoWikiImageKind.icon,
        url: 'https://x.example/path/icon.png',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('header kind + URL .jpg → <id>_header.jpg', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoYoWikiImageKind.header,
        url: 'https://x.example/path/header.jpg',
      );
      expect(f.path, endsWith('5125428_header.jpg'));
    });

    test('URL 帶 query string → 仍取得乾淨副檔名', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoYoWikiImageKind.icon,
        url: 'https://x/icon.png?v=1&w=80',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 無副檔名 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoYoWikiImageKind.icon,
        url: 'https://x/icon',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('URL 為空字串 → default .png', () {
      final f = hoyowikiCacheFile(
        baseDir: tempDir,
        id: '5125428',
        kind: HoYoWikiImageKind.icon,
        url: '',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });
  });
}
