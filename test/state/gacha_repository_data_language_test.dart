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
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_fetcher.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 建立測試用的 [GachaRecord]，預設 5★ 角色。
GachaRecord _rec({
  required String id,
  required String uid,
  required String name,
  required String gachaType,
  required String lang,
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

/// 內含「胡桃」(id='1') 的雙語名冊，供 fake converter 使用。
final _catalogs = <String, LangCatalog>{
  'zh-tw': LangCatalog.fromEntries('zh-tw', {'1': (name: '胡桃', kind: 2)}),
  'en-us': LangCatalog.fromEntries('en-us', {'1': (name: 'Hu Tao', kind: 2)}),
};

/// fake catalog 解析器（繞過網路）。
Future<LangCatalog> _ensureCatalog(
  String lang, {
  bool forceRefresh = false,
}) async => _catalogs[lang]!;

/// 一定會拋例外的 fake converter，用於驗證轉換例外被吞。
class _ThrowingConverter extends GachaLanguageConverter {
  _ThrowingConverter() : super(ensureCatalog: _ensureCatalog);

  @override
  Future<
    ({BannerStorage data, LangConvertResult result, List<IndexHint> hints})
  >
  convert(BannerStorage data, String targetLang) async {
    throw StateError('boom');
  }
}

/// 對所有 HoYoWiki 端點都回 404 的 client（避免增量補圖打網路）。
http.Client _noopHoYoWikiClient() =>
    MockClient((req) async => http.Response('', 404));

/// 啟動測試用 [ProviderContainer]，可注入 fake converter 與預置存檔。
Future<ProviderContainer> _bootstrap({
  required Directory tempDir,
  GachaLanguageConverter? converter,
  http.Client? apiClient,
}) async {
  final storage = GachaStorage(tempDir);
  final hoyowikiDir = Directory('${tempDir.path}/hoyowiki');
  if (!await hoyowikiDir.exists()) await hoyowikiDir.create(recursive: true);
  final indexStorage = HoYoWikiIndexStorage(hoyowikiDir);

  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      hoyowikiIndexStorageProvider.overrideWithValue(indexStorage),
      hoyowikiCacheDirProvider.overrideWithValue(hoyowikiDir),
      hoyowikiFetcherProvider.overrideWithValue(HoYoWikiFetcher()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: apiClient ?? _noopHoYoWikiClient(),
          cancel: () {},
        ),
      ),
      if (converter != null)
        gachaLanguageConverterProvider.overrideWithValue(converter),
    ],
  );
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
  await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  return container;
}

/// 建立通用的 fake converter。
GachaLanguageConverter _fakeConverter() =>
    GachaLanguageConverter(ensureCatalog: _ensureCatalog);

// update 路徑（_runUpdate）的 dataLanguage seeding 因需真實 MITM 捕獲，無法在單元
// 測試穩定觸發；故以 import／unify 路徑作等價驗證（兩者共用 _convertAccountToDataLanguage
// 與 _seedLangFromData，與 update 路徑同一段邏輯）。
//
// unify 結尾的 best-effort HoYoWiki pre-warm 會走既有 _fetchHoYoWiki，沿用 _bootstrap
// 注入的 _noopHoYoWikiClient（所有端點回 404），故不會打真實網路。
void main() {
  test('unifyDataLanguage：把 zh-tw 記錄轉成 en-us，聚合計數正確、結尾清進度', () async {
    final tempDir = await Directory.systemTemp.createTemp('gacha_lang_unify_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _fakeConverter(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);

    // 設定資料語言 en-us，並以 import 預置一筆 zh-tw「胡桃」（import 路徑也會轉，
    // 故先設 dataLanguage 之前用 debugImportOnly 在未設語言時放原始 zh-tw）。
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
                _rec(
                  id: '1',
                  uid: '1001',
                  name: '胡桃',
                  gachaType: '301',
                  lang: 'zh-tw',
                ),
              ],
              '302': [],
              '500': [],
              '200': [],
              '100': [],
            },
          ),
        ),
      ],
    );
    // 尚未設定 dataLanguage → import 不轉，保留 zh-tw。
    await notifier.debugImportOnly(bundle);
    expect(
      container
          .read(gachaRepositoryProvider)
          .byUid['1001']!
          .banners['301']!
          .single
          .name,
      '胡桃',
    );

    await container.read(settingsProvider.notifier).setDataLanguage('en-us');

    final result = await notifier.unifyDataLanguage();

    expect(result.total, 1);
    expect(result.converted, 1);
    expect(result.unresolved, 0);

    final rec = container
        .read(gachaRepositoryProvider)
        .byUid['1001']!
        .banners['301']!
        .single;
    expect(rec.name, 'Hu Tao');
    expect(rec.lang, 'en-us');

    // 結尾清進度
    expect(container.read(gachaRepositoryProvider).progress, isNull);

    // 存檔也被寫入轉換後資料
    final saved = await GachaStorage(tempDir).load('1001');
    expect(saved!.banners['301']!.single.name, 'Hu Tao');

    // index 收到 hint
    final id = container
        .read(hoyowikiIndexProvider)
        .lookupId(name: 'Hu Tao', lang: 'en-us');
    expect(id, '1');
  });

  test('unifyDataLanguage：未設定資料語言時回零結果、不動資料', () async {
    final tempDir = await Directory.systemTemp.createTemp('gacha_lang_noop_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _fakeConverter(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);
    await notifier.debugImportOnly(
      AccountsBundle(
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
                  _rec(
                    id: '1',
                    uid: '1001',
                    name: '胡桃',
                    gachaType: '301',
                    lang: 'zh-tw',
                  ),
                ],
                '302': [],
                '500': [],
                '200': [],
                '100': [],
              },
            ),
          ),
        ],
      ),
    );

    final result = await notifier.unifyDataLanguage();
    expect(result.total, 0);
    expect(result.converted, 0);
    expect(
      container
          .read(gachaRepositoryProvider)
          .byUid['1001']!
          .banners['301']!
          .single
          .name,
      '胡桃',
    );
  });

  test('import 後置轉換：dataLanguage=en-us 時，匯入的 zh-tw「胡桃」被轉成 Hu Tao', () async {
    final tempDir = await Directory.systemTemp.createTemp('gacha_lang_import_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _fakeConverter(),
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setDataLanguage('en-us');

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final result = await notifier.debugImportOnly(
      AccountsBundle(
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
                  _rec(
                    id: '1',
                    uid: '1001',
                    name: '胡桃',
                    gachaType: '301',
                    lang: 'zh-tw',
                  ),
                ],
                '302': [],
                '500': [],
                '200': [],
                '100': [],
              },
            ),
          ),
        ],
      ),
    );

    expect(result.successAccounts, 1);
    // 轉換不改筆數 → added 仍為 1
    expect(result.addedRecords, 1);

    final rec = container
        .read(gachaRepositoryProvider)
        .byUid['1001']!
        .banners['301']!
        .single;
    expect(rec.name, 'Hu Tao');
    expect(rec.lang, 'en-us');
  });

  test('import 後置播種：未設語言時，匯入後 dataLanguage 被播種為記錄語言', () async {
    final tempDir = await Directory.systemTemp.createTemp('gacha_lang_seed_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _fakeConverter(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);
    await notifier.debugImportOnly(
      AccountsBundle(
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
                  _rec(
                    id: '1',
                    uid: '1001',
                    name: '胡桃',
                    gachaType: '301',
                    lang: 'zh-tw',
                  ),
                ],
                '302': [],
                '500': [],
                '200': [],
                '100': [],
              },
            ),
          ),
        ],
      ),
    );

    expect(container.read(dataLanguageProvider), 'zh-tw');
  });

  test(
    'bootstrap 播種：tempDir 預置 zh-tw 存檔 → build 後 dataLanguage 被播種 zh-tw',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'gacha_lang_bootstrap_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});

      // 預置存檔（在 bootstrap 之前直接寫入 storage）
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '1001',
          lastUpdated: DateTime.utc(2026, 5, 25),
          banners: {
            '301': [
              _rec(
                id: '1',
                uid: '1001',
                name: '胡桃',
                gachaType: '301',
                lang: 'zh-tw',
              ),
            ],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );

      final container = await _bootstrap(
        tempDir: tempDir,
        converter: _fakeConverter(),
      );
      addTearDown(container.dispose);

      expect(container.read(dataLanguageProvider), 'zh-tw');
    },
  );

  test('轉換例外被吞：import 仍成功、資料保留原狀、流程不崩', () async {
    final tempDir = await Directory.systemTemp.createTemp('gacha_lang_throw_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _ThrowingConverter(),
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setDataLanguage('en-us');

    final notifier = container.read(gachaRepositoryProvider.notifier);
    final result = await notifier.debugImportOnly(
      AccountsBundle(
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
                  _rec(
                    id: '1',
                    uid: '1001',
                    name: '胡桃',
                    gachaType: '301',
                    lang: 'zh-tw',
                  ),
                ],
                '302': [],
                '500': [],
                '200': [],
                '100': [],
              },
            ),
          ),
        ],
      ),
    );

    // import 仍成功（轉換失敗只吞掉、回原資料）
    expect(result.successAccounts, 1);
    expect(result.addedRecords, 1);

    // 資料保留原狀（未被轉換）
    final rec = container
        .read(gachaRepositoryProvider)
        .byUid['1001']!
        .banners['301']!
        .single;
    expect(rec.name, '胡桃');
    expect(rec.lang, 'zh-tw');

    // 存檔也保留原始資料
    final saved = await GachaStorage(tempDir).load('1001');
    expect(saved!.banners['301']!.single.name, '胡桃');
  });

  test('unifyDataLanguage：converter 拋例外時 skip 該 uid，流程不崩、結尾清進度', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'gacha_lang_unify_throw_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({});

    final container = await _bootstrap(
      tempDir: tempDir,
      converter: _ThrowingConverter(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(gachaRepositoryProvider.notifier);
    await notifier.debugImportOnly(
      AccountsBundle(
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
                  _rec(
                    id: '1',
                    uid: '1001',
                    name: '胡桃',
                    gachaType: '301',
                    lang: 'zh-tw',
                  ),
                ],
                '302': [],
                '500': [],
                '200': [],
                '100': [],
              },
            ),
          ),
        ],
      ),
    );

    await container.read(settingsProvider.notifier).setDataLanguage('en-us');

    final result = await notifier.unifyDataLanguage();
    // 全部 skip → 聚合為零
    expect(result.total, 0);
    expect(result.converted, 0);
    // 資料保留原狀
    expect(
      container
          .read(gachaRepositoryProvider)
          .byUid['1001']!
          .banners['301']!
          .single
          .name,
      '胡桃',
    );
    // 結尾清進度
    expect(container.read(gachaRepositoryProvider).progress, isNull);
  });
}
