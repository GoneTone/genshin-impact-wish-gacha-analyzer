import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/pity_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/stat_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/timeline_vertical.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/data/sortable_table.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/manual_url_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

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

  /// 在 [size] 的畫面上呈現 [page]（已有一個帳號的紀錄，角色活動祈願預設為 [_records]），回傳 container。
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size,
    Widget page, {
    double keyboard = 0,
    PairingPhase phase = PairingPhase.disclosure,
    LogAccessMethod? method,
    List<GachaRecord>? records,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    late ProviderContainer container;
    await tester.runAsync(() async {
      final storage = GachaStorage(tempDir);
      await storage.save(
        BannerStorage(
          uid: '701000000',
          lastUpdated: DateTime.utc(2026, 5, 1),
          banners: {'301': records ?? _records(), '2000': _odesRecords()},
        ),
      );
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
          locale: const Locale('zh'),
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
}
