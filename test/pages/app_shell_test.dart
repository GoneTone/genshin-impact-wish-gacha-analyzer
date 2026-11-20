import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/last_updated_label.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';

/// 已有一個帳號、記錄 update 呼叫次數的 repository 替身。
class _Repo extends GachaRepository {
  /// update 被呼叫的次數。
  int updates = 0;

  @override
  GachaState build() => GachaState(
    activeUid: '701000000',
    byUid: {
      '701000000': BannerStorage(
        uid: '701000000',
        lastUpdated: DateTime.now().toUtc(),
        banners: const {},
      ),
    },
    isBootstrapping: false,
  );

  @override
  Future<void> update({bool afterPairing = false}) async => updates++;
}

/// 不發請求的版本檢查替身。
class _Release extends AppReleaseNotifier {
  @override
  Future<void> check({required bool manual}) async {}
}

/// 不啟動同步的雲端同步替身。
class _Sync extends CloudSyncNotifier {
  @override
  Future<void> start() async {}
}

void main() {
  late _Repo repo;
  late ProviderContainer container;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 以 [size] 開啟外殼（起始於 [initialLocation]）；路由頁面只顯示 `page:<path>`。
  Future<AppLocalizations> pump(
    WidgetTester tester,
    Size size, {
    Locale locale = const Locale('zh'),
    double textScale = 1,
    String? alias,
    double keyboard = 0,
    String initialLocation = '/',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    repo = _Repo();
    container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.8.1'),
        gachaRepositoryProvider.overrideWith(() => repo),
        appReleaseProvider.overrideWith(_Release.new),
        cloudSyncProvider.overrideWith(_Sync.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).waitForLoad();
    if (alias != null) {
      await container
          .read(settingsProvider.notifier)
          .setUidAlias('701000000', alias);
    }
    Widget page(GoRouterState s) => Text('page:${s.uri.path}');
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (_, _, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, s) => page(s)),
            GoRoute(path: '/banner/:type', builder: (_, s) => page(s)),
            GoRoute(path: '/contributors', builder: (_, s) => page(s)),
            GoRoute(path: '/settings', builder: (_, s) => page(s)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(AppShell)))!;
  }

  /// 抽屜按鈕（Scaffold 自動加在 AppBar 左上）。
  Finder drawerButton(WidgetTester tester) => find.byTooltip(
    MaterialLocalizations.of(
      tester.element(find.byType(AppShell)),
    ).openAppDrawerTooltip,
  );

  testWidgets('phone portrait uses a drawer instead of the rail', (
    tester,
  ) async {
    final l = await pump(tester, const Size(360, 800));
    expect(drawerButton(tester), findsOneWidget);
    expect(find.text(l.navOverview), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('drawer lists the same destinations as the rail', (tester) async {
    final l = await pump(tester, const Size(360, 800));
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    // 頌願「常駐」與祈願「常駐」同名，頌願區段改用「活動」代表。
    for (final label in [
      l.navOverview,
      l.navCharacter,
      l.navOdesEvent,
      l.navContributors,
      l.navSettings,
    ]) {
      final f = find.text(label);
      await tester.scrollUntilVisible(
        f,
        50,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(f, findsOneWidget, reason: label);
      expect(
        tester
            .getSize(find.ancestor(of: f, matching: find.byType(InkWell)).first)
            .height,
        greaterThanOrEqualTo(48),
        reason: label,
      );
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('tapping a drawer item navigates and closes the drawer', (
    tester,
  ) async {
    final l = await pump(tester, const Size(360, 800));
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.navWeapon));
    await tester.pumpAndSettle();
    expect(
      find.text('page:/banner/${gachaTypes[1].gachaType}'),
      findsOneWidget,
    );
    expect(find.byType(Drawer), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('drawer marks the current odes page', (tester) async {
    final firstOdes = gachaTypes.firstWhere(
      (t) => t.category == GachaCategory.odes,
    );
    final firstGacha = gachaTypes.firstWhere(
      (t) => t.category == GachaCategory.gacha,
    );
    final l = await pump(
      tester,
      const Size(360, 800),
      initialLocation: '/banner/${firstOdes.gachaType}',
    );
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    // 選中項目換成實心圖示：第一個頌願選中，第一個祈願（角色）沒有。
    expect(
      find.descendant(of: drawer, matching: find.byIcon(Icons.auto_awesome)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.byIcon(Icons.person)),
      findsNothing,
    );
    await tester.tap(find.text(l.navCharacter));
    await tester.pumpAndSettle();
    expect(find.text('page:/banner/${firstGacha.gachaType}'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone landscape also uses the drawer', (tester) async {
    await pump(tester, const Size(800, 360));
    expect(drawerButton(tester), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop keeps the rail and the version', (tester) async {
    final l = await pump(tester, const Size(1280, 800));
    expect(drawerButton(tester), findsNothing);
    expect(find.text(l.navOverview), findsOneWidget);
    expect(find.textContaining('v1.8.1'), findsOneWidget);
    expect(find.text(TeamInfo.name), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  // 測試字型把拉丁字母與數字畫成全形寬，帳號標示會比實際寬很多；有別名的情況改在 800 寬檢查。
  for (final (name, size, locale, alias) in [
    ('640 zh', const Size(640, 450), const Locale('zh'), null),
    ('640 en', const Size(640, 450), const Locale('en'), null),
    ('800 zh alias', const Size(800, 450), const Locale('zh'), '主帳號別名'),
  ]) {
    testWidgets('narrow desktop title ellipsizes instead of clipping ($name)', (
      tester,
    ) async {
      await pump(tester, size, locale: locale, alias: alias);
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.textContaining('v1.8.1'));
      expect(title.overflow, TextOverflow.ellipsis);
      expect(title.maxLines, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  for (final (name, locale, scale) in [
    ('zh', const Locale('zh'), 1.0),
    ('en', const Locale('en'), 1.0),
    ('large text', const Locale('zh'), 1.3),
  ]) {
    testWidgets('phone title hides the version and never overflows ($name)', (
      tester,
    ) async {
      await pump(
        tester,
        const Size(360, 800),
        locale: locale,
        textScale: scale,
        alias: 'AVeryLongAccountAliasName',
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('v1.8.1'), findsNothing);
      expect(find.textContaining('701000000'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('phone update button is an icon with a tooltip', (tester) async {
    final l = await pump(tester, const Size(360, 800));
    final button = find.byTooltip(l.actionUpdate);
    expect(
      find.ancestor(of: button, matching: find.byType(IconButton)),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    expect(repo.updates, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, locale) in [('ja', Locale('ja')), ('en', Locale('en'))]) {
    testWidgets('account menu fits a phone and shows the full alias ($name)', (
      tester,
    ) async {
      await pump(
        tester,
        const Size(360, 800),
        locale: locale,
        textScale: 1.3,
        alias: 'MainAcct',
      );
      await tester.tap(find.byType(AccountTriggerButton));
      await tester.pumpAndSettle();
      final e = tester.takeException();
      expect(e, isNull, reason: e is FlutterError ? e.toStringDeep() : '$e');
      final menuAlias = tester.renderObject<RenderParagraph>(
        find.text('MainAcct').last,
      );
      expect(menuAlias.didExceedMaxLines, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('phone account button uses 12dp side padding', (tester) async {
    // 按鈕內距從 24 縮到 12，360dp 手機上 UID 才放得下。
    await pump(tester, const Size(360, 800));
    final button = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byType(AccountTriggerButton),
        matching: find.byType(OutlinedButton),
      ),
    );
    final padding = button.style!.padding!.resolve({});
    expect(padding, const EdgeInsets.symmetric(horizontal: 12));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone landscape with the keyboard open hides the footer', (
    tester,
  ) async {
    // 橫向手機開鍵盤後只剩約 50dp，固定的底部狀態列會把畫面擠到溢出。
    await pump(tester, const Size(800, 360), keyboard: 250);
    final e = tester.takeException();
    expect(e, isNull, reason: e is FlutterError ? e.toStringDeep() : '$e');
    expect(find.byType(TeamLinksBar), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone footer is 48dp tall', (tester) async {
    await pump(tester, const Size(360, 800));
    expect(
      tester.getSize(find.byKey(const Key('shell-bottom-bar'))).height,
      48,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone bottom bar has no team links in portrait or landscape', (
    tester,
  ) async {
    await pump(tester, const Size(360, 800));
    final bar = find.byKey(const Key('shell-bottom-bar'));
    expect(
      find.descendant(of: bar, matching: find.byType(LastUpdatedLabel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.byType(TeamLinksBar)),
      findsNothing,
    );
    await pump(tester, const Size(800, 360));
    expect(find.byKey(const Key('shell-bottom-bar')), findsNothing);
    expect(find.byType(LastUpdatedLabel), findsNothing);
    expect(find.byType(TeamLinksBar), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone landscape has no footer', (tester) async {
    await pump(tester, const Size(800, 360));
    expect(find.byKey(const Key('shell-bottom-bar')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop bottom bar keeps the one-row team links', (
    tester,
  ) async {
    await pump(tester, const Size(1280, 800));
    final bar = find.byKey(const Key('shell-bottom-bar'));
    expect(
      find.descendant(of: bar, matching: find.byType(LastUpdatedLabel)),
      findsOneWidget,
    );
    final links = find.descendant(of: bar, matching: find.byType(TeamLinksBar));
    expect(links, findsOneWidget);
    expect(tester.widget<TeamLinksBar>(links).stacked, isFalse);
    expect(find.byType(Drawer), findsNothing);
    final icon = tester.getRect(find.byType(FaIcon).first);
    final name = tester.getRect(find.text(TeamInfo.name));
    expect((icon.center.dy - name.center.dy).abs(), lessThan(8));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final (name, size) in const [
    ('portrait', Size(360, 800)),
    ('landscape', Size(914, 411)),
  ]) {
    testWidgets('phone drawer shows the stacked team links ($name)', (
      tester,
    ) async {
      await pump(tester, size);
      await tester.tap(drawerButton(tester));
      await tester.pumpAndSettle();
      final bar = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(TeamLinksBar),
      );
      expect(bar, findsOneWidget);
      expect(tester.widget<TeamLinksBar>(bar).stacked, isTrue);
      expect(find.text(TeamInfo.name), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final (name, size) in const [
    ('portrait', Size(360, 800)),
    ('landscape', Size(914, 411)),
  ]) {
    testWidgets('drawer team links stack icons over the team name ($name)', (
      tester,
    ) async {
      await pump(tester, size);
      await tester.tap(drawerButton(tester));
      await tester.pumpAndSettle();
      final bar = find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(TeamLinksBar),
      );
      await tester.ensureVisible(bar);
      await tester.pumpAndSettle();
      final buttons = find.descendant(
        of: bar,
        matching: find.byType(IconButton),
      );
      expect(buttons, findsNWidgets(4));
      var iconsBottom = 0.0;
      var iconsLeft = double.infinity;
      var iconsRight = 0.0;
      for (var i = 0; i < 4; i++) {
        final rect = tester.getRect(buttons.at(i));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        iconsBottom = rect.bottom > iconsBottom ? rect.bottom : iconsBottom;
        iconsLeft = rect.left < iconsLeft ? rect.left : iconsLeft;
        iconsRight = rect.right > iconsRight ? rect.right : iconsRight;
      }
      final nameRect = tester.getRect(find.text(TeamInfo.name));
      expect(iconsBottom, lessThanOrEqualTo(nameRect.top));
      // 兩行各自在抽屜可見內容間置中：圖示按鈕左右的空白對稱，名稱本身置中。
      final center = tester.getCenter(find.byType(Drawer)).dx;
      expect((iconsLeft + iconsRight) / 2, closeTo(center, 1));
      expect(nameRect.center.dx, closeTo(center, 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final locale in const [Locale('en'), Locale('ja')]) {
    testWidgets(
      'drawer team links fit at 1.3x text in ${locale.languageCode}',
      (tester) async {
        await pump(
          tester,
          const Size(360, 800),
          locale: locale,
          textScale: 1.3,
        );
        await tester.tap(drawerButton(tester));
        await tester.pumpAndSettle();
        final bar = find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(TeamLinksBar),
        );
        await tester.ensureVisible(bar);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.ancestor(of: bar, matching: find.byType(FittedBox)),
          findsNothing,
        );
        final drawer = tester.getRect(find.byType(Drawer));
        final nameRect = tester.getRect(find.text(TeamInfo.name));
        expect(nameRect.left, greaterThanOrEqualTo(drawer.left));
        expect(nameRect.right, lessThanOrEqualTo(drawer.right));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('narrow phone footer swaps the last updated prefix for an icon', (
    tester,
  ) async {
    // 放大字級時前綴會把時間擠掉；手機狀態列不再放連結圖示，改用大字級重現。
    final l = await pump(
      tester,
      const Size(360, 800),
      locale: const Locale('en'),
      textScale: 2,
    );
    final full = l.footerLastUpdated(l.relativeNow);
    expect(find.byIcon(Icons.update), findsOneWidget);
    expect(find.text(l.relativeNow), findsOneWidget);
    expect(find.textContaining('Last updated'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.update));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(full), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, size, locale) in [
    ('zh phone', const Size(360, 800), const Locale('zh')),
    ('en desktop', const Size(1280, 800), const Locale('en')),
  ]) {
    testWidgets(
      'footer keeps the full last updated text when it fits ($name)',
      (tester) async {
        final l = await pump(tester, size, locale: locale);
        expect(find.byIcon(Icons.update), findsNothing);
        final prefix = l.footerLastUpdated('').trim();
        expect(find.textContaining(prefix, findRichText: true), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('system back closes the open drawer instead of leaving the app', (
    tester,
  ) async {
    // Android 16 的預測返回：App 沒先宣告「自己處理返回」時，系統會直接關掉 App。
    final handlesBack = <bool>[];
    var systemPops = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handlesBack.add(call.arguments as bool);
        }
        if (call.method == 'SystemNavigator.pop') systemPops++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pump(tester, const Size(360, 800));
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    expect(handlesBack, isNotEmpty);
    expect(handlesBack.last, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(systemPops, 0);
    expect(find.byType(AppShell), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, size) in [
    ('phone', const Size(360, 800)),
    ('tablet', const Size(1280, 800)),
  ]) {
    testWidgets('system back on another page returns to the overview ($name)', (
      tester,
    ) async {
      var systemPops = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') systemPops++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, size);
      final router = GoRouter.of(tester.element(find.byType(AppShell)));
      for (final path in [
        '/banner/${gachaTypes.first.gachaType}',
        '/settings',
        '/contributors',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(find.text('page:$path'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('page:/'), findsOneWidget, reason: path);
        expect(systemPops, 0, reason: path);
      }

      // 在綜合頁才交給系統離開 App。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(systemPops, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('rotating with the drawer open does not throw', (tester) async {
    await pump(tester, const Size(360, 800));
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('crossing the breakpoint twice does not reopen the drawer', (
    tester,
  ) async {
    await pump(tester, const Size(500, 800));
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 800);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('phone app bar leaves the app name to the drawer header', (
    tester,
  ) async {
    final l = await pump(tester, const Size(360, 800));
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text(l.appName)),
      findsNothing,
    );
    expect(
      find.descendant(of: appBar, matching: find.byType(Image)),
      findsNothing,
    );
    await tester.tap(drawerButton(tester));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text(l.appName)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.textContaining('v1.8.1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: drawer, matching: find.byType(Image)),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone account button gets the space the title used', (
    tester,
  ) async {
    // 舊版保留給 App 圖示的 48dp 讓給帳號按鈕；360 寬時上限從 160 變成 232。
    await pump(
      tester,
      const Size(360, 800),
      alias: 'AVeryLongAccountAliasName',
    );
    final indicator = tester.getRect(find.byType(UidIndicator));
    expect(indicator.width, greaterThan(160));
    expect(
      indicator.left,
      greaterThanOrEqualTo(tester.getRect(drawerButton(tester)).right),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final (name, size, pinned) in [
    ('portrait pins them', const Size(360, 800), true),
    ('landscape scrolls them with the list', const Size(800, 360), false),
  ]) {
    testWidgets('drawer contributors and settings: $name', (tester) async {
      // 橫向高度只剩約 360dp，固定在底部會占掉三分之一，改成跟著清單一起捲。
      final l = await pump(tester, size);
      await tester.tap(drawerButton(tester));
      await tester.pumpAndSettle();
      final list = find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final label in [l.navContributors, l.navSettings, l.appName]) {
        final inList = find
            .descendant(of: list, matching: find.text(label))
            .evaluate()
            .isNotEmpty;
        // 頂部的 App 資訊一律跟著清單捲；貢獻者／設定只有高度夠時才固定。
        expect(inList, label == l.appName || !pinned, reason: label);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('phone landscape keeps the page clear of the camera cutout', (
    tester,
  ) async {
    // 橫向時開孔鏡頭在左邊；標題列由 AppBar 自己避開，內容區也要避開。
    await pump(tester, const Size(800, 360));
    tester.view.padding = const FakeViewPadding(left: 44);
    tester.view.viewPadding = const FakeViewPadding(left: 44);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('page:/')).left, greaterThanOrEqualTo(44));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('phone footer sits above the gesture bar', (tester) async {
    // 背景延伸到螢幕底，但文字要在手勢列上方。
    await pump(tester, const Size(360, 800));
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(LastUpdatedLabel)).bottom,
      lessThanOrEqualTo(800 - 24),
    );
    expect(
      tester.getRect(find.byKey(const Key('shell-bottom-bar'))).bottom,
      800,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
