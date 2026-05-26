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
    test('gallery 圖檔下載到 <id>_gallery_<hash>.<ext>', () async {
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
      expect(files.any((f) => f == '12345_icon.png'), isTrue);
      expect(
        files.any(
          (f) => RegExp(r'^12345_gallery_[0-9a-f]{12}\.gif$').hasMatch(f),
        ),
        isTrue,
      );
      expect(
        files.any(
          (f) => RegExp(r'^12345_gallery_[0-9a-f]{12}\.png$').hasMatch(f),
        ),
        isTrue,
      );
    });

    test('跨 lang 同 URL 只下載一次', () async {
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
          // 兩個 lang 都回完全相同的圖 URL → 應該共用一份檔
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

      // icon (1) + shared.png (1, 跨 lang 共用) = 2 次 image download
      expect(imageDownloadCount, 2);
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
}
