# 橫向時間軸 · 可滑動視覺提示 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `TimelineHorizontal` 在內容超出 viewport 時,**靜態畫面**就能看出可左右滑(邊緣 fade + 半透明圓形箭頭按鈕,只顯示可滑方向)。

**Architecture:** 把 `TimelineHorizontal` 從 `StatelessWidget` 升級為 `StatefulWidget`,持有 `ScrollController` 監聽 offset,在 Stack 內以 4 個 `Positioned` 層條件渲染左/右 fade + 左/右箭頭。點擊箭頭呼叫 `controller.animateTo(offset ± 90)`(一欄寬,240 ms easeOutCubic)。

**Tech Stack:** Flutter / Dart;新增的私有 widget(`_EdgeFade`、`_ArrowButton`、`enum ScrollSide`)全部留在 `lib/widgets/cards/timeline_horizontal.dart` 同檔。l10n 沿用 Flutter gen-l10n + ARB(master = `app_zh_Hant.arb`)。

**Spec:** `docs/superpowers/specs/2026-05-13-timeline-horizontal-scroll-affordance-design.md`

---

## 檔案影響

| 動作 | 路徑 | 責任 |
|---|---|---|
| Modify | `lib/l10n/app_zh_Hant.arb` | master locale,加 `timelineScrollLeft` / `timelineScrollRight`(2 個 key) |
| Modify | `lib/l10n/app_zh_Hans.arb` | 簡中 override,同 2 個 key 改字 |
| Modify | `lib/l10n/app_en.arb` | 英文,同 2 個 key |
| Modify | `lib/l10n/generated/**` | 由 `flutter gen-l10n` 自動產生,**不要手改** |
| Modify | `lib/widgets/cards/timeline_horizontal.dart` | 整檔大改:Stateless → Stateful、加 fade + 箭頭 |
| Modify | `test/widgets/cards/timeline_horizontal_test.dart` | 新增 affordance 測試案例(保留現有 6 個) |

---

## Task 1: 新增 l10n keys

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`(template / master)
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_en.arb`
- Auto-generated:`lib/l10n/generated/app_localizations*.dart`

**為什麼這 3 個檔就夠?** 專案 `l10n.yaml` 設定 `template-arb-file: app_zh_Hant.arb`,其他語系(es/fr/ja/pt/th/vi/zh)缺翻譯時自動 fallback 用 master 字。已存在的 `timelineNoRecords` 等 keys 在 `app_localizations_ja.dart` 等檔都是 `'暫無 5★ 紀錄'`(master fallback)。

- [ ] **Step 1: 加 keys 到 `app_zh_Hant.arb`(master)**

在 `timelineMonthLabel` 區塊結束的閉合 `},`(目前約 line 190)**之後**,空白行之前,插入兩行:

```json
  "timelineScrollLeft": "往左捲動",
  "timelineScrollRight": "往右捲動",
```

不加 `@timelineScrollLeft` metadata — 是 simple 字串無 placeholder,跟現有 `timelineNoRecords` 風格一致。

- [ ] **Step 2: 加 keys 到 `app_zh_Hans.arb`**

簡中與繁中字不同(「捲動 / 滚动」),需要 override。在 `timelineMonthLabel` metadata 閉合 `},`(目前約 line 145)之後,空白行之前:

```json
  "timelineScrollLeft": "往左滚动",
  "timelineScrollRight": "往右滚动",
```

- [ ] **Step 3: 加 keys 到 `app_en.arb`**

在 `timelineMonthLabel` metadata 閉合之後(目前約 line 171),空白行之前:

```json
  "timelineScrollLeft": "Scroll left",
  "timelineScrollRight": "Scroll right",
```

- [ ] **Step 4: 重新產生 generated/**

```bash
flutter gen-l10n
```

預期輸出無錯誤(若有 ARB JSON 語法錯,gen-l10n 會直接拋出 missing comma / unexpected token,先回頭修)。

- [ ] **Step 5: 驗證 generated 檔有新方法**

```bash
grep -n "timelineScrollLeft\|timelineScrollRight" lib/l10n/generated/app_localizations.dart
```

預期:`String get timelineScrollLeft;` 與 `String get timelineScrollRight;` 兩條 abstract getter(在 `AppLocalizations` 抽象類別內)。

```bash
grep -n "timelineScrollLeft" lib/l10n/generated/app_localizations_ja.dart
```

預期:ja 也有 `String get timelineScrollLeft => '往左捲動';`(master fallback)。

- [ ] **Step 6: commit**

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "feat(l10n): add timelineScrollLeft/Right keys for horizontal timeline affordance"
```

---

## Task 2: 寫失敗測試 — affordance 顯示與互動

**Files:**
- Modify: `test/widgets/cards/timeline_horizontal_test.dart`(保留現有 6 個 case,在尾端 `}` 前加新 case)

**測試 viewport 設定**:現有 `_wrap` 給 1000 px 寬。20 entries × 90 px = 1800 px,會 overflow(`maxScrollExtent ≈ 800`);2 entries 才 180 px,**不** overflow。

- [ ] **Step 1: 在現存 `}`(`void main()` 收尾)之前插入 affordance 測試組**

把下面整段貼進去(maintain 縮排):

```dart
  // ---- Scroll affordance (fade + arrows) ----

  List<TimelineEntry> _manyEntries(int n) => [
    for (var i = n - 1; i >= 0; i--)
      _e('E$i', '301', 60 + (n - 1 - i),
          DateTime(2025, 1, 1).add(Duration(days: i))),
  ];

  testWidgets(
    'overflow + offset=0 → right arrow visible, left hidden',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: _manyEntries(20),
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    },
  );

  testWidgets(
    'overflow + offset=middle → both arrows visible',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: _manyEntries(20),
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    },
  );

  testWidgets(
    'overflow + offset=max → left arrow visible, right hidden',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: _manyEntries(20),
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets(
    'no overflow (2 entries) → no arrows on either side',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: [
              _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
              _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
            ],
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets(
    'tap right arrow → scrolls by one column (90 px)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: _manyEntries(20),
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, 0);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(90, 0.5));
    },
  );

  testWidgets(
    'tap right arrow repeatedly → clamps at maxScrollExtent and hides right arrow',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) => TimelineHorizontal(
            entries: _manyEntries(20),
            colors: colors,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TimelineHorizontal),
          matching: find.byType(Scrollable),
        ),
      );
      // 1800 - 1000 = 800 px max; 90 px/tap → 10 taps is plenty
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
      }
      expect(
        scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, 0.5),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    },
  );

  testWidgets(
    'entries shrink from overflow to non-overflow → arrows disappear',
    (tester) async {
      final widget = (List<TimelineEntry> entries) => _wrap(
        (ctx, colors) =>
            TimelineHorizontal(entries: entries, colors: colors),
      );
      await tester.pumpWidget(widget(_manyEntries(20)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.pumpWidget(
        widget([
          _e('夜蘭', '301', 87, DateTime(2025, 4, 1)),
          _e('流浪者', '301', 74, DateTime(2025, 3, 1)),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    },
  );

  testWidgets(
    'empty + no nowPulls → no scroll affordance even if widget renders',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          (ctx, colors) =>
              TimelineHorizontal(entries: const [], colors: colors),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );
```

- [ ] **Step 2: 確認測試失敗(現行實作尚未做 affordance)**

```bash
flutter test test/widgets/cards/timeline_horizontal_test.dart
```

預期:8 個新 case 中,「顯示箭頭」相關(`findsOneWidget` 的)會 fail(no chevron icon)、「不顯示」相關(`findsNothing` 的)會 pass。**至少 4 個 fail 才是正確紅燈狀態**。

若所有 case 都 pass,代表 expect 寫法有誤 — 回頭檢查 Step 1。

- [ ] **Step 3: 不 commit**(等實作完成才一起 commit)

---

## Task 3: 實作 — `TimelineHorizontal` Stateful 升級 + fade + 箭頭

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`(整檔大改;頂層常數、`_EntryColumn` / `_NowColumn` / `_Node` 三個私有 widget 不動)

- [ ] **Step 1: 在頂層常數區後新增 enum 與動畫常數**

在 `const double _haloSize = 22;`(現約 line 13)**之後**,插入:

```dart
const double _edgeFadeWidth = 32;
const Duration _scrollDuration = Duration(milliseconds: 240);
const Curve _scrollCurve = Curves.easeOutCubic;

enum _ScrollSide { left, right }
```

- [ ] **Step 2: 把 `class TimelineHorizontal extends StatelessWidget` 改成 Stateful**

把現有 class 宣告與建構子保留,**將 extends 改為 `StatefulWidget`**,新增 `createState`:

```dart
class TimelineHorizontal extends StatefulWidget {
  const TimelineHorizontal({
    super.key,
    required this.entries,
    required this.colors,
    this.nowPulls,
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;

  @override
  State<TimelineHorizontal> createState() => _TimelineHorizontalState();
}
```

- [ ] **Step 3: 新增 `_TimelineHorizontalState`**

放在 `TimelineHorizontal` class 收尾 `}` 之後,`_EntryColumn` 之前:

```dart
class _TimelineHorizontalState extends State<TimelineHorizontal> {
  late final ScrollController _controller;
  bool _hasLeft = false;
  bool _hasRight = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_updateAffordance);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateAffordance(),
    );
  }

  @override
  void didUpdateWidget(covariant TimelineHorizontal old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries || old.nowPulls != widget.nowPulls) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _updateAffordance(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + delta).clamp(0.0, pos.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: _scrollDuration,
      curve: _scrollCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;

    if (widget.entries.isEmpty && widget.nowPulls == null) {
      return Center(
        child: Text(
          l.timelineNoRecords,
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return Stack(
      children: [
        // 背景軸線
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: Center(
              child: Container(
                height: 2,
                color: tokens.textMuted.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        // 內容層 (橫向 scroll)
        Positioned.fill(
          child: ScrollConfiguration(
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.nowPulls != null)
                      _NowColumn(nowPulls: widget.nowPulls!, tokens: tokens),
                    for (final entry in widget.entries)
                      _EntryColumn(
                        entry: entry,
                        colors: widget.colors,
                        tokens: tokens,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 左 fade + 左箭頭
        if (_hasLeft) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _edgeFadeWidth,
            child: const IgnorePointer(
              child: _EdgeFade(side: _ScrollSide.left),
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(
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
              child: _EdgeFade(side: _ScrollSide.right),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ArrowButton(
                icon: Icons.chevron_right,
                tooltip: l.timelineScrollRight,
                tokens: tokens,
                onPressed: () => _scrollBy(_colWidth),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
```

注意:Stateful 升級後 `widget.entries` / `widget.nowPulls` / `widget.colors`,**不要**忘記改前綴。

- [ ] **Step 4: 刪除原本 `TimelineHorizontal` 內的 `build` method 與 `entries / colors / nowPulls` field 之外的內容**

(Step 2 已把 fields 留在 StatefulWidget 內。`build` 已移到 `_TimelineHorizontalState`。把現在還掛在 `class TimelineHorizontal` 內的舊 `build` 整段刪掉。)

- [ ] **Step 5: 新增 `_EdgeFade` widget**

放在 `_Node` 收尾 `}` 之後(檔案末端):

```dart
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.side});
  final _ScrollSide side;

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).gacha.surfaceCard;
    final isLeft = side == _ScrollSide.left;
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
```

- [ ] **Step 6: 新增 `_ArrowButton` widget**

緊接在 `_EdgeFade` 之後:

```dart
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.tokens,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final GachaTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
              child: Icon(icon, size: 16, color: tokens.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: 跑測試確認綠燈**

```bash
flutter test test/widgets/cards/timeline_horizontal_test.dart
```

預期:**全部測試通過**(現有 6 + 新增 8 = 14 個)。

若有 case 失敗,常見原因與排查:
- 箭頭找不到 → 檢查 `_hasRight` 初次評估是否在 `addPostFrameCallback` 觸發,測試是否有 `pumpAndSettle`
- 「tap right → 90 px」變成 0 → 檢查 `_scrollBy` 的 sign 是否寫反 / `_colWidth` 常數是否引用對

- [ ] **Step 8: 跑全套測試確認沒撞到別處**

```bash
flutter test
```

預期:`All tests passed!`(其他 widget 例如 `BannerPage` 內含 `TimelineHorizontal`,若有測試覆蓋也要綠)。

---

## Task 4: 品質檢查 + commit

CLAUDE.md 明文規定 commit 前依序跑這三項。

- [ ] **Step 1: 格式化**

```bash
dart format lib/ test/
```

(**不要**對 `.` 跑,會動到 `rust_builder/` 內 vendored 程式碼。)

預期輸出:`Formatted N files (M changed)`。

- [ ] **Step 2: 靜態分析**

```bash
flutter analyze
```

預期:`No issues found!`。若出現 warning(unused import / parameter)就修。

- [ ] **Step 3: 測試**

```bash
flutter test
```

預期:`All tests passed!`。

- [ ] **Step 4: commit**

```bash
git add lib/widgets/cards/timeline_horizontal.dart test/widgets/cards/timeline_horizontal_test.dart
git commit -m "feat(timeline-horizontal): add edge fade + arrow buttons for scroll affordance"
```

---

## Task 5: 手動驗收(UI 視覺確認)

CLAUDE.md / system prompt 都強調 UI 改動要在瀏覽器/桌面實際操作。

- [ ] **Step 1: 跑 dev**

```bash
flutter run -d windows
```

(或 `-d chrome` / `-d macos`,依開發機而定)

- [ ] **Step 2: 開啟一個有 ≥ 5 個 5★ 紀錄的卡池**

導航到 BannerPage,看 Row 2 的 5★ 時間軸 ChartCard。

**驗收清單**:

- [ ] 初始狀態:右側看到漸層淡出 + 半透明圓形 `❯` 按鈕,左側沒有
- [ ] 點擊 `❯` 一次:內容平滑向左滑(箭頭往右移動相當於畫面左移)約 90 px,動畫順
- [ ] 連點 `❯` 直到底:右側 fade + `❯` 消失,左側 fade + `❮` 出現
- [ ] 拖曳/滾輪/觸控板手勢仍可滑(原行為未壞)
- [ ] 切到只有 ≤ 3 個 5★ 的卡池:兩側都不出現 affordance(內容沒超出)
- [ ] 切換深/淺主題:fade 顏色跟著卡片背景改

- [ ] **Step 3: 若發現視覺異常**(例如 fade 顏色不對、箭頭 z-order 錯、tooltip 不出現)

回 Task 3 對應 step,修正,重跑 Task 4 品質檢查。

---

## Self-Review

- **Spec coverage**:
  - §2 視覺風格 → Task 3 Step 5/6/7(`_EdgeFade`、`_ArrowButton`、Stack 結構)
  - §3 架構 → Task 3 Step 1-4(Stateful 升級、Stack widget tree)
  - §4 視覺規格 → Task 3 Step 5/6 的 code 內常數
  - §5 狀態資料流 → Task 3 Step 3(`_TimelineHorizontalState` lifecycle)
  - §6 點擊行為 → Task 3 Step 3(`_scrollBy`)
  - §7 邊界情境 → Task 2 測試組(空狀態、不可滑、entries 變動、邊界 ±1)
  - §8 l10n keys → Task 1
  - §9 測試 → Task 2 + Task 3 Step 7-8
  - §10 YAGNI 排除項目 → 計畫內未實作(no shared widget、no 鍵盤滾動、no permanent scrollbar)

- **未涵蓋的 spec 項**:無

- **Placeholder 掃描**:無 TBD / TODO / "similar to" / 空泛敘述

- **Type 一致性**:
  - `_colWidth = 90`(原檔常數)在 Task 3 Step 3 的 `_scrollBy(-_colWidth)` / `_scrollBy(_colWidth)` 使用 — 一致
  - `_ScrollSide.left / right` enum 與 `_EdgeFade(side: ...)` 使用 — 一致
  - `tokens.textPrimary` / `tokens.textMuted` / `tokens.surfaceCard` 全部來自 `GachaTokens`,跟 `_Node` / `_EntryColumn` 既有用法一致
  - `AppLocalizations` 的 `timelineScrollLeft` / `timelineScrollRight` getter:Task 1 加入 ARB 後 Task 3 引用 — 一致
