# 五星一覽（橫向圓形 Icon 列）設計

## 背景與目標

在各祈願頁面與綜合數據頁，使用者目前只能透過時間軸與記錄列表逐筆看五星，缺少一個「我在這個卡池／整體祈願總共抽到哪些五星、各抽到幾份」的總覽視圖。

本功能新增一個「五星一覽」區塊：把該範圍內所有不重複的五星物品，以**橫向排列的圓形 Icon**呈現，每個 Icon 右下角標示該物品**累計被抽到的次數**。一行排滿後自動往下換行，不限行數。

## 範圍

套用於下列三處：

1. **所有非頌願卡池頁**（`BannerPage`）：角色、武器、常駐、集約、新手、已結束等卡池；頌願（odes，`gachaType` `2000` / `1000`）不套用。
2. **綜合數據頁的祈願段**（`OverviewPage` 的 gacha section）：頌願段完全不動。
3. **分享圖**（`ShareCard`）：卡池分享圖與綜合分享圖，皆放在整張圖的**最尾端**。

頌願（頌願個別頁、綜合頁頌願段、分享圖頌願段）一律不納入本功能。

## 核心語意

- **去重 + 計數**：每個不重複的五星物品只有一個圓形 Icon；右下角徽章 = 該物品在範圍內被抽到的**總次數（份數）**，恆顯示（次數為 1 也顯示「1」）。
- **合併鍵**：以**物品名稱**（`GachaRecord.name`）為鍵。單一帳號內語系一致，同名即同物。
- **代表 record**：取該物品**最近一次**被抽到的 `GachaRecord`，用其 `name` / `lang` / `gachaType` 餵 `GachaItemIcon` 做圖示查找與 tooltip。
- **排序**：依 `count` **降冪**；次數相同時，以「最近抽到時間」**降冪**作為 tie-break（抽到次數最多者排最前，左上起逐行往下）。
- **綜合頁／綜合分享圖**：同物品**跨祈願卡池合併、次數相加**（例如某常駐五星在角色池與常駐池都出過，算同一個，次數累加），形成一條合併的五星一覽。
- **卡池頁／卡池分享圖**：僅該卡池自身的 records。

## 視覺樣式（已選定方案 A）

- **圓形 Icon**：邊長 48px（預設值，實作時若觀感需要可微調），使用 HoYoWiki 物品圖示；缺圖時沿用 `GachaItemIcon` 既有 placeholder。
- **外環**：統一 2px **金色**外環（`GachaTokens.fiveStar`，呼應五星），附輕微金色光暈。
- **徽章**：右下角金底深字圓形徽章，僅放數字，外圍以卡片底色描邊與 Icon 區隔。
- **互動**（僅 App 頁面）：Icon 可點擊開啟物品詳情 dialog（`GachaItemTapTarget`），hover 顯示物品名 `Tooltip`，滑鼠游標 `SystemMouseCursors.click`。分享圖為靜態圖，chip 不帶互動。
- **排版**：`Wrap` 左對齊、隨容器寬度自動換行、不限行數，由 `Wrap` 處理 RWD，不會爆版。
- **空狀態**：範圍內無任何五星時，整個區塊（含標題）不顯示。

## 架構與元件

### 1. 資料聚合（新檔 `lib/services/five_star_collection.dart`）

純函式 + 不可變資料類，不依賴 Flutter widget，便於單元測試：

```dart
@immutable
class FiveStarCollectionItem {
  final GachaRecord representative; // 最近一次抽到的紀錄；決定 icon 與 tooltip
  final int count;                  // 該物品被抽到的總次數
}

/// 單一 records 來源：取 rankType == 5，依 name 合併計數，依規則排序。
List<FiveStarCollectionItem> buildFiveStarCollection(List<GachaRecord> records);

/// 跨卡池：合併多卡池後，同 name 跨卡池累加，再依規則排序。
List<FiveStarCollectionItem> buildFiveStarCollectionAcrossBanners(
  Map<String, List<GachaRecord>> banners,
);
```

- 跨卡池版可在內部攤平所有 records 後委派給單一版的合併邏輯，避免重複。
- 關鍵節點埋 `Logger('wish.fiveStar')`：聚合後不重複物品數、跨卡池合併前後筆數等；敏感資料沿用既有脫敏規則（本功能不涉 URL／UID，主要記數量級 context）。

### 2. 呈現 widget（新檔 `lib/widgets/cards/five_star_overview.dart`）

- `FiveStarOverview`：接收 `List<FiveStarCollectionItem>`，以 `Wrap`（`spacing` / `runSpacing` 用 `AppSpacing`）排列 `_FiveStarChip`；空清單回傳 `SizedBox.shrink()`。提供 `interactive`（預設 `true`）參數，分享圖傳 `false`。
- `_FiveStarChip`（私有）：48px 圓形 `GachaItemIcon`（見下方擴充）+ 金色外環 + 右下角數字徽章；`interactive` 為真時外包 `GachaItemTapTarget` 與 `Tooltip`。

### 3. `GachaItemIcon` 擴充（`lib/widgets/gacha_item_icon.dart`）

- 新增可選參數讓它能渲染**圓形**（例如 `shape: BoxShape.rectangle`（預設）/ `circle`，或 `circular: false` 預設），預設行為與既有圓角方塊完全一致，時間軸等既有 callsite 零影響。
- 金環與徽章不進 `GachaItemIcon`（保持其單一職責），留在 `_FiveStarChip`。

### 4. 版面定位

- **`banner_page.dart`**：在「祈願記錄列表」`InlineSectionTitle`（現約 `:296`）**上方**插入獨立區塊：
  `InlineSectionTitle(icon: Icons.star_outline, title: l.fiveStarOverviewTitle)` + `FiveStarOverview(items: buildFiveStarCollection(records))`。無五星時整段隱藏。
- **`overview_page.dart`**：`_OverviewSection` 新增一個可選參數（聚合後的 `List<FiveStarCollectionItem>`，或預建好的 widget），**只在 gacha 段**傳入；放在時間軸 `InlineSectionTitle`（現約 `:398`）**上方**。odes 段不傳 → 完全不動。

### 5. 分享圖（`lib/widgets/share/share_card.dart`）

- `ShareCard.banner`：以 `records` 算 `buildFiveStarCollection(records)`。
- `ShareCard.overview`：以 `buildOverviewSections(banners).gacha.banners` 算 `buildFiveStarCollectionAcrossBanners(...)`（僅祈願卡池）。
- 在 `build` 的 `content` Column **最尾端**（所有 `_SectionView` 之後）加一個 `_FiveStarShareSection`：標題（`l.fiveStarOverviewTitle`）+ `FiveStarOverview(interactive: false)`。資料於 factory 階段算好存入欄位，build 階段渲染。
- 圖示渲染：沿用既有 `PreloadedHoYoWikiImages` + `UncontrolledProviderScope` 機制（`buildShareRenderTree` 已具備），`recordsForPreload` 既已涵蓋所需 records（卡池 = 該池；綜合 = 全卡池），無需新增預載管線。
- 分享圖寬固定 1200px、高隨內容自適應；`Wrap` 自然增高即可，不需裁切。

### 6. i18n

- 新增字串 key `fiveStarOverviewTitle`，值「五星一覽」。
- 先寫 `app_zh.arb`，再以繁中為基準翻譯至**已有實體翻譯**的 ARB；空殼 ARB 不碰（留給 Crowdin pipeline）。
- 徽章僅數字、tooltip 用物品名，無需額外字串。

## 錯誤處理與邊界

- 缺圖：`GachaItemIcon` 既有 placeholder。
- 物品數量很多：`Wrap` 自然換行；分享圖隨之增高（符合「放最尾端、不限行數」的需求）。
- 無五星：整段（含標題）隱藏。
- 頌願：`GachaItemIcon` 對 odes 本就回傳空，且本功能不在頌願範圍佈署，雙重保險。

## 測試

- **單元測試**（`buildFiveStarCollection` / `buildFiveStarCollectionAcrossBanners`）：
  - 去重計數正確；
  - 排序：次數降冪、同次數以最近時間降冪 tie-break；
  - 跨卡池同名合併、次數相加；
  - 只取 5★（排除 4★／3★）；
  - 空輸入回傳空清單；
  - 代表 record 取最近一次。
- **Widget 測試**（`FiveStarOverview`）：徽章數字正確、Icon 依排序呈現、空清單不顯示、`interactive: false` 不掛 tap target / tooltip。
- **分享圖**：可加一個離屏渲染 smoke test，確認尾端區塊存在且不崩。
- 若 `testWidgets` 用到 tempDir 圖檔，`tearDown` 需清 `ImageCache`，避免跨測試 codec race（見既有慣例）。

## 不做（YAGNI）

- 不為單卡池頁加卡池色環（方案 A 統一金環）。
- 不加「展開／收合」「載入更多」「上限 N 個」等控制；既然需求是不限行數，全部顯示。
- 不動頌願任何呈現。
- 不為跨卡池合併引入 HoYoWiki id 作為合併鍵（名稱足夠；單帳號語系一致）。
