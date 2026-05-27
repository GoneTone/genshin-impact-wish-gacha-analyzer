# 橫向時間軸 · 可滑動視覺提示

| 項目 | 內容 |
|---|---|
| 日期 | 2026-05-13 |
| 主題 | 讓 `TimelineHorizontal` 一眼看上去就知道可以左右滑動 |
| 動機 | 現有橫向時間軸內容經常超出 ChartCard viewport,但靜態畫面沒有任何 affordance,使用者不知道右側還有更多紀錄 |
| 範圍 | `lib/widgets/cards/timeline_horizontal.dart` 一個檔案;新增 2 個 l10n key |

---

## 1. 背景

### 1.1 現況

`TimelineHorizontal`(`lib/widgets/cards/timeline_horizontal.dart`)在 `BannerPage` Row 2 的 `ChartCard` 槽位內,寬度約 330 px(三欄佈局)。每欄寬 `_colWidth = 90`,因此實際可容納 3–4 欄,5★ 紀錄超過 4 個就會橫向超出 viewport。

現有可滑動的 affordance 只有兩個:

1. `MouseRegion(cursor: SystemMouseCursors.resizeLeftRight)` — 滑鼠 hover 進入 timeline 時游標變左右拖拉箭頭
2. `ScrollConfiguration.dragDevices` 加入 mouse / trackpad / touch / stylus — 桌面滑鼠拖得動

兩個都是「使用者得先把滑鼠移上去」才看得到。靜態截圖、觸控裝置首次看到 timeline、或視線快速掃過時,完全無法判斷「右側其實還有東西」。

### 1.2 問題

「一眼看上去」就要能識別 timeline 可橫向滾動。

### 1.3 設計目標

1. 內容超出 viewport 時,**不需互動**就能看出有「左/右還有更多」
2. 提供直接操作管道(箭頭點擊),不只是視覺暗示
3. 內容未超出時(短紀錄、空狀態)不顯示任何 affordance,維持靜態圖樣貌
4. 既有的拖曳/滾輪/觸控滑動行為完全不動

---

## 2. 視覺設計決策(已確認)

| 決策點 | 結論 |
|---|---|
| Affordance 風格 | **邊緣 fade + 箭頭按鈕**(兩招並用) |
| 顯示策略 | **只顯示可滑方向**(右邊還有 → 右側 fade + ❯;滑到底 → 右側消失、左側 ❮ 出現) |
| 點擊行為 | **一次滑一欄**(90 px,= `_colWidth`) |
| 動畫 | 240 ms,`Curves.easeOutCubic` |
| 平台處理 | 桌面與行動端皆顯示箭頭(目標就是「一眼」,不為平台美感打折) |
| Scrollbar | 不額外加(避免與 fade/箭頭視覺擁擠) |
| 鍵盤滾動 | 暫不加(YAGNI,使用者極少用鍵盤滾 timeline) |

---

## 3. 架構

### 3.1 檔案結構

```
lib/widgets/cards/
└── timeline_horizontal.dart        ← 改造:Stateless → Stateful,新增 _EdgeFade、_ArrowButton
```

**不抽出共用 widget**:全專案目前只有這一處橫向滾動(`grep` 結果僅 1 個 `scrollDirection: Axis.horizontal`),提早抽象違反 YAGNI。未來若出現第二處再 extract。

### 3.2 Widget tree

`TimelineHorizontal` 從 `StatelessWidget` 升級為 `StatefulWidget`,持有 `ScrollController`。

```
TimelineHorizontal (Stateful)
└─ Stack
   ├─ [背景軸線層]   Positioned.fill → Padding → Center → Container (h=2, 灰)
   ├─ [內容層]      Positioned.fill → ScrollConfiguration → SingleChildScrollView (controller)
   │                  └─ MouseRegion(resizeLeftRight) → Row → _NowColumn / _EntryColumn × N
   ├─ [左 fade]     Positioned(left, top, bottom, width=32) → IgnorePointer → _EdgeFade(side: left)
   │                   顯示條件: _hasLeft
   ├─ [右 fade]     Positioned(right, top, bottom, width=32) → IgnorePointer → _EdgeFade(side: right)
   │                   顯示條件: _hasRight
   ├─ [左箭頭]      Positioned(left:4, top:0, bottom:0) → Center → _ArrowButton(onPressed: _scrollBy(-90))
   │                   顯示條件: _hasLeft
   └─ [右箭頭]      Positioned(right:4, top:0, bottom:0) → Center → _ArrowButton(onPressed: _scrollBy(90))
                       顯示條件: _hasRight
```

疊層由底而上:軸線 → 內容 → fade → 箭頭。fade 蓋住軸線兩端,讓軸線看起來也淡出。

### 3.3 新增的私有元件(同檔)

- `enum ScrollSide { left, right }`(private)
- `_EdgeFade({required ScrollSide side, required Color cardColor})` — 純視覺,`DecoratedBox` + `LinearGradient`
- `_ArrowButton({required IconData icon, required VoidCallback onPressed, required String tooltip, required GachaTokens tokens})` — `Material(CircleBorder) + InkWell` 提供 ripple

### 3.4 現有 `_EntryColumn`、`_NowColumn`、`_Node` 不動。

---

## 4. 視覺規格

### 4.1 邊緣 fade

- 寬度:`32 px`
- 漸層:`LinearGradient`,卡片背景色(`tokens.surfaceCard`)→ 透明
  - 右側 fade:`begin: centerRight, end: centerLeft`(顏色濃在右)
  - 左側 fade:`begin: centerLeft, end: centerRight`
- `IgnorePointer`:fade 層不吃手勢

### 4.2 箭頭按鈕

| 屬性 | 值 |
|---|---|
| 形狀 | 24×24 圓形 `Material(shape: CircleBorder)` |
| 背景 | `tokens.surfaceCard.withValues(alpha: 0.85)` |
| 邊框 | `tokens.textMuted.withValues(alpha: 0.25)`,寬 1 |
| 圖示 | `Icons.chevron_right` / `chevron_left`,16 px,色 `tokens.textPrimary` |
| 位置 | 垂直置中,水平距卡片邊框 4 px(`left: 4` / `right: 4`) |
| Tooltip | 左 = `l.timelineScrollLeft`、右 = `l.timelineScrollRight` |
| Cursor | `SystemMouseCursors.click`(覆蓋外層的 resize 游標) |
| Semantics | `button: true`,label 同 tooltip |

### 4.3 顯示時機

```
_hasLeft  = controller.offset > 1
_hasRight = controller.offset < position.maxScrollExtent - 1
```

`> 1` / `- 1` 避免 floating point 抖動造成箭頭閃爍。

內容 ≤ viewport 時 `maxScrollExtent == 0`,兩側皆隱藏 — 此時 ChartCard 看起來是靜態圖,正確。

---

## 5. 狀態與資料流

```dart
class _TimelineHorizontalState extends State<TimelineHorizontal> {
  late final ScrollController _controller;
  bool _hasLeft = false;
  bool _hasRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateAffordance);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateAffordance());
  }

  @override
  void didUpdateWidget(covariant TimelineHorizontal old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries || old.nowPulls != widget.nowPulls) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateAffordance());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateAffordance() {
    if (!_controller.hasClients) return;
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
}
```

**重點**:

- 只在 `_hasLeft / _hasRight` 改變時才 `setState`,避免每幀重繪
- `addPostFrameCallback` 確保首次 layout 與 entries 變動後拿得到正確的 `maxScrollExtent`
- `didUpdateWidget` 接住 entries / nowPulls 動態更新(換卡池、import 完成)
- 視窗 resize:`ScrollPosition.didChangeViewportDimension` 內部會 notify listeners,自動重算

---

## 6. 點擊行為與動畫

```dart
static const _scrollStepPx = _colWidth;          // 90 px
static const _scrollDuration = Duration(milliseconds: 240);
static const _scrollCurve = Curves.easeOutCubic;

void _scrollBy(double delta) {
  if (!_controller.hasClients) return;
  final pos = _controller.position;
  final target = (_controller.offset + delta).clamp(0.0, pos.maxScrollExtent);
  _controller.animateTo(target, duration: _scrollDuration, curve: _scrollCurve);
}
```

**設計決策**:

- 一欄 = 90 px,綁定 `_colWidth`,以後改欄寬不會走樣
- 240 ms / easeOutCubic:Material Motion「small expressive」區間,連點響應感佳
- `clamp`:越界自動止於邊界,listener 接著收掉對應方向箭頭
- 連點不自己 debounce,讓 `animateTo` 預設行為(cancel + 接續)處理

---

## 7. 邊界情境

| 情境 | 行為 |
|---|---|
| `entries` 空 + `nowPulls == null` | 維持現狀:顯示 `l.timelineNoRecords`,Stack 不渲染 |
| 內容 ≤ viewport(`maxScrollExtent == 0`) | 兩側 affordance 皆隱藏 |
| 邊界 ±1 px | `> 1` / `< max - 1` 避免閃爍 |
| `entries` 動態更新 | `didUpdateWidget` 下幀重算;offset 超界由 `ScrollPosition` 自動 clamp |
| 視窗 resize | `didChangeViewportDimension` 觸發 listener,自動重算 |
| 主題切換(深/淺) | `_EdgeFade` 每次 build 從 `Theme.of(context).gacha.surfaceCard` 拿色,即時跟隨 |
| RTL | timeline 語意「新→舊」與 RTL 無關;`_EdgeFade` 用 `centerLeft/centerRight`(非 `start/end`)避免被 ambient `Directionality` 翻轉 |

---

## 8. 新增的 l10n keys

`lib/l10n/app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb` 三個檔同步加入:

| Key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `timelineScrollLeft` | 往左捲動 | 往左滚动 | Scroll left |
| `timelineScrollRight` | 往右捲動 | 往右滚动 | Scroll right |

---

## 9. 測試

新增 `test/widgets/timeline_horizontal_test.dart`(若已存在則新增 cases)。

| Case | 驗證 |
|---|---|
| 可滑時起始狀態 | 10 entries / 330 px viewport,初始只有右箭頭可見 |
| 滑到中段 | `controller.jumpTo(maxScrollExtent / 2)` → 兩側皆可見 |
| 滑到最右 | `controller.jumpTo(maxScrollExtent)` → 只剩左箭頭 |
| 不可滑時 | 2 entries / 330 px viewport,兩側 `find.byIcon(chevron_left/right)` 皆為空 |
| 點擊右箭頭 | `tap` + `pumpAndSettle` → `controller.offset == 90` |
| 連點越界 | 連點 N 次 → `offset == maxScrollExtent`、右箭頭消失 |
| entries 動態變動 | 10 entries → 替換成 2 entries → 兩側箭頭消失 |
| 空狀態 | `entries: []`, `nowPulls: null` → 顯示 `timelineNoRecords`,無 Stack |

**回歸**:`flutter test` 須全綠;檢查現有 widget 測試是否有對 `TimelineHorizontal` 為 Stateless 的隱含假設(目前 grep 結果無)。

---

## 10. 不在範圍內(YAGNI)

- 抽出共用 `EdgeFadeMask` widget — 全專案僅一處橫滾,真有第二處再 extract
- 鍵盤方向鍵滾動 — 使用者極少需要,真有 a11y 需求再加
- 永遠可見的 scrollbar — fade + 箭頭已足夠,避免視覺擁擠
- 移除現有的 `resizeLeftRight` 游標 — 拖曳依然是有效操作,保留
- 自動 bounce / 首次出現動畫掃一下右邊 — 太花俏,違反「靜態一眼看出」的目標
