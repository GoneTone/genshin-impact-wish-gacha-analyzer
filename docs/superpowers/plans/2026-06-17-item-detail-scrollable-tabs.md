# 物品詳情 Dialog 頁籤改為單行可捲動 + 三角箭頭導航 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把物品詳情 Dialog 的頁籤從會換多行的 `Wrap` + `ChoiceChip` 改成維持一行、可水平捲動、左右有三角箭頭導航（頭／尾停用）的單行頁籤列。

**Architecture:** 先把 `timeline_horizontal.dart` 內既有的 `_EdgeFade`／`_ArrowButton` 抽成共用視覺元件 `ScrollEdgeFade`／`ScrollArrowButton`（放 `lib/widgets/scroll/`），讓 timeline 與新頁籤列共用；再新建獨立的 `GalleryChipBar` 元件負責三欄排版與捲動編排（箭頭由「選中索引頭尾」驅動、fade 由「scroll offset」驅動，兩者解耦）；最後讓 dialog 以 `GalleryChipBar` 取代原 `Wrap`。

**Tech Stack:** Flutter（Material 3）、`flutter_test` widget test、專案 `GachaTokens` 主題 extension（`Theme.of(context).gacha`）、`AppLocalizations` l10n。

**相對 spec 的調整：** spec 原寫「dialog 內 private `_GalleryChipBar`」。本 plan 改為 **public 獨立檔 `lib/widgets/dialogs/gallery_chip_bar.dart`**，理由：可獨立做 widget test（private 類別測試檔無法 import），且讓 dialog 檔更聚焦。行為與 spec 完全一致。

**tooltip 文案：** 重用既有 `l.timelineScrollLeft`（「往左捲動」）／`l.timelineScrollRight`（「往右捲動」），不新增 ARB key（YAGNI、避免擴張 i18n）。

---

## File Structure

- **Create** `lib/widgets/scroll/scroll_affordance.dart` — 共用捲動視覺元件：`ScrollSide` enum、`ScrollEdgeFade`、`ScrollArrowButton`（`onPressed` 為 nullable，`null` 即停用樣式），以及共用動畫常數 `kScrollAffordanceDuration`／`kScrollAffordanceCurve`。
- **Create** `test/widgets/scroll/scroll_affordance_test.dart` — `ScrollArrowButton` 啟用／停用行為測試。
- **Modify** `lib/widgets/cards/timeline_horizontal.dart` — 刪掉 private `_ScrollSide`／`_EdgeFade`／`_ArrowButton`／`_scrollDuration`／`_scrollCurve`，改 import 共用元件與常數（行為不變、icon 仍為 chevron）。
- **Create** `lib/widgets/dialogs/gallery_chip_bar.dart` — `GalleryChipBar`：三欄排版 + `ScrollController` + 箭頭切頁 + 選中自動捲入 + fade。
- **Create** `test/widgets/dialogs/gallery_chip_bar_test.dart` — `GalleryChipBar` 箭頭停用／切頁／點 chip 行為測試。
- **Modify** `lib/widgets/dialogs/gacha_item_detail_dialog.dart` — content Column 內的 `Wrap(...ChoiceChip...)` 換成 `GalleryChipBar(...)`。

---

## Task 1: 抽出共用捲動視覺元件 `scroll_affordance.dart`

**Files:**
- Create: `lib/widgets/scroll/scroll_affordance.dart`
- Test: `test/widgets/scroll/scroll_affordance_test.dart`

- [ ] **Step 1: 先寫失敗測試**

Create `test/widgets/scroll/scroll_affordance_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

Widget _wrap(Widget Function(GachaTokens tokens) build) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(
    body: Builder(
      builder: (ctx) => Center(child: build(Theme.of(ctx).gacha)),
    ),
  ),
);

void main() {
  testWidgets('onPressed != null → tappable, fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_left));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('onPressed == null → renders icon but tap does nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (tokens) => ScrollArrowButton(
          icon: Icons.arrow_left,
          tooltip: 'prev',
          tokens: tokens,
          onPressed: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_left), findsOneWidget);
    final inkWell = tester.widget<InkWell>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_left),
        matching: find.byType(InkWell),
      ),
    );
    expect(inkWell.onTap, isNull);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/scroll/scroll_affordance_test.dart`
Expected: FAIL（`scroll_affordance.dart` 不存在 / `ScrollArrowButton` 未定義，編譯錯誤）。

- [ ] **Step 3: 建立共用元件**

Create `lib/widgets/scroll/scroll_affordance.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 點擊捲動箭頭的動畫時長（timeline 與頁籤列共用）。
const Duration kScrollAffordanceDuration = Duration(milliseconds: 240);

/// 點擊捲動箭頭的動畫曲線（timeline 與頁籤列共用）。
const Curve kScrollAffordanceCurve = Curves.easeOutCubic;

/// 捲動可及性元件的方向。
enum ScrollSide {
  /// 左側：fade 從左往右漸隱。
  left,

  /// 右側：fade 從右往左漸隱。
  right,
}

/// 邊緣漸隱遮罩，用於提示使用者該方向仍可捲動。
///
/// 漸層自 [GachaTokens.surfaceCard]（不透明）漸隱到透明，會自動跟隨卡片／
/// dialog 背景色。寬度由外層 [Positioned] 決定，此元件本身不設寬度。
class ScrollEdgeFade extends StatelessWidget {
  /// 建立 [ScrollEdgeFade]。
  const ScrollEdgeFade({super.key, required this.side});

  /// 漸隱方向。
  final ScrollSide side;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).gacha.surfaceCard;
    final isLeft = side == ScrollSide.left;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [cardColor, cardColor.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// 浮在捲動區邊緣的圓形箭頭按鈕。
///
/// [onPressed] 為 `null` 時呈現停用樣式（icon 轉淡、游標不變手形、無法點擊），
/// 用於「已在最前／最後」的情境；非 `null` 時為可點的啟用樣式。
class ScrollArrowButton extends StatelessWidget {
  /// 建立 [ScrollArrowButton]。
  const ScrollArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onPressed,
  });

  /// 按鈕圖示（左箭頭或右箭頭）。
  final IconData icon;

  /// 無障礙 tooltip 文字。
  final String tooltip;

  /// 主題 token，用於按鈕背景色與 icon 顏色。
  final GachaTokens tokens;

  /// 點擊後的回呼；為 `null` 時按鈕停用。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Material(
            color: tokens.surfaceCard.withValues(alpha: 0.85),
            shape: CircleBorder(
              side: BorderSide(
                color: tokens.textMuted.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 24,
                height: 24,
                child: Icon(
                  icon,
                  size: 16,
                  color: enabled
                      ? tokens.textPrimary
                      : tokens.textMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/scroll/scroll_affordance_test.dart`
Expected: PASS（2 個測試）。

- [ ] **Step 5: 格式化 + 分析**

Run: `fvm dart format lib/widgets/scroll/ test/widgets/scroll/ && fvm flutter analyze lib/widgets/scroll/ test/widgets/scroll/`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/scroll/scroll_affordance.dart test/widgets/scroll/scroll_affordance_test.dart
git commit -m "feat(scroll): extract shared ScrollArrowButton and ScrollEdgeFade"
```

---

## Task 2: `timeline_horizontal.dart` 改用共用元件（純重構，迴歸保護）

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`
- Test（迴歸，不改）：`test/widgets/cards/timeline_horizontal_test.dart`

此任務不新增測試，靠既有 `timeline_horizontal_test.dart` 當迴歸保護（它用 `find.byIcon(Icons.chevron_left/right)` 驗證箭頭、用 `ScrollableState` 驗證捲動，icon 與行為都不變）。

- [ ] **Step 1: 先跑既有 timeline 測試，確認改動前是綠的**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: PASS（作為改動前基準）。

- [ ] **Step 2: 加入共用元件 import**

在 `lib/widgets/cards/timeline_horizontal.dart` 既有 import 區（約第 11 行 `gacha_item_icon.dart` import 之後）加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';
```

- [ ] **Step 3: 刪除被取代的私有常數與 enum**

刪除以下三段（第 25–32 行附近）：

```dart
/// 點擊箭頭捲動的動畫時長。
const Duration _scrollDuration = Duration(milliseconds: 240);

/// 點擊箭頭捲動的動畫曲線。
const Curve _scrollCurve = Curves.easeOutCubic;

/// 捲動可及性箭頭的方向。
enum _ScrollSide { left, right }
```

保留 `_edgeFadeWidth`（第 22–23 行）不動——timeline 仍用它當 Positioned 寬度。

- [ ] **Step 4: `_scrollBy` 改用共用常數**

把 `_scrollBy`（第 138–147 行）內的 `_scrollDuration`／`_scrollCurve` 改為共用常數：

```dart
  /// 相對捲動 [delta] px，夾在 0 與 maxScrollExtent 之間，使用動畫。
  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + delta).clamp(0.0, pos.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: kScrollAffordanceDuration,
      curve: kScrollAffordanceCurve,
    );
  }
```

- [ ] **Step 5: build 內 fade／箭頭改用共用元件**

把第 213–261 行的「左 fade + 左箭頭」「右 fade + 右箭頭」兩段，把 `_EdgeFade` → `ScrollEdgeFade`、`_ScrollSide` → `ScrollSide`、`_ArrowButton` → `ScrollArrowButton`：

```dart
        // 左 fade + 左箭頭
        if (_hasLeft) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edgeFadeWidth,
            child: const IgnorePointer(
              child: ScrollEdgeFade(side: ScrollSide.left),
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: ScrollArrowButton(
                icon: Icons.chevron_left,
                tooltip: l.timelineScrollLeft,
                tokens: tokens,
                onPressed: () => _scrollBy(-_colWidth),
              ),
            ),
          ),
        ],
        // 右 fade + 右箭頭
        if (_hasRight) ...[
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _edgeFadeWidth,
            child: const IgnorePointer(
              child: ScrollEdgeFade(side: ScrollSide.right),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: ScrollArrowButton(
                icon: Icons.chevron_right,
                tooltip: l.timelineScrollRight,
                tokens: tokens,
                onPressed: () => _scrollBy(_colWidth),
              ),
            ),
          ),
        ],
```

- [ ] **Step 6: 刪除檔尾被取代的 `_EdgeFade` 與 `_ArrowButton` 類別**

刪除第 444–519 行（`/// 邊緣漸隱遮罩...` 的 `_EdgeFade` class 與 `/// 浮在時間軸邊緣...` 的 `_ArrowButton` class）整段。`_Node`、`_EntryColumn`、`_NowColumn` 等其他私有類別保留不動。

- [ ] **Step 7: 跑 timeline 測試確認仍綠**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: PASS（全部維持綠——行為不變）。

- [ ] **Step 8: 格式化 + 分析**

Run: `fvm dart format lib/widgets/cards/timeline_horizontal.dart && fvm flutter analyze lib/widgets/cards/timeline_horizontal.dart`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/cards/timeline_horizontal.dart
git commit -m "refactor(timeline): use shared ScrollArrowButton and ScrollEdgeFade"
```

---

## Task 3: 新建 `GalleryChipBar` 元件

**Files:**
- Create: `lib/widgets/dialogs/gallery_chip_bar.dart`
- Test: `test/widgets/dialogs/gallery_chip_bar_test.dart`

**介面契約：** `GalleryChipBar({required List<String> labels, required int selectedIndex, required ValueChanged<int> onSelected})`。呼叫端需保證 `0 <= selectedIndex < labels.length`（dialog 已用 `clampedIndex` 收斂）。元件本身不判斷 `labels.length > 1`——是否顯示整條 bar 由呼叫端控制。

- [ ] **Step 1: 先寫失敗測試**

Create `test/widgets/dialogs/gallery_chip_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gallery_chip_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 400, child: child)),
  ),
);

ScrollArrowButton _btn(WidgetTester tester, IconData icon) =>
    tester.widget<ScrollArrowButton>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(ScrollArrowButton),
      ),
    );

void main() {
  testWidgets('selectedIndex=0 → left arrow disabled, right enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_left).onPressed, isNull);
    expect(_btn(tester, Icons.arrow_right).onPressed, isNotNull);
  });

  testWidgets('selectedIndex=last → right arrow disabled, left enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 2,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_right).onPressed, isNull);
    expect(_btn(tester, Icons.arrow_left).onPressed, isNotNull);
  });

  testWidgets('selectedIndex=middle → both arrows enabled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_btn(tester, Icons.arrow_left).onPressed, isNotNull);
    expect(_btn(tester, Icons.arrow_right).onPressed, isNotNull);
  });

  testWidgets('tap right arrow → onSelected(selectedIndex + 1)', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_right));
    await tester.pump();
    expect(picked, 1);
  });

  testWidgets('tap left arrow → onSelected(selectedIndex - 1)', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 2,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_left));
    await tester.pump();
    expect(picked, 1);
  });

  testWidgets('tap a chip → onSelected(that index)', (tester) async {
    int? picked;
    await tester.pumpWidget(
      _wrap(
        GalleryChipBar(
          labels: const ['A', 'B', 'C'],
          selectedIndex: 0,
          onSelected: (i) => picked = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('C'));
    await tester.pump();
    expect(picked, 2);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/dialogs/gallery_chip_bar_test.dart`
Expected: FAIL（`gallery_chip_bar.dart` 不存在 / `GalleryChipBar` 未定義）。

- [ ] **Step 3: 建立 `GalleryChipBar`**

Create `lib/widgets/dialogs/gallery_chip_bar.dart`:

```dart
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/scroll/scroll_affordance.dart';

/// 左／右箭頭欄的寬度（含內距，足以容納 24px 圓鈕）。
const double _arrowSlotWidth = 32;

/// 中間捲動區邊緣漸隱遮罩的寬度。
const double _chipFadeWidth = 24;

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
      _keys = _buildKeys(widget.labels.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateAffordance());
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
              tooltip: l.timelineScrollLeft,
              tokens: tokens,
              onPressed: selected > 0
                  ? () => widget.onSelected(selected - 1)
                  : null,
            ),
          ),
        ),
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
        SizedBox(
          width: _arrowSlotWidth,
          child: Center(
            child: ScrollArrowButton(
              icon: Icons.arrow_right,
              tooltip: l.timelineScrollRight,
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
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/dialogs/gallery_chip_bar_test.dart`
Expected: PASS（6 個測試）。

- [ ] **Step 5: 格式化 + 分析**

Run: `fvm dart format lib/widgets/dialogs/gallery_chip_bar.dart test/widgets/dialogs/gallery_chip_bar_test.dart && fvm flutter analyze lib/widgets/dialogs/gallery_chip_bar.dart test/widgets/dialogs/gallery_chip_bar_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/dialogs/gallery_chip_bar.dart test/widgets/dialogs/gallery_chip_bar_test.dart
git commit -m "feat(item-detail): add single-line scrollable GalleryChipBar"
```

---

## Task 4: dialog 改用 `GalleryChipBar` 取代 `Wrap`

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`

- [ ] **Step 1: 加入 import**

在 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` 既有 import 區（約第 19–21 行 dialog 相關 import 附近）加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gallery_chip_bar.dart';
```

- [ ] **Step 2: 替換 content Column 內的 chip 列**

把第 681–695 行（`if (chipEntries.length > 1)` 的 `Wrap(...ChoiceChip...)` 與其後的 `if (chipEntries.length > 1) const SizedBox(height: 12)`）整段，改為：

```dart
          if (chipEntries.length > 1) ...[
            GalleryChipBar(
              labels: [for (final e in chipEntries) e.label],
              selectedIndex: clampedIndex,
              onSelected: (i) => setState(() => _selectedIndex = i),
            ),
            const SizedBox(height: 12),
          ],
```

說明：原本 chip 列與其後 12px 間距是兩個獨立的 `if`；合併成一個 collection-if + spread 較精簡，行為等同（`clampedIndex` 在 `chipEntries.length > 1` 時必 `>= 0`，傳入安全）。

- [ ] **Step 3: 格式化 + 分析**

Run: `fvm dart format lib/widgets/dialogs/gacha_item_detail_dialog.dart && fvm flutter analyze lib/widgets/dialogs/gacha_item_detail_dialog.dart`
Expected: `No issues found!`

- [ ] **Step 4: 跑全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/dialogs/gacha_item_detail_dialog.dart
git commit -m "feat(item-detail): use GalleryChipBar for single-line scrollable tabs"
```

---

## 最終驗收

- [ ] **格式化全專案目標目錄**

Run: `fvm dart format lib/ test/`
Expected: 無重大變動（或僅既有格式微調）。

- [ ] **靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **手動驗證（建議）**

實際開啟一個有多個 gallery 頁籤的物品詳情 Dialog（角色類，gallery.list 多項），確認：
1. 頁籤維持一行、不換行，過長可水平捲動。
2. 左右三角箭頭永遠顯示（>1 頁籤時）；在第一個頁籤左箭頭灰掉、最後一個右箭頭灰掉。
3. 點箭頭會切到上／下一個頁籤並把它捲入可視範圍。
4. 縮窄視窗時不 overflow、箭頭不遮頁籤。
