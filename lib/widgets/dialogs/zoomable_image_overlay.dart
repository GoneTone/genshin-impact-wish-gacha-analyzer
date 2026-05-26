import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 開啟全螢幕 lightbox 顯示 [imageFile]，可拖曳平移、滾輪 / 雙擊縮放、ESC / 點背景 / X 關閉。
Future<void> showZoomableImageOverlay(
  BuildContext context, {
  required File imageFile,
}) {
  Logger('gacha.hoyowiki.zoom').info('overlay open file=${imageFile.path}');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    // barrierDismissible: true 讓 Flutter Navigator 內建 ESC 關閉生效。
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ZoomableImageOverlay(imageFile: imageFile),
    ),
  );
}

/// 全螢幕 lightbox 圖片檢視器；獨立可重用，不耦合 caller。
class ZoomableImageOverlay extends StatefulWidget {
  /// 建立 [ZoomableImageOverlay]。
  const ZoomableImageOverlay({super.key, required this.imageFile});

  /// 要顯示的本地圖檔。
  final File imageFile;

  @override
  State<ZoomableImageOverlay> createState() => _ZoomableImageOverlayState();
}

/// [ZoomableImageOverlay] 的 state — 後續 task 會接入 `_ctrl` / wheel / double-tap。
class _ZoomableImageOverlayState extends State<ZoomableImageOverlay> {
  /// 關 overlay 並 log 來源。[reason] 走 `backdrop | button` 二選一；ESC 由 Navigator barrierDismissible 處理，不經此路徑。
  void _close(String reason) {
    Logger('gacha.hoyowiki.zoom').info('overlay close reason=$reason');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Stack(
      children: [
        // backdrop — 滿屏，點任一處（落在 InteractiveViewer 以外）即關閉。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _close('backdrop'),
          ),
        ),
        // 中央圖片區 — 留 48px padding 給 backdrop tap 區。
        Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Image.file(
              widget.imageFile,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) {
                Logger('gacha.hoyowiki.zoom').warning(
                  'image errorBuilder file=${widget.imageFile.path}',
                  e,
                  st,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        // X 按鈕 — 半透明黑底圓鈕，永遠最上層。
        Positioned(
          top: 16,
          right: 16,
          child: Material(
            color: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: l.actionCloseImagePreview,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => _close('button'),
            ),
          ),
        ),
      ],
    );
  }
}
