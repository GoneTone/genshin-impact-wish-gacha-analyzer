import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';

/// 分享圖流程的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 把 [ShareExportResult] 攤平成 dialog 需要的訊息與 reveal 路徑。
/// copiedOnly 只進剪貼簿、無檔案，故 revealPath 為 null。
({String message, String? revealPath}) _shareResultToDialog(
  AppLocalizations l,
  ShareExportResult r,
) {
  switch (r.status) {
    case ShareExportStatus.savedAndCopied:
      return (
        message: l.shareImageSavedAndCopied(r.path ?? ''),
        revealPath: r.path,
      );
    case ShareExportStatus.savedOnly:
      return (message: l.shareImageSavedOnly(r.path ?? ''), revealPath: r.path);
    case ShareExportStatus.copiedOnly:
      return (message: l.shareImageCopiedOnly, revealPath: null);
  }
}

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
  final options = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (options == null) return;
  if (!context.mounted) return;

  final container = ProviderScope.containerOf(context);
  final hoyowikiIndex = container.read(hoyowikiIndexProvider);
  final cacheDir = container.read(hoyowikiCacheDirProvider);
  final icon = await loadAppIconImage();
  final preloaded = await preloadHoyoWikiImages(
    index: hoyowikiIndex,
    cacheDir: cacheDir,
    records: recordsForPreload,
  );
  try {
    final png = await renderWidgetToPng(
      buildShareRenderTree(
        card: PreloadedHoyoWikiImages(
          images: preloaded,
          child: buildCard(icon, options),
        ),
        brightness: options.brightness,
        locale: locale,
        container: container,
      ),
      width: kShareCardWidth,
    );
    final result = await exportShareImage(png, suggestedName: suggestedName);
    if (!context.mounted) return;
    final m = _shareResultToDialog(l, result);
    await showExportResultDialog(
      context,
      success: true,
      message: m.message,
      revealPath: m.revealPath,
    );
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    if (!context.mounted) return;
    await showExportResultDialog(
      context,
      success: false,
      message: l.shareImageFailed,
    );
  } finally {
    icon.dispose();
    disposePreloadedHoyoWikiImages(preloaded);
  }
}
