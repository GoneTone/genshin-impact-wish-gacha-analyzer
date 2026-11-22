import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/ads/ad_placement.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';

/// 建立指定卡池的測試記錄。
GachaRecord _r(String gachaType) => GachaRecord(
  id: '1',
  uid: '801000000',
  gachaType: gachaType,
  name: '刻晴',
  itemType: '角色',
  rankType: 5,
  time: DateTime.utc(2026, 1, 1),
  lang: 'zh-tw',
);

/// 建立作用中帳號的測試狀態，[banners] 為各卡池記錄。
GachaState _state({
  Map<String, List<GachaRecord>> banners = const {},
  bool bootstrapping = false,
  bool hasActive = true,
}) => GachaState(
  activeUid: hasActive ? '801000000' : null,
  byUid: {
    '801000000': BannerStorage(
      uid: '801000000',
      lastUpdated: DateTime.utc(2026, 1, 1),
      banners: banners,
    ),
  },
  isBootstrapping: bootstrapping,
);

void main() {
  final withRecords = _state(
    banners: {
      '301': [_r('301')],
    },
  );
  final empty = _state(banners: {'301': const []});

  test('設定頁、貢獻者頁不放原生廣告', () {
    expect(pageHasAdContent(path: '/settings', gacha: empty), isFalse);
    expect(pageHasAdContent(path: '/contributors', gacha: empty), isFalse);
  });

  test('/ 在 bootstrap 中沒有廣告內容', () {
    expect(
      pageHasAdContent(path: '/', gacha: _state(bootstrapping: true)),
      isFalse,
    );
  });

  test('/ 無作用中帳號時沒有廣告內容', () {
    expect(
      pageHasAdContent(path: '/', gacha: _state(hasActive: false)),
      isFalse,
    );
  });

  test('/ 所有卡池都空時沒有廣告內容', () {
    expect(pageHasAdContent(path: '/', gacha: empty), isFalse);
  });

  test('/ 任一卡池有記錄時有廣告內容', () {
    expect(pageHasAdContent(path: '/', gacha: withRecords), isTrue);
  });

  test('/banner/<有記錄的 key> 有廣告內容', () {
    expect(pageHasAdContent(path: '/banner/301', gacha: withRecords), isTrue);
  });

  test('/banner/1000（頌願）有記錄為 true、無記錄為 false', () {
    final odes = _state(
      banners: {
        '1000': [_r('1000')],
      },
    );
    expect(pageHasAdContent(path: '/banner/1000', gacha: odes), isTrue);
    expect(pageHasAdContent(path: '/banner/1000', gacha: withRecords), isFalse);
  });

  test('/banner/<空的 key> 沒有廣告內容', () {
    expect(pageHasAdContent(path: '/banner/301', gacha: empty), isFalse);
    expect(pageHasAdContent(path: '/banner/999', gacha: withRecords), isFalse);
  });

  test('/banner/<有記錄的 key> 在 bootstrap 中或無作用中帳號時沒有廣告內容', () {
    final banners = {
      '301': [_r('301')],
    };
    final bootstrapping = _state(banners: banners, bootstrapping: true);
    final noActive = _state(banners: banners, hasActive: false);
    expect(
      pageHasAdContent(path: '/banner/301', gacha: bootstrapping),
      isFalse,
    );
    expect(pageHasAdContent(path: '/banner/301', gacha: noActive), isFalse);
  });

  test('格式不符的 banner 路徑沒有廣告內容', () {
    for (final path in ['/banner/', '/bannerx', '/banner/301/extra']) {
      expect(
        pageHasAdContent(path: path, gacha: withRecords),
        isFalse,
        reason: path,
      );
    }
  });

  test('banners 為空時 / 與 /banner/301 沒有廣告內容', () {
    final noBanners = _state();
    expect(pageHasAdContent(path: '/', gacha: noBanners), isFalse);
    expect(pageHasAdContent(path: '/banner/301', gacha: noBanners), isFalse);
  });

  test('未知路徑沒有廣告內容', () {
    expect(pageHasAdContent(path: '/foo', gacha: withRecords), isFalse);
  });

  group('overviewSectionHasAdContent', () {
    final onlyGacha = withRecords;
    final onlyOdes = _state(
      banners: {
        '1000': [_r('1000')],
      },
    );
    final both = _state(
      banners: {
        '301': [_r('301')],
        '1000': [_r('1000')],
      },
    );

    /// 回傳 [gacha] 下（祈願段, 頌願段）是否有廣告內容。
    (bool, bool) sections(GachaState gacha) => (
      overviewSectionHasAdContent(category: GachaCategory.gacha, gacha: gacha),
      overviewSectionHasAdContent(category: GachaCategory.odes, gacha: gacha),
    );

    test('只有 301 有記錄：祈願段 true、頌願段 false', () {
      expect(sections(onlyGacha), (true, false));
    });

    test('只有 1000 有記錄：祈願段 false、頌願段 true', () {
      expect(sections(onlyOdes), (false, true));
    });

    test('只有 2000（常駐頌願）有記錄：祈願段 false、頌願段 true', () {
      final onlyStandardOdes = _state(
        banners: {
          '2000': [_r('2000')],
        },
      );
      expect(sections(onlyStandardOdes), (false, true));
    });

    test('兩者都有記錄時皆為 true', () {
      expect(sections(both), (true, true));
    });

    test('都沒有記錄、啟動載入中、沒有作用中帳號時皆為 false', () {
      expect(sections(empty), (false, false));
      expect(
        sections(
          _state(banners: both.activeData!.banners, bootstrapping: true),
        ),
        (false, false),
      );
      expect(
        sections(_state(banners: both.activeData!.banners, hasActive: false)),
        (false, false),
      );
    });
  });
}
