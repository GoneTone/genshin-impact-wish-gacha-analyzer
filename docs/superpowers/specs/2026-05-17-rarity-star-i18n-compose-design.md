# 星等字串改用 `rarityStar` 組合 — 設計 spec

日期：2026-05-17
分支：`flutter-rewrite`

## 目標

翻譯檔中所有寫死的星等（`5★`/`4★`/`3★`、各語言自行排列的 `{rank}★` / `★{rank}`）一律改由既有的 locale-aware `rarityStar(rank)` 負責產生星等顯示。其他訊息只保留單一 `{star}` String placeholder，由 Dart 端傳入 `l.rarityStar(rank)`。

## 背景與動機

- 專案已有 `rarityStar` key（commit `eb9ac49` 起導入），日文為 `★{rank}`、其他語言為 `{rank}★`，集中處理星等顯示順序。
- 目前仍有多處字串自行寫死星等與順序，等於把「星等顯示」這個關注點重複散落在每個語言的每個 key，違反 CLAUDE.md「嚴禁重複造輪子」。
- 改為組合 `rarityStar` 後：新增語言或調整星等樣式只需改一處；ja 順序不會跑掉；非 ★ 語言不再各自維護星詞。

## 核心原則

所有星等顯示一律由 `rarityStar(rank)` 產生。受影響訊息只保留 `{star}` (String) placeholder，呼叫端傳 `l.rarityStar(rank)`。各語言譯文不再出現 `★` 字元與星等順序邏輯。

### locale 檔現況（重要前提）

`l10n.yaml` 的 `template-arb-file` 是 **`app_zh.arb`**。各 locale key 數：`en/zh/zh_Hans/ja` 各 261（完整）；`es`=40、`fr`=31、`pt`=24、`th`=14、`vi`=14。**未定義的 key 一律 fallback 到 zh 模板**，gen-l10n 只依模板（app_zh.arb）產生介面，模板沒有的 key 不會產生、模板有但某 locale 沒有的 key 該 locale 靜默回退 zh。

本次受影響 key 的實際定義狀況：

- **A 組 7 個 key**：只定義於 `en/ja/zh/zh_Hans`；es/fr/pt/th/vi 皆未定義（fallback zh）。
- **B 組**：`statsFiveStarCount`/`statsFourStarCount` 定義於 `en/ja/zh/zh_Hans/es/fr/pt/th`（vi 無）；`pity*Star`、`filterRarity*Star` 只定義於 `en/ja/zh/zh_Hans`（es/fr/pt/th/vi fallback zh）。

**補譯 es/fr/pt/th/vi 未定義 key 不在本 spec 範圍**（屬 200+ key/語言的獨立工程，另開 spec 處理）。本 spec 對非完整語言僅：(1) 把 es/fr/pt/th 既有的 `statsFiveStarCount`/`statsFourStarCount` 譯文遷移到 `statsRankCount`（不新增譯文）；(2) 其餘改名 key 自動 fallback zh。`l.rarityStar(rank)` 對 es/fr/pt/th/vi 經 zh 模板 fallback 得 `{rank}★`（僅 ja 為 `★{rank}`），組合行為正確。

## A 組：已有 `{rank}` 的 7 個 key — 改 placeholder 型別

key：`tableMainPityTooltip`、`pityNoMainRarity`、`timelineNoRecordsForRank`、`timelineNowSinceLast`、`timelineNowSinceCrossPool`、`timelineTopRarityTitle`、`bannerTopRarityPullsSinceLast`

### ARB 變更

- placeholder `rank` (int) → `star` (String)，並移除字串內的 `★` 字元。
- 含 `{n}` 的（`timelineNowSinceLast`、`timelineNowSinceCrossPool`、`timelineTopRarityTitle`、`bannerTopRarityPullsSinceLast`）保留 `{n}` placeholder 不動，只處理 star 部分。
- 只需改 `en/ja/zh/zh_Hans` 這 4 個檔（A 組 key 僅定義於此）；es/fr/pt/th/vi 無此 key，維持 zh fallback，不動。

範例（`tableMainPityTooltip`）：

| locale | 變更前 | 變更後 |
|---|---|---|
| en | `Pulls since the last {rank}★` | `Pulls since the last {star}` |
| ja | `前回の ★{rank} からの回数` | `前回の {star} からの回数` |
| zh | `距上一次 {rank}★ 的抽數` | `距上一次 {star} 的抽數` |

`@key` metadata 的 `placeholders` 由 `{ "rank": { "type": "int" } }` 改為 `{ "star": { "type": "String" } }`；原本就有的 `{n}` placeholder 保留。

### 呼叫端變更

呼叫由 `l.foo(rank, ...)` 改為 `l.foo(l.rarityStar(rank), ...)`：

- `lib/widgets/data/sortable_table.dart:196` — `tableMainPityTooltip(mainRank)`
- `lib/widgets/cards/banner_top_rarity_bars.dart:47` — `pityNoMainRarity(type.primaryPity.rank)`
- `lib/widgets/cards/banner_top_rarity_bars.dart:54` — `bannerTopRarityPullsSinceLast(...)`
- `lib/widgets/cards/pity_card.dart:203` — `pityNoMainRarity(rank)`
- `lib/widgets/cards/timeline_vertical.dart:119` — `timelineNoRecordsForRank(targetRank)`
- `lib/widgets/cards/timeline_vertical.dart:346` — `timelineNowSinceCrossPool(targetRank, nowPulls)`
- `lib/widgets/cards/timeline_vertical.dart:347` — `timelineNowSinceLast(targetRank, nowPulls)`
- `lib/widgets/cards/timeline_horizontal.dart:131` — `timelineNoRecordsForRank(widget.targetRank)`
- `lib/pages/banner_page.dart:241` — `timelineTopRarityTitle(...)`
- `lib/pages/overview_page.dart:365` — `timelineTopRarityTitle(timelineRank, timelineEntries.length)`

含 `{n}` 的方法注意參數順序：`{star}` 對應原 `rank`、`{n}` 對應原 `n`，傳入時把原 rank 參數替換成 `l.rarityStar(rank)` 即可，順序不變。

## B 組：寫死數字的 getter 對 → collapse 成參數化方法

| 移除 key | 新增 key | en | zh | ja |
|---|---|---|---|---|
| `statsFiveStarCount` / `statsFourStarCount` | `statsRankCount(star)` | `{star} Count` | `{star} 件數` | `{star} 件数` |
| `pityFiveStar` / `pityFourStar` / `pityThreeStar` | `pityRank(star)` | `{star} pity` | `{star} 保底` | `{star} 天井` |
| `filterRarityFiveStar` / `filterRarityFourStar` | `filterRarityRankOnly(star)` | `{star} only` | `只看 {star}` | `{star} のみ` |

- 在 `en/ja/zh/zh_Hans` 4 個檔移除舊 key、加入新 key，並加 `@key` metadata：`placeholders` 為 `{ "star": { "type": "String" } }`。
- `pity*Star` / `filterRarity*Star`：es/fr/pt/th/vi 本就未定義（fallback zh），無動作；改名後它們自動 fallback 至 zh 模板的新 key（`pityRank`/`filterRarityRankOnly`），維持與現況一致的 zh 顯示。

### es/fr/pt/th statsRankCount 遷移（保留原譯文）

`statsFiveStarCount`/`statsFourStarCount` 額外定義於 `es/fr/pt/th`，且為各語言的真實譯文（非 zh fallback）。collapse 時**不刪除、改為遷移**：把舊兩 key 移除，改在各語言定義 `statsRankCount`，沿用其既有用詞、把數字＋星詞位置換成 `{star}`：

| locale | 既有 5★ / 4★ | 遷移後 `statsRankCount` |
|---|---|---|
| es | `Numero de articulos 5-Estrellas` / `Numero de articulos 4-Estrellas` | `Numero de articulos {star}` |
| fr | `Nombre d'objets 5★ obtenu` / `Nombre d'objets 4★ obtenu` | `Nombre d'objets {star} obtenu` |
| th | `จำนวนไอเทม 5 ดาวที่ดรอป` / `จำนวนไอเทม 4 ดาวที่ดรอป` | `จำนวนไอเทม {star} ที่ดรอป` |
| pt | `O número de ganhar um 5 estrelas` / `A quantidade ganha de um 4 estrelas` | `O número de ganhar um {star}`（取 5★ 句型為模，4★ 原句棄用） |

- 每個遷移後 key 加 `@statsRankCount` metadata：`placeholders` 為 `{ "star": { "type": "String" } }`。
- 已知且接受的副作用：傳入的 `{star}` 由 `rarityStar` 經 zh 模板 fallback 得 `5★`/`4★`（僅 ja 為 `★5`），故 es 顯示由 `5-Estrellas` 變 `5★`、th 由 `5 ดาว` 變 `5★`。使用者已確認接受。
- `vi` 無 `statsFiveStarCount`/`statsFourStarCount`（fallback zh），不動，改名後自動 fallback zh 模板的 `statsRankCount`。

### 呼叫端變更

- `lib/pages/overview_page.dart:85` — `l.statsFiveStarCount` → `l.statsRankCount(l.rarityStar(5))`
- `lib/pages/overview_page.dart:96` — `l.statsFourStarCount` → `l.statsRankCount(l.rarityStar(4))`
- `lib/widgets/data/search_filter_bar.dart:101` — `l.filterRarityFiveStar` → `l.filterRarityRankOnly(l.rarityStar(5))`
- `lib/widgets/data/search_filter_bar.dart:105` — `l.filterRarityFourStar` → `l.filterRarityRankOnly(l.rarityStar(4))`

## PityRule 結構清理（移除 labelKey）

`pityRank` 由 `PityRule.rank` 驅動，`PityRule.labelKey` 變冗餘，一併移除。

- `lib/data/gacha_types.dart`
  - `PityRule`：移除 `required this.labelKey` 建構參數與 `final String labelKey;` 欄位。
  - 7 個 `const _pityXxx`（`gacha_types.dart:53-59`）移除 `labelKey:` 引數。
- `lib/pages/banner_page.dart`
  - 刪除 `_pityLabel` switch 函式（含 `:294-299` 的註解與實作）。
  - `:43-44` inline `PityRule` 移除 `labelKey:`。
  - `:124` `_pityLabel(primary.labelKey, l)` → `l.pityRank(l.rarityStar(primary.rank))`。
  - `:134` `_pityLabel(secondary.labelKey, l)` → `l.pityRank(l.rarityStar(secondary.rank))`。
- `lib/widgets/cards/timeline_vertical.dart:229-230` inline `PityRule` 移除 `labelKey:`。

## 收尾與驗證

1. `flutter gen-l10n` 重新產生 `lib/l10n/generated/*`，不手動編輯 generated 檔。
2. 更新受影響測試：`test/` 內若有對舊 key（`statsFiveStarCount` 等）或 `PityRule(labelKey:)` 的斷言一併調整；rarity 相關測試（如 `rarity_pie_test`）確認仍通過。
3. 提交前品質檢查依序通過：
   - `dart format lib/ test/`
   - `flutter analyze` → `No issues found!`
   - `flutter test` → `All tests passed!`

## YAGNI 確認

- 不新增任何未使用的 key 或參數。
- 不動 `rarityStar` 本身的實作與譯文。
- 不補譯 es/fr/pt/th/vi 未定義的 key（獨立工程，另開 spec）；本 spec 對 es/fr/pt/th 只遷移其「既有」`statsFiveStarCount`/`statsFourStarCount` 譯文至 `statsRankCount`，不新增其他譯文。

## 影響檔案清單

- ARB 內容變更（A 組改 placeholder + B 組 collapse 全部 key）：`lib/l10n/app_{en,ja,zh,zh_Hans}.arb`（4 個）
- ARB `statsRankCount` 遷移（保留原譯文）：`lib/l10n/app_{es,fr,pt,th}.arb`（4 個）
- `app_vi.arb`：無受影響 key，不動
- 產生檔：`lib/l10n/generated/*`（由 gen-l10n 重產）
- Dart：`lib/data/gacha_types.dart`、`lib/pages/banner_page.dart`、`lib/pages/overview_page.dart`、`lib/widgets/data/sortable_table.dart`、`lib/widgets/data/search_filter_bar.dart`、`lib/widgets/cards/banner_top_rarity_bars.dart`、`lib/widgets/cards/pity_card.dart`、`lib/widgets/cards/timeline_vertical.dart`、`lib/widgets/cards/timeline_horizontal.dart`
- 測試：`test/` 內相關斷言
