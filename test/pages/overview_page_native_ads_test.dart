import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/ads/native_ad.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';

import '../helpers/native_ad_fakes.dart';

/// 卡池 [pool] 的 [count] 筆記錄。
List<GachaRecord> _records(int count, {String pool = '301'}) => [
  for (var i = 1; i <= count; i++)
    GachaRecord(
      id: '${1000 + i}',
      uid: fakeNativeAdUid,
      gachaType: pool,
      name: 'Item $i',
      itemType: '武器',
      rankType: i % 10 == 0 ? 5 : 3,
      time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
      lang: 'zh-tw',
    ),
];

/// 祈願與頌願都有記錄的資料。
Map<String, List<GachaRecord>> _both() => {
  '301': _records(25),
  '1000': _records(25, pool: '1000'),
};

/// 只有祈願記錄的資料。
Map<String, List<GachaRecord>> _gachaOnly() => {'301': _records(25)};

/// 只有頌願記錄的資料。
Map<String, List<GachaRecord>> _odesOnly() => {
  '1000': _records(25, pool: '1000'),
};

/// 「類型分布」卡（祈願段在前、頌願段在後）。
final _typeCards = find.byType(ItemTypeChartCard, skipOffstage: false);

/// 「各卡池主稀有度件數」卡（祈願段在前、頌願段在後）。
final _barsCards = find.byWidgetPredicate(
  (w) => w is ChartCard && w.icon == Icons.bar_chart,
  skipOffstage: false,
);

void main() {
  late FakeNativeAdLoader loader;
  late ProviderContainer container;

  /// 建立 container：[banners] 為各卡池記錄，[android]／[canRequestAds] 為廣告條件。
  void setUpContainer({
    Map<String, List<GachaRecord>>? banners,
    bool android = true,
    bool canRequestAds = true,
    bool fail = false,
    bool bootstrapping = false,
  }) {
    loader = FakeNativeAdLoader(fail: fail);
    container = ProviderContainer(
      overrides: [
        gachaRepositoryProvider.overrideWith(
          () => FixedGachaRepository(
            banners ?? _both(),
            bootstrapping: bootstrapping,
          ),
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

  /// 以 [size] 與 [mode] 呈現總覽頁；高度夠大，兩個區段都在建構範圍內。
  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(360, 6000),
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
          home: const Scaffold(body: OverviewPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 第 [section] 段（0 為第一個有內容的段落）「類型分布」卡下緣到「各卡池主稀有度件數」卡上緣的距離。
  double typeToBarsGap(WidgetTester tester, int section) =>
      tester.getTopLeft(_barsCards.at(section)).dy -
      tester.getBottomLeft(_typeCards.at(section)).dy;

  /// 斷言 [placement] 的廣告夾在第 [section] 個有內容段落的兩張卡之間，前後間距都是 m。
  void expectAdInSection(
    WidgetTester tester,
    NativeAdPlacement placement,
    int section,
  ) {
    final block = find.ancestor(
      of: fakeNativeViewOf(placement),
      matching: find.byType(NativeAdBlock),
    );
    expect(block, findsOneWidget);
    expect(
      tester.getTopLeft(block).dy -
          tester.getBottomLeft(_typeCards.at(section)).dy,
      AppSpacing.m,
    );
    expect(
      tester.getTopLeft(_barsCards.at(section)).dy -
          tester.getBottomLeft(block).dy,
      AppSpacing.m,
    );
  }

  testWidgets('兩段都有記錄：兩則各載入一次，各在自己區段的類型分布下方', (tester) async {
    setUpContainer();
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.overviewGacha), 1);
    expect(loader.calls(NativeAdPlacement.overviewOdes), 1);
    expect(anyFakeNativeView, findsNWidgets(2));
    expectAdInSection(tester, NativeAdPlacement.overviewGacha, 0);
    expectAdInSection(tester, NativeAdPlacement.overviewOdes, 1);
  });

  testWidgets('只有祈願：只載入 overviewGacha，頌願空狀態沒有廣告', (tester) async {
    setUpContainer(banners: _gachaOnly());
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.overviewGacha), 1);
    expect(loader.calls(NativeAdPlacement.overviewOdes), 0);
    expect(anyFakeNativeView, findsOneWidget);
    expectAdInSection(tester, NativeAdPlacement.overviewGacha, 0);
  });

  testWidgets('只有頌願：只載入 overviewOdes', (tester) async {
    setUpContainer(banners: _odesOnly());
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.overviewGacha), 0);
    expect(loader.calls(NativeAdPlacement.overviewOdes), 1);
    expect(anyFakeNativeView, findsOneWidget);
    expectAdInSection(tester, NativeAdPlacement.overviewOdes, 0);
  });

  testWidgets('兩段都沒有記錄：不載入', (tester) async {
    setUpContainer(banners: {'301': const [], '1000': const []});
    await pumpPage(tester);
    expect(loader.loads, isEmpty);
    expect(anyFakeNativeView, findsNothing);
  });

  for (final (name, android, canRequestAds, bootstrapping) in [
    ('非 Android', false, true, false),
    ('尚未可請求廣告', true, false, false),
    ('啟動載入中', true, true, true),
  ]) {
    testWidgets('$name時不載入，版面與沒有廣告時相同', (tester) async {
      setUpContainer(
        android: android,
        canRequestAds: canRequestAds,
        bootstrapping: bootstrapping,
      );
      await pumpPage(tester);
      expect(loader.loads, isEmpty);
      expect(anyFakeNativeView, findsNothing);
      if (!bootstrapping) {
        expect(typeToBarsGap(tester, 0), AppSpacing.m);
        expect(typeToBarsGap(tester, 1), AppSpacing.m);
      }
    });
  }

  testWidgets('進頁時尚未可請求廣告，之後變成可請求：兩則各載入一次，之後重建不再載入', (tester) async {
    setUpContainer(canRequestAds: false);
    await pumpPage(tester);
    expect(loader.loads, isEmpty);

    (container.read(adsProvider.notifier) as FakeAdsController).canRequestAds =
        true;
    await tester.pump();
    await tester.pump();
    expect(loader.calls(NativeAdPlacement.overviewGacha), 1);
    expect(loader.calls(NativeAdPlacement.overviewOdes), 1);
    expect(anyFakeNativeView, findsNWidgets(2));

    await pumpPage(tester);
    expect(loader.loads, hasLength(2));
    expect(loader.loads.every((a) => !a.disposed), isTrue);
  });

  testWidgets('手機橫向：廣告寬 400 並置中', (tester) async {
    setUpContainer(banners: _gachaOnly());
    await pumpPage(tester, size: const Size(800, 360));
    expect(loader.calls(NativeAdPlacement.overviewGacha), 1);
    await tester.scrollUntilVisible(
      anyFakeNativeView,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(
      tester.getSize(anyFakeNativeView),
      const Size(400, kNativeMediumHeight),
    );
    expect(tester.getCenter(anyFakeNativeView).dx, 400);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('內容寬度不足 320 時不載入、不多間距', (tester) async {
    setUpContainer();
    // 手機頁邊距 m：340 − 24 = 316。
    await pumpPage(tester, size: const Size(340, 6000));
    expect(loader.loads, isEmpty);
    expect(typeToBarsGap(tester, 0), AppSpacing.m);
    expect(typeToBarsGap(tester, 1), AppSpacing.m);
  });

  testWidgets('載入失敗時不顯示、不多間距', (tester) async {
    setUpContainer(fail: true);
    await pumpPage(tester);
    expect(loader.calls(NativeAdPlacement.overviewGacha), 1);
    expect(loader.calls(NativeAdPlacement.overviewOdes), 1);
    expect(anyFakeNativeView, findsNothing);
    expect(typeToBarsGap(tester, 0), AppSpacing.m);
    expect(typeToBarsGap(tester, 1), AppSpacing.m);
  });

  testWidgets('切到沒有頌願記錄的帳號：頌願廣告移除並釋放，祈願廣告不重載', (tester) async {
    setUpContainer();
    await pumpPage(tester);
    final gacha = loader.loads.firstWhere(
      (a) => a.placement == NativeAdPlacement.overviewGacha,
    );
    final odes = loader.loads.firstWhere(
      (a) => a.placement == NativeAdPlacement.overviewOdes,
    );

    (container.read(gachaRepositoryProvider.notifier) as FixedGachaRepository)
        .setBanners(_gachaOnly());
    await tester.pump();
    await tester.pump();

    expect(fakeNativeViewOf(NativeAdPlacement.overviewOdes), findsNothing);
    expect(odes.disposed, isTrue);
    expect(odes.disposedWhileMounted, isFalse);
    expect(find.byKey(gacha.key), findsOneWidget);
    expect(gacha.disposed, isFalse);
    expect(loader.loads, hasLength(2));
  });

  testWidgets('深色切淺色：兩則都以 light 各再載入一次，舊的離開畫面後才釋放', (tester) async {
    setUpContainer();
    await pumpPage(tester);
    final olds = List.of(loader.loads);
    expect(olds.map((a) => a.brightness), everyElement(Brightness.dark));

    await pumpPage(tester, mode: ThemeMode.light);
    await tester.pump();
    for (final placement in [
      NativeAdPlacement.overviewGacha,
      NativeAdPlacement.overviewOdes,
    ]) {
      expect(loader.calls(placement), 2);
    }
    expect(
      loader.loads.skip(2).map((a) => a.brightness),
      everyElement(Brightness.light),
    );
    for (final old in olds) {
      expect(old.disposed, isTrue);
      expect(old.disposedWhileMounted, isFalse);
      expect(old.disposedAfterFrame, isTrue);
    }
  });
}
