import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

/// 左／右箭頭欄的寬度（含內距，足以容納 24px 圓鈕）。
const double _arrowSlotWidth = 32;

/// 中間捲動區邊緣漸隱遮罩的寬度。
const double _chipFadeWidth = 24;

/// 箭頭欄與中間頁籤捲動區之間的水平間距，讓箭頭與標籤拉開一點呼吸空間。
const double _arrowGap = 6;

/// 單行可水平捲動的頁籤列：左箭頭、可捲動 ChoiceChip 列（含邊緣 fade）、右箭頭。
///
/// 三欄固定排版，箭頭獨立欄位不會遮住邊緣頁籤。箭頭由「選中索引是否在頭／尾」
/// 驅動（在第一個時左箭頭停用、最後一個時右箭頭停用），點箭頭等同切換到上／下
/// 一個頁籤並把它捲入可視範圍；中間 fade 則由實際 scroll offset 驅動，兩者解耦。
///
/// 呼叫端需保證 `0 <= selectedIndex < labels.length`；是否顯示整條 bar
/// （例如只有一個頁籤時隱藏）由呼叫端決定，此元件不自行判斷。
class GalleryChipBar extends StatefulWidget {
  /// 建立 [GalleryChipBar]。
  const GalleryChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  /// 各頁籤的顯示文字，順序即顯示順序。
  final List<String> labels;

  /// 當前選中的頁籤索引。
  final int selectedIndex;

  /// 切換頁籤時的回呼，參數為新選中的索引。
  final ValueChanged<int> onSelected;

  @override
  State<GalleryChipBar> createState() => _GalleryChipBarState();
}

/// [GalleryChipBar] 的 state：管理橫向捲動控制器、fade 可見性與選中自動捲入。
class _GalleryChipBarState extends State<GalleryChipBar> {
  /// 中間頁籤列的捲動控制器。
  late final ScrollController _controller;

  /// 每個頁籤的 key，供 [Scrollable.ensureVisible] 把選中頁籤捲入可視範圍。
  late List<GlobalKey> _keys;

  /// true 時顯示左側漸隱遮罩。
  bool _hasLeft = false;

  /// true 時顯示右側漸隱遮罩。
  bool _hasRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateAffordance);
    _keys = _buildKeys(widget.labels.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateAffordance();
      _ensureSelectedVisible();
    });
  }

  @override
  void didUpdateWidget(covariant GalleryChipBar old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      // 頁籤數量變動會重建 _keys，選中頁籤可能因此跑出視野；除了更新 fade，
      // 也一併把選中頁籤捲回可視範圍，避免停在被裁切的位置。
      _keys = _buildKeys(widget.labels.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateAffordance();
        _ensureSelectedVisible();
      });
    }
    if (old.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSelectedVisible(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 產生 [n] 個全新的 [GlobalKey]，對應 [GalleryChipBar.labels] 各項。
  List<GlobalKey> _buildKeys(int n) => List.generate(n, (_) => GlobalKey());

  /// 依捲動位置更新 [_hasLeft] / [_hasRight]，控制兩側 fade 的顯示。
  void _updateAffordance() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final hasLeft = _controller.offset > 1;
    final hasRight = _controller.offset < pos.maxScrollExtent - 1;
    if (hasLeft != _hasLeft || hasRight != _hasRight) {
      setState(() {
        _hasLeft = hasLeft;
        _hasRight = hasRight;
      });
    }
  }

  /// 把當前選中的頁籤以動畫捲入可視範圍中央。
  void _ensureSelectedVisible() {
    if (!mounted) return;
    final index = widget.selectedIndex;
    if (index < 0 || index >= _keys.length) return;
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: kScrollAffordanceDuration,
      curve: kScrollAffordanceCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final l = AppLocalizations.of(context)!;
    final selected = widget.selectedIndex;
    final lastIndex = widget.labels.length - 1;

    return Row(
      children: [
        SizedBox(
          width: _arrowSlotWidth,
          child: Center(
            child: ScrollArrowButton(
              icon: Icons.arrow_left,
              tooltip: l.galleryPrevTab,
              tokens: tokens,
              onPressed: selected > 0
                  ? () => widget.onSelected(selected - 1)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: _arrowGap),
        Expanded(
          child: Stack(
            children: [
              // 非 Positioned 的 sizing child：決定 Stack 高度（dialog 內無固定
              // 高度，不能像 timeline 那樣全用 Positioned.fill，否則高度塌陷）。
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.labels.length; i++)
                          Padding(
                            key: _keys[i],
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(widget.labels[i]),
                              selected: i == selected,
                              showCheckmark: false,
                              onSelected: (_) => widget.onSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_hasLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _chipFadeWidth,
                  child: const IgnorePointer(
                    child: ScrollEdgeFade(side: ScrollSide.left),
                  ),
                ),
              if (_hasRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _chipFadeWidth,
                  child: const IgnorePointer(
                    child: ScrollEdgeFade(side: ScrollSide.right),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: _arrowGap),
        SizedBox(
          width: _arrowSlotWidth,
          child: Center(
            child: ScrollArrowButton(
              icon: Icons.arrow_right,
              tooltip: l.galleryNextTab,
              tokens: tokens,
              onPressed: selected < lastIndex
                  ? () => widget.onSelected(selected + 1)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
