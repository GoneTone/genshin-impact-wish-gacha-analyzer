import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

/// 記錄目前開著幾個 dialog（[PopupRoute]）的 observer。
class _DialogCounter extends NavigatorObserver {
  /// 目前開著的 dialog 數。
  int open = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) open++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) open--;
  }

  // 進度視窗以 removeRoute 關閉（只移除自己的 route），走的是 didRemove。
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) open--;
  }
}

/// 以真實 event loop 推進非同步工作（icon 解碼、離屏渲染），直到 [done] 成立。
Future<void> _pumpUntil(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
  expect(done(), isTrue);
}

void main() {
  late Directory tempDir;
  late _DialogCounter dialogs;
  late AppLocalizations l;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('share_progress_test_');
    dialogs = _DialogCounter();
    l = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  tearDown(() {
    shareImagePreloadOverride = null;
    resetFileAccessSeams();
    tempDir.deleteSync(recursive: true);
  });

  /// 掛上觸發 [generateAndShareImage] 的按鈕，開啟選項對話框後按「儲存圖片」。
  Future<void> openAndSave(WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          isAndroidProvider.overrideWithValue(false),
          hoyowikiIndexStorageProvider.overrideWithValue(
            HoYoWikiIndexStorage(tempDir),
          ),
          hoyowikiCacheDirProvider.overrideWithValue(tempDir),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          navigatorObservers: [dialogs],
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => generateAndShareImage(
                context: ctx,
                l: AppLocalizations.of(ctx)!,
                suggestedName: 'card.png',
                recordsForPreload: const <GachaRecord>[],
                buildCard: (icon, options) => const SizedBox(height: 10),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text(l.shareImageActionSave));
    await t.pump();
  }

  testWidgets('progress dialog shows while images preload', (t) async {
    final preload = Completer<Map<String, ui.Image>>();
    var preloading = false;
    shareImagePreloadOverride = (_) {
      preloading = true;
      return preload.future;
    };
    await openAndSave(t);
    await _pumpUntil(t, () => preloading);

    expect(find.text(l.shareImageGenerating), findsOneWidget);

    // 收尾：讓流程以失敗結束，避免留下未完成的 future 與無限動畫。
    preload.completeError(StateError('done'));
    await _pumpUntil(
      t,
      () => find.text(l.shareImageFailed).evaluate().isNotEmpty,
    );
  });

  testWidgets(
    'progress dialog closes and reports failure when preloading throws',
    (t) async {
      shareImagePreloadOverride = (_) async => throw StateError('boom');
      await openAndSave(t);
      await _pumpUntil(
        t,
        () => find.text(l.shareImageFailed).evaluate().isNotEmpty,
      );
      await t.pumpAndSettle();

      expect(find.text(l.shareImageGenerating), findsNothing);
      expect(find.text(l.shareImageFailed), findsOneWidget);
    },
  );

  testWidgets('progress dialog is gone before the save dialog opens', (
    t,
  ) async {
    int? openAtPreload;
    shareImagePreloadOverride = (_) async {
      openAtPreload = dialogs.open;
      return <String, ui.Image>{};
    };
    int? openAtSave;
    fileSaveDialog = (b, n, e, m, title) async {
      openAtSave = dialogs.open;
      return null;
    };
    await openAndSave(t);
    await _pumpUntil(t, () => openAtSave != null);
    await t.pumpAndSettle();

    // 預載時唯一開著的是進度視窗（選項對話框已關），確保 0 不是因為從沒開過。
    expect(openAtPreload, 1);
    expect(openAtSave, 0);
    expect(find.text(l.shareImageGenerating), findsNothing);
  });
}
