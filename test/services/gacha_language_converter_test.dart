import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_language_converter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/lang_catalog_storage.dart';

GachaRecord rec(String id, String type, String name, String lang) =>
    GachaRecord(
      id: id,
      uid: '1',
      gachaType: type,
      name: name,
      itemType: '角色',
      rankType: 5,
      time: DateTime(2024),
      lang: lang,
    );

BannerStorage storage(Map<String, List<GachaRecord>> banners) =>
    BannerStorage(uid: '1', lastUpdated: DateTime.utc(2024), banners: banners);

void main() {
  final cats = <String, LangCatalog>{
    'zh-tw': LangCatalog.fromEntries('zh-tw', {
      '5125428': (name: '胡桃', kind: 2),
    }),
    'en-us': LangCatalog.fromEntries('en-us', {
      '5125428': (name: 'Hu Tao', kind: 2),
    }),
  };
  Future<LangCatalog> ensure(String lang, {bool forceRefresh = false}) async {
    final c = cats[lang];
    if (c == null) throw StateError('no catalog for $lang');
    return c;
  }

  test('converts name+lang via id round-trip and emits hint', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({
        '301': [rec('1', '301', '胡桃', 'zh-tw')],
      }),
      'en-us',
    );
    final r = out.data.banners['301']!.single;
    expect(r.name, 'Hu Tao');
    expect(r.lang, 'en-us');
    expect(out.result.converted, 1);
    expect(out.result.unresolved, 0);
    expect(out.hints.single.id, '5125428');
    expect(out.hints.single.menuId, 2);
    expect(out.hints.single.name, 'Hu Tao');
  });

  test('same-lang records are skipped and uncounted', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({
        '301': [rec('1', '301', 'Hu Tao', 'en-us')],
      }),
      'en-us',
    );
    expect(out.result.total, 0);
    expect(out.result.converted, 0);
    expect(out.data.banners['301']!.single.name, 'Hu Tao');
  });

  test('odes records are never touched', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({
        '2000': [rec('1', '2000', '某裝扮', 'zh-tw')],
      }),
      'en-us',
    );
    expect(out.result.total, 0);
    expect(out.data.banners['2000']!.single.name, '某裝扮');
    expect(out.data.banners['2000']!.single.lang, 'zh-tw');
  });

  test('unresolved name is kept as-is and counted', () async {
    final conv = GachaLanguageConverter(ensureCatalog: ensure);
    final out = await conv.convert(
      storage({
        '301': [rec('1', '301', '不存在的物品', 'zh-tw')],
      }),
      'en-us',
    );
    expect(out.result.total, 1);
    expect(out.result.converted, 0);
    expect(out.result.unresolved, 1);
    expect(out.data.banners['301']!.single.name, '不存在的物品');
  });

  test(
    'stale cached catalog triggers one forced refresh then converts',
    () async {
      var refreshed = false;
      final staleEn = LangCatalog.fromEntries('en-us', {
        '5125428': (name: 'Hu Tao', kind: 2),
      });
      final freshEn = LangCatalog.fromEntries('en-us', {
        '5125428': (name: 'Hu Tao', kind: 2),
        '999': (name: 'NewChar', kind: 2),
      });
      final zh = LangCatalog.fromEntries('zh-tw', {
        '5125428': (name: '胡桃', kind: 2),
        '999': (name: '新角色', kind: 2),
      });
      Future<LangCatalog> ensureStale(
        String lang, {
        bool forceRefresh = false,
      }) async {
        if (lang == 'zh-tw') return zh;
        if (lang == 'en-us') {
          if (forceRefresh) {
            refreshed = true;
            return freshEn;
          }
          return refreshed ? freshEn : staleEn;
        }
        throw StateError('no catalog $lang');
      }

      final conv = GachaLanguageConverter(ensureCatalog: ensureStale);
      final out = await conv.convert(
        storage({
          '301': [rec('1', '301', '新角色', 'zh-tw')],
        }),
        'en-us',
      );
      expect(refreshed, isTrue);
      expect(out.data.banners['301']!.single.name, 'NewChar');
      expect(out.result.converted, 1);
    },
  );

  test(
    'ambiguous name (multi-id in src catalog) drops from idByName -> unresolved',
    () async {
      final ambiguous = <String, LangCatalog>{
        'zh-tw': LangCatalog.fromEntries('zh-tw', {
          '1': (name: '同名', kind: 2),
          '2': (name: '同名', kind: 4),
        }),
        'en-us': LangCatalog.fromEntries('en-us', {'1': (name: 'X', kind: 2)}),
      };
      Future<LangCatalog> ens(String lang, {bool forceRefresh = false}) async =>
          ambiguous[lang]!;
      final conv = GachaLanguageConverter(ensureCatalog: ens);
      final out = await conv.convert(
        storage({
          '301': [rec('1', '301', '同名', 'zh-tw')],
        }),
        'en-us',
      );
      expect(out.result.unresolved, 1);
      expect(out.result.converted, 0);
      expect(out.data.banners['301']!.single.name, '同名');
    },
  );

  test(
    'unsupported src lang (short code) does NOT trigger forced refresh',
    () async {
      var forceRefreshCalls = 0;
      final cats2 = <String, LangCatalog>{
        'en-us': LangCatalog.fromEntries('en-us', {
          '1': (name: 'Hu Tao', kind: 2),
        }),
        'en': LangCatalog.fromEntries('en', const {}),
      };
      Future<LangCatalog> ens(String lang, {bool forceRefresh = false}) async {
        if (forceRefresh) forceRefreshCalls++;
        return cats2[lang]!;
      }

      final conv = GachaLanguageConverter(ensureCatalog: ens);
      final out = await conv.convert(
        storage({
          '301': [rec('1', '301', 'whatever', 'en')],
        }),
        'en-us',
      );
      expect(forceRefreshCalls, 0);
      expect(out.result.unresolved, 1);
    },
  );
}
