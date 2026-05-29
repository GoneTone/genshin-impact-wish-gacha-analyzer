# 用 HoYoWiki menu_id 判定物品類型（消除跨語言統計分裂）

## 背景與問題

`GachaRecord.itemType` 是抓取當下遊戲語言的原始字串，依 `record.lang` 而定：
zh-tw「角色／武器」、en「Character／Weapon」、ja「キャラクター／武器」……，並未對 UI
語言翻譯。

連帶 bug：`computeGachaStats` 以原始 `itemType` 字串聚合（`byItemType[r.itemType]`）。
若使用者曾切換遊戲語言再同步，同一種類型會以多個語言字串存在，導致：

- 類型圓餅圖分裂成多塊（同一個「角色」被算成「角色」「Character」兩塊）。
- 篩選下拉出現重複的類型選項。
- 表格「類型」欄顯示混雜語言。

## 目標

以 HoYoWiki 的 `menu_id`（語言無關的官方分類：**2＝角色、4＝武器**）作為類型判定依據，
消除跨語言分裂。涵蓋三個受影響畫面：**類型圓餅圖統計**、**記錄列表「類型」欄（含排序）**、
**篩選下拉**。

## 非目標

- 物品**名稱**的在地化（需整套遊戲辭典，YAGNI）。
- 強制或主動觸發 HoYoWiki 拓圖；沿用既有 lazy／選用抓取流程。
- 存檔 schema 變更或資料遷移。

## 既有基礎（已存在，直接重用）

- `HoYoWikiIndex`（`lib/services/hoyowiki_index.dart`）已帶：
  - `searchMap`：`"<lang>::<name>"` → `hoyowiki_id`，方法 `lookupId({name, lang})`。
  - `menuIds`：`hoyowiki_id` → `menu_id`（2／4），方法 `lookupMenuId(id)`。
- `hoyowikiIndexProvider`（`lib/state/hoyowiki_index.dart`）是 live Riverpod provider，
  拓圖完成會 emit 新 index → watch 的 widget 自動 rebuild。
- 既有範例 `buildFiveStarCollection(records, {required HoYoWikiIndex index})`
  （`lib/services/five_star_collection.dart`）已確立慣例：**service 吃 records + index，
  以 `index.lookupId` 跨語系合併、miss 時 fallback**。本設計沿用此模式。

## 設計

### 核心 primitive

新增共用方法（放 `lib/services/`，併入 `gacha_stats.dart` 或新檔 `item_type_kind.dart`）：

```dart
/// canonical key 前綴；與任何遊戲原始 itemType 字串（角色／Character…）不會碰撞。
const _kindCharacter = 'kind:character';
const _kindWeapon = 'kind:weapon';

/// 解析單筆 record 的類型聚合鍵：menu_id 命中用 canonical，miss fallback 原始字串。
String itemTypeKeyOf(GachaRecord r, HoYoWikiIndex index) {
  final id = index.lookupId(name: r.name, lang: r.lang);
  final menuId = id == null ? null : index.lookupMenuId(id);
  return switch (menuId) {
    2 => _kindCharacter,
    4 => _kindWeapon,
    _ => r.itemType,
  };
}

/// key → 顯示用在地化標籤。
String itemTypeKeyLabel(String key, AppLocalizations l) => switch (key) {
  _kindCharacter => l.kindCharacter,
  _kindWeapon => l.kindWeapon,
  '' => l.kindUnknown,
  _ => key, // 原始字串 fallback 原樣顯示
};
```

**Fallback 行為（hybrid）**：menu_id 查得到用 canonical kind（跨語系合併成同一塊）；查不到
（使用者沒跑過拓圖、該物品 wiki 沒收錄、或拓圖失敗）退回顯示原始 `itemType` 字串。已抓過的
記錄不論語言都合併；只有未抓過且跨語言的記錄仍可能各自分開——這是 hybrid 取捨，且**單語言或
沒跑過拓圖的使用者完全等同現狀，無回歸**。

### 三個畫面的接法

**A. 類型圓餅圖統計**

- `computeGachaStats(records, {required HoYoWikiIndex index})`：`byItemType` 改用
  `itemTypeKeyOf(r, index)` 聚合（取代 `r.itemType`）。
- `itemTypeDistributionEntries`（`lib/widgets/item_type_pie.dart`）顯示時，entry 的
  `name` 由 `itemTypeKeyLabel(key, l)` 求得（取代目前 `e.key.isEmpty ? l.kindUnknown : e.key`）。
- 三個呼叫點補上 `index:`：
  - `lib/pages/banner_page.dart:93` —— 已有 `ref.watch(hoyowikiIndexProvider)`。
  - `lib/services/overview_sections.dart:165,181` —— `buildOverviewSections` 加
    `{required HoYoWikiIndex index}` 參數往下傳；呼叫點 `overview_page.dart:54` 與 share
    路徑補上（兩處皆已可取得 index）。
  - `lib/widgets/share/share_card.dart:111` —— 離屏渲染已攜帶 HoYoWiki 資料（五星一覽用），
    沿同一路徑取得 index。

**B. 記錄列表「類型」欄 + 排序**

- `RecordRow`（`lib/services/gacha_row.dart`）新增 `final String itemTypeKey`，於
  `buildRecordRows(records, {required HoYoWikiIndex index})` 建構時用 `itemTypeKeyOf` 算好。
  如此排序／篩選純函式簽名**不必吃 index**。
- `sortable_table.dart:413` `Text(record.itemType)` → `Text(itemTypeKeyLabel(row.itemTypeKey, l))`。
- `sortRecordRows` 的 `SortColumn.kind`（`gacha_filter.dart:135`）改比 `row.itemTypeKey`。
  排序後標籤分組更直覺（character／weapon 各自聚集）。
- `buildRecordRows` 呼叫點（`banner_page.dart:111` 等）補上 `index:`。

**C. 篩選下拉**

- `availableItemTypes`（`banner_page.dart:114–120`）改由 `allRows` 的 distinct
  `itemTypeKey` 建（取代原始字串 set）。
- `SearchFilterBar` 下拉 label 套 `itemTypeKeyLabel`（取代目前直接 `Text(t)`）。
- `filterRecordRows`（`gacha_filter.dart:117`）`r.itemType != f.itemType` →
  `row.itemTypeKey != f.itemType`。
- `RecordFilter.itemType` **維持 `String?`**（存的是 key 字串）——零狀態遷移；
  `recordFilterProvider` 持久化內容沿用既有 schema。

### i18n

- 新增 `kindCharacter` / `kindWeapon`（`kindUnknown` 已存在）。
- 值依 `docs/術語表.md`（權威來源）填：zh-tw＝「角色」「武器」。
- 從 `app_zh.arb` 起手，只加進**已有實體翻譯**的 ARB；空殼 ARB 留給 Crowdin pipeline。

### Logging

- `itemTypeKeyOf` 屬熱路徑（每筆 record 都跑），**不**逐筆埋 log。
- 在聚合層加 summary：`computeGachaStats` 結尾 `Logger('gacha.stats').fine(...)`，記 canonical
  命中數 vs fallback 筆數，方便日後判斷使用者拓圖覆蓋率。

## 測試

- **`itemTypeKeyOf`**：menu_id=2／4 命中回 canonical；miss 回原始字串；跨語系（zh-tw「角色」
  與 en「Character」對到同一 hoyowiki_id）合併成同一 key。
- **`computeGachaStats`**：跨語系記錄 + 命中的 index → `byItemType` 不分裂；命中項 fallback
  路徑（空 index）→ 維持原始字串聚合（無回歸）。
- **`filterRecordRows` / `sortRecordRows`**：以 `itemTypeKey` 過濾與排序。
- **`buildRecordRows`**：`itemTypeKey` 正確標記。
- 更新既有 `item_type_pie_test`、`sortable_table_test`、`search_filter_bar_test`、
  `overview_sections_test`、`gacha_stats_test`、`gacha_filter_test`、`gacha_row_test`
  以符合新簽名。

## 風險與取捨

- **碰撞**：canonical key 用 `kind:` 前綴，遊戲原始 itemType 字串（角色／Character／
  キャラクター…）絕不會等於 `kind:character`，無碰撞風險。
- **混雜顯示**：當同類型同時存在「已抓（canonical 在地化標籤）」與「未抓（原始字串）」記錄時，
  圓餅圖／下拉會出現兩個項目。這是 hybrid fallback 的固有行為，使用者已接受；跑完整拓圖後消失。
- **效能**：聚合改為顯示時即時計算，資料量小（單一帳號祈願記錄）可忽略，與
  `five_star_collection` 同等級。
