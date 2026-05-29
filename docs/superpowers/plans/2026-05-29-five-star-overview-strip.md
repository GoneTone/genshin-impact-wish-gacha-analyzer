# 五星一覽（橫向圓形 Icon 列）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在所有非頌願卡池頁、綜合數據頁祈願段、以及卡池／綜合分享圖最尾端，新增「五星一覽」區塊：去重後每個五星物品一個圓形 Icon，右下角金色徽章標示累計抽到次數。

**Architecture:** 一個純函式 service（`five_star_collection.dart`）把 records 聚合成「不重複五星清單（代表 record + 次數）」，以 HoYoWiki id 為合併鍵（缺則名稱）支援跨語系合併；一個 widget（`FiveStarOverview` + `_FiveStarChip`）以 `Wrap` 呈現，重用既有 `GachaItemIcon`（擴充圓形模式）；banner_page／overview_page／share_card 三處接線。

**Tech Stack:** Flutter、Riverpod、Dart、flutter gen-l10n（ARB）。測試用 `flutter_test`。

參考 spec：`docs/superpowers/specs/2026-05-29-five-star-overview-strip-design.md`

---

## 檔案結構

- **Create** `lib/services/five_star_collection.dart` — `FiveStarCollectionItem` + `buildFiveStarCollection` + `buildFiveStarCollectionAcrossBanners`。
- **Create** `test/services/five_star_collection_test.dart` — 聚合／排序／跨卡池／跨語系／fallback 單元測試。
- **Create** `lib/widgets/cards/five_star_overview.dart` — `FiveStarOverview` + 私有 `_FiveStarChip`。
- **Create** `test/widgets/cards/five_star_overview_test.dart` — widget 測試。
- **Modify** `lib/widgets/gacha_item_icon.dart` — 加 `circular` 參數（圓形模式）。
- **Modify** `test/widgets/gacha_item_icon_test.dart`（不存在則 Create）— 圓形 placeholder 測試。
- **Modify** `lib/l10n/app_zh.arb`（template）+ 已翻譯 ARB（`app_zh_Hans` / `app_en` / `app_es` / `app_fr` / `app_ja` / `app_pt_BR` / `app_th` / `app_vi`）— 新增 `fiveStarOverviewTitle`。
- **Modify** `lib/pages/banner_page.dart` — 記錄列表上方插入五星一覽區塊 + 分享圖 factory 傳 index。
- **Modify** `lib/pages/overview_page.dart` — 祈願段時間軸上方插入五星一覽 + 分享圖 factory 傳 index。
- **Modify** `lib/widgets/share/share_card.dart` — factory 加 `index` 參數、build 尾端加五星一覽區塊。
- **Modify** `test/services/share_image_renderer_test.dart` 或新增 share 測試 — 驗證分享圖含五星一覽。

---

## Task 1: 五星聚合 service

**Files:**
- Create: `lib/services/five_star_collection.dart`
- Test: `test/services/five_star_collection_test.dart`

- [ ] **Step 1: 寫失敗測試**

Create `test/services/five_star_collection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

GachaRecord _r({
  required String id,
  required int rank,
  required DateTime time,
  String gachaType = '301',
  String name = 'x',
  String lang = 'zh-tw',
}) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: gachaType,
  name: name,
  itemType: '角色',
  rankType: rank,
  time: time,
  lang: lang,
);

void main() {
  const emptyIndex = HoYoWikiIndex.empty();

  group('buildFiveStarCollection', () {
    test('empty records → empty list', () {
      expect(buildFiveStarCollection(const [], index: emptyIndex), isEmpty);
    });

    test('只取 5★，排除 4★／3★', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 4, name: 'B', time: DateTime(2025, 1, 2)),
        _r(id: '3', rank: 3, name: 'C', time: DateTime(2025, 1, 3)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(1));
      expect(result.single.representative.name, 'A');
      expect(result.single.count, 1);
    });

    test('同名去重計數，代表 record 取最近一次', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 5, name: 'A', time: DateTime(2025, 3, 1)),
        _r(id: '3', rank: 5, name: 'A', time: DateTime(2025, 2, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(1));
      expect(result.single.count, 3);
      expect(result.single.representative.id, '2'); // 2025-03-01 最近
    });

    test('排序：次數降冪，同次數以最近時間降冪', () {
      final records = [
        _r(id: 'a1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: 'a2', rank: 5, name: 'A', time: DateTime(2025, 1, 2)),
        _r(id: 'b1', rank: 5, name: 'B', time: DateTime(2025, 5, 1)),
        _r(id: 'c1', rank: 5, name: 'C', time: DateTime(2025, 4, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      // A=2 → 最前；B/C 各 1，B(5/1) 比 C(4/1) 新 → B 在 C 前
      expect(result.map((e) => e.representative.name).toList(), ['A', 'B', 'C']);
    });

    test('跨語系：同 id 不同語系名稱合併為一', () {
      const index = HoYoWikiIndex(
        searchMap: {'zh-tw::雷電將軍': '10000052', 'en::Raiden Shogun': '10000052'},
        entries: {},
        menuIds: {},
      );
      final records = [
        _r(id: '1', rank: 5, name: '雷電將軍', lang: 'zh-tw', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 5, name: 'Raiden Shogun', lang: 'en', time: DateTime(2025, 2, 1)),
      ];
      final result = buildFiveStarCollection(records, index: index);
      expect(result, hasLength(1));
      expect(result.single.count, 2);
      expect(result.single.representative.lang, 'en'); // 最近一筆
    });

    test('fallback：index lookup miss 時以名稱為鍵，不誤併不同物', () {
      final records = [
        _r(id: '1', rank: 5, name: 'A', time: DateTime(2025, 1, 1)),
        _r(id: '2', rank: 5, name: 'B', time: DateTime(2025, 2, 1)),
      ];
      final result = buildFiveStarCollection(records, index: emptyIndex);
      expect(result, hasLength(2));
    });
  });

  group('buildFiveStarCollectionAcrossBanners', () {
    test('同物品跨卡池合併、次數相加', () {
      const index = HoYoWikiIndex(
        searchMap: {'zh-tw::琴': '10000003'},
        entries: {},
        menuIds: {},
      );
      final banners = {
        '301': [
          _r(id: 'c1', rank: 5, name: '琴', time: DateTime(2025, 1, 1)),
        ],
        '200': [
          _r(id: 's1', rank: 5, name: '琴', gachaType: '200', time: DateTime(2025, 3, 1)),
          _r(id: 's2', rank: 5, name: '琴', gachaType: '200', time: DateTime(2025, 2, 1)),
        ],
      };
      final result = buildFiveStarCollectionAcrossBanners(banners, index: index);
      expect(result, hasLength(1));
      expect(result.single.count, 3);
      expect(result.single.representative.id, 's1'); // 2025-03-01 最近
    });

    test('empty banners → empty list', () {
      expect(
        buildFiveStarCollectionAcrossBanners(const {}, index: emptyIndex),
        isEmpty,
      );
    });
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/services/five_star_collection_test.dart`
Expected: FAIL（`five_star_collection.dart` 不存在，編譯錯誤）。

- [ ] **Step 3: 寫最小實作**

Create `lib/services/five_star_collection.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';

/// 五星一覽聚合的 logger。
final _log = Logger('wish.fiveStar');

/// 五星一覽的單一條目：一個不重複的五星物品 + 其累計抽到次數。
@immutable
class FiveStarCollectionItem {
  /// 建立 [FiveStarCollectionItem]。
  const FiveStarCollectionItem({
    required this.representative,
    required this.count,
  });

  /// 該物品最近一次被抽到的紀錄；決定 icon 查找與 tooltip 顯示名稱。
  final GachaRecord representative;

  /// 該物品（同合併鍵）在來源中被抽到的總次數。
  final int count;
}

/// 內部累積桶：記住該合併鍵目前的代表 record（最近一次）與出現次數。
class _Bucket {
  /// 以首次遇到的 record 初始化，count 由呼叫端累加。
  _Bucket(this.representative) : count = 0;

  /// 目前該合併鍵最近一次的 record。
  GachaRecord representative;

  /// 出現次數。
  int count;
}

/// 計算合併鍵：優先用 HoYoWiki id（可跨語系合併），lookup miss 時退化以名稱為鍵。
String _mergeKey(GachaRecord r, HoYoWikiIndex index) =>
    index.lookupId(name: r.name, lang: r.lang) ?? r.name;

/// 由單一 records 來源建構五星一覽：取 5★，依合併鍵去重計數，
/// 依「次數降冪 → 最近抽到時間降冪」排序。
List<FiveStarCollectionItem> buildFiveStarCollection(
  List<GachaRecord> records, {
  required HoYoWikiIndex index,
}) {
  final buckets = <String, _Bucket>{};
  for (final r in records) {
    if (r.rankType != 5) continue;
    final b = buckets.putIfAbsent(_mergeKey(r, index), () => _Bucket(r));
    b.count++;
    if (r.time.isAfter(b.representative.time)) {
      b.representative = r;
    }
  }
  final items = buckets.values
      .map(
        (b) => FiveStarCollectionItem(
          representative: b.representative,
          count: b.count,
        ),
      )
      .toList();
  items.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return b.representative.time.compareTo(a.representative.time);
  });
  _log.info('buildFiveStarCollection: ${items.length} unique five-star item(s)');
  return items;
}

/// 跨卡池版：攤平所有卡池 records 後委派給 [buildFiveStarCollection]，
/// 同合併鍵跨卡池累加。
List<FiveStarCollectionItem> buildFiveStarCollectionAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required HoYoWikiIndex index,
}) {
  final all = banners.values.expand((r) => r).toList(growable: false);
  return buildFiveStarCollection(all, index: index);
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/services/five_star_collection_test.dart`
Expected: PASS（全部綠）。

- [ ] **Step 5: Commit**

```bash
git add lib/services/five_star_collection.dart test/services/five_star_collection_test.dart
git commit -m "feat(wish): add five-star collection aggregation service"
```

---

## Task 2: `GachaItemIcon` 圓形模式

**Files:**
- Modify: `lib/widgets/gacha_item_icon.dart`
- Test: `test/widgets/gacha_item_icon_test.dart`（新建）

- [ ] **Step 1: 寫失敗測試**

Create `test/widgets/gacha_item_icon_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

GachaRecord _record() => GachaRecord(
  id: '1',
  uid: '1',
  gachaType: '301',
  name: '夜蘭',
  itemType: '角色',
  rankType: 5,
  time: DateTime(2025, 1, 1),
  lang: 'zh-tw',
);

void main() {
  testWidgets('circular=true → placeholder 用圓形 BoxShape.circle', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('gacha_icon_test_');
    });
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: Scaffold(
            body: GachaItemIcon(record: _record(), size: 48, circular: true),
          ),
        ),
      ),
    );
    await tester.pump();

    final deco = tester
        .widget<Container>(
          find.descendant(
            of: find.byType(GachaItemIcon),
            matching: find.byType(Container),
          ),
        )
        .decoration as BoxDecoration;
    expect(deco.shape, BoxShape.circle);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/widgets/gacha_item_icon_test.dart`
Expected: FAIL（`circular` 具名參數不存在，編譯錯誤）。

- [ ] **Step 3: 寫最小實作**

Modify `lib/widgets/gacha_item_icon.dart`：

3a. 建構子加 `circular` 參數（`GachaItemIcon` class 內，`size` 後）：

```dart
  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({
    super.key,
    required this.record,
    required this.size,
    this.circular = false,
  });

  /// 卡池記錄；用其 name / lang / rankType / gachaType。
  final GachaRecord record;

  /// icon 邊長（px，依使用情境調整：所有宿主一律 32）。
  final double size;

  /// true 時以圓形裁切／圓形 placeholder 呈現（五星一覽用）。
  final bool circular;
```

3b. 在 `build` 內新增私有 helper（放在 `build` 方法上方，class 內）：

```dart
  /// 依 [circular] 將 icon 圖片裁成圓形或 4px 圓角方塊。
  Widget _clipIcon(Widget child) => circular
      ? ClipOval(child: child)
      : ClipRRect(borderRadius: BorderRadius.circular(4), child: child);
```

3c. 把 build 內兩處 `ClipRRect(borderRadius: BorderRadius.circular(4), child: ...)` 改用 `_clipIcon(...)`：

preloaded 路徑：

```dart
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(RawImage(image: preloadedImage, fit: BoxFit.cover)),
        );
```

file 路徑：

```dart
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(Image.file(file, fit: BoxFit.cover)),
        );
```

3d. placeholder 傳入 circular：

```dart
    return _Placeholder(
      rankType: record.rankType,
      size: size,
      tokens: tokens,
      circular: circular,
    );
```

3e. `_Placeholder` 加 `circular` 欄位並套用 shape：

```dart
class _Placeholder extends StatelessWidget {
  /// 建立 [_Placeholder]。
  const _Placeholder({
    required this.rankType,
    required this.size,
    required this.tokens,
    this.circular = false,
  });

  /// 星級（3 / 4 / 5）；決定強調色。
  final int rankType;

  /// 方塊邊長（px）。
  final double size;

  /// 主題 token；提供稀有度顏色。
  final GachaTokens tokens;

  /// true 時以圓形呈現。
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final accent = switch (rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textMuted,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(Icons.question_mark, size: size * 0.55, color: accent),
      ),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/widgets/gacha_item_icon_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/gacha_item_icon.dart test/widgets/gacha_item_icon_test.dart
git commit -m "feat(wish): add circular mode to GachaItemIcon"
```

---

## Task 3: `FiveStarOverview` widget

**Files:**
- Create: `lib/widgets/cards/five_star_overview.dart`
- Test: `test/widgets/cards/five_star_overview_test.dart`

- [ ] **Step 1: 寫失敗測試**

Create `test/widgets/cards/five_star_overview_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';

GachaRecord _r(String id, String name, DateTime time) => GachaRecord(
  id: id,
  uid: '1',
  gachaType: '301',
  name: name,
  itemType: '角色',
  rankType: 5,
  time: time,
  lang: 'zh-tw',
);

Future<ProviderContainer> _container(WidgetTester tester) async {
  late Directory tempDir;
  await tester.runAsync(() async {
    tempDir = await Directory.systemTemp.createTemp('five_star_overview_test_');
  });
  addTearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });
  final container = ProviderContainer(
    overrides: [
      hoyowikiIndexStorageProvider.overrideWithValue(
        HoYoWikiIndexStorage(tempDir),
      ),
      hoyowikiCacheDirProvider.overrideWithValue(tempDir),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(
    () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
  );
  return container;
}

Widget _wrap(ProviderContainer c, Widget child) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: buildDarkTheme(),
    home: Scaffold(body: SizedBox(width: 800, child: child)),
  ),
);

void main() {
  const emptyIndex = HoYoWikiIndex.empty();

  testWidgets('空清單 → SizedBox.shrink，不顯示任何 chip', (tester) async {
    final c = await _container(tester);
    await tester.pumpWidget(_wrap(c, const FiveStarOverview(items: [])));
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsNothing);
    expect(find.textContaining('×'), findsNothing);
  });

  testWidgets('顯示每個物品的次數徽章', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
      _r('2', 'A', DateTime(2025, 1, 2)),
      _r('3', 'B', DateTime(2025, 1, 3)),
    ], index: emptyIndex);
    await tester.pumpWidget(_wrap(c, FiveStarOverview(items: items)));
    await tester.pump();
    expect(find.text('2'), findsOneWidget); // A 抽到 2 次
    expect(find.text('1'), findsOneWidget); // B 抽到 1 次
  });

  testWidgets('interactive=false → 不掛 GachaItemTapTarget', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    await tester.pumpWidget(
      _wrap(c, FiveStarOverview(items: items, interactive: false)),
    );
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsNothing);
  });

  testWidgets('interactive=true → 掛 GachaItemTapTarget', (tester) async {
    final c = await _container(tester);
    final items = buildFiveStarCollection([
      _r('1', 'A', DateTime(2025, 1, 1)),
    ], index: emptyIndex);
    await tester.pumpWidget(_wrap(c, FiveStarOverview(items: items)));
    await tester.pump();
    expect(find.byType(GachaItemTapTarget), findsOneWidget);
  });
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/widgets/cards/five_star_overview_test.dart`
Expected: FAIL（`five_star_overview.dart` 不存在）。

- [ ] **Step 3: 寫最小實作**

Create `lib/widgets/cards/five_star_overview.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';

/// 圓形 icon 邊長。
const double _iconSize = 48;

/// 金色外環寬度。
const double _ringWidth = 2;

/// 徽章高度（直徑）。
const double _badgeSize = 19;

/// 五星一覽：把不重複五星物品以橫向 [Wrap] 排列，每個 chip 為圓形 icon +
/// 金色外環 + 右下角累計次數徽章。一行排滿自動換行、不限行數。空清單不顯示。
class FiveStarOverview extends StatelessWidget {
  /// 建立 [FiveStarOverview]。
  const FiveStarOverview({
    super.key,
    required this.items,
    this.interactive = true,
  });

  /// 聚合後的五星清單（已排序）。
  final List<FiveStarCollectionItem> items;

  /// true 時 chip 可點開詳情並顯示 tooltip；分享圖（靜態圖）傳 false。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        for (final item in items)
          _FiveStarChip(item: item, interactive: interactive),
      ],
    );
  }
}

/// 單一五星 chip：圓形 icon + 金環 + 右下角次數徽章；[interactive] 時可點 / hover。
class _FiveStarChip extends StatelessWidget {
  /// 建立 [_FiveStarChip]。
  const _FiveStarChip({required this.item, required this.interactive});

  /// 對應的五星條目。
  final FiveStarCollectionItem item;

  /// 是否可互動。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final gold = tokens.fiveStar;
    // 金底徽章上的文字：dark 主題金色偏亮用深字、light 主題金色偏暗用白字，
    // 兩個主題下都維持足夠對比。
    final onGold = theme.brightness == Brightness.dark
        ? tokens.surfaceBackground
        : Colors.white;

    final stack = SizedBox(
      width: _iconSize + _ringWidth * 2,
      height: _iconSize + _ringWidth * 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: _ringWidth),
              boxShadow: [
                BoxShadow(color: gold.withValues(alpha: 0.35), blurRadius: 6),
              ],
            ),
            child: GachaItemIcon(
              record: item.representative,
              size: _iconSize,
              circular: true,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: _badgeSize),
              height: _badgeSize,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(_badgeSize / 2),
                border: Border.all(color: tokens.surfaceCard, width: 2),
              ),
              child: Text(
                '${item.count}',
                style: TextStyle(
                  color: onGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!interactive) return stack;
    return Tooltip(
      message: item.representative.name,
      waitDuration: const Duration(milliseconds: 100),
      child: GachaItemTapTarget(record: item.representative, child: stack),
    );
  }
}
```

- [ ] **Step 4: 執行測試確認通過**

Run: `flutter test test/widgets/cards/five_star_overview_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/five_star_overview.dart test/widgets/cards/five_star_overview_test.dart
git commit -m "feat(wish): add FiveStarOverview widget"
```

---

## Task 4: i18n 字串 `fiveStarOverviewTitle`

**Files:**
- Modify: `lib/l10n/app_zh.arb`（template，含 @-metadata）
- Modify: `lib/l10n/app_zh_Hans.arb` / `app_en.arb` / `app_es.arb` / `app_fr.arb` / `app_ja.arb` / `app_pt_BR.arb` / `app_th.arb` / `app_vi.arb`

> 只動已有實體翻譯的 ARB；其餘語系空殼留給 Crowdin pipeline，不要碰。

- [ ] **Step 1: 在 template `app_zh.arb` 新增 key + metadata**

於 `lib/l10n/app_zh.arb` 既有 `pageBannerRecordList` 條目之後加入（若該檔已有對應 `@pageBannerRecordList` metadata，緊接其後）：

```json
  "fiveStarOverviewTitle": "五星一覽",
  "@fiveStarOverviewTitle": {
    "description": "Section title above the record list / timeline showing every unique five-star item the user pulled, each with a badge of how many copies were obtained."
  },
```

- [ ] **Step 2: 在各已翻譯 ARB 新增同 key（僅 key:value，無 metadata）**

於每個檔案的 `pageBannerRecordList` 條目之後加入對應翻譯：

- `app_zh_Hans.arb`: `"fiveStarOverviewTitle": "五星一览",`
- `app_en.arb`: `"fiveStarOverviewTitle": "5-Star Overview",`
- `app_es.arb`: `"fiveStarOverviewTitle": "Resumen de 5 estrellas",`
- `app_fr.arb`: `"fiveStarOverviewTitle": "Aperçu 5 étoiles",`
- `app_ja.arb`: `"fiveStarOverviewTitle": "星5一覧",`
- `app_pt_BR.arb`: `"fiveStarOverviewTitle": "Visão geral de 5 estrelas",`
- `app_th.arb`: `"fiveStarOverviewTitle": "ภาพรวม 5 ดาว",`
- `app_vi.arb`: `"fiveStarOverviewTitle": "Tổng quan 5 sao",`

> 注意 JSON 逗號：插在中間時上一行結尾與本行皆需正確逗號；勿在物件最後一個 key 後留多餘逗號。

- [ ] **Step 3: 重新產生 localizations**

Run: `flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 `String get fiveStarOverviewTitle`。

- [ ] **Step 4: 驗證 analyze 通過**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): add fiveStarOverviewTitle string"
```

---

## Task 5: banner_page 接線

**Files:**
- Modify: `lib/pages/banner_page.dart`

- [ ] **Step 1: 新增 import**

於 `lib/pages/banner_page.dart` import 區（依字母序插入適當位置）加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
```

- [ ] **Step 2: 計算五星清單**

在 `build` 內、`availableItemTypes` 計算之後（`return SingleChildScrollView` 之前）加入：

```dart
    final fiveStarItems = buildFiveStarCollection(
      records,
      index: ref.watch(hoyowikiIndexProvider),
    );
```

- [ ] **Step 3: 在記錄列表標題上方插入區塊**

把現有這段：

```dart
          const SizedBox(height: AppSpacing.xl),
          InlineSectionTitle(
            icon: Icons.table_chart_outlined,
            title: l.pageBannerRecordList,
          ),
```

改為：

```dart
          const SizedBox(height: AppSpacing.xl),
          if (fiveStarItems.isNotEmpty) ...[
            InlineSectionTitle(
              icon: Icons.star_outline,
              title: l.fiveStarOverviewTitle,
            ),
            const SizedBox(height: AppSpacing.s),
            FiveStarOverview(items: fiveStarItems),
            const SizedBox(height: AppSpacing.xl),
          ],
          InlineSectionTitle(
            icon: Icons.table_chart_outlined,
            title: l.pageBannerRecordList,
          ),
```

- [ ] **Step 4: 驗證 analyze 通過**

Run: `flutter analyze lib/pages/banner_page.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/pages/banner_page.dart
git commit -m "feat(wish): show five-star overview above banner record list"
```

---

## Task 6: overview_page 接線（僅祈願段）

**Files:**
- Modify: `lib/pages/overview_page.dart`

- [ ] **Step 1: 新增 import**

加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
```

- [ ] **Step 2: `_OverviewSection` 加參數**

於 `_OverviewSection` 建構子末尾加入具名參數（預設空 → odes 段不傳即不顯示）：

```dart
  const _OverviewSection({
    required this.title,
    required this.types,
    required this.banners,
    required this.stats,
    required this.bannerColors,
    required this.statCards,
    required this.emptyTitle,
    required this.timeline,
    required this.timelineNowPulls,
    required this.timelineRank,
    this.fiveStarItems = const [],
  });
```

並在欄位宣告區（`timelineRank` 欄位之後）加入：

```dart
  /// 此段的五星一覽清單；空清單時不顯示該區塊（odes 段一律空）。
  final List<FiveStarCollectionItem> fiveStarItems;
```

- [ ] **Step 3: 祈願段傳入聚合清單**

在 `OverviewPage.build` 內，gacha 段的 `_OverviewSection(...)` 呼叫加入 `fiveStarItems`：

```dart
          _OverviewSection(
            title: l.pageOverviewGachaSection,
            types: gachaSec.types,
            banners: gachaSec.banners,
            stats: gachaSec.stats,
            bannerColors: bannerColors,
            statCards: gachaStatCards,
            emptyTitle: l.emptyNoGachaRecords,
            timeline: gachaSec.timeline,
            timelineNowPulls: gachaSec.timelineNowPulls,
            timelineRank: gachaSec.timelineRank,
            fiveStarItems: buildFiveStarCollectionAcrossBanners(
              gachaSec.banners,
              index: ref.watch(hoyowikiIndexProvider),
            ),
          ),
```

odes 段的 `_OverviewSection(...)` **不加** `fiveStarItems`（維持預設空）。

- [ ] **Step 4: 在 timeline 標題上方插入區塊**

於 `_OverviewSection.build` 內，把現有這段：

```dart
        const SizedBox(height: AppSpacing.xl),
        InlineSectionTitle(
          icon: Icons.timeline,
          title: l.timelineTopRarityTitle(
            l.rarityStar(timelineRank),
            timeline.length,
          ),
        ),
```

改為：

```dart
        const SizedBox(height: AppSpacing.xl),
        if (fiveStarItems.isNotEmpty) ...[
          InlineSectionTitle(
            icon: Icons.star_outline,
            title: l.fiveStarOverviewTitle,
          ),
          const SizedBox(height: AppSpacing.s),
          FiveStarOverview(items: fiveStarItems),
          const SizedBox(height: AppSpacing.xl),
        ],
        InlineSectionTitle(
          icon: Icons.timeline,
          title: l.timelineTopRarityTitle(
            l.rarityStar(timelineRank),
            timeline.length,
          ),
        ),
```

- [ ] **Step 5: 驗證 analyze 通過**

Run: `flutter analyze lib/pages/overview_page.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/pages/overview_page.dart
git commit -m "feat(wish): show five-star overview in overview gacha section"
```

---

## Task 7: 分享圖接線（尾端五星一覽）

**Files:**
- Modify: `lib/widgets/share/share_card.dart`
- Modify: `lib/pages/banner_page.dart`（`_generateBannerShare` 傳 index）
- Modify: `lib/pages/overview_page.dart`（`_generateOverviewShare` 傳 index）
- Test: `test/widgets/cards/share_card_five_star_test.dart`（新建）

- [ ] **Step 1: 寫失敗測試**

Create `test/widgets/cards/share_card_five_star_test.dart`:

```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  testWidgets('banner 分享圖含 FiveStarOverview（含 5★ 時）', (tester) async {
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('share_five_star_test_');
    });
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    final container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoYoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(
      () => container.read(hoyowikiIndexProvider.notifier).waitForLoad(),
    );

    final icon = await tester.runAsync(_solidImage);
    addTearDown(() => icon!.dispose());

    final records = [
      GachaRecord(
        id: '1',
        uid: '100000001',
        gachaType: '301',
        name: '夜蘭',
        itemType: '角色',
        rankType: 5,
        time: DateTime(2025, 4, 1),
        lang: 'zh-tw',
      ),
    ];

    late AppLocalizations l;
    final card = Builder(
      builder: (ctx) {
        l = AppLocalizations.of(ctx)!;
        return ShareCard.banner(
          l: l,
          appVersion: '1.0.0',
          appIcon: icon!,
          options: const ShareImageOptions(
            brightness: Brightness.dark,
            showFullUid: true,
          ),
          uid: '100000001',
          updatedAt: DateTime(2025, 4, 1),
          title: 'Test',
          records: records,
          targetRank: 5,
          index: container.read(hoyowikiIndexProvider),
        );
      },
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreloadedHoYoWikiImages(
                images: const {},
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FiveStarOverview), findsOneWidget);
    expect(find.text(l.fiveStarOverviewTitle), findsOneWidget);
  });
}
```

> `ShareImageOptions` 建構子若參數名與此處不同，請依實際定義調整（`brightness` / `showFullUid`）。

- [ ] **Step 2: 執行測試確認失敗**

Run: `flutter test test/widgets/cards/share_card_five_star_test.dart`
Expected: FAIL（`ShareCard.banner` 無 `index` 具名參數，編譯錯誤）。

- [ ] **Step 3a: share_card.dart 新增 import**

於 `lib/widgets/share/share_card.dart` import 區加入：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/five_star_collection.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/five_star_overview.dart';
```

- [ ] **Step 3b: 私有建構子加欄位**

把 `ShareCard._({...})` 改為帶 `fiveStar`：

```dart
  const ShareCard._({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.options,
    required this.uid,
    required this.updatedAt,
    required List<_Section> sections,
    required List<FiveStarCollectionItem> fiveStar,
  }) : _sections = sections,
       _fiveStar = fiveStar;
```

並在欄位宣告區（`final List<_Section> _sections;` 之後）加入：

```dart
  /// 尾端五星一覽清單（banner = 該池；overview = 跨祈願卡池合併）。
  final List<FiveStarCollectionItem> _fiveStar;
```

- [ ] **Step 3c: `ShareCard.banner` factory 加 `index` 並算清單**

簽名加入 `required HoYoWikiIndex index,`（放 `targetRank` 之後）。`return ShareCard._(` 內加入：

```dart
      fiveStar: buildFiveStarCollection(records, index: index),
```

- [ ] **Step 3d: `ShareCard.overview` factory 加 `index` 並算清單**

簽名加入 `required HoYoWikiIndex index,`（放 `banners` 之後）。`return ShareCard._(` 內加入（`s` 即既有 `buildOverviewSections(banners)` 結果）：

```dart
      fiveStar: buildFiveStarCollectionAcrossBanners(s.gacha.banners, index: index),
```

- [ ] **Step 3e: build 尾端加入五星一覽區塊**

於 `build` 的 `content` Column，`for (...) ... _SectionView(...)` 迴圈結束後（`children: [` 的最後一個元素）加入：

```dart
        if (_fiveStar.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Divider(color: tokens.borderEmphasis, height: 1, thickness: 1),
          const SizedBox(height: AppSpacing.xl),
          Text(l.fiveStarOverviewTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.m),
          FiveStarOverview(items: _fiveStar, interactive: false),
        ],
```

- [ ] **Step 4: 更新呼叫端傳 index**

4a. `lib/pages/banner_page.dart` 的 `_generateBannerShare` 內 `ShareCard.banner(...)` 加入：

```dart
        targetRank: type.primaryPity.rank,
        index: ref.read(hoyowikiIndexProvider),
```

（`ShareCard.banner` 已在 `buildCard` callback 中，`ref` 為 `_generateBannerShare` 參數。）

4b. `lib/pages/overview_page.dart` 的 `_generateOverviewShare` 內 `ShareCard.overview(...)` 加入：

```dart
        banners: activeData.banners,
        index: ref.read(hoyowikiIndexProvider),
```

> 兩處 import（`state/hoyowiki_index.dart`）已於 Task 5 / 6 加入。

- [ ] **Step 5: 執行測試確認通過**

Run: `flutter test test/widgets/cards/share_card_five_star_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/share_card.dart lib/pages/banner_page.dart lib/pages/overview_page.dart test/widgets/cards/share_card_five_star_test.dart
git commit -m "feat(wish): append five-star overview to share image"
```

---

## Task 8: 全套品質檢查

**Files:** 無（驗證用）

- [ ] **Step 1: 格式化**

Run: `dart format lib/ test/`
Expected: 列出已格式化檔案；無錯誤。

- [ ] **Step 2: 靜態分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 視覺確認（手動）**

Run: `flutter run -d windows`（或既有 run 流程）
確認：
- 角色／武器等卡池頁、綜合頁祈願段「祈願記錄列表／時間軸」上方出現「五星一覽」圓形 icon 列，徽章次數正確、可點開詳情、hover 顯名。
- 頌願個別頁與綜合頁頌願段**無**此區塊。
- 卡池分享圖、綜合分享圖最尾端各有「五星一覽」。
- 無五星紀錄時整段隱藏。

- [ ] **Step 5: 最終 commit（若格式化有改動）**

```bash
git add -A
git commit -m "style: format five-star overview feature"
```

---

## Self-Review

**Spec coverage：**
- 去重 + 計數、恆顯示 → Task 1（聚合）+ Task 3（徽章恆顯示，無 count==1 隱藏邏輯）。✓
- 合併鍵 HoYoWiki id + name fallback → Task 1 `_mergeKey`，測試涵蓋跨語系與 miss fallback。✓
- 代表 record 取最近一次 → Task 1（`isAfter` 更新），測試涵蓋。✓
- 排序次數降冪 + 最近時間 tie-break → Task 1 sort，測試涵蓋。✓
- 跨卡池合併、次數相加 → Task 1 across-banners，測試涵蓋。✓
- 樣式 A（金環 + 圓形數字徽章、48px）→ Task 2 + Task 3。✓
- 圓形 icon 重用 GachaItemIcon → Task 2 擴充。✓
- 互動（點擊詳情 / tooltip）僅 App、分享圖靜態 → Task 3 `interactive`。✓
- 空清單隱藏 → Task 3 `SizedBox.shrink` + 各頁 `if (...isNotEmpty)`。✓
- banner_page 記錄列表上方 → Task 5。✓
- overview 祈願段時間軸上方、頌願不動 → Task 6（odes 不傳 `fiveStarItems`）。✓
- 分享圖尾端（卡池 = 該池、綜合 = 跨祈願卡池合併）→ Task 7。✓
- i18n `fiveStarOverviewTitle`、繁中起手、只翻已翻 ARB → Task 4。✓
- 埋 log（`wish.fiveStar`）→ Task 1。✓
- 測試（聚合/排序/跨卡池/跨語系/空、widget 徽章/排序/空/interactive、分享圖 smoke、ImageCache tearDown）→ Task 1/3/7（tempDir tearDown 已含；本功能 widget 測試用空 index 走 placeholder，不解碼圖檔，無 ImageCache race 風險）。✓

**Placeholder scan：** 無 TODO／TBD；所有 step 含實際程式碼或精確指令。

**Type consistency：** `FiveStarCollectionItem`（`representative` / `count`）、`buildFiveStarCollection(records, {index})`、`buildFiveStarCollectionAcrossBanners(banners, {index})`、`FiveStarOverview({items, interactive})`、`GachaItemIcon(..., circular)`、`ShareCard.banner(..., index)` / `ShareCard.overview(..., index)` 跨 Task 命名一致。
