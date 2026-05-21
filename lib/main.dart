import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/routing/app_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/window_state_keeper.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/logging.dart'
    as rust_logging;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

/// 應用程式入口：初始化 Flutter、Rust bridge、視窗管理、log 服務，然後啟動 app。
Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await RustLib.init();

      if (Platform.isWindows) {
        await windowManager.ensureInitialized();
        await WindowStateKeeper.bootstrap();
      }

      final supportDir = await getApplicationSupportDirectory();
      final logService = await LogService.bootstrap(supportDir);

      // 注意：onError 用 scheduleMicrotask 排到下一個 tick，避免 listener
      // 在處理某條 log 時拋例外被 zone 接住後，又同步 publish 到正在 firing
      // 的 root logger broadcast controller，造成 "Cannot fire new event" 死循環。
      FlutterError.onError = (details) {
        scheduleMicrotask(() {
          Logger('app.error').severe(
            'FlutterError: ${details.exceptionAsString()}',
            details.exception,
            details.stack,
          );
        });
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (e, st) {
        scheduleMicrotask(
          () => Logger('app.error').severe('Uncaught async error', e, st),
        );
        return true;
      };

      unawaited(_connectRustLogStream());

      final pkgInfo = await PackageInfo.fromPlatform();

      Logger('app.startup').info(
        'app start v${pkgInfo.version}+${pkgInfo.buildNumber} '
        'on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
        'locale=${Platform.localeName}',
      );

      try {
        final cleaned = await rust_capture.cleanupStaleProxy();
        if (cleaned) {
          Logger(
            'app.startup',
          ).info('cleanup_stale_proxy: stale proxy detected and reset');
        }
      } catch (e, st) {
        Logger('app.startup').warning('cleanup_stale_proxy failed', e, st);
      }

      final gachaDir = Directory('${supportDir.path}/gacha_data');
      if (!await gachaDir.exists()) {
        await gachaDir.create(recursive: true);
      }
      final storage = GachaStorage(gachaDir);

      runApp(
        ProviderScope(
          overrides: [
            gachaStorageProvider.overrideWithValue(storage),
            appVersionProvider.overrideWithValue(pkgInfo.version),
            logServiceProvider.overrideWithValue(logService),
          ],
          child: const MainApp(),
        ),
      );
    },
    (e, st) {
      scheduleMicrotask(
        () => Logger('app.error').severe('Zone uncaught', e, st),
      );
    },
  );
}

/// 訂閱 Rust 端的 log stream，將每條 log 轉發到 Dart logging。
Future<void> _connectRustLogStream() async {
  try {
    rust_logging.startLogStream().listen(
      (event) {
        Logger(
          'rust.${event.target}',
        ).log(_levelFromRust(event.level), sanitizeLogMessage(event.message));
      },
      onError: (Object e, StackTrace st) {
        Logger('rust.bridge').warning('log stream error', e, st);
      },
    );
    Logger('rust.bridge').info('rust log stream connected');
  } catch (e, st) {
    Logger('rust.bridge').warning('failed to start rust log stream', e, st);
  }
}

/// 將 Rust log level 字串對應到 Dart [Level]。
Level _levelFromRust(String s) => switch (s) {
  'ERROR' => Level.SEVERE,
  'WARN' => Level.WARNING,
  'INFO' => Level.INFO,
  'DEBUG' => Level.FINE,
  _ => Level.FINER,
};

/// App 根元件，負責套用主題、語言與路由設定。
class MainApp extends ConsumerStatefulWidget {
  /// 建立 [MainApp]。
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

/// [MainApp] 的 state，持有 GoRouter 快取。
class _MainAppState extends ConsumerState<MainApp> {
  /// 快取 router 實例，避免每次 build（主題 / 語言切換）時重建並重設到 initialLocation。
  late final GoRouter _router = buildAppRouter();

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      onGenerateTitle: (ctx) {
        final title = AppLocalizations.of(ctx)!.appName;
        if (Platform.isWindows) {
          scheduleMicrotask(() async {
            try {
              await windowManager.setTitle(title);
            } catch (e, st) {
              Logger('app.window').warning('setTitle failed', e, st);
            }
          });
        }
        return title;
      },
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: ref.watch(releasedLocalesProvider),
      localeListResolutionCallback: localeListResolution,
      routerConfig: _router,
    );
  }
}
