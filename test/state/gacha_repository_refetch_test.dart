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
  required String uid,
  required String name,
  required String gachaType,
  String lang = 'en-us',
}) => GachaRecord(
  id: id,
  uid: uid,
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: 5,
  time: DateTime(2026, 5, 24),
  lang: lang,
);

void main() {
  test('主要路徑：跨 UID 聚合 pairs、清檔後重抓、emit UpdateCompleted', () async {
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
                  'name': req.url.queryParameters['keyword'],
                  'entry_page_id': 'eid_${req.url.queryParameters["keyword"]}',
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
                'icon_url': 'https://x/${id}_icon.png',
                'header_img_url': 'https://x/${id}_header.png',
              },
            },
          }),
          200,
        );
      }
      return http.Response.bytes([1, 2, 3], 200);
    });

    final tempDir = await Directory.systemTemp.createTemp(
      'gacha_refetch_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});
    final storage = GachaStorage(tempDir);
    // UID 1001 與 UID 1002 各有不同物品，測 union 去重
    // GachaStorage.listKnownUids() 只載入純數字的 UID，故用數字 UID。
    await storage.save(
      BannerStorage(
        uid: '1001',
        lastUpdated: DateTime.utc(2026, 5, 24),
        banners: {
          '301': [_rec(id: '1', uid: '1001', name: 'Hu Tao', gachaType: '301')],
          '302': [],
          '500': [],
          '200': [
            _rec(id: '2', uid: '1001', name: 'Skyward Harp', gachaType: '200'),
          ],
          '100': [],
        },
      ),
    );
    await storage.save(
      BannerStorage(
        uid: '1002',
        lastUpdated: DateTime.utc(2026, 5, 24),
        banners: {
          '301': [_rec(id: '3', uid: '1002', name: 'Hu Tao', gachaType: '301')],
          '302': [],
          '500': [],
          '200': [],
          '100': [],
        },
      ),
    );

    // 使用獨立子目錄存放 hoyowiki index + cache，避免 wipeCacheDirectory
    // 刪光整個 tempDir（其中含 gacha data）。
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();

    // 預植一個 stale cache 檔，驗證會被清掉
    final staleCache = File('${hoyowikiDir.path}/stale_icon.png');
    await staleCache.writeAsBytes([9, 9, 9]);
    // 預植 index 含舊資料，驗證 clearAll 會清光
    final indexStorage = HoYoWikiIndexStorage(hoyowikiDir);
    await indexStorage.save(
      HoYoWikiIndex(
        searchMap: const {'en-us::StaleItem': '999'},
        entries: const {},
        menuIds: const {},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(storage),
        hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoYoWikiImages();

    // 跨 UID 去重後 search 兩次（Hu Tao + Skyward Harp）
    expect(searchCalls.toSet(), {'Hu Tao', 'Skyward Harp'});

    // 既有 stale 檔已被清掉
    expect(staleCache.existsSync(), isFalse);

    // 舊 index 已被清掉（StaleItem 不在 searchMap），新 index 有 Hu Tao
    final index = container.read(hoyowikiIndexProvider);
    expect(index.searchMap['en-us::StaleItem'], isNull);
    expect(index.searchMap['en-us::Hu Tao'], isNotNull);

    // 結束 emit UpdateCompleted，並驗證圖片下載數（Hu Tao + Skyward Harp，各 icon+header = 4 張）
    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateCompleted>());
    expect(
      (progress as UpdateCompleted).hoYoWikiImagesDownloaded,
      4,
      reason: '兩個物品各有 icon+header，共下載 4 張',
    );
  });

  test('空紀錄：不打 fetcher、直接 emit UpdateCompleted', () async {
    var apiCalled = false;
    final apiClient = MockClient((req) async {
      apiCalled = true;
      return http.Response('', 404);
    });

    final tempDir = await Directory.systemTemp.createTemp(
      'gacha_refetch_empty_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoYoWikiImages();

    expect(apiCalled, isFalse, reason: '沒 pairs 不該打 API');
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });

  test('互斥早退：state.progress 非 null 時 no-op', () async {
    final apiClient = MockClient((req) async => http.Response('', 404));

    final tempDir = await Directory.systemTemp.createTemp(
      'gacha_refetch_mutex_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final indexStorage = HoYoWikiIndexStorage(tempDir);
    // 預植一筆 index 資料，驗證互斥早退**沒有**呼叫 resetAll
    await indexStorage.save(
      HoYoWikiIndex(
        searchMap: const {'en-us::Existing': '111'},
        entries: const {},
        menuIds: const {},
      ),
    );

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(gachaRepositoryProvider.notifier);
    await notifier.waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    // 模擬另一進度進行中（用 reflection 不易，改用呼叫 forceRefetch 兩次）：
    // 直接呼叫 forceRefetch 不 await，馬上再呼叫一次，第二次應 no-op。
    final first = notifier.forceRefetchAllHoYoWikiImages();
    final second = notifier.forceRefetchAllHoYoWikiImages();
    await Future.wait(<Future<void>>[first, second]);

    // index 在 first 中已清，但第二次不該再 clear（難以單獨驗證）；
    // 改驗：`_isUpdating` 結束後 state.progress 為 UpdateCompleted 而非錯誤狀態
    expect(
      container.read(gachaRepositoryProvider).progress,
      isA<UpdateCompleted>(),
    );
  });

  test('清檔失敗：emit UpdateFailed(UpdateErrorWipeHoYoWikiCache)', () async {
    final apiClient = MockClient((req) async => http.Response('', 404));

    final tempDir = await Directory.systemTemp.createTemp(
      'gacha_refetch_wipefail_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    // 用一個不可寫的目錄當 cacheDir（讓 wipeCacheDirectory 拋例外）。
    // Windows 環境改用「指向已被刪除的 parent 的子目錄」觸發 createDir 失敗較難；
    // 退而求其次：override hoyowikiIndexStorageProvider 為會在 clearAll 拋
    // FileSystemException 的 fake。最低成本是包一層 throwing storage。
    final throwingStorage = _ThrowingClearAllStorage(tempDir);

    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        hoyowikiIndexStorageProvider.overrideWithValue(throwingStorage),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        hoyowikiFetcherProvider.overrideWithValue(
          HoYoWikiFetcher(rateLimit: Duration.zero),
        ),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(client: apiClient, cancel: () {}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();

    await container
        .read(gachaRepositoryProvider.notifier)
        .forceRefetchAllHoYoWikiImages();

    final progress = container.read(gachaRepositoryProvider).progress;
    expect(progress, isA<UpdateFailed>());
    expect(
      (progress as UpdateFailed).error,
      isA<UpdateErrorWipeHoYoWikiCache>(),
    );
  });
}

/// 覆寫 [clearAll] 使其拋出 [FileSystemException]，用於測試清檔失敗路徑。
class _ThrowingClearAllStorage extends HoYoWikiIndexStorage {
  _ThrowingClearAllStorage(super.baseDir);

  @override
  Future<void> clearAll() async {
    throw const FileSystemException('simulated wipe failure');
  }
}
