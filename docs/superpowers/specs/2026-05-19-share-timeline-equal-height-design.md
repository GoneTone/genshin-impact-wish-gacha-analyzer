# 分享圖右欄時間軸與左欄等高（明確量測後強制）

日期：2026-05-19
分支：flutter-rewrite

## 問題

分享圖版面 B：左欄為「稀有度分布 + 類型分布」雙圓餅卡，右欄為「5★ 時間軸」卡。
需求：**右側時間軸卡片邊框永遠 = 左欄高度**；時間軸內容少時卡內底部留白、
內容多時底部直接裁切。

現有機制（`share_card.dart` `_SectionView`）靠 `IntrinsicHeight` +
`Stack(Clip.hardEdge)` + `OverflowBox`，利用「Stack 只有 Positioned 子代 →
intrinsic 高 = 0 → Row 高由左欄 intrinsic 決定」這個**間接推導**把右欄裁到
左欄高。離屏渲染管線給整棵樹 unbounded 高約束，此間接技巧在該管線下不穩定
（連續 5 個 commit 微調仍對不齊）。根因是右欄高度被間接推導，而非明確量測。

已與使用者確認的目標行為：

- 右卡邊框高度 **永遠** = 左欄高度
- 時間軸內容 < 左欄高：卡內底部留白（空白在邊框內）
- 時間軸內容 > 左欄高：底部裁切（裁切點在邊框內）

## 方案

把「右欄高 = 左欄高」從「間接推導」改為「明確量測後強制」，分三處改動。

### 1. 新增 layout primitive `LeftDrivenEqualHeight`

`CustomMultiChildLayout` 的 render box size 在 `getSize(constraints)` 階段即須
決定、不能依賴子代尺寸；本需求的 box 高正好要等於左欄量測值，故不採用，
改寫一個小型 `MultiChildRenderObjectWidget`。

- 位置：`lib/widgets/share/left_driven_equal_height.dart`
- 兩個子代，以 `LayoutId`-風格的 parentData 或固定順序（index 0 = 左、
  index 1 = 右）標識；採固定順序即可，無需 id（YAGNI）。
- RenderObject（`RenderBox` + `ContainerRenderObjectMixin` +
  `RenderBoxContainerDefaultsMixin`）`performLayout`：
  1. `gap = AppSpacing.l`；`contentW = constraints.maxWidth - gap`；
     `leftW = contentW * 11 / 20`；`rightW = contentW - leftW`
  2. 左欄：`BoxConstraints.tightFor(width: leftW)` 高 `0..∞` → 量得 `leftH`
  3. 右欄：`BoxConstraints.tightFor(width: rightW, height: leftH)`（強制）
  4. 定位：左 `(0, 0)`、右 `(leftW + gap, 0)`
  5. `size = Size(constraints.maxWidth, leftH)`
- `paint`：以 default children paint（兩子代各自偏移），不需自行 clip
  （裁切在 §2 由 `TimelineVertical` 內部完成）。
- intrinsics / dry layout：離屏管線走 `performLayout` 路徑。實作
  `computeMinIntrinsicHeight` / `computeMaxIntrinsicHeight` 委派左欄子代，
  以防 App 內其他外層（若有）查詢 intrinsic；`computeDryLayout` 比照
  performLayout 規則回 `Size(constraints.maxWidth, 左欄 dry 高)`。

> flex 11:9 與 `AppSpacing.l` 間距沿用現有 `_SectionView` 設定，視覺不變。

### 2. `TimelineVertical` 的 `fillHeight` 強化

現況：`fillHeight:true` 僅對外層 `Container` 加
`constraints: BoxConstraints(minHeight: double.infinity)`。在 §1 給的
tight height 下，`Container` 經 constraints `enforce` 會解析成正好 `leftH`，
邊框高正確；但內容 > `leftH` 時內部 `Column(mainAxisSize: min)` 會
RenderFlex overflow（debug 警告，且可能使 widget test 失敗）。

改動：`container()` builder 中，`fillHeight == true` 時，把 `body` 包成

```
ClipRect(
  child: OverflowBox(
    minHeight: 0,
    maxHeight: double.infinity,
    alignment: Alignment.topCenter,
    child: body,
  ),
)
```

外層 `Container` 維持 `fillHeight` 的高度約束（解析為 `leftH`）。效果：

- 內容 < `leftH`：`OverflowBox` 內 `body` 自然高且置頂，`ClipRect` 區域
  = `leftH`，下方為卡內 padding/背景留白 → **卡片仍滿高**
- 內容 > `leftH`：`body` 以自然高 layout（`OverflowBox` 解開高約束 →
  無 RenderFlex overflow），`ClipRect` 裁到 `leftH` → **底部裁切**

`fillHeight == false`（App 既有用法）分支完全不變，渲染樹逐字等價、零回歸。

### 3. `_SectionView` 接點與綜合模式

`_SectionView.build` 下半段，移除現有
`IntrinsicHeight > Row[Expanded(左), SizedBox(gap), Expanded(Stack(右))]`
整塊（含 `Stack` / `Positioned` / `OverflowBox` 與該段長註解），改為：

```
LeftDrivenEqualHeight(
  children: [
    左欄雙圓餅 Column（原 flex 11 Expanded 內的 Column 內容，不再包 Expanded）,
    _timeline(),  // 改傳 fillHeight: true
  ],
)
```

- `_timeline()` 內 `TimelineVertical(...)` 新增 `fillHeight: true`。
- 右欄不再需要 `Stack` / `OverflowBox` / `Positioned` 包裝與
  `Key('shareTimelineClip')`。
- 頂部三張 `StatCard` 的 `IntrinsicHeight` Row **不動**（該塊本即正常）。
- 綜合模式（`ShareCard.overview`）為兩個獨立 `_SectionView`，各自持有一個
  `LeftDrivenEqualHeight` 實例 → 兩段各自獨立等高，天然成立，無需額外處理。
- `share_card.dart` 內 `_kShareTimelineMaxEntries`（取前 10 筆）邏輯保留
  不變；超出右欄高度的部分由 §2 的 `ClipRect` 負責裁切。

## 測試與品質閘

- 更新既有 share widget test：移除對 `Key('shareTimelineClip')` 的斷言，
  改驗 `LeftDrivenEqualHeight` 存在；保留 `Key('shareStatRow')` 相關斷言。
- 新增 case：
  - 長時間軸（內容自然高 > 左欄）：右卡 render 高 == 左欄 render 高，
    且時間軸尾端 row 被裁（驗高度相等即可，不需逐 row 斷言）。
  - 短時間軸（內容自然高 < 左欄，如 5★ 筆數極少）：右卡 render 高
    仍 == 左欄 render 高。
- 提交前依序通過：
  1. `dart format lib/ test/`
  2. `flutter analyze` → `No issues found!`
  3. `flutter test` → `All tests passed!`
- 若需埋 log：本變更為純版面 layout，無 I/O / 外部 API / Rust bridge
  互動，無新增 log 點需求。

## 不做（YAGNI）

- 不為 `LeftDrivenEqualHeight` 加 id / 可變 flex / 可配置 gap 參數，
  以固定順序 + 沿用現值實作。
- 不重構頂部 StatCard row 或其他無關版面。
- 不在 render object 內自行 clip（裁切由 §2 集中於 `TimelineVertical`，
  避免兩處各自裁切的維護負擔）。
