# 中獎率與中獎數資訊分離 — 設計文件

- 日期：2026-05-10
- 分支：`flutter-rewrite`
- 影響頁面：總覽頁（OverviewPage）、卡池頁（BannerPage）

---

## 1. 背景與動機

目前統計頁面中，「中獎率（百分比）」與「中獎數（件數）」混在同一個視覺容器內，使用者必須花時間判讀數字代表的單位。具體混合來源有三處：

1. **總覽頁 5★/4★ Stat Card**
   - 標題：`5★ 中獎率`、`4★ 中獎率`
   - 主視覺：`12`、`88`（次數）
   - 副視覺：`1.23%`、`8.95%`（率）
   - 問題：標題說「率」，主視覺卻是「數」，副視覺才是「率」 — 標題與內容矛盾。

2. **稀有度餅圖 RarityPie**（兩頁皆用）
   - 標題：`5★ 中獎率 / 4★ 中獎率 / 3★ 中獎率`
   - 扇形面積：率
   - 切片標籤：`5★ 12`（次數）
   - 問題：扇形與切片標籤分別表達「率」與「數」兩種單位，疊在同張圖上。

3. **角色 / 武器餅圖 ItemTypePie**（兩頁皆用）
   - 標題：`角色 / 武器`（無單位提示）
   - 切片標籤：`角色 38`、`武器 62`（次數，無 `%`）
   - 問題：標籤數字看起來像百分比但其實是次數，使用者需反推。

## 2. 目標

讓使用者一眼就能分辨：哪個視覺元素代表「次數」、哪個代表「百分比」。每個視覺容器只回答一個明確的問題。

## 3. 採用方向 — A · 圖例表格 + 卡片視覺分層

| 容器 | 「率」呈現位置 | 「數」呈現位置 |
| --- | --- | --- |
| Stat Card | 副欄文字 `佔總抽 X.XX%` | 主視覺大數字 |
| 餅圖卡 | 圖例的「率」欄 | 圖例的「次數」欄 |

設計原則：
- **餅圖切片內不再有任何文字**，扇形大小 = 比例的純視覺表達。
- **圖例採表格式排版**，每行 `[色塊] [名稱] [次數欄] [率欄]`，欄位對齊、單位明確。
- **Stat Card 標題正名**為「件數」，配合「佔總抽 X.XX%」前綴消除歧義。

## 4. 元件設計

### 4.1 新元件：`DistributionLegend`

路徑：`lib/widgets/distribution_legend.dart`

```dart
class DistributionEntry {
  const DistributionEntry({
    required this.color,
    required this.name,
    required this.count,
    required this.rate, // 0.0 ~ 1.0
  });

  final Color color;
  final String name;
  final int count;
  final double rate;
}

class DistributionLegend extends StatelessWidget {
  const DistributionLegend({super.key, required this.entries});
  final List<DistributionEntry> entries;
}
```

排版規格：
- 每行：色塊（10×10 圓角 2）→ 名稱（固定寬，左對齊）→ 次數（彈性寬，右對齊，例 `12 次`）→ 率（固定寬，右對齊，例 `1.23%`）
- 數字使用 tabular-figures，便於上下對齊
- `count == 0` 的 entry 不渲染

### 4.2 修改：`RarityPie`

- 將每個 `PieChartSectionData` 改為 `showTitle: false`，不再渲染切片內文字
- 新增 module-level helper：
  ```dart
  List<DistributionEntry> rarityDistributionEntries(
    WishStats stats,
    GachaTokens tokens,
  ) { ... }
  ```
  回傳 5★/4★/3★ 三筆（不過濾 0，由 `DistributionLegend` 自行過濾）。

### 4.3 修改：`ItemTypePie`

- 同樣移除切片標題
- 新增 helper `itemTypeDistributionEntries(stats, tokens, l)`：回傳角色/武器/未知三筆（`unknownCount > 0` 才包含）
- helper 需傳入 `AppLocalizations` 以本地化「角色」「武器」「未知」名稱

### 4.4 不修改：`StatCard`、`ChartCard`、`WishStats`

`ChartCard` 已具備 `legend` 參數可直接注入，無需改動。`StatCard` API 已支援 label/value/subtitle，調整僅在呼叫端的字串。`WishStats` 已具備 `count` 與 `rate` getter。

## 5. 頁面變更

### 5.1 `OverviewPage`

**Row 1 Stat Card（程式碼修改點）：**

```dart
final fiveCard = StatCard(
  label: l.statsFiveStarCount,                     // 原 statsFiveStarRate
  value: '${stats.fiveStarCount}',
  accent: tokens.fiveStar,
  subtitle: l.statsShareOfTotal(
    (stats.fiveStarRate * 100).toStringAsFixed(2),
  ),                                               // 原裸 '1.23%'
);
// 4★ 同上
```

**Row 2 ChartCard：**

```dart
ChartCard(
  title: l.statsRarityDistribution,                // 原 5★/4★/3★ 中獎率串接
  chart: RarityPie(stats: stats),
  legend: DistributionLegend(
    entries: rarityDistributionEntries(stats, tokens),
  ),
),
ChartCard(
  title: l.statsItemTypeDistribution,              // 原 '角色 / 武器'
  chart: ItemTypePie(stats: stats),
  legend: DistributionLegend(
    entries: itemTypeDistributionEntries(stats, tokens, l),
  ),
),
```

### 5.2 `BannerPage`

只需更新 Row 2 的兩張 ChartCard（與 5.1 相同）。Row 1 沿用 `PityCard` + `StatCard(總抽數)`，無變更。

### 5.3 不變動的相鄰元件

OverviewPage 與 BannerPage 的 Row 2 都包含第 3 張 timeline 卡（`_LatestFiveStar` / `TimelineCard`）— 這張卡與本次主題無關，保持原樣。

## 6. l10n 變更

### 6.1 新增

| key | zh-Hant | en |
| --- | --- | --- |
| `statsFiveStarCount` | `5★ 件數` | `5★ Count` |
| `statsFourStarCount` | `4★ 件數` | `4★ Count` |
| `statsShareOfTotal` (param `rate`，型別 `String`) | `佔總抽 {rate}%` | `{rate}% of total` |
| `statsRarityDistribution` | `稀有度分布` | `Rarity Distribution` |
| `statsItemTypeDistribution` | `類型分布` | `Type Distribution` |

zh-Hans 同步、en 沿用既有翻譯風格。

### 6.2 移除

- `statsFiveStarRate`、`statsFourStarRate`、`statsThreeStarRate`、`statsCharacterRate`、`statsWeaponRate`

確認無其他引用（grep 確認後可安全刪除）。

### 6.3 重新生成

執行 `flutter gen-l10n` 更新 `lib/l10n/generated/`。

## 7. 邊界情況

| 狀況 | 處理 |
| --- | --- |
| 總抽 = 0 | 沿用既有 `statsNoData` 提示，餅圖與圖例皆不顯示 |
| 某類別 count = 0 | 該 entry 從圖例隱藏（餅圖切片本就不畫） |
| `unknownCount > 0` | 圖例多一行「未知」 |
| 窄寬螢幕 | 沿用 ChartCard 既有 layout（legend 在 chart 下方） |
| ChartCard 高度 | 先沿用既有 `height: 260`；實作時實機檢視，若餅圖被擠壓再於頁面端調整 |

## 8. 測試影響

- `test/services/wish_stats_test.dart`：無需修改（資料層未動）。
- `test/widgets/cards/chart_card_test.dart`：原本測試已涵蓋 `legend` 注入，預期通過。
- 新增測試（建議，可由實作 plan 決定是否納入）：
  - `test/widgets/distribution_legend_test.dart`：驗證 `count = 0` 過濾、欄位排版、tabular figures。
- 既有 widget 測試若 hardcode 舊 l10n key（如 `statsFiveStarRate`），需同步更新斷言字串。

## 9. 不在此範圍

- Hover / tooltip 互動（fl_chart 預設行為已可滿足）
- 「率視圖 / 數視圖」切換
- 顏色主題重整、字體系統調整
- BannerPage 的 `PityCard` 與保底相關卡片
- BannerPage Row 1 的「總抽數」`StatCard`（純數，無混淆）

## 10. 未來可選延伸（不本次處理）

- 使用者自訂圖例排序（依次數 / 名稱）
- 點擊圖例 row 高亮對應扇形
- 匯出 CSV 時新增 `rate` 欄
