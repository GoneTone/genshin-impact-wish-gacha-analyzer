// lib/widgets/share/share_image_helper.dart
// 通用分享圖生成流程：dialog → render → export → snackbar+reveal。
// overview / banner 兩頁共用，避免骨架重複（CLAUDE.md 嚴禁重複造輪子）。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_result_snackbar.dart';

final _log = Logger('share.image');

/// 跑完整分享圖流程。[buildCard] 收已載入的 icon、選項，回傳 ShareCard。
/// [logicalHeight] 該卡片固定畫布高度；[suggestedName] 完整建議檔名（含時間戳）。
Future<void> generateAndShareImage({
  required BuildContext context,
  required AppLocalizations l,
  required double logicalHeight,
  required String suggestedName,
  required Widget Function(ui.Image icon, ShareImageOptions options) buildCard,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final brightness = Theme.of(context).brightness;
  final options = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (options == null) return;
  if (!context.mounted) return;

  final icon = await loadAppIconImage();
  try {
    final card = MediaQuery(
      data: const MediaQueryData(),
      child: Theme(
        data: options.brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        child: Material(
          type: MaterialType.transparency,
          child: buildCard(icon, options),
        ),
      ),
    );
    final png = await renderWidgetToPng(
      Directionality(textDirection: TextDirection.ltr, child: card),
      logicalSize: Size(kShareCardWidth, logicalHeight),
    );
    final result = await exportShareImage(png, suggestedName: suggestedName);
    showShareResultSnackBar(messenger, l, result);
  } catch (e, st) {
    _log.warning('share image flow failed', e, st);
    messenger.showSnackBar(SnackBar(content: Text(l.shareImageFailed)));
  } finally {
    icon.dispose();
  }
}
