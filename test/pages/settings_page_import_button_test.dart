import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cancellable_http_client.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import '../helpers/no_game_dir.dart';
import '../helpers/xlsx_fixture.dart';
import '../helpers/wait_until.dart';

/// 空 [GachaCapture] 替身，避免測試啟動真實 MITM session。
class _NullCapture implements GachaCapture {
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}

/// 啟動測試用 [ProviderContainer]，覆寫 SettingsPage 所需依賴並完成 bootstrap。
Future<ProviderContainer> _setupContainer({
  required GachaStorage storage,
  required Directory tempDir,
  http.Client? httpClient,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (httpClient != null) httpClientProvider.overrideWithValue(httpClient),
      gachaStorageProvider.overrideWithValue(storage),
      noGameDirOverride,
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
  await container.read(gachaRepositoryProvider.notifier).waitForBootstrap();
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return container;
}

/// 將 [SettingsPage] 包進 [MaterialApp] 與 [UncontrolledProviderScope]，
/// 套用測試所需的 i18n delegates 與主題。
Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'Hant'),
    theme: buildDarkTheme(),
    home: const Scaffold(body: SettingsPage()),
  ),
);

/// 一筆只有 `item_id`、缺名稱的 UIGF v3 檔，匯入時一定要向 resolver 補名稱。
final _unresolvableUigf = jsonEncode({
  'info': {'uid': '100000001', 'uigf_version': 'v3.0'},
  'list': [
    {
      'gacha_type': '200',
      'item_id': '11101',
      'count': '1',
      'time': '2025-01-01 10:00:00',
      'item_type': '武器',
      'rank_type': '3',
      'id': '1735696800000000001',
      'uigf_gacha_type': '200',
    },
  ],
});

/// 最近一次選檔對話框收到的標題。
String? openTitle;

void main() {
  late Directory tempDir;

  setUp(() async {
    openTitle = null;
    tempDir = await Directory.systemTemp.createTemp('settings_import_btn_');
  });

  tearDown(() async {
    resetFileAccessSeams();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('progress 為 null：匯入按鈕 enabled（無紀錄也可按）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = find.widgetWithText(OutlinedButton, '匯入資料');
    expect(btn, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(btn).onPressed,
      isNotNull,
      reason: '匯入按鈕在 progress 為 null 時應 enabled（含無紀錄）',
    );
  });

  testWidgets('progress 非 null：匯入按鈕 disabled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);

    // 用 debug API 將 progress 設為 Preparing
    container
        .read(gachaRepositoryProvider.notifier)
        .debugSetProgress(const Preparing());

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = find.widgetWithText(OutlinedButton, '匯入資料');
    expect(btn, findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(btn).onPressed,
      isNull,
      reason: 'progress 非 null 時匯入按鈕應 disabled',
    );
  });

  /// 以 [bytes]（null 代表取消）當選檔內容，點擊 [buttonText] 並等流程跑完。
  Future<AppLocalizations> tapImportWith(
    WidgetTester tester,
    Uint8List? bytes,
    String buttonText,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
      );
    });
    addTearDown(container.dispose);
    fileOpenDialog = (_, title) async {
      openTitle = title;
      return bytes;
    };

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    final btn = find.widgetWithText(OutlinedButton, buttonText);
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(SettingsPage)))!;
  }

  testWidgets('import dialog gets the localized open title', (tester) async {
    final l = await tapImportWith(tester, Uint8List.fromList([0xff]), '匯入資料');
    expect(openTitle, l.dialogOpenTitle);
  });

  testWidgets(
    'importing a backup with invalid UTF-8 shows the unreadable message',
    (tester) async {
      final l = await tapImportWith(
        tester,
        Uint8List.fromList([0xff, 0xfe, 0xfd]),
        '匯入資料',
      );

      expect(
        find.text(l.settingsImportFailed(l.importReasonUnreadable)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'importing a corrupt backup parsed in the background shows the invalid '
    'format message and logs the failure on the main isolate',
    (tester) async {
      final messages = <String>[];
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'accounts.io')
          .listen((r) => messages.add(r.message));
      addTearDown(sub.cancel);

      final l = await tapImportWith(
        tester,
        Uint8List.fromList(utf8.encode('{ not json')),
        '匯入資料',
      );
      final failed = find.text(
        l.settingsImportFailed(l.importReasonInvalidFormat),
      );
      await pumpUntil(tester, () => failed.evaluate().isNotEmpty);

      expect(failed, findsOneWidget);
      expect(messages, contains(startsWith('import failed')));
    },
  );

  testWidgets(
    'importing a foreign backup shows the foreign app message and logs it',
    (tester) async {
      final messages = <String>[];
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'accounts.io')
          .listen((r) => messages.add(r.message));
      addTearDown(sub.cancel);

      final l = await tapImportWith(
        tester,
        Uint8List.fromList(
          utf8.encode('{"app":"other","schema_version":1,"accounts":[]}'),
        ),
        '匯入資料',
      );
      final failed = find.text(
        l.settingsImportFailed(l.importReasonForeignApp),
      );
      await pumpUntil(tester, () => failed.evaluate().isNotEmpty);

      expect(failed, findsOneWidget);
      expect(messages, contains('import failed: foreign bundle'));
    },
  );

  testWidgets('cancelling the import file picker shows nothing', (
    tester,
  ) async {
    final l = await tapImportWith(tester, null, '匯入資料');

    expect(openTitle, l.dialogOpenTitle);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  for (final busy in [false, true]) {
    testWidgets('other platform import button enabled: ${!busy}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = await _setupContainer(
          storage: GachaStorage(tempDir),
          tempDir: tempDir,
        );
      });
      addTearDown(container.dispose);
      if (busy) {
        container
            .read(gachaRepositoryProvider.notifier)
            .debugSetProgress(const Preparing());
      }

      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      final btn = find.widgetWithText(OutlinedButton, '從其他平台匯入');
      expect(btn, findsOneWidget);
      expect(tester.widget<OutlinedButton>(btn).onPressed == null, busy);
    });
  }

  /// 點「從其他平台匯入」、選 [platform]，選檔回傳 [bytes]；[httpClient] 給補資料用。
  Future<(ProviderContainer, List<String>?)> importFromPlatform(
    WidgetTester tester,
    String platform,
    Uint8List bytes, {
    http.Client? httpClient,
  }) async {
    SharedPreferences.setMockInitialValues({});
    late ProviderContainer container;
    await tester.runAsync(() async {
      container = await _setupContainer(
        storage: GachaStorage(tempDir),
        tempDir: tempDir,
        httpClient: httpClient,
      );
    });
    addTearDown(container.dispose);
    List<String>? extensions;
    fileOpenDialog = (ext, title) async {
      extensions = ext;
      openTitle = title;
      return bytes;
    };

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    final btn = find.widgetWithText(OutlinedButton, '從其他平台匯入');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.text(platform));
    await tester.pump();
    await tester.pump();
    return (container, extensions);
  }

  testWidgets('a foreign file picked for UIGF shows the not platform message', (
    tester,
  ) async {
    final (_, extensions) = await importFromPlatform(
      tester,
      'UIGF',
      Uint8List.fromList(utf8.encode('{"app":"other"}')),
    );
    await tester.pumpAndSettle();

    expect(extensions, ['json']);
    expect(find.text('匯入失敗：此檔案不是有效的 UIGF 匯出檔'), findsOneWidget);
  });

  testWidgets(
    'a UIGF file whose names cannot be resolved shows the resolving dialog '
    'then the unresolved message',
    (tester) async {
      final gate = Completer<http.Response>();
      await importFromPlatform(
        tester,
        'UIGF',
        Uint8List.fromList(utf8.encode(_unresolvableUigf)),
        httpClient: MockClient((_) => gate.future),
      );

      // 進度條一直在動，不能 pumpAndSettle；等平台選單關閉動畫跑完。
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('正在補齊物品資料...'), findsOneWidget);
      expect(find.byType(AppDialogCloseButton), findsNothing);

      gate.complete(http.Response('', 500));
      await tester.pumpAndSettle();

      expect(find.text('正在補齊物品資料...'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('匯入失敗：無法補齊物品資料（11101），請確認網路連線後再試'), findsOneWidget);
    },
  );

  testWidgets(
    'a UIGF file that barely matches local official records warns in the '
    'confirm dialog',
    (tester) async {
      await tester.runAsync(
        () => GachaStorage(tempDir).save(
          BannerStorage(
            uid: '100000001',
            lastUpdated: DateTime.utc(2025, 2, 1),
            banners: {
              '200': [
                for (var d = 12; d >= 1; d--)
                  GachaRecord(
                    id: '17356968000000000${d.toString().padLeft(2, '0')}',
                    uid: '100000001',
                    gachaType: '200',
                    name: '冷刃',
                    itemType: '武器',
                    rankType: 3,
                    time: DateTime(2025, 1, d, 10),
                    lang: 'zh-tw',
                  ),
              ],
            },
          ),
        ),
      );
      final file = jsonEncode({
        'info': {'uid': '100000001', 'lang': 'zh-tw', 'uigf_version': 'v3.0'},
        'list': [
          for (var d = 1; d <= 12; d++)
            {
              'gacha_type': '200',
              'count': '1',
              'time': '2025-01-${d.toString().padLeft(2, '0')} 11:00:00',
              'name': '冷刃',
              'item_type': '武器',
              'rank_type': '3',
              'id': '',
              'uigf_gacha_type': '200',
            },
        ],
      });
      await importFromPlatform(
        tester,
        'UIGF',
        Uint8List.fromList(utf8.encode(file)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '繼續'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          '⚠ 100000001：2025-01-01～2025-01-12 這段期間兩邊都有記錄，但 11 次抽卡'
          '沒有一次對得上本機的官方記錄。可能選錯了帳號，或檔案的時區不同。',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '仍要匯入'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a paimon.moe file goes to the chosen local account and merges into it',
    (tester) async {
      await tester.runAsync(
        () => GachaStorage(tempDir).save(
          BannerStorage(
            uid: '100000001',
            lastUpdated: DateTime.utc(2025, 2, 1),
            banners: {
              '200': [
                GachaRecord(
                  id: '1735696800000000001',
                  uid: '100000001',
                  gachaType: '200',
                  name: '冷刃',
                  itemType: '武器',
                  rankType: 3,
                  time: DateTime(2025, 1, 1, 10),
                  lang: 'zh-tw',
                ),
              ],
            },
          ),
        ),
      );
      final (_, extensions) = await importFromPlatform(
        tester,
        'paimon.moe',
        buildPaimonXlsx({
          'Standard': [
            paimonRow('Weapon', 'Cool Steel', '2025-01-02 10:00:00', 3),
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(extensions, ['xlsx']);

      expect(find.text('匯入到哪個帳號？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '繼續'));
      await tester.pumpAndSettle();

      expect(find.text('選擇要匯入的帳號'), findsOneWidget);
      final inDialog = find.byType(Dialog);
      expect(
        find.descendant(of: inDialog, matching: find.text('100000001')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inDialog, matching: find.text('合併')),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, '繼續'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '匯入'), findsOneWidget);
      expect(find.textContaining('⚠'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a dialog opened above the resolving dialog stays after resolving ends',
    (tester) async {
      final gate = Completer<http.Response>();
      await importFromPlatform(
        tester,
        'UIGF',
        Uint8List.fromList(utf8.encode(_unresolvableUigf)),
        httpClient: MockClient((_) => gate.future),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('正在補齊物品資料...'), findsOneWidget);

      // 模擬補資料期間自動跳出的對話框（例如新版本提示）。
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(SettingsPage)),
          builder: (_) => const AlertDialog(content: Text('new version')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      gate.complete(http.Response('', 500));
      await tester.pumpAndSettle();

      expect(find.text('正在補齊物品資料...'), findsNothing);
      expect(find.text('new version'), findsOneWidget);
    },
  );

  for (final (name, file, message) in [
    (
      'a newer UIGF version',
      '{"info":{"uigf_version":"v5.0"},"hk4e":[]}',
      '匯入失敗：這個檔案的 UIGF 版本（v5.0）較新，目前還不支援。請更新 App，或在原工具改用 v4 匯出',
    ),
    (
      'an unknown gacha type',
      jsonEncode({
        'info': {'uid': '100000001', 'lang': 'zh-tw', 'uigf_version': 'v3.0'},
        'list': [
          {
            'gacha_type': '999',
            'count': '1',
            'time': '2025-01-01 10:00:00',
            'name': '冷刃',
            'item_type': '武器',
            'rank_type': '3',
            'id': '1735696800000000001',
            'uigf_gacha_type': '999',
          },
        ],
      }),
      '匯入失敗：檔案裡有不支援的卡池類型（999）',
    ),
    ('invalid JSON', '{ not json', '匯入失敗：檔案格式不正確或已損毀'),
  ]) {
    testWidgets('UIGF import with $name shows its message', (tester) async {
      await importFromPlatform(
        tester,
        'UIGF',
        Uint8List.fromList(utf8.encode(file)),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });
  }
}
