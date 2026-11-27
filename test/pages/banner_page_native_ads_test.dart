import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/ads/native_ad.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';

import '../helpers/native_ad_fakes.dart';

/// 卡池 [pool] 的 [count] 筆記錄（名稱 `Item 1`..）；[withFive] 時每 10 筆有一筆 5★。
List<GachaRecord> _records(
  int count, {
  bool withFive = true,
  String pool = '301',
}) => [
  for (var i = 1; i <= count; i++)
    GachaRecord(
      id: '${1000 + i}',
      uid: fakeNativeAdUid,
      gachaType: pool,
      name: 'Item $i',
      itemType: '武器',
      rankType: withFive && i % 10 == 0 ? 5 : 3,
      time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
      lang: 'zh-tw',
    ),
];

/// 記錄列表的卡片外框（圓角邊框的 Container）。
final _cardFrames = find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).border != null &&
      (w.decoration! as BoxDecoration).borderRadius ==
          BorderRadius.circular(AppRadius.md),
);

/// 記錄卡片（私有型別，以型別名稱比對）。
final _recordCards = find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_RecordCard',
  skipOffstage: false,
);

/// 時間軸那張卡。
final _timelineCard = find.byWidgetPredicate(
  (w) => w is ChartCard && w.icon == Icons.timeline,
);

/// 以 [icon] 找到的段落標題。
Finder _sectionTitle(IconData icon) =>
    find.byWidgetPredicate((w) => w is InlineSectionTitle && w.icon == icon);

void main() {
  late FakeNativeAdLoader loader;
  late ProviderContainer container;

  /// 建立 container：[banners] 為各卡池記錄，[android]／[canRequestAds] 為廣告條件。
  void setUpContainer({
    required Map<String, List<GachaRecord>> banners,
    bool android = true,
    bool canRequestAds = true,
    bool fail = false,
  }) {
    loader = FakeNativeAdLoader(fail: fail);
    container = ProviderContainer(
      overrides: [
        gachaRepositoryProvider.overrideWith(
          () => FixedGachaRepository(banners),
        ),
        hoyowikiIndexProvider.overrideWith(EmptyHoYoWikiIndex.new),
        hoyowikiCacheDirProvider.overrideWithValue(Directory.systemTemp),
        isAndroidProvider.overrideWithValue(android),
        adsProvider.overrideWith(() => FakeAdsController(canRequestAds)),
        nativeAdLoaderProvider.overrideWithValue(loader.call),
      ],
    );
    addTearDown(container.dispose);
  }

  /// 以 [size] 與 [mode] 呈現卡池 [pool] 的頁面。
  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    String pool = '301',
    ThemeMode mode = ThemeMode.dark,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: BannerPage(gachaType: pool)),
        ),
      ),
    );
    await _settle(tester);
  }

  /// 第 10 與第 11 張記錄卡是否在同一個外框裡（列表沒被切開）。
  void expectListNotSplit(WidgetTester tester) {
    final cards = _recordCards.evaluate().toList();
    expect(cards.length, greaterThan(10));
    Element frameOf(Element card) => find
        .ancestor(of: find.byWidget(card.widget), matching: _cardFrames)
        .evaluate()
        .first;
    expect(frameOf(cards[9]), same(frameOf(cards[10])));
  }

  /// 時間軸卡下緣到「5★ 一覽」標題上緣的距離（內容座標，途中會捲動）。
  Future<double> timelineToFiveStarGap(WidgetTester tester) async {
    final timelineBottom = _bottom(tester, _timelineCard);
    await _scrollTo(tester, _sectionTitle(Icons.star_outline));
    return _top(tester, _sectionTitle(Icons.star_outline)) - timelineBottom;
  }

  testWidgets('手機直向進頁即載入兩個位置，位置 3 在時間軸正上方', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);

    final mid = fakeNativeViewOf(NativeAdPlacement.bannerMid);
    await _scrollTo(tester, mid);
    // 卡片之間一律 m；時間軸下方接區塊標題，維持段落間距 xl。
    expect(_top(tester, _timelineCard) - _bottom(tester, mid), AppSpacing.m);
    expect(await timelineToFiveStarGap(tester), AppSpacing.xl);

    await _scrollTo(tester, fakeNativeViewOf(NativeAdPlacement.bannerList));
    expect(fakeNativeViewOf(NativeAdPlacement.bannerList), findsOneWidget);
    // 列表中的廣告是同一個外框裡的一列，不切開列表。
    expectListNotSplit(tester);
  });

  testWidgets('沒有 5★ 時位置 3 照放，與「記錄列表」標題至少隔 xl', (tester) async {
    setUpContainer(banners: {'301': _records(25, withFive: false)});
    await pumpPage(tester);
    final mid = fakeNativeViewOf(NativeAdPlacement.bannerMid);
    await _scrollTo(tester, mid);
    final midBottom = _bottom(tester, mid);
    final title = _sectionTitle(Icons.table_chart_outlined);
    await _scrollTo(tester, title);
    expect(
      _top(tester, title) - midBottom,
      greaterThanOrEqualTo(AppSpacing.xl),
    );
  });

  testWidgets('手機橫向：卡片模式載入兩個位置，位置 3 寬 400 並置中', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester, size: const Size(800, 360));
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);

    final mid = fakeNativeViewOf(NativeAdPlacement.bannerMid);
    await _scrollTo(tester, mid);
    expect(tester.getSize(mid), const Size(400, kNativeMediumHeight));
    expect(tester.getCenter(mid).dx, 400);

    final list = fakeNativeViewOf(NativeAdPlacement.bannerList);
    await _scrollTo(tester, list);
    expect(list, findsOneWidget);
    expect(_recordCards, findsWidgets);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('進頁時尚未可請求廣告，之後變成可請求：兩個位置各載入一次，之後重建不再載入', (tester) async {
    setUpContainer(banners: {'301': _records(25)}, canRequestAds: false);
    await pumpPage(tester);
    expect(loader.loads, isEmpty);

    (container.read(adsProvider.notifier) as FakeAdsController).canRequestAds =
        true;
    await _settle(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);

    await pumpPage(tester);
    await _scrollTo(tester, fakeNativeViewOf(NativeAdPlacement.bannerList));
    expect(loader.loads.length, 2);
    expect(loader.loads.where((a) => a.disposed), isEmpty);
  });

  testWidgets('只有 8 筆時不載入位置 1，仍載入位置 3', (tester) async {
    setUpContainer(banners: {'301': _records(8)});
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 0);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);
  });

  testWidgets('平板寬（表格模式）不載入位置 1', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester, size: const Size(1000, 800));
    expect(loader.calls(NativeAdPlacement.bannerList), 0);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);
  });

  testWidgets('三欄寬度：時間軸與圓餅同列，位置 3 放在整列下方', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester, size: const Size(1280, 800));
    final mid = fakeNativeViewOf(NativeAdPlacement.bannerMid);
    await _scrollTo(tester, mid);
    expect(_top(tester, mid) - _bottom(tester, _timelineCard), AppSpacing.m);
    final midBottom = _bottom(tester, mid);
    await _scrollTo(tester, _sectionTitle(Icons.star_outline));
    expect(
      _top(tester, _sectionTitle(Icons.star_outline)) - midBottom,
      AppSpacing.xl,
    );
  });

  testWidgets('內容寬度不足 320 時兩個都不載入、不多間距', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    // 手機頁邊距 m：340 − 24 = 316。
    await pumpPage(tester, size: const Size(340, 800));
    expect(loader.loads, isEmpty);
    expect(await timelineToFiveStarGap(tester), AppSpacing.xl);
    await _scrollTo(tester, _recordCards.at(10));
    expectListNotSplit(tester);
  });

  for (final (name, android, canRequestAds) in [
    ('非 Android', false, true),
    ('尚未可請求廣告', true, false),
  ]) {
    testWidgets('$name時兩個都不載入，版面與沒有廣告時相同', (tester) async {
      setUpContainer(
        banners: {'301': _records(25)},
        android: android,
        canRequestAds: canRequestAds,
      );
      await pumpPage(tester);
      expect(loader.loads, isEmpty);
      expect(anyFakeNativeView, findsNothing);
      expect(await timelineToFiveStarGap(tester), AppSpacing.xl);
      await _scrollTo(tester, _recordCards.at(10));
      expectListNotSplit(tester);
    });
  }

  testWidgets('頌願卡池頁（1000）有記錄時兩個位置照放', (tester) async {
    setUpContainer(banners: {'1000': _records(25, pool: '1000')});
    await pumpPage(tester, pool: '1000');
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);
    await _scrollTo(tester, fakeNativeViewOf(NativeAdPlacement.bannerMid));
    await _scrollTo(tester, fakeNativeViewOf(NativeAdPlacement.bannerList));
    expectListNotSplit(tester);
  });

  testWidgets('卡池沒有記錄時兩個都不載入', (tester) async {
    setUpContainer(banners: {'301': const []});
    await pumpPage(tester);
    expect(loader.loads, isEmpty);
    expect(anyFakeNativeView, findsNothing);
  });

  testWidgets('載入失敗時不顯示、不插入間距', (tester) async {
    setUpContainer(banners: {'301': _records(25)}, fail: true);
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);
    expect(anyFakeNativeView, findsNothing);
    expect(await timelineToFiveStarGap(tester), AppSpacing.xl);
    await _scrollTo(tester, _recordCards.at(10));
    expectListNotSplit(tester);
  });

  testWidgets('翻到第 2 頁不再載入', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester);
    await _scrollTo(tester, find.byIcon(Icons.chevron_right));
    await tester.tap(find.byIcon(Icons.chevron_right));
    await _settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(loader.loads.length, 2);
    expect(loader.loads.where((a) => a.disposed), isEmpty);
  });

  /// 舊廣告 [ad] 已釋放，且是在 view 離開畫面後、下一幀的 post-frame 階段才釋放（否則會出現紅色錯誤框）。
  void expectDisposedAfterUnmount(FakeNativeAd ad) {
    expect(ad.disposed, isTrue, reason: '${ad.placement}');
    expect(ad.disposedWhileMounted, isFalse, reason: '${ad.placement}');
    expect(ad.disposedAfterFrame, isTrue, reason: '${ad.placement}');
  }

  for (final placement in [
    NativeAdPlacement.bannerMid,
    NativeAdPlacement.bannerList,
  ]) {
    testWidgets('深色切淺色：兩個位置以 light 各再載入一次，畫面上的 ${placement.name} 離開畫面後才釋放', (
      tester,
    ) async {
      setUpContainer(banners: {'301': _records(25)});
      await pumpPage(tester);
      final old = [...loader.loads];
      expect(old.map((a) => a.brightness), everyElement(Brightness.dark));
      await _scrollTo(tester, fakeNativeViewOf(placement));
      expect(fakeNativeViewOf(placement), findsOneWidget);

      await pumpPage(tester, mode: ThemeMode.light);
      // 舊廣告在 provider 釋放後的下一幀才 dispose。
      await tester.pump();
      final fresh = loader.loads.skip(old.length).toList();
      expect(
        fresh.map((a) => (a.placement, a.brightness)),
        unorderedEquals([
          (NativeAdPlacement.bannerList, Brightness.light),
          (NativeAdPlacement.bannerMid, Brightness.light),
        ]),
      );
      old.forEach(expectDisposedAfterUnmount);
    });

    testWidgets('切到另一個 25 筆卡池：以新 scope 各載入一次，畫面上的 ${placement.name} 離開畫面後才釋放', (
      tester,
    ) async {
      setUpContainer(
        banners: {
          '301': _records(25),
          '302': _records(25, pool: '302'),
        },
      );
      await pumpPage(tester);
      final old = [...loader.loads];
      await _scrollTo(tester, fakeNativeViewOf(placement));
      expect(fakeNativeViewOf(placement), findsOneWidget);

      await pumpPage(tester, pool: '302');
      await tester.pump();
      expect(loader.calls(NativeAdPlacement.bannerList), 2);
      expect(loader.calls(NativeAdPlacement.bannerMid), 2);
      old.forEach(expectDisposedAfterUnmount);
    });
  }

  testWidgets('同一個 State 切到 8 筆卡池：不帶上一池的位置 1 要求', (tester) async {
    setUpContainer(
      banners: {
        '301': _records(25),
        '302': _records(8, pool: '302'),
      },
    );
    await pumpPage(tester);
    final old = [...loader.loads];
    expect(old.length, 2);

    await pumpPage(tester, pool: '302');
    await tester.pump();
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 2);
    old.forEach(expectDisposedAfterUnmount);
  });

  testWidgets('已載入後寬度縮到不足 320：不顯示、不插間距、不釋放；放回寬度後照舊顯示', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    await pumpPage(tester);
    expect(loader.loads.length, 2);

    await pumpPage(tester, size: const Size(340, 800));
    expect(anyFakeNativeView, findsNothing);
    expect(await timelineToFiveStarGap(tester), AppSpacing.xl);
    await _scrollTo(tester, _recordCards.at(10));
    expectListNotSplit(tester);

    await pumpPage(tester);
    await _scrollTo(tester, fakeNativeViewOf(NativeAdPlacement.bannerList));
    expect(fakeNativeViewOf(NativeAdPlacement.bannerList), findsOneWidget);
    expect(loader.loads.length, 2);
    expect(loader.loads.where((a) => a.disposed), isEmpty);
  });

  testWidgets('篩選到 10 筆以下不載入位置 1；清掉後補載一次；再篩回去不釋放、不顯示', (tester) async {
    setUpContainer(banners: {'301': _records(25)});
    final filter = container.read(recordFilterProvider('301').notifier);
    // 「Item 2」只符合 Item 2、20..25，共 7 筆。
    filter.setFilter(const RecordFilter(query: 'Item 2'));
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 0);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);

    filter.clear();
    await _settle(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 1);

    filter.setFilter(const RecordFilter(query: 'Item 2'));
    await _settle(tester);
    expect(loader.calls(NativeAdPlacement.bannerList), 1);
    expect(loader.calls(NativeAdPlacement.bannerMid), 1);
    expect(loader.loads.where((a) => a.disposed), isEmpty);
    expect(fakeNativeViewOf(NativeAdPlacement.bannerList), findsNothing);
  });
}

/// 推進到動畫（換頁、主題切換）結束；頁面有持續動畫，不能用 pumpAndSettle。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 捲到 [finder] 可見。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await _settle(tester);
}

/// 主捲動區目前的捲動位移。
double _pixels(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// [finder] 上緣在捲動內容中的位置（不受捲動影響）。
double _top(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder).dy + _pixels(tester);

/// [finder] 下緣在捲動內容中的位置（不受捲動影響）。
double _bottom(WidgetTester tester, Finder finder) =>
    tester.getBottomLeft(finder).dy + _pixels(tester);
