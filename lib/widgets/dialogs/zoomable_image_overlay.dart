import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/dialog_toast.dart';

/// 開啟全螢幕 lightbox 顯示 [imageFile]，可拖曳平移、滾輪 / 單擊縮放、ESC / 點背景 / X 關閉。
/// [suggestedBaseName] 為 copy／save 對話框的建議檔名（不含副檔名）。
Future<void> showZoomableImageOverlay(
  BuildContext context, {
  required File imageFile,
  required String suggestedBaseName,
}) {
  Logger('gacha.hoyowiki.zoom').info('overlay open file=${imageFile.path}');
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    // barrierDismissible: true 讓 Flutter Navigator 內建 ESC 關閉生效。
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ZoomableImageOverlay(
        imageFile: imageFile,
        suggestedBaseName: suggestedBaseName,
      ),
    ),
  );
}

/// 全螢幕 lightbox 圖片檢視器；獨立可重用，不耦合 caller。
class ZoomableImageOverlay extends StatefulWidget {
  /// 建立 [ZoomableImageOverlay]。
  const ZoomableImageOverlay({
    super.key,
    required this.imageFile,
    required this.suggestedBaseName,
  });

  /// 要顯示的本地圖檔。
  final File imageFile;

  /// copy／save「另存」對話框的建議檔名（不含副檔名）。
  final String suggestedBaseName;

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

  /// 放大狀態的目標 scale；fit ↔ 此值切換。
  static const double _zoomedScale = 2.0;

  /// 控制 InteractiveViewer 的 Matrix4；wheel / 單擊會手動設置 scale，
  /// InteractiveViewer 自動處理 pan。
  final TransformationController _ctrl = TransformationController();

  /// 共用的 [FileImage] provider；同時餵給 [Image] 渲染與 [_stream] 取得 intrinsic size，
  /// 避免兩次 decode。
  late final FileImage _imageProvider = FileImage(widget.imageFile);

  /// [_imageProvider] resolve 出的 stream；用來監聽 decode 完成事件以取得 intrinsic size。
  ImageStream? _stream;

  /// 監聽 image decode 完成的 listener；[dispose] 內 removeListener 解除註冊。
  late final ImageStreamListener _streamListener = ImageStreamListener((
    info,
    _,
  ) {
    if (!mounted) return;
    setState(() {
      _imageSize = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
    });
  });

  /// image 的 intrinsic 大小；null 時為 decode 尚未完成。用來把圖片像素區精準框在
  /// BoxFit.contain 後的 painted rect 上：單擊該區縮放，落在 image 外的暗區則傳到
  /// 外層 GestureDetector 觸發關閉。
  Size? _imageSize;

  /// 目前是否已放大（scale > fit）；驅動圖片游標與縮放鈕 icon。
  bool _zoomed = false;

  /// 最近一次 layout 的 viewport 尺寸；供縮放鈕以 viewport 中心為焦點縮放。
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    _stream = _imageProvider.resolve(ImageConfiguration.empty);
    _stream!.addListener(_streamListener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_streamListener);
    _ctrl.dispose();
    super.dispose();
  }

  /// 關 overlay 並 log 來源。[reason] 走 `backdrop | outside-image | button` 三選一；ESC 由 Navigator barrierDismissible 處理，不經此路徑。
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
    // 回到 fit（_minScale）→ 強制單位矩陣，否則 focal-centered 縮放公式會留下
    // translation 殘量，讓 scale=1 時圖片仍偏離 viewport（要拖一下 InteractiveViewer
    // 的 pan handler 才會 clamp 回來）。InteractiveViewer 的 constrained=true 只
    // 在使用者互動 pan 時 clamp，手動寫 matrix 必須自己處理。
    if ((next - _minScale).abs() < 1e-6) {
      _ctrl.value = Matrix4.identity();
      return;
    }
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
  /// 純水平滾動（dy == 0）忽略，避免 trackpad 兩指水平滑動誤觸發縮放。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy == 0) return;
    final delta = event.scrollDelta.dy < 0 ? _wheelStep : 1 / _wheelStep;
    _zoomAt(localFocal: event.localPosition, scaleDelta: delta);
    _syncZoomed();
  }

  /// 由當前矩陣推導 [_zoomed]；有變才 setState（讓游標／icon 同步、避免多餘 rebuild）。
  void _syncZoomed() {
    final z = (_ctrl.value.getMaxScaleOnAxis() - _minScale).abs() >= 0.05;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  /// 單擊圖片或按縮放鈕：在 fit ↔ [_zoomedScale] 間切換，以 [viewportFocal]
  /// （viewport 局部座標）為焦點。
  void _toggleZoom(Offset viewportFocal) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    final atFit = (current - _minScale).abs() < 0.05;
    final target = atFit ? _zoomedScale : _minScale;
    _zoomAt(localFocal: viewportFocal, scaleDelta: target / current);
    _syncZoomed();
    Logger(
      'gacha.hoyowiki.zoom',
    ).info('zoom toggle -> ${atFit ? 'in' : 'fit'}');
  }

  /// copy／save 共用選單項目（複製圖片 ／ 儲存圖片）；⋮ 按鈕與右鍵選單共用。
  List<PopupMenuEntry<String>> _menuItems(AppLocalizations l) => [
    PopupMenuItem(
      value: 'copy',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.copy, size: 20),
        title: Text(l.actionCopyImage),
      ),
    ),
    PopupMenuItem(
      value: 'save',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt, size: 20),
        title: Text(l.actionSaveImage),
      ),
    ),
  ];

  /// 分派選單選擇：複製 ／ 儲存。
  void _onMenuSelected(String value) {
    switch (value) {
      case 'copy':
        unawaited(_copy());
      case 'save':
        unawaited(_save());
    }
  }

  /// 複製目前圖片到剪貼簿（GIF 保留動畫、其餘轉 PNG），結果以 toast 回報。
  Future<void> _copy() async {
    final l = AppLocalizations.of(context)!;
    Logger('gacha.hoyowiki.zoom').info('menu copy');
    final ok = await copyImageFileToClipboard(widget.imageFile);
    if (!mounted) return;
    showDialogToast(context, ok ? l.imageCopied : l.imageCopyFailed);
  }

  /// 儲存目前圖片（GIF 存 .gif、其餘轉 PNG）→ 系統存檔對話框，結果以 toast 回報。
  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    Logger('gacha.hoyowiki.zoom').info('menu save');
    try {
      final path = await saveImageFile(
        widget.imageFile,
        suggestedBaseName: widget.suggestedBaseName,
      );
      if (!mounted || path == null) return;
      showDialogToast(context, l.imageSavedTo(path));
    } catch (_) {
      if (!mounted) return;
      showDialogToast(context, l.imageSaveFailed);
    }
  }

  /// 半透明黑底圓鈕包裝；右上角三顆按鈕共用，沿用既有 lightbox 視覺。
  Widget _circleButton(Widget child) => Material(
    color: Colors.black.withValues(alpha: 0.4),
    shape: const CircleBorder(),
    child: child,
  );

  /// 右鍵在圖片上叫出與 ⋮ 相同的選單，位置跟著游標。
  Future<void> _showContextMenu(Offset globalPosition) async {
    final l = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: _menuItems(l),
    );
    if (selected == null || !mounted) return;
    _onMenuSelected(selected);
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
            child: GestureDetector(
              // image 像素外的暗區（BoxFit.contain 留白）也視為背景，點擊立即關閉。
              // 只掛 onTap（不掛 onDoubleTap），TapGR 不會被 DoubleTapGR
              // arbitration 卡住 kDoubleTapTimeout（300ms）才 fire；單擊縮放
              // 下放到 image 上的內層 GestureDetector 處理。
              onTap: () => _close('outside-image'),
              child: InteractiveViewer(
                transformationController: _ctrl,
                panEnabled: true,
                // wheel / 單擊 自管 scale，避免兩套 scale source 打架。
                scaleEnabled: false,
                minScale: _minScale,
                maxScale: _maxScale,
                child: Center(
                  // 把 image 包進 SizedBox 並 size 到 BoxFit.contain 後的 painted
                  // rect，讓內層 GestureDetector 只覆蓋圖片像素區；image 外的
                  // letterbox 暗區留給外層 GestureDetector 處理 onTap 關閉。
                  // _imageSize 為 null（decode 尚未完成）時退化為填滿可用空間，
                  // 此時 GD 暫時覆蓋整個 viewer；本地檔案 decode 通常在第一幀
                  // 就完成，使用者察覺不到。
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      _viewportSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final imgSize = _imageSize;
                      double w = constraints.maxWidth;
                      double h = constraints.maxHeight;
                      if (imgSize != null &&
                          imgSize.width > 0 &&
                          imgSize.height > 0) {
                        final scale = (w / imgSize.width) < (h / imgSize.height)
                            ? w / imgSize.width
                            : h / imgSize.height;
                        w = imgSize.width * scale;
                        h = imgSize.height * scale;
                      }
                      // SizedBox 相對 viewport 置中的偏移；tap 落點（SizedBox 局部）加此偏移
                      // 還原成 viewport 局部座標，與滾輪／縮放鈕同一座標空間。
                      final dx = (constraints.maxWidth - w) / 2;
                      final dy = (constraints.maxHeight - h) / 2;
                      return SizedBox(
                        width: w,
                        height: h,
                        child: MouseRegion(
                          cursor: _zoomed
                              ? SystemMouseCursors.zoomOut
                              : SystemMouseCursors.zoomIn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // 單擊圖片像素區 → fit↔2x 切換（焦點＝點擊落點還原成 viewport 座標）。
                            // 圖片不再單擊關閉；暗區關閉由外層 GD 處理（對應常見圖片檢視器的習慣）。
                            onTapUp: (d) =>
                                _toggleZoom(d.localPosition + Offset(dx, dy)),
                            onSecondaryTapDown: (d) =>
                                unawaited(_showContextMenu(d.globalPosition)),
                            child: Image(
                              image: _imageProvider,
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
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        // 右上角按鈕列 [⋮][🔍][✕] — 永遠最上層。
        Positioned(
          top: 16,
          right: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _circleButton(
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    tooltip: '',
                    onSelected: _onMenuSelected,
                    itemBuilder: (_) => _menuItems(l),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _circleButton(
                IconButton(
                  tooltip: _zoomed ? l.actionZoomOut : l.actionZoomIn,
                  icon: Icon(
                    _zoomed ? Icons.zoom_out : Icons.zoom_in,
                    color: Colors.white,
                  ),
                  onPressed: () => _toggleZoom(
                    _viewportSize?.center(Offset.zero) ?? Offset.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _circleButton(
                IconButton(
                  tooltip: l.actionCloseImagePreview,
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => _close('button'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
