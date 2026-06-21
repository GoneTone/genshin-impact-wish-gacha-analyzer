import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_progress_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

/// 分享圖流程的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 建構離屏渲染用的 widget 樹（含 Localizations，使重用的 RarityPie/ItemTypePie
/// 內部 AppLocalizations.of(context) 能在同步 flush 內解析）。
///
/// 只放同步載入的 delegate：AppLocalizations.delegate 透過 SynchronousFuture
/// 載入，Default*Localizations 也都同步；離屏渲染只跑一次同步 pipeline flush，
/// 用 AppLocalizations.localizationsDelegates（含 Global*，可能 async）會來不及
/// 解析而導致畫面空白。
///
/// [container] 為 Riverpod ProviderContainer；離屏 pipeline 是獨立樹，需透過
/// [UncontrolledProviderScope] 顯式傳入，否則 tree 內 [ConsumerWidget]（如
/// [GachaItemIcon]）無法查到 providers。生產端從呼叫 Widget 的 ref 取得，
/// 測試端自行建立並注入。
Widget buildShareRenderTree({
  required Widget card,
  required Brightness brightness,
  required Locale locale,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Localizations(
        locale: locale,
        delegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Theme(
            data: brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
            child: Material(
              type: MaterialType.transparency,
              // Overlay 補齊 TimelineVertical 內 Tooltip 所需的 Overlay 祖先；
              // 離屏為 RenderView tight constraints，opaque entry 會填滿畫布。
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    opaque: true,
                    maintainState: true,
                    // 離屏渲染給 unbounded 高度約束以達高度自適應；此非定位
                    // entry 設 canSizeOverlay 後，Overlay 會以它（即 ShareCard）
                    // 的自然高決定自身高度（見 share_image_renderer.dart）。
                    canSizeOverlay: true,
                    builder: (_) => card,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 依 [action] 把已渲染的 [png] 複製或儲存，並顯示結果 dialog。
///
/// copy：成功與失敗皆跳結果 dialog（[shareImageCopiedOnly] / [shareImageCopyFailed]）。
/// save：成功跳結果 dialog（[shareImageSaved] 附開資料夾）；使用者取消選路徑則靜默；
/// 寫檔失敗由 [saveImagePng] rethrow，交由呼叫端（[generateAndShareImage]）處理。
Future<void> exportRenderedShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required ShareImageAction action,
  required Uint8List png,
  required String suggestedName,
}) async {
  switch (action) {
    case ShareImageAction.copy:
      final ok = await copyImagePngToClipboard(png);
      _log.info('share image copy clipboard=$ok bytes=${png.length}');
      if (!context.mounted) return;
      await showExportResultDialog(
        context,
        success: ok,
        message: ok ? l.shareImageCopiedOnly : l.shareImageCopyFailed,
      );
    case ShareImageAction.save:
      final path = await saveImagePng(png, suggestedName: suggestedName);
      if (path == null) {
        _log.info('share image save cancelled');
        return;
      }
      if (!context.mounted) return;
      await showExportResultDialog(
        context,
        success: true,
        message: l.shareImageSaved(path),
        revealPath: path,
      );
  }
}

/// 跑完整分享圖流程。[buildCard] 收已載入的 icon、選項，回傳 ShareCard。
/// 分享圖寬固定為 [kShareCardWidth]、高隨內容自適應（底部不留白、不裁切）；
/// [suggestedName] 完整建議檔名（含時間戳）。
/// [recordsForPreload] 用於 sync pipeline 前預解碼 hoyowiki icon。
/// overview 與 banner 兩頁共用，避免重複骨架。
Future<void> generateAndShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required String suggestedName,
  required Iterable<GachaRecord> recordsForPreload,
  required Widget Function(ui.Image icon, ShareImageOptions options) buildCard,
}) async {
  final brightness = Theme.of(context).brightness;
  final locale = Localizations.localeOf(context);
  final choice = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (choice == null) return;
  if (!context.mounted) return;

  final container = ProviderScope.containerOf(context);
  final hoyowikiIndex = container.read(hoyowikiIndexProvider);
  final cacheDir = container.read(hoyowikiCacheDirProvider);
  final icon = await loadAppIconImage();
  final preloaded = await preloadHoYoWikiImages(
    index: hoyowikiIndex,
    cacheDir: cacheDir,
    records: recordsForPreload,
  );

  if (!context.mounted) {
    icon.dispose();
    disposePreloadedHoYoWikiImages(preloaded);
    return;
  }
  // 進度 dialog 只覆蓋渲染這段；render 完成或失敗後即關閉，再進入複製／存檔，
  // 避免遮住系統存檔對話框。progressOpen 防止 catch 分支重複 pop。
  showShareProgressDialog(context);
  var progressOpen = true;
  try {
    final png = await renderWidgetToPng(
      buildShareRenderTree(
        card: PreloadedHoYoWikiImages(
          images: preloaded,
          child: buildCard(icon, choice.options),
        ),
        brightness: choice.options.brightness,
        locale: locale,
        container: container,
      ),
      width: kShareCardWidth,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
    if (!context.mounted) return;
    await exportRenderedShareImage(
      context: context,
      l: l,
      action: choice.action,
      png: png,
      suggestedName: suggestedName,
    );
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    if (progressOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    await showExportResultDialog(
      context,
      success: false,
      message: l.shareImageFailed,
    );
  } finally {
    icon.dispose();
    disposePreloadedHoYoWikiImages(preloaded);
  }
}
