# 星級寫法 i18n 收斂 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 程式碼硬寫死的 `N★` 星級標籤改用單一 i18n key `rarityStar`，日文正確顯示 `★N`。

**Architecture:** 在 template `app_zh.arb` 與三個維護 locale 檔新增 `rarityStar` key（zh/zh_Hans/en = `{rank}★`，ja = `★{rank}`），gen-l10n 產生的 `AppLocalizations.rarityStar(int rank)` 即唯一 helper；把 `rarity_pie.dart` / `overview_page.dart` / `sortable_table.dart` 中硬寫的 `N★` 全改為呼叫它，並修正受影響的既有測試。

**Tech Stack:** Flutter gen-l10n、ARB、flutter_test、Python（既有 verify_arb 腳本）。

**參考 spec:** `docs/superpowers/specs/2026-05-17-rarity-star-order-i18n-design.md`

**版控注意:** 本 plan 與 spec 沿用 `docs/superpowers` gitignored 慣例，不進版控、不 git add。交付物為 4 個 arb 檔 + 3 個 dart 檔 + 2 個 test 檔。

---

## 前置事實（執行前確認，勿假設）

- 4 個 arb 檔（`app_zh.arb` template、`app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`）皆為：第 103 行 `"tableRarity": "<值>",`、第 104 行 `"tableTotalIndex": "<值>",`。`rarityStar` 插在這兩行之間。
- template `@`-metadata 多行格式範例（`app_zh.arb` 107-109 行 `@tableMainPityTooltip`）：
  ```
    "@tableMainPityTooltip": {
      "placeholders": { "rank": { "type": "int" } }
    },
  ```
- 維護 locale 檔依慣例鏡像 template 的 `@`-metadata；故 4 檔都加 `"rarityStar"` 值 + 照抄的 `"@rarityStar"` 區塊。其餘 `fr/es/pt/th/vi` 不加（gen-l10n runtime 回退 template `{rank}★`，對這些語言皆正確；`flutter analyze` 不把 untranslated 當錯，先前已驗證）。
- gen-l10n 在 `flutter analyze` / `flutter test` / `flutter gen-l10n` 時重產 `lib/l10n/generated/app_localizations.dart`。`int` placeholder 無 `format` → 產生 `String rarityStar(int rank)`，值以一般插值（rank 2–5 無位數分組問題）。
- `rarityDistributionEntries` 現簽章 `rarityDistributionEntries(WishStats stats, GachaTokens tokens)`（`lib/widgets/rarity_pie.dart:15`）。呼叫點：`lib/pages/banner_page.dart:219`、`lib/pages/overview_page.dart:294`，兩處 build 內皆有 `final l = AppLocalizations.of(context)!;`（banner_page:51、overview_page:32）。
- `lib/widgets/data/sortable_table.dart`：第 295 行 row build 所在類別有欄位 `final AppLocalizations l;`（第 292 行），故 335 行可用 `l`。`_Pill`（359 行）為 `StatelessWidget` 無 `l`，其 `build` 內需自取。檔案已 import `app_localizations.dart`（51 行用 `AppLocalizations.of`）。
- **既有測試會被破壞**：`test/widgets/rarity_pie_test.dart` 有 5 個測試呼叫 2-arg `rarityDistributionEntries(stats, GachaTokens.dark)` 並斷言 `entries[*].name == '5★'` 等 — 改 3-arg 後會編譯失敗且字面失效，Task 2 必須一併修正（zh 載入下 `'5★'` 仍正確）。`test/widgets/data/sortable_table_test.dart` 既有測試在 zh 下斷言 `find.text('5★')`，zh 不變仍有效，只需新增 ja 測試。

---

### Task 1: 新增 `rarityStar` ARB key 並驗證 gen-l10n

**Files:**
- Modify: `lib/l10n/app_zh.arb`、`lib/l10n/app_zh_Hans.arb`、`lib/l10n/app_en.arb`、`lib/l10n/app_ja.arb`（各於 `tableRarity` 後插入）
- Create: `test/l10n/rarity_star_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/l10n/rarity_star_test.dart`：

```dart
// test/l10n/rarity_star_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  group('AppLocalizations.rarityStar', () {
    test('zh / en / zh_Hans 為 {rank}★ 順序', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.rarityStar(5), '5★');
      expect(zh.rarityStar(2), '2★');

      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.rarityStar(4), '4★');

      final hans = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(hans.rarityStar(3), '3★');
    });

    test('ja 為 ★{rank} 順序', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.rarityStar(5), '★5');
      expect(ja.rarityStar(4), '★4');
      expect(ja.rarityStar(3), '★3');
      expect(ja.rarityStar(2), '★2');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/l10n/rarity_star_test.dart`
Expected: 編譯失敗 —「The method 'rarityStar' isn't defined for the type 'AppLocalizations'」（key 尚未加、未產碼）。

- [ ] **Step 3: 在 template 加 key**

`lib/l10n/app_zh.arb`，在 `"tableRarity": "稀有度",` 與 `"tableTotalIndex": "總抽數",` 之間插入：

old:
```
  "tableRarity": "稀有度",
  "tableTotalIndex": "總抽數",
```
new:
```
  "tableRarity": "稀有度",
  "rarityStar": "{rank}★",
  "@rarityStar": {
    "placeholders": { "rank": { "type": "int" } }
  },
  "tableTotalIndex": "總抽數",
```

- [ ] **Step 4: 在三個維護 locale 檔加 key（值不同、metadata 照抄）**

`lib/l10n/app_zh_Hans.arb`，在 `"tableRarity": "稀有度",` 後插入：
```
  "rarityStar": "{rank}★",
  "@rarityStar": {
    "placeholders": { "rank": { "type": "int" } }
  },
```
（其下原本就是 `"tableTotalIndex": "总抽数",`）

`lib/l10n/app_en.arb`，在 `"tableRarity": "Rarity",` 後插入同上的
```
  "rarityStar": "{rank}★",
  "@rarityStar": {
    "placeholders": { "rank": { "type": "int" } }
  },
```

`lib/l10n/app_ja.arb`，在 `"tableRarity": "レアリティ",` 後插入（**值為 `★{rank}`**）：
```
  "rarityStar": "★{rank}",
  "@rarityStar": {
    "placeholders": { "rank": { "type": "int" } }
  },
```

- [ ] **Step 5: 重新產碼**

Run: `flutter gen-l10n`
Expected: 正常結束，無錯；`lib/l10n/generated/app_localizations.dart` 出現 `rarityStar` 方法。

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/l10n/rarity_star_test.dart`
Expected: All tests passed!（zh/en/zh_Hans = `5★`…，ja = `★5`…）

- [ ] **Step 7: key 集合一致性檢查**

Run: `set PYTHONUTF8=1 && python docs/superpowers/verify_arb_2026-05-17.py`
Expected: 印 `PASS`、exit 0（三維護檔 key 集合仍 == template，含新 `rarityStar`；placeholder `rank` 一致）。

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/generated/app_localizations.dart test/l10n/rarity_star_test.dart
git commit -m "feat(i18n): add rarityStar key for locale-aware star order

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```
（若 `lib/l10n/generated/` 為 gitignored 則該檔不會被 add，照常 commit 其餘；不要 git add docs/superpowers）

---

### Task 2: 收斂 rarity_pie 與 overview_page 的硬寫 N★

**Files:**
- Modify: `lib/widgets/rarity_pie.dart:15-46`
- Modify: `lib/pages/banner_page.dart:219`
- Modify: `lib/pages/overview_page.dart:123,128,294`
- Modify: `test/widgets/rarity_pie_test.dart`（修 5 個既有測試 + 加 ja 測試）

- [ ] **Step 1: 改既有測試為失敗狀態（TDD：先讓測試表達新行為）**

整檔覆寫 `test/widgets/rarity_pie_test.dart` 為：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

void main() {
  group('rarityDistributionEntries', () {
    late AppLocalizations zh;
    late AppLocalizations ja;

    setUp(() async {
      zh = await AppLocalizations.delegate.load(const Locale('zh'));
      ja = await AppLocalizations.delegate.load(const Locale('ja'));
    });

    test('returns 5★/4★/3★ entries with correct counts and rates (zh)', () {
      const stats = WishStats(
        total: 100,
        fiveStarCount: 1,
        fourStarCount: 9,
        threeStarCount: 90,
        twoStarCount: 0,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, zh);
      expect(entries, hasLength(3));
      expect(entries[0].name, '5★');
      expect(entries[0].count, 1);
      expect(entries[0].rate, closeTo(0.01, 1e-9));
      expect(entries[0].color, GachaTokens.dark.fiveStar);
      expect(entries[1].name, '4★');
      expect(entries[1].count, 9);
      expect(entries[2].name, '3★');
      expect(entries[2].count, 90);
    });

    test('包含 2★ 當 twoStarCount > 0 (zh)', () {
      const stats = WishStats(
        total: 10,
        fiveStarCount: 1,
        fourStarCount: 2,
        threeStarCount: 5,
        twoStarCount: 2,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, zh);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★', '2★']);
      expect(entries.last.count, 2);
      expect(entries.last.rate, closeTo(0.2, 1e-9));
      expect(entries.last.color, GachaTokens.dark.twoStar);
    });

    test('略過 2★ 當 twoStarCount == 0 (zh)', () {
      const stats = WishStats(
        total: 8,
        fiveStarCount: 1,
        fourStarCount: 2,
        threeStarCount: 5,
        twoStarCount: 0,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, zh);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★']);
    });

    test('threeStarCount 不再包含 2★（獨立計算, zh）', () {
      const stats = WishStats(
        total: 6,
        fiveStarCount: 0,
        fourStarCount: 1,
        threeStarCount: 3,
        twoStarCount: 2,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, zh);
      final three = entries.firstWhere((e) => e.name == '3★');
      expect(three.count, 3);
      expect(three.rate, closeTo(3 / 6, 1e-9));
      final two = entries.firstWhere((e) => e.name == '2★');
      expect(two.count, 2);
      expect(two.rate, closeTo(2 / 6, 1e-9));
    });

    test('keeps zero-count entries when twoStar absent (zh)', () {
      const stats = WishStats(
        total: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        threeStarCount: 0,
        twoStarCount: 0,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, zh);
      expect(entries, hasLength(3));
      expect(entries.every((e) => e.count == 0), isTrue);
    });

    test('ja 用 ★N 順序', () {
      const stats = WishStats(
        total: 10,
        fiveStarCount: 1,
        fourStarCount: 2,
        threeStarCount: 5,
        twoStarCount: 2,
        byItemType: {},
      );
      final entries = rarityDistributionEntries(stats, GachaTokens.dark, ja);
      expect(entries.map((e) => e.name).toList(), ['★5', '★4', '★3', '★2']);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/rarity_pie_test.dart`
Expected: 編譯失敗 —「too many positional arguments: 2 expected, but 3 found」（簽章還是 2-arg）。

- [ ] **Step 3: 改 `rarityDistributionEntries` 簽章與值**

`lib/widgets/rarity_pie.dart`，將：

```dart
List<DistributionEntry> rarityDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
) {
  return [
    DistributionEntry(
      color: tokens.fiveStar,
      name: '5★',
      count: stats.fiveStarCount,
      rate: stats.fiveStarRate,
    ),
    DistributionEntry(
      color: tokens.fourStar,
      name: '4★',
      count: stats.fourStarCount,
      rate: stats.fourStarRate,
    ),
    DistributionEntry(
      color: tokens.threeStar,
      name: '3★',
      count: stats.threeStarCount,
      rate: stats.threeStarRate,
    ),
    if (stats.twoStarCount > 0)
      DistributionEntry(
        color: tokens.twoStar,
        name: '2★',
        count: stats.twoStarCount,
        rate: stats.twoStarRate,
      ),
  ];
}
```

改為：

```dart
List<DistributionEntry> rarityDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
  AppLocalizations l,
) {
  return [
    DistributionEntry(
      color: tokens.fiveStar,
      name: l.rarityStar(5),
      count: stats.fiveStarCount,
      rate: stats.fiveStarRate,
    ),
    DistributionEntry(
      color: tokens.fourStar,
      name: l.rarityStar(4),
      count: stats.fourStarCount,
      rate: stats.fourStarRate,
    ),
    DistributionEntry(
      color: tokens.threeStar,
      name: l.rarityStar(3),
      count: stats.threeStarCount,
      rate: stats.threeStarRate,
    ),
    if (stats.twoStarCount > 0)
      DistributionEntry(
        color: tokens.twoStar,
        name: l.rarityStar(2),
        count: stats.twoStarCount,
        rate: stats.twoStarRate,
      ),
  ];
}
```

（`app_localizations.dart` 已於檔案 4 行 import，無需新增 import。）

- [ ] **Step 4: 更新兩個呼叫點傳入 `l`**

`lib/pages/banner_page.dart:219`，將
`entries: rarityDistributionEntries(stats, tokens),`
改為
`entries: rarityDistributionEntries(stats, tokens, l),`

`lib/pages/overview_page.dart:294`，將
`entries: rarityDistributionEntries(stats, tokens),`
改為
`entries: rarityDistributionEntries(stats, tokens, l),`

- [ ] **Step 5: 改 overview_page 的 odes 標籤 123/128**

`lib/pages/overview_page.dart`：
- 第 123 行 `label: '${odesEventType.resolveName(l)} 5★',`
  → `label: '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',`
- 第 128 行 `label: '${odesStandardType.resolveName(l)} 4★',`
  → `label: '${odesStandardType.resolveName(l)} ${l.rarityStar(4)}',`

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/widgets/rarity_pie_test.dart`
Expected: All tests passed!（zh 仍 `5★…`；新 ja 測試得 `★5/★4/★3/★2`）

- [ ] **Step 7: analyze 確認無破壞**

Run: `flutter analyze lib/widgets/rarity_pie.dart lib/pages/banner_page.dart lib/pages/overview_page.dart`
Expected: No issues found!（呼叫點簽章一致、無未用 import）

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/rarity_pie.dart lib/pages/banner_page.dart lib/pages/overview_page.dart test/widgets/rarity_pie_test.dart
git commit -m "refactor(i18n): rarity_pie/overview use rarityStar for star order

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 收斂 sortable_table 的硬寫 N★

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart:335` 與 `_Pill.build`（約 365-380 行）
- Modify: `test/widgets/data/sortable_table_test.dart`（新增 ja 測試）

- [ ] **Step 1: 寫失敗測試（ja 下 rank cell 為 ★N）**

在 `test/widgets/data/sortable_table_test.dart` 的 `void main() {` 之後、第一個 `testWidgets` 之前，新增一個 ja 專用 wrap 與測試。先在檔案頂部既有 `_wrap` 函式**之後**新增：

```dart
Widget _wrapJa(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  locale: const Locale('ja'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 1200, child: child)),
  ),
);
```

在 `void main() {` 內，第一個 `testWidgets(...)` 之前新增：

```dart
  testWidgets('ja locale → rank cell uses ★N order (pill + plain)', (
    tester,
  ) async {
    final records = [
      _r(id: '5', rank: 5, name: 'A'), // accent != null → _Pill
      _r(id: '4', rank: 4, name: 'B'), // accent != null → _Pill
      _r(id: '3', rank: 3, name: 'C'), // accent == null → 純 Text 分支
    ];
    final rows = buildRecordRows(records);
    await tester.pumpWidget(
      _wrapJa(
        SortableTable(
          rows: rows,
          sort: null,
          mainRank: 5,
          onSortColumnTapped: (_) {},
        ),
      ),
    );
    expect(find.text('★5'), findsOneWidget);
    expect(find.text('★4'), findsOneWidget);
    expect(find.text('★3'), findsOneWidget);
    expect(find.text('5★'), findsNothing);
    expect(find.text('4★'), findsNothing);
    expect(find.text('3★'), findsNothing);
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/data/sortable_table_test.dart`
Expected: 新測試 FAIL —「Expected: exactly one matching node... Found: 0」對 `★5`（程式碼仍輸出 `5★`）。既有 zh 測試仍 PASS。

- [ ] **Step 3: 改 335 行純 Text 分支**

`lib/widgets/data/sortable_table.dart`，將：
```dart
                : Text('${record.rankType}★'),
```
改為：
```dart
                : Text(l.rarityStar(record.rankType)),
```
（該 build 所在類別有欄位 `final AppLocalizations l;`，`l` 直接可用。）

- [ ] **Step 4: 改 `_Pill` 用 rarityStar**

`lib/widgets/data/sortable_table.dart` `_Pill.build`，將：
```dart
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$rank★',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
```
改為：
```dart
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          l.rarityStar(rank),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
```

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/widgets/data/sortable_table_test.dart`
Expected: All tests passed!（新 ja 測試得 `★5/★4/★3`；既有 zh 測試 `5★/4★` 仍 PASS）

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/data/sortable_table.dart test/widgets/data/sortable_table_test.dart
git commit -m "refactor(i18n): sortable_table rank cell uses rarityStar

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: 全量驗證

**Files:** 無新增改動，僅驗證。

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 正常結束（勿對 `.` 跑）。若有檔案被改動，`git add` 該檔並 `git commit -m "style: dart format"`。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: ARB 一致性**

Run: `set PYTHONUTF8=1 && python docs/superpowers/verify_arb_2026-05-17.py`
Expected: `PASS`、exit 0。

- [ ] **Step 5: 任一失敗先修**

任一步未達預期，定位修正對應檔（不可改 `app_zh.arb` 既有 key、不可 `--no-verify`），回 Step 1 重跑直到全綠。全綠即完成（前面 Task 已各自 commit，無額外 commit）。

---

## Self-Review

**Spec coverage：**
- 單一 ARB key `rarityStar`（zh/zh_Hans/en=`{rank}★`、ja=`★{rank}`）+ 插入點固定於 `tableRarity` 後 → Task 1 Step 3-4。
- 維持 locale 鏡像 template、不動 fr/es/pt/th/vi → Task 1 只改 4 檔、Step 7 verify。
- rarity_pie 簽章加 `l` + 4 個 name 改 `l.rarityStar(n)` + 兩呼叫點 → Task 2 Step 3-4。
- overview_page 123/128 → Task 2 Step 5。
- sortable_table 335 + `_Pill` → Task 3 Step 3-4。
- 測試（rarityStar en/ja 單元、RarityPie entries ja、sortable_table ja 雙分支）→ Task 1 Step 1、Task 2 Step 1（含修 5 個既有破壞測試）、Task 3 Step 1。
- 不重構 ARB 內嵌句子、不加抽象層 → 計畫無此步，與 YAGNI 段一致。
- CLAUDE.md 驗證序列 → Task 4。
- docs/superpowers 不進版控 → header 與各 commit step 標明。

**Placeholder scan：** 無 TBD/TODO；所有 code/test step 附完整程式碼與精確 old/new；指令附預期輸出。

**Type consistency：** `rarityStar(int rank)` 簽章跨 Task 1/2/3 一致；`rarityDistributionEntries(WishStats, GachaTokens, AppLocalizations)` 三參數順序在 Task 2 定義並於兩呼叫點、測試一致；`_Pill` 仍 `rank` int 欄位、改用 `l.rarityStar(rank)` 一致。

無待修項。
