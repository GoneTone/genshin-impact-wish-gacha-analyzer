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
}
