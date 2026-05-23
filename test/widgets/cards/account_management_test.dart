import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';

class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 建立並預熱 ProviderContainer。
///
/// 必須在 tester.runAsync 裡呼叫，以跳出 FakeAsync 環境，
/// 讓 File I/O 和 Future.delayed 能正常完成。
Future<ProviderContainer> _setupContainer({
  required GachaStorage storage,
  Map<String, dynamic> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
  final container = ProviderContainer(
    overrides: [
      gachaStorageProvider.overrideWithValue(storage),
      gachaCaptureProvider.overrideWithValue(_NullCapture()),
      cancellableHttpClientFactoryProvider.overrideWithValue(
        () => CancellableHttpClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          cancel: () {},
        ),
      ),
    ],
  );
  await container.read(settingsProvider.notifier).waitForLoad();
  container.read(gachaRepositoryProvider);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return container;
}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'Hant'),
    theme: buildDarkTheme(),
    home: const Scaffold(body: AccountManagement()),
  ),
);

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('acct_mgmt_test_');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('依 uidOrder 顯示順序', (tester) async {
    final storage = GachaStorage(tempDir);
    // 用 runAsync 跳出 FakeAsync，讓 File I/O / Future.delayed 正常完成
    await tester.runAsync(() async {
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      await storage.save(
        BannerStorage(
          uid: '100000002',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
    });

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: storage,
        prefs: {'pref.uidOrder': '["100000001","100000002"]'},
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final textsA = tester.getTopLeft(find.text('100000001')).dy;
    final textsB = tester.getTopLeft(find.text('100000002')).dy;
    expect(
      textsA,
      lessThan(textsB),
      reason: '100000001 應該在 100000002 之前（依自訂順序）',
    );
  });

  testWidgets('拖曳 row → 呼叫 setUidOrder', (tester) async {
    final storage = GachaStorage(tempDir);
    await tester.runAsync(() async {
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
      await storage.save(
        BannerStorage(
          uid: '100000002',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
    });

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(storage: storage);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 用 ReorderableListView 的內部 onReorder 直接觸發 — 比 tester.drag 穩定
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorder(0, 2); // 把第 0 個 (100000001) 移到第 1 個（之後）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final reloaded = await tester.runAsync(() => SettingsStorage.load());
    expect(reloaded!.uidOrder, ['100000002', '100000001']);
  });

  testWidgets('編輯別名 onSubmitted → 寫入 setUidAlias', (tester) async {
    final storage = GachaStorage(tempDir);
    await tester.runAsync(() async {
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
    });

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(storage: storage);
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = find.byType(TextField).first;
    await tester.enterText(field, '主帳號');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final reloaded = await tester.runAsync(() => SettingsStorage.load());
    expect(reloaded!.uidAliases, {'100000001': '主帳號'});
  });

  testWidgets('別名空字串 → 移除', (tester) async {
    final storage = GachaStorage(tempDir);
    await tester.runAsync(() async {
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 5, 9),
          banners: const {
            '301': [],
            '302': [],
            '500': [],
            '200': [],
            '100': [],
          },
        ),
      );
    });

    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: storage,
        prefs: {'pref.uidAliases': '{"100000001":"舊名"}'},
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = find.byType(TextField).first;
    await tester.enterText(field, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final reloaded = await tester.runAsync(() => SettingsStorage.load());
    expect(reloaded!.uidAliases, isEmpty);
  });
}
