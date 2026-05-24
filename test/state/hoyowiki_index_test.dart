import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hoyowiki_state_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoyoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('hoyowikiIndexProvider 初始為空 index', () async {
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap, isEmpty);
    expect(index.entries, isEmpty);
    // 等 _load() 完成
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    expect(container.read(hoyowikiIndexProvider).searchMap, isEmpty);
  });

  test('setSearch 更新 state 並 persist（含 menuId）', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setSearch(
      name: 'Hu Tao',
      lang: 'en-us',
      id: '5125428',
      menuId: 2,
    );
    expect(
      container
          .read(hoyowikiIndexProvider)
          .lookupId(name: 'Hu Tao', lang: 'en-us'),
      '5125428',
    );
    expect(container.read(hoyowikiIndexProvider).lookupMenuId('5125428'), 2);
    // 重新 load 一次確認 persist
    final reloaded = await HoyoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
    expect(reloaded.lookupMenuId('5125428'), 2);
  });

  test('setEntry 更新 state 並 persist', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    final entry = HoyoWikiEntry(
      iconUrl: 'https://x/icon.png',
      headerImgUrl: '',
      fetchedAt: DateTime.utc(2026, 5, 23),
    );
    await notifier.setEntry(id: '5125428', entry: entry);
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('5125428')?.iconUrl,
      'https://x/icon.png',
    );
    final reloaded = await HoyoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupEntry('5125428')?.iconUrl, 'https://x/icon.png');
  });

  test('bumpCacheRevision 觸發 state 更新（supplies new identity）', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    final before = container.read(hoyowikiIndexProvider);
    notifier.bumpCacheRevision();
    final after = container.read(hoyowikiIndexProvider);
    expect(identical(before, after), isFalse);
    expect(after.searchMap, before.searchMap);
  });

  group('HoyoWikiIndexNotifier.resetAll', () {
    test('清空 index、刪除 cache 目錄、cacheRevision 遞增', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_notifier_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoyoWikiIndexStorage(dir);
      // 預植 index 與一個 cache 檔
      await storage.save(
        HoyoWikiIndex(
          searchMap: const {'en-us::Hu Tao': '111'},
          entries: {
            '111': HoyoWikiEntry(
              iconUrl: 'https://x/icon.png',
              headerImgUrl: '',
              fetchedAt: DateTime.utc(2026, 5, 23),
            ),
          },
          menuIds: const {'111': 2},
        ),
      );
      await File('${dir.path}/111_icon.png').writeAsBytes([1, 2, 3]);

      final container = ProviderContainer(
        overrides: [hoyowikiIndexStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.waitForLoad();
      final before = container.read(hoyowikiIndexProvider);
      expect(before.searchMap, isNotEmpty);

      await notifier.resetAll();

      final after = container.read(hoyowikiIndexProvider);
      expect(after.searchMap, isEmpty);
      expect(after.entries, isEmpty);
      expect(after.menuIds, isEmpty);
      expect(
        identical(after, before),
        isFalse,
        reason: 'bumpCacheRevision 應換新 identity',
      );
      // cache 檔應已刪
      expect(File('${dir.path}/111_icon.png').existsSync(), isFalse);
    });
  });
}
