import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/contributors_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/log_access_setup_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android/log_access_resolver.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/adb_pairing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/banner_top_rarity_bars.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/chart_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_horizontal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/pager.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/search_filter_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/manual_url_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/inline_section_title.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/last_updated_label.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';

import '../helpers/no_game_dir.dart';

/// 空 [GachaCapture] 替身。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 固定在 [phase] 的配對流程替身（讀取設定頁用）。
class _Ctl extends AdbPairingController {
  /// 建立替身。
  _Ctl(this.phase);

  /// 固定的階段。
  final PairingPhase phase;

  @override
  AdbPairingState build() => AdbPairingState(phase);
  @override
  Future<void> refresh() async {}
}

/// 角色活動祈願的測試紀錄：5★、4★、3★ 交錯，名稱刻意偏長。
List<GachaRecord> _records() => [
  for (var i = 0; i < 30; i++)
    GachaRecord(
      id: '${1000 + i}',
      uid: '701000000',
      gachaType: '301',
      rankType: i % 10 == 0 ? 5 : (i % 3 == 0 ? 4 : 3),
      itemType: i % 2 == 0 ? '角色' : '武器',
      name: i % 10 == 0 ? 'Character With A Long Name $i' : 'Item $i',
      time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
      lang: 'zh-tw',
    ),
];

/// 活動頌願的測試紀錄：5★、4★、3★ 交錯，名稱刻意偏長。
List<GachaRecord> _odesRecords() => [
  for (var i = 0; i < 30; i++)
    GachaRecord(
      id: '${2000 + i}',
      uid: '701000000',
      gachaType: '2000',
      rankType: i % 10 == 0 ? 5 : (i % 3 == 0 ? 4 : 3),
      itemType: '裝扮套裝',
      name: i % 10 == 0 ? 'Outfit Set With A Long Name $i' : 'Outfit $i',
      time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
      lang: 'zh-tw',
    ),
];

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('phone_pages_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 在 [size] 的畫面上呈現 [page]（已有一個帳號的紀錄，角色活動祈願預設為 [_records]；給 [banners] 時改用它），回傳 container。
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size,
    Widget page, {
    double keyboard = 0,
    PairingPhase phase = PairingPhase.disclosure,
    LogAccessMethod? method,
    List<GachaRecord>? records,
    bool synced = true,
    Map<String, List<GachaRecord>>? banners,
    Locale locale = const Locale('zh'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    late ProviderContainer container;
    await tester.runAsync(() async {
      final storage = GachaStorage(tempDir);
      if (synced) {
        await storage.save(
          BannerStorage(
            uid: '701000000',
            lastUpdated: DateTime.utc(2026, 5, 1),
            banners:
                banners ??
                {'301': records ?? _records(), '2000': _odesRecords()},
          ),
        );
      }
      container = ProviderContainer(
        overrides: [
          noGameDirOverride,
          isAndroidProvider.overrideWithValue(true),
          wirelessPairingStatusProvider.overrideWith(
            (ref) async => (paired: true, canToggle: false),
          ),
          adbPairingProvider.overrideWith(() => _Ctl(phase)),
          gachaStorageProvider.overrideWithValue(storage),
          gachaCaptureProvider.overrideWithValue(_NullCapture()),
          cancellableHttpClientFactoryProvider.overrideWithValue(
            () => CancellableHttpClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              cancel: () {},
            ),
          ),
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
          appVersionProvider.overrideWithValue('0.0.0-test'),
        ],
      );
      await container.read(settingsProvider.notifier).waitForLoad();
      await container
          .read(settingsProvider.notifier)
          .setLogAccessMethod(method);
      await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  /// 沒有例外；有的話把完整錯誤（含溢出元件的位置）放進失敗訊息。
  void expectNoException(WidgetTester tester) {
    final e = tester.takeException();
    expect(e, isNull, reason: e is FlutterError ? e.toStringDeep() : '$e');
  }

  /// 一路捲到底，途中任何 overflow 都算失敗。
  Future<void> scrollToEnd(WidgetTester tester) async {
    expectNoException(tester);
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    final main = scrollables.first;
    for (var i = 0; i < 40; i++) {
      final position = tester.state<ScrollableState>(main).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(main, const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expectNoException(tester);
    }
  }

  for (final (name, size) in [
    ('portrait', const Size(360, 800)),
    ('landscape', const Size(800, 360)),
  ]) {
    testWidgets('overview page fits a phone ($name)', (tester) async {
      await pump(tester, size, const OverviewPage());
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('banner page fits a phone ($name)', (tester) async {
      await pump(tester, size, const BannerPage(gachaType: '301'));
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('odes banner page fits a phone ($name)', (tester) async {
      await pump(tester, size, const BannerPage(gachaType: '2000'));
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('settings page fits a phone ($name)', (tester) async {
      await pump(tester, size, const SettingsPage());
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets(
      'settings page with the log access section fits a phone ($name)',
      (tester) async {
        await pump(
          tester,
          size,
          const SettingsPage(),
          method: LogAccessMethod.wirelessDebugging,
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        )!;
        expect(
          find.text(l.settingsPairedManual, skipOffstage: false),
          findsOneWidget,
        );
        await scrollToEnd(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('contributors page fits a phone ($name)', (tester) async {
      await pump(tester, size, const ContributorsPage());
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    for (final (pageName, page) in [
      ('settings', const SettingsPage() as Widget),
      ('contributors', const ContributorsPage()),
    ]) {
      testWidgets('$pageName section cards are one card gap apart ($name)', (
        tester,
      ) async {
        await pump(tester, size, page);
        final cards = find.byType(SectionCard);
        expect(
          tester.getTopLeft(cards.at(1)).dy -
              tester.getBottomLeft(cards.at(0)).dy,
          AppSpacing.m,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }

    for (final phase in [
      PairingPhase.disclosure,
      PairingPhase.ready,
      PairingPhase.grantFailed,
    ]) {
      testWidgets('log access setup page fits a phone ($name, ${phase.name})', (
        tester,
      ) async {
        await pump(tester, size, const LogAccessSetupPage(), phase: phase);
        await scrollToEnd(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }
  }

  for (final (name, page) in [
    ('overview', const OverviewPage()),
    ('banner', const BannerPage(gachaType: '301')),
    ('odes banner', const BannerPage(gachaType: '2000')),
  ]) {
    testWidgets('$name header shows last updated in phone landscape', (
      tester,
    ) async {
      await pump(tester, const Size(800, 360), page);
      expect(find.byType(LastUpdatedLabel), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('$name landscape header: label after title, share at edge', (
      tester,
    ) async {
      await pump(tester, const Size(800, 360), page);
      final title = tester.getRect(
        find
            .descendant(
              of: find.byType(PageHeader),
              matching: find.byType(Text),
            )
            .first,
      );
      final label = tester.getRect(find.byType(LastUpdatedLabel));
      expect(label.left - title.right, inInclusiveRange(0, 16));
      expect(label.center.dy, inInclusiveRange(title.top, title.bottom));
      // 頁面左右內距 12：分享按鈕和直向一樣貼齊右緣。
      expect(tester.getRect(find.byType(ShareActionButton)).right, 800 - 12);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('$name header has no last updated in phone portrait', (
      tester,
    ) async {
      await pump(tester, const Size(360, 800), page);
      expect(find.byType(LastUpdatedLabel), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('$name unsynced landscape shows not-synced text and empty', (
      tester,
    ) async {
      await pump(tester, const Size(800, 360), page, synced: false);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byIcon(Icons.refresh),
        ),
        findsOneWidget,
      );
      expectNoException(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('banner page with keyboard open does not overflow', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
      keyboard: 300,
    );
    await scrollToEnd(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'manual url dialog with keyboard in landscape does not overflow',
    (tester) async {
      await pump(
        tester,
        const Size(800, 360),
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showManualUrlDialog(context),
            child: const Text('open'),
          ),
        ),
        keyboard: 180,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expectNoException(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final (name, size) in [
    ('phone portrait', const Size(360, 800)),
    ('phone landscape', const Size(800, 256)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('empty pool message is centered below the header ($name)', (
      tester,
    ) async {
      // 原本放在固定 320 高的框裡，只在那一段置中，橫向（殼內約 256 高）還會溢出。
      await pump(tester, size, const BannerPage(gachaType: '302'));
      expectNoException(tester);
      final header = tester.getRect(find.byType(PageHeader));
      final content = tester.getRect(
        find
            .descendant(
              of: find.byType(EmptyState),
              matching: find.byType(Column),
            )
            .first,
      );
      final padding = size.shortestSide < 600 ? AppSpacing.m : AppSpacing.l;
      expect(content.center.dx, closeTo(size.width / 2, 1));
      expect(
        content.center.dy,
        closeTo((header.bottom + size.height - padding) / 2, 1),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('banner page padding is 12 on phones', (tester) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
    );
    expect(tester.getTopLeft(find.byType(PityCard).first).dx, 12);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  // 頁面邊緣留白全 App 一致：手機排版 12、其他 16（與卡池頁、綜合頁相同）。
  for (final (pageName, page) in [
    ('settings', const SettingsPage() as Widget),
    ('contributors', const ContributorsPage()),
  ]) {
    for (final (form, size, platform, padding) in const [
      ('portrait phone', Size(360, 800), TargetPlatform.android, 12.0),
      ('landscape phone', Size(800, 360), TargetPlatform.android, 12.0),
      ('desktop', Size(700, 800), TargetPlatform.windows, 16.0),
    ]) {
      testWidgets('$pageName page padding is $padding ($form)', (tester) async {
        await pump(tester, size, page);
        // 內容上限 720：扣掉留白後還比 720 寬時，卡片會再被置中推開。
        final centering = math.max(0.0, (size.width - padding * 2 - 720) / 2);
        expect(
          tester.getTopLeft(find.byType(SectionCard).first).dx,
          padding + centering,
        );
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  for (final (pageName, page) in [
    ('settings', const SettingsPage() as Widget),
    ('contributors', const ContributorsPage()),
  ]) {
    testWidgets('$pageName section cards are one card gap apart on desktop', (
      tester,
    ) async {
      await pump(tester, const Size(1280, 800), page);
      final cards = find.byType(SectionCard);
      expect(
        tester.getTopLeft(cards.at(1)).dy -
            tester.getBottomLeft(cards.at(0)).dy,
        AppSpacing.m,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('banner page padding stays 16 on desktop', (tester) async {
    await pump(
      tester,
      const Size(1280, 800),
      const BannerPage(gachaType: '301'),
    );
    expect(tester.getTopLeft(find.byType(PityCard).first).dx, 16);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('overview builds bottom sections only when scrolled near', (
    tester,
  ) async {
    await pump(tester, const Size(360, 800), const OverviewPage());
    final l = AppLocalizations.of(tester.element(find.byType(OverviewPage)))!;
    expect(find.byType(TimelineVertical, skipOffstage: false), findsNothing);
    // 祈願段在畫面上時，頌願段的區塊還沒建構：只有祈願段的三張統計卡。
    expect(find.byType(StatCard, skipOffstage: false), findsNWidgets(3));
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byType(TimelineVertical),
      500,
      scrollable: scrollable,
    );
    expect(find.byType(TimelineVertical), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(l.pageOverviewOdesSection),
      500,
      scrollable: scrollable,
    );
    await tester.scrollUntilVisible(
      find.byType(StatCard).first,
      300,
      scrollable: scrollable,
    );
    // 捲到頌願段時，畫面外的祈願段統計卡已經回收，只剩頌願段的三張。
    expect(find.byType(StatCard, skipOffstage: false), findsNWidgets(3));
    expect(
      find.text(l.pageOverviewGachaSection, skipOffstage: false),
      findsNothing,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('banner page builds the record table only when scrolled near', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
    );
    expect(find.byType(SortableTable, skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(
      find.byType(SortableTable),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(SortableTable), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('banner page has one sort button, inside the filter bar', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
    );
    await tester.scrollUntilVisible(
      find.byType(SortableTable),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(RecordSortButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchFilterBar),
        matching: find.byType(RecordSortButton),
      ),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, page) in [
    ('banner', const BannerPage(gachaType: '301')),
    ('odes banner', const BannerPage(gachaType: '2000')),
  ]) {
    testWidgets('$name page shows record cards in phone landscape', (
      tester,
    ) async {
      await pump(tester, const Size(800, 360), page);
      await tester.scrollUntilVisible(
        find.byType(SortableTable),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      final l = AppLocalizations.of(
        tester.element(find.byType(SortableTable)),
      )!;
      expect(find.text(l.tableTotalIndex), findsNothing);
      // 篩選列保活，捲過頭仍在樹上；不計畫面外的以免被捲動量影響。
      expect(
        find.byType(RecordSortButton, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.textContaining('#', findRichText: true), findsWidgets);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('odes banner page uses one-row filters and landscape cards', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '2000'),
    );
    await tester.scrollUntilVisible(
      find.byType(SortableTable),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byType(SearchFilterBar),
        matching: find.byType(RecordSortButton),
      ),
      findsOneWidget,
    );
    expect(find.byType(RecordSortButton), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  /// 在高度會變的容器裡呈現 [page]，回傳高度 notifier；橫向標題列收合、鍵盤開合時內容區高度每幀都在變。
  Future<ValueNotifier<double>> pumpResizable(
    WidgetTester tester,
    Widget page,
  ) async {
    final height = ValueNotifier(300.0);
    addTearDown(height.dispose);
    await pump(
      tester,
      const Size(800, 360),
      ValueListenableBuilder<double>(
        valueListenable: height,
        builder: (_, h, child) => Align(
          alignment: Alignment.topCenter,
          child: SizedBox(height: h, child: child),
        ),
        child: page,
      ),
    );
    return height;
  }

  /// 把高度由 248 逐幀拉到 300，回傳期間重建了幾次標題、保底卡、統計卡與圓餅卡。
  Future<int> cardRebuildsWhileResizing(
    WidgetTester tester,
    ValueNotifier<double> height,
  ) async {
    var rebuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget
          case PageHeader() || PityCard() || StatCard() || RarityChartCard()) {
        rebuilds++;
      }
    };
    for (var h = 248.0; h <= 300; h += 4) {
      height.value = h;
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = previous;
    return rebuilds;
  }

  for (final (name, page) in [
    ('banner', const BannerPage(gachaType: '301')),
    ('overview', const OverviewPage()),
  ]) {
    testWidgets(
      '$name page does not rebuild its cards when only height changes',
      (tester) async {
        final height = await pumpResizable(tester, page);
        expect(await cardRebuildsWhileResizing(tester, height), 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('overview odes section does not rebuild on height-only changes', (
    tester,
  ) async {
    final height = await pumpResizable(tester, const OverviewPage());
    final l = AppLocalizations.of(tester.element(find.byType(OverviewPage)))!;
    await tester.scrollUntilVisible(
      find.text(l.pageOverviewOdesSection),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(await cardRebuildsWhileResizing(tester, height), 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('banner filter bar is kept alive when scrolled out of view', (
    tester,
  ) async {
    // 篩選列包在 LayoutBuilder 裡建構，捲出可視範圍後仍要保留原本的 State（輸入框內容、計時器）。
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
      records: [
        for (var i = 0; i < 60; i++)
          GachaRecord(
            id: '${6000 + i}',
            uid: '701000000',
            gachaType: '301',
            rankType: 3,
            itemType: '武器',
            name: 'Item $i',
            time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
            lang: 'zh-tw',
          ),
      ],
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byType(SearchFilterBar),
      300,
      scrollable: scrollable,
    );
    final bar = tester.state(find.byType(SearchFilterBar));
    await tester.drag(scrollable, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byType(SearchFilterBar), findsNothing);
    expect(
      tester.state(find.byType(SearchFilterBar, skipOffstage: false)),
      same(bar),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('changing the record page scrolls back to the list title', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '301'),
      records: [
        for (var i = 0; i < 45; i++)
          GachaRecord(
            id: '${5000 + i}',
            uid: '701000000',
            gachaType: '301',
            rankType: 3,
            itemType: '武器',
            name: 'Item $i',
            time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
            lang: 'zh-tw',
          ),
      ],
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byType(Pager),
      100,
      scrollable: scrollable,
    );
    final l = AppLocalizations.of(tester.element(find.byType(Pager)))!;
    await tester.ensureVisible(find.byTooltip(l.actionNextPage));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l.actionNextPage));
    await tester.pumpAndSettle();
    final title = find.widgetWithText(
      InlineSectionTitle,
      l.pageBannerRecordList,
    );
    final top = tester.getTopLeft(scrollable).dy;
    expect(tester.getTopLeft(title).dy, closeTo(top, 8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, page) in [
    ('overview', const OverviewPage()),
    ('banner', const BannerPage(gachaType: '301')),
    ('odes banner', const BannerPage(gachaType: '2000')),
  ]) {
    testWidgets('$name page does not rebuild when only progress changes', (
      tester,
    ) async {
      final container = await pump(tester, const Size(360, 800), page);
      var rebuilds = 0;
      debugOnRebuildDirtyWidget = (e, _) {
        if (e.widget.runtimeType == page.runtimeType) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      // clearProgress 每次都產生新的狀態物件，等同更新時每換一池更新一次進度。
      container.read(gachaRepositoryProvider.notifier).clearProgress();
      await tester.pump();
      expect(rebuilds, 0);
    });
  }

  testWidgets('overview keeps its three stat cards in one row on desktop', (
    tester,
  ) async {
    await pump(tester, const Size(1280, 800), const OverviewPage());
    expectNoException(tester);
    // 只看畫面上的卡片：頌願段的三張在畫面下方。
    final tops = [
      for (final e in find.byType(StatCard).evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    ];
    expect(tops, hasLength(3));
    expect(tops.toSet(), hasLength(1));
    final heights = {
      for (final e in find.byType(StatCard).evaluate())
        tester.getSize(find.byWidget(e.widget)).height,
    };
    expect(heights, hasLength(1), reason: 'IntrinsicHeight keeps cards equal');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  /// [finder] 第 [i] 個元件的左上角。
  Offset topLeftAt(WidgetTester tester, Finder finder, int i) =>
      tester.getTopLeft(finder.at(i));

  /// 斷言 [cards] 的後兩張同列、等高，且第一張在它們上方。
  void expectLastTwoPaired(WidgetTester tester, Finder cards) {
    final a = topLeftAt(tester, cards, 1);
    final b = topLeftAt(tester, cards, 2);
    expect(a.dy, b.dy);
    expect(a.dx, isNot(b.dx));
    expect(topLeftAt(tester, cards, 0).dy, lessThan(a.dy));
    expect(
      tester.getSize(cards.at(1)).height,
      tester.getSize(cards.at(2)).height,
    );
  }

  testWidgets('overview pairs the last two stat cards on a phone', (
    tester,
  ) async {
    await pump(tester, const Size(360, 800), const OverviewPage());
    expectNoException(tester);
    final cards = find.byType(StatCard);
    expect(cards, findsNWidgets(3));
    expectLastTwoPaired(tester, cards);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('overview odes section pairs stat cards on phones', (
    tester,
  ) async {
    await pump(tester, const Size(360, 800), const OverviewPage());
    final l = AppLocalizations.of(tester.element(find.byType(OverviewPage)))!;
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text(l.pageOverviewOdesSection),
      500,
      scrollable: scrollable,
    );
    await tester.scrollUntilVisible(
      find.byType(StatCard).first,
      300,
      scrollable: scrollable,
    );
    final cards = find.byType(StatCard);
    expect(cards, findsNWidgets(3));
    expect(
      topLeftAt(tester, cards, 0).dy,
      greaterThan(
        tester.getBottomLeft(find.text(l.pageOverviewOdesSection)).dy,
      ),
    );
    expectLastTwoPaired(tester, cards);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  /// 單一卡池 [gachaType] 的 30 筆五星／四星／三星交錯記錄。
  List<GachaRecord> recordsOf(String gachaType) => [
    for (var i = 0; i < 30; i++)
      GachaRecord(
        id: '${4000 + i}',
        uid: '701000000',
        gachaType: gachaType,
        rankType: i % 10 == 0 ? 5 : (i % 3 == 0 ? 4 : 3),
        itemType: '角色',
        name: 'Item $i',
        time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
        lang: 'zh-tw',
      ),
  ];

  // 全部卡池（含新手與頌願常駐）；有次保底就兩欄並排，沒有就總抽數獨佔一列。
  for (final type in gachaTypes) {
    testWidgets(
      'stat card rows follow banner ${type.gachaType} pity rules on a phone',
      (tester) async {
        await pump(
          tester,
          const Size(360, 800),
          BannerPage(gachaType: type.gachaType),
          banners: {type.gachaType: recordsOf(type.gachaType)},
        );
        expectNoException(tester);
        final pity = find.byType(PityCard);
        final total = find.byType(StatCard);
        if (type.secondaryPity != null) {
          expect(pity, findsNWidgets(2));
          expect(
            topLeftAt(tester, pity, 0).dy,
            lessThan(topLeftAt(tester, pity, 1).dy),
          );
          expect(topLeftAt(tester, pity, 1).dy, topLeftAt(tester, total, 0).dy);
          expect(
            tester.getSize(pity.at(1)).height,
            tester.getSize(total.first).height,
          );
        } else {
          expect(pity, findsOneWidget);
          expect(
            topLeftAt(tester, pity, 0).dy,
            lessThan(topLeftAt(tester, total, 0).dy),
          );
          expect(
            tester.getSize(total.first).width,
            tester.getSize(pity.first).width,
          );
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('odes banner page pairs stat cards on phones', (tester) async {
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '2000'),
    );
    expectNoException(tester);
    final pity = find.byType(PityCard);
    expect(pity, findsNWidgets(2));
    expect(
      topLeftAt(tester, pity, 1).dy,
      topLeftAt(tester, find.byType(StatCard), 0).dy,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('banner page shows three cards in a row in phone landscape', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(800, 360),
      const BannerPage(gachaType: '301'),
    );
    expectNoException(tester);
    final pity = find.byType(PityCard);
    expect(pity, findsNWidgets(2));
    final dy = topLeftAt(tester, find.byType(StatCard), 0).dy;
    expect(topLeftAt(tester, pity, 0).dy, dy);
    expect(topLeftAt(tester, pity, 1).dy, dy);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final locale in [
    const Locale('en'),
    const Locale('ja'),
    const Locale('fr'),
  ]) {
    for (final (name, page) in [
      ('overview', const OverviewPage() as Widget),
      ('banner', const BannerPage(gachaType: '301')),
    ]) {
      testWidgets('$name at 1.3x text scale in $locale does not overflow', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester, const Size(360, 800), page, locale: locale);
        if (name == 'overview') {
          await scrollToEnd(tester);
        } else {
          // 表格與 Pager 在畫面外、按需才建構，首屏不會有任何溢出。
          expectNoException(tester);
          expect(find.byType(PityCard), findsNWidgets(2));
          await tester.scrollUntilVisible(
            find.byType(ItemTypeChartCard),
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }
  }

  /// 目前畫面上所有圓餅卡的版面（綜合頁祈願與頌願兩段各一組）。
  List<ChartCardLayout> pieLayouts(WidgetTester tester) => [
    for (final w in tester.widgetList<RarityChartCard>(
      find.byType(RarityChartCard),
    ))
      w.layout,
    for (final w in tester.widgetList<ItemTypeChartCard>(
      find.byType(ItemTypeChartCard),
    ))
      w.layout,
  ];

  for (final (name, page) in [
    ('overview', const OverviewPage() as Widget),
    ('banner', const BannerPage(gachaType: '301')),
    ('odes banner', const BannerPage(gachaType: '2000')),
  ]) {
    testWidgets('$name pie cards are compact on a portrait phone', (
      tester,
    ) async {
      await pump(tester, const Size(360, 800), page);
      expectNoException(tester);
      expect(pieLayouts(tester), everyElement(ChartCardLayout.compact));
      expect(
        tester.getSize(find.byType(RarityChartCard).first).height,
        lessThan(260),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('$name pie cards sit side by side in phone landscape', (
      tester,
    ) async {
      await pump(tester, const Size(800, 360), page);
      expect(
        pieLayouts(tester),
        everyElement(ChartCardLayout.compactTitleBeside),
      );
      final rarity = find.byType(RarityChartCard).first;
      final itemType = find.byType(ItemTypeChartCard).first;
      expect(tester.getTopLeft(rarity).dy, tester.getTopLeft(itemType).dy);
      expect(
        tester.getTopLeft(itemType).dx,
        greaterThan(tester.getTopRight(rarity).dx),
      );
      // 圖例列數不同（稀有度 3 列、類型 2 列）時，同一列的兩張卡仍要等高。
      expect(tester.getSize(itemType).height, tester.getSize(rarity).height);
      // 兩張圓餅卡中間的縫要對齊上面數值卡列的縫。
      final rarityRight = tester.getTopRight(rarity).dx;
      final statRights = [
        for (final e
            in find
                .byWidgetPredicate((w) => w is StatCard || w is PityCard)
                .evaluate())
          tester.getTopRight(find.byWidget(e.widget)).dx,
      ];
      expect(
        statRights.any((x) => (x - rarityRight).abs() < 0.5),
        isTrue,
        reason: 'rarity right $rarityRight vs stat cards $statRights',
      );
      await scrollToEnd(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('$name pie cards stay standard on desktop', (tester) async {
      await pump(tester, const Size(1280, 800), page);
      expect(pieLayouts(tester), everyElement(ChartCardLayout.standard));
      expect(tester.getSize(find.byType(RarityChartCard).first).height, 380);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    for (final (form, size, platform) in const [
      ('portrait phone', Size(360, 800), TargetPlatform.android),
      ('landscape phone', Size(800, 360), TargetPlatform.android),
      ('desktop', Size(1280, 800), TargetPlatform.windows),
    ]) {
      testWidgets('$name stat row and pie row are one card gap apart ($form)', (
        tester,
      ) async {
        await pump(tester, size, page);
        final pieTop = tester.getTopLeft(find.byType(RarityChartCard).first).dy;
        // 綜合頁有祈願、頌願兩段：只取第一個圓餅卡上方的數字卡。
        final statBottom = [
          for (final e
              in find
                  .byWidgetPredicate((w) => w is StatCard || w is PityCard)
                  .evaluate())
            tester.getBottomLeft(find.byWidget(e.widget)).dy,
        ].where((y) => y <= pieTop).reduce((a, b) => a > b ? a : b);
        expect(pieTop - statBottom, AppSpacing.m);
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  /// 橫向時間軸所在的 [ChartCard]。
  Finder timelineCard() => find.ancestor(
    of: find.byType(TimelineHorizontal),
    matching: find.byType(ChartCard),
  );

  for (final (name, size) in const [
    ('portrait', Size(360, 800)),
    ('landscape', Size(914, 411)),
  ]) {
    for (final gachaType in const ['301', '2000']) {
      testWidgets('banner $gachaType timeline card spans the row and fits '
          'its content on a phone ($name)', (tester) async {
        await pump(tester, size, BannerPage(gachaType: gachaType));
        await tester.scrollUntilVisible(
          find.byType(TimelineHorizontal),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expectNoException(tester);
        final card = tester.getRect(timelineCard());
        // 與上方圓餅列同寬：左緣對齊稀有度卡、右緣對齊類型卡。
        final rarity = find.byType(RarityChartCard, skipOffstage: false);
        final itemType = find.byType(ItemTypeChartCard, skipOffstage: false);
        expect(card.left, tester.getTopLeft(rarity).dx);
        expect(card.right, tester.getTopRight(itemType).dx);
        expect(card.top, greaterThan(tester.getBottomLeft(itemType).dy));
        expect(card.height, lessThan(kChartCardHeight - 60));
        // 時間軸高度貼合欄內容：首個月份標籤就在時間軸頂端，上方沒有空白帶。
        final l = AppLocalizations.of(tester.element(timelineCard()))!;
        final timeline = tester.getRect(find.byType(TimelineHorizontal));
        final label = tester.getRect(
          find.text(l.timelineMonthLabel('2026', '05')).first,
        );
        expect(label.top - timeline.top, lessThan(2));
        // 底部也沒有空白帶：最低的日期列貼近時間軸底端。
        final lowestText = find
            .descendant(
              of: find.byType(TimelineHorizontal),
              matching: find.byType(RichText),
            )
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)).bottom)
            .reduce((a, b) => a > b ? a : b);
        expect(timeline.bottom - lowestText, lessThanOrEqualTo(16));
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    }
  }

  testWidgets('banner timeline card shares the pie row on desktop', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(1280, 800),
      const BannerPage(gachaType: '301'),
    );
    expectNoException(tester);
    final card = tester.getRect(timelineCard());
    final rarity = tester.getRect(find.byType(RarityChartCard));
    expect(card.top, rarity.top);
    expect(card.height, rarity.height);
    expect(card.height, kChartCardHeight);
    expect(card.width, rarity.width);
    expect(card.left, greaterThan(rarity.right));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('banner page keeps pity and total cards in one row on desktop', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(1280, 800),
      const BannerPage(gachaType: '301'),
    );
    expectNoException(tester);
    expect(
      tester.getTopLeft(find.byType(StatCard).first).dy,
      tester.getTopLeft(find.byType(PityCard).first).dy,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'desktop builds the whole overview so the scrollbar stays stable',
    (tester) async {
      await pump(tester, const Size(1280, 800), const OverviewPage());
      // 祈願、頌願兩段的時間軸都已建好。
      expect(
        find.byType(TimelineVertical, skipOffstage: false),
        findsNWidgets(2),
      );
      expectNoException(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'desktop builds the whole banner page so the scrollbar stays stable',
    (tester) async {
      await pump(
        tester,
        const Size(1280, 400),
        const BannerPage(gachaType: '301'),
      );
      expect(find.byType(SortableTable, skipOffstage: false), findsOneWidget);
      expectNoException(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('narrow desktop window still builds the whole overview', (
    tester,
  ) async {
    // 電腦視窗拉窄會切成手機排版，但捲軸仍常駐，整頁照樣預先建好。
    await pump(tester, const Size(500, 800), const OverviewPage());
    expect(isCompactLayout(tester.element(find.byType(OverviewPage))), isTrue);
    expect(
      find.byType(TimelineVertical, skipOffstage: false),
      findsNWidgets(2),
    );
    expectNoException(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('android tablets still build the overview on demand', (
    tester,
  ) async {
    await pump(tester, const Size(1280, 800), const OverviewPage());
    // 平板寬度下祈願段較矮、它的時間軸落在預先建構範圍內；畫面外的頌願段時間軸還沒建構。
    expect(find.byType(TimelineVertical, skipOffstage: false), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'banner page keeps table and search state when the five-star section appears',
    (tester) async {
      List<GachaRecord> records({required bool withFiveStar}) => [
        for (var i = 0; i < 45; i++)
          GachaRecord(
            id: '${3000 + i}',
            uid: '701000000',
            gachaType: '301',
            rankType: withFiveStar && i == 44 ? 5 : (i % 3 == 0 ? 4 : 3),
            itemType: '武器',
            name: 'Item $i',
            time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
            lang: 'zh-tw',
          ),
      ];
      final container = await pump(
        tester,
        const Size(360, 800),
        const BannerPage(gachaType: '301'),
        records: records(withFiveStar: false),
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byType(Pager),
        500,
        scrollable: scrollable,
      );
      await tester.ensureVisible(find.byType(Pager));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(Pager),
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      await tester.pump();
      expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
      final searchBar = find.byType(SearchFilterBar, skipOffstage: false);
      final searchState = tester.state(searchBar);

      final repo = container.read(gachaRepositoryProvider.notifier);
      repo.state = repo.state.copyWith(
        byUid: {
          '701000000': BannerStorage(
            uid: '701000000',
            lastUpdated: DateTime.utc(2026, 5, 1),
            banners: {
              '301': records(withFiveStar: true),
              '2000': _odesRecords(),
            },
          ),
        },
      );
      await tester.pump();

      final after = searchBar.evaluate();
      expect(after, hasLength(1), reason: 'search bar state was dropped');
      expect((after.single as StatefulElement).state, same(searchState));
      expect(tester.widget<Pager>(find.byType(Pager)).page, 1);

      // 確認五星一覽確實出現了（不是空轉的測試）。
      await tester.scrollUntilVisible(
        find.byIcon(Icons.star_outline),
        -500,
        scrollable: scrollable,
      );
      expect(find.byIcon(Icons.star_outline), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('odes banner page keeps table page after scrolling out', (
    tester,
  ) async {
    // 頌願頁共用 BannerPage：記錄表翻到第 2 頁、捲到頁首再捲回，仍停在第 2 頁。
    await pump(
      tester,
      const Size(360, 800),
      const BannerPage(gachaType: '2000'),
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byType(Pager),
      500,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.byType(Pager));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(Pager),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pump();
    expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
    final table = tester.state(find.byType(SortableTable));

    await tester.drag(scrollable, const Offset(0, 6000));
    await tester.pumpAndSettle();
    expect(find.byType(Pager), findsNothing);
    expect(find.byType(PageHeader), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(Pager),
      500,
      scrollable: scrollable,
    );
    expect(tester.widget<Pager>(find.byType(Pager)).page, 1);
    expect(tester.state(find.byType(SortableTable)), same(table));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  /// 200 個不同的五星（手機寬約 40 列），用來驗證五星一覽按列建構。
  List<GachaRecord> manyFiveStars() => [
    for (var i = 0; i < 200; i++)
      GachaRecord(
        id: '${3000 + i}',
        uid: '701000000',
        gachaType: '301',
        rankType: 5,
        itemType: '角色',
        name: 'Star $i',
        time: DateTime(2026, 5, 1).subtract(Duration(hours: i)),
        lang: 'zh-tw',
      ),
  ];

  for (final (name, page) in [
    ('overview', const OverviewPage() as Widget),
    ('banner page', const BannerPage(gachaType: '301')),
  ]) {
    testWidgets('$name builds the five-star overview row by row', (
      tester,
    ) async {
      await pump(tester, const Size(360, 800), page, records: manyFiveStars());
      await tester.scrollUntilVisible(
        find.byIcon(Icons.star_outline),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final chips = find.descendant(
        of: find.byType(SliverFiveStarOverview, skipOffstage: false),
        matching: find.byType(GachaItemIcon, skipOffstage: false),
      );
      expect(chips.evaluate(), isNotEmpty);
      expect(chips.evaluate().length, lessThan(200));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('odes section has no five-star overview rows', (tester) async {
    // 只有祈願段有五星一覽，頌願段不多出空區塊或間距。
    // 視窗拉高讓兩段都在畫面內：畫面外 sliver 的繪製位置會被夾住，量不出間距。
    await pump(tester, const Size(1280, 6000), const OverviewPage());
    expectNoException(tester);
    expect(
      find.byType(SliverFiveStarOverview, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.star_outline, skipOffstage: false),
      findsOneWidget,
    );
    // 頌願段在下方：取各自最下面的那一個。
    double lowest(Finder f, double Function(Rect) edge) => f
        .evaluate()
        .map(
          (e) => edge(
            tester.getRect(find.byWidget(e.widget, skipOffstage: false)),
          ),
        )
        .reduce((a, b) => a > b ? a : b);
    final barsBottom = lowest(
      find.byWidgetPredicate(
        (w) => w is ChartCard && w.chart is BannerTopRarityBars,
        skipOffstage: false,
      ),
      (r) => r.bottom,
    );
    final timelineTitleTop = lowest(
      find.byWidgetPredicate(
        (w) => w is InlineSectionTitle && w.icon == Icons.timeline,
        skipOffstage: false,
      ),
      (r) => r.top,
    );
    expect(timelineTitleTop - barsBottom, AppSpacing.xl);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
