import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// 不會被觸發的 fake capture。
class _FakeCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 建立模擬 HoYoWiki API 的 [MockClient]（search／entry_page／圖檔皆成功）。
http.Client _hoYoWikiMockClient() => MockClient((req) async {
  if (req.url.path.endsWith('/search')) {
    final kw = req.url.queryParameters['keyword']!;
    return http.Response(
      jsonEncode({
        'retcode': 0,
        'data': {
          'list': [
            {
              'name': kw,
              'entry_page_id': 'eid_$kw',
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
      headers: const {'content-type': 'application/json'},
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
      headers: const {'content-type': 'application/json'},
    );
  }
  return http.Response.bytes([1, 2, 3], 200);
});

/// 單帳號 bundle（1 筆五星祈願記錄，gacha_type=301）。
AccountsBundle _bundle(String uid) => AccountsBundle.fromJson(
  jsonDecode(
        jsonEncode({
          'schema_version': AccountsBundle.currentSchemaVersion,
          'app': accountsBundleAppId,
          'exported_at': '2026-07-06T00:00:00.000Z',
          'app_version': '1.6.0',
          'last_active_uid': uid,
          'accounts': [
            {
              'uid': uid,
              'last_updated': '2026-07-01T00:00:00.000Z',
              'banners': {
                '301': [
                  {
                    'id': '1900000000000000001',
                    'uid': uid,
                    'gacha_type': '301',
                    'name': '測試角色',
                    'item_type': '角色',
                    'rank_type': 5,
                    'time': '2026-06-30 12:00:00',
                    'lang': 'zh-tw',
                  },
                ],
              },
            },
          ],
        }),
      )
      as Map<String, dynamic>,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cloud_import_test_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 建立完成 bootstrap 的 container（含 HoYoWiki 依賴覆寫）。
  Future<ProviderContainer> makeContainer() async {
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    await hoyowikiDir.create();
    final container = ProviderContainer(
      overrides: [
        gachaStorageProvider.overrideWithValue(GachaStorage(tempDir)),
        gachaCaptureProvider.overrideWithValue(_FakeCapture()),
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(hoyowikiDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
        hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
        cancellableHttpClientFactoryProvider.overrideWithValue(
          () => CancellableHttpClient(
            client: _hoYoWikiMockClient(),
            cancel: () {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
    return container;
  }

  test('importBundleForCloudSync 合併進本機且不啟動 progress', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);

    final result = await repo.importBundleForCloudSync(_bundle('800000001'));

    expect(result.successAccounts, 1);
    expect(result.addedRecords, 1);
    final state = container.read(gachaRepositoryProvider);
    expect(state.byUid.keys, contains('800000001'));
    expect(state.progress, isNull);
  });

  test('重複匯入同 bundle → 全數 duplicate', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);

    await repo.importBundleForCloudSync(_bundle('800000001'));
    final second = await repo.importBundleForCloudSync(_bundle('800000001'));

    expect(second.addedRecords, 0);
    expect(second.duplicateRecords, 1);
  });

  test(
    'progress 進行中 → importBundleForCloudSync 拋 CloudSyncBusyException',
    () async {
      final container = await makeContainer();
      final repo = container.read(gachaRepositoryProvider.notifier);
      repo.debugSetProgress(const Preparing());

      expect(
        () => repo.importBundleForCloudSync(_bundle('800000001')),
        throwsA(isA<CloudSyncBusyException>()),
      );
    },
  );

  test(
    'fetchItemImagesForCloudSync → 補抓並 emit UpdateCompleted 不帶 importSummary',
    () async {
      final container = await makeContainer();
      final repo = container.read(gachaRepositoryProvider.notifier);
      await repo.importBundleForCloudSync(_bundle('800000001'));

      await repo.fetchItemImagesForCloudSync();

      final progress = container.read(gachaRepositoryProvider).progress;
      expect(progress, isA<UpdateCompleted>());
      final completed = progress as UpdateCompleted;
      expect(completed.importSummary, isNull);
      expect(completed.totalNewRecords, 0);
      expect(completed.hoYoWikiImagesDownloaded, greaterThan(0));

      // 再跑一次：圖示與詳情都已齊全、沒有工作可做 → 全程靜默，
      // 不彈進度框也不留「更新完成」訊息。
      repo.clearProgress();
      await repo.fetchItemImagesForCloudSync();
      expect(container.read(gachaRepositoryProvider).progress, isNull);
    },
  );

  test('快取目錄執行中被清掉 → 補抓重新下載圖檔時把 index 檔一併重建', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);
    await repo.importBundleForCloudSync(_bundle('800000001'));
    await repo.fetchItemImagesForCloudSync();
    repo.clearProgress();

    // 模擬快取目錄（含 index 檔）在 App 執行中被外部清掉。
    final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
    final indexFile = File('${hoyowikiDir.path}/hoyowiki_index.json');
    expect(await indexFile.exists(), isTrue);
    for (final f in hoyowikiDir.listSync()) {
      if (f is File) f.deleteSync();
    }
    expect(await indexFile.exists(), isFalse);

    // 記憶體索引仍完好：這輪不會有任何 search／entry 寫入，只會因圖檔
    // 缺失重新下載——index 檔必須被主動重建，否則重啟後全部圖示失效。
    await repo.fetchItemImagesForCloudSync();

    expect(await indexFile.exists(), isTrue, reason: '重新下載圖檔的那一輪必須把記憶體索引重新落盤');
    final reloaded = await HoYoWikiIndexStorage(hoyowikiDir).load();
    expect(reloaded.searchMap, isNotEmpty);
    expect(reloaded.entries, isNotEmpty);
  });
  test('fetchItemImagesForCloudSync：progress 進行中 → 直接略過', () async {
    final container = await makeContainer();
    final repo = container.read(gachaRepositoryProvider.notifier);
    repo.debugSetProgress(const Preparing());

    await repo.fetchItemImagesForCloudSync();

    expect(container.read(gachaRepositoryProvider).progress, isA<Preparing>());
  });
}
