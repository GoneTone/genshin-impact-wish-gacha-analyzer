# 分享圖右欄時間軸與左欄等高 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓分享圖右欄時間軸卡片高度永遠等於左欄雙圓餅高度（內容少時卡內留白、多時底部裁切），把現有「間接推導」改為「明確量測後強制」。

**Architecture:** 新增一個小型 `MultiChildRenderObjectWidget`（`LeftDrivenEqualHeight`）：左欄以自然高度 layout、量得高 H、強制右欄 tight height = H。`TimelineVertical` 的 `fillHeight` 分支加 `ClipRect + OverflowBox` 解開內部高約束並裁切，使卡片邊框恆滿 H 且無 RenderFlex overflow。`_SectionView` 把現有 `IntrinsicHeight + Stack` 區塊換成 `LeftDrivenEqualHeight`。

**Tech Stack:** Flutter（custom RenderBox + ContainerRenderObjectMixin）、flutter_test widget tests。

參考 spec：`docs/superpowers/specs/2026-05-19-share-timeline-equal-height-design.md`

---

## File Structure

- **Create** `lib/widgets/share/left_driven_equal_height.dart` — 兩欄等高 layout primitive（左欄驅動高度），單一職責、無外部相依（僅 tokens 取 `AppSpacing.l`）。
- **Modify** `lib/widgets/cards/timeline_vertical.dart` — `container()` builder 的 `fillHeight==true` 分支加 `ClipRect + OverflowBox`；`fillHeight==false` 完全不變。
- **Modify** `lib/widgets/share/share_card.dart` — `_SectionView.build` 下半段改用 `LeftDrivenEqualHeight`；`_timeline()` 加 `fillHeight: true`；移除 `Stack`/`Positioned`/`OverflowBox`/`Key('shareTimelineClip')` 與該段長註解。
- **Create** `test/widgets/share/left_driven_equal_height_test.dart` — 新 primitive 的單元行為測試。
- **Modify** `test/widgets/cards/timeline_vertical_test.dart` — 新增「fillHeight + 內容超出有界高 → 無 overflow、卡片恆滿高」測試。
- **Modify** `test/widgets/share/share_card_test.dart` — 既有兩處 `Key('shareTimelineClip')` 量測改為量 `TimelineVertical` 外框 Container；更新對應描述/註解；補 `LeftDrivenEqualHeight` 結構斷言。

---

## Task 1: 新增 `LeftDrivenEqualHeight` layout primitive

**Files:**
- Create: `lib/widgets/share/left_driven_equal_height.dart`
- Test: `test/widgets/share/left_driven_equal_height_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/share/left_driven_equal_height_test.dart`：

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';

const _leftKey = Key('ldeh-left');
const _rightKey = Key('ldeh-right');

Future<void> _pump(WidgetTester t, double leftH, double rightNaturalH) async {
  await t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 1000,
          child: LeftDrivenEqualHeight(
            children: [
              SizedBox(key: _leftKey, height: leftH),
              SizedBox(key: _rightKey, height: rightNaturalH),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('右欄高被強制 = 左欄高（右自然較高 → 不撐大整體）', (t) async {
    await _pump(t, 300, 1000);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byKey(_rightKey)).height, closeTo(300, 0.01));
    expect(t.getSize(find.byKey(_leftKey)).height, closeTo(300, 0.01));
    expect(
      t.getSize(find.byType(LeftDrivenEqualHeight)).height,
      closeTo(300, 0.01),
    );
  });

  testWidgets('右欄高被強制 = 左欄高（右自然較矮 → 仍撐到左欄高）', (t) async {
    await _pump(t, 300, 50);
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byKey(_rightKey)).height, closeTo(300, 0.01));
  });

  testWidgets('寬度依 11:9 + AppSpacing.l 間距切分', (t) async {
    await _pump(t, 200, 200);
    const contentW = 1000 - AppSpacing.l;
    expect(
      t.getSize(find.byKey(_leftKey)).width,
      closeTo(contentW * 11 / 20, 0.01),
    );
    expect(
      t.getSize(find.byKey(_rightKey)).width,
      closeTo(contentW * 9 / 20, 0.01),
    );
    // 右欄水平起點 = 左寬 + 間距。
    final leftRight = t.getTopRight(find.byKey(_leftKey)).dx;
    final rightLeft = t.getTopLeft(find.byKey(_rightKey)).dx;
    expect(rightLeft - leftRight, closeTo(AppSpacing.l, 0.01));
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/share/left_driven_equal_height_test.dart`
Expected: FAIL — `left_driven_equal_height.dart` / `LeftDrivenEqualHeight` 不存在（compile error）。

- [ ] **Step 3: 實作 primitive**

建立 `lib/widgets/share/left_driven_equal_height.dart`：

```dart
// lib/widgets/share/left_driven_equal_height.dart
//
// 兩欄版面：左欄以自然高度 layout，量得其高 H 後，強制右欄高度也為 H。
// 右欄超出 H 的部分由右欄自身（TimelineVertical 的 fillHeight 分支）clip，
// 本元件不負責裁切。寬度依固定 flex 11:9 + AppSpacing.l 間距切分。
// children 必須恰為兩個：index 0 = 左、index 1 = 右。
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class LeftDrivenEqualHeight extends MultiChildRenderObjectWidget {
  const LeftDrivenEqualHeight({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeftDrivenEqualHeight();
}

class _LDParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderLeftDrivenEqualHeight extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LDParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LDParentData> {
  static const double _leftFlex = 11;
  static const double _rightFlex = 9;
  static const double _gap = AppSpacing.l;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LDParentData) {
      child.parentData = _LDParentData();
    }
  }

  ({double leftW, double rightW}) _split(double maxWidth) {
    final contentW = maxWidth - _gap;
    final leftW = contentW * _leftFlex / (_leftFlex + _rightFlex);
    return (leftW: leftW, rightW: contentW - leftW);
  }

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth,
      'LeftDrivenEqualHeight 需有界寬度（分享圖固定 1200）',
    );
    assert(childCount == 2, 'LeftDrivenEqualHeight 必須恰兩個 children');
    final maxW = constraints.maxWidth;
    final (:leftW, :rightW) = _split(maxW);

    final left = firstChild!;
    final right = childAfter(left)!;

    left.layout(BoxConstraints.tightFor(width: leftW), parentUsesSize: true);
    final leftH = left.size.height;
    right.layout(
      BoxConstraints.tightFor(width: rightW, height: leftH),
      parentUsesSize: true,
    );

    (left.parentData! as _LDParentData).offset = Offset.zero;
    (right.parentData! as _LDParentData).offset = Offset(leftW + _gap, 0);

    size = Size(maxW, leftH);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final (:leftW, rightW: _) = _split(width);
    return firstChild!.getMinIntrinsicHeight(leftW);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final (:leftW, rightW: _) = _split(width);
    return firstChild!.getMaxIntrinsicHeight(leftW);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild!.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild!.getMaxIntrinsicWidth(height);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final (:leftW, rightW: _) = _split(constraints.maxWidth);
    final leftSize = firstChild!.getDryLayout(
      BoxConstraints.tightFor(width: leftW),
    );
    return Size(constraints.maxWidth, leftSize.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/share/left_driven_equal_height_test.dart`
Expected: PASS（3 個測試全綠）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/share/left_driven_equal_height.dart test/widgets/share/left_driven_equal_height_test.dart
git commit -m "feat(share): add LeftDrivenEqualHeight layout primitive"
```

提交訊息結尾加上：

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 2: `TimelineVertical` fillHeight 加 ClipRect + OverflowBox

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart:144-162`（`container()` 內 `return Container(...)`）
- Test: `test/widgets/cards/timeline_vertical_test.dart`（在第 231 行 `fillHeight: true` 測試之後新增一個 test）

- [ ] **Step 1: 寫失敗測試**

在 `test/widgets/cards/timeline_vertical_test.dart` 第 231 行
（`fillHeight: true → 卡片外框撐滿…600` 測試的 `});` 結尾）之後、
第 233 行 `fillHeight: false …` 測試之前，插入：

```dart
  testWidgets(
    'fillHeight: true + 內容遠超有界高（300）→ 無 overflow、卡片恆 = 300、內容置頂',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => SizedBox(
            height: 300,
            child: TimelineVertical(
              fillHeight: true,
              entries: [
                for (var i = 0; i < 30; i++)
                  _e('五星$i', '301', 80, DateTime(2026, 1, 1).subtract(
                    Duration(days: 31 * i + 1),
                  )),
              ],
              colors: colors,
              targetRank: 5,
            ),
          ),
        ),
      );
      // 解開內部高約束 + clip → 不可有 RenderFlex overflow / 任何 error。
      expect(tester.takeException(), isNull);
      // 卡片外框恆 = 父給的有界高 300（不被內容撐大、也不縮小）。
      final boxFinder = find.descendant(
        of: find.byType(TimelineVertical),
        matching: find.byType(Container),
      );
      expect(tester.getSize(boxFinder.first).height, closeTo(300, 0.5));
      // fillHeight 分支應包一層 ClipRect 負責裁切超出內容。
      expect(
        find.descendant(
          of: find.byType(TimelineVertical),
          matching: find.byType(ClipRect),
        ),
        findsWidgets,
      );
      // 最上方（最新）entry 仍可見（內容置頂、未被裁掉）。
      expect(find.text('五星0'), findsOneWidget);
    },
  );
```

> 註：`_wrap` / `_e` 為該測試檔既有 helper，沿用即可，勿另造。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart -p vm --plain-name "內容遠超有界高"`
Expected: FAIL — 目前 `fillHeight` 分支內部 `Column(min)` 在 300 有界高下會 RenderFlex overflow，`takeException()` 非 null（且無 `ClipRect`）。

- [ ] **Step 3: 改實作**

開啟 `lib/widgets/cards/timeline_vertical.dart`，將 `container()` 內現有的
`return Container(...)`（約第 144–162 行）整段：

```dart
      return Container(
        // fillHeight=true：在父為有界高度時撐滿該高度（內容因下方 Column
        // 仍 mainAxisSize.min 而置頂，底部為 padding 內留白）。
        // fillHeight=false（App 既有用法）：不加 constraints，渲染樹與加入
        // 此參數前逐字等價、零回歸。
        constraints: fillHeight
            ? const BoxConstraints(minHeight: double.infinity)
            : null,
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.l,
          horizontal: AppSpacing.l,
        ),
        child: body,
      );
```

替換為：

```dart
      // fillHeight=true：父為有界高度時，外框撐滿該高度；內部 body 以
      // ClipRect + OverflowBox 解開高約束（自然高、不 RenderFlex overflow）
      // 並置頂，超出邊框 padding 區的部分由 ClipRect 直接裁掉。內容少時
      // OverflowBox 區域 = 有界高，body 自然高較矮 → 下方為卡內留白。
      // fillHeight=false（App 既有用法）：child 維持原 body，渲染樹與加入
      // 此參數前逐字等價、零回歸。
      final Widget content = fillHeight
          ? ClipRect(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topCenter,
                child: body,
              ),
            )
          : body;
      return Container(
        constraints: fillHeight
            ? const BoxConstraints(minHeight: double.infinity)
            : null,
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.l,
          horizontal: AppSpacing.l,
        ),
        child: content,
      );
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: PASS（新測試 + 既有 `fillHeight: true/false` 兩個既有測試皆綠；`fillHeight:false` 分支未動 → 零回歸）。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "fix(timeline): fillHeight clips overflow + fills bounded height (no RenderFlex overflow)"
```

提交訊息結尾加上：

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 3: `_SectionView` 改用 `LeftDrivenEqualHeight` 並更新 share 測試

**Files:**
- Modify: `lib/widgets/share/share_card.dart`（import；`_SectionView._timeline()`；`_SectionView.build` 下半段約第 408–495 行）
- Modify: `test/widgets/share/share_card_test.dart`

- [ ] **Step 1: 改 `_timeline()` 傳 `fillHeight: true`**

`lib/widgets/share/share_card.dart` 的 `_SectionView._timeline()` 內
`return TimelineVertical(...)`，於 `isAcrossBanners: section.isAcrossBanners,`
之後新增一行 `fillHeight: true,`：

```dart
    return TimelineVertical(
      title: l.timelineTopRarityTitle(l.rarityStar(rank), shown.length),
      entries: shown,
      colors: colors,
      targetRank: rank,
      nowPulls: section.timelineNowPulls,
      isAcrossBanners: section.isAcrossBanners,
      fillHeight: true,
    );
```

- [ ] **Step 2: 加 import**

在 `share_card.dart` import 區（與其他 `widgets/...` import 同段，依字母序）新增：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';
```

- [ ] **Step 3: 換掉 `build` 下半段**

`_SectionView.build` 內，從註解
`// 下方：左欄雙圓餅 + 右欄時間軸（直接裁切）。` 起，到對應的
`IntrinsicHeight( child: Row( ... ) )` 整塊（含長機制註解、`Stack`、
`Positioned`、`OverflowBox`、`Key('shareTimelineClip')`，約第 408–495 行
`const SizedBox(height: AppSpacing.l),` 之後到該 `IntrinsicHeight` 結束）
整段替換為：

```dart
        const SizedBox(height: AppSpacing.l),
        // 下方：左欄雙圓餅 + 右欄時間軸，右欄高度由左欄量測後強制等高
        // （LeftDrivenEqualHeight）。右欄 fillHeight：內容少→卡內底部留白、
        // 內容多→底部由 TimelineVertical 自身 ClipRect 裁切。
        LeftDrivenEqualHeight(
          children: [
            // index 0 = 左欄：稀有度 + 類型雙圓餅（含圖例）
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _PieBox(
                  title: l.statsRarityDistribution,
                  pie: RarityPie(
                    stats: section.stats,
                    animationDuration: Duration.zero,
                  ),
                  legend: DistributionLegend(
                    entries: rarityDistributionEntries(
                      section.stats,
                      tokens,
                      l,
                    ),
                  ),
                  tokens: tokens,
                ),
                const SizedBox(height: AppSpacing.m),
                _PieBox(
                  title: l.statsItemTypeDistribution,
                  pie: ItemTypePie(
                    stats: section.stats,
                    animationDuration: Duration.zero,
                  ),
                  legend: DistributionLegend(
                    entries: itemTypeDistributionEntries(
                      section.stats,
                      brightness,
                      l,
                    ),
                  ),
                  tokens: tokens,
                ),
              ],
            ),
            // index 1 = 右欄：時間軸（fillHeight，超出自身裁切）
            _timeline(),
          ],
        ),
```

> 確認替換後 `build` 的 `Column` children 結尾結構正確（`Text(title)`、
> `SizedBox`、頂部 `IntrinsicHeight` StatCard Row 維持不動；只有最後這塊
> 由 `IntrinsicHeight(Row[...])` 變為 `LeftDrivenEqualHeight`）。

- [ ] **Step 4: 更新 `share_card_test.dart` — 兩處 clip 量測 + 描述**

`test/widgets/share/share_card_test.dart`：

(a) 第 201 行測試標題
`'時間軸超出左欄高：右欄區域恆 = 左欄高、內容被裁、無 footer、無 overflow'`
改為
`'時間軸超出左欄高：右欄卡恆 = 左欄高、內容被裁、無 footer、無 overflow'`。

(b) 第 219–225 行：

```dart
    // 右欄裁切容器（Stack）高度恆 == 左欄兩 _PieBox 疊高（由 Stack
    // intrinsic=0 → Row stretch 高度完全由左欄決定，右欄不反拉左欄）。
    final clipHeight = t
        .getSize(find.byKey(const Key('shareTimelineClip')))
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(clipHeight, closeTo(leftHeight, 0.5));
```

替換為：

```dart
    // 右欄時間軸卡外框高度恆 == 左欄兩 _PieBox 疊高（LeftDrivenEqualHeight
    // 量左欄高後強制右欄等高；超出由 TimelineVertical 自身 ClipRect 裁掉）。
    expect(find.byType(LeftDrivenEqualHeight), findsOneWidget);
    final rightHeight = t
        .getSize(
          find
              .descendant(
                of: find.byType(TimelineVertical),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(rightHeight, closeTo(leftHeight, 0.5));
```

(c) 第 271 行測試標題
`'資料少：右欄裁切容器恆 = 左欄高（Row 由左欄決定，右不反拉）'`
改為
`'資料少：右欄卡恆 = 左欄高（卡內底部留白，不縮小）'`。

(d) 第 287–294 行：

```dart
    // 裁切容器（Stack）撐滿右欄區域，其高 = 左欄高（Stack intrinsic=0，
    // Row stretch 高度完全由左欄決定）。資料少時 TimelineVertical 自然高
    // 比此矮，是已選定行為（右欄下方為背景空白，不強撐等高）。
    final clipHeight = t
        .getSize(find.byKey(const Key('shareTimelineClip')))
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(clipHeight, closeTo(leftHeight, 0.5));
```

替換為：

```dart
    // 資料少時，右欄卡仍被強制撐到左欄高（卡內底部為留白，非縮小、
    // 非外部背景空白）—— 即使用者確認的目標行為。
    expect(find.byType(LeftDrivenEqualHeight), findsOneWidget);
    final rightHeight = t
        .getSize(
          find
              .descendant(
                of: find.byType(TimelineVertical),
                matching: find.byType(Container),
              )
              .first,
        )
        .height;
    final leftHeight = _leftColumnHeight(t, l);
    expect(rightHeight, closeTo(leftHeight, 0.5));
```

(e) 第 297 行 overview 測試（`跨月 5★ 大量資料（overview）…`）內，於
`expect(find.byType(TimelineVertical), findsNWidgets(2));` 之後新增一行
結構斷言：

```dart
    expect(find.byType(LeftDrivenEqualHeight), findsNWidgets(2));
```

(f) 在 `share_card_test.dart` import 區（依字母序，於
`widgets/share/share_card.dart` import 之前）新增：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/left_driven_equal_height.dart';
```

- [ ] **Step 5: 跑 share 相關測試確認通過**

Run: `flutter test test/widgets/share/share_card_test.dart test/widgets/share/share_render_tree_test.dart`
Expected: PASS（全綠；無 `Key('shareTimelineClip')` 殘留參照、無 overflow）。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/share_card.dart test/widgets/share/share_card_test.dart
git commit -m "feat(share): right timeline card height equals left column via LeftDrivenEqualHeight"
```

提交訊息結尾加上：

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Task 4: 全套品質閘

**Files:** 無（驗證 only）

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 僅本次改動檔被格式化（或 `0 changed`）；不要對 `.` 跑。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`
（若出現 `log_service` / `app_release_checker` 平行 flaky，單獨重跑該檔確認綠即非回歸。）

- [ ] **Step 4: 若有格式化改動則補 commit**

```bash
git add -A
git commit -m "style: dart format after share equal-height changes"
```

（若 Step 1 無改動則跳過此步。）提交訊息結尾加上：

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Self-Review

**Spec coverage：**

- spec §1（`LeftDrivenEqualHeight` primitive）→ Task 1 ✅
- spec §2（`TimelineVertical` fillHeight clip + 解高約束）→ Task 2 ✅
- spec §3（`_SectionView` 接點、`_timeline()` fillHeight、移除 Stack/key、綜合模式兩段獨立）→ Task 3（綜合模式天然由兩個 `_SectionView` → 兩個 `LeftDrivenEqualHeight` 實例，Step 4(e) 斷言 `findsNWidgets(2)`）✅
- spec §「測試與品質閘」→ Task 1/2/3 的 TDD 測試 + Task 4 三道閘 ✅
- spec §「不做（YAGNI）」→ primitive 固定順序無 id/無可變 flex；不動 StatCard row；不在 render object 內 clip（裁切集中於 TimelineVertical）✅

**Placeholder scan：** 無 TBD/TODO；每個改 code 的 step 均附完整程式碼與精確行段。

**Type consistency：** `LeftDrivenEqualHeight({super.key, required super.children})` 於 Task 1 定義，Task 3 以 `children: [左 Column, _timeline()]` 使用一致；`fillHeight` 參數為 `TimelineVertical` 既有具名參數（spec/現碼已存在），Task 3 Step 1 僅新增傳值；`_leftColumnHeight` / `_wrap` / `_e` 均為既有 test helper，未重定義。
