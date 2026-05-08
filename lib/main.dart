import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/routing/app_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/api/capture.dart'
    as rust_capture;
import 'package:genshin_impact_wish_gacha_analyzer/src/rust/frb_generated.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  try {
    final cleaned = await rust_capture.cleanupStaleProxy();
    if (cleaned) {
      debugPrint('[startup] stale proxy detected and reset');
    }
  } catch (e) {
    debugPrint('[startup] cleanup_stale_proxy failed: $e');
  }

  final supportDir = await getApplicationSupportDirectory();
  final wishDir = Directory('${supportDir.path}/wish_data');
  if (!await wishDir.exists()) {
    await wishDir.create(recursive: true);
  }
  final storage = WishStorage(wishDir);

  final pkgInfo = await PackageInfo.fromPlatform();

  runApp(ProviderScope(
    overrides: [
      wishStorageProvider.overrideWithValue(storage),
      appVersionProvider.overrideWithValue(pkgInfo.version),
    ],
    child: const MainApp(),
  ));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: appName,
      theme: buildAppTheme(),
      routerConfig: buildAppRouter(),
    );
  }
}
