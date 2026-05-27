import 'dart:convert';
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
        pageByLang: const {},
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
            pageByLang: const {},
            fetchedAt: DateTime.utc(2026, 5, 23, 8),
          ),
        },
        menuIds: const {'5125428': 2},
      );
      await storage.save(original);
      final loaded = await storage.load();
      expect(loaded.searchMap, original.searchMap);
      expect(loaded.entries['5125428']!.iconUrl, 'https://x/icon.png');
      expect(loaded.entries['5125428']!.pageByLang, isEmpty);
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
              pageByLang: const {},
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

    test('baseDir 整個被外部刪除時不爆（force refetch 場景）', () async {
      final parent = await Directory.systemTemp.createTemp('hoyowiki_storage_');
      addTearDown(() async {
        if (await parent.exists()) await parent.delete(recursive: true);
      });
      // 模擬「使用者手動刪除整個 hoyowiki_cache/」：baseDir 直接不存在。
      final dir = Directory('${parent.path}/missing_cache');
      expect(await dir.exists(), isFalse);
      final storage = HoYoWikiIndexStorage(dir);

      await storage.clearAll();

      expect(await dir.exists(), isTrue, reason: 'save 應自動建立缺失的父目錄');
      final reloaded = await storage.load();
      expect(reloaded.searchMap, isEmpty);
      expect(reloaded.entries, isEmpty);
      expect(reloaded.menuIds, isEmpty);
    });
  });

  group('HoYoWikiIndexStorage.deleteGalleryCacheFiles', () {
    late Directory tempDir;
    late HoYoWikiIndexStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_storage_test_');
      storage = HoYoWikiIndexStorage(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    Future<File> touch(String name) async {
      final f = File('${tempDir.path}/$name');
      await f.writeAsBytes([0]);
      return f;
    }

    test('只刪 *_gallery_* 檔，icon 與 index JSON 保留', () async {
      final icon = await touch('abc_icon.png');
      final gal1 = await touch('abc_gallery_aaaaaaaaaaaa.png');
      final gal2 = await touch('def_gallery_bbbbbbbbbbbb.jpg');
      final idx = await touch('hoyowiki_index.json');

      await storage.deleteGalleryCacheFiles();

      expect(icon.existsSync(), isTrue);
      expect(gal1.existsSync(), isFalse);
      expect(gal2.existsSync(), isFalse);
      expect(idx.existsSync(), isTrue);
    });

    test('目錄不存在 → 不拋例外', () async {
      await tempDir.delete(recursive: true);
      await storage.deleteGalleryCacheFiles();
      // 沒拋就算過
    });

    test('沒有任何 gallery 檔 → no-op', () async {
      await touch('abc_icon.png');
      await storage.deleteGalleryCacheFiles();
      expect(File('${tempDir.path}/abc_icon.png').existsSync(), isTrue);
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

  group('hoyowikiIconCacheFile', () {
    final baseDir = Directory.systemTemp;

    test('組合為 <id>_icon.<ext>', () {
      final f = hoyowikiIconCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/icon.png',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });

    test('無副檔名時 fallback png', () {
      final f = hoyowikiIconCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/icon',
      );
      expect(f.path, endsWith('5125428_icon.png'));
    });
  });

  group('hoyowikiGalleryCacheFile', () {
    final baseDir = Directory.systemTemp;

    test('同 URL → 同檔名', () {
      final a = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      final b = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      expect(a.path, b.path);
    });

    test('不同 URL → 不同檔名', () {
      final a = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.png',
      );
      final b = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/b.png',
      );
      expect(a.path, isNot(b.path));
    });

    test('檔名格式為 <id>_gallery_<hash12>.<ext>', () {
      final f = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.gif',
      );
      expect(
        RegExp(r'5125428_gallery_[0-9a-f]{12}\.gif$').hasMatch(f.path),
        isTrue,
      );
    });

    test('帶 query string 不影響 ext 推導', () {
      final f = hoyowikiGalleryCacheFile(
        baseDir: baseDir,
        id: '5125428',
        url: 'https://x/a.webp?token=abc',
      );
      expect(f.path, endsWith('.webp'));
    });
  });

  group('HoYoWikiIndexStorage v3 schema', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_storage_v3_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('round trip：page_by_lang 完整保存 gallery + desc + tags', () async {
      final storage = HoYoWikiIndexStorage(tempDir);
      final index = HoYoWikiIndex(
        searchMap: const {'zh-tw::胡桃': '5125428'},
        entries: {
          '5125428': HoYoWikiEntry(
            iconUrl: 'https://x/icon.png',
            pageByLang: {
              'zh-tw': const HoYoWikiPageData(
                gallery: HoYoWikiGalleryData(
                  picUrl: 'https://x/card.png',
                  list: [
                    HoYoWikiGalleryItem(
                      id: 'g1',
                      key: '原畫',
                      imgUrl: 'https://x/c.png',
                      imgDescHtml: '<p>x</p>',
                    ),
                  ],
                ),
                desc: '「往生堂」...',
                tags: ['生命之契', '4星', '蒙德'],
              ),
            },
            fetchedAt: DateTime.utc(2026, 5, 26),
          ),
        },
        menuIds: const {'5125428': 2},
      );
      await storage.save(index);
      final reloaded = await storage.load();
      final page = reloaded.lookupEntry('5125428')!.pageByLang['zh-tw']!;
      expect(page.gallery!.picUrl, 'https://x/card.png');
      expect(page.gallery!.list, hasLength(1));
      expect(page.desc, '「往生堂」...');
      expect(page.tags, ['生命之契', '4星', '蒙德']);
    });

    test('gallery 為 null 的 page（武器頁）也能 round trip', () async {
      final storage = HoYoWikiIndexStorage(tempDir);
      final index = HoYoWikiIndex(
        searchMap: const {'en-us::Sword': '9001'},
        entries: {
          '9001': HoYoWikiEntry(
            iconUrl: 'https://x/sword.png',
            pageByLang: const {
              'en-us': HoYoWikiPageData(
                gallery: null,
                desc: 'A sharp blade.',
                tags: ['4★', 'Sword'],
              ),
            },
            fetchedAt: DateTime.utc(2026, 5, 26),
          ),
        },
        menuIds: const {'9001': 4},
      );
      await storage.save(index);
      final reloaded = await storage.load();
      final page = reloaded.lookupEntry('9001')!.pageByLang['en-us']!;
      expect(page.gallery, isNull);
      expect(page.desc, 'A sharp blade.');
      expect(page.tags, ['4★', 'Sword']);
    });
  });

  group('HoYoWikiIndexStorage v1/v2 → v3 migration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_storage_mig_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test(
      'v2 cache 載入：pageByLang reset 為空、icon_url / search / menu_ids 保留',
      () async {
        final v2 = {
          'version': 2,
          'search': {'zh-tw::胡桃': '5125428'},
          'menu_ids': {'5125428': 2},
          'entries': {
            '5125428': {
              'icon_url': 'https://x/icon.png',
              'fetched_at': '2026-05-25T10:00:00.000Z',
              'gallery_by_lang': {
                'zh-tw': {'pic_url': 'https://x/card.png', 'list': []},
              },
            },
          },
        };
        final f = File('${tempDir.path}/hoyowiki_index.json');
        await f.writeAsString(jsonEncode(v2));
        final storage = HoYoWikiIndexStorage(tempDir);
        final loaded = await storage.load();
        final entry = loaded.lookupEntry('5125428')!;
        expect(entry.iconUrl, 'https://x/icon.png');
        expect(entry.pageByLang, isEmpty);
        expect(loaded.lookupId(name: '胡桃', lang: 'zh-tw'), '5125428');
        expect(loaded.lookupMenuId('5125428'), 2);
      },
    );

    test('v1 cache 載入：pageByLang reset 為空、header_img_url 丟棄', () async {
      final v1 = {
        'version': 1,
        'search': {'en-us::Sword': '9001'},
        'menu_ids': {'9001': 4},
        'entries': {
          '9001': {
            'icon_url': 'https://x/sword.png',
            'header_img_url': 'https://x/header.png',
            'fetched_at': '2026-05-25T10:00:00.000Z',
          },
        },
      };
      final f = File('${tempDir.path}/hoyowiki_index.json');
      await f.writeAsString(jsonEncode(v1));
      final storage = HoYoWikiIndexStorage(tempDir);
      final loaded = await storage.load();
      final entry = loaded.lookupEntry('9001')!;
      expect(entry.iconUrl, 'https://x/sword.png');
      expect(entry.pageByLang, isEmpty);
    });

    test('檔案不存在 → 回空 index', () async {
      final loaded = await HoYoWikiIndexStorage(tempDir).load();
      expect(loaded.entries, isEmpty);
      expect(loaded.searchMap, isEmpty);
    });
  });
}
