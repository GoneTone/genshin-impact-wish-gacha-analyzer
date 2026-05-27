# 星等字串改用 rarityStar 組合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把翻譯檔中寫死的星等（`5★`/`4★`/`3★`、各語言自排的 `{rank}★`/`★{rank}`）全部改由既有 locale-aware `rarityStar(rank)` 組合產生。

**Architecture:** ARB 受影響訊息只留單一 `{star}` String placeholder，Dart 呼叫端傳入 `l.rarityStar(rank)`。B 組寫死數字的 getter 對 collapse 成參數化方法。`PityRule.labelKey` 與 `_pityLabel` switch 一併移除（改由 `PityRule.rank` 驅動）。

**Tech Stack:** Flutter / Dart、`flutter gen_l10n`（`l10n.yaml`，`template-arb-file: app_zh.arb`）、`flutter_test`。

**前提事實：** 完整語言只有 `en/ja/zh/zh_Hans`（各 261 key）。`es/fr/pt/th/vi` 大量 fallback zh 模板。受影響 key 中，只有 A 組 7 key 與 B 組 `pity*Star`/`filterRarity*Star` 僅定義於 4 完整語言；`statsFiveStarCount`/`statsFourStarCount` 額外定義於 `es/fr/pt/th`（需遷移，非刪除），`vi` 無。

**重要慣例：**
- ARB 改完一定要跑 `flutter gen-l10n` 重新產生 `lib/l10n/generated/*`，且這些 generated 檔有進版控，要一起 commit。
- 每個 task 結尾的提交前品質檢查（依 CLAUDE.md）必須全綠才 commit：
  1. `dart format lib/ test/`（不要對 `.` 跑）
  2. `flutter analyze` → `No issues found!`
  3. `flutter test` → `All tests passed!`
- 本 plan 檔位於 `docs/superpowers/`，**不要 git add／不要 commit 此檔**。只 commit `lib/` 與 `test/` 變更。
- 含 `{n}` 的方法 placeholder 宣告順序固定為 `star` 在前、`n` 在後，使產生的方法簽章為 `(String star, int n)`，呼叫端把原 `rank` 引數位置換成 `l.rarityStar(rank)`、其餘不動。

---

## Task 1: A 組 — 7 個 `{rank}` key 改 `{star}` placeholder

把已帶 `{rank}` 的 7 個 key 改為 `{star}` (String)，移除字串內 `★`，只動 `en/ja/zh/zh_Hans`。涉及 key：`tableMainPityTooltip`、`pityNoMainRarity`、`timelineNoRecordsForRank`、`timelineNowSinceLast`、`timelineNowSinceCrossPool`、`timelineTopRarityTitle`、`bannerTopRarityPullsSinceLast`。

**Files:**
- Modify: `lib/l10n/app_en.arb`、`lib/l10n/app_ja.arb`、`lib/l10n/app_zh.arb`、`lib/l10n/app_zh_Hans.arb`
- Modify (call sites): `lib/widgets/data/sortable_table.dart:196`、`lib/widgets/cards/banner_top_rarity_bars.dart:47,54`、`lib/widgets/cards/pity_card.dart:203`、`lib/widgets/cards/timeline_vertical.dart:119,346,347`、`lib/widgets/cards/timeline_horizontal.dart:131`、`lib/pages/banner_page.dart:241`、`lib/pages/overview_page.dart:365`
- Test: `test/widgets/cards/banner_top_rarity_bars_test.dart`、`test/widgets/cards/timeline_horizontal_test.dart`、`test/widgets/cards/timeline_vertical_test.dart`

- [ ] **Step 1: 改 `app_en.arb`（值 + @metadata）**

逐一用 Edit 工具替換（old → new）：

```
"tableMainPityTooltip": "Pulls since the last {rank}★",
→ "tableMainPityTooltip": "Pulls since the last {star}",

"pityNoMainRarity": "No {rank}★ yet",
→ "pityNoMainRarity": "No {star} yet",

"timelineNoRecordsForRank": "No {rank}★ records",
→ "timelineNoRecordsForRank": "No {star} records",

"timelineNowSinceLast": "{n} pulls since last {rank}★",
→ "timelineNowSinceLast": "{n} pulls since last {star}",

"timelineNowSinceCrossPool": "{n} pulls since last {rank}★ across banners",
→ "timelineNowSinceCrossPool": "{n} pulls since last {star} across banners",

"timelineTopRarityTitle": "{rank}★ Timeline ({n})",
→ "timelineTopRarityTitle": "{star} Timeline ({n})",

"bannerTopRarityPullsSinceLast": "{n} pulls since last {rank}★",
→ "bannerTopRarityPullsSinceLast": "{n} pulls since last {star}",
```

@metadata：3 個單 placeholder key 改型別：

```
"@tableMainPityTooltip": {
    "placeholders": { "rank": { "type": "int" } }
→  "placeholders": { "star": { "type": "String" } }
```
（`@pityNoMainRarity`、`@timelineNoRecordsForRank` 同樣 `{ "rank": { "type": "int" } }` → `{ "star": { "type": "String" } }`）

4 個雙 placeholder key，把 `rank` 那行改成 `star` 並保持在 `n` 前面：

```
"@timelineNowSinceLast": {
    "placeholders": {
      "rank": { "type": "int" },
      "n": { "type": "int" }
    }
→  "placeholders": {
      "star": { "type": "String" },
      "n": { "type": "int" }
    }
```
（`@timelineNowSinceCrossPool`、`@timelineTopRarityTitle`、`@bannerTopRarityPullsSinceLast` 同型一併比照）

- [ ] **Step 2: 改 `app_ja.arb`（值；@metadata 同 Step 1 的型別調整）**

```
"tableMainPityTooltip": "前回の ★{rank} からの回数",
→ "tableMainPityTooltip": "前回の {star} からの回数",

"pityNoMainRarity": "★{rank} はまだありません",
→ "pityNoMainRarity": "{star} はまだありません",

"timelineNoRecordsForRank": "★{rank} の記録はまだありません",
→ "timelineNoRecordsForRank": "{star} の記録はまだありません",

"timelineNowSinceLast": "前回の ★{rank} から {n} 回",
→ "timelineNowSinceLast": "前回の {star} から {n} 回",

"timelineNowSinceCrossPool": "前回の ★{rank} から現在まで {n} 回",
→ "timelineNowSinceCrossPool": "前回の {star} から現在まで {n} 回",

"timelineTopRarityTitle": "★{rank} タイムライン（{n}）",
→ "timelineTopRarityTitle": "{star} タイムライン（{n}）",

"bannerTopRarityPullsSinceLast": "前回の ★{rank} から {n} 回",
→ "bannerTopRarityPullsSinceLast": "前回の {star} から {n} 回",
```
@metadata 比照 Step 1（`rank`→`star`、型別 `int`→`String`、雙 placeholder 保持 `star` 在 `n` 前）。

- [ ] **Step 3: 改 `app_zh.arb`（值 + @metadata 同型調整）**

```
"tableMainPityTooltip": "距上一次 {rank}★ 的抽數",
→ "tableMainPityTooltip": "距上一次 {star} 的抽數",

"pityNoMainRarity": "暫無 {rank}★",
→ "pityNoMainRarity": "暫無 {star}",

"timelineNoRecordsForRank": "暫無 {rank}★ 紀錄",
→ "timelineNoRecordsForRank": "暫無 {star} 紀錄",

"timelineNowSinceLast": "距上次 {rank}★ {n} 抽",
→ "timelineNowSinceLast": "距上次 {star} {n} 抽",

"timelineNowSinceCrossPool": "從上次 {rank}★ 至今 {n} 抽",
→ "timelineNowSinceCrossPool": "從上次 {star} 至今 {n} 抽",

"timelineTopRarityTitle": "{rank}★ 時間軸 ({n})",
→ "timelineTopRarityTitle": "{star} 時間軸 ({n})",

"bannerTopRarityPullsSinceLast": "距上次 {rank}★ {n} 抽",
→ "bannerTopRarityPullsSinceLast": "距上次 {star} {n} 抽",
```
@metadata 比照 Step 1。

- [ ] **Step 4: 改 `app_zh_Hans.arb`（值 + @metadata 同型調整）**

```
"tableMainPityTooltip": "距上一次 {rank}★ 的抽数",
→ "tableMainPityTooltip": "距上一次 {star} 的抽数",

"pityNoMainRarity": "暂无 {rank}★",
→ "pityNoMainRarity": "暂无 {star}",

"timelineNoRecordsForRank": "暂无 {rank}★ 记录",
→ "timelineNoRecordsForRank": "暂无 {star} 记录",

"timelineNowSinceLast": "距上次 {rank}★ {n} 抽",
→ "timelineNowSinceLast": "距上次 {star} {n} 抽",

"timelineNowSinceCrossPool": "从上次 {rank}★ 至今 {n} 抽",
→ "timelineNowSinceCrossPool": "从上次 {star} 至今 {n} 抽",

"timelineTopRarityTitle": "{rank}★ 时间轴 ({n})",
→ "timelineTopRarityTitle": "{star} 时间轴 ({n})",

"bannerTopRarityPullsSinceLast": "距上次 {rank}★ {n} 抽",
→ "bannerTopRarityPullsSinceLast": "距上次 {star} {n} 抽",
```
@metadata 比照 Step 1。

- [ ] **Step 5: 重新產生 l10n**

Run: `flutter gen-l10n`
Expected: 無錯誤輸出；`lib/l10n/generated/*` 中相關方法簽章變為 `tableMainPityTooltip(String star)`、`timelineNowSinceLast(String star, int n)` 等。

- [ ] **Step 6: 改呼叫端，把原 `rank` 引數包成 `l.rarityStar(...)`**

`lib/widgets/data/sortable_table.dart:196`
```dart
tooltip: l.tableMainPityTooltip(mainRank),
→ tooltip: l.tableMainPityTooltip(l.rarityStar(mainRank)),
```

`lib/widgets/cards/banner_top_rarity_bars.dart:47`
```dart
subtitle = l.pityNoMainRarity(type.primaryPity.rank);
→ subtitle = l.pityNoMainRarity(l.rarityStar(type.primaryPity.rank));
```

`lib/widgets/cards/banner_top_rarity_bars.dart:54-57`
```dart
subtitle = l.bannerTopRarityPullsSinceLast(
  type.primaryPity.rank,
  pity,
);
→ subtitle = l.bannerTopRarityPullsSinceLast(
  l.rarityStar(type.primaryPity.rank),
  pity,
);
```

`lib/widgets/cards/pity_card.dart:203`
```dart
? (l.pityNoMainRarity(rank), tokens.textMuted)
→ ? (l.pityNoMainRarity(l.rarityStar(rank)), tokens.textMuted)
```

`lib/widgets/cards/timeline_vertical.dart:119`
```dart
l.timelineNoRecordsForRank(targetRank),
→ l.timelineNoRecordsForRank(l.rarityStar(targetRank)),
```

`lib/widgets/cards/timeline_vertical.dart:346-347`
```dart
? l.timelineNowSinceCrossPool(targetRank, nowPulls)
: l.timelineNowSinceLast(targetRank, nowPulls);
→ ? l.timelineNowSinceCrossPool(l.rarityStar(targetRank), nowPulls)
: l.timelineNowSinceLast(l.rarityStar(targetRank), nowPulls);
```

`lib/widgets/cards/timeline_horizontal.dart:131`
```dart
l.timelineNoRecordsForRank(widget.targetRank),
→ l.timelineNoRecordsForRank(l.rarityStar(widget.targetRank)),
```

`lib/pages/banner_page.dart:241-244`
```dart
title: l.timelineTopRarityTitle(
  primary.rank,
  _countAtRank(stats, primary.rank),
),
→ title: l.timelineTopRarityTitle(
  l.rarityStar(primary.rank),
  _countAtRank(stats, primary.rank),
),
```

`lib/pages/overview_page.dart:365`
```dart
title: l.timelineTopRarityTitle(timelineRank, timelineEntries.length),
→ title: l.timelineTopRarityTitle(l.rarityStar(timelineRank), timelineEntries.length),
```

- [ ] **Step 7: 更新測試斷言**

`test/widgets/cards/banner_top_rarity_bars_test.dart`（行 70、71、119、148、149；`l` 為該測試已取得的 `AppLocalizations`）
```dart
l.pityNoMainRarity(5)            → l.pityNoMainRarity(l.rarityStar(5))
l.pityNoMainRarity(4)            → l.pityNoMainRarity(l.rarityStar(4))
l.bannerTopRarityPullsSinceLast(5, 2) → l.bannerTopRarityPullsSinceLast(l.rarityStar(5), 2)
```

`test/widgets/cards/timeline_horizontal_test.dart`（行 51、108）
```dart
l.timelineNoRecordsForRank(5) → l.timelineNoRecordsForRank(l.rarityStar(5))
```

`test/widgets/cards/timeline_vertical_test.dart`（行 43、87、88、108、129）
```dart
l.timelineNoRecordsForRank(5)        → l.timelineNoRecordsForRank(l.rarityStar(5))
l.timelineNowSinceCrossPool(5, 12)   → l.timelineNowSinceCrossPool(l.rarityStar(5), 12)
l.timelineNowSinceLast(5, 12)        → l.timelineNowSinceLast(l.rarityStar(5), 12)
l.timelineNowSinceLast(5, 28)        → l.timelineNowSinceLast(l.rarityStar(5), 28)
```

- [ ] **Step 8: 品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 9: Commit**

```bash
git add lib/l10n test/widgets/cards/banner_top_rarity_bars_test.dart test/widgets/cards/timeline_horizontal_test.dart test/widgets/cards/timeline_vertical_test.dart lib/widgets lib/pages
git commit -m "refactor(i18n): A-group rank→star placeholder via rarityStar

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: B 組 — `statsRankCount` collapse + es/fr/pt/th 遷移

移除 `statsFiveStarCount`/`statsFourStarCount`，新增參數化 `statsRankCount(star)`；`es/fr/pt/th` 既有譯文遷移保留。

**Files:**
- Modify: `lib/l10n/app_en.arb`、`app_ja.arb`、`app_zh.arb`、`app_zh_Hans.arb`、`app_es.arb`、`app_fr.arb`、`app_pt.arb`、`app_th.arb`
- Modify (call sites): `lib/pages/overview_page.dart:85,96`

- [ ] **Step 1: 4 完整語言 collapse**

各檔把兩行（`statsFiveStarCount`、`statsFourStarCount`）替換為單一 `statsRankCount` + `@statsRankCount`：

`app_en.arb`
```
"statsFiveStarCount": "5★ Count",
"statsFourStarCount": "4★ Count",
→ "statsRankCount": "{star} Count",
  "@statsRankCount": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_ja.arb`：`"★5 件数"`/`"★4 件数"` → `"statsRankCount": "{star} 件数"` + 同 `@statsRankCount`
`app_zh.arb`：`"5★ 件數"`/`"4★ 件數"` → `"statsRankCount": "{star} 件數"` + 同 `@statsRankCount`
`app_zh_Hans.arb`：`"5★ 件数"`/`"4★ 件数"` → `"statsRankCount": "{star} 件数"` + 同 `@statsRankCount`

- [ ] **Step 2: es/fr/pt/th 遷移（保留原譯文，不刪）**

`app_es.arb`
```
"statsFiveStarCount": "Numero de articulos 5-Estrellas",
"statsFourStarCount": "Numero de articulos 4-Estrellas",
→ "statsRankCount": "Numero de articulos {star}",
  "@statsRankCount": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_fr.arb`
```
"statsFiveStarCount": "Nombre d'objets 5★ obtenu",
"statsFourStarCount": "Nombre d'objets 4★ obtenu",
→ "statsRankCount": "Nombre d'objets {star} obtenu",
  "@statsRankCount": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_pt.arb`（取 5★ 句型為模，4★ 原句棄用）
```
"statsFiveStarCount": "O número de ganhar um 5 estrelas",
"statsFourStarCount": "A quantidade ganha de um 4 estrelas",
→ "statsRankCount": "O número de ganhar um {star}",
  "@statsRankCount": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_th.arb`
```
"statsFiveStarCount": "จำนวนไอเทม 5 ดาวที่ดรอป",
"statsFourStarCount": "จำนวนไอเทม 4 ดาวที่ดรอป",
→ "statsRankCount": "จำนวนไอเทม {star} ที่ดรอป",
  "@statsRankCount": {
    "placeholders": { "star": { "type": "String" } }
  },
```
（`app_vi.arb` 無此 key，不動。）

- [ ] **Step 3: 重新產生 l10n**

Run: `flutter gen-l10n`
Expected: 無錯誤；`statsFiveStarCount`/`statsFourStarCount` getter 消失，新增 `String statsRankCount(String star)`。

- [ ] **Step 4: 改呼叫端**

`lib/pages/overview_page.dart:85`
```dart
label: l.statsFiveStarCount,
→ label: l.statsRankCount(l.rarityStar(5)),
```
`lib/pages/overview_page.dart:96`
```dart
label: l.statsFourStarCount,
→ label: l.statsRankCount(l.rarityStar(4)),
```

- [ ] **Step 5: 品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze` → Expected: `No issues found!`
Run: `flutter test` → Expected: `All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/l10n lib/pages/overview_page.dart
git commit -m "refactor(i18n): collapse statsFiveStarCount/Four into statsRankCount

es/fr/pt/th existing translations migrated to {star} placeholder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: B 組 — `filterRarityRankOnly` collapse

移除 `filterRarityFiveStar`/`filterRarityFourStar`，新增 `filterRarityRankOnly(star)`。只動 4 完整語言（es/fr/pt/th/vi 本就 fallback zh）。

**Files:**
- Modify: `lib/l10n/app_en.arb`、`app_ja.arb`、`app_zh.arb`、`app_zh_Hans.arb`
- Modify (call sites): `lib/widgets/data/search_filter_bar.dart:101,105`

- [ ] **Step 1: 4 完整語言 collapse**

`app_en.arb`
```
"filterRarityFiveStar": "5★ only",
"filterRarityFourStar": "4★ only",
→ "filterRarityRankOnly": "{star} only",
  "@filterRarityRankOnly": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_ja.arb`：`"★5 のみ"`/`"★4 のみ"` → `"filterRarityRankOnly": "{star} のみ"` + 同 `@filterRarityRankOnly`
`app_zh.arb`：`"只看 5★"`/`"只看 4★"` → `"filterRarityRankOnly": "只看 {star}"` + 同 `@filterRarityRankOnly`
`app_zh_Hans.arb`：`"只看 5★"`/`"只看 4★"` → `"filterRarityRankOnly": "只看 {star}"` + 同 `@filterRarityRankOnly`

- [ ] **Step 2: 重新產生 l10n**

Run: `flutter gen-l10n`
Expected: 新增 `String filterRarityRankOnly(String star)`，舊兩 getter 消失。

- [ ] **Step 3: 改呼叫端**

`lib/widgets/data/search_filter_bar.dart:101`
```dart
child: Text(l.filterRarityFiveStar),
→ child: Text(l.filterRarityRankOnly(l.rarityStar(5))),
```
`lib/widgets/data/search_filter_bar.dart:105`
```dart
child: Text(l.filterRarityFourStar),
→ child: Text(l.filterRarityRankOnly(l.rarityStar(4))),
```

- [ ] **Step 4: 品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze` → Expected: `No issues found!`
Run: `flutter test` → Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/l10n lib/widgets/data/search_filter_bar.dart
git commit -m "refactor(i18n): collapse filterRarityFiveStar/Four into filterRarityRankOnly

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: B 組 — `pityRank` collapse + 移除 `PityRule.labelKey`

移除 `pityFiveStar`/`pityFourStar`/`pityThreeStar`，新增 `pityRank(star)`；移除 `PityRule.labelKey` 欄位與 `_pityLabel` switch，改由 `rank` 驅動。

**Files:**
- Modify: `lib/l10n/app_en.arb`、`app_ja.arb`、`app_zh.arb`、`app_zh_Hans.arb`
- Modify: `lib/data/gacha_types.dart`、`lib/pages/banner_page.dart`、`lib/widgets/cards/timeline_vertical.dart`

- [ ] **Step 1: 4 完整語言 collapse**

`app_en.arb`
```
"pityFiveStar": "5★ pity",
"pityFourStar": "4★ pity",
"pityThreeStar": "3★ pity",
→ "pityRank": "{star} pity",
  "@pityRank": {
    "placeholders": { "star": { "type": "String" } }
  },
```
`app_ja.arb`：`"★5 天井"`/`"★4 天井"`/`"★3 天井"` → `"pityRank": "{star} 天井"` + 同 `@pityRank`
`app_zh.arb`：`"5★ 保底"`/`"4★ 保底"`/`"3★ 保底"` → `"pityRank": "{star} 保底"` + 同 `@pityRank`
`app_zh_Hans.arb`：`"5★ 保底"`/`"4★ 保底"`/`"3★ 保底"` → `"pityRank": "{star} 保底"` + 同 `@pityRank`

- [ ] **Step 2: 重新產生 l10n**

Run: `flutter gen-l10n`
Expected: 新增 `String pityRank(String star)`；`pityFiveStar`/`pityFourStar`/`pityThreeStar` getter 消失（此時 `banner_page.dart` 的 `_pityLabel` 會編譯錯誤，下一步修）。

- [ ] **Step 3: 移除 `PityRule.labelKey`（`lib/data/gacha_types.dart`）**

```dart
class PityRule {
  const PityRule({
    required this.rank,
    required this.threshold,
    required this.labelKey,
  });

  final int rank;
  final int threshold;
  final String labelKey;
}
```
改為
```dart
class PityRule {
  const PityRule({
    required this.rank,
    required this.threshold,
  });

  final int rank;
  final int threshold;
}
```
並把 7 個 const 定義移除 `labelKey:`：
```dart
const _pityFive90 = PityRule(rank: 5, threshold: 90, labelKey: 'pityFiveStar');
const _pityFive80 = PityRule(rank: 5, threshold: 80, labelKey: 'pityFiveStar');
const _pityFive70 = PityRule(rank: 5, threshold: 70, labelKey: 'pityFiveStar');
const _pityFive20 = PityRule(rank: 5, threshold: 20, labelKey: 'pityFiveStar');
const _pityFour70 = PityRule(rank: 4, threshold: 70, labelKey: 'pityFourStar');
const _pityFour10 = PityRule(rank: 4, threshold: 10, labelKey: 'pityFourStar');
const _pityThree5 = PityRule(rank: 3, threshold: 5, labelKey: 'pityThreeStar');
```
改為
```dart
const _pityFive90 = PityRule(rank: 5, threshold: 90);
const _pityFive80 = PityRule(rank: 5, threshold: 80);
const _pityFive70 = PityRule(rank: 5, threshold: 70);
const _pityFive20 = PityRule(rank: 5, threshold: 20);
const _pityFour70 = PityRule(rank: 4, threshold: 70);
const _pityFour10 = PityRule(rank: 4, threshold: 10);
const _pityThree5 = PityRule(rank: 3, threshold: 5);
```

- [ ] **Step 4: `lib/pages/banner_page.dart` — 移除 `_pityLabel`、改用 `pityRank`**

刪除檔尾整段（行約 294-300）：
```dart
/// 將 [PityRule.labelKey] 解析為對應的 i18n 字串。
String _pityLabel(String labelKey, AppLocalizations l) => switch (labelKey) {
  'pityFiveStar' => l.pityFiveStar,
  'pityFourStar' => l.pityFourStar,
  'pityThreeStar' => l.pityThreeStar,
  _ => labelKey,
};
```

行 43-44 inline `PityRule` 去掉 `labelKey:`：
```dart
PityRule(rank: 5, threshold: 90, labelKey: 'pityFiveStar'),
PityRule(rank: 4, threshold: 10, labelKey: 'pityFourStar'),
→ PityRule(rank: 5, threshold: 90),
  PityRule(rank: 4, threshold: 10),
```

行 124：
```dart
label: _pityLabel(primary.labelKey, l),
→ label: l.pityRank(l.rarityStar(primary.rank)),
```
行 134：
```dart
label: _pityLabel(secondary.labelKey, l),
→ label: l.pityRank(l.rarityStar(secondary.rank)),
```

- [ ] **Step 5: `lib/widgets/cards/timeline_vertical.dart:229-230` — inline `PityRule` 去 `labelKey`**

```dart
PityRule(rank: 5, threshold: 90, labelKey: 'pityFiveStar'),
PityRule(rank: 4, threshold: 10, labelKey: 'pityFourStar'),
→ PityRule(rank: 5, threshold: 90),
  PityRule(rank: 4, threshold: 10),
```

- [ ] **Step 6: 品質檢查**

Run: `dart format lib/ test/`
Run: `flutter analyze` → Expected: `No issues found!`（確認無 `_pityLabel`、`labelKey` 殘留未用、無 import 警告）
Run: `flutter test` → Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/l10n lib/data/gacha_types.dart lib/pages/banner_page.dart lib/widgets/cards/timeline_vertical.dart
git commit -m "refactor(i18n): collapse pity*Star into pityRank, drop PityRule.labelKey

PityRule.rank now drives the label; _pityLabel switch removed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 全面驗證

- [ ] **Step 1: 確認無星等寫死殘留**

Run: `grep -rnE '★|\{rank\}★' lib/l10n/app_en.arb lib/l10n/app_ja.arb lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb`
Expected: 只剩 `"rarityStar"` 本身那一行（en/zh/zh_Hans 為 `{rank}★`、ja 為 `★{rank}`）；其餘受影響 key 不再出現 `★`。

Run: `grep -rnE 'labelKey|_pityLabel|pityFiveStar|pityFourStar|pityThreeStar|statsFiveStarCount|statsFourStarCount|filterRarityFiveStar|filterRarityFourStar' lib test`
Expected: 無任何結果（全部已移除/改名）。

- [ ] **Step 2: 最終品質閘**

Run: `dart format lib/ test/`
Run: `flutter analyze` → Expected: `No issues found!`
Run: `flutter test` → Expected: `All tests passed!`

- [ ] **Step 3: 確認 generated 已隨 ARB 重產並入庫**

Run: `git status --porcelain lib/l10n/generated`
Expected: 空輸出（generated 變更已在前面各 task 一併 commit，無未追蹤殘留）。

---

## Self-Review

- **Spec coverage：** A 組 7 key（Task 1）、B 組 statsRankCount + es/fr/pt/th 遷移（Task 2）、filterRarityRankOnly（Task 3）、pityRank + PityRule.labelKey 移除（Task 4）、gen-l10n 重產（各 task Step）、測試更新（Task 1 Step 7）、品質閘（各 task + Task 5）、`vi` 不動（Task 2 Step 2 註明）。spec 各節皆有對應 task。
- **Placeholder scan：** 無 TBD/TODO；每個 ARB 與 Dart 變更皆給出完整 old→new。
- **Type consistency：** 新方法簽章一致 — `statsRankCount(String star)`、`pityRank(String star)`、`filterRarityRankOnly(String star)`、A 組單參 `(String star)`、雙參 `(String star, int n)`；呼叫端一律 `l.<key>(l.rarityStar(rank)[, n])`，引數順序與 placeholder 宣告順序（star 先、n 後）相符。`PityRule` 移除 `labelKey` 後所有建構點（gacha_types 7 處、banner_page 2 處、timeline_vertical 2 處）皆已列出同步移除。
