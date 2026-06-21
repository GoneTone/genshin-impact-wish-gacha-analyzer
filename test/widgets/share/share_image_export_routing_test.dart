import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_image_helper.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetImageClipboardSaveSeams);

  Widget host(ShareImageAction action) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => exportRenderedShareImage(
              context: ctx,
              l: AppLocalizations.of(ctx)!,
              action: action,
              png: png,
              suggestedName: 'a.png',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );

  testWidgets('copy 成功 → 跳已複製到剪貼簿', (t) async {
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => true;
    await t.pumpWidget(host(ShareImageAction.copy));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageCopiedOnly), findsOneWidget);
  });

  testWidgets('copy 失敗 → 跳複製失敗', (t) async {
    imageClipboardWriter = (bytes, {required isGif, filePath}) async => false;
    await t.pumpWidget(host(ShareImageAction.copy));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageCopyFailed), findsOneWidget);
  });

  testWidgets('save 成功 → 跳已儲存且有開資料夾', (t) async {
    final tmp = '${Directory.systemTemp.path}/share_route_a.png';
    Uint8List? writtenBytes;
    imageSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    // testWidgets 不跑真實 IO event loop；用 seam 攔截寫檔，避免 pumpAndSettle
    // 無法 await 真實 File.writeAsBytes 導致 dialog 未在 frame 內出現。
    imageFileWriter = (path, bytes) async => writtenBytes = bytes;
    await t.pumpWidget(host(ShareImageAction.save));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.shareImageSaved(tmp)), findsOneWidget);
    expect(find.text(l.actionOpenFolder), findsOneWidget);
    expect(writtenBytes, png);
  });

  testWidgets('save 取消 → 不跳任何結果 dialog', (t) async {
    imageSaveLocationPicker = (name) async => null;
    await t.pumpWidget(host(ShareImageAction.save));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.exportDialogSuccessTitle), findsNothing);
    expect(find.text(l.exportDialogFailedTitle), findsNothing);
  });
}
