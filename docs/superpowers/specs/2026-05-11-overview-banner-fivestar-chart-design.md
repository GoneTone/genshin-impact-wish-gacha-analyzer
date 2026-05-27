# 綜合頁簡化 + 各卡池 5★ 件數圖表

- 日期：2026-05-11
- 範圍：`lib/pages/overview_page.dart` 重構；新增 `lib/widgets/cards/banner_five_star_bars.dart`；新增 i18n key。

## 目標

1. **簡化綜合頁版面**：移除 Row 1（StatCards）與 Row 2（稀有度 Pie、類型 Pie、橫向時間軸），只保留 PageHeader 與下方的 `TimelineVertical`。
2. **新增「各卡池 5★ 件數」Card**：以水平 Bar 呈現 5 個卡池的 5★ 件數，並在 bar 右側標示「件數 · 距上次 5★ N 抽」（新手池顯示「已結束」、無 5★ 顯示「暫無 5★」）。位置：PageHeader 與 5★ 時間軸 之間。

非目標：
- 不動 banner 頁（per-banner 頁）。
- 不動 `TimelineVertical` 本身。
- 不引入 `fl_chart` 的 `BarChart`（垂直方向不符需求；用自製水平 bar 與既有 `PityCard._ProgressBar` 模式一致）。
- 不顯示百分比、不顯示 4★ 件數。

## 最終版面

```
PageHeader「綜合數據（全卡池合計）」
└─ ChartCard「各卡池 5★ 件數」（新）
    ├─ 角色活動  ████████████████  23 · 距上次 5★ 35 抽
    ├─ 武器活動  ██████████        12 · 距上次 5★ 21 抽
    ├─ 集錄      █████              7 · 距上次 5★ 60 抽
    ├─ 常駐      ████               4 · 距上次 5★ 12 抽
    └─ 新手      ██                 2 · 已結束
└─ 5★ 時間軸 (n)
    └─ TimelineVertical（保留）
```

## 元件設計

### 新元件：`BannerFiveStarBars`（`lib/widgets/cards/banner_five_star_bars.dart`）

職責：吃一份 `Map<String, List<WishRecord>> banners`，輸出 5 條水平 bar。

```dart
class BannerFiveStarBars extends StatelessWidget {
  const BannerFiveStarBars({
    super.key,
    required this.banners,
    required this.colors,
  });

  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;
}
```

行為：
- 以 `data/gacha_types.dart` 的 `gachaTypes` 順序遍歷，產生 5 個 row（即使該卡池無紀錄也維持位置，bar 寬度 = 0）。
- 每個 row：左欄卡池名（`GachaType.resolveName`）、中欄水平 bar、右欄「件數 · {subtitle}」。
- Bar 長度 = `fiveStarCount / max(所有卡池 fiveStarCount)`；最大值的卡池 bar 為 100%。所有卡池皆為 0 時 bar 全部顯示為 0 寬度（空 row）。
- Bar 顏色取自 `BannerColors.colorFor(gachaType)`（與時間軸顏色一致）。
- 右欄 subtitle 分三態：
  - 新手池（`gachaType == '100'`）→ `pityBeginnerEnded` (i18n)
  - 該卡池無 5★（`fiveStarCount == 0`）→ `pityNoFiveStar` (i18n)
  - 其他 → `bannerFiveStarPullsSinceLast(n)`（新增 i18n key，下節）
- 高度：自然撐高（5 row × ~36px + padding ≈ 200px），呼叫端使用 `ChartCard(height: 280)` 約能裝下。

### Bar 視覺實作

不重複造輪子：抽出 `PityCard.dart` 內 `_ProgressBar` 的核心結構為共用 widget，或直接在 `BannerFiveStarBars` 用相同模式（`Container` + `widthFactor`）。視覺差異：

- 無 phase 概念（不需要 `breath` 動畫、不需要 close/guaranteed 著色）。
- 漸層：`accent.withValues(alpha: 0.55) → accent`，與 normal phase 一致風格。

決定：**在新檔內以相同模式重寫 bar widget**（不抽共用 widget），因為兩處差異足以讓抽象帶來負擔，YAGNI。

### 資料計算

每個卡池需要兩個數字：
- **5★ 件數**：`computeWishStats(records).fiveStarCount`
- **距上次 5★ 抽數**：`computePity(records, threshold: type.fiveStarPity).current`

兩者都已有 service，**不另寫新邏輯**。

### `OverviewPage` 改寫

```dart
final bannerColors = BannerColors.fromTokens(tokens);
final timelineEntries = buildTimelineEntriesAcrossBanners(activeData.banners);

return SingleChildScrollView(
  padding: const EdgeInsets.all(AppSpacing.l),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeader(title: l.pageOverviewTitle),

      ChartCard(
        title: l.bannerFiveStarCountTitle,
        height: 280,
        chart: BannerFiveStarBars(
          banners: activeData.banners,
          colors: bannerColors,
        ),
      ),

      const SizedBox(height: AppSpacing.xl),
      Text(
        l.timelineCountFiveStar(timelineEntries.length),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.s),
      TimelineVertical(
        entries: timelineEntries,
        colors: bannerColors,
        nowPulls: pullsSinceLastFiveStarAcrossBanners(activeData.banners),
        isAcrossBanners: true,
      ),
    ],
  ),
);
```

簡化要點：
- 不再需要 `activeData.allRecords` / `computeWishStats(all)`，因 timeline title 改用 `timelineEntries.length`（已經就是所有 5★ 的數量）。`BannerFiveStarBars` 內部會 per-banner 各自計算件數。
- `services/wish_stats.dart` 在綜合頁不再使用（仍由 `banner_page.dart` 使用，**保留檔案**）。
- `widgets/rarity_pie.dart`、`widgets/item_type_pie.dart`、`widgets/cards/stat_card.dart`、`widgets/cards/timeline_horizontal.dart`、`widgets/distribution_legend.dart` 在綜合頁中**不再 import**，但因為仍由 `banner_page.dart` 使用，**保留檔案**。
- 移除 Row 1 / Row 2 的 `LayoutBuilder`（不再需要根據寬度切 1/2/3 欄）。

## i18n

新增 keys（三份 arb：`app_en.arb`、`app_zh.arb` 即 zh_Hans、`app_zh_Hant.arb`）：

| Key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `bannerFiveStarCountTitle` | 各卡池 5★ 件數 | 各卡池 5★ 件数 | 5★ count per banner |
| `bannerFiveStarPullsSinceLast` | 距上次 5★ {n} 抽 | 距上次 5★ {n} 抽 | {n} pulls since last 5★ |

`pityBeginnerEnded`（已結束）、`pityNoFiveStar`（暫無 5★）已存在，直接重用。

## 測試

新增 `test/widgets/cards/banner_five_star_bars_test.dart`：

1. **5 row 永遠存在** — 即使 `banners` 為空 map，仍渲染 5 個 row（各 0 件、subtitle 為「暫無 5★」）。
2. **新手池 subtitle** — `100` 卡池的 subtitle 永遠是「已結束」，不管件數多寡。
3. **件數正確** — 給定 banners，每個 row 顯示的件數 = 該卡池 records 中 `rankType == 5` 的數量。
4. **距上次 5★ 正確** — desc-by-time records 中，最新一筆 5★ 之前的記錄數即為「距上次 5★」。
5. **bar 比例** — 最大件數卡池的 bar 寬度 = 1.0（widthFactor）；其他依比例縮放。
6. **顏色** — 每 row 的 bar 顏色 = `BannerColors.colorFor(gachaType)`。

更新 `test/pages/overview_page_test.dart`（若存在）：
- 確認原本對 StatCard / RarityPie / ItemTypePie / TimelineHorizontal 的 expect 不再尋找這些 widget。
- 新增對 `BannerFiveStarBars` 的存在 expect。
- 保留對 `TimelineVertical` 的 expect。

若 `overview_page_test.dart` 不存在，僅需新元件測試。

## 邊界與錯誤處理

- **完全沒紀錄**（`activeData == null`）：沿用既有 `EmptyState.noSync` 邏輯，整頁不渲染本元件。
- **有紀錄但全 5 個卡池都 0 件**：5 row 都顯示「0 · 暫無 5★」，bar 全部 0 寬。
- **新手池有紀錄但無 5★**：subtitle = 「已結束」（新手池規則優先於「暫無 5★」）。
- **某卡池 records 為 null**（`banners[gachaType]` 不存在）：視為空 list，按上述處理。

## 開放問題

無。

## 不在範圍

- 本元件不顯示「總抽數」、「4★ 件數」、「百分比」。
- 不替換 banner 頁的 PityCard。
- 不調整 `TimelineVertical` 本身。
- 不引入新套件。

## 提交前檢查

依 `CLAUDE.md`：

1. `dart format lib/ test/`
2. `flutter analyze`（必須 `No issues found!`）
3. `flutter test`（必須 `All tests passed!`）
