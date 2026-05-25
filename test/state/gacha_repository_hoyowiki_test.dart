import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

GachaRecord _rec({
  required String id,
  required String name,
  required String gachaType,
  String lang = 'en-us',
}) => GachaRecord(
  id: id,
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 23),
  lang: lang,
);

void main() {
  late Directory tempDir;

  Future<ProviderContainer> setupContainer({
    required MockClient apiClient,
  }) async {
    tempDir = await Directory.systemTemp.createTemp('gacha_hoyowiki_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 23),
        banners: {
          '301': [_rec(id: '1', name: 'Hu Tao', gachaType: '301')],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
          '2000': [_rec(id: '2', name: 'OdesItem', gachaType: '2000')],
          '1000': [],
        },
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    return container;
  }

  test('FetchingHoYoWiki 階段：祈願 record 進 worklist，頌願不進', () async {
    final searchCalls = <String>[];
    final entryCalls = <String>[];
    final downloadCalls = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalls.add(req.url.queryParameters['keyword']!);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': req.url.queryParameters['keyword'],
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCalls.add(req.url.queryParameters['entry_page_id']!);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url':
                    'https://x/${req.url.queryParameters['entry_page_id']}_icon.png',
                'header_img_url':
                    'https://x/${req.url.queryParameters['entry_page_id']}_header.png',
              },
            },
          }),
          200,
        );
      }
      downloadCalls.add(req.url.toString());
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    await container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();

    // 只祈願 record (Hu Tao) 進 search，頌願 (OdesItem) 不進
    expect(searchCalls, ['Hu Tao']);
    expect(entryCalls, ['111']);
    // icon + header 兩個下載
    expect(downloadCalls.length, 2);

    // bytes 確實落檔到 cache dir
    final cacheFiles = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(cacheFiles.length, 2, reason: 'icon + header cache files written');
  });

  test('hoyowiki 階段失敗不影響後續（每個 item 獨立 try/catch）', () async {
    final searchCalls = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalls.add(req.url.queryParameters['keyword']!);
        return http.Response(
          jsonEncode({'retcode': -1, 'message': 'fail', 'data': null}),
          200,
        );
      }
      return http.Response('', 404);
    });
    final container = await setupContainer(apiClient: apiClient);
    await container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();

    expect(searchCalls, ['Hu Tao']);
    // index 維持空（沒寫入失敗的）
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap, isEmpty);
  });

  test('已 search 命中的不再重 search', () async {
    final searchCalls = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        searchCalls.add(req.url.queryParameters['keyword']!);
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {'icon_url': 'https://x/icon.png', 'header_img_url': ''},
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoYoWikiOnly();
    expect(searchCalls.length, 1);

    await notifier.debugRunHoYoWikiOnly();
    expect(searchCalls.length, 1, reason: '第二次不應再 search');
  });

  test('menu_id 2（角色）：兩個 URL 都空 → 下次重抓', () async {
    var entryCallCount = 0;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {'icon_url': '', 'header_img_url': ''},
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 2, reason: 'menu_id 2：兩個 URL 都空應視為 incomplete，下次重抓');
  });

  test('menu_id 2（角色）：header 為空但 icon 有 → 下次仍重抓', () async {
    var entryCallCount = 0;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 2},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {'icon_url': 'https://x/icon.png', 'header_img_url': ''},
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 2, reason: 'menu_id 2：header 空 → 嚴格規則，下次重抓');
  });

  test('menu_id 4（武器）：只有 icon 無 header → 不重抓', () async {
    // 武器（menu_id 4）寬鬆規則：有任一 URL 就不重抓
    var entryCallCount = 0;
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': 'Hu Tao',
                  'entry_page_id': '111',
                  'menu': {
                    'sub_menus': [
                      {'id': 4},
                    ],
                  },
                },
              ],
            },
          }),
          200,
        );
      }
      if (req.url.path.endsWith('/entry_page')) {
        entryCallCount++;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {'icon_url': 'https://x/icon.png', 'header_img_url': ''},
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);

    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1, reason: 'menu_id 4：有 icon → 寬鬆規則，不重抓');
  });

  test(
    '_fetchHoYoWiki 三段 phase 依序推進（searching → fetchingEntries → downloading）',
    () async {
      final phases = <HoYoWikiPhase>[];
      final apiClient = MockClient((req) async {
        if (req.url.path.endsWith('/search')) {
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'data': {
                'list': [
                  {
                    'name': 'Hu Tao',
                    'entry_page_id': '111',
                    'menu': {
                      'sub_menus': [
                        {'id': 2},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/entry_page')) {
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'data': {
                'page': {
                  'icon_url': 'https://x/icon.png',
                  'header_img_url': 'https://x/header.png',
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      });
      final container = await setupContainer(apiClient: apiClient);

      container.listen(gachaRepositoryProvider.select((s) => s.progress), (
        _,
        next,
      ) {
        if (next is FetchingHoYoWiki) phases.add(next.phase);
      });

      await container
          .read(gachaRepositoryProvider.notifier)
          .debugRunHoYoWikiOnly();

      // 三段都出現過，且順序為 searching → fetchingEntries → downloading
      expect(
        phases,
        containsAll([
          HoYoWikiPhase.searching,
          HoYoWikiPhase.fetchingEntries,
          HoYoWikiPhase.downloading,
        ]),
      );
      final firstSearchIdx = phases.indexOf(HoYoWikiPhase.searching);
      final firstEntryIdx = phases.indexOf(HoYoWikiPhase.fetchingEntries);
      final firstDownloadIdx = phases.indexOf(HoYoWikiPhase.downloading);
      expect(firstSearchIdx, lessThan(firstEntryIdx));
      expect(firstEntryIdx, lessThan(firstDownloadIdx));
    },
  );
}
