import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

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

http.Client _hoYoWikiMockClient({void Function(String keyword)? onSearch}) =>
    MockClient((req) async {
      if (req.url.path.endsWith('/search')) {
        final kw = req.url.queryParameters['keyword']!;
        onSearch?.call(kw);
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

Future<ProviderContainer> _bootstrap({
  required Directory tempDir,
  required http.Client apiClient,
}) async {
  final storage = GachaStorage(tempDir);
  final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
  await hoyowikiDir.create();
  final indexStorage = HoYoWikiIndexStorage(hoyowikiDir);

  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
      hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
      hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(client: apiClient, cancel: () {}),
      ),
    ],
  );
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
  await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  return container;
}

void main() {
  test('主路徑：import + 增量補圖 → emit UpdateCompleted with importSummary', () async {
    final searchCalls = <String>[];
    final apiClient = _hoYoWikiMockClient(onSearch: searchCalls.add);

    final tempDir = await Directory.systemTemp.createTemp('gacha_import_main_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(tempDir: tempDir, apiClient: apiClient);
    addTearDown(container.dispose);

    // 構造 bundle：兩個帳號、各一筆祈願紀錄
    final bundle = AccountsBundle(
      exportedAt: DateTime.utc(2026, 5, 25),
      appVersion: 'x',
      lastActiveUid: '1001',
      accounts: [
        ExportedAccount(
          data: BannerStorage(
            uid: '1001',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [
                _rec(id: '1', uid: '1001', name: 'Hu Tao', gachaType: '301'),
              ],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
        ExportedAccount(
          data: BannerStorage(
            uid: '1002',
            lastUpdated: DateTime.utc(2026, 5, 25),
            banners: {
              '301': [],
              '302': [],
              '500': [],
              '200': [
                _rec(
                  id: '2',
                  uid: '1002',
                  name: 'Skyward Harp',
                  gachaType: '200',
                ),
              ],
              '100': [],
            },
          ),
        ),
      ],
    );

    await container
        .read(gachaRepositoryProvider.notifier)
        .importAccountsAndFetchHoYoWiki(bundle);

    // 跨 UID 去重後 search 兩次
    expect(searchCalls.toSet(), {'Hu Tao', 'Skyward Harp'});

    // byUid 含兩個帳號
    final state = container.read(gachaRepositoryProvider);
    expect(state.byUid.keys.toSet(), {'1001', '1002'});

    // 結束 emit UpdateCompleted；importSummary 與圖片下載數齊全
    final progress = state.progress;
    expect(progress, isA<UpdateCompleted>());
    final completed = progress as UpdateCompleted;
    expect(completed.importSummary, isNotNull);
    expect(completed.importSummary!.successAccounts, 2);
    expect(completed.importSummary!.failedUids, isEmpty);
    expect(completed.importSummary!.totalRecords, 2);
    expect(
      completed.hoYoWikiImagesDownloaded,
      4,
      reason: 'Hu Tao + Skyward Harp，各 icon+header = 4 張',
    );
  });
}
