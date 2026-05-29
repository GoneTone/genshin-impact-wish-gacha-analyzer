# HoYoWiki menu_id 物品類型判定 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 HoYoWiki `menu_id`（2＝角色、4＝武器）作為語言無關的物品類型判定，消除類型圓餅圖、記錄列表類型欄／排序、篩選下拉的跨語言統計分裂；查不到時 fallback 回原始 `itemType` 字串。

**Architecture:** 新增共用 primitive `itemTypeKeyOf(record, index)`（沿用 `five_star_collection` 的「records + HoYoWikiIndex，`lookupId`→`lookupMenuId`，miss fallback」模式）回傳聚合鍵 `kind:character` / `kind:weapon` / 原始字串；`itemTypeKeyLabel(key, l)` 把鍵轉在地化標籤。`computeGachaStats` 與 `buildRecordRows` 改用此鍵，不動存檔、零狀態遷移、隨 HoYoWiki index live provider 反應式更新。

**Tech Stack:** Flutter、Dart、Riverpod、Flutter gen-l10n（ARB）、flutter_test。

**Branch:** `feat/item-type-hoyowiki-classification`（已從 master 開好，含 spec commit）。

**Spec:** `docs/superpowers/specs/2026-05-29-hoyowiki-item-type-classification-design.md`

---

## File Structure

- **新增** `lib/services/item_type_kind.dart` — 類型判定模組：kind 常數 + `itemTypeKeyOf`（純，依 `HoYoWikiIndex`）+ `itemTypeKeyLabel`（依 `AppLocalizations`）。單一職責。
- **新增** `test/services/item_type_kind_test.dart`。
- **改** `lib/l10n/app_zh.arb` 等 9 個有實體翻譯的 ARB — 新增 `kindCharacter` / `kindWeapon`。
- **改** `lib/services/gacha_stats.dart` — `computeGachaStats` 加 `{required index}`，`byItemType` 改用鍵聚合 + summary log。
- **改** `lib/widgets/item_type_pie.dart` — legend 顯示套 `itemTypeKeyLabel`。
- **改** `lib/services/overview_sections.dart` — `buildOverviewSections` 加 `{required index}` 往下傳。
- **改** `lib/services/gacha_row.dart` — `RecordRow` 加 `itemTypeKey`，`buildRecordRows` 加 `{required index}`。
- **改** `lib/services/gacha_filter.dart` — `filterRecordRows` / `sortRecordRows` 改用 `row.itemTypeKey`。
- **改** `lib/widgets/data/sortable_table.dart` — 類型欄顯示套 `itemTypeKeyLabel`。
- **改** `lib/widgets/data/search_filter_bar.dart` — 下拉 label 套 `itemTypeKeyLabel`。
- **改** 呼叫點：`lib/pages/banner_page.dart`、`lib/pages/overview_page.dart`、`lib/widgets/share/share_card.dart`。
- **改** 既有測試：`gacha_stats_test`、`item_type_pie_test`、`overview_sections_test`、`gacha_row_test`、`gacha_filter_test`、`sortable_table_test`、`search_filter_bar_test`。

---

## Task 1: 新增 i18n 字串 kindCharacter / kindWeapon

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template，近 `kindUnknown` 第 108 行）
- Modify: `lib/l10n/app_zh_Hans.arb`、`app_en.arb`、`app_ja.arb`、`app_es.arb`、`app_fr.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`（僅這 9 個已有實體翻譯的 ARB；空殼 ARB 不碰，留給 Crowdin pipeline）

譯名取自 `docs/術語表.md`（權威來源，角色／武器名詞嵌在卡池全名列）；標準物品類型名詞，作為標籤首字母大寫。

- [ ] **Step 1: 在 `app_zh.arb` 的 `kindUnknown` 那一行後加入兩個 key**

`app_zh.arb` 現有：
```json
  "kindUnknown": "未知",
```
改為：
```json
  "kindUnknown": "未知",
  "kindCharacter": "角色",
  "kindWeapon": "武器",
```

- [ ] **Step 2: 在其餘 8 個 ARB 對應 `kindUnknown` 位置加入相同 key，值如下**

逐檔在該檔既有 `"kindUnknown": ...,` 之後插入：

`app_zh_Hans.arb`:
```json
  "kindCharacter": "角色",
  "kindWeapon": "武器",
```
`app_en.arb`:
```json
  "kindCharacter": "Character",
  "kindWeapon": "Weapon",
```
`app_ja.arb`:
```json
  "kindCharacter": "キャラクター",
  "kindWeapon": "武器",
```
`app_es.arb`:
```json
  "kindCharacter": "Personaje",
  "kindWeapon": "Arma",
```
`app_fr.arb`:
```json
  "kindCharacter": "Personnage",
  "kindWeapon": "Arme",
```
`app_pt_BR.arb`:
```json
  "kindCharacter": "Personagem",
  "kindWeapon": "Arma",
```
`app_th.arb`:
```json
  "kindCharacter": "ตัวละคร",
  "kindWeapon": "อาวุธ",
```
`app_vi.arb`:
```json
  "kindCharacter": "Nhân Vật",
  "kindWeapon": "Vũ Khí",
```

> 注意：JSON 不可有尾逗號問題——若 `kindUnknown` 是該物件最後一個 key，插入後確保最後一個 key 無尾逗號。各 ARB 內 `kindUnknown` 後通常還有其他 key，照原檔逗號規則維持。

- [ ] **Step 3: 重新產生 localizations**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `String get kindCharacter;` 與 `String get kindWeapon;`。

- [ ] **Step 4: 驗證 analyze 通過**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): add kindCharacter and kindWeapon strings"
```

---

## Task 2: 新增 itemTypeKeyOf / itemTypeKeyLabel primitive

**Files:**
- Create: `lib/services/item_type_kind.dart`
- Test: `test/services/item_type_kind_test.dart`

- [ ] **Step 1: 寫失敗測試**

Create `test/services/item_type_kind_test.dart`:
```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';

GachaRecord _r({required String name, required String lang, String itemType = '角色'}) =>
    GachaRecord(
      id: '1',
      uid: '1',
      gachaType: '301',
      name: name,
      itemType: itemType,
      rankType: 5,
      time: DateTime(2025),
      lang: lang,
    );

void main() {
  // 迪希雅(zh-tw) 與 Dehya(en) 對到同一 hoyowiki id c1（menu_id 2＝角色）；
  // 天空之翼 對到 w1（menu_id 4＝武器）。
  final index = HoYoWikiIndex(
    searchMap: const {
      'zh-tw::迪希雅': 'c1',
      'en::Dehya': 'c1',
      'zh-tw::天空之翼': 'w1',
    },
    entries: const {},
    menuIds: const {'c1': 2, 'w1': 4},
  );

  group('itemTypeKeyOf', () {
    test('menu_id 2 → kind:character', () {
      expect(itemTypeKeyOf(_r(name: '迪希雅', lang: 'zh-tw'), index), 'kind:character');
    });

    test('menu_id 4 → kind:weapon', () {
      expect(itemTypeKeyOf(_r(name: '天空之翼', lang: 'zh-tw', itemType: '武器'), index), 'kind:weapon');
    });

    test('跨語系同物品合併成同一 key', () {
      final zh = itemTypeKeyOf(_r(name: '迪希雅', lang: 'zh-tw', itemType: '角色'), index);
      final en = itemTypeKeyOf(_r(name: 'Dehya', lang: 'en', itemType: 'Character'), index);
      expect(zh, en);
      expect(zh, 'kind:character');
    });

    test('查無 menu_id → fallback 原始 itemType', () {
      expect(itemTypeKeyOf(_r(name: '未知物', lang: 'zh-tw', itemType: 'Character'), index), 'Character');
    });

    test('查無且原始字串為空 → 回空字串', () {
      expect(itemTypeKeyOf(_r(name: '未知物', lang: 'zh-tw', itemType: ''), index), '');
    });
  });

  group('itemTypeKeyLabel', () {
    test('canonical key 轉在地化標籤；fallback 原樣', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(itemTypeKeyLabel('kind:character', l), 'Character');
      expect(itemTypeKeyLabel('kind:weapon', l), 'Weapon');
      expect(itemTypeKeyLabel('', l), l.kindUnknown);
      expect(itemTypeKeyLabel('裝扮', l), '裝扮');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/item_type_kind_test.dart`
Expected: 編譯失敗（`item_type_kind.dart` 不存在 / `itemTypeKeyOf` 未定義）。

- [ ] **Step 3: 實作 primitive**

Create `lib/services/item_type_kind.dart`:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// 角色類型聚合鍵；以 `kind:` 前綴與遊戲原始 itemType 字串（角色／Character…）區隔，
/// 永不碰撞。
const kItemKindCharacter = 'kind:character';

/// 武器類型聚合鍵。
const kItemKindWeapon = 'kind:weapon';

/// 解析單筆 [r] 的類型聚合鍵：以 HoYoWiki [index] 的 menu_id 判定（2＝角色、
/// 4＝武器），跨語系自然合併；查不到時 fallback 回原始 `itemType` 字串（含空字串）。
String itemTypeKeyOf(GachaRecord r, HoYoWikiIndex index) {
  final id = index.lookupId(name: r.name, lang: r.lang);
  final menuId = id == null ? null : index.lookupMenuId(id);
  return switch (menuId) {
    2 => kItemKindCharacter,
    4 => kItemKindWeapon,
    _ => r.itemType,
  };
}

/// 將 [key]（[itemTypeKeyOf] 產物）轉成顯示用在地化標籤：canonical 鍵套
/// [l] 譯名、空字串顯示「未知」、其餘原始字串 fallback 原樣顯示。
String itemTypeKeyLabel(String key, AppLocalizations l) => switch (key) {
  kItemKindCharacter => l.kindCharacter,
  kItemKindWeapon => l.kindWeapon,
  '' => l.kindUnknown,
  _ => key,
};
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/item_type_kind_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/services/item_type_kind.dart test/services/item_type_kind_test.dart
git commit -m "feat(wish): add HoYoWiki menu_id item-type key resolver"
```

---

## Task 3: 圓餅圖統計改用聚合鍵（消除分裂）

**Files:**
- Modify: `lib/services/gacha_stats.dart`
- Modify: `lib/widgets/item_type_pie.dart:54-58`
- Modify: `lib/services/overview_sections.dart:104-106,165,181`
- Modify: `lib/pages/banner_page.dart:93`
- Modify: `lib/pages/overview_page.dart:54`
- Modify: `lib/widgets/share/share_card.dart:111,163`
- Test: `test/services/gacha_stats_test.dart`、`test/services/overview_sections_test.dart`、`test/widgets/item_type_pie_test.dart`

- [ ] **Step 1: 更新 `gacha_stats_test.dart` — 既有呼叫補 `index`（驗無回歸）+ 新增跨語系合併測試**

`gacha_stats_test.dart` 頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
```
把檔內所有 `computeGachaStats(records)` / `computeGachaStats(const [])` 改為帶 `index: const HoYoWikiIndex.empty()`（空 index → 全 fallback 原始字串 → 既有 assertion 不變，即無回歸）。例如：
```dart
final s = computeGachaStats(const [], index: const HoYoWikiIndex.empty());
```
```dart
final s = computeGachaStats(records, index: const HoYoWikiIndex.empty());
```
（共 6 處：第 20、35、52、64、73、83 行附近。）

在 `group('GachaStats', ...)` 內新增測試：
```dart
test('跨語系同物品以 menu_id 合併，不分裂', () {
  final index = HoYoWikiIndex(
    searchMap: const {'zh-tw::迪希雅': 'c1', 'en::Dehya': 'c1'},
    entries: const {},
    menuIds: const {'c1': 2},
  );
  final records = [
    _r(id: '1', itemType: '角色'),
    GachaRecord(
      id: '2', uid: '1', gachaType: '301', name: 'Dehya',
      itemType: 'Character', rankType: 5, time: DateTime(2025), lang: 'en',
    ),
  ];
  // _r 的 name 預設為 'x'、lang 'zh-tw'；需讓第一筆 name 命中 index。
  final stats = computeGachaStats([
    GachaRecord(
      id: '1', uid: '1', gachaType: '301', name: '迪希雅',
      itemType: '角色', rankType: 5, time: DateTime(2025), lang: 'zh-tw',
    ),
    records[1],
  ], index: index);
  expect(stats.byItemType, {'kind:character': 2});
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/gacha_stats_test.dart`
Expected: 編譯失敗（`computeGachaStats` 尚無 `index` 具名參數）。

- [ ] **Step 3: 改 `computeGachaStats` 簽名與聚合 + summary log**

`lib/services/gacha_stats.dart` 頂部 import 加：
```dart
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
```
在 `computeGachaStats` 前加 logger：
```dart
/// 祈願統計 logger。
final _log = Logger('gacha.stats');
```
把函式：
```dart
GachaStats computeGachaStats(List<GachaRecord> records) {
  var five = 0, four = 0, three = 0, two = 0;
  final byItemType = <String, int>{};
  for (final r in records) {
    switch (r.rankType) {
      case 5:
        five++;
      case 4:
        four++;
      case 3:
        three++;
      case 2:
        two++;
    }
    byItemType[r.itemType] = (byItemType[r.itemType] ?? 0) + 1;
  }
```
改為：
```dart
GachaStats computeGachaStats(
  List<GachaRecord> records, {
  required HoYoWikiIndex index,
}) {
  var five = 0, four = 0, three = 0, two = 0;
  var canonical = 0, fallback = 0;
  final byItemType = <String, int>{};
  for (final r in records) {
    switch (r.rankType) {
      case 5:
        five++;
      case 4:
        four++;
      case 3:
        three++;
      case 2:
        two++;
    }
    final key = itemTypeKeyOf(r, index);
    if (key == kItemKindCharacter || key == kItemKindWeapon) {
      canonical++;
    } else {
      fallback++;
    }
    byItemType[key] = (byItemType[key] ?? 0) + 1;
  }
  if (records.isNotEmpty) {
    _log.fine(
      'computeGachaStats: total=${records.length} '
      'canonicalKind=$canonical rawFallback=$fallback',
    );
  }
```
（`return GachaStats(...)` 區塊不變。）

- [ ] **Step 4: 更新 stats 呼叫點補 `index`**

`lib/pages/banner_page.dart:93`：
```dart
    final stats = computeGachaStats(records, index: ref.watch(hoyowikiIndexProvider));
```
（`banner_page.dart` 已 import `hoyowiki_index.dart` state；若無則加 `import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';`。第 123 行已用 `ref.watch(hoyowikiIndexProvider)`，故 import 已存在。）

`lib/widgets/share/share_card.dart:111`：
```dart
    final stats = computeGachaStats(records, index: index);
```

`lib/services/overview_sections.dart`：把
```dart
OverviewSections buildOverviewSections(
  Map<String, List<GachaRecord>> activeBanners,
) {
```
改為（頂部 import 加 `import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';`）：
```dart
OverviewSections buildOverviewSections(
  Map<String, List<GachaRecord>> activeBanners, {
  required HoYoWikiIndex index,
}) {
```
第 165、181 行：
```dart
      stats: computeGachaStats(gachaAll, index: index),
```
```dart
      stats: computeGachaStats(odesAll, index: index),
```

`lib/pages/overview_page.dart:54`：
```dart
    final sections = buildOverviewSections(
      activeData.banners,
      index: ref.watch(hoyowikiIndexProvider),
    );
```
（`overview_page.dart` 已 import state hoyowiki，見第 151、199 行。）

`lib/widgets/share/share_card.dart:163`：
```dart
    final s = buildOverviewSections(banners, index: index);
```

- [ ] **Step 5: 圓餅圖 legend 顯示套 `itemTypeKeyLabel`**

`lib/widgets/item_type_pie.dart` 頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
```
把第 54-58 行 `DistributionEntry(... name: e.key.isEmpty ? l.kindUnknown : e.key, ...)` 的 `name` 改為：
```dart
        name: itemTypeKeyLabel(e.key, l),
```

- [ ] **Step 6: 更新 `overview_sections_test.dart` 補 `index`**

找出檔內所有 `buildOverviewSections(...)` 呼叫，補 `index: const HoYoWikiIndex.empty()`（import `hoyowiki_index.dart`）。例如：
```dart
final sections = buildOverviewSections(banners, index: const HoYoWikiIndex.empty());
```

- [ ] **Step 7: 更新 `item_type_pie_test.dart`**

檔內所有 `computeGachaStats(...)` 補 `index: const HoYoWikiIndex.empty()`（import `hoyowiki_index.dart`）。空 index 下原始字串 legend 行為不變，既有 assertion 應仍成立；若有測「未知」legend 的案例（空 itemType）維持以 `kindUnknown` 呈現，不需改。

- [ ] **Step 8: 跑相關測試**

Run: `flutter test test/services/gacha_stats_test.dart test/services/overview_sections_test.dart test/widgets/item_type_pie_test.dart`
Expected: All tests passed!

- [ ] **Step 9: analyze + commit**

Run: `flutter analyze`（Expected: `No issues found!`）
```bash
git add lib/services/gacha_stats.dart lib/widgets/item_type_pie.dart lib/services/overview_sections.dart lib/pages/banner_page.dart lib/pages/overview_page.dart lib/widgets/share/share_card.dart test/
git commit -m "feat(wish): aggregate item-type stats by HoYoWiki kind key"
```

---

## Task 4: RecordRow 帶 itemTypeKey

**Files:**
- Modify: `lib/services/gacha_row.dart`
- Modify: `lib/pages/banner_page.dart:111`
- Test: `test/services/gacha_row_test.dart`

- [ ] **Step 1: 更新 `gacha_row_test.dart`**

頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
```
把檔內所有 `buildRecordRows(records)` / `buildRecordRows(records, mainRank: X)` 補 `index: const HoYoWikiIndex.empty()`。例如：
```dart
final rows = buildRecordRows(records, index: const HoYoWikiIndex.empty());
```
新增測試（驗 itemTypeKey 命中與 fallback）：
```dart
test('itemTypeKey: menu_id 命中用 canonical，miss fallback 原始字串', () {
  final index = HoYoWikiIndex(
    searchMap: const {'zh-tw::迪希雅': 'c1'},
    entries: const {},
    menuIds: const {'c1': 2},
  );
  final records = [
    GachaRecord(
      id: '1', uid: '1', gachaType: '301', name: '迪希雅',
      itemType: '角色', rankType: 5, time: DateTime(2025, 1, 2), lang: 'zh-tw',
    ),
    GachaRecord(
      id: '2', uid: '1', gachaType: '301', name: '某武器',
      itemType: '武器', rankType: 4, time: DateTime(2025, 1, 1), lang: 'zh-tw',
    ),
  ];
  final rows = buildRecordRows(records, index: index);
  expect(rows[0].itemTypeKey, 'kind:character'); // 迪希雅命中
  expect(rows[1].itemTypeKey, '武器');             // 未命中 → 原始字串
});
```
（注意：`buildRecordRows` 輸出順序與輸入相同（desc by time），`records` 以 time desc 排，故 rows[0]＝迪希雅。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/gacha_row_test.dart`
Expected: 編譯失敗（`buildRecordRows` 無 `index` 參數、`RecordRow.itemTypeKey` 不存在）。

- [ ] **Step 3: `RecordRow` 加欄位、`buildRecordRows` 加 index**

`lib/services/gacha_row.dart` 頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
```
`RecordRow` 加欄位與建構參數：
```dart
  const RecordRow({
    required this.record,
    required this.totalIndex,
    required this.mainPityIndex,
    required this.itemTypeKey,
  });
```
```dart
  /// 跨語言無關的類型聚合鍵（[itemTypeKeyOf] 產物：kind:character / kind:weapon
  /// / 原始字串）。供表格類型欄顯示、排序、篩選共用，避免各處重複解析 index。
  final String itemTypeKey;
```
`buildRecordRows` 簽名與 row 建構：
```dart
List<RecordRow> buildRecordRows(
  List<GachaRecord> records, {
  required HoYoWikiIndex index,
  int mainRank = 5,
}) {
```
迴圈內 `out.add(...)`：
```dart
    out.add(RecordRow(
      record: r,
      totalIndex: total,
      mainPityIndex: pity,
      itemTypeKey: itemTypeKeyOf(r, index),
    ));
```

- [ ] **Step 4: 更新 banner_page 呼叫點**

`lib/pages/banner_page.dart:111`：
```dart
    final allRows = buildRecordRows(
      records,
      index: ref.watch(hoyowikiIndexProvider),
      mainRank: primary.rank,
    );
```

- [ ] **Step 5: 跑測試確認通過 + analyze**

Run: `flutter test test/services/gacha_row_test.dart`（Expected: All tests passed!）
Run: `flutter analyze`（Expected: `No issues found!`）

- [ ] **Step 6: Commit**

```bash
git add lib/services/gacha_row.dart lib/pages/banner_page.dart test/services/gacha_row_test.dart
git commit -m "feat(wish): stamp item-type key onto RecordRow"
```

---

## Task 5: 表格類型欄顯示 + 排序改用 itemTypeKey

**Files:**
- Modify: `lib/services/gacha_filter.dart:135`（`sortRecordRows` 的 `SortColumn.kind`）
- Modify: `lib/widgets/data/sortable_table.dart:413`
- Test: `test/services/gacha_filter_test.dart`、`test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: 更新 `gacha_filter_test.dart` 的排序測試**

檔內凡建 `RecordRow`（直接 new 或經 `buildRecordRows`）的地方須提供 `itemTypeKey`。
- 若用 `buildRecordRows(...)`：補 `index: const HoYoWikiIndex.empty()`（import `hoyowiki_index.dart`）。
- 若直接 `RecordRow(...)`：補 `itemTypeKey: '<該列原始 itemType 或 kind:xxx>'`。

新增／調整「依 kind 排序」測試，斷言改以 `itemTypeKey` 為排序鍵。範例：
```dart
test('SortColumn.kind 依 itemTypeKey 排序', () {
  final rows = [
    RecordRow(record: _rec('a'), totalIndex: 1, mainPityIndex: 1, itemTypeKey: 'kind:weapon'),
    RecordRow(record: _rec('b'), totalIndex: 2, mainPityIndex: 2, itemTypeKey: 'kind:character'),
  ];
  final sorted = sortRecordRows(rows, const TableSort(column: SortColumn.kind, direction: SortDirection.asc));
  expect(sorted.first.itemTypeKey, 'kind:character');
});
```
（`_rec` 為該測試檔既有的 record helper；若名稱不同，沿用檔內現有 helper。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/gacha_filter_test.dart`
Expected: FAIL（排序仍用 `record.itemType`，斷言不符）或編譯失敗（`RecordRow` 缺 `itemTypeKey`）。

- [ ] **Step 3: `sortRecordRows` 的 kind 改比 itemTypeKey**

`lib/services/gacha_filter.dart:135-136`：
```dart
    case SortColumn.kind:
      cmp = (a, b) => a.record.itemType.compareTo(b.record.itemType);
```
改為：
```dart
    case SortColumn.kind:
      cmp = (a, b) => a.itemTypeKey.compareTo(b.itemTypeKey);
```

- [ ] **Step 4: 表格類型欄顯示套 label**

`lib/widgets/data/sortable_table.dart` 頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
```
第 413 行：
```dart
          Expanded(flex: 2, child: Text(record.itemType)),
```
改為（`_Row` 內 `row` 與 `l` 均在 scope）：
```dart
          Expanded(flex: 2, child: Text(itemTypeKeyLabel(row.itemTypeKey, l))),
```

- [ ] **Step 5: 更新 `sortable_table_test.dart`**

檔內建 `RecordRow` / `buildRecordRows` 處補 `itemTypeKey` / `index`（同 Step 1 規則）。若有斷言類型欄文字＝原始 itemType（如 `'角色'`），改為驗 `itemTypeKeyLabel` 結果——空 index fallback 下原始字串照舊顯示，故原斷言多半仍成立；canonical 命中的測試案例改驗在地化標籤。

- [ ] **Step 6: 跑測試 + analyze**

Run: `flutter test test/services/gacha_filter_test.dart test/widgets/data/sortable_table_test.dart`（Expected: All tests passed!）
Run: `flutter analyze`（Expected: `No issues found!`）

- [ ] **Step 7: Commit**

```bash
git add lib/services/gacha_filter.dart lib/widgets/data/sortable_table.dart test/services/gacha_filter_test.dart test/widgets/data/sortable_table_test.dart
git commit -m "feat(wish): display and sort item-type column by kind key"
```

---

## Task 6: 篩選下拉與過濾改用 itemTypeKey

**Files:**
- Modify: `lib/services/gacha_filter.dart:117`（`filterRecordRows`）
- Modify: `lib/pages/banner_page.dart:114-120`（`availableItemTypes`）+ 傳給 `SearchFilterBar` 的型別
- Modify: `lib/widgets/data/search_filter_bar.dart:131-132`（下拉 label）
- Test: `test/services/gacha_filter_test.dart`、`test/widgets/data/search_filter_bar_test.dart`

- [ ] **Step 1: 更新 `gacha_filter_test.dart` 的過濾測試**

新增／調整「依 itemType 過濾」測試，`RecordFilter.itemType` 存的是聚合鍵：
```dart
test('filterRecordRows 依 itemTypeKey 過濾', () {
  final rows = [
    RecordRow(record: _rec('a'), totalIndex: 1, mainPityIndex: 1, itemTypeKey: 'kind:character'),
    RecordRow(record: _rec('b'), totalIndex: 2, mainPityIndex: 2, itemTypeKey: 'kind:weapon'),
  ];
  final out = filterRecordRows(rows, const RecordFilter(itemType: 'kind:character'));
  expect(out.length, 1);
  expect(out.first.itemTypeKey, 'kind:character');
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/gacha_filter_test.dart`
Expected: FAIL（`filterRecordRows` 仍比 `r.itemType`）。

- [ ] **Step 3: `filterRecordRows` 改比 itemTypeKey**

`lib/services/gacha_filter.dart:117`：
```dart
        if (f.itemType != null && r.itemType != f.itemType) return false;
```
改為（注意此處 `r` 是 `row.record`，需改用 `row.itemTypeKey`；檢視該 `where` 區塊把 `final r = row.record;` 保留，新增比較用 `row.itemTypeKey`）：
```dart
        if (f.itemType != null && row.itemTypeKey != f.itemType) return false;
```

- [ ] **Step 4: 跑過濾測試確認通過**

Run: `flutter test test/services/gacha_filter_test.dart`
Expected: All tests passed!

- [ ] **Step 5: banner_page 的 availableItemTypes 改用 rows 的 itemTypeKey**

`lib/pages/banner_page.dart:114-120`：
```dart
    final availableItemTypes =
        records
            .map((r) => r.itemType)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
```
改為（用已建好的 `allRows`，去重 distinct key、空字串排除）：
```dart
    final availableItemTypes =
        allRows
            .map((row) => row.itemTypeKey)
            .where((k) => k.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
```
（`allRows` 於 Task 4 已含 itemTypeKey，且定義在第 111 行，位於此段之前。）

- [ ] **Step 6: SearchFilterBar 下拉 label 套 itemTypeKeyLabel**

`lib/widgets/data/search_filter_bar.dart` 頂部 import 加：
```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/item_type_kind.dart';
```
第 131-132 行：
```dart
            for (final t in widget.availableItemTypes)
              DropdownMenuItem<String?>(value: t, child: Text(t)),
```
改為：
```dart
            for (final t in widget.availableItemTypes)
              DropdownMenuItem<String?>(value: t, child: Text(itemTypeKeyLabel(t, l))),
```
（`availableItemTypes` 的 dartdoc 文案順手更新為「當前 banner 出現過的類型聚合鍵集合」。）

- [ ] **Step 7: 更新 `search_filter_bar_test.dart`**

`availableItemTypes` 傳入值改為聚合鍵（如 `['kind:character', 'kind:weapon']` 或原始字串 fallback）。若有斷言下拉項顯示文字，改驗 `itemTypeKeyLabel` 對應的在地化標籤（widget test 內可用 `tester` 找到的 `AppLocalizations`，或直接斷言文字如 'Character'／視測試語系而定）。

- [ ] **Step 8: 跑測試 + analyze**

Run: `flutter test test/services/gacha_filter_test.dart test/widgets/data/search_filter_bar_test.dart`（Expected: All tests passed!）
Run: `flutter analyze`（Expected: `No issues found!`）

- [ ] **Step 9: Commit**

```bash
git add lib/services/gacha_filter.dart lib/pages/banner_page.dart lib/widgets/data/search_filter_bar.dart test/services/gacha_filter_test.dart test/widgets/data/search_filter_bar_test.dart
git commit -m "feat(wish): filter records by kind key and localize dropdown"
```

---

## Task 7: 全套品質檢查

**Files:** 無（驗證）

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 顯示已格式化檔案數，無錯誤。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 如格式化有變更則 commit**

```bash
git add -A
git commit -m "style: format item-type classification changes"
```
（若 `git status` 乾淨則略過。）

---

## Self-Review 紀錄

- **Spec coverage**：圓餅圖統計（Task 3）、表格類型欄＋排序（Task 5）、篩選下拉（Task 6）、primitive＋fallback（Task 2）、i18n（Task 1）、summary log（Task 3 Step 3）、測試（各 task 內含 + Task 7）。三畫面全覆蓋。
- **無 placeholder**：所有 step 含實際程式碼／指令／預期輸出。
- **型別一致**：`itemTypeKeyOf` / `itemTypeKeyLabel` / `kItemKindCharacter` / `kItemKindWeapon` / `RecordRow.itemTypeKey` / `computeGachaStats(..., {required index})` / `buildRecordRows(..., {required index, mainRank})` / `buildOverviewSections(..., {required index})` 跨 task 命名一致。
- **編譯連續性**：每個 task 結尾 analyze + test 綠燈；簽名變更與其呼叫點在同一 task 內更新。
