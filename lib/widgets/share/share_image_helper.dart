import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_access.dart';
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
    child: Localizations(
      locale: locale,
      delegates: const [
        AppLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      // DefaultWidgetsLocalizations 固定由左往右，Localizations 會以它再包一層
      // Directionality，所以書寫方向要在這層底下依語言重設。
      child: Directionality(
        textDirection: Bidi.isRtlLanguage(locale.languageCode)
            ? TextDirection.rtl
            : TextDirection.ltr,
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

/// 依 [action] 把 [png] 存檔、分享或複製，並以結果視窗回報。
///
/// 取消存檔與分享成功不彈視窗；Android 存檔訊息只顯示檔名、不給開啟資料夾。
/// 存檔寫入失敗由 [saveBytes] rethrow，交由呼叫端（[generateAndShareImage]）處理。
@visibleForTesting
Future<void> deliverShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required ShareImageAction action,
  required Uint8List png,
  required String suggestedName,
}) async {
  switch (action) {
    case ShareImageAction.save:
      final saved = await saveBytes(
        png,
        suggestedName: suggestedName,
        extension: 'png',
        mimeType: 'image/png',
        dialogTitle: l.dialogSaveAsTitle,
      );
      if (!context.mounted || saved == null) return;
      await showExportResultDialog(
        context,
        success: true,
        message: l.shareImageSaved(saved.path ?? saved.displayName),
        revealPath: saved.path,
      );
    case ShareImageAction.share:
      final ok = await shareBytes(
        png,
        fileName: suggestedName,
        mimeType: 'image/png',
      );
      if (!context.mounted || ok) return;
      await showExportResultDialog(
        context,
        success: false,
        message: l.shareFailed,
      );
    case ShareImageAction.copy:
      final ok = await copyImageToClipboard(png);
      if (!context.mounted) return;
      await showExportResultDialog(
        context,
        success: ok,
        message: ok ? l.shareImageCopiedOnly : l.shareImageCopyFailed,
      );
  }
}

/// 取代 [generateAndShareImage] 預載 hoyowiki icon 那一步的測試 seam；null 表示
/// 使用 [preloadHoYoWikiImages]。
@visibleForTesting
Future<Map<String, ui.Image>> Function(Iterable<GachaRecord> records)?
shareImagePreloadOverride;

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

  // 預載 + 離屏渲染期間顯示不可關閉的「生成中」進度視窗；closeProgress 可重複
  // 呼叫，渲染一完成（早於存檔系統視窗／複製結果通知）即關閉，catch 與 finally
  // 再各呼叫一次當保險，確保任何路徑都不會卡住進度視窗。
  var progressOpen = false;

  /// 進度視窗仍開著且 context 還掛著時關閉它。
  void closeProgress() {
    if (progressOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
  }

  showShareProgressDialog(context);
  progressOpen = true;

  ui.Image? icon;
  Map<String, ui.Image>? preloaded;
  try {
    icon = await loadAppIconImage();
    preloaded =
        await (shareImagePreloadOverride?.call(recordsForPreload) ??
            preloadHoYoWikiImages(
              index: hoyowikiIndex,
              cacheDir: cacheDir,
              records: recordsForPreload,
            ));
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
    closeProgress();
    if (!context.mounted) return;
    await deliverShareImage(
      context: context,
      l: l,
      action: choice.action,
      png: png,
      suggestedName: suggestedName,
    );
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    closeProgress();
    if (!context.mounted) return;
    await showExportResultDialog(
      context,
      success: false,
      message: l.shareImageFailed,
    );
  } finally {
    closeProgress();
    icon?.dispose();
    if (preloaded != null) disposePreloadedHoYoWikiImages(preloaded);
  }
}
