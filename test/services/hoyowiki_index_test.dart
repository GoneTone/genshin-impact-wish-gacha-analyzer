import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

void main() {
  group('HoyoWikiIndex.lookupId', () {
    test('命中回 id', () {
      final index = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: const {},
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
      );
      expect(index.lookupEntry('5125428'), entry);
    });

    test('未命中回 null', () {
      const index = HoyoWikiIndex.empty();
      expect(index.lookupEntry('5125428'), isNull);
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

    test('save → load roundtrip', () async {
      final original = HoyoWikiIndex(
        searchMap: const {'en-us::Hu Tao': '5125428'},
        entries: {
          '5125428': HoyoWikiEntry(
            iconUrl: 'https://x/icon.png',
            headerImgUrl: '',
            fetchedAt: DateTime.utc(2026, 5, 23, 8),
          ),
        },
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
    });

    test('atomic write 不留 .tmp 殘檔', () async {
      await storage.save(const HoyoWikiIndex.empty());
      final tmp = File('${tempDir.path}/hoyowiki_index.json.tmp');
      expect(await tmp.exists(), isFalse);
    });

    test('save 兩次 → 後者覆蓋', () async {
      await storage.save(
        HoyoWikiIndex(searchMap: const {'a::1': 'id1'}, entries: const {}),
      );
      await storage.save(
        HoyoWikiIndex(searchMap: const {'b::2': 'id2'}, entries: const {}),
      );
      final loaded = await storage.load();
      expect(loaded.searchMap, {'b::2': 'id2'});
    });
  });
}
