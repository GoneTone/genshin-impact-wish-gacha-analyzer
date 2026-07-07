import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// load 被閘門扣住的 storage，用於決定性重現「載入完成前就有寫入」的時序。
class _GatedLoadStorage extends HoYoWikiIndexStorage {
  /// 建立 [_GatedLoadStorage]。
  _GatedLoadStorage(super.baseDir);

  /// load 開始前等待的閘門；complete 後才真正讀檔。
  final loadGate = Completer<void>();

  /// 等 [loadGate] 開啟後才讀檔。
  @override
  Future<HoYoWikiIndex> load() async {
    await loadGate.future;
    return super.load();
  }
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hoyowiki_state_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
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
    final reloaded = await HoYoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupId(name: 'Hu Tao', lang: 'en-us'), '5125428');
    expect(reloaded.lookupMenuId('5125428'), 2);
  });

  test('setSearches 批次套用多筆並 persist', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setSearches([
      (name: 'Hu Tao', lang: 'en-us', id: '1', menuId: 2),
      (name: '胡桃', lang: 'zh-tw', id: '1', menuId: 2),
      (name: 'Staff of Homa', lang: 'en-us', id: '2', menuId: 4),
    ]);
    final idx = container.read(hoyowikiIndexProvider);
    expect(idx.lookupId(name: 'Hu Tao', lang: 'en-us'), '1');
    expect(idx.lookupId(name: '胡桃', lang: 'zh-tw'), '1');
    expect(idx.lookupId(name: 'Staff of Homa', lang: 'en-us'), '2');
    expect(idx.lookupMenuId('1'), 2);
    expect(idx.lookupMenuId('2'), 4);
    // persist 後可重新 load 回來
    final reloaded = await HoYoWikiIndexStorage(tempDir).load();
    expect(reloaded.lookupId(name: '胡桃', lang: 'zh-tw'), '1');
    expect(reloaded.lookupMenuId('2'), 4);
  });

  test('setSearches 空輸入為 no-op', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.setSearches(const []);
    expect(container.read(hoyowikiIndexProvider).searchMap, isEmpty);
  });

  test('初始載入完成前的寫入不得覆寫磁碟上的既有 index（迴歸：雲端同步啟動合併）', () async {
    // 磁碟上已有完整 index（模擬長期累積的物品資料）。
    await HoYoWikiIndexStorage(tempDir).save(
      const HoYoWikiIndex(
        searchMap: {'en-us::Hu Tao': '5125428'},
        entries: {},
        menuIds: {'5125428': 2},
      ),
    );

    // 用可閘控 load 的 storage 讓「載入未完成」的時序決定性重現：
    // 啟動時雲端同步的合併（setSearches）可能比 index 檔載入先跑到。
    final gated = _GatedLoadStorage(tempDir);
    final raceContainer = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(gated),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(raceContainer.dispose);
    final notifier = raceContainer.read(hoyowikiIndexProvider.notifier);

    // 載入尚未完成就寫入一筆新 hint。
    final mutation = notifier.setSearches([
      (name: 'Zhongli', lang: 'en-us', id: '999', menuId: 2),
    ]);
    gated.loadGate.complete();
    await mutation;
    await notifier.waitForLoad();

    // 磁碟上既有資料必須還在，且新 hint 也已套用。
    final reloaded = await HoYoWikiIndexStorage(tempDir).load();
    expect(
      reloaded.lookupId(name: 'Hu Tao', lang: 'en-us'),
      '5125428',
      reason: '載入前的寫入不得以空 index 覆寫磁碟',
    );
    expect(reloaded.lookupId(name: 'Zhongli', lang: 'en-us'), '999');
  });

  test('mergeEntry 更新 state 並 persist', () async {
    final notifier = container.read(hoyowikiIndexProvider.notifier);
    await notifier.waitForLoad();
    await notifier.mergeEntry(
      id: '5125428',
      lang: 'en-us',
      fetched: const HoYoWikiEntryFetched(
        iconUrl: 'https://x/icon.png',
        page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
      ),
    );
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('5125428')?.iconUrl,
      'https://x/icon.png',
    );
    final reloaded = await HoYoWikiIndexStorage(tempDir).load();
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

  group('HoYoWikiIndexNotifier.resetAll', () {
    test('清空 index、刪除 cache 目錄、state identity 換新', () async {
      final dir = await Directory.systemTemp.createTemp('hoyowiki_notifier_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final storage = HoYoWikiIndexStorage(dir);
      // 預植 index 與一個 cache 檔
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
        reason: 'state = const HoYoWikiIndex.empty() 應換新 identity',
      );
      // cache 檔應已刪
      expect(File('${dir.path}/111_icon.png').existsSync(), isFalse);
    });
  });

  group('HoYoWikiIndexNotifier concurrent writes', () {
    test('並發 mergeEntry 全部寫入不丟失', () async {
      final raceTempDir = await Directory.systemTemp.createTemp(
        'hoyowiki_index_race_',
      );
      addTearDown(() async {
        if (await raceTempDir.exists()) {
          await raceTempDir.delete(recursive: true);
        }
      });
      final raceContainer = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(
            _SlowSaveStorage(raceTempDir),
          ),
        ],
      );
      addTearDown(raceContainer.dispose);
      final notifier = raceContainer.read(hoyowikiIndexProvider.notifier);
      await notifier.waitForLoad();

      // 同時跑 10 個 mergeEntry：無 lock 時各自從相同 baseline Map.from(state.entries)
      // 拿快照、寫回時後者覆蓋前者，final 只剩最後一筆。
      await Future.wait(
        List.generate(
          10,
          (i) => notifier.mergeEntry(
            id: 'id_$i',
            lang: 'en-us',
            fetched: HoYoWikiEntryFetched(
              iconUrl: 'http://x/$i.png',
              page: const HoYoWikiPageData(gallery: null, desc: '', tags: []),
            ),
          ),
        ),
      );

      final finalState = raceContainer.read(hoyowikiIndexProvider);
      expect(finalState.entries.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(finalState.entries['id_$i']?.iconUrl, 'http://x/$i.png');
      }
    });
  });

  group('HoYoWikiIndexNotifier.pruneLanguages', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pruneLanguages_test_');
      container = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        ],
      );
      addTearDown(container.dispose);
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('清掉殘留語言、保留當前語言', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      // 寫入同一 id 的 zh-tw 與 en-us 兩個 page
      await notifier.mergeEntry(
        id: '999',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '繁中說明', tags: ['tag1']),
        ),
      );
      await notifier.mergeEntry(
        id: '999',
        lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(gallery: null, desc: 'en desc', tags: []),
        ),
      );
      // 確認兩 lang 均在
      expect(
        container
            .read(hoyowikiIndexProvider)
            .lookupEntry('999')!
            .pageByLang
            .keys
            .toSet(),
        {'zh-tw', 'en-us'},
      );

      // pruneLanguages 只保留 zh-tw → 回傳 1（1 個物品被清理）
      final pruned = await notifier.pruneLanguages({'zh-tw'});
      expect(pruned, 1);

      final entry = container.read(hoyowikiIndexProvider).lookupEntry('999')!;
      expect(entry.pageByLang.keys.toSet(), {'zh-tw'});
      // iconUrl 與 zh-tw page 保留
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.pageByLang['zh-tw']!.desc, '繁中說明');
    });

    test('無變動為 no-op（keepLangs 為超集）', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '888',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '內容', tags: []),
        ),
      );
      final before = container.read(hoyowikiIndexProvider);

      // keepLangs 為超集（包含比實際存在更多的 lang）→ 回傳 0（無物品被清理）
      final pruned = await notifier.pruneLanguages({'zh-tw', 'en-us'});
      expect(pruned, 0);

      final after = container.read(hoyowikiIndexProvider);
      // 無實際變動 → entry 內容不變
      expect(after.lookupEntry('888')!.pageByLang.keys.toSet(), {'zh-tw'});
      expect(
        after.lookupEntry('888')!.iconUrl,
        before.lookupEntry('888')!.iconUrl,
      );
      // 無變動時不應重建 index state
      expect(identical(before, after), isTrue, reason: '無變動時不應重建 index');
    });

    test('空 keepLangs 為 no-op，回傳 0', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '777',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '內容', tags: []),
        ),
      );
      final before = container.read(hoyowikiIndexProvider);

      // 空 keepLangs → no-op，回傳 0
      final pruned = await notifier.pruneLanguages({});
      expect(pruned, 0);

      // state 應未變動
      final after = container.read(hoyowikiIndexProvider);
      expect(
        identical(before, after),
        isTrue,
        reason: '空 keepLangs 不應變動 index',
      );
    });
  });

  group('HoYoWikiIndexNotifier.mergeEntry', () {
    late Directory tempDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mergeEntry_test_');
      container = ProviderContainer(
        overrides: [
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        ],
      );
      addTearDown(container.dispose);
      await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('首次寫入：lang gallery 寫進去', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(
              picUrl: 'https://x/card.png',
              list: [
                HoYoWikiGalleryItem(
                  id: 'a',
                  key: '原畫',
                  imgUrl: 'https://x/a.png',
                  imgDescHtml: '',
                ),
              ],
            ),
            desc: '',
            tags: [],
          ),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.pageByLang['zh-tw']!.gallery!.list.single.key, '原畫');
    });

    test('第二次寫入不同 lang：既有 lang 保留', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(picUrl: 'https://x/zh.png', list: []),
            desc: '',
            tags: [],
          ),
        ),
      );
      await notifier.mergeEntry(
        id: '12345',
        lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(picUrl: 'https://x/en.png', list: []),
            desc: '',
            tags: [],
          ),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.pageByLang.keys.toSet(), {'zh-tw', 'en-us'});
      expect(entry.pageByLang['zh-tw']!.gallery!.picUrl, 'https://x/zh.png');
      expect(entry.pageByLang['en-us']!.gallery!.picUrl, 'https://x/en.png');
    });

    test('icon 非空覆寫：空 icon 不會把既有好值清掉', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(picUrl: 'https://x/zh.png', list: []),
            desc: '',
            tags: [],
          ),
        ),
      );
      await notifier.mergeEntry(
        id: '12345',
        lang: 'en-us',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: '',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(picUrl: 'https://x/en.png', list: []),
            desc: '',
            tags: [],
          ),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');
    });

    test('gallery 為 null：寫入該 lang page（含空 gallery），icon 仍可更新', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '12345',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(gallery: null, desc: '', tags: []),
        ),
      );
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.iconUrl, 'https://x/icon.png');
      expect(entry.pageByLang.keys.toSet(), {'zh-tw'});
      expect(entry.pageByLang['zh-tw']!.gallery, isNull);
    });

    test('mergeEntry 寫入完整 page（gallery + desc + tags）', () async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.mergeEntry(
        id: '5125428',
        lang: 'zh-tw',
        fetched: const HoYoWikiEntryFetched(
          iconUrl: 'https://x/icon.png',
          page: HoYoWikiPageData(
            gallery: HoYoWikiGalleryData(
              picUrl: 'https://x/card.png',
              list: [],
            ),
            desc: '「往生堂」...',
            tags: ['生命之契', '4星'],
          ),
        ),
      );
      final page = container
          .read(hoyowikiIndexProvider)
          .lookupEntry('5125428')!
          .pageByLang['zh-tw']!;
      expect(page.gallery!.picUrl, 'https://x/card.png');
      expect(page.desc, '「往生堂」...');
      expect(page.tags, ['生命之契', '4星']);
    });
  });
}

/// 強制 save 內出現 async gap，迫使 read-modify-write race 觀察得到。
class _SlowSaveStorage extends HoYoWikiIndexStorage {
  _SlowSaveStorage(super.baseDir);

  @override
  Future<void> save(HoYoWikiIndex index) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await super.save(index);
  }
}
