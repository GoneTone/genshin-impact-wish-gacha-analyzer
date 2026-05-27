# 星級寫法 i18n 收斂（程式碼硬寫 N★ → 單一 ARB key）：設計

- 日期：2026-05-17
- 分支：flutter-rewrite
- 狀態：設計已確認，待寫實作計畫

## 問題

部分星級標籤在 Dart 程式碼中硬寫死 `N★` 順序，日文應為 `★N` 卻不會反轉。
ARB 字串內嵌的 `{rank}★`/`★{rank}` 已於先前任務按語言修正；本任務只處理
**程式碼建構**的星級標籤。

受影響點：

| 位置 | 現況 | 取 `l` 方式 |
|---|---|---|
| `lib/widgets/rarity_pie.dart` `rarityDistributionEntries()` | `'5★' '4★' '3★' '2★'` | 頂層函式無 `l`，需加參數；呼叫點 `lib/pages/banner_page.dart:219`、`lib/pages/overview_page.dart:294` 皆有 `l` |
| `lib/pages/overview_page.dart:123,128` | `'${...resolveName(l)} 5★'`、`4★` | `l` 已在 scope |
| `lib/widgets/data/sortable_table.dart:335` | `Text('${record.rankType}★')` | `l` 已在 scope（同 build 內有 `relativeTime(record.time, l)`） |
| `lib/widgets/data/sortable_table.dart:378` `_Pill` | `'$rank★'` | 子 widget，`build(BuildContext context)` 內取 `AppLocalizations.of(context)!` |

不受影響：`lib/widgets/cards/timeline_horizontal.dart` 的 `DistributionEntry`
是卡池名（`type.resolveName(l)`）非星級。

## 已確認決策

1. **方案 A：單一 ARB key + helper，全面收斂**（使用者選定）。
2. ARB 內嵌 `{rank}★`/`★{rank}` 的句子（`timelineNoRecordsForRank`、
   `pityNoMainRarity`、`timelineNowSinceLast` 等）**不重構**——ICU 無法嵌套訊息
   參照，且這些字串已各自按語言正確。
3. 不引入額外 Dart 格式化抽象層（YAGNI、嚴禁重複造輪子）；gen-l10n 產生的
   `AppLocalizations.rarityStar` 即為唯一 helper。

## 設計

### 單一來源

在 template `lib/l10n/app_zh.arb` 新增 key，**插入位置固定**：緊接 `tableRarity`
之後、`tableTotalIndex` 之前（與稀有度語意同群、不破壞既有分組空行）。
三個維護 locale 檔在相同相對位置插入，順序與 template 完全一致：

```jsonc
"rarityStar": "{rank}★",
"@rarityStar": {
  "placeholders": { "rank": { "type": "int" } }
}
```

gen-l10n 產生 `String rarityStar(int rank)`，即為唯一 helper，無額外抽象。

各語言值：

| locale 檔 | rarityStar |
|---|---|
| `app_zh.arb`（template）/ `app_zh_Hans.arb` / `app_en.arb` | `{rank}★` |
| `app_ja.arb` | `★{rank}` |

維持「locale 檔鏡像 template」不變式：`app_zh_Hans.arb` / `app_en.arb` /
`app_ja.arb` 三個維護檔都加入此 key 與照抄的 `@rarityStar` metadata，位置與
template 完全一致、保留分組空行。其餘 `fr/es/pt/th/vi` **不加**（gen-l10n
runtime 回退 template `{rank}★`，對這些語言皆正確；專案 `flutter analyze`
不將 untranslated message 視為錯誤，先前已驗證）。

### 程式碼改動

1. `lib/widgets/rarity_pie.dart`
   - `rarityDistributionEntries(WishStats stats, GachaTokens tokens)` →
     加參數 `AppLocalizations l`：`rarityDistributionEntries(stats, tokens, l)`。
   - 4 個 `DistributionEntry` 的 `name:` 由 `'5★'`/`'4★'`/`'3★'`/`'2★'`
     改為 `l.rarityStar(5)` / `l.rarityStar(4)` / `l.rarityStar(3)` /
     `l.rarityStar(2)`。
   - 更新呼叫點：`lib/pages/banner_page.dart:219`、
     `lib/pages/overview_page.dart:294` 傳入既有 scope 的 `l`。

2. `lib/pages/overview_page.dart:123,128`
   - `'${odesEventType.resolveName(l)} 5★'` →
     `'${odesEventType.resolveName(l)} ${l.rarityStar(5)}'`
   - `'${odesStandardType.resolveName(l)} 4★'` →
     `'${odesStandardType.resolveName(l)} ${l.rarityStar(4)}'`

3. `lib/widgets/data/sortable_table.dart:335`
   - `Text('${record.rankType}★')` → `Text(l.rarityStar(record.rankType))`

4. `lib/widgets/data/sortable_table.dart` `_Pill.build`
   - 取 `final l = AppLocalizations.of(context)!;`
   - `Text('$rank★', ...)` → `Text(l.rarityStar(rank), ...)`（保留既有
     `style`）

### 測試

新增 / 擴充測試（沿用既有 `flutter_test` + `AppLocalizations` 載入慣例）：

- 單元：`AppLocalizations` 於 `en` 時 `rarityStar(5) == '5★'`；於 `ja` 時
  `rarityStar(5) == '★5'`；`rarityStar(2)` 同理（驗證低 rank 也對）。
- Widget：`RarityPie` 對應的 `DistributionLegend` 在 `ja` locale 下出現
  `★5` 文字、不出現 `5★`。
- Widget：`sortable_table` rank cell（含 `_Pill` 與非 `_Pill` 分支）在 `ja`
  locale 下渲染 `★5`。

### 驗證

提交前依 CLAUDE.md：

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`（含 gen-l10n 重新產碼）
3. `flutter test` → `All tests passed!`

## 不做（YAGNI）

- 不重構 ARB 內嵌 `{rank}★` 的句子。
- 不動 `fr/es/pt/th/vi`。
- 不引入額外 Dart 星級格式化抽象層或 extension。
- 不改 `timeline_horizontal.dart`（非星級）。

## 版控

spec 沿用 `docs/superpowers` gitignored 慣例，不進版控。交付物：
`lib/l10n/app_zh.arb`、`app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、
`lib/widgets/rarity_pie.dart`、`lib/pages/overview_page.dart`、
`lib/pages/banner_page.dart`、`lib/widgets/data/sortable_table.dart`、
相關測試檔。
