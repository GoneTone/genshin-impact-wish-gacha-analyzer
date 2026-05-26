import 'dart:io';

import 'package:flutter/gestures.dart';
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

/// [ZoomableImageOverlay] 的 state — 管理 [_ctrl] 縮放矩陣與 close 路徑。
class _ZoomableImageOverlayState extends State<ZoomableImageOverlay> {
  /// 縮放最小值（= fit，整圖可見）。
  static const double _minScale = 1.0;

  /// 縮放最大值。
  static const double _maxScale = 5.0;

  /// 滑鼠滾輪每一格的縮放係數（×1.1 in / ÷1.1 out）。
  static const double _wheelStep = 1.1;

  /// 控制 InteractiveViewer 的 Matrix4；wheel / double-tap 會手動設置 scale，
  /// InteractiveViewer 自動處理 pan。
  final TransformationController _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 關 overlay 並 log 來源。[reason] 走 `backdrop | button` 二選一；ESC 由 Navigator barrierDismissible 處理，不經此路徑。
  void _close(String reason) {
    Logger('gacha.hoyowiki.zoom').info('overlay close reason=$reason');
    Navigator.of(context).pop();
  }

  /// 以 [localFocal]（Listener / InteractiveViewer 局部座標）為中心套用 [scaleDelta]
  /// 倍縮放。公式：T(focal) · S(delta) · T(-focal) · M，確保焦點 scene 位置在縮放後不動。
  /// 新 scale 會 clamp 在 [_minScale]..[_maxScale]。
  void _zoomAt({required Offset localFocal, required double scaleDelta}) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    final next = (current * scaleDelta).clamp(_minScale, _maxScale);
    final actual = next / current;
    if ((actual - 1).abs() < 1e-6) return;
    _ctrl.value =
        (Matrix4.identity()
          ..translateByDouble(localFocal.dx, localFocal.dy, 0, 1)
          ..scaleByDouble(actual, actual, actual, 1)
          ..translateByDouble(-localFocal.dx, -localFocal.dy, 0, 1)) *
        _ctrl.value;
  }

  /// 處理 mouse wheel：向上（scrollDelta.dy < 0）放大、向下縮小，以游標為中心。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy < 0 ? _wheelStep : 1 / _wheelStep;
    _zoomAt(localFocal: event.localPosition, scaleDelta: delta);
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
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: InteractiveViewer(
              transformationController: _ctrl,
              panEnabled: true,
              // wheel / double-tap 自管 scale，避免兩套 scale source 打架。
              scaleEnabled: false,
              minScale: _minScale,
              maxScale: _maxScale,
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
