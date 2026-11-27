import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

/// 測試用的假 PNG bytes。
final _png = Uint8List.fromList([1, 2, 3, 4]);

/// 開一個按鈕執行 [deliverShareImage]，回傳 zh 在地化字串。
Future<AppLocalizations> _run(WidgetTester t, ShareImageAction action) async {
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => deliverShareImage(
            context: ctx,
            l: AppLocalizations.of(ctx)!,
            action: action,
            png: _png,
            suggestedName: 'card.png',
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  return AppLocalizations.delegate.load(const Locale('zh'));
}

void main() {
  tearDown(resetFileAccessSeams);

  testWidgets('Windows 存檔成功 → 顯示完整路徑與開啟資料夾', (t) async {
    fileSaveDialog = (b, n, e, m, title) async => r'C:\out\card.png';
    final l = await _run(t, ShareImageAction.save);

    expect(find.text(l.shareImageSaved(r'C:\out\card.png')), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Android 存檔成功 → 顯示檔名、無開啟資料夾', (t) async {
    fileSaveDialog = (b, n, e, m, title) async =>
        '/document/primary:Download/card.png';
    final l = await _run(t, ShareImageAction.save);

    expect(find.text(l.shareImageSaved('card.png')), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('取消存檔 → 不彈任何視窗', (t) async {
    fileSaveDialog = (b, n, e, m, title) async => null;
    await _run(t, ShareImageAction.save);

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('分享 → 以 .png 檔名送出 png，成功時不顯示視窗', (t) async {
    String? name;
    String? mime;
    fileSharer = (b, n, m) async {
      name = n;
      mime = m;
    };
    await _run(t, ShareImageAction.share);

    expect(name, 'card.png');
    expect(mime, 'image/png');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('分享失敗 → 顯示 shareFailed', (t) async {
    fileSharer = (b, n, m) async => throw Exception('boom');
    final l = await _run(t, ShareImageAction.share);

    expect(find.text(l.shareFailed), findsOneWidget);
  });

  testWidgets('複製成功 → 顯示 shareImageCopiedOnly', (t) async {
    imageClipboardWriter = (b, {required isGif, filePath}) async => true;
    final l = await _run(t, ShareImageAction.copy);

    expect(find.text(l.shareImageCopiedOnly), findsOneWidget);
  });

  testWidgets('複製失敗 → 顯示 shareImageCopyFailed', (t) async {
    imageClipboardWriter = (b, {required isGif, filePath}) async => false;
    final l = await _run(t, ShareImageAction.copy);

    expect(find.text(l.shareImageCopyFailed), findsOneWidget);
  });

  testWidgets('複製丟例外 → 顯示 shareImageCopyFailed', (t) async {
    imageClipboardWriter = (b, {required isGif, filePath}) async =>
        throw StateError('boom');
    final l = await _run(t, ShareImageAction.copy);

    expect(find.text(l.shareImageCopyFailed), findsOneWidget);
  });
}
