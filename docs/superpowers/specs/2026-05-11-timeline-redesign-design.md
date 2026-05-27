# 時間軸重新設計

| 項目 | 內容 |
|---|---|
| 日期 | 2026-05-11 |
| 主題 | 重新設計三處時間軸相關區塊 |
| 動機 | 現有 TimelineCard 視覺層次太弱,看起來「不像時間軸」 |
| 範圍 | `OverviewPage` Row 2、`OverviewPage` 下方、`BannerPage` Row 2 |

---

## 1. 背景

### 1.1 現況

專案目前有三處「時間軸相關」區塊,實作不一致:

| 位置 | 元件 | 現況 |
|---|---|---|
| BannerPage Row 2(ChartCard 槽位)| `TimelineCard` | 5★ 膠囊橫排,左→右 = 新→舊,寬版橫向 scroll、窄版 (<320px) 縱向 |
| OverviewPage Row 2(同槽位)| `_LatestFiveStar`(在 `overview_page.dart` 內) | 僅顯示一行文字「最新:XXX (N 抽)」,不是時間軸 |
| OverviewPage 下方 | `FiveStarList` | 卡片容器內的 4 欄表格(名稱 / 卡池 / N 抽 / 日期時間)|

### 1.2 問題

- 視覺上沒有「軸線」「節點」這類時間軸隱喻,只是一排小卡或表格
- 三處實作各自獨立,資料計算邏輯(從 records 萃取 5★ 並計算 pull-since-prev)在兩個檔案中重複
- Overview Row 2 與 BannerPage Row 2 是同個槽位卻長得完全不一樣

### 1.3 設計目標

1. 三處統一為「真正的時間軸」視覺隱喻(軸線 + 節點)
2. 資料層收斂為單一純函式來源
3. 橫向版本與直向版本各自針對自己的版位最佳化,不強行共用排版

---

## 2. 視覺設計決策(已確認)

| 決策點 | 結論 |
|---|---|
| 時間軸視覺隱喻 | **橫向時間軸 (A)** 用於兩處 Row 2;**直向時間軸 (B)** 用於 Overview 下方 |
| 橫向節點密度 | 顯示全部 5★ + 橫向 scroll,跟現行行為一致 |
| 橫向節點排版 | **變體 1 上下分流**:名稱 / 節點 / 日期+抽數 三行 |
| 排序方向 | 左 → 右 = 新 → 舊(橫向);上 → 下 = 新 → 舊(直向)|
| 直向分組 | 月份分組,但**軸線連續不中斷** — 月份標籤置於軸線左外側 |
| 「現在」標記 | **加在 BannerPage A 與 Overview B**,不加在 Overview A(跨卡池且空間小,意義不明)|

---

## 3. 架構

### 3.1 檔案結構

```
lib/
├── services/
│   └── timeline_entries.dart          ← 新增:純函式 + Entry model
├── widgets/
│   ├── banner_colors.dart             ← 新增:從 five_star_list 抽出
│   └── cards/
│       ├── timeline_horizontal.dart   ← 新增
│       └── timeline_vertical.dart     ← 新增

lib/widgets/cards/timeline_card.dart   ← 刪除
lib/widgets/data/five_star_list.dart   ← 刪除

test/
├── services/
│   └── timeline_entries_test.dart     ← 新增
└── widgets/cards/
    ├── timeline_horizontal_test.dart  ← 新增
    ├── timeline_vertical_test.dart    ← 新增
    └── timeline_card_test.dart        ← 刪除
```

被改動的頁面:`overview_page.dart`、`banner_page.dart`(import 與 Row 2/下方 widget 替換)。
i18n 變更:`app_en.arb`、`app_zh.arb`、`app_zh_Hant.arb`、`app_zh_Hans.arb`(新增 / 刪除字串)。

### 3.2 共用 vs 不共用

| 共用 | 不共用 |
|---|---|
| `TimelineEntry` model | A 與 B 的 widget 本體 |
| `buildTimelineEntries*()` 純函式 | A 的 chip 排版、B 的月份標籤排版 |
| `BannerColors` 配色表 | 節點繪製細節(尺寸、軸線方向) |

理由:A 是「上下分流 + 軸線居中」、B 是「左軸 + 月份外側標籤」,排版結構差異夠大,共用 widget 會把分支邏輯包進 widget 反而難維護(YAGNI)。資料層與配色才有真共用價值。

---

## 4. 元件規格

### 4.1 `lib/services/timeline_entries.dart`

純函式,無 widget 依賴。

```dart
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.name,
    required this.gachaType,
    required this.time,
    required this.pullsSincePrev,
  });
  final String name;
  final String gachaType;
  final DateTime time;
  final int pullsSincePrev;
}

/// 單一卡池:從 desc-by-time 的 records 萃取 5★。
/// 回傳結果依時間 desc(最新在前)。
List<TimelineEntry> buildTimelineEntries(List<WishRecord> records);

/// 跨卡池:合併所有卡池的 entries,依時間 desc 排序。
/// 注意:跨卡池版的 pullsSincePrev 仍以「該 entry 所屬卡池的上一筆 5★」為基準,
/// 不是「跨卡池上一筆」 — 因為保底計算永遠是 per-pool 的。
List<TimelineEntry> buildTimelineEntriesAcrossBanners(
  Map<String, List<WishRecord>> banners,
);

/// 從 desc 排序的 records 中,計算「最後一個 5★ 之後又抽了多少抽」。
/// 若沒有任何 5★,回傳 records.length(從頭累計)。
int pullsSinceLastFiveStar(List<WishRecord> records);

/// 跨卡池:從 banners map 計算「自跨卡池最新的 5★ 之後,
/// 跨全部卡池又共抽了多少筆」。
/// 若所有卡池皆無 5★,回傳所有卡池 record 數總和。
int pullsSinceLastFiveStarAcrossBanners(
  Map<String, List<WishRecord>> banners,
);
```

實作要點:
- 現有 `TimelineCard._buildEntries` 與 `FiveStarList._build` 的計算邏輯合併在這裡
- 跨卡池 `buildTimelineEntriesAcrossBanners` 等同於對每個卡池跑 `buildTimelineEntries` 然後 merge sort

### 4.2 `lib/widgets/banner_colors.dart`

```dart
@immutable
class BannerColors {
  const BannerColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.fallback,
  });

  factory BannerColors.fromTokens(GachaTokens tokens) => BannerColors(
    character: tokens.character,
    weapon: tokens.weapon,
    chronicled: tokens.accentPrimary,
    standard: tokens.threeStar,
    beginner: tokens.textMuted,
    fallback: tokens.textMuted,
  );

  // ... 6 個 Color 欄位

  Color colorFor(String gachaType) => switch (gachaType) {
    '301' => character,
    '302' => weapon,
    '500' => chronicled,
    '200' => standard,
    '100' => beginner,
    _ => fallback,
  };
}
```

行為與現有 `FiveStarListColors` 完全相同,但搬到共用位置並加 `fromTokens` factory 收斂 token mapping。

### 4.3 `lib/widgets/cards/timeline_horizontal.dart`

**API**

```dart
class TimelineHorizontal extends StatelessWidget {
  const TimelineHorizontal({
    super.key,
    required this.entries,        // 已依時間 desc 排序
    required this.colors,
    this.nowPulls,                // null = 不顯示「現在」標記
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;
}
```

**排版規格**

- 外層:`SingleChildScrollView(scrollDirection: Axis.horizontal)` + `Stack`
- 背景層:水平軸線一條(2px 實線,`textMuted` 半透明),貫穿整個內容寬度,定位在容器中央 (y = 50%)
- 前景層:`Row` of 節點欄
- 排序方向:左 → 右 = 新 → 舊;若 `nowPulls != null`,「現在」欄為最左欄
- 每個 entry 欄位寬 ~90px,內部 3 行(上至下):
  1. 名稱:`BannerColors.colorFor(gachaType)`、bold、12px
  2. 節點:直徑 14px 圓、banner 色填滿、外圍 halo(實心 banner 色 2px 環)
  3. 中繼資料:`textMuted`、10px、格式 `MM/dd · N抽`(用 `intl.DateFormat('MM/dd')`)
- 「現在」欄(若 `nowPulls != null`)
  - 節點:**中空圓**(transparent fill + banner 色或 `accentPrimary` border)+ 虛線 halo
  - 名稱位置:`l.timelineNowLabel`("現在")
  - 中繼位置:`l.timelineNowPulls(nowPulls)`("已 N 抽")
- 空狀態(`entries.isEmpty && nowPulls == null`):顯示 `l.timelineNoRecords` 置中
- `entries.isEmpty && nowPulls != null`:仍渲染單一「現在」欄
- 不再做 <320px 縱向 fallback(B 已是縱向版本,A 在窄寬下仍橫向 scroll)
- 抽數欄位使用 `FontFeature.tabularFigures()` 對齊數字

### 4.4 `lib/widgets/cards/timeline_vertical.dart`

**API**

```dart
class TimelineVertical extends StatelessWidget {
  const TimelineVertical({
    super.key,
    required this.entries,           // 已依時間 desc 排序
    required this.colors,
    this.nowPulls,                   // null = 不顯示「現在」row
    this.isAcrossBanners = false,    // 決定「現在」row 顯示哪段 i18n 文案
  });

  final List<TimelineEntry> entries;
  final BannerColors colors;
  final int? nowPulls;
  final bool isAcrossBanners;
}
```

**排版規格**

- 最外層:Container 帶 `surfaceCard` 背景、`borderSubtle` 1px border、`AppRadius.md` 圓角(沿用現有 FiveStarList 容器樣式)
- 內部:`Stack`
  - 背景層:垂直軸線(2px,`textMuted` 半透明),從容器內邊距上緣到下緣
  - 前景層:`Column` of rows
- Row 結構:三欄
  1. 左欄(寬 ~80px,軸線外側):月份標籤,僅當「此 row 跨入新月份」才顯示
  2. 節點圓(14px,定位疊在軸線上)
  3. 主內容(軸線右側 padding-left 18px):名稱(banner 色,bold,14px) + 中繼資料(textMuted,12px)
- 中繼資料格式:`MM/dd · {卡池名} · {N} 抽`(卡池名透過 `gachaTypes.firstWhere(...).resolveName(l)` 解析,沿用現有 FiveStarList 做法)
- 月份判定:遍歷 entries,以 `year * 12 + month` 比對相鄰 entry,當不同時較新的 row 顯示月份標籤;最頂端的 row 一定有月份標籤
- 月份標籤格式:`DateFormat.yMMM(Localizations.localeOf(context).toLanguageTag()).format(...)`(透過 `intl` 自動本地化,例:"Apr 2025" / "2025年4月")
- 「現在」row(若 `nowPulls != null`)
  - 永遠是第一個 row(最頂),不參與月份分組
  - 節點為**中空圓**(transparent fill + banner 色或 `accentPrimary` border)+ 虛線 halo
  - 名稱位置:`l.timelineNowLabel`
  - 中繼位置:`isAcrossBanners == true` → `l.timelineNowSinceCrossPool(nowPulls)`;否則 → `l.timelineNowSinceLast(nowPulls)`
- 空狀態(`entries.isEmpty && nowPulls == null`):容器內 vertical padding `AppSpacing.xl`,中央顯示 `l.timelineNoRecords`
- `entries.isEmpty && nowPulls != null`:仍渲染單一「現在」row
- 抽數欄位使用 `FontFeature.tabularFigures()` 對齊

---

## 5. 頁面整合

### 5.1 `overview_page.dart`

- **刪除**:檔案末端的 `_LatestFiveStar` private widget
- **Row 2 第 3 格**(原 `_LatestFiveStar`):
  ```dart
  ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineHorizontal(
      entries: buildTimelineEntriesAcrossBanners(activeData.banners),
      colors: BannerColors.fromTokens(tokens),
      // 不傳 nowPulls,跨卡池 Row 2 不顯示現在標記
    ),
  )
  ```
- **下方原 FiveStarList**:
  ```dart
  TimelineVertical(
    entries: buildTimelineEntriesAcrossBanners(activeData.banners),
    colors: BannerColors.fromTokens(tokens),
    nowPulls: pullsSinceLastFiveStarAcrossBanners(activeData.banners),
    isAcrossBanners: true,
  )
  ```
- 移除 `import 'package:.../five_star_list.dart';`(`wish_stats.dart` 仍被上方 StatCard 計算使用,保留)

### 5.2 `banner_page.dart`

- **Row 2 第 3 格**(原 `TimelineCard`):
  ```dart
  ChartCard(
    title: l.timelineCountFiveStar(stats.fiveStarCount),
    chart: TimelineHorizontal(
      entries: buildTimelineEntries(records),
      colors: BannerColors.fromTokens(tokens),
      nowPulls: pullsSinceLastFiveStar(records),
    ),
  )
  ```
- 移除 `import 'package:.../timeline_card.dart';`

---

## 6. i18n 變更

### 6.1 新增字串

| Key | en | zh-Hant | zh-Hans |
|---|---|---|---|
| `timelineNowLabel` | `Now` | `現在` | `现在` |
| `timelineNowPulls` | `{n} pulls` | `已 {n} 抽` | `已 {n} 抽` |
| `timelineNowSinceLast` | `{n} pulls since last 5★` | `距上次 5★ {n} 抽` | `距上次 5★ {n} 抽` |
| `timelineNowSinceCrossPool` | `{n} pulls since last 5★ across all banners` | `從上次 5★ 至今 {n} 抽` | `从上次 5★ 至今 {n} 抽` |

`{n}` 使用 `placeholders` 設為 `int`。

### 6.2 移除字串

- `timelineLatestEntry`(僅 `_LatestFiveStar` 使用,該元件刪除)

### 6.3 保留字串

- `timelineNoRecords`、`timelineSinceLast`、`timelineCountFiveStar`(`timelineCountFiveStar` 仍用作 ChartCard 標題)

### 6.4 重新產生

執行 `flutter gen-l10n` 後,`lib/l10n/generated/*.dart` 會自動更新。

---

## 7. 錯誤處理 / 邊界條件

| 狀況 | 行為 |
|---|---|
| `entries.isEmpty && nowPulls == null` | 顯示 `l.timelineNoRecords` 置中(A: 整個橫向區;B: 容器中央)|
| `entries.isEmpty && nowPulls != null` | 仍渲染單一「現在」節點 |
| `nowPulls == 0` | 仍顯示「現在 · 已 0 抽」(代表剛抽到 5★ 後尚未開始累積)|
| 月份分組跨年 | 使用 `year * 12 + month` 判定,跨年正確 |
| `gachaType` 未知 | `BannerColors.colorFor` 走 `_` => fallback,沿用現有行為 |
| Locale 切換 | 月份標籤透過 `DateFormat.yMMM(locale)` 自動更新;hot reload 時 widget rebuild 即可 |

---

## 8. 測試策略

### 8.1 `test/services/timeline_entries_test.dart`(純函式,優先級最高)

- `buildTimelineEntries`:
  - 空 records → 空 list
  - 只含非 5★ records → 空 list
  - 多筆 5★ 計算 pullsSincePrev(包含「第一個 5★ 從頭累計」案例)
  - 輸出依時間 desc
- `buildTimelineEntriesAcrossBanners`:
  - 多卡池合併後依時間 desc
  - 每筆 pullsSincePrev 仍依 per-pool 計算,不受跨卡池影響
- `pullsSinceLastFiveStar`:
  - 無 5★ → 回傳 records.length
  - 有 5★ → 回傳「desc 排序中第一個 5★ 之前(即時間上之後)的 record 數」
- `pullsSinceLastFiveStarAcrossBanners`:
  - 多卡池中找到跨卡池最新 5★,計算其後所有 record(跨卡池)總數
  - 所有卡池都無 5★ → 回傳所有 record 數總和

### 8.2 `test/widgets/cards/timeline_horizontal_test.dart`

- 空狀態:`entries.isEmpty && nowPulls == null` 時找到 `timelineNoRecords` 文字
- N entries 渲染 N 個節點
- `nowPulls != null` 時節點數為 N+1,且「現在」位於最左
- 4★ 紀錄不出現(間接驗證,透過 entries 已過濾)
- banner 色 stripe 對應正確(取樣一個 entry 的 name 文字色)

### 8.3 `test/widgets/cards/timeline_vertical_test.dart`

- 月份跨界正確產生 month tag(餵入 2025/04 vs 2025/03 兩筆,驗證 month tag 出現次數)
- `nowPulls != null` 時頂端多一個「現在」row(`isAcrossBanners` true / false 各驗一次 i18n)
- 空狀態
- 卡池名顯示正確(餵入 gachaType '301',驗證表頭文字 == 角色池本地化字串)

### 8.4 既有測試清理

- 刪除 `test/widgets/cards/timeline_card_test.dart`
- 若有其他測試 import 了 `TimelineCard` / `FiveStarList`,跟著改

---

## 9. YAGNI 邊界(本次不做)

- 不加入「4★ 也顯示在時間軸」功能
- 不加入節點點擊互動(跳轉/開 dialog)
- 不加入 Overview B 的卡池篩選 UI
- 不加入「贏 / 輸 50/50」標記(需新資料計算,且現有資料模型未追蹤)
- 不引入第三方 timeline 套件(自行客製成本可接受)

未來若需要任一項,屆時再開新 spec。

---

## 10. 風險

| 風險 | 嚴重度 | 緩解 |
|---|---|---|
| `_LatestFiveStar` 刪除後,Overview Row 2 視覺密度感受改變(從一行文字變成橫向時間軸)| 低 | 設計目標即如此;若使用者反饋不喜歡可調整節點密度 |
| 月份標籤左欄寬度在 zh / en 下差異大("Apr 2025" vs "2025年4月")| 低 | 預留 80px 寬,實作時測兩語系並調整 |
| `pullsSinceLastFiveStarAcrossBanners` 在 Overview 跨卡池語意可能引起誤解 | 低 | i18n 文案「從上次 5★ 至今 N 抽」已明示「跨卡池」概念;若仍混淆,可改文案 |

---

## 11. 驗收條件

1. `flutter analyze` 輸出 `No issues found!`
2. `flutter test` 輸出 `All tests passed!`
3. `dart format lib/ test/` 後無格式變動
4. 手動驗證(desktop window):
   - Overview Row 2 顯示橫向時間軸(跨卡池),無「現在」標記
   - Overview 下方顯示直向時間軸,軸線連續,月份標籤外側,頂端有「現在」row
   - BannerPage Row 2 顯示橫向時間軸,最左有「現在」中空節點
   - 切換 zh / en 月份標籤本地化正確
   - 空狀態(無紀錄、無 5★)畫面正常
