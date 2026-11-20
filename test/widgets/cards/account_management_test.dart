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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import '../../helpers/no_game_dir.dart';

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
      noGameDirOverride,
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
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
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

    // 用 ReorderableListView 的內部 onReorderItem 直接觸發 — 比 tester.drag 穩定
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // onReorderItem 的 newIndex 已是移除 oldIndex 後的目標位置：把第 0 個
    // (100000001) 移到第 1 個之後 → 傳 1（非舊 onReorder 的 2）。
    list.onReorderItem!(0, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final reloaded = await tester.runAsync(() => SettingsStorage.load());
    expect(reloaded!.uidOrder, ['100000002', '100000001']);
  });

  group('AccountManagement: 緊湊列與 ⋮ 選單', () {
    /// 存入兩個帳號（100000001 較新＝使用中）並 pump，回傳 container。
    Future<ProviderContainer> pumpTwo(
      WidgetTester tester, {
      Map<String, dynamic> prefs = const {},
    }) async {
      final storage = GachaStorage(tempDir);
      await tester.runAsync(() async {
        for (final e in {
          '100000001': DateTime.utc(2026, 5, 9),
          '100000002': DateTime.utc(2026, 1, 1),
        }.entries) {
          await storage.save(
            BannerStorage(
              uid: e.key,
              lastUpdated: e.value,
              banners: const {'301': []},
            ),
          );
        }
      });
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await _setupContainer(storage: storage, prefs: prefs);
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return container;
    }

    /// 開啟第 [row] 列的 ⋮ 選單。
    Future<void> openMenu(WidgetTester tester, int row) async {
      await tester.tap(find.byIcon(Icons.more_vert).at(row));
      await tester.pumpAndSettle();
    }

    testWidgets('列內沒有 TextField；無別名顯示提示、有別名顯示別名', (tester) async {
      await pumpTwo(tester, prefs: {'pref.uidAliases': '{"100000001":"主帳號"}'});
      expect(find.byType(TextField), findsNothing);
      expect(find.text('主帳號'), findsOneWidget);
      expect(find.text('未設定別名'), findsOneWidget);
    });

    testWidgets('使用中標籤只出現在 active 列', (tester) async {
      await pumpTwo(tester);
      expect(find.text('活躍'), findsOneWidget);
    });

    testWidgets('選單：active 列沒有「設為活躍」，非 active 列有', (tester) async {
      await pumpTwo(tester);
      await openMenu(tester, 0);
      expect(find.text('編輯別名'), findsOneWidget);
      expect(find.text('設為活躍'), findsNothing);
      expect(find.text('移除'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      await openMenu(tester, 1);
      expect(find.text('設為活躍'), findsOneWidget);
    });

    testWidgets('設為活躍 → activeUid 改變', (tester) async {
      final c = await pumpTwo(tester);
      await openMenu(tester, 1);
      await tester.tap(find.text('設為活躍'));
      await tester.pumpAndSettle();
      expect(c.read(gachaRepositoryProvider).activeUid, '100000002');
    });

    testWidgets('編輯別名：預填、儲存、Enter、清空、取消', (tester) async {
      final c = await pumpTwo(
        tester,
        prefs: {'pref.uidAliases': '{"100000001":"舊名"}'},
      );
      Map<String, String> aliases() => c.read(settingsProvider).uidAliases;

      await openMenu(tester, 0);
      await tester.tap(find.text('編輯別名'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '舊名'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Main');
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(aliases()['100000001'], 'Main');

      await openMenu(tester, 0);
      await tester.tap(find.text('編輯別名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Enter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(aliases()['100000001'], 'Enter');

      await openMenu(tester, 0);
      await tester.tap(find.text('編輯別名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'X');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(aliases()['100000001'], 'Enter');

      await openMenu(tester, 0);
      await tester.tap(find.text('編輯別名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();
      expect(aliases(), isEmpty);
    });

    testWidgets('移除帳號 → 出現打字確認對話框', (tester) async {
      await pumpTwo(tester);
      await openMenu(tester, 0);
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('remove-account dialog: the close button cancels', (
      tester,
    ) async {
      final c = await pumpTwo(tester);
      await openMenu(tester, 0);
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppDialogCloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(c.read(gachaRepositoryProvider).knownUids, hasLength(2));
    });
  });

  for (final locale in const [Locale('en'), Locale('ja'), Locale('fr')]) {
    testWidgets('360dp 寬、1.3 倍字級（${locale.languageCode}）：列、選單、別名對話框不溢出', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = GachaStorage(tempDir);
      await tester.runAsync(() async {
        for (final e in {
          '100000001': DateTime.utc(2026, 5, 9),
          '100000002': DateTime.utc(2026, 1, 1),
        }.entries) {
          await storage.save(
            BannerStorage(
              uid: e.key,
              lastUpdated: e.value,
              banners: const {'301': []},
            ),
          );
        }
      });
      final longAlias = 'A' * 45;
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await _setupContainer(
          storage: storage,
          prefs: {'pref.uidAliases': '{"100000002":"$longAlias"}'},
        );
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            theme: buildDarkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const Scaffold(body: AccountManagement()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuItem).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  group('AccountManagement: maskUidInUi', () {
    /// 建立含單一 UID 的 storage 並 pump AccountManagement，回傳預熱完成的 container。
    Future<ProviderContainer> pumpWithUid(
      WidgetTester tester, {
      required String uid,
      required bool maskUidInUi,
    }) async {
      final storage = GachaStorage(tempDir);
      await tester.runAsync(() async {
        await storage.save(
          BannerStorage(
            uid: uid,
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
          prefs: {'pref.maskUidInUi': maskUidInUi},
        );
      });
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return container;
    }

    testWidgets('maskUidInUi=false 顯示完整 UID', (tester) async {
      await pumpWithUid(tester, uid: '123456789', maskUidInUi: false);
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('123••••••'), findsNothing);
    });

    testWidgets('maskUidInUi=true 顯示遮蔽 UID', (tester) async {
      await pumpWithUid(tester, uid: '123456789', maskUidInUi: true);
      expect(find.text('123••••••'), findsOneWidget);
      expect(find.text('123456789'), findsNothing);
    });

    testWidgets('刪除確認 dialog 仍顯示完整 UID（隱私模式下）', (tester) async {
      await pumpWithUid(tester, uid: '123456789', maskUidInUi: true);
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      // confirm dialog 透過 i18n confirmClearActiveBody({uid}) 把完整 UID 嵌入訊息，
      // 即使介面隱私模式啟用也要顯示完整碼，避免使用者誤刪錯帳號。
      expect(find.textContaining('123456789'), findsWidgets);
    });
  });

  testWidgets('account drag handle is at least 48dp on phones', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = GachaStorage(tempDir);
    await tester.runAsync(() async {
      await storage.save(
        BannerStorage(
          uid: '100000001',
          lastUpdated: DateTime.utc(2026, 1, 1),
          banners: const {'301': []},
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
    final handle = tester.getSize(
      find.byType(ReorderableDragStartListener).first,
    );
    expect(handle.width, greaterThanOrEqualTo(48));
    expect(handle.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
