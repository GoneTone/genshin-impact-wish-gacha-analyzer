# 卡池主稀有度件數長條圖：兩側文字換行版面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 `BannerTopRarityBars` 各列的卡池名稱與右側「件數·說明」在任何語系下完整換行顯示不截斷，中間 bar 縮短讓出空間。

**Architecture:** 只改 `_BannerRow.build` 的版面：名稱欄與右側說明欄固定加寬並移除 `ellipsis`、允許自由換行；`_Bar` 外包 `ConstrainedBox(minWidth)` 防止窄視窗塌陷。不動任何資料 / 業務邏輯（件數、`computePity`、顏色、排序、文案）。

**Tech Stack:** Flutter / Dart，`flutter_test` widget test。

**Spec:** `docs/superpowers/specs/2026-05-18-banner-top-rarity-bars-wrap-layout-design.md`

---

## File Structure

- **Modify:** `lib/widgets/cards/banner_top_rarity_bars.dart` — 僅 `_BannerRow.build`（名稱 `SizedBox` 約 102-111 行、右側欄 `SizedBox` 約 117-142 行、`Expanded(_Bar)` 約 113-115 行）。
- **Modify (test):** `test/widgets/cards/banner_top_rarity_bars_test.dart` — 為共用 `_wrap` helper 加可選 `locale` / `width` / `height` 具名參數（預設值維持既有行為，既有測試呼叫點不變），並新增一個 no-truncation 測試。

既有測試以完整文字 `find.text(...)`、`·` 數量、`widthFactor`、漸層顏色斷言；本變更不動文字內容與 bar 比例，既有測試應全數續過，**不修改既有測試案例**。

---

### Task 1: 新增 no-truncation 失敗測試

**Files:**
- Test: `test/widgets/cards/banner_top_rarity_bars_test.dart`

說明：`find.text('...')` 比對的是 `Text` widget 的 `data` 屬性，而非實際渲染像素 —— 即使目前有 `overflow: ellipsis`，`find.text` 仍找得到完整字串，無法用來證明「截斷已修好」。因此測試契約改為直接斷言設計決策：名稱與 subtitle 的 `Text` **不得**有 `TextOverflow.ellipsis`，且 bar 仍渲染、版面不丟 overflow 例外。

- [ ] **Step 1: 為 `_wrap` 加可選具名參數（不改既有呼叫點）**

把 `test/widgets/cards/banner_top_rarity_bars_test.dart` 的 `_wrap` 由：

```dart
Widget _wrap(Widget Function(BuildContext ctx, BannerColors colors) build) =>
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 280,
          child: Builder(
            builder: (ctx) {
              final colors = BannerColors.of(Theme.of(ctx).brightness);
              return build(ctx, colors);
            },
          ),
        ),
      ),
    );
```

改為（新增 `locale` / `width` / `height` 具名參數，預設值等同舊行為，既有測試以單一位置參數呼叫不受影響）：

```dart
Widget _wrap(
  Widget Function(BuildContext ctx, BannerColors colors) build, {
  Locale? locale,
  double width = 800,
  double height = 280,
}) =>
    MaterialApp(
      theme: buildDarkTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: Builder(
            builder: (ctx) {
              final colors = BannerColors.of(Theme.of(ctx).brightness);
              return build(ctx, colors);
            },
          ),
        ),
      ),
    );
```

- [ ] **Step 2: 新增失敗測試**

在 `test/widgets/cards/banner_top_rarity_bars_test.dart` 的 `main()` 內，最後一個 `testWidgets(...)` 之後、`}` 之前，加入：

```dart
  testWidgets('英文窄視窗：名稱/說明不截斷（無 ellipsis）、bar 仍渲染', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        (ctx, colors) => BannerTopRarityBars(
          types: gachaTypes,
          banners: const {},
          colors: colors,
        ),
        locale: const Locale('en'),
        width: 360, // 刻意窄，逼出換行
      ),
    );
    await tester.pumpAndSettle();

    // 名稱 Text 不得有 ellipsis（完整換行顯示）
    final nameText = tester.widget<Text>(find.text('Character Event Wish'));
    expect(nameText.overflow, isNot(TextOverflow.ellipsis));

    // 右側 subtitle Text 不得有 ellipsis（空 banners → "No 5★ yet"，取第一個）
    final subtitleText = tester
        .widgetList<Text>(find.text('No 5★ yet'))
        .first;
    expect(subtitleText.overflow, isNot(TextOverflow.ellipsis));

    // bar 仍每列渲染
    expect(
      find.descendant(
        of: find.byType(BannerTopRarityBars),
        matching: find.byType(FractionallySizedBox),
      ),
      findsNWidgets(gachaTypes.length),
    );

    // 版面未拋 overflow 例外
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/widgets/cards/banner_top_rarity_bars_test.dart -r expanded`
Expected: 新測試 FAIL —— `nameText.overflow` / `subtitleText.overflow` 目前為 `TextOverflow.ellipsis`，`isNot(TextOverflow.ellipsis)` 斷言失敗（`Expected: not TextOverflow.ellipsis  Actual: TextOverflow.ellipsis`）。其餘既有測試 PASS。

- [ ] **Step 4: Commit**

```bash
git add test/widgets/cards/banner_top_rarity_bars_test.dart
git commit -m @'
test(banner-bars): add no-truncation widget test for wrap layout

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

### Task 2: 實作換行版面（名稱/說明加寬不截斷、bar 縮短）

**Files:**
- Modify: `lib/widgets/cards/banner_top_rarity_bars.dart`（`_BannerRow.build`）

像素值 `120` / `180` / `56` 為起始值。實作完成後，實作者須以 en / ja / zh / zh_Hans 最長卡池名稱與最長 subtitle 實際渲染目視對照，微調到「常見 CJK 單行、英日約兩行、bar 仍有合理可比寬度」後定稿，並更新註解說明調校依據。測試契約（無 ellipsis、bar 渲染、無 overflow 例外）不依賴確切像素值，故微調不影響測試。

- [ ] **Step 1: 改名稱欄 —— 加寬、移除 ellipsis、允許換行**

在 `lib/widgets/cards/banner_top_rarity_bars.dart`，把 `_BannerRow.build` 內的名稱 `SizedBox` 由：

```dart
        SizedBox(
          width:
              96, // name label column, tuned for longest banner name at bodyMedium
          child: Text(
            name,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
```

改為：

```dart
        SizedBox(
          width:
              120, // name label column; tuned so longest CJK name fits one
          // line and English wraps (~2 lines) without truncation
          child: Text(
            name,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.right,
          ),
        ),
```

- [ ] **Step 2: 改右側件數·說明欄 —— 加寬、移除 subtitle ellipsis**

把 `_BannerRow.build` 內右側欄由：

```dart
        SizedBox(
          width: 156, // count + separator + subtitle (ellipsis) column
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$topCount',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text('·', style: TextStyle(color: tokens.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
```

改為（移除 subtitle 的 `overflow: TextOverflow.ellipsis`，欄寬 `156`→`180`，註解更新）：

```dart
        SizedBox(
          width: 180, // count + separator + subtitle column; subtitle wraps
          // freely (no ellipsis) so it is never truncated in any locale
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$topCount',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text('·', style: TextStyle(color: tokens.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
```

- [ ] **Step 3: 改 bar —— 加最小寬度防窄視窗塌陷**

把 `_BannerRow.build` 內：

```dart
        Expanded(
          child: _Bar(color: color, ratio: ratio),
        ),
```

改為：

```dart
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: _Bar(color: color, ratio: ratio),
          ),
        ),
```

- [ ] **Step 4: 跑新測試確認通過**

Run: `flutter test test/widgets/cards/banner_top_rarity_bars_test.dart -r expanded`
Expected: PASS（含新測試與所有既有測試）。

- [ ] **Step 5: 提交前品質檢查（依 CLAUDE.md）**

依序執行，全部須通過：

```bash
dart format lib/ test/
flutter analyze
flutter test
```

Expected:
- `dart format` 完成（有重排則照單全收）
- `flutter analyze` → `No issues found!`
- `flutter test` → `All tests passed!`

任何一項失敗先修再繼續，不得 `--no-verify`。

- [ ] **Step 6: 實作者目視微調像素值（en / ja / zh / zh_Hans）**

跑起 app 切換 en / ja / zh / zh_Hans，檢視 Overview 頁「Highest rarity count per banner」卡片：確認最長卡池名稱與最長 subtitle 不被截斷、常見情境約 1~2 行、bar 仍有合理可比寬度。如需調整 `120` / `180` / `56`，直接改常數並同步更新該行註解的調校說明。改完重跑 Step 5 三項檢查確認仍全綠。

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/cards/banner_top_rarity_bars.dart
git commit -m @'
fix(banner-bars): wrap name/subtitle instead of truncating, shrink bar

Name and right-side count·subtitle columns are widened and no longer
ellipsis-truncated; they wrap freely so non-CJK locales show full text.
The bar shrinks to make room and keeps a minWidth so it never collapses
on narrow windows. No data/logic changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
'@
```

---

## Self-Review

**1. Spec coverage：**
- 名稱欄加寬 + 移除 ellipsis + 自由換行 → Task 2 Step 1 ✅
- 右側說明欄加寬 + 移除 subtitle ellipsis、`件數·` 留首行 → Task 2 Step 2 ✅
- bar `ConstrainedBox(minWidth)` → Task 2 Step 3 ✅
- 列 `crossAxisAlignment: center` → 既有 `Row` 預設即 center，無需改動，spec 已載明「維持」，無對應變更步驟正確 ✅
- 不動資料 / 邏輯 / `overview_page.dart` → 三步皆只動版面、未列其他檔案 ✅
- 既有測試不修改、須續過 → Task 1 Step 1 僅對 `_wrap` 加「預設值等同舊行為」的可選參數，既有案例呼叫點不變 ✅
- 新增 no-truncation 測試（完整字串 + bar 渲染）→ Task 1 Step 2 ✅
- 提交前 format / analyze / test → Task 2 Step 5 ✅
- 像素值實測微調 → Task 2 Step 6 ✅

**2. Placeholder scan：** 無 TBD/TODO，所有改碼步驟皆附完整程式碼。✅

**3. Type consistency：** 全程僅 `BannerTopRarityBars` / `_BannerRow` / `_Bar` / `_wrap`，簽名與屬性（`overflow`、`minWidth`、`FractionallySizedBox`）一致。✅

無待修缺口。
