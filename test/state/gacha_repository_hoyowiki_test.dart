import 'dart:async';
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
    // 該 entry 沒有 gallery_character module（mock response 未含 modules），
    // 所以 enqueueDownloadsForEntry 只會排 icon 一張。
    expect(downloadCalls.length, 1);

    // bytes 確實落檔到 cache dir
    final cacheFiles = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(cacheFiles.length, 1, reason: 'icon cache file written');
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

  test('該 lang 已有 page（即便空）→ 下次不重抓（pageByLang.containsKey 即視為已抓）', () async {
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
    expect(
      entryCallCount,
      1,
      reason: '新模型下 pageByLang 寫入即視為已抓；空 desc / 無 gallery 不再觸發重抓',
    );
  });

  test('icon 有值且 gallery 有資料 → 下次不重抓（不管 menu_id）', () async {
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
              'page': {
                'icon_url': 'https://x/icon.png',
                'modules': [
                  {
                    'components': [
                      {
                        'component_id': 'gallery_character',
                        'data': jsonEncode({
                          'pic': '',
                          'list': [
                            {
                              'id': 'a',
                              'key': 'k',
                              'img': 'https://x/a.png',
                              'imgDesc': '',
                            },
                          ],
                        }),
                      },
                    ],
                  },
                ],
              },
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
    expect(entryCallCount, 1, reason: 'icon 有值且 gallery 有資料 → 不重抓');
  });

  test('menu_id 4（武器）：icon 有值且 gallery 有資料 → 不重抓', () async {
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
              'page': {
                'icon_url': 'https://x/icon.png',
                'modules': [
                  {
                    'components': [
                      {
                        'component_id': 'gallery_character',
                        'data': jsonEncode({
                          'pic': '',
                          'list': [
                            {
                              'id': 'a',
                              'key': 'k',
                              'img': 'https://x/a.png',
                              'imgDesc': '',
                            },
                          ],
                        }),
                      },
                    ],
                  },
                ],
              },
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
    expect(entryCallCount, 1, reason: 'icon 有值且 gallery 有資料 → 不重抓');
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

  test('download 階段 concurrency 生效（N workers 同時 in-flight）', () async {
    final pending = <Completer<List<int>>>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': req.url.queryParameters['keyword'],
                  'entry_page_id': '111_${req.url.queryParameters['keyword']}',
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
        final id = req.url.queryParameters['entry_page_id']!;
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'page': {
                'icon_url': 'https://x/$id-icon.png',
                'header_img_url': '',
              },
            },
          }),
          200,
        );
      }
      // image download
      final c = Completer<List<int>>();
      pending.add(c);
      final bytes = await c.future;
      return http.Response.bytes(bytes, 200);
    });

    tempDir = await Directory.systemTemp.createTemp('gacha_concurrency_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 23),
        banners: {
          '301': [
            for (var i = 0; i < 12; i++)
              _rec(id: '$i', name: 'Char$i', gachaType: '301'),
          ],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
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
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(
            searchConcurrency: 4,
            entryConcurrency: 4,
            downloadConcurrency: 3,
          ),
        ),
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

    final repoFuture = container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();

    // 等到 download 階段湧出 N 個 in-flight
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (pending.length < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(
      pending.length,
      3,
      reason: 'download concurrency = 3 應同時 in-flight 3 筆',
    );

    // 完成所有 pending 讓 pipeline 跑完
    for (final c in pending) {
      if (!c.isCompleted) c.complete(List<int>.filled(4, 0));
    }
    // 後續 9 筆會陸續上來
    while (pending.length < 12) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final c in pending.where((c) => !c.isCompleted)) {
        c.complete(List<int>.filled(4, 0));
      }
    }
    await repoFuture;
  });

  group('hoyowiki per-lang entry fetch', () {
    test('同 id 兩 lang 都會發 entry_page 請求', () async {
      final entryReqs = <String>[];
      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'message': 'OK',
              'data': {
                'list': [
                  {
                    'name': 'Hu Tao',
                    'entry_page_id': '12345',
                    'menu': {
                      'sub_menus': [
                        {'id': 2, 'name': 'Character'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        }
        if (url.contains('/wapi/entry_page')) {
          final lang = req.headers['X-Rpc-Language'] ?? '';
          final id = Uri.parse(url).queryParameters['entry_page_id'] ?? '';
          entryReqs.add('$id::$lang');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'retcode': 0,
                'message': 'OK',
                'data': {
                  'page': {
                    'icon_url': 'https://x/icon.png',
                    'modules': [
                      {
                        'components': [
                          {
                            'component_id': 'gallery_character',
                            'data': jsonEncode({
                              'pic': 'https://x/p.png',
                              'list': [
                                {
                                  'id': 'a',
                                  'key': 'k-$lang',
                                  'img': 'https://x/a.png',
                                  'imgDesc': '',
                                },
                              ],
                            }),
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
            ),
            200,
          );
        }
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47],
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      // 兩筆 record 同 name 不同 lang
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_perlang_');
      SharedPreferences.setMockInitialValues({});
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '801057625',
          lastUpdated: DateTime.utc(2026, 5, 26),
          banners: {
            '301': [
              _rec(id: '1', name: 'Hu Tao', gachaType: '301', lang: 'zh-tw'),
              _rec(id: '2', name: 'Hu Tao', gachaType: '301', lang: 'en-us'),
            ],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
            '2000': [],
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

      await container
          .read(gachaRepositoryProvider.notifier)
          .debugRunHoYoWikiOnly();

      expect(entryReqs.toSet(), {'12345::zh-tw', '12345::en-us'});

      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      expect(entry.pageByLang.keys.toSet(), {'zh-tw', 'en-us'});
      expect(entry.pageByLang['zh-tw']!.gallery!.list.single.key, 'k-zh-tw');
      expect(entry.pageByLang['en-us']!.gallery!.list.single.key, 'k-en-us');
    });
  });

  group('hoyowiki gallery download', () {
    // gallery 大圖改 lazy fetch（commit 5bf10c3），update flow 只下 icon；
    // 此測試改為確認：icon 落檔、gallery 元資料寫入 index、但 cache 目錄無 gallery 檔。
    test('update flow 僅下 icon；gallery URL 存入 index 但不預先落檔', () async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_dl_');
      SharedPreferences.setMockInitialValues({});

      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'message': 'OK',
              'data': {
                'list': [
                  {
                    'name': 'Hu Tao',
                    'entry_page_id': '12345',
                    'menu': {
                      'sub_menus': [
                        {'id': 2, 'name': 'c'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        }
        if (url.contains('/wapi/entry_page')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'retcode': 0,
                'message': 'OK',
                'data': {
                  'page': {
                    'icon_url': 'https://x/icon.png',
                    'modules': [
                      {
                        'components': [
                          {
                            'component_id': 'gallery_character',
                            'data': jsonEncode({
                              'pic': 'https://x/card.png',
                              'list': [
                                {
                                  'id': 'a',
                                  'key': 'k',
                                  'img': 'https://x/a.gif',
                                  'imgDesc': '',
                                },
                              ],
                            }),
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
            ),
            200,
          );
        }
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47],
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '801057625',
          lastUpdated: DateTime.utc(2026, 5, 26),
          banners: {
            '301': [_rec(id: '1', name: 'Hu Tao', gachaType: '301')],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
            '2000': [],
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

      await container
          .read(gachaRepositoryProvider.notifier)
          .debugRunHoYoWikiOnly();

      final files = Directory(tempDir.path)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      // icon 仍由 update flow 預下
      expect(files.any((f) => f == '12345_icon.png'), isTrue);
      // gallery 大圖不再由 update flow 下載；cache 目錄中不應出現 gallery 檔
      expect(
        files.any((f) => RegExp(r'^12345_gallery_').hasMatch(f)),
        isFalse,
        reason: 'gallery 改 lazy fetch，update flow 不應寫入 gallery 快取檔',
      );

      // gallery URL 仍完整寫入 index（供 dialog lazy fetch 使用）
      final entry = container.read(hoyowikiIndexProvider).lookupEntry('12345')!;
      final gallery = entry.pageByLang['en-us']?.gallery;
      expect(gallery, isNotNull, reason: 'gallery 元資料應存在 index 中');
      expect(gallery!.picUrl, 'https://x/card.png');
      expect(gallery.list.single.imgUrl, 'https://x/a.gif');
    });

    // gallery 大圖改 lazy fetch（commit 5bf10c3），update flow 只下 icon；
    // 跨 lang 的去重邏輯仍存在於 icon 層；此測試確認 icon 只下一次（= 1）。
    test('跨 lang 同 icon URL 只下載一次；gallery 不在 update flow 下載', () async {
      tempDir = await Directory.systemTemp.createTemp('hoyowiki_dedupe_');
      SharedPreferences.setMockInitialValues({});

      var imageDownloadCount = 0;
      final apiClient = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('/wapi/search')) {
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'message': 'OK',
              'data': {
                'list': [
                  {
                    'name': 'Hu Tao',
                    'entry_page_id': '12345',
                    'menu': {
                      'sub_menus': [
                        {'id': 2, 'name': 'c'},
                      ],
                    },
                  },
                ],
              },
            }),
            200,
          );
        }
        if (url.contains('/wapi/entry_page')) {
          // 兩個 lang 都回完全相同的圖 URL
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'retcode': 0,
                'message': 'OK',
                'data': {
                  'page': {
                    'icon_url': 'https://x/icon.png',
                    'modules': [
                      {
                        'components': [
                          {
                            'component_id': 'gallery_character',
                            'data': jsonEncode({
                              'pic': 'https://x/shared.png',
                              'list': [],
                            }),
                          },
                        ],
                      },
                    ],
                  },
                },
              }),
            ),
            200,
          );
        }
        imageDownloadCount++;
        return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47],
          200,
          headers: {'content-type': 'image/png'},
        );
      });

      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '801057625',
          lastUpdated: DateTime.utc(2026, 5, 26),
          banners: {
            '301': [
              _rec(id: '1', name: 'Hu Tao', gachaType: '301', lang: 'zh-tw'),
              _rec(id: '2', name: 'Hu Tao', gachaType: '301', lang: 'en-us'),
            ],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
            '2000': [],
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

      await container
          .read(gachaRepositoryProvider.notifier)
          .debugRunHoYoWikiOnly();

      // icon (1, 跨 lang 共用同 URL 只下一次) = 1 次 image download；
      // gallery shared.png 不在 update flow 下載（lazy fetch by dialog）
      expect(imageDownloadCount, 1);
    });
  });

  test('cancel 在 worker 取下一筆前生效，其餘 item 不被 dispatch', () async {
    final dispatched = <String>[];
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        final kw = req.url.queryParameters['keyword']!;
        dispatched.add(kw);
        // 慢慢回應，留時間讓 cancel 生效
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(
          jsonEncode({
            'retcode': 0,
            'data': {
              'list': [
                {
                  'name': kw,
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
      return http.Response('{}', 200);
    });

    tempDir = await Directory.systemTemp.createTemp('gacha_cancel_test_');
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    await storage.save(
      BannerStorage(
        uid: '801057625',
        lastUpdated: DateTime.utc(2026, 5, 23),
        banners: {
          '301': [
            for (var i = 0; i < 50; i++)
              _rec(id: '$i', name: 'Char$i', gachaType: '301'),
          ],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
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
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(searchConcurrency: 2),
        ),
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

    // 開跑 + 馬上取消（cancelPreparing 設 _cancelTriggered = true）
    final repoFuture = container
        .read(gachaRepositoryProvider.notifier)
        .debugRunHoYoWikiOnly();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    container.read(gachaRepositoryProvider.notifier).cancelPreparing();
    await repoFuture;

    // 50 筆中只應 dispatch 少數幾筆（不可能 50 全跑）
    expect(dispatched.length, lessThan(10));
  });

  test('forceEntryRefetch=true：已解析的 entry 仍重抓並更新 gallery', () async {
    var entryCallCount = 0;
    var galleryListLen = 1;
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
              'page': {
                'icon_url': 'https://x/icon.png',
                'modules': [
                  {
                    'components': [
                      {
                        'component_id': 'gallery_character',
                        'data': jsonEncode({
                          'pic': '',
                          'list': [
                            for (var i = 0; i < galleryListLen; i++)
                              {
                                'id': 'g$i',
                                'key': 'k$i',
                                'img': 'https://x/g$i.png',
                                'imgDesc': '',
                              },
                          ],
                        }),
                      },
                    ],
                  },
                ],
              },
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);

    // 第一次增量抓取：entry 抓 1 次，gallery 1 張
    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1);
    expect(
      container
          .read(hoyowikiIndexProvider)
          .lookupEntry('111')!
          .pageByLang['en-us']!
          .gallery!
          .list
          .length,
      1,
    );

    // HoYoWiki 端新增一張 gallery 圖
    galleryListLen = 2;

    // 非 force：已抓過 → 不重抓，gallery 仍是舊的 1 張
    await notifier.debugRunHoYoWikiOnly();
    expect(entryCallCount, 1, reason: '非 force 模式不重抓已解析 entry');

    // force：強制重抓 entry → gallery 更新為 2 張
    await notifier.debugRunHoYoWikiOnly(forceEntryRefetch: true);
    expect(entryCallCount, 2, reason: 'force 模式重抓已解析 entry');
    expect(
      container
          .read(hoyowikiIndexProvider)
          .lookupEntry('111')!
          .pageByLang['en-us']!
          .gallery!
          .list
          .length,
      2,
      reason: 'force 重抓後 mergeEntry 覆蓋 gallery，新圖出現',
    );

    // gallery 大圖不應被 eager 下載（維持 lazy）
    final galleryFiles = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'111_gallery_').hasMatch(f.path))
        .toList();
    expect(galleryFiles, isEmpty, reason: 'gallery 維持 lazy，不在更新流程下載');
  });

  test(
    'refreshAllHoYoWikiMetadata：非破壞性重抓，保留 icon、emit UpdateCompleted',
    () async {
      var entryCallCount = 0;
      var imageDownloadCount = 0;
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
                'page': {
                  'icon_url': 'https://x/icon.png',
                  'header_img_url': '',
                },
              },
            }),
            200,
          );
        }
        imageDownloadCount++;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final container = await setupContainer(apiClient: apiClient);
      final notifier = container.read(gachaRepositoryProvider.notifier);

      // 先增量抓一次：建立 index + icon 快取檔
      await notifier.debugRunHoYoWikiOnly();
      expect(entryCallCount, 1);
      expect(imageDownloadCount, 1, reason: '第一次下 icon');
      final iconFile = File('${tempDir.path}/111_icon.png');
      expect(iconFile.existsSync(), isTrue);

      // 非破壞性更新
      await notifier.refreshAllHoYoWikiMetadata();

      // entry 被強制重抓；icon 已在快取 → 不重下；icon 檔仍在（未被 wipe）
      expect(entryCallCount, 2, reason: 'force 重抓 entry');
      expect(imageDownloadCount, 1, reason: 'icon 已快取，缺才下 → 不重下');
      expect(iconFile.existsSync(), isTrue, reason: '非破壞性：既有快取保留');

      // 結束狀態為 UpdateCompleted
      expect(
        container.read(gachaRepositoryProvider).progress,
        isA<UpdateCompleted>(),
      );

      // hoyoWikiEntriesRefreshed 應為 1（Hu Tao，相異物品數）
      final done =
          container.read(gachaRepositoryProvider).progress as UpdateCompleted;
      expect(done.hoyoWikiEntriesRefreshed, 1);
      expect(done.hoYoWikiImagesDownloaded, 0, reason: 'icon 已快取，不重下');
    },
  );

  test(
    'refreshAllHoYoWikiMetadata：同 id 兩 lang → hoyoWikiEntriesRefreshed 為 1（相異 id，非 lang 配對數）',
    () async {
      var entryCallCount = 0;
      final apiClient = MockClient((req) async {
        if (req.url.path.endsWith('/search')) {
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
          entryCallCount++;
          return http.Response(
            jsonEncode({
              'retcode': 0,
              'data': {
                'page': {
                  'icon_url': 'https://x/icon.png',
                  'header_img_url': '',
                },
              },
            }),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      });

      // 兩筆 record：同 name（Hu Tao）不同 lang
      tempDir = await Directory.systemTemp.createTemp('gacha_hoyowiki_2lang_');
      SharedPreferences.setMockInitialValues({});
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '801057625',
          lastUpdated: DateTime.utc(2026, 6, 18),
          banners: {
            '301': [
              _rec(id: '1', name: 'Hu Tao', gachaType: '301', lang: 'zh-tw'),
              _rec(id: '2', name: 'Hu Tao', gachaType: '301', lang: 'en-us'),
            ],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
            '2000': [],
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

      await container
          .read(gachaRepositoryProvider.notifier)
          .refreshAllHoYoWikiMetadata();

      // 兩 lang 各一次 entry 請求
      expect(entryCallCount, 2, reason: '同 id 兩 lang 各發一次 entry_page');

      final done =
          container.read(gachaRepositoryProvider).progress as UpdateCompleted;
      // 雖然 entry 階段處理了 2 個 (id, lang) 配對，相異 id 只有 1 個
      expect(done.hoyoWikiEntriesRefreshed, 1, reason: '相異 id 只有 1 個');
    },
  );

  test('refreshAllHoYoWikiMetadata 清掉殘留語言（stale zh-tw page 被移除）', () async {
    final apiClient = MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
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

    // setupContainer 預設記錄 lang = en-us（_rec 預設值）
    final container = await setupContainer(apiClient: apiClient);
    final notifier = container.read(gachaRepositoryProvider.notifier);
    final indexNotifier = container.read(hoyowikiIndexProvider.notifier);

    // 先跑一次 hoyowiki，建立 en-us 的 search + entry
    await notifier.debugRunHoYoWikiOnly();
    expect(
      container.read(hoyowikiIndexProvider).lookupEntry('111'),
      isNotNull,
      reason: 'en-us entry 應已建立',
    );

    // 手動注入一個不在記錄中的 zh-tw 殘留 page
    await indexNotifier.mergeEntry(
      id: '111',
      lang: 'zh-tw',
      fetched: const HoYoWikiEntryFetched(
        iconUrl: 'https://x/icon.png',
        page: HoYoWikiPageData(gallery: null, desc: '繁中說明', tags: []),
      ),
    );
    // 確認此時兩 lang 均在
    expect(
      container
          .read(hoyowikiIndexProvider)
          .lookupEntry('111')!
          .pageByLang
          .keys
          .toSet(),
      containsAll(['en-us', 'zh-tw']),
    );

    // 執行 refreshAllHoYoWikiMetadata（含 pruneStaleLangs = true）
    await notifier.refreshAllHoYoWikiMetadata();

    // 殘留的 zh-tw 應被清除；en-us 仍在
    final entry = container.read(hoyowikiIndexProvider).lookupEntry('111')!;
    expect(
      entry.pageByLang.containsKey('zh-tw'),
      isFalse,
      reason: '殘留的 zh-tw page 應被 pruneLanguages 清除',
    );
    expect(
      entry.pageByLang.containsKey('en-us'),
      isTrue,
      reason: 'en-us page 應仍保留',
    );
  });
}
