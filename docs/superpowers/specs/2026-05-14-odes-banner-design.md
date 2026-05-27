# Spec：新增「頌願」（Odes）卡池類型

- 日期：2026-05-14
- 分支：`feat/odes-banner`
- 來源：使用者要求新增頌願（官方英文 **Odes**）卡池支援，並把側選單的祈願 / 頌願明顯分區。

> **命名約定**：程式碼識別符（enum、檔名、i18n key、變數）一律使用官方英文 **`odes`**。中文 UI 顯示為「頌願 / 活動頌願 / 常駐頌願」，英文 UI 顯示為「Odes / Event Odes / Standard Odes」。

## 1. 背景

目前應用程式只支援祈願（`getGachaLog` endpoint）5 種卡池（角色 301 / 武器 302 / 集錄 500 / 常駐 200 / 新手 100）。米哈遊新增頌願體系，使用獨立 endpoint `getBeyondGachaLog`，分兩種子卡池：

| gacha_type | 中文名 | 英文名 | 主保底 | 副保底 | 備註 |
|---|---|---|---|---|---|
| 2000 | 活動頌願 | Event Odes | 5★：70 抽 | 4★：10 抽 | 物品為「裝扮」 |
| 1000 | 常駐頌願 | Standard Odes | 4★：70 抽 | 3★：5 抽 | **沒有 5★**；有 2★（祈願無） |

頌願物品全為「裝扮」，與祈願的「角色 / 武器」是不同領域；常駐頌願甚至沒有 5★，打破現有 `GachaType.fiveStarPity / fourStarPity` 寫死兩欄的假設。

使用者觀察的 API URL 顯示活動頌願與常駐頌願 `authkey` 完全相同，代表**一張 authkey 兩個 endpoint 共用**。

## 2. 目標

1. 抓取活動頌願 / 常駐頌願記錄並存檔。
2. 側選單把「祈願」「頌願」分成兩個明顯的群組。
3. 各卡池頁面（BannerPage）根據卡池本身的保底規則顯示對應的 PityCard、RarityPie、Timeline。
4. 綜合頁（OverviewPage）拆成「祈願綜合」「頌願綜合」兩個獨立區塊。
5. **同步重構物品類型分類為動態**：移除 `WishItemKind` 寫死字串對應，改由實際 `item_type` 字串動態分類，祈願段一併受益。
6. 不重寫不該動的東西：儲存格式、抓取管線（merge / retry / progress）保持不變。

## 3. 非目標（YAGNI）

- 不為頌願做專屬的「部件 vs 動作」物品類型分布圖（資料分類不夠明確，等明確需求再加）。
- 不改 `appName` 字串（`原神祈願卡池分析`）— 雖然名稱不再完全準確，但變更會牽動所有平台 metadata，本次先擱置。
- 不做頌願 banner 各自的「綜合」頁。
- **i18n 不補占位翻譯**：除 `en` / `zh_Hant` / `zh_Hans` 三份 ARB 外，其他 7 種語言檔（es / fr / ja / pt / th / vi / zh）**完全不動**；缺 key 由 Flutter i18n 自動 fallback 到 `en`。

## 4. 設計

### 4.1 資料模型：`GachaType` 改為資料驅動的保底列表

**目的**：消除「最高 = 5★」「次高 = 4★」的硬假設，讓常駐頌願（最高 4★ / 次高 3★）可以共用同一套 PityCard / Timeline / Stats 渲染邏輯。

`lib/data/gacha_types.dart`：

```dart
enum GachaCategory { wish, odes }

class PityRule {
  const PityRule({
    required this.rank,
    required this.threshold,
    required this.labelKey,
  });
  final int rank;          // 5 / 4 / 3
  final int threshold;     // 保底抽數
  final String labelKey;   // i18n key: 'pityFiveStar' / 'pityFourStar' / 'pityThreeStar'
}

class GachaType {
  const GachaType({
    required this.gachaType,
    required this.nameKey,
    required this.category,
    required this.pities,
  });

  final String gachaType;
  final String nameKey;
  final GachaCategory category;
  /// 由高 rank 到低 rank。[0] 為主保底，[1] 為副保底。
  final List<PityRule> pities;

  PityRule get primaryPity => pities[0];
  PityRule? get secondaryPity => pities.length > 1 ? pities[1] : null;
  String resolveName(AppLocalizations l) => ...; // 加入頌願兩個 case
}
```

完整清單：

| gacha_type | nameKey | category | pities |
|---|---|---|---|
| 301 | gachaTypeCharacter | wish | `[(5, 90, pityFiveStar), (4, 10, pityFourStar)]` |
| 302 | gachaTypeWeapon | wish | `[(5, 80, pityFiveStar), (4, 10, pityFourStar)]` |
| 500 | gachaTypeChronicled | wish | `[(5, 90, pityFiveStar), (4, 10, pityFourStar)]` |
| 200 | gachaTypeStandard | wish | `[(5, 90, pityFiveStar), (4, 10, pityFourStar)]` |
| 100 | gachaTypeBeginner | wish | `[(5, 20, pityFiveStar), (4, 10, pityFourStar)]` |
| 2000 | gachaTypeOdesEvent | odes | `[(5, 70, pityFiveStar), (4, 10, pityFourStar)]` |
| 1000 | gachaTypeOdesStandard | odes | `[(4, 70, pityFourStar), (3, 5, pityThreeStar)]` |

**衝擊面**：所有引用 `t.fiveStarPity / t.fourStarPity` 的位置改為 `t.primaryPity.threshold / t.secondaryPity?.threshold`。

### 4.2 API endpoint：擴充 `/getBeyondGachaLog`

**Rust mitm**（`rust/src/mitm.rs:34`）：

```rust
fn is_target(uri: &Uri) -> bool {
    let host_ok = uri.host()
        .map(|h| h == "hoyoverse.com" || h.ends_with(".hoyoverse.com"))
        .unwrap_or(false);
    let path = uri.path();
    let path_ok = path.ends_with("/getGachaLog")
               || path.ends_with("/getBeyondGachaLog");
    host_ok && path_ok
}
```

其他攔截 / shutdown 邏輯不動。

**Dart `GachaUrl`** 增加 `endpoint` 概念：

```dart
enum GachaEndpoint {
  wish('getGachaLog'),
  odes('getBeyondGachaLog');
  const GachaEndpoint(this.pathSegment);
  final String pathSegment;
}

class GachaUrl {
  Uri build({
    required String gachaType,
    required String endId,
    required GachaEndpoint endpoint,   // 新增
    int size = 20,
    int page = 1,
  }) {
    // 1. 替換 path 最後一段為 endpoint.pathSegment
    // 2. 維持 query params 改寫邏輯
  }
}
```

`GachaCategory` → `GachaEndpoint` 由簡單 switch 對應（wish→wish、odes→odes）。

### 4.3 抓取邏輯：依 category 切 endpoint

`WishFetcher`：

- `fetchPage` 不變。
- `fetchBannerWithMerge` 多吃 `endpoint` 參數，傳給 `url.build`。
- `probeUid` 改為依序探測：先跑所有 wish banner 各 1 頁 → 若都空再跑所有 odes banner 各 1 頁。第一筆非空回傳 uid。

`WishRepository._fetchAllBanners`：

- 對 `gachaTypes` 中每個 type，依其 `category` 決定 `endpoint` 傳給 `fetchBannerWithMerge`。
- 其他 merge / progress / failed 處理完全不變。

**authkey 假設**：兩個 endpoint 共用同一張 authkey。若實際 API 拒絕跨 endpoint（HTTP 200 但 retcode != 0），會在 `AuthExpired / ApiError` 流程被攔到，使用者可以重新 capture。**這是設計核心假設**。

### 4.4 儲存：完全不變

`BannerStorage.banners: Map<String, List<WishRecord>>` 的 key 直接加入 "1000" / "2000"。**舊使用者升級後讀檔不會壞**，缺的 key 在抓取時自然填入。

`WishRecord.rank_type` 本來就是 `int`，2 / 3 / 4 / 5 全部支援。

### 4.5 物品類型動態分類（同步重構祈願段）

**移除 `WishItemKind` enum 與其字串對應表**。改用 `item_type` 字串本身當分類 key — API 回傳的 `item_type` 已是當前 `lang` 對應的本地化字串（祈願：「角色」「Character」「武器」「Weapon」；頌願：「裝扮」「Outfit」），直接顯示即可，不必再寫死翻譯對應表。

**`lib/models/wish_record.dart`**：

- 移除 `WishItemKind` enum 整段。
- `WishRecord` 移除 `kind` 欄位（保留 `itemType` 字串）。
- `fromApiJson` / `fromStorageJson` / `toStorageJson` 移除 `kind` 相關邏輯。
- **儲存檔向後相容**：舊版 `toStorageJson` 本就不存 `kind`（從 itemType 推導），新版直接不推導即可；讀舊檔不會壞。

**`lib/services/wish_stats.dart`**：

```dart
class WishStats {
  final int total;
  final int fiveStarCount;
  final int fourStarCount;
  final int threeStarCount;
  final int twoStarCount;                    // 新增（頌願才出現）
  final Map<String, int> byItemType;         // 動態 key = itemType 字串
  // 移除 characterCount / weaponCount / unknownCount
}
```

`byItemType` 依出現順序累計；UI 渲染時 sort by count desc。空字串 `itemType` 歸入 fallback key（i18n 顯示 `kindUnknown` =「未知」/「Unknown」— 保留此 key）。

**`lib/services/wish_filter.dart`**：

- 移除 `enum KindFilter { all, character, weapon }`。
- `RecordFilter.kind` 改為 `String? itemType`（null = 全部）。
- `filterRecordRows` 內：`if (f.itemType != null && r.itemType != f.itemType) return false;`
- `SortColumn.kind` 維持，排序仍依 `r.itemType` 字串（既有行為已是）。

**`lib/widgets/data/search_filter_bar.dart`**：

- 第二個 dropdown 由「角色 / 武器」靜態 enum 換成「依當前 banner 出現過的 `itemType` 字串動態列舉」+ 「全部類型」first item。
- BannerPage 傳入 `availableItemTypes: List<String>`（從當前 banner records 萃取 unique itemType，按字母排序）。

**`lib/widgets/item_type_pie.dart`**：

- `itemTypeDistributionEntries(stats, palette, l)` 改為遍歷 `stats.byItemType.entries`，依 count desc 排序後依序從 palette 分配顏色：
  ```dart
  const palette = [tokens.character, tokens.weapon, tokens.accentPrimary,
                   tokens.threeStar, tokens.twoStar, tokens.textMuted];
  // index 大於 palette 長度時 wrap-around 或用 textMuted fallback
  ```
- `ItemTypePie` 同理動態產生 sections。
- 頌願 banner 自然顯示「裝扮 100%」單一 ring；活動頌願與常駐頌願都是有效資料（不必特殊隱藏）。

### 4.6 側選單分區

`lib/pages/app_shell.dart` 的 `_Rail` 重新結構：

```
┌──────────────┐
│ 綜合          │  ← rail-top（標準 NavigationRail）
│ ─ 祈願 ─      │  ← section label + divider
│ 角色          │
│ 武器          │  ← rail-wish（5 個 destinations）
│ 集錄          │
│ 常駐          │
│ 新手          │
│ ─ 頌願 ─      │  ← section label + divider
│ 活動頌願      │  ← rail-odes（2 個 destinations）
│ 常駐頌願      │
├──────────────┤
│ 貢獻者        │  ← 既有底部按鈕，不動
│ 設定          │
└──────────────┘
```

實作：把現有單一 `NavigationRail` 拆成三段，外層用 `Column` 串接。**`NavigationRail` 不接受任意 widget 作為 destination，必須用「多個 NavigationRail + 中間插自製 section header」的方式**。每條 rail 各自管自己的 `selectedIndex`，依當前路徑互斥（落在哪條 rail 就只有那條有 selected）。

- **extended 模式**：section label 顯示「祈願」/「頌願」全字、字體用 `labelMedium` 配 `textMuted`。
- **collapsed 模式 + 有 label**：section label 用更小的字（如 `labelSmall`）。
- **collapsed + no label（最窄）**：section label 隱藏，只剩 divider 不占太多視覺空間。

`_bannerIndexFromLocation` 改為 `_resolveRailSelection(path)`，回傳對應 rail 的 nullable index。

### 4.7 BannerPage：由 `pities` 驅動

`PityCard` 重構：接受一個 `PityRule` 跟 `records`，內部自己算 `current` / `threshold`。配色由 `rank` 對應到 token：

```dart
Color accentFor(int rank, GachaTokens t) => switch (rank) {
  5 => t.fiveStar,
  4 => t.fourStar,
  3 => t.threeStar,
  2 => t.twoStar,
  _ => t.textMuted,
};
```

`BannerPage` 直接：

```dart
PityCard(rule: type.primaryPity, records: records, accent: accentFor(type.primaryPity.rank, tokens))
if (type.secondaryPity != null)
  PityCard(rule: type.secondaryPity!, records: records, accent: accentFor(type.secondaryPity!.rank, tokens))
```

- **RarityPie**：擴展支援 2★。新增 `tokens.twoStar` 顏色 token，更新 `rarityDistributionEntries` 包含 2★ 項（若為 0 略過）。
- **ItemTypePie**：依 §4.5 動態渲染，頌願 banner 不必特殊隱藏。
- **Timeline**：`buildTimelineEntries` 加 `targetRank` 參數，預設 5★；BannerPage 傳入 `type.primaryPity.rank`（常駐頌願 = 4）。Timeline 標題 i18n 改為 `timelineCountTopRarity` 接 `{rank, n}` 雙參數，全部 banner 共用一個 key。
- **配色**：`BannerColors.colorFor` 加 1000 / 2000 case，新增對應 tokens（`odesEvent` / `odesStandard`）。
- **圖示**：`_iconForGachaType` 加兩個 case，建議 `Icons.auto_awesome` / `Icons.auto_awesome_motion`。

### 4.8 OverviewPage：拆兩個獨立區塊

`OverviewPage` 結構：

```
PageHeader: 綜合
─────────────────────
■ 祈願 綜合（pageOverviewWishSection）
  Stat 卡列：總抽數 / 5★ 件數 / 4★ 件數
  Pie 列：稀有度分布 / 物品類型分布（動態）
  Bar：各祈願卡池 5★ 件數（5 條）
  Timeline：5★ 時間軸（祈願跨卡池）
─────────────────────
■ 頌願 綜合（pageOverviewOdesSection）
  Stat 卡列：總抽數 / 活動頌願 5★ 件數 / 常駐頌願 4★ 件數
  Pie 列：稀有度分布（含 2★）/ 物品類型分布（動態）
  Bar：各頌願卡池主稀有度件數（2 條：活動 5★、常駐 4★）
  Timeline：頌願跨卡池主稀有度時間軸（混軸，依 banner 配色區分）
─────────────────────
```

實作：

- 新增 helper：`Map<String, List<WishRecord>> filterBannersByCategory(banners, category)`。
- `BannerFiveStarBars` 改名 / 泛化為 `BannerTopRarityBars`，接受 `types: List<GachaType>` 子集，每池用自己 `primaryPity.rank` 算「該稀有度件數」，標題用 i18n `bannerTopRarityCountTitle`。祈願段傳 wish 5 個 type，效果與現有完全一致。
- `buildTimelineEntriesAcrossBanners` 多吃 `rankFor: int Function(String gachaType)`：祈願段傳「永遠回 5」，頌願段傳「依 type.primaryPity.rank」。
- 頌願 Stat 卡的「總抽數」**只算頌願 banner 的 records 數量**，不與祈願合計。

若某使用者完全沒有頌願記錄（兩條 banner 都空），整個「頌願 綜合」section 顯示一個小的 EmptyState「尚無頌願記錄」，不渲染下方圖表。

### 4.9 i18n

**範圍**：只更新 `lib/l10n/app_en.arb` / `app_zh_Hant.arb` / `app_zh_Hans.arb`。其他 7 種語言檔不動，缺 key 自動 fallback 到 `en`。

**新增 key**：

| key | zh_Hant | zh_Hans | en |
|---|---|---|---|
| `gachaTypeOdesEvent` | 活動頌願 | 活动颂愿 | Event Odes |
| `gachaTypeOdesStandard` | 常駐頌願 | 常驻颂愿 | Standard Odes |
| `navOdesEvent` | 活動頌願 | 活动颂愿 | Event Odes |
| `navOdesStandard` | 常駐頌願 | 常驻颂愿 | Standard Odes |
| `navSectionWish` | 祈願 | 祈愿 | Wish |
| `navSectionOdes` | 頌願 | 颂愿 | Odes |
| `pageOverviewWishSection` | 祈願綜合 | 祈愿综合 | Wish overview |
| `pageOverviewOdesSection` | 頌願綜合 | 颂愿综合 | Odes overview |
| `pityThreeStar` | 3★ 保底 | 3★ 保底 | 3★ pity |
| `statsThreeStarCount` | 3★ 件數 | 3★ 件数 | 3★ count |
| `statsTwoStarCount` | 2★ 件數 | 2★ 件数 | 2★ count |
| `bannerTopRarityCountTitle` | 各卡池主稀有度件數 | 各卡池主稀有度件数 | Top-rarity count per banner |
| `emptyNoOdesRecords` | 尚無頌願記錄 | 暂无颂愿记录 | No Odes records yet |
| `timelineCountTopRarity` | {rank}★ 時間軸 ({n}) | {rank}★ 时间轴 ({n}) | {rank}★ timeline ({n}) |

**移除 key**（祈願段同步重構帶來的）：

- `kindCharacter` / `kindWeapon` — 不再寫死，從 record.itemType 直接取
- `filterKindCharacter` / `filterKindWeapon` — 改為動態 dropdown，由實際資料驅動

**保留 key**：

- `kindUnknown` — itemType 為空字串時 fallback 顯示
- `filterKindAll` — dropdown 第一項「全部類型」
- `timelineCountFiveStar` — **移除**，由 `timelineCountTopRarity` 取代（祈願 banner 傳 rank=5）

### 4.10 Rust 端

`rust/src/mitm.rs:34` 改 `is_target` 接受兩個 endpoint。其他不動。

## 5. 衝擊面與測試

### 影響到的檔案

- `lib/data/gacha_types.dart` — 重構 GachaType + 新增 7 個 type
- `lib/services/gacha_url.dart` — 加 endpoint
- `lib/services/wish_fetcher.dart` — endpoint 傳遞
- `lib/state/wish_repository.dart` — 抓取 endpoint 切換
- `lib/models/wish_record.dart` — **移除 WishItemKind / kind 欄位**
- `lib/services/wish_stats.dart` — 動態 byItemType + 加 twoStarCount / threeStarCount
- `lib/services/wish_filter.dart` — 移除 KindFilter enum，改為 `itemType: String?`
- `lib/services/timeline_entries.dart` — 加 `targetRank` 參數
- `lib/widgets/item_type_pie.dart` — 動態 sections / palette 分配
- `lib/widgets/data/search_filter_bar.dart` — kind dropdown 動態
- `lib/widgets/cards/pity_card.dart` — 接受 PityRule
- `lib/widgets/cards/banner_five_star_bars.dart` → `banner_top_rarity_bars.dart`
- `lib/widgets/banner_colors.dart` — 加 1000 / 2000、加 twoStar
- `lib/widgets/rarity_pie.dart` — 支援 2★
- `lib/theme/tokens.dart` — `twoStar` token、頌願配色
- `lib/pages/app_shell.dart` — `_Rail` 拆 3 段
- `lib/pages/banner_page.dart` — PityCard rule-based、傳 availableItemTypes
- `lib/pages/overview_page.dart` — 拆 wish / odes section
- `lib/l10n/app_en.arb` / `app_zh_Hant.arb` / `app_zh_Hans.arb` — 加 / 移 key
- `rust/src/mitm.rs` — endpoint 列表

### 測試

- `test/services/gacha_url_test.dart` — endpoint 替換驗證
- `test/services/wish_fetcher_test.dart` — endpoint 切換驗證
- `test/data/gacha_types_test.dart` — 新增，驗證 7 個 type 的 pities 結構
- `test/widgets/cards/pity_card_test.dart` — rule-based 改寫
- `test/widgets/cards/banner_top_rarity_bars_test.dart`（rename）— 驗證頌願 4★ 件數
- `test/widgets/rarity_pie_test.dart` — 2★ 顯示
- `test/widgets/item_type_pie_test.dart` — 動態 sections / palette
- `test/services/wish_stats_test.dart` — `byItemType` 累計、2★ count
- `test/services/wish_filter_test.dart` — `itemType` 字串過濾
- `test/models/wish_record_test.dart` — WishItemKind 移除後讀寫驗證

### 提交前品質檢查

依 `CLAUDE.md`：
1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

## 6. 風險與待驗證

- **authkey 跨 endpoint**：需實測。若失敗，方案降級為「祈願與頌願分開 capture」。
- **頌願 `getBeyondGachaLog` 分頁 / retcode 行為**：假設與 `getGachaLog` 完全相同（page=1, size=20, end_id 機制、retcode -101/-110）。
- **常駐頌願保底資料來源**：規則來自使用者，未對 mihoyo 官方文件交叉驗證；活動頌願保底亦同。
- **OverviewPage 篇幅變長**：兩個 section + Pies + Bars + Timelines，垂直滾動顯著變長，可接受。
- **`item_type` 為空字串 fallback 行為**：實際 API 是否會回空 `item_type` 未知；保留 `kindUnknown` i18n 處理意外狀況。

## 7. 不在本 spec 範圍

- 任何 OverviewPage 樣式整體重設計（如 Tab 化、Drawer 化）。
- 對 `appName` 字串重新命名。
- 既有祈願視覺的非必要調整。
- 對 7 種非中英語言補翻譯。

---

實作會由 writing-plans 接手把這份 spec 拆成可執行步驟。
