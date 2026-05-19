import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';

void main() {
  String? capturedExe;
  List<String>? capturedArgs;

  setUp(() {
    capturedExe = null;
    capturedArgs = null;
  });
  tearDown(resetFileRevealSeams);

  Future<void> pumpHost(
    WidgetTester t, {
    required bool success,
    required String message,
    String? revealPath,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showExportResultDialog(
                  ctx,
                  success: success,
                  message: message,
                  revealPath: revealPath,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('失敗：只有關閉鈕，無開啟資料夾', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await pumpHost(t, success: false, message: '匯出失敗：boom', revealPath: null);

    expect(find.text(l.exportDialogFailedTitle), findsOneWidget);
    expect(find.text('匯出失敗：boom'), findsOneWidget);
    expect(find.text(l.actionClose), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsNothing);
  });

  testWidgets('成功但無路徑（copiedOnly）：無開啟資料夾鈕', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await pumpHost(t, success: true, message: '已複製到剪貼簿', revealPath: null);

    expect(find.text(l.actionOpenFolder), findsNothing);
    expect(find.text(l.actionClose), findsOneWidget);
  });

  // revealInFileManager 包含真實 dart:io（File.exists + ProcessRunner），
  // 必須用 runAsync 讓 IO 在真實事件迴圈中完成，再回到 FakeAsync 做 UI 斷言。
  testWidgets('成功且有路徑：顯示訊息＋開啟資料夾＋關閉，不自動 reveal', (t) async {
    revealPlatform = () => RevealPlatform.windows;
    revealProcessRunner = (exe, args) async {
      capturedExe = exe;
      capturedArgs = args;
      return ProcessResult(0, 1, '', '');
    };

    // makeTempFile 是真實 IO，需在 runAsync 內執行
    final f = await t.runAsync(
      () => File(
        '${Directory.systemTemp.path}/__gwga_erd_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ).create(),
    );
    final l = await AppLocalizations.delegate.load(const Locale('zh'));

    try {
      await pumpHost(
        t,
        success: true,
        message: '已匯出至 ${f!.path}',
        revealPath: f.path,
      );

      expect(find.text('已匯出至 ${f.path}'), findsOneWidget);
      expect(find.text(l.exportDialogSuccessTitle), findsOneWidget);
      expect(find.text(l.actionOpenFolder), findsOneWidget);
      expect(find.text(l.actionClose), findsOneWidget);
      expect(capturedExe, isNull); // 不自動 reveal

      await t.tap(find.text(l.actionOpenFolder));
      // unawaited(revealInFileManager(...)) 是真實 IO；
      // 用 runAsync 短暫離開 FakeAsync，讓 IO future 完成後再 settle UI。
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();

      expect(capturedExe, 'explorer');
      expect(capturedArgs, ['/select,${f.path}']);
      expect(find.text(l.actionClose), findsNothing); // dialog 已關
    } finally {
      await t.runAsync(() async {
        if (await f!.exists()) await f.delete();
      });
    }
  });

  testWidgets('點關閉：dialog 消失且未觸發 reveal', (t) async {
    revealPlatform = () => RevealPlatform.windows;
    revealProcessRunner = (exe, args) async {
      capturedExe = exe;
      return ProcessResult(0, 1, '', '');
    };

    final f = await t.runAsync(
      () => File(
        '${Directory.systemTemp.path}/__gwga_erd_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ).create(),
    );
    final l = await AppLocalizations.delegate.load(const Locale('zh'));

    try {
      await pumpHost(
        t,
        success: true,
        message: '已匯出至 ${f!.path}',
        revealPath: f.path,
      );
      await t.tap(find.text(l.actionClose));
      await t.pumpAndSettle();

      expect(find.text(l.actionClose), findsNothing);
      expect(capturedExe, isNull);
    } finally {
      await t.runAsync(() async {
        if (await f!.exists()) await f.delete();
      });
    }
  });
}
