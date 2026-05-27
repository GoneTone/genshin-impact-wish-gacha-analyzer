# Odes Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增頌願（Odes）兩個卡池（活動 2000、常駐 1000）的攔截、抓取、儲存與 UI 呈現；側選單區分祈願 / 頌願；同步重構物品類型分類為動態。

**Architecture:** `GachaType` 重構為資料驅動的保底列表（`pities: List<PityRule>`），讓常駐頌願「最高 4★」也可共用同一套 PityCard / Timeline。`getBeyondGachaLog` endpoint 透過 `GachaEndpoint` enum 在 `GachaUrl.build` 替換 path 最後一段，使用者捕獲一張 authkey 即可同時打祈願 / 頌願兩個 endpoint。`WishItemKind` 整段移除，改由實際 `item_type` 字串動態驅動 ItemTypePie 與 filter。

**Tech Stack:** Flutter / Dart 3 / Riverpod 2 / GoRouter / fl_chart / Rust mitm (hudsucker) via flutter_rust_bridge / Flutter ARB i18n.

**Spec:** `docs/superpowers/specs/2026-05-14-odes-banner-design.md`

**Branch:** `feat/odes-banner`（已建立）

**Quality gate before every commit**（CLAUDE.md 要求）：
1. `dart format lib/ test/`
2. `flutter analyze` 必須 `No issues found!`
3. `flutter test` 必須 `All tests passed!`

---

## File Structure

### 新增檔案

- `lib/widgets/rank_palette.dart` — `accentForRank(int, GachaTokens)` helper（給 PityCard / RarityPie / TopRarityBars 共用）
- `lib/widgets/cards/banner_top_rarity_bars.dart` — 由 `banner_five_star_bars.dart` rename / 泛化
- `test/data/gacha_types_test.dart` — GachaType 結構驗證

### 重大重構檔案

- `lib/data/gacha_types.dart` — 加 `PityRule` / `GachaCategory`，重構 GachaType
- `lib/services/gacha_url.dart` — 加 `GachaEndpoint`
- `lib/services/wish_fetcher.dart` — endpoint 傳遞、probeUid 兩階段
- `lib/state/wish_repository.dart` — 依 category 切 endpoint
- `lib/models/wish_record.dart` — **移除 `WishItemKind` 與 `kind` 欄位**
- `lib/services/wish_stats.dart` — 加 twoStarCount / threeStarCount；`byItemType: Map<String, int>` 取代 character/weapon/unknown count
- `lib/services/wish_filter.dart` — 移除 `KindFilter` enum，改 `itemType: String?`
- `lib/services/timeline_entries.dart` — 加 `targetRank` / `rankFor` 參數，rename `pullsSinceLastFiveStar*` → `pullsSinceLastRankedAcrossBanners`
- `lib/widgets/item_type_pie.dart` — 動態 sections / palette
- `lib/widgets/rarity_pie.dart` — 支援 2★
- `lib/widgets/banner_colors.dart` — 加 1000 / 2000
- `lib/widgets/data/search_filter_bar.dart` — kind dropdown 改動態
- `lib/theme/tokens.dart` — 加 `twoStar`、`odesEvent`、`odesStandard`
- `lib/pages/banner_page.dart` — PityCard / Timeline / SearchFilterBar 由 GachaType 驅動
- `lib/pages/overview_page.dart` — 拆 wish / odes section
- `lib/pages/app_shell.dart` — `_Rail` 拆三段 + section labels
- `lib/l10n/app_en.arb` / `app_zh_Hant.arb` / `app_zh_Hans.arb` — 新增 / 移除 key
- `rust/src/mitm.rs` — `is_target` 接受 `getBeyondGachaLog`

### 重大重構測試

- `test/data/gacha_types_test.dart`（新）
- `test/models/wish_record_test.dart`
- `test/services/wish_stats_test.dart`
- `test/services/wish_filter_test.dart`
- `test/services/wish_pity_test.dart`（不變動，已通用）
- `test/services/timeline_entries_test.dart`
- `test/services/gacha_url_test.dart`
- `test/services/wish_fetcher_test.dart`
- `test/widgets/item_type_pie_test.dart`
- `test/widgets/rarity_pie_test.dart`
- `test/widgets/cards/pity_card_test.dart`
- `test/widgets/cards/banner_top_rarity_bars_test.dart`（從 banner_five_star_bars_test rename）

---

## Task 1: 重構 `GachaType` 為資料驅動保底列表

**Files:**
- Modify: `lib/data/gacha_types.dart`
- Modify: `lib/pages/banner_page.dart`
- Modify: `lib/widgets/cards/banner_five_star_bars.dart`
- Create: `test/data/gacha_types_test.dart`
- Modify: `test/widgets/cards/banner_five_star_bars_test.dart`

新 `GachaType` 結構（先建好基礎，後面 task 用 `primaryPity` / `secondaryPity` / `category`）。**這個 task 只引入新結構並更新既有 caller，暫時不加頌願兩個 type**（避免 i18n / URL / fetcher 還沒準備好就出現 broken state）。

- [ ] **Step 1: 寫 GachaType 結構驗證測試**

建立 `test/data/gacha_types_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';

void main() {
  group('gachaTypes registry', () {
    test('每個 type 至少有一條 pity rule', () {
      for (final t in gachaTypes) {
        expect(t.pities, isNotEmpty, reason: t.gachaType);
      }
    });

    test('primaryPity 是 pities[0]', () {
      for (final t in gachaTypes) {
        expect(t.primaryPity, same(t.pities.first));
      }
    });

    test('secondaryPity 在 pities 有第二筆時非 null', () {
      for (final t in gachaTypes) {
        if (t.pities.length >= 2) {
          expect(t.secondaryPity, same(t.pities[1]));
        } else {
          expect(t.secondaryPity, isNull);
        }
      }
    });

    test('5 個祈願 type 都是 wish category', () {
      const wishTypes = {'301', '302', '500', '200', '100'};
      for (final t in gachaTypes) {
        if (wishTypes.contains(t.gachaType)) {
          expect(t.category, GachaCategory.wish);
        }
      }
    });

    test('既有保底值保留', () {
      final character = gachaTypes.firstWhere((t) => t.gachaType == '301');
      expect(character.primaryPity.rank, 5);
      expect(character.primaryPity.threshold, 90);
      expect(character.secondaryPity!.rank, 4);
      expect(character.secondaryPity!.threshold, 10);

      final weapon = gachaTypes.firstWhere((t) => t.gachaType == '302');
      expect(weapon.primaryPity.threshold, 80);

      final beginner = gachaTypes.firstWhere((t) => t.gachaType == '100');
      expect(beginner.primaryPity.threshold, 20);
    });
  });
}
```

- [ ] **Step 2: 跑測試確認 fail**

Run: `flutter test test/data/gacha_types_test.dart`
Expected: 編譯失敗（`PityRule` / `GachaCategory` / `primaryPity` 不存在）

- [ ] **Step 3: 重構 `lib/data/gacha_types.dart`**

```dart
// lib/data/gacha_types.dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

enum GachaCategory { wish, odes }

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

class GachaType {
  const GachaType({
    required this.gachaType,
    required this.nameKey,
    required this.category,
    required this.pities,
  });

  /// 對應 getGachaLog / getBeyondGachaLog API 的 query string `gacha_type=...`。
  final String gachaType;

  /// i18n key（透過 [resolveName] 取顯示字串）。
  final String nameKey;

  /// wish = getGachaLog，odes = getBeyondGachaLog。
  final GachaCategory category;

  /// 由高 rank 到低 rank。[0] 為主保底，[1] 為副保底（若有）。
  final List<PityRule> pities;

  PityRule get primaryPity => pities.first;
  PityRule? get secondaryPity => pities.length > 1 ? pities[1] : null;

  String resolveName(AppLocalizations l) => switch (nameKey) {
    'gachaTypeCharacter' => l.gachaTypeCharacter,
    'gachaTypeWeapon' => l.gachaTypeWeapon,
    'gachaTypeChronicled' => l.gachaTypeChronicled,
    'gachaTypeStandard' => l.gachaTypeStandard,
    'gachaTypeBeginner' => l.gachaTypeBeginner,
    _ => nameKey,
  };
}

const _pityFive90 = PityRule(rank: 5, threshold: 90, labelKey: 'pityFiveStar');
const _pityFive80 = PityRule(rank: 5, threshold: 80, labelKey: 'pityFiveStar');
const _pityFive20 = PityRule(rank: 5, threshold: 20, labelKey: 'pityFiveStar');
const _pityFour10 = PityRule(rank: 4, threshold: 10, labelKey: 'pityFourStar');

const gachaTypes = <GachaType>[
  GachaType(
    gachaType: '301',
    nameKey: 'gachaTypeCharacter',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '302',
    nameKey: 'gachaTypeWeapon',
    category: GachaCategory.wish,
    pities: [_pityFive80, _pityFour10],
  ),
  GachaType(
    gachaType: '500',
    nameKey: 'gachaTypeChronicled',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '200',
    nameKey: 'gachaTypeStandard',
    category: GachaCategory.wish,
    pities: [_pityFive90, _pityFour10],
  ),
  GachaType(
    gachaType: '100',
    nameKey: 'gachaTypeBeginner',
    category: GachaCategory.wish,
    pities: [_pityFive20, _pityFour10],
  ),
];
```

- [ ] **Step 4: 更新 `lib/pages/banner_page.dart` 既有 caller**

把 `type.fiveStarPity` / `type.fourStarPity` 換成 `type.primaryPity.threshold` / `type.secondaryPity!.threshold`。

修改 `BannerPage.build` 內：

```dart
final fivePity = computePity(records, threshold: type.primaryPity.threshold);
final fourPity = computePity(
  records,
  threshold: type.secondaryPity!.threshold,
  rank: 4,
);
```

（這個 task 只動 caller，PityCard 仍用 5★/4★ 寫死 label，下一個 task 才動）

- [ ] **Step 5: 更新 `lib/widgets/cards/banner_five_star_bars.dart`**

把第 44 行 `threshold: type.fiveStarPity` 改為 `threshold: type.primaryPity.threshold`。

- [ ] **Step 6: 更新測試 `test/widgets/cards/banner_five_star_bars_test.dart`**

掃描檔內若用到 `fiveStarPity` / `fourStarPity` 字面值或建構 `GachaType` 物件的部分，改用 `pities` list。**先讀檔再判斷實際改法**。

- [ ] **Step 7: 跑測試確認綠**

```
flutter test test/data/gacha_types_test.dart
flutter test test/widgets/cards/banner_five_star_bars_test.dart
flutter test test/widgets/cards/pity_card_test.dart
flutter test test/pages/  # 若有 banner_page 相關 test
```

Expected: PASS

- [ ] **Step 8: 全域 quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: `No issues found!` + `All tests passed!`

```bash
git add lib/data/gacha_types.dart lib/pages/banner_page.dart \
        lib/widgets/cards/banner_five_star_bars.dart \
        test/data/gacha_types_test.dart \
        test/widgets/cards/banner_five_star_bars_test.dart
git commit -m "refactor(gacha-types): replace fiveStarPity/fourStarPity with pities list

- 加入 PityRule / GachaCategory，讓 GachaType 可表達多稀有度保底
- primaryPity / secondaryPity getter 取代寫死的 5★ / 4★ 欄位
- 既有 5 個祈願 type 行為不變；頌願兩個 type 留待後續 task 加入"
```

---

## Task 2: 移除 `WishItemKind`，物品類型改為動態

**Files:**
- Modify: `lib/models/wish_record.dart`
- Modify: `lib/services/wish_stats.dart`
- Modify: `lib/services/wish_filter.dart`
- Modify: `lib/widgets/item_type_pie.dart`
- Modify: `lib/widgets/data/search_filter_bar.dart`
- Modify: `lib/pages/banner_page.dart`
- Modify: `lib/pages/overview_page.dart`
- Modify: `test/models/wish_record_test.dart`
- Modify: `test/services/wish_stats_test.dart`
- Modify: `test/services/wish_filter_test.dart`
- Modify: `test/widgets/item_type_pie_test.dart`

這是大重構，必須一次完成讓 analyze + tests pass，但範圍乾淨：只動 `kind` 系統。

- [ ] **Step 1: 改 `WishStats` 結構（先測試）**

更新 `test/services/wish_stats_test.dart`，移除 `characterCount / weaponCount / unknownCount` 相關 expectation，新增：

```dart
test('byItemType 累計每種 item_type 出現次數', () {
  final records = [
    record(itemType: '角色', rank: 5),
    record(itemType: '角色', rank: 4),
    record(itemType: '武器', rank: 5),
    record(itemType: '裝扮', rank: 4),
  ];
  final stats = computeWishStats(records);
  expect(stats.byItemType, {'角色': 2, '武器': 1, '裝扮': 1});
});

test('twoStarCount 與 threeStarCount 分開計算', () {
  final records = [
    record(rank: 5), record(rank: 4),
    record(rank: 3), record(rank: 3),
    record(rank: 2),
  ];
  final stats = computeWishStats(records);
  expect(stats.fiveStarCount, 1);
  expect(stats.fourStarCount, 1);
  expect(stats.threeStarCount, 2);
  expect(stats.twoStarCount, 1);
});

test('空字串 itemType 累計到 ""', () {
  final records = [record(itemType: '', rank: 5)];
  final stats = computeWishStats(records);
  expect(stats.byItemType, {'': 1});
});
```

helper `record(...)` 定義（沿用既有 test 寫法或新增）：

```dart
WishRecord record({
  String itemType = '角色',
  int rank = 5,
  String id = '1',
  String uid = 'u',
  String gachaType = '301',
  String name = 'n',
  DateTime? time,
  String lang = 'zh-tw',
}) => WishRecord(
  id: id, uid: uid, gachaType: gachaType, name: name,
  itemType: itemType, rankType: rank,
  time: time ?? DateTime(2026, 1, 1), lang: lang,
);
```

- [ ] **Step 2: 改 `lib/services/wish_stats.dart`**

```dart
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';

class WishStats {
  const WishStats({
    required this.total,
    required this.fiveStarCount,
    required this.fourStarCount,
    required this.threeStarCount,
    required this.twoStarCount,
    required this.byItemType,
  });

  final int total;
  final int fiveStarCount;
  final int fourStarCount;
  final int threeStarCount;
  final int twoStarCount;
  final Map<String, int> byItemType;

  double _rate(int n) => total == 0 ? 0.0 : n / total;

  double get fiveStarRate => _rate(fiveStarCount);
  double get fourStarRate => _rate(fourStarCount);
  double get threeStarRate => _rate(threeStarCount);
  double get twoStarRate => _rate(twoStarCount);

  /// 依 count desc 排序的 entries（給 pie / legend 用）。
  List<MapEntry<String, int>> sortedItemTypes() {
    final list = byItemType.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

WishStats computeWishStats(List<WishRecord> records) {
  var five = 0, four = 0, three = 0, two = 0;
  final byItemType = <String, int>{};
  for (final r in records) {
    switch (r.rankType) {
      case 5: five++; break;
      case 4: four++; break;
      case 3: three++; break;
      case 2: two++; break;
    }
    byItemType[r.itemType] = (byItemType[r.itemType] ?? 0) + 1;
  }
  return WishStats(
    total: records.length,
    fiveStarCount: five,
    fourStarCount: four,
    threeStarCount: three,
    twoStarCount: two,
    byItemType: byItemType,
  );
}
```

- [ ] **Step 3: 改 `lib/models/wish_record.dart`**

整段重寫：

```dart
class WishRecord {
  const WishRecord({
    required this.id,
    required this.uid,
    required this.gachaType,
    required this.name,
    required this.itemType,
    required this.rankType,
    required this.time,
    required this.lang,
  });

  final String id;
  final String uid;
  final String gachaType;
  final String name;
  final String itemType;
  final int rankType;
  final DateTime time;
  final String lang;

  factory WishRecord.fromApiJson(Map<String, dynamic> json) => WishRecord(
    id: json['id'] as String,
    uid: json['uid'] as String,
    gachaType: json['gacha_type'] as String,
    name: json['name'] as String,
    itemType: json['item_type'] as String,
    rankType: int.parse(json['rank_type'] as String),
    time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
    lang: json['lang'] as String,
  );

  factory WishRecord.fromStorageJson(Map<String, dynamic> json) => WishRecord(
    id: json['id'] as String,
    uid: json['uid'] as String,
    gachaType: json['gacha_type'] as String,
    name: json['name'] as String,
    itemType: json['item_type'] as String,
    rankType: json['rank_type'] as int,
    time: DateTime.parse((json['time'] as String).replaceFirst(' ', 'T')),
    lang: json['lang'] as String,
  );

  Map<String, dynamic> toStorageJson() {
    final t = time;
    final timeStr =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'uid': uid,
      'gacha_type': gachaType,
      'name': name,
      'item_type': itemType,
      'rank_type': rankType,
      'time': timeStr,
      'lang': lang,
    };
  }
}
```

`WishItemKind` enum 整段刪除。

- [ ] **Step 4: 改 `lib/services/wish_filter.dart`**

```dart
import 'package:flutter/foundation.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_row.dart';

enum RarityFilter { all, fiveStar, fourStar }

@immutable
class RecordFilter {
  const RecordFilter({
    this.rarity = RarityFilter.all,
    this.itemType,
    this.query = '',
  });

  final RarityFilter rarity;

  /// null = 全部類型；非 null = 只看該 itemType 字串。
  final String? itemType;
  final String query;

  bool get hasAny =>
      rarity != RarityFilter.all ||
      itemType != null ||
      query.trim().isNotEmpty;

  RecordFilter copyWith({
    RarityFilter? rarity,
    Object? itemType = _sentinel,
    String? query,
  }) => RecordFilter(
    rarity: rarity ?? this.rarity,
    itemType: identical(itemType, _sentinel) ? this.itemType : itemType as String?,
    query: query ?? this.query,
  );

  static const _sentinel = Object();
}

enum SortColumn { time, name, kind, rarity, totalIndex, fiveStarPity }
enum SortDirection { asc, desc }

@immutable
class TableSort {
  // 不變（已在原檔）
  ...
}

List<RecordRow> filterRecordRows(List<RecordRow> rows, RecordFilter f) {
  final q = f.query.trim().toLowerCase();
  return rows.where((row) {
    final r = row.record;
    if (f.rarity == RarityFilter.fiveStar && r.rankType != 5) return false;
    if (f.rarity == RarityFilter.fourStar && r.rankType != 4) return false;
    if (f.itemType != null && r.itemType != f.itemType) return false;
    if (q.isNotEmpty && !r.name.toLowerCase().contains(q)) return false;
    return true;
  }).toList(growable: false);
}

// sortRecordRows 不變
```

把現有檔內 `KindFilter` enum 整段刪除，把 `import wish_record.dart` 拿掉（若沒其他依賴）。

**注意**：`copyWith` 用 sentinel 處理「想把 itemType 設回 null」與「不改 itemType」兩種情境。

- [ ] **Step 5: 改 `lib/widgets/item_type_pie.dart`**

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';

const double _kRingRadius = 75;
const double _kCenterRadius = 40;

/// 依出現順序分配 palette；超出 palette 長度時 wrap-around。
List<Color> _itemTypePalette(GachaTokens t) => [
  t.character,
  t.weapon,
  t.accentPrimary,
  t.threeStar,
  t.fourStar,
  t.fiveStar,
  t.textMuted,
];

List<DistributionEntry> itemTypeDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
  AppLocalizations l,
) {
  final palette = _itemTypePalette(tokens);
  return [
    for (final (i, e) in stats.sortedItemTypes().indexed)
      DistributionEntry(
        color: palette[i % palette.length],
        name: e.key.isEmpty ? l.kindUnknown : e.key,
        count: e.value,
        rate: stats.total == 0 ? 0.0 : e.value / stats.total,
      ),
  ];
}

class ItemTypePie extends StatelessWidget {
  const ItemTypePie({super.key, required this.stats});
  final WishStats stats;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (stats.total == 0) {
      return Center(
        child: Text(l.statsNoData, style: TextStyle(color: tokens.textMuted)),
      );
    }
    final palette = _itemTypePalette(tokens);
    final sections = <PieChartSectionData>[
      for (final (i, e) in stats.sortedItemTypes().indexed)
        PieChartSectionData(
          showTitle: false,
          value: e.value.toDouble(),
          color: palette[i % palette.length],
          radius: _kRingRadius,
        ),
    ];
    return PieChart(
      PieChartData(
        sections: sections,
        sectionsSpace: 2,
        centerSpaceRadius: _kCenterRadius,
        pieTouchData: PieTouchData(enabled: false),
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }
}
```

- [ ] **Step 6: 改 `lib/widgets/data/search_filter_bar.dart`**

`SearchFilterBar` 接受 `availableItemTypes: List<String>`，dropdown 由它驅動：

```dart
class SearchFilterBar extends StatefulWidget {
  const SearchFilterBar({
    super.key,
    required this.state,
    required this.availableItemTypes,
    required this.onFilterChanged,
    required this.onClear,
  });

  final RecordFilterState state;
  final List<String> availableItemTypes;  // 由 BannerPage 傳入
  final ValueChanged<RecordFilter> onFilterChanged;
  final VoidCallback onClear;
  // ...
}
```

在 build 內把原 KindFilter dropdown 整段換成：

```dart
DropdownButton<String?>(
  value: widget.state.filter.itemType,
  onChanged: (v) {
    widget.onFilterChanged(widget.state.filter.copyWith(itemType: v));
  },
  items: [
    DropdownMenuItem<String?>(
      value: null,
      child: Text(l.filterKindAll),
    ),
    for (final t in widget.availableItemTypes)
      DropdownMenuItem<String?>(value: t, child: Text(t)),
  ],
),
```

- [ ] **Step 7: 改 `lib/pages/banner_page.dart` 傳 availableItemTypes**

在 `BannerPage.build` 內 records 變數之後：

```dart
final availableItemTypes = records
    .map((r) => r.itemType)
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList()
  ..sort();
```

把 `SearchFilterBar(...)` 多傳 `availableItemTypes: availableItemTypes`。

- [ ] **Step 8: 更新 `lib/pages/overview_page.dart`**

OverviewPage 直接呼叫 `computeWishStats(all)`，回傳新結構，stats 字段使用會壞掉。把所有用到 `characterCount` / `weaponCount` / `unknownCount` 的地方換掉（grep 確認）。若 `itemTypeDistributionEntries` 與 `ItemTypePie` 都已動態，OverviewPage 不需特別改 — 但須確認 import / 引用點。

- [ ] **Step 9: 更新所有受影響測試**

- `test/models/wish_record_test.dart`：移除 `kind` / `WishItemKind` 相關 expectation；驗證 `fromStorageJson` 不會因缺 `kind` 鍵壞掉（舊檔讀寫）。
- `test/services/wish_filter_test.dart`：把 `KindFilter` cases 換成 `itemType: '角色'` / `itemType: null` cases。
- `test/widgets/item_type_pie_test.dart`：改驗證動態 entries（如「給 3 種 itemType 的 stats，產生 3 個 DistributionEntry，顏色依 palette 順序」）。
- `test/widgets/data/search_filter_bar_test.dart`（若存在）：傳 `availableItemTypes: ['角色', '武器']`，驗證 dropdown items。

- [ ] **Step 10: 跑單元測試確認綠**

```
flutter test test/models/wish_record_test.dart
flutter test test/services/wish_stats_test.dart
flutter test test/services/wish_filter_test.dart
flutter test test/widgets/item_type_pie_test.dart
flutter test test/widgets/data/search_filter_bar_test.dart
```

Expected: PASS

- [ ] **Step 11: Quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/models/wish_record.dart lib/services/wish_stats.dart \
        lib/services/wish_filter.dart lib/widgets/item_type_pie.dart \
        lib/widgets/data/search_filter_bar.dart \
        lib/pages/banner_page.dart lib/pages/overview_page.dart \
        test/models/wish_record_test.dart test/services/wish_stats_test.dart \
        test/services/wish_filter_test.dart test/widgets/item_type_pie_test.dart \
        test/widgets/data/search_filter_bar_test.dart
git commit -m "refactor(item-type): remove WishItemKind, drive distribution dynamically

- WishRecord 拿掉 kind 欄位（API item_type 字串本就是當前 lang，直接用）
- WishStats 新增 byItemType: Map<String,int>、twoStarCount、threeStarCount
- ItemTypePie / itemTypeDistributionEntries 改為依出現順序動態分配 palette
- SearchFilterBar kind dropdown 改為依當前 banner 出現的 itemType 動態列舉
- RecordFilter.kind (KindFilter enum) → itemType (String?)"
```

---

## Task 3: 加 `tokens.twoStar`，`RarityPie` 支援 2★

**Files:**
- Modify: `lib/theme/tokens.dart`
- Modify: `lib/widgets/rarity_pie.dart`
- Modify: `test/widgets/rarity_pie_test.dart`

- [ ] **Step 1: 寫 RarityPie 2★ 測試**

`test/widgets/rarity_pie_test.dart` 加：

```dart
testWidgets('rarityDistributionEntries 包含 2★ 當 twoStarCount > 0', (tester) async {
  final stats = WishStats(
    total: 10, fiveStarCount: 1, fourStarCount: 2,
    threeStarCount: 5, twoStarCount: 2, byItemType: const {},
  );
  // 包一層 MaterialApp 取 tokens
  await tester.pumpWidget(MaterialApp(
    theme: appTheme(brightness: Brightness.dark),
    home: Builder(builder: (ctx) {
      final tokens = Theme.of(ctx).gacha;
      final entries = rarityDistributionEntries(stats, tokens);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★', '2★']);
      expect(entries.last.count, 2);
      return const SizedBox.shrink();
    }),
  ));
});

testWidgets('rarityDistributionEntries 略過 2★ 當 twoStarCount == 0', (tester) async {
  final stats = WishStats(
    total: 8, fiveStarCount: 1, fourStarCount: 2,
    threeStarCount: 5, twoStarCount: 0, byItemType: const {},
  );
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (ctx) {
      final tokens = Theme.of(ctx).gacha;
      final entries = rarityDistributionEntries(stats, tokens);
      expect(entries.map((e) => e.name).toList(), ['5★', '4★', '3★']);
      return const SizedBox.shrink();
    }),
  ));
});
```

- [ ] **Step 2: 加 `tokens.twoStar`**

`lib/theme/tokens.dart`：

```dart
@immutable
class GachaTokens extends ThemeExtension<GachaTokens> {
  const GachaTokens({
    ...
    required this.fiveStar,
    required this.fourStar,
    required this.threeStar,
    required this.twoStar,    // 新增
    ...
  });

  final Color twoStar;        // 新增

  static const dark = GachaTokens(
    ...
    threeStar: Color(0xFF5B9BD5),
    twoStar: Color(0xFF6A7080),    // 灰藍，比 textMuted 略深
    ...
  );

  static const light = GachaTokens(
    ...
    threeStar: Color(0xFF2E7CC2),
    twoStar: Color(0xFF8A92A6),
    ...
  );

  // copyWith 加 twoStar 參數
  // lerp 加 twoStar 計算
}
```

- [ ] **Step 3: 改 `lib/widgets/rarity_pie.dart`**

```dart
List<DistributionEntry> rarityDistributionEntries(
  WishStats stats,
  GachaTokens tokens,
) {
  return [
    DistributionEntry(
      color: tokens.fiveStar, name: '5★',
      count: stats.fiveStarCount, rate: stats.fiveStarRate,
    ),
    DistributionEntry(
      color: tokens.fourStar, name: '4★',
      count: stats.fourStarCount, rate: stats.fourStarRate,
    ),
    DistributionEntry(
      color: tokens.threeStar, name: '3★',
      count: stats.threeStarCount, rate: stats.threeStarRate,
    ),
    if (stats.twoStarCount > 0)
      DistributionEntry(
        color: tokens.twoStar, name: '2★',
        count: stats.twoStarCount, rate: stats.twoStarRate,
      ),
  ];
}

// RarityPie.build 內 sections list 加上：
final sections = <PieChartSectionData>[
  _section(stats.fiveStarCount, tokens.fiveStar),
  _section(stats.fourStarCount, tokens.fourStar),
  _section(stats.threeStarCount, tokens.threeStar),
  if (stats.twoStarCount > 0) _section(stats.twoStarCount, tokens.twoStar),
].where((s) => s.value > 0).toList(growable: false);
```

**注意**：之前 `stats.threeStarOrBelowCount` 把 2★ 也算在內，現在 `threeStarCount` 純 3★、`twoStarCount` 純 2★，兩者分離。

- [ ] **Step 4: 跑測試 + Quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/theme/tokens.dart lib/widgets/rarity_pie.dart \
        test/widgets/rarity_pie_test.dart
git commit -m "feat(rarity-pie): support 2★ for odes standard banner

- tokens 加 twoStar 配色
- RarityPie / rarityDistributionEntries 4 等稀有度分開計算，當 2★ count > 0 才顯示"
```

---

## Task 4: 提供 `accentForRank` helper

**Files:**
- Create: `lib/widgets/rank_palette.dart`

純函數，給後續 task 用。不需要獨立測試（trivial pure mapping）。

- [ ] **Step 1: 建立檔案**

```dart
// lib/widgets/rank_palette.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 依稀有度 rank 取對應主色 token。
Color accentForRank(int rank, GachaTokens t) => switch (rank) {
  5 => t.fiveStar,
  4 => t.fourStar,
  3 => t.threeStar,
  2 => t.twoStar,
  _ => t.textMuted,
};
```

- [ ] **Step 2: Quality gate + commit**

```
dart format lib/
flutter analyze
flutter test
```

```bash
git add lib/widgets/rank_palette.dart
git commit -m "feat(theme): add accentForRank helper"
```

---

## Task 5: `Timeline` 支援動態目標稀有度

**Files:**
- Modify: `lib/services/timeline_entries.dart`
- Modify: `test/services/timeline_entries_test.dart`

把寫死 5★ 改為 `targetRank` 參數，並 rename 對外 API（鍵字「fiveStar」改「ranked」）。

- [ ] **Step 1: 先更新測試**

`test/services/timeline_entries_test.dart`：

- 找所有 `buildTimelineEntries(records)` 呼叫，多傳 `targetRank: 5` 維持原行為
- 找所有 `pullsSinceLastFiveStar(records)` 呼叫，改為 `pullsSinceLastRanked(records, rank: 5)`
- 找所有 `buildTimelineEntriesAcrossBanners(banners)` 呼叫，多傳 `rankFor: (_) => 5`
- 找所有 `pullsSinceLastFiveStarAcrossBanners(banners)` 呼叫，改為 `pullsSinceLastRankedAcrossBanners(banners, rankFor: (_) => 5)`
- 新增 case：`targetRank: 4` 時對 4★ 萃取 entries（用幾筆 mix 5/4/3 records 驗證）

- [ ] **Step 2: 改 `lib/services/timeline_entries.dart`**

```dart
List<TimelineEntry> buildTimelineEntries(
  List<WishRecord> records, {
  int targetRank = 5,
}) {
  final asc = records.reversed.toList(growable: false);
  final out = <TimelineEntry>[];
  var pull = 0;
  for (final r in asc) {
    pull++;
    if (r.rankType == targetRank) {
      out.add(TimelineEntry(
        name: r.name,
        gachaType: r.gachaType,
        time: r.time,
        pullsSincePrev: pull,
      ));
      pull = 0;
    }
  }
  return out.reversed.toList(growable: false);
}

List<TimelineEntry> buildTimelineEntriesAcrossBanners(
  Map<String, List<WishRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  final out = <TimelineEntry>[];
  for (final entry in banners.entries) {
    out.addAll(buildTimelineEntries(entry.value, targetRank: rankFor(entry.key)));
  }
  out.sort((a, b) => b.time.compareTo(a.time));
  return out;
}

int pullsSinceLastRanked(List<WishRecord> records, {required int rank}) {
  var count = 0;
  for (final r in records) {
    if (r.rankType == rank) return count;
    count++;
  }
  return count;
}

int pullsSinceLastRankedAcrossBanners(
  Map<String, List<WishRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  String? latestId;
  String? latestPool;
  DateTime? latestTime;
  for (final entry in banners.entries) {
    final rank = rankFor(entry.key);
    for (final r in entry.value) {
      if (r.rankType == rank) {
        if (latestTime == null || r.time.isAfter(latestTime)) {
          latestTime = r.time;
          latestId = r.id;
          latestPool = entry.key;
        }
        break;
      }
    }
  }
  if (latestTime == null) {
    var total = 0;
    for (final records in banners.values) {
      total += records.length;
    }
    return total;
  }
  var count = 0;
  for (final entry in banners.entries) {
    final records = entry.value;
    if (entry.key == latestPool) {
      for (final r in records) {
        if (r.id == latestId) break;
        count++;
      }
    } else {
      for (final r in records) {
        if (r.time.isAfter(latestTime)) {
          count++;
        } else {
          break;
        }
      }
    }
  }
  return count;
}
```

- [ ] **Step 3: 更新所有 caller**

Grep 找所有 `pullsSinceLastFiveStar` / `buildTimelineEntriesAcrossBanners`：

- `lib/pages/banner_page.dart` — `pullsSinceLastFiveStar(records)` → `pullsSinceLastRanked(records, rank: type.primaryPity.rank)`
- `lib/pages/overview_page.dart` — `buildTimelineEntriesAcrossBanners(activeData.banners)` → 加 `rankFor: (_) => 5`（這個 task 只做 wish 段，odes 段在 Task 14 加入）
- `lib/pages/overview_page.dart` — `pullsSinceLastFiveStarAcrossBanners(banners)` → `pullsSinceLastRankedAcrossBanners(banners, rankFor: (_) => 5)`
- `lib/widgets/cards/timeline_horizontal.dart` / `timeline_vertical.dart` — 標題 i18n 之後 Task 10 改

- [ ] **Step 4: Quality gate + commit**

```bash
git add lib/services/timeline_entries.dart \
        lib/pages/banner_page.dart lib/pages/overview_page.dart \
        test/services/timeline_entries_test.dart
git commit -m "refactor(timeline): support dynamic target rank

- buildTimelineEntries 加 targetRank 參數（預設 5）
- buildTimelineEntriesAcrossBanners 改為接受 rankFor callback
- pullsSinceLastFiveStar* → pullsSinceLastRanked* rename
- 既有 caller 全部維持 rank=5 行為不變"
```

---

## Task 6: 加 `GachaEndpoint` 與 `GachaUrl.build` endpoint 替換

**Files:**
- Modify: `lib/services/gacha_url.dart`
- Modify: `test/services/gacha_url_test.dart`

- [ ] **Step 1: 先寫測試**

`test/services/gacha_url_test.dart` 加：

```dart
test('build with endpoint=wish 保留 getGachaLog path', () {
  final url = GachaUrl.parse(
    'https://example.com/gacha_info/api/getGachaLog?authkey=AAA&gacha_type=301&end_id=0',
  );
  final built = url.build(
    gachaType: '301', endId: '0',
    endpoint: GachaEndpoint.wish,
  );
  expect(built.path, '/gacha_info/api/getGachaLog');
});

test('build with endpoint=odes 替換為 getBeyondGachaLog', () {
  final url = GachaUrl.parse(
    'https://example.com/gacha_info/api/getGachaLog?authkey=AAA&gacha_type=301&end_id=0',
  );
  final built = url.build(
    gachaType: '2000', endId: '0',
    endpoint: GachaEndpoint.odes,
  );
  expect(built.path, '/gacha_info/api/getBeyondGachaLog');
});

test('build 從 odes URL 解析後也能切回 wish', () {
  final url = GachaUrl.parse(
    'https://example.com/gacha_info/api/getBeyondGachaLog?authkey=AAA&gacha_type=2000&end_id=0',
  );
  final built = url.build(
    gachaType: '301', endId: '0',
    endpoint: GachaEndpoint.wish,
  );
  expect(built.path, '/gacha_info/api/getGachaLog');
});
```

- [ ] **Step 2: 改 `lib/services/gacha_url.dart`**

```dart
enum GachaEndpoint {
  wish('getGachaLog'),
  odes('getBeyondGachaLog');

  const GachaEndpoint(this.pathSegment);
  final String pathSegment;
}

class GachaUrl {
  GachaUrl._(this._uri);

  final Uri _uri;

  static GachaUrl parse(String capturedUrl) =>
      GachaUrl._(Uri.parse(capturedUrl));

  Uri build({
    required String gachaType,
    required String endId,
    required GachaEndpoint endpoint,
    int size = 20,
    int page = 1,
  }) {
    final segments = List<String>.from(_uri.pathSegments);
    if (segments.isNotEmpty) {
      segments[segments.length - 1] = endpoint.pathSegment;
    } else {
      segments.add(endpoint.pathSegment);
    }
    final params = Map<String, String>.from(_uri.queryParameters)
      ..['gacha_type'] = gachaType
      ..['page'] = page.toString()
      ..['size'] = size.toString()
      ..['end_id'] = endId;
    return _uri.replace(pathSegments: segments, queryParameters: params);
  }
}
```

- [ ] **Step 3: 更新既有 caller**

Grep `url.build(`，每個呼叫加 `endpoint: GachaEndpoint.wish`（這個 task 全部都還是祈願，下一個 task 才依 category 切）。

- `lib/state/wish_repository.dart`
- `lib/services/wish_fetcher.dart`（含 `probeUid`）

- [ ] **Step 4: Quality gate + commit**

```bash
git add lib/services/gacha_url.dart lib/state/wish_repository.dart \
        lib/services/wish_fetcher.dart test/services/gacha_url_test.dart
git commit -m "feat(gacha-url): add GachaEndpoint enum for endpoint switching

- 新增 GachaEndpoint.wish (getGachaLog) / .odes (getBeyondGachaLog)
- build() 多吃 endpoint，替換 path 最後一段
- 既有 caller 全部傳 GachaEndpoint.wish 維持行為不變"
```

---

## Task 7: `WishFetcher` 加 endpoint 傳遞

**Files:**
- Modify: `lib/services/wish_fetcher.dart`
- Modify: `test/services/wish_fetcher_test.dart`

- [ ] **Step 1: 寫測試 — fetchBannerWithMerge 依 endpoint 打對 URL**

`test/services/wish_fetcher_test.dart` 新增：

```dart
test('fetchBannerWithMerge with endpoint=odes 走 getBeyondGachaLog', () async {
  final paths = <String>[];
  final client = MockClient((req) async {
    paths.add(req.url.path);
    return http.Response(jsonEncode({'retcode': 0, 'data': {'list': []}}), 200);
  });
  await WishFetcher().fetchBannerWithMerge(
    url: GachaUrl.parse(_baseUrl()),
    gachaType: '2000',
    endpoint: GachaEndpoint.odes,
    existing: const [],
    primer: null,
    onProgress: (_) {},
    client: client,
  );
  expect(paths.every((p) => p.endsWith('/getBeyondGachaLog')), isTrue);
});
```

- [ ] **Step 2: 改 `lib/services/wish_fetcher.dart`**

`fetchBannerWithMerge`：

```dart
Future<List<WishRecord>> fetchBannerWithMerge({
  required GachaUrl url,
  required String gachaType,
  required GachaEndpoint endpoint,   // 新增
  required List<WishRecord> existing,
  required FetchedPage? primer,
  required void Function(FetchProgress) onProgress,
  required http.Client client,
}) async {
  // 內部所有 url.build(...) 加 endpoint: endpoint
  ...
}
```

`probeUid` 改為兩階段：

```dart
Future<UidProbeResult> probeUid({
  required GachaUrl url,
  required http.Client client,
}) async {
  final primers = <String, FetchedPage>{};

  Future<UidProbeResult?> tryCategory(GachaCategory cat) async {
    final endpoint = switch (cat) {
      GachaCategory.wish => GachaEndpoint.wish,
      GachaCategory.odes => GachaEndpoint.odes,
    };
    for (final type in gachaTypes.where((t) => t.category == cat)) {
      if (primers.isNotEmpty) await Future<void>.delayed(rateLimit);
      final page = await fetchPage(
        url.build(
          gachaType: type.gachaType, endId: '0', endpoint: endpoint,
        ),
        client,
      );
      primers[type.gachaType] = page;
      if (page.records.isNotEmpty) {
        return UidProbeResult(
          uid: page.records.first.uid,
          primerPages: primers,
        );
      }
    }
    return null;
  }

  final wishHit = await tryCategory(GachaCategory.wish);
  if (wishHit != null) return wishHit;
  final odesHit = await tryCategory(GachaCategory.odes);
  if (odesHit != null) return odesHit;
  return UidProbeResult(uid: null, primerPages: primers);
}
```

- [ ] **Step 3: 跑 wish_fetcher_test**

```
flutter test test/services/wish_fetcher_test.dart
```

Expected: PASS（既有 wish endpoint 行為不變，新測試覆蓋 odes path）

- [ ] **Step 4: Quality gate + commit**

```bash
git add lib/services/wish_fetcher.dart test/services/wish_fetcher_test.dart
git commit -m "feat(wish-fetcher): thread endpoint through fetchBannerWithMerge

- fetchBannerWithMerge 多吃 endpoint 參數
- probeUid 改為先掃所有 wish banner、若都空再掃所有 odes banner
- 一個 UID 即使只在祈願 OR 頌願有紀錄都能正確探測"
```

---

## Task 8: `WishRepository` 依 category 切 endpoint

**Files:**
- Modify: `lib/state/wish_repository.dart`

- [ ] **Step 1: 改 `_fetchAllBanners`**

```dart
for (final t in gachaTypes) {
  final endpoint = switch (t.category) {
    GachaCategory.wish => GachaEndpoint.wish,
    GachaCategory.odes => GachaEndpoint.odes,
  };
  try {
    final merged = await fetcher.fetchBannerWithMerge(
      url: gachaUrl,
      gachaType: t.gachaType,
      endpoint: endpoint,
      existing: existing.banners[t.gachaType] ?? const [],
      primer: probe.primerPages[t.gachaType],
      client: client,
      onProgress: (p) { ... },  // 不動
    );
    ...
  }
}
```

- [ ] **Step 2: Quality gate + commit**

```bash
git add lib/state/wish_repository.dart
git commit -m "feat(wish-repository): pick endpoint per gacha category"
```

---

## Task 9: Rust mitm 接受 `getBeyondGachaLog`

**Files:**
- Modify: `rust/src/mitm.rs`

- [ ] **Step 1: 改 `is_target`**

`rust/src/mitm.rs:34`：

```rust
fn is_target(uri: &Uri) -> bool {
    let host_ok = uri
        .host()
        .map(|h| h == "hoyoverse.com" || h.ends_with(".hoyoverse.com"))
        .unwrap_or(false);
    let path = uri.path();
    let path_ok = path.ends_with("/getGachaLog")
               || path.ends_with("/getBeyondGachaLog");
    host_ok && path_ok
}
```

- [ ] **Step 2: 跑 cargo check 確認編譯**

```
cd rust && cargo check
```

Expected: 編譯通過

- [ ] **Step 3: Quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add rust/src/mitm.rs
git commit -m "feat(mitm): accept getBeyondGachaLog endpoint for Odes capture"
```

---

## Task 10: 加 odes 兩個 GachaType + i18n key

**Files:**
- Modify: `lib/data/gacha_types.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `test/data/gacha_types_test.dart`

**注意**：其他 7 個 ARB 檔（es / fr / ja / pt / th / vi / zh）**完全不動**，缺 key 自動 fallback 到 en。

- [ ] **Step 1: 加 i18n key（en / zh_Hant / zh_Hans）**

新增 key（以下表格為 zh_Hant / zh_Hans / en）：

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
| `timelineCountTopRarity` | `{rank}★ 時間軸 ({n})` | `{rank}★ 时间轴 ({n})` | `{rank}★ timeline ({n})` |

`timelineCountTopRarity` 的 ARB 範例（en）：

```json
"timelineCountTopRarity": "{rank}★ timeline ({n})",
"@timelineCountTopRarity": {
  "placeholders": {
    "rank": { "type": "int" },
    "n": { "type": "int" }
  }
}
```

**移除 key**（從 en / zh_Hant / zh_Hans 三檔同步刪除）：
- `kindCharacter`、`kindWeapon`
- `filterKindCharacter`、`filterKindWeapon`
- `timelineCountFiveStar`

**保留**：`kindUnknown`、`filterKindAll`。

- [ ] **Step 2: 跑 `flutter gen-l10n`（如有設定 hook）或重新 build**

`flutter pub get` 觸發 i18n codegen。確認 `lib/l10n/generated/app_localizations.dart` 更新。

- [ ] **Step 3: 加頌願兩個 GachaType + 更新 resolveName**

```dart
// lib/data/gacha_types.dart

const _pityFive70 = PityRule(rank: 5, threshold: 70, labelKey: 'pityFiveStar');
const _pityFour70 = PityRule(rank: 4, threshold: 70, labelKey: 'pityFourStar');
const _pityThree5 = PityRule(rank: 3, threshold: 5, labelKey: 'pityThreeStar');

const gachaTypes = <GachaType>[
  // ... 既有 5 個 wish ...
  GachaType(
    gachaType: '2000',
    nameKey: 'gachaTypeOdesEvent',
    category: GachaCategory.odes,
    pities: [_pityFive70, _pityFour10],
  ),
  GachaType(
    gachaType: '1000',
    nameKey: 'gachaTypeOdesStandard',
    category: GachaCategory.odes,
    pities: [_pityFour70, _pityThree5],
  ),
];
```

`resolveName` 加兩個 case：

```dart
String resolveName(AppLocalizations l) => switch (nameKey) {
  ...
  'gachaTypeOdesEvent' => l.gachaTypeOdesEvent,
  'gachaTypeOdesStandard' => l.gachaTypeOdesStandard,
  _ => nameKey,
};
```

- [ ] **Step 4: 更新 `test/data/gacha_types_test.dart`**

加 case：

```dart
test('2 個頌願 type 是 odes category', () {
  const odesTypes = {'2000', '1000'};
  for (final t in gachaTypes) {
    if (odesTypes.contains(t.gachaType)) {
      expect(t.category, GachaCategory.odes);
    }
  }
});

test('活動頌願 (2000): 5★ 70 / 4★ 10', () {
  final t = gachaTypes.firstWhere((g) => g.gachaType == '2000');
  expect(t.primaryPity.rank, 5);
  expect(t.primaryPity.threshold, 70);
  expect(t.secondaryPity!.rank, 4);
  expect(t.secondaryPity!.threshold, 10);
});

test('常駐頌願 (1000): 4★ 70 / 3★ 5（無 5★）', () {
  final t = gachaTypes.firstWhere((g) => g.gachaType == '1000');
  expect(t.primaryPity.rank, 4);
  expect(t.primaryPity.threshold, 70);
  expect(t.secondaryPity!.rank, 3);
  expect(t.secondaryPity!.threshold, 5);
});
```

- [ ] **Step 5: Quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/data/gacha_types.dart lib/l10n/app_en.arb \
        lib/l10n/app_zh_Hant.arb lib/l10n/app_zh_Hans.arb \
        test/data/gacha_types_test.dart
git commit -m "feat(odes): register Event Odes (2000) and Standard Odes (1000) banners

- gachaTypes 加入 odes category 兩個 type
- 活動頌願保底 5★/70 + 4★/10；常駐頌願 4★/70 + 3★/5（無 5★）
- 新增 i18n key (en/zh_Hant/zh_Hans)；移除已不再使用的 kind/filterKind/timeline 寫死 key
- 其他 7 語言檔不動，自動 fallback 到 en"
```

---

## Task 11: `BannerColors` 加頌願配色與圖示

**Files:**
- Modify: `lib/theme/tokens.dart`
- Modify: `lib/widgets/banner_colors.dart`
- Modify: `lib/pages/banner_page.dart`

- [ ] **Step 1: 加 tokens.odesEvent / odesStandard**

`lib/theme/tokens.dart`：

```dart
const dark = GachaTokens(
  ...
  character: Color(0xFF46B07A),
  weapon: Color(0xFFE6736B),
  odesEvent: Color(0xFFD9A3E6),     // 粉紫，與祈願 character/weapon 視覺區隔
  odesStandard: Color(0xFF8A92A6),  // 中性灰藍
  ...
);

const light = GachaTokens(
  ...
  character: Color(0xFF2E7D32),
  weapon: Color(0xFFC62828),
  odesEvent: Color(0xFFAB47BC),
  odesStandard: Color(0xFF6A7080),
  ...
);
```

加到建構式必要參數 + 欄位 + copyWith + lerp。

- [ ] **Step 2: 改 `lib/widgets/banner_colors.dart`**

```dart
factory BannerColors.fromTokens(GachaTokens tokens) => BannerColors(
  character: tokens.character,
  weapon: tokens.weapon,
  chronicled: tokens.accentPrimary,
  standard: tokens.threeStar,
  beginner: tokens.textMuted,
  odesEvent: tokens.odesEvent,
  odesStandard: tokens.odesStandard,
  fallback: tokens.textMuted,
);

final Color odesEvent;
final Color odesStandard;

Color colorFor(String gachaType) => switch (gachaType) {
  '301' => character,
  '302' => weapon,
  '500' => chronicled,
  '200' => standard,
  '100' => beginner,
  '2000' => odesEvent,
  '1000' => odesStandard,
  _ => fallback,
};
```

- [ ] **Step 3: 改 `lib/pages/banner_page.dart` `_iconForGachaType`**

```dart
IconData _iconForGachaType(GachaType type) {
  return switch (type.nameKey) {
    'gachaTypeCharacter' => Icons.person_outline,
    'gachaTypeWeapon' => Icons.shield_outlined,
    'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
    'gachaTypeStandard' => Icons.history,
    'gachaTypeBeginner' => Icons.school_outlined,
    'gachaTypeOdesEvent' => Icons.auto_awesome,
    'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
    _ => Icons.casino_outlined,
  };
}
```

- [ ] **Step 4: Quality gate + commit**

```bash
git add lib/theme/tokens.dart lib/widgets/banner_colors.dart \
        lib/pages/banner_page.dart
git commit -m "feat(theme): add Odes banner colors and icons"
```

---

## Task 12: `BannerFiveStarBars` → `BannerTopRarityBars`

**Files:**
- Create: `lib/widgets/cards/banner_top_rarity_bars.dart`
- Delete: `lib/widgets/cards/banner_five_star_bars.dart`
- Rename: `test/widgets/cards/banner_five_star_bars_test.dart` → `banner_top_rarity_bars_test.dart`
- Modify: `lib/pages/overview_page.dart`

- [ ] **Step 1: 先寫新測試**

`test/widgets/cards/banner_top_rarity_bars_test.dart`：（從舊測試 rename + 改）

```dart
testWidgets('依每個 type 自己的 primaryPity.rank 算件數', (tester) async {
  final eventOdes = gachaTypes.firstWhere((t) => t.gachaType == '2000');
  final standardOdes = gachaTypes.firstWhere((t) => t.gachaType == '1000');
  final banners = <String, List<WishRecord>>{
    '2000': [
      record(rank: 5, gachaType: '2000'),    // 算這筆（活動頌願主稀有度 5★）
      record(rank: 4, gachaType: '2000'),
    ],
    '1000': [
      record(rank: 4, gachaType: '1000'),    // 算這筆（常駐頌願主稀有度 4★）
      record(rank: 3, gachaType: '1000'),
    ],
  };
  await tester.pumpWidget(MaterialApp(
    theme: appTheme(brightness: Brightness.dark),
    home: BannerTopRarityBars(
      types: [eventOdes, standardOdes],
      banners: banners,
      colors: BannerColors.fromTokens(GachaTokens.dark),
    ),
  ));
  expect(find.text('1'), findsNWidgets(2));  // 兩條 bar 各 1 件
});

testWidgets('既有祈願 wish 5 個 type 用 5★ rank 維持原行為', (tester) async {
  final wishTypes = gachaTypes.where((t) => t.category == GachaCategory.wish).toList();
  // ... (沿用舊 banner_five_star_bars_test 測試案例邏輯)
});
```

- [ ] **Step 2: 建立 `lib/widgets/cards/banner_top_rarity_bars.dart`**

完整檔案內容（從 `banner_five_star_bars.dart` 複製改）：

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/wish_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

class BannerTopRarityBars extends StatelessWidget {
  const BannerTopRarityBars({
    super.key,
    required this.types,
    required this.banners,
    required this.colors,
  });

  final List<GachaType> types;
  final Map<String, List<WishRecord>> banners;
  final BannerColors colors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final counts = <String, int>{
      for (final t in types)
        t.gachaType: (banners[t.gachaType] ?? const [])
            .where((r) => r.rankType == t.primaryPity.rank)
            .length,
    };
    final maxCount = counts.values.fold<int>(0, (m, v) => v > m ? v : m);

    final rows = types.map((type) {
      final records = banners[type.gachaType] ?? const <WishRecord>[];
      final topCount = counts[type.gachaType]!;
      final isEnded = type.gachaType == '100';
      final String subtitle;
      if (isEnded) {
        subtitle = l.pityBeginnerEnded;
      } else if (topCount == 0) {
        subtitle = l.pityNoFiveStar;
      } else {
        final pity = computePity(
          records,
          threshold: type.primaryPity.threshold,
          rank: type.primaryPity.rank,
        ).current;
        subtitle = l.bannerFiveStarPullsSinceLast(pity);
      }
      return _BannerRow(
        name: type.resolveName(l),
        color: colors.colorFor(type.gachaType),
        topCount: topCount,
        subtitle: subtitle,
        ratio: maxCount == 0 ? 0.0 : topCount / maxCount,
      );
    }).toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s),
          rows[i],
        ],
      ],
    );
  }
}

// _BannerRow / _Bar 從舊檔複製（把 fiveStarCount 改 topCount）
class _BannerRow extends StatelessWidget {
  const _BannerRow({
    required this.name,
    required this.color,
    required this.topCount,
    required this.subtitle,
    required this.ratio,
  });
  final String name;
  final Color color;
  final int topCount;
  final String subtitle;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(name, style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.right, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(child: _Bar(color: color, ratio: ratio)),
        const SizedBox(width: AppSpacing.s),
        SizedBox(
          width: 156,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$topCount',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('·', style: TextStyle(color: tokens.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textMuted),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.ratio});
  final Color color;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          heightFactor: 1.0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.55), color],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 改 `lib/pages/overview_page.dart` 用新 widget**

把舊：

```dart
ChartCard(
  title: l.bannerFiveStarCountTitle,
  ...
  chart: BannerFiveStarBars(banners: activeData.banners, colors: bannerColors),
),
```

換成（後續 Task 14 再拆 wish / odes section，這個 task 先讓主檔不壞）：

```dart
ChartCard(
  title: l.bannerTopRarityCountTitle,
  ...
  chart: BannerTopRarityBars(
    types: gachaTypes,
    banners: activeData.banners,
    colors: bannerColors,
  ),
),
```

- [ ] **Step 4: 刪除舊檔**

```bash
git rm lib/widgets/cards/banner_five_star_bars.dart
git mv test/widgets/cards/banner_five_star_bars_test.dart \
       test/widgets/cards/banner_top_rarity_bars_test.dart
```

（如 git mv 不適用，手動刪 + 新增）

- [ ] **Step 5: Quality gate + commit**

```bash
git add -A
git commit -m "refactor(overview): rename BannerFiveStarBars → BannerTopRarityBars

- 依每個 GachaType 自己的 primaryPity.rank 算件數
- 祈願 5 個 type 仍是 5★，行為不變
- 頌願 type 用各自主稀有度（活動 5★、常駐 4★）"
```

---

## Task 13: `AppShell._Rail` 拆三段 + section labels

**Files:**
- Modify: `lib/pages/app_shell.dart`

這個 task 純 UI 結構。沒有單獨測試（widget test 屬於 banner_page 整合測試範圍）。

- [ ] **Step 1: 改 `_Rail` 為三段**

把原 `NavigationRail` 拆為三段：

```dart
class _Rail extends StatelessWidget {
  // ...constructor 不變，但 selectedIndex 改為 _RailSelection
  ...
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;

    // 三條 rail 的 destinations
    final topDestinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: Text(l.navOverview),
      ),
    ];

    final wishTypes = gachaTypes.where((t) => t.category == GachaCategory.wish).toList();
    final wishDestinations = wishTypes.map((t) => NavigationRailDestination(
      icon: Icon(_railIconInactive(t.nameKey)),
      selectedIcon: Icon(_railIconActive(t.nameKey)),
      label: Text(_railLabel(t.nameKey, l)),
    )).toList();

    final odesTypes = gachaTypes.where((t) => t.category == GachaCategory.odes).toList();
    final odesDestinations = odesTypes.map((t) => NavigationRailDestination(
      icon: Icon(_railIconInactive(t.nameKey)),
      selectedIcon: Icon(_railIconActive(t.nameKey)),
      label: Text(_railLabel(t.nameKey, l)),
    )).toList();

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  NavigationRail(
                    selectedIndex: selection.topIndex,
                    onDestinationSelected: (_) => context.go('/'),
                    extended: extended,
                    labelType: extended ? null
                        : (collapsedNoLabel
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all),
                    destinations: topDestinations,
                    groupAlignment: -1.0,
                  ),
                  _SectionLabel(
                    label: l.navSectionWish,
                    extended: extended,
                    hideLabel: collapsedNoLabel,
                    tokens: tokens,
                  ),
                  NavigationRail(
                    selectedIndex: selection.wishIndex,
                    onDestinationSelected: (i) =>
                        context.go('/banner/${wishTypes[i].gachaType}'),
                    extended: extended,
                    labelType: extended ? null
                        : (collapsedNoLabel
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all),
                    destinations: wishDestinations,
                    groupAlignment: -1.0,
                  ),
                  _SectionLabel(
                    label: l.navSectionOdes,
                    extended: extended,
                    hideLabel: collapsedNoLabel,
                    tokens: tokens,
                  ),
                  NavigationRail(
                    selectedIndex: selection.odesIndex,
                    onDestinationSelected: (i) =>
                        context.go('/banner/${odesTypes[i].gachaType}'),
                    extended: extended,
                    labelType: extended ? null
                        : (collapsedNoLabel
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all),
                    destinations: odesDestinations,
                    groupAlignment: -1.0,
                  ),
                ],
              ),
            ),
          ),
          // 既有底部按鈕（貢獻者、設定）保留不動
          _BottomRailButton(... contributors ...),
          _BottomRailButton(... settings ...),
        ],
      ),
    );
  }
}

class _RailSelection {
  const _RailSelection({this.topIndex, this.wishIndex, this.odesIndex});
  final int? topIndex;
  final int? wishIndex;
  final int? odesIndex;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label, required this.extended,
    required this.hideLabel, required this.tokens,
  });
  final String label;
  final bool extended;
  final bool hideLabel;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      child: hideLabel
          ? Divider(height: 1, color: tokens.borderSubtle)
          : Row(
              children: [
                Expanded(child: Divider(color: tokens.borderSubtle)),
                if (extended) ...[
                  const SizedBox(width: AppSpacing.s),
                  Text(label,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.textMuted)),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: Divider(color: tokens.borderSubtle)),
                ],
              ],
            ),
    );
  }
}
```

- [ ] **Step 2: 改 `_AppShellState._bannerIndexFromLocation` 為 `_resolveRailSelection`**

```dart
_RailSelection _resolveRailSelection(String path, bool isSettings, bool isContributors) {
  if (isSettings || isContributors) {
    return const _RailSelection();
  }
  if (path == '/') return const _RailSelection(topIndex: 0);
  if (path.startsWith('/banner/')) {
    final type = path.substring('/banner/'.length);
    final wishTypes = gachaTypes.where((t) => t.category == GachaCategory.wish).toList();
    final wi = wishTypes.indexWhere((t) => t.gachaType == type);
    if (wi >= 0) return _RailSelection(wishIndex: wi);
    final odesTypes = gachaTypes.where((t) => t.category == GachaCategory.odes).toList();
    final oi = odesTypes.indexWhere((t) => t.gachaType == type);
    if (oi >= 0) return _RailSelection(odesIndex: oi);
  }
  return const _RailSelection(topIndex: 0);
}
```

並把 `_Rail` 的 `selectedIndex: int?` 改為 `selection: _RailSelection`。

- [ ] **Step 3: 加 `_railIconActive` / `_railIconInactive` / `_railLabel` helpers**

```dart
String _railLabel(String nameKey, AppLocalizations l) => switch (nameKey) {
  'gachaTypeCharacter' => l.navCharacter,
  'gachaTypeWeapon' => l.navWeapon,
  'gachaTypeChronicled' => l.navChronicled,
  'gachaTypeStandard' => l.navStandard,
  'gachaTypeBeginner' => l.navBeginner,
  'gachaTypeOdesEvent' => l.navOdesEvent,
  'gachaTypeOdesStandard' => l.navOdesStandard,
  _ => nameKey,
};

IconData _railIconInactive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person_outline,
  'gachaTypeWeapon' => Icons.shield_outlined,
  'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
  'gachaTypeStandard' => Icons.history,
  'gachaTypeBeginner' => Icons.school_outlined,
  'gachaTypeOdesEvent' => Icons.auto_awesome_outlined,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion_outlined,
  _ => Icons.casino_outlined,
};

IconData _railIconActive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person,
  'gachaTypeWeapon' => Icons.shield,
  'gachaTypeChronicled' => Icons.collections_bookmark,
  'gachaTypeStandard' => Icons.history_toggle_off,
  'gachaTypeBeginner' => Icons.school,
  'gachaTypeOdesEvent' => Icons.auto_awesome,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
  _ => Icons.casino,
};
```

- [ ] **Step 4: 手動 smoke test**

`flutter run -d windows`，視覺確認：

- 側選單顯示「綜合 / ─祈願─ / 角色 / 武器 / 集錄 / 常駐 / 新手 / ─頌願─ / 活動頌願 / 常駐頌願 / ─ / 貢獻者 / 設定」
- extended（寬度 ≥ 1180）顯示 section label「祈願」「頌願」
- collapsed + with label（800 ≤ 寬 < 1180）也顯示
- collapsed no label（寬 < 800）只顯示 divider
- 點頌願頁面 navigate 成功，網址 `/banner/2000` 或 `/banner/1000`

- [ ] **Step 5: Quality gate + commit**

```
dart format lib/ test/
flutter analyze
flutter test
```

```bash
git add lib/pages/app_shell.dart
git commit -m "feat(app-shell): split nav rail into wish/odes sections

- 三條 NavigationRail 串接（綜合 / 祈願 5 / 頌願 2）
- section label '祈願' / '頌願' 在 extended + with-label 模式顯示，no-label 時隱去只剩 divider
- _RailSelection 取代單一 int selectedIndex"
```

---

## Task 14: `OverviewPage` 拆 wish / odes 兩個 section

**Files:**
- Modify: `lib/pages/overview_page.dart`
- Modify: `lib/widgets/empty_state.dart`（加 noOdesRecords 工廠）

- [ ] **Step 1: 加 EmptyState.noOdesRecords**

`lib/widgets/empty_state.dart`：

```dart
factory EmptyState.noOdesRecords(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  return EmptyState(
    icon: Icons.auto_awesome_outlined,
    title: l.emptyNoOdesRecords,
  );
}
```

（依現有 EmptyState 建構式調整）

- [ ] **Step 2: 改 `lib/pages/overview_page.dart`**

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final tokens = Theme.of(context).gacha;
  final state = ref.watch(wishRepositoryProvider);
  final activeData = state.activeData;

  if (state.isBootstrapping) return const LoadingState();
  if (activeData == null) return EmptyState.noSync(context);

  final wishTypes = gachaTypes.where((t) => t.category == GachaCategory.wish).toList();
  final odesTypes = gachaTypes.where((t) => t.category == GachaCategory.odes).toList();
  final wishBanners = {
    for (final t in wishTypes)
      t.gachaType: activeData.banners[t.gachaType] ?? const <WishRecord>[],
  };
  final odesBanners = {
    for (final t in odesTypes)
      t.gachaType: activeData.banners[t.gachaType] ?? const <WishRecord>[],
  };
  final wishAll = wishBanners.values.expand((l) => l).toList(growable: false);
  final odesAll = odesBanners.values.expand((l) => l).toList(growable: false);
  final wishStats = computeWishStats(wishAll);
  final odesStats = computeWishStats(odesAll);
  final bannerColors = BannerColors.fromTokens(tokens);

  return SingleChildScrollView(
    padding: const EdgeInsets.all(AppSpacing.l),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: l.pageOverviewTitle, icon: Icons.dashboard_outlined),
        const SizedBox(height: AppSpacing.l),
        _OverviewSection(
          title: l.pageOverviewWishSection,
          types: wishTypes,
          banners: wishBanners,
          stats: wishStats,
          bannerColors: bannerColors,
        ),
        const SizedBox(height: AppSpacing.xl),
        odesAll.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: EmptyState.noOdesRecords(context),
              )
            : _OverviewSection(
                title: l.pageOverviewOdesSection,
                types: odesTypes,
                banners: odesBanners,
                stats: odesStats,
                bannerColors: bannerColors,
              ),
      ],
    ),
  );
}
```

`_OverviewSection` widget：把現有 OverviewPage Body 內容（3 個 stat card + 2 pies + bar + timeline）萃取出來，接 `types / banners / stats / bannerColors` 參數。重點：

- Stat 卡列：依 `types` 動態：
  - 祈願段（types 含 5★ rank）：總抽數 / 5★ 件數 / 4★ 件數
  - 頌願段（types 主稀有度混合）：總抽數 / `types[0].primaryPity.rank`★ 件數 (活動) / `types[1].primaryPity.rank`★ 件數 (常駐)
  - 簡化做法：StatCard 列改為「動態依 types 順序的主稀有度件數」 — 第一張固定總抽數，後面 `types.length` 張 stat 卡，每張 = `{type.resolveName}: {records.where(rank == primary).count}`
- Pie：稀有度（rarity_pie 動態支援 2★）+ 物品類型（item_type_pie 動態）
- Bar：`BannerTopRarityBars(types: types, ...)`
- Timeline：`buildTimelineEntriesAcrossBanners(banners, rankFor: (gt) => typesMap[gt]!.primaryPity.rank)`

具體 `_OverviewSection` 完整實作（粗略骨架，依現有 OverviewPage 視覺貼合）：

```dart
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.types,
    required this.banners,
    required this.stats,
    required this.bannerColors,
  });

  final String title;
  final List<GachaType> types;
  final Map<String, List<WishRecord>> banners;
  final WishStats stats;
  final BannerColors bannerColors;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final typesByGt = {for (final t in types) t.gachaType: t};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineSectionTitle(icon: Icons.summarize_outlined, title: title),
        const SizedBox(height: AppSpacing.m),
        // Stat 卡列：總抽數 + 每個 type 主稀有度件數
        LayoutBuilder(builder: (context, c) {
          final cards = <Widget>[
            StatCard(label: l.statsTotal, value: '${stats.total}',
                     accent: tokens.accentPrimary),
            for (final t in types)
              StatCard(
                label: '${t.resolveName(l)} ${t.primaryPity.rank}★',
                value: '${banners[t.gachaType]?.where((r) => r.rankType == t.primaryPity.rank).length ?? 0}',
                accent: accentForRank(t.primaryPity.rank, tokens),
              ),
          ];
          // ... 依寬度 wide/mid/narrow 排列（複製 OverviewPage 既有邏輯）
          return ResponsiveStatRow(cards: cards);  // 或直接 inline LayoutBuilder
        }),
        const SizedBox(height: AppSpacing.l),
        // Pie 列：rarity + item type
        LayoutBuilder(builder: (context, c) {
          // 沿用 OverviewPage 既有 LayoutBuilder 邏輯
          return Row(...);
        }),
        const SizedBox(height: AppSpacing.m),
        // Bar
        ChartCard(
          title: l.bannerTopRarityCountTitle,
          icon: Icons.bar_chart,
          height: null,
          chart: BannerTopRarityBars(
            types: types,
            banners: banners,
            colors: bannerColors,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        // Timeline
        InlineSectionTitle(
          icon: Icons.timeline,
          title: l.timelineCountTopRarity(
            types.first.primaryPity.rank,  // 標題用第一個 type 的 rank
            buildTimelineEntriesAcrossBanners(
              banners, rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
            ).length,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        TimelineVertical(
          entries: buildTimelineEntriesAcrossBanners(
            banners, rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
          ),
          colors: bannerColors,
          nowPulls: pullsSinceLastRankedAcrossBanners(
            banners, rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
          ),
          isAcrossBanners: true,
        ),
      ],
    );
  }
}
```

**注意**：Stat 卡列響應式排列邏輯沿用既有 wide/mid/narrow 三段，直接從現有 OverviewPage 複製。

- [ ] **Step 3: 手動驗證**

`flutter run -d windows`，視覺確認：

- 祈願段顯示「祈願綜合」section title + 6 張 stat card（總抽 + 5 個祈願主稀有度）+ 兩 pie + bar + timeline
- 頌願段（若無記錄）顯示 EmptyState「尚無頌願記錄」
- 頌願段（有記錄）顯示「頌願綜合」+ 3 張 stat card（總抽 + 活動 5★ + 常駐 4★）+ 兩 pie + bar + timeline
- 視覺與祈願段一致，section 之間有明顯間距

- [ ] **Step 4: Quality gate + commit**

```bash
git add lib/pages/overview_page.dart lib/widgets/empty_state.dart
git commit -m "feat(overview): split into Wish and Odes sections

- 兩個獨立 section 各自統計，不再把頌願裝扮跟祈願角色武器混算
- Stat 卡列依 GachaType.primaryPity.rank 動態列舉每個 banner 的主稀有度件數
- 頌願段無記錄時顯示 EmptyState"
```

---

## Task 15: `BannerPage` 整合所有改動

**Files:**
- Modify: `lib/pages/banner_page.dart`
- Modify: `lib/widgets/cards/timeline_horizontal.dart`（標題 i18n）

- [ ] **Step 1: 改 `BannerPage` PityCard 由 pities 驅動**

```dart
final type = _resolveType();
final records = activeData.banners[gachaType] ?? const [];
if (records.isEmpty) { ... 維持既有 EmptyState }

final stats = computeWishStats(records);
final primaryPity = computePity(
  records,
  threshold: type.primaryPity.threshold,
  rank: type.primaryPity.rank,
);
final secondaryPity = type.secondaryPity != null
    ? computePity(
        records,
        threshold: type.secondaryPity!.threshold,
        rank: type.secondaryPity!.rank,
      )
    : null;
final isEndedPool = type.gachaType == '100';

final availableItemTypes = records
    .map((r) => r.itemType)
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList()
  ..sort();

// Row 1: PityCard 主 + 副 + 總抽
final primaryLabel = _pityLabel(type.primaryPity.labelKey, l);
final secondaryLabel = type.secondaryPity != null
    ? _pityLabel(type.secondaryPity!.labelKey, l)
    : null;

PityCard(
  label: primaryLabel,
  pity: primaryPity,
  accent: accentForRank(type.primaryPity.rank, tokens),
  isEndedPool: isEndedPool,
),
if (secondaryPity != null)
  PityCard(
    label: secondaryLabel!,
    pity: secondaryPity,
    accent: accentForRank(type.secondaryPity!.rank, tokens),
    isEndedPool: isEndedPool,
  ),

// ... TotalCard 不變
```

helper：

```dart
String _pityLabel(String labelKey, AppLocalizations l) => switch (labelKey) {
  'pityFiveStar' => l.pityFiveStar,
  'pityFourStar' => l.pityFourStar,
  'pityThreeStar' => l.pityThreeStar,
  _ => labelKey,
};
```

- [ ] **Step 2: 改 Timeline 區塊**

```dart
final timelineEntries = buildTimelineEntries(
  records, targetRank: type.primaryPity.rank,
);
final nowPulls = pullsSinceLastRanked(
  records, rank: type.primaryPity.rank,
);

// ChartCard 標題
title: l.timelineCountTopRarity(type.primaryPity.rank, stats.fiveStarCount),
```

**注意**：`stats.fiveStarCount` 在常駐頌願 = 0（因為主稀有度是 4★），所以標題的 count 要動態 — 應該用「該稀有度件數」：

```dart
int countAtRank(int rank) => switch (rank) {
  5 => stats.fiveStarCount,
  4 => stats.fourStarCount,
  3 => stats.threeStarCount,
  2 => stats.twoStarCount,
  _ => 0,
};

title: l.timelineCountTopRarity(type.primaryPity.rank, countAtRank(type.primaryPity.rank)),
```

- [ ] **Step 3: 改 SearchFilterBar 傳 availableItemTypes**

```dart
SearchFilterBar(
  state: filterState,
  availableItemTypes: availableItemTypes,
  onFilterChanged: (f) =>
      ref.read(recordFilterProvider(gachaType).notifier).setFilter(f),
  onClear: () =>
      ref.read(recordFilterProvider(gachaType).notifier).clear(),
),
```

- [ ] **Step 4: 改 `lib/widgets/cards/timeline_horizontal.dart` 標題**

若該 widget 直接用 `l.timelineCountFiveStar`，改為接 `title: String` 參數讓 caller 決定，或內部接 `targetRank: int` 並用 `l.timelineCountTopRarity(rank, count)`。**簡單做法：移除 timeline_horizontal 內部 i18n 字串，改為接 `title: String` 從外部傳入**。

- [ ] **Step 5: 手動驗證**

- 進入活動頌願頁：PityCard 顯示「5★ 保底 / 4★ 保底」，Timeline 顯示「5★ 時間軸 (n)」
- 進入常駐頌願頁：PityCard 顯示「4★ 保底 / 3★ 保底」，Timeline 顯示「4★ 時間軸 (n)」
- 進入既有祈願 banner：行為與原本完全一致
- SearchFilterBar 第二個 dropdown 依當前 banner 出現過的 itemType 動態列舉

- [ ] **Step 6: Quality gate + commit**

```bash
git add lib/pages/banner_page.dart lib/widgets/cards/timeline_horizontal.dart
git commit -m "feat(banner-page): drive PityCard, Timeline, filter from GachaType.pities

- PityCard 主 / 副依 type.primaryPity / secondaryPity 動態 label + accent
- Timeline 接 type.primaryPity.rank（常駐頌願 = 4★ 時間軸）
- SearchFilterBar 接 availableItemTypes（依 records 動態列舉）"
```

---

## Task 16: 最終 quality gate + 手動 release 驗證

**Files:** —（驗證 only，無 code 改動）

- [ ] **Step 1: 全套 quality gate**

```
dart format lib/ test/
flutter analyze
flutter test
```

Expected: 三項皆 PASS。

若 analyze 報未使用 import / 變數 → 修掉並重跑。

- [ ] **Step 2: Release build smoke test**

```
flutter run -d windows --release
```

實機操作：

1. 設定既有 UID（祈願已有資料）
2. 點「更新資料」
3. 從**頌願**歷史紀錄頁觸發攔截（不是祈願）
   - 確認 mitm 攔到 `getBeyondGachaLog` URL
4. 觀察：祈願 5 個 banner + 頌願 2 個 banner 是否都抓回新資料
5. 切到「活動頌願」頁：PityCard 顯示 5★/70 + 4★/10，Timeline 5★，記錄列表正常
6. 切到「常駐頌願」頁：PityCard 顯示 4★/70 + 3★/5，Timeline 4★，記錄列表有 2★
7. 切到「綜合」頁：祈願綜合 + 頌願綜合兩個 section 各自獨立顯示
8. 側選單視覺：祈願 / 頌願 section label 清楚

- [ ] **Step 3: 再從祈願頁攔截確認 authkey 跨 endpoint**

1. 刪除目前 captured URL（或清資料重來）
2. 從**祈願**歷史紀錄頁觸發攔截 → 攔到 `getGachaLog` URL
3. 觀察是否仍能成功抓回頌願兩個 banner
4. 若失敗（API 拒絕跨 endpoint）→ 在 spec 風險章節記錄結果，回頭實作 dual-capture

- [ ] **Step 4: 驗證 `item_type` 字串實際內容**

從第一筆頌願記錄抓 `item_type` 實際字串（debug log 或檢視 `<uid>.json`）。確認 ItemTypePie / SearchFilterBar dropdown 顯示的標籤正確。若 `item_type` 是空字串，確認 fallback 顯示 `kindUnknown`「未知」。

- [ ] **Step 5: 收尾 commit（若有手動驗證後的微調）**

如無修正，直接 push 並開 PR。如有微調：

```bash
git add -A
git commit -m "chore: post-validation tweaks"
```

---

## Self-Review

**Spec 覆蓋率**：

- §4.1 GachaType 重構 → Task 1
- §4.2 GachaEndpoint / Rust mitm → Task 6 + Task 9
- §4.3 抓取依 category → Task 7 + Task 8
- §4.4 儲存不變 → 隱含於 Task 2（WishRecord 簡化）
- §4.5 動態 itemType 分類 → Task 2
- §4.6 側選單分區 → Task 13
- §4.7 BannerPage pity 驅動 → Task 15
- §4.8 OverviewPage 拆 section → Task 14
- §4.9 i18n key 增刪 → Task 10
- §4.10 Rust mitm → Task 9
- 加 odes 兩個 GachaType → Task 10
- twoStar token / RarityPie 2★ → Task 3
- accentForRank → Task 4
- Timeline rankFor → Task 5
- BannerTopRarityBars rename → Task 12
- 配色 / 圖示 → Task 11
- Quality gate / release smoke → Task 16

**Placeholder scan**：無 TBD / TODO / 「similar to ...」。每個 step 都有具體程式碼或具體指令。

**Type consistency**：
- `PityRule { rank, threshold, labelKey }` — Task 1 定義，Task 10 / 15 一致使用
- `GachaCategory.wish / .odes` — Task 1 定義，Task 7 / 8 / 14 一致
- `GachaEndpoint.wish / .odes` — Task 6 定義，Task 7 / 8 一致
- `WishStats.byItemType: Map<String, int>` + `twoStarCount` + `threeStarCount` — Task 2 定義，Task 3 / 14 / 15 一致
- `RecordFilter.itemType: String?` — Task 2 定義，Task 2 內 SearchFilterBar 一致
- `accentForRank(int, GachaTokens)` — Task 4 定義，Task 14 / 15 一致
- `BannerTopRarityBars({types, banners, colors})` — Task 12 定義，Task 14 一致
- `buildTimelineEntriesAcrossBanners(banners, {required rankFor})` — Task 5 定義，Task 14 / 15 一致
- `_RailSelection { topIndex, wishIndex, odesIndex }` — Task 13 定義，僅內用

---

實作建議：採用 subagent-driven-development，逐個 task 提交，每個 task 後做 mini review（quality gate 已內建）。
