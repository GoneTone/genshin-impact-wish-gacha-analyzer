import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

/// 分享圖渲染的 logger（命名空間 share.image）。
final _log = Logger('share.image');

/// 預解碼 app icon，給 ShareCard 以 RawImage 同步繪製
/// （Image.asset 是 async，無法在同步 pipeline flush 內完成）。
///
/// 回傳的 [ui.Image] 由呼叫端負責用完後 dispose 釋放 native 資源。
Future<ui.Image> loadAppIconImage() async {
  final data = await rootBundle.load('assets/icons/app_icon.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// 把 [widget] 以「寬固定 [width]、高隨內容自適應」同步離屏渲染成 PNG bytes。
///
/// 採獨立 RenderView + BuildOwner pipeline，不依賴 live Navigator/Overlay；
/// 全程同步 flush（無動畫、無 async image），輸出穩定可測。
///
/// 寬度 tight 約束為 [width]；高度給 **unbounded**（0..∞）約束，讓 boundary
/// 取內容自然高度。實測本專案 ShareCard 透過 `buildShareRenderTree` 的
/// `Overlay`（`canSizeOverlay: true` 的非定位 entry）在 unbounded 高度下會
/// shrink-wrap 成 `Container(width:…)` + `Column(mainAxisSize.min)` 的自然高；
/// 故輸出像素尺寸 = `width × 內容自然高 × pixelRatio`，底部不留白、不裁切。
///
/// 註：Flutter 3.41.9 的 `_RenderTheatre`（Overlay 底層）只有在
/// `constraints.biggest.isFinite == false` 時才會走「以 size-determining child
/// 決定自身大小」分支；給 finite `maxHeight` 會讓 Overlay 直接撐滿到 maxHeight
/// 而非自適應，故此處必須用 unbounded 高度約束。
///
/// [maxHeight] 為防內容失控的安全上限：layout 後若 boundary 高度超過
/// `maxHeight` 才夾住（極端情況），正常內容不受影響、輸出即實際內容高。
Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required double width,
  double pixelRatio = 3.0,
  double maxHeight = 8000,
}) async {
  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;

  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      // 寬 tight = width；高 unbounded（0..∞）→ Overlay 走 child-sizing 分支，
      // boundary shrink-wrap 取內容自然高。
      logicalConstraints: BoxConstraints(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: double.infinity,
      ),
      physicalConstraints: BoxConstraints(
        minWidth: width * pixelRatio,
        maxWidth: width * pixelRatio,
        minHeight: 0,
        maxHeight: double.infinity,
      ),
      devicePixelRatio: pixelRatio,
    ),
    // boundary 直接作 child（RepaintBoundary 為 RenderProxyBox，透傳約束、
    // 取 child size）。不可包 RenderPositionedBox：Align 在 unbounded 主軸會
    // 報錯。
    child: boundary,
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  try {
    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: MediaQueryData(devicePixelRatio: pixelRatio),
        child: widget,
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    // boundary.size 已是 width × 內容自然高（unbounded 高度 → Overlay
    // shrink-wrap）。安全上限：內容高超過 maxHeight 才以 tight 約束重 layout
    // 夾住（避免極端資料產生失控大圖）；正常內容不會觸發。
    if (boundary.size.height > maxHeight) {
      _log.warning(
        'content height ${boundary.size.height} exceeds maxHeight '
        '$maxHeight, clamping',
      );
      renderView.configuration = ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(Size(width, maxHeight)),
        physicalConstraints: BoxConstraints.tight(
          Size(width, maxHeight) * pixelRatio,
        ),
        devicePixelRatio: pixelRatio,
      );
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();
    }

    // 須在 dispose/卸載前讀取 size 供 log。
    final renderedSize = boundary.size;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }
    final out = bytes.buffer.asUint8List();
    _log.info(
      'render ok: ${renderedSize.width}x${renderedSize.height} '
      '@${pixelRatio}x, ${out.length} bytes',
    );
    return out;
  } catch (e, st) {
    _log.severe('render failed', e, st);
    rethrow;
  } finally {
    // 釋放 render tree：卸下 render 節點，斷開 pipeline/build owner。
    // 整個 pipeline 為本函式區域物件、無 live binding 參照，
    // 卸下後即可被 GC 回收。
    boundary.child = null;
    renderView.child = null;
    pipelineOwner.rootNode = null;
  }
}
