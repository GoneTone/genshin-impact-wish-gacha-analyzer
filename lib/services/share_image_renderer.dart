// lib/services/share_image_renderer.dart
//
// 把任意 widget 以固定邏輯尺寸 + pixelRatio 同步離屏渲染成 PNG。
// 用獨立 RenderView + BuildOwner pipeline，不依賴 live Navigator/Overlay，
// 全程同步 flush（無動畫、無 async image），輸出穩定可測。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

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

/// 把 [widget] 以 [logicalSize] 邏輯尺寸、[pixelRatio] 像素密度同步離屏渲染成
/// PNG bytes（輸出像素尺寸 = logicalSize * pixelRatio）。
Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required Size logicalSize,
  double pixelRatio = 3.0,
}) async {
  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;

  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(logicalSize),
      physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
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

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }
    final out = bytes.buffer.asUint8List();
    _log.info(
      'render ok: ${logicalSize.width}x${logicalSize.height} '
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
