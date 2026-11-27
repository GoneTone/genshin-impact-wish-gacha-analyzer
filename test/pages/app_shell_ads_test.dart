import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/ads.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

/// 已有一個帳號的 repository 替身。
class _Repo extends GachaRepository {
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
  Future<void> update({bool afterPairing = false}) async {}
}

/// 狀態固定、不碰原生 SDK 的廣告控制器替身。
class _Ads extends AdsController {
  /// [start] 被呼叫的次數。
  int starts = 0;

  @override
  AdsState build() => const AdsState(canRequestAds: true);

  @override
  Future<void> start() async => starts++;
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
  late _Ads ads;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 以 [size] 開啟外殼；[android] 決定 `isAndroidProvider` 的值。
  Future<void> pump(
    WidgetTester tester,
    Size size, {
    bool android = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ads = _Ads();
    final container = ProviderContainer(
      overrides: [
        appVersionProvider.overrideWithValue('1.8.1'),
        gachaRepositoryProvider.overrideWith(_Repo.new),
        appReleaseProvider.overrideWith(_Release.new),
        cloudSyncProvider.overrideWith(_Sync.new),
        isAndroidProvider.overrideWithValue(android),
        adsProvider.overrideWith(() => ads),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (_, _, child) => AppShell(child: child),
          routes: [GoRoute(path: '/', builder: (_, _) => const Text('page'))],
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
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts the ads flow on Android only', (tester) async {
    await pump(tester, const Size(412, 915));
    expect(ads.starts, 1);
  });

  testWidgets('never starts the ads flow off Android', (tester) async {
    await pump(tester, const Size(1280, 800), android: false);
    expect(ads.starts, 0);
  });
}
