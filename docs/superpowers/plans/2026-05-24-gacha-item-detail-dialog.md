# Gacha Item Detail Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 點擊物品 icon / 名稱時彈出 dialog,上方顯示 icon + 名稱、下方顯示 HoyoWiki header 大圖;同時清理本分支殘留的 `Wish*` 命名為 `Gacha*`。

**Architecture:** 兩階段 commit。Phase 1 純機械 rename(本分支殘留 `Wish*` → `Gacha*`),Phase 2 新增 `lib/widgets/dialogs/gacha_item_detail_dialog.dart`(含 `hasHoyoWikiContent` / `GachaItemTapTarget` / `showGachaItemDetailDialog` / `GachaItemDetailDialog` 四個成員),並在三處顯示點(`SortableTable`、`TimelineVertical`、`TimelineHorizontal`)用 `GachaItemTapTarget` 包裝既有 icon + 名稱區塊。Dialog 寬度套 `AppDialogSize.md`,header 用 `Flexible(loose) + BoxFit.contain` 吃剩餘高度,保證不撐爆視窗、不滾動。

**Tech Stack:** Flutter 3.x、Riverpod、`AppDialog`(`lib/widgets/dialogs/app_dialog.dart`)、`logging` package、既有 `HoyoWikiIndex` + `hoyowikiCacheFile`。

---

## File Structure

### 新檔
- `lib/widgets/dialogs/gacha_item_detail_dialog.dart` — 含 `hasHoyoWikiContent`、`GachaItemTapTarget`、`showGachaItemDetailDialog`、`GachaItemDetailDialog`
- `test/widgets/dialogs/gacha_item_detail_dialog_test.dart` — 對應測試

### Rename(`git mv`)
- `lib/widgets/wish_item_icon.dart` → `lib/widgets/gacha_item_icon.dart`
- `test/widgets/wish_item_icon_test.dart` → `test/widgets/gacha_item_icon_test.dart`

### 修改(`Wish*` 殘留)
- `lib/widgets/data/sortable_table.dart` — import + `WishItemIcon` use site
- `lib/widgets/cards/timeline_vertical.dart` — import + use site
- `lib/widgets/cards/timeline_horizontal.dart` — import + use site
- `lib/widgets/share/share_image_helper.dart:52` — 註解 `[WishItemIcon]` doc ref
- `lib/services/hoyowiki_fetcher.dart:53-54` — 註解 + Logger 名
- `lib/services/hoyowiki_index.dart:67` — Logger 名
- `lib/state/hoyowiki_index.dart:37` — Logger 名
- `lib/widgets/share/preloaded_hoyowiki_images.dart:10` — Logger 名
- `lib/state/gacha_repository.dart:646-652` — local const + 註解
- `test/widgets/cards/timeline_horizontal_test.dart` — use site + 描述字串
- `test/widgets/cards/timeline_vertical_test.dart` — use site + 描述字串
- `test/widgets/data/sortable_table_test.dart` — use site + 描述字串
- `lib/widgets/gacha_item_icon.dart`(rename 後)— `WishItemIcon` 改 `GachaItemIcon`、註解 doc ref 改
- `test/widgets/gacha_item_icon_test.dart`(rename 後)— import path、`WishItemIcon` ref、temp dir prefix

### Dialog 階段修改
- `lib/widgets/data/sortable_table.dart` — name 欄包 `GachaItemTapTarget`
- `lib/widgets/cards/timeline_vertical.dart` — Row 包 `GachaItemTapTarget`
- `lib/widgets/cards/timeline_horizontal.dart` — icon + name 區塊包 `GachaItemTapTarget`

---

## Phase 1 — 前置 rename(`Wish*` → `Gacha*`)

### Task 1: 重新命名檔案並改 `gacha_item_icon.dart` 內容

**Files:**
- Rename: `lib/widgets/wish_item_icon.dart` → `lib/widgets/gacha_item_icon.dart`
- Rename: `test/widgets/wish_item_icon_test.dart` → `test/widgets/gacha_item_icon_test.dart`
- Modify: `lib/widgets/gacha_item_icon.dart`(rename 後)

- [ ] **Step 1: `git mv` 兩個檔案**

```bash
git mv lib/widgets/wish_item_icon.dart lib/widgets/gacha_item_icon.dart
git mv test/widgets/wish_item_icon_test.dart test/widgets/gacha_item_icon_test.dart
```

Expected: 兩行命令成功,`git status` 顯示 `renamed:`。

- [ ] **Step 2: 修改 `lib/widgets/gacha_item_icon.dart`**

在新檔內把 `WishItemIcon` 改 `GachaItemIcon`(class 宣告 + dartdoc),其餘邏輯零變動。

```dart
// line 13-16 區
/// 顯示一筆祈願物品的 icon；cache 未到 / 缺資料時顯示 [_Placeholder]。
class GachaItemIcon extends ConsumerWidget {
  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({super.key, required this.record, required this.size});
```

dartdoc 內「祈願物品」改「卡池物品」:

```dart
/// 顯示一筆卡池物品的 icon；cache 未到 / 缺資料時顯示 [_Placeholder]。
class GachaItemIcon extends ConsumerWidget {
  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({super.key, required this.record, required this.size});
```

- [ ] **Step 3: 不要 commit,留待 Task 5 統一 verify 後一次 commit**

---

### Task 2: 改 use site(三個 widget 檔)

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart:9, 391`
- Modify: `lib/widgets/cards/timeline_vertical.dart:8, 408`
- Modify: `lib/widgets/cards/timeline_horizontal.dart:10, 304`

- [ ] **Step 1: `lib/widgets/data/sortable_table.dart`**

第 9 行 import:
```dart
// 舊
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
// 新
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
```

第 391 行 use site:
```dart
// 舊
WishItemIcon(record: record, size: 32),
// 新
GachaItemIcon(record: record, size: 32),
```

- [ ] **Step 2: `lib/widgets/cards/timeline_vertical.dart`**

第 8 行 import:
```dart
// 舊
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
// 新
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
```

第 408 行:
```dart
// 舊
WishItemIcon(record: entry.sourceRecord!, size: 32),
// 新
GachaItemIcon(record: entry.sourceRecord!, size: 32),
```

- [ ] **Step 3: `lib/widgets/cards/timeline_horizontal.dart`**

第 10 行 import:
```dart
// 舊
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
// 新
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
```

第 304 行:
```dart
// 舊
WishItemIcon(record: entry.sourceRecord!, size: 32),
// 新
GachaItemIcon(record: entry.sourceRecord!, size: 32),
```

- [ ] **Step 4: 不要 commit,繼續下一個 task**

---

### Task 3: 改 Logger + local const + 註解(5 個檔)

**Files:**
- Modify: `lib/services/hoyowiki_fetcher.dart:53-54`
- Modify: `lib/services/hoyowiki_index.dart:67`
- Modify: `lib/state/hoyowiki_index.dart:37`
- Modify: `lib/widgets/share/preloaded_hoyowiki_images.dart:10`
- Modify: `lib/state/gacha_repository.dart:646, 648, 652`
- Modify: `lib/widgets/share/share_image_helper.dart:52`

- [ ] **Step 1: `lib/services/hoyowiki_fetcher.dart`**

第 53-54 行(註解 + Logger):
```dart
// 舊
  /// Logger 實例（wish.hoyowiki 命名空間，對齊既有 `gacha.fetcher`）。
  static final _log = Logger('wish.hoyowiki');
// 新
  /// Logger 實例（gacha.hoyowiki 命名空間，對齊既有 `gacha.fetcher`）。
  static final _log = Logger('gacha.hoyowiki');
```

- [ ] **Step 2: `lib/services/hoyowiki_index.dart`**

第 67 行:
```dart
// 舊
  static final _log = Logger('wish.hoyowiki.storage');
// 新
  static final _log = Logger('gacha.hoyowiki.storage');
```

- [ ] **Step 3: `lib/state/hoyowiki_index.dart`**

第 37 行:
```dart
// 舊
  static final _log = Logger('wish.hoyowiki.notifier');
// 新
  static final _log = Logger('gacha.hoyowiki.notifier');
```

- [ ] **Step 4: `lib/widgets/share/preloaded_hoyowiki_images.dart`**

第 10 行:
```dart
// 舊
final _log = Logger('wish.hoyowiki.preload');
// 新
final _log = Logger('gacha.hoyowiki.preload');
```

- [ ] **Step 5: `lib/state/gacha_repository.dart`**

第 646-652 行:
```dart
// 舊
    const wishGachaTypes = {'301', '302', '500', '200', '100'};

    // 收集所有 UID 全部祈願 record 的 unique (name, lang)
    final uniquePairs = <(String name, String lang)>{};
    for (final data in state.byUid.values) {
      for (final entry in data.banners.entries) {
        if (!wishGachaTypes.contains(entry.key)) continue;
// 新
    const hoyoWikiTargetGachaTypes = {'301', '302', '500', '200', '100'};

    // 收集所有 UID 全部卡池 record 的 unique (name, lang)
    final uniquePairs = <(String name, String lang)>{};
    for (final data in state.byUid.values) {
      for (final entry in data.banners.entries) {
        if (!hoyoWikiTargetGachaTypes.contains(entry.key)) continue;
```

- [ ] **Step 6: `lib/widgets/share/share_image_helper.dart`**

第 52 行(註解內 doc reference):
```dart
// 舊
/// 解析而導致畫面空白。
///
/// [container] 為 Riverpod ProviderContainer；離屏 pipeline 是獨立樹，需透過
/// [UncontrolledProviderScope] 顯式傳入，否則 tree 內 [ConsumerWidget]（如
/// [WishItemIcon]）無法查到 providers。生產端從呼叫 Widget 的 ref 取得，
// 新
/// 解析而導致畫面空白。
///
/// [container] 為 Riverpod ProviderContainer；離屏 pipeline 是獨立樹，需透過
/// [UncontrolledProviderScope] 顯式傳入，否則 tree 內 [ConsumerWidget]（如
/// [GachaItemIcon]）無法查到 providers。生產端從呼叫 Widget 的 ref 取得，
```

- [ ] **Step 7: 不要 commit,繼續下一個 task**

---

### Task 4: 改 test 內容(4 個 test 檔)

**Files:**
- Modify: `test/widgets/gacha_item_icon_test.dart`(Task 1 rename 過)
- Modify: `test/widgets/cards/timeline_horizontal_test.dart`
- Modify: `test/widgets/cards/timeline_vertical_test.dart`
- Modify: `test/widgets/data/sortable_table_test.dart`

- [ ] **Step 1: `test/widgets/gacha_item_icon_test.dart`**

第 12 行 import:
```dart
// 舊
import 'package:genshin_impact_wish_gacha_analyzer/widgets/wish_item_icon.dart';
// 新
import 'package:genshin_impact_wish_gacha_analyzer/widgets/gacha_item_icon.dart';
```

第 43 行 temp dir prefix:
```dart
// 舊
tempDir = await Directory.systemTemp.createTemp('wish_item_icon_test_');
// 新
tempDir = await Directory.systemTemp.createTemp('gacha_item_icon_test_');
```

全檔 `WishItemIcon` → `GachaItemIcon`(用 `replace_all` 替換),包含 `find.byType(WishItemIcon)` 與 widget 建構式。

- [ ] **Step 2: `test/widgets/cards/timeline_horizontal_test.dart`**

第 375 行 test 標題:
```dart
// 舊
testWidgets('每欄名稱上方顯示 WishItemIcon', (tester) async {
// 新
testWidgets('每欄名稱上方顯示 GachaItemIcon', (tester) async {
```

第 450 行 use site:
```dart
// 舊
expect(find.byType(WishItemIcon), findsNWidgets(entries.length));
// 新
expect(find.byType(GachaItemIcon), findsNWidgets(entries.length));
```

import:該檔若有直接 import `wish_item_icon.dart`,同步改 `gacha_item_icon.dart`(用 grep 確認)。

- [ ] **Step 3: `test/widgets/cards/timeline_vertical_test.dart`**

第 593 行:
```dart
// 舊
testWidgets('每筆 entry 名稱前顯示 WishItemIcon', (tester) async {
// 新
testWidgets('每筆 entry 名稱前顯示 GachaItemIcon', (tester) async {
```

第 667 行:
```dart
// 舊
expect(find.byType(WishItemIcon), findsNWidgets(entries.length));
// 新
expect(find.byType(GachaItemIcon), findsNWidgets(entries.length));
```

import 同前。

- [ ] **Step 4: `test/widgets/data/sortable_table_test.dart`**

第 205 行:
```dart
// 舊
testWidgets('每列名稱欄前顯示 WishItemIcon', (tester) async {
// 新
testWidgets('每列名稱欄前顯示 GachaItemIcon', (tester) async {
```

第 224 行(註解):
```dart
// 舊
// 三筆 record → 三個 WishItemIcon
// 新
// 三筆 record → 三個 GachaItemIcon
```

第 225 行:
```dart
// 舊
expect(find.byType(WishItemIcon), findsNWidgets(3));
// 新
expect(find.byType(GachaItemIcon), findsNWidgets(3));
```

import 同前。

- [ ] **Step 5: 不要 commit,進入 verify task**

---

### Task 5: Verify(format + analyze + test + grep)+ Commit 1

**Files:** 無修改(僅執行檢查)

- [ ] **Step 1: dart format**

Run:
```powershell
dart format lib/ test/
```

Expected: 列出有 format 變動的檔案;若 0 個變動 OK。**不要對 `.` 跑(會動 `rust_builder/`)**。

- [ ] **Step 2: flutter analyze**

Run:
```powershell
flutter analyze
```

Expected output 結尾必須是 `No issues found!`。若有 issue,先修(常見:漏改的 import / 漏改的引用)。

- [ ] **Step 3: flutter test**

Run:
```powershell
flutter test
```

Expected output 結尾必須是 `All tests passed!`。所有既有測試應該 zero regression(rename 不改邏輯)。

- [ ] **Step 4: Grep 殘留檢查**

Run:
```powershell
git grep -nE '[Ww]ish' lib/ test/
```

Expected: 殘留只能落在白名單:
- `lib/data/app_repo.dart`、`lib/data/contributors.dart`、`test/pages/contributors_page_test.dart` 內的 `genshin-impact-wish-gacha-analyzer` repo URL
- 任何檔內的 `package:genshin_impact_wish_gacha_analyzer/...` import 行
- arb 檔內顯示文字值(本 phase 不應改到 arb,跑 `git status` 確認 arb 未動)
- arb 對應 generated 檔(`lib/l10n/generated/`)— 本 phase 不應改到

若有其他殘留,回去修(常見:某個 use site 漏改)。

- [ ] **Step 5: Commit 1**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(naming): rename residual Wish→Gacha in hoyowiki branch

對齊 2026-05-18 wish→gacha 中立化規則,清理本分支 (feat/hoyowiki-item-icon)
殘留的 Wish 命名:
- WishItemIcon → GachaItemIcon (含檔名 git mv)
- Logger wish.hoyowiki.* → gacha.hoyowiki.*
- wishGachaTypes → hoyoWikiTargetGachaTypes
- 註解/dartdoc 「祈願」→「卡池」

純 rename,無行為變更。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit 成功,`git log -1` 顯示新 commit。

---

## Phase 2 — Dialog 實作

### Task 6: `hasHoyoWikiContent` 判定函式(TDD)

**Files:**
- Create: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`
- Create: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`

- [ ] **Step 1: 寫第一批 failing test(判定矩陣)**

建立 `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';

GachaRecord _rec({
  required String name,
  required String gachaType,
  String lang = 'en-us',
  int rankType = 5,
}) => GachaRecord(
  id: '1',
  uid: '801057625',
  gachaType: gachaType,
  name: name,
  itemType: 'Character',
  rankType: rankType,
  time: DateTime(2026, 5, 24),
  lang: lang,
);

/// 在 [dir] 內建立一個指定路徑的假圖檔(內容隨意,僅供 existsSync 命中)。
Future<File> _touchFile(Directory dir, String relative) async {
  final f = File('${dir.path}/$relative');
  await f.create(recursive: true);
  await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47]); // PNG magic, 4 bytes
  return f;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gacha_item_detail_test_');
    container = ProviderContainer(
      overrides: [
        hoyowikiIndexStorageProvider.overrideWithValue(
          HoyoWikiIndexStorage(tempDir),
        ),
        hoyowikiCacheDirProvider.overrideWithValue(tempDir),
      ],
    );
    addTearDown(container.dispose);
    await container.read(hoyowikiIndexProvider.notifier).waitForLoad();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 把 hasHoyoWikiContent 包成 widget context 內可呼叫的 helper。
  Future<bool> _check(WidgetTester tester, GachaRecord r) async {
    bool? out;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            out = hasHoyoWikiContent(ref, r);
            return const SizedBox();
          },
        ),
      ),
    );
    return out!;
  }

  group('hasHoyoWikiContent', () {
    testWidgets('gachaType 2000 (頌願) → false', (tester) async {
      expect(
        await _check(tester, _rec(name: 'Ode', gachaType: '2000')),
        isFalse,
      );
    });

    testWidgets('gachaType 1000 (頌願) → false', (tester) async {
      expect(
        await _check(tester, _rec(name: 'Ode', gachaType: '1000')),
        isFalse,
      );
    });

    testWidgets('lookup miss → false', (tester) async {
      expect(
        await _check(tester, _rec(name: 'Unknown', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('entry 兩 URL 都空 → false', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(
        name: 'X', lang: 'en-us', id: 'x1', menuId: 2,
      );
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: '', headerImgUrl: '', fetchedAt: DateTime.now(),
        ),
      );
      expect(
        await _check(tester, _rec(name: 'X', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('URL 存在但 cache file 未到 → false', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(
        name: 'X', lang: 'en-us', id: 'x1', menuId: 2,
      );
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      expect(
        await _check(tester, _rec(name: 'X', gachaType: '301')),
        isFalse,
      );
    });

    testWidgets('只 icon file 存在 → true', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(
        name: 'X', lang: 'en-us', id: 'x1', menuId: 2,
      );
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: '',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');
      expect(
        await _check(tester, _rec(name: 'X', gachaType: '301')),
        isTrue,
      );
    });

    testWidgets('只 header file 存在 → true', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(
        name: 'X', lang: 'en-us', id: 'x1', menuId: 2,
      );
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: '',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_header.png');
      expect(
        await _check(tester, _rec(name: 'X', gachaType: '301')),
        isTrue,
      );
    });

    testWidgets('兩者都存在 → true', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(
        name: 'X', lang: 'en-us', id: 'x1', menuId: 2,
      );
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');
      await _touchFile(tempDir, 'x1_header.png');
      expect(
        await _check(tester, _rec(name: 'X', gachaType: '301')),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: 編譯失敗 — `Undefined name 'hasHoyoWikiContent'`(因為 `gacha_item_detail_dialog.dart` 不存在)。

- [ ] **Step 3: 建立 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` 並寫 `hasHoyoWikiContent` 最小實作**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';

/// 頌願卡池 gachaType 集合 — 永遠不可點(對應 GachaItemIcon 內 _odesGachaTypes)。
const _odesGachaTypes = {'2000', '1000'};

/// 判斷 [record] 是否在 dialog 內有東西可顯示(至少有 icon 或 header 任一個
/// HoyoWiki 圖片快取到本機)。頌願卡池一律 false。
bool hasHoyoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);

  bool fileReady(String url, HoyoWikiImageKind kind) =>
      url.isNotEmpty &&
      hoyowikiCacheFile(baseDir: cacheDir, id: id, kind: kind, url: url)
          .existsSync();

  return fileReady(entry.iconUrl, HoyoWikiImageKind.icon) ||
      fileReady(entry.headerImgUrl, HoyoWikiImageKind.header);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: `All tests passed!`(8 個 case 全綠)。

- [ ] **Step 5: 不要 commit,繼續下一個 task(待 Dialog 全部完成統一 commit 2)**

---

### Task 7: `GachaItemDetailDialog` widget(TDD)

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`(新增 `GachaItemDetailDialog`)
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`(新增 dialog 渲染測試)

- [ ] **Step 1: 加 4 個 failing test(dialog 渲染矩陣 + 不溢出)**

在現有 `gacha_item_detail_dialog_test.dart` 的 `main()` 最底部、`group('hasHoyoWikiContent', ...)` 之後加新 group:

```dart
  Future<void> _pumpDialog(
    WidgetTester tester,
    GachaRecord record,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      showDialog<void>(
        context: navigatorState.context,
        builder: (_) => GachaItemDetailDialog(record: record),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('GachaItemDetailDialog 渲染', () {
    testWidgets('兩圖齊全 → title row 有 icon Image.file + name,content 有 header Image.file', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');
      await _touchFile(tempDir, 'x1_header.png');

      await _pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('只 icon → 整個 dialog 只有一個 Image', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: '',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');

      await _pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('只 header → 只有 header Image,沒有 icon Image', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: '',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_header.png');

      await _pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('小視窗 (640x480) 不會 vertical overflow', (tester) async {
      tester.view.physicalSize = const Size(640, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: 'https://cdn.hoyolab.com/x_header.png',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');
      await _touchFile(tempDir, 'x1_header.png');

      await _pumpDialog(tester, _rec(name: 'X', gachaType: '301'));

      expect(tester.takeException(), isNull);
    });
  });
```

頂部 import 加:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
```

(把 `package:flutter/widgets.dart` 換成 `material.dart`,既有 `Consumer` 屬於 riverpod 可保留 widgets,但 `Scaffold` / `MaterialApp` / `Image` 需要 material。)

- [ ] **Step 2: Run test to verify they fail**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart -p chrome --reporter expanded
```

(若無 chrome 跳過 `-p chrome` 用預設 VM)

Expected: 編譯失敗 — `Undefined name 'GachaItemDetailDialog'`。

- [ ] **Step 3: 在 `lib/widgets/dialogs/gacha_item_detail_dialog.dart` 加 `GachaItemDetailDialog`**

在檔案底部追加(`hasHoyoWikiContent` 之下):

```dart
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 點擊物品 icon / 名稱時彈出的 dialog;顯示 icon + 名稱(top)+ HoyoWiki
/// header 大圖(bottom)。缺哪個就不顯示哪個;`AppDialogSize.md` 寬度,
/// header 用 `Flexible + BoxFit.contain` 吃剩餘高度,保證不撐爆視窗。
class GachaItemDetailDialog extends ConsumerWidget {
  /// 建立 [GachaItemDetailDialog]。
  const GachaItemDetailDialog({super.key, required this.record});

  /// 要顯示的卡池 record。
  final GachaRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);

    File? iconFile;
    File? headerFile;
    if (id != null && entry != null) {
      if (entry.iconUrl.isNotEmpty) {
        final f = hoyowikiCacheFile(
          baseDir: cacheDir,
          id: id,
          kind: HoyoWikiImageKind.icon,
          url: entry.iconUrl,
        );
        if (f.existsSync()) iconFile = f;
      }
      if (entry.headerImgUrl.isNotEmpty) {
        final f = hoyowikiCacheFile(
          baseDir: cacheDir,
          id: id,
          kind: HoyoWikiImageKind.header,
          url: entry.headerImgUrl,
        );
        if (f.existsSync()) headerFile = f;
      }
    }

    final nameColor = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textPrimary,
    };

    return AppDialog(
      size: AppDialogSize.md,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (iconFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(
                iconFile,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, e, st) {
                  Logger('gacha.hoyowiki.detail')
                      .warning('icon errorBuilder id=$id', e, st);
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              record.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: nameColor,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerFile != null)
            Flexible(
              fit: FlexFit.loose,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  headerFile,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, e, st) {
                    Logger('gacha.hoyowiki.detail')
                        .warning('header errorBuilder id=$id', e, st);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}
```

檔案頂部 import 補:
```dart
import 'dart:io';

import 'package:logging/logging.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: `All tests passed!`(12 個 case 全綠:8 + 4 新增)。

注意:`Image.file` 在 Flutter 測試環境讀 4 bytes PNG 可能會走 `errorBuilder`(因為不是有效 PNG),但 `find.byType(Image)` 仍會命中。若測試 `findsNWidgets(2)` 失敗,改為 `find.descendant(of: find.byType(GachaItemDetailDialog), matching: find.byType(Image))` 並再次驗證 — 我們找的是 widget tree 內的 `Image`,不是渲染結果。

若仍 fail,將 `_touchFile` 寫入的 bytes 換成最小有效 PNG(8-byte signature + 最小 IHDR/IEND chunk),改成:
```dart
await f.writeAsBytes([
  // PNG signature
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  // 後續 chunks 省略 — Image widget 樹建立只看 path,不解碼
]);
```

實際上 Flutter `Image.file` 是 lazy decode,widget tree 內仍會存在 `Image`,測試應該過。

- [ ] **Step 5: 不要 commit,繼續下一個 task**

---

### Task 8: `showGachaItemDetailDialog` helper + `GachaItemTapTarget`(TDD)

**Files:**
- Modify: `lib/widgets/dialogs/gacha_item_detail_dialog.dart`(新增 helper + tap target)
- Modify: `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`(新增 tap 行為測試)

- [ ] **Step 1: 加 failing test(tap 行為)**

在 test 檔加新 group:

```dart
  group('GachaItemTapTarget', () {
    testWidgets('clickable record → 點下去 dialog 出現', (tester) async {
      final notifier = container.read(hoyowikiIndexProvider.notifier);
      await notifier.setSearch(name: 'X', lang: 'en-us', id: 'x1', menuId: 2);
      await notifier.setEntry(
        id: 'x1',
        entry: HoyoWikiEntry(
          iconUrl: 'https://cdn.hoyolab.com/x_icon.png',
          headerImgUrl: '',
          fetchedAt: DateTime.now(),
        ),
      );
      await _touchFile(tempDir, 'x1_icon.png');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'X', gachaType: '301'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GachaItemDetailDialog), findsNothing);
      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsOneWidget);
    });

    testWidgets('頌願 → 點下去不出 dialog,passthrough 無 MouseRegion click cursor', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'Ode', gachaType: '2000'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      // passthrough:整個 tap target 內找不到 cursor=click 的 MouseRegion
      final mouseRegions = tester.widgetList<MouseRegion>(
        find.descendant(
          of: find.byType(GachaItemTapTarget),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(
        mouseRegions.any((m) => m.cursor == SystemMouseCursors.click),
        isFalse,
      );

      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsNothing);
    });

    testWidgets('lookup miss → passthrough,點下去不出 dialog', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: GachaItemTapTarget(
                record: _rec(name: 'Unknown', gachaType: '301'),
                child: const Text('tap-me'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap-me'));
      await tester.pumpAndSettle();
      expect(find.byType(GachaItemDetailDialog), findsNothing);
    });
  });
```

- [ ] **Step 2: Run test to verify they fail**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: 編譯失敗 — `Undefined name 'GachaItemTapTarget'`。

- [ ] **Step 3: 在 `gacha_item_detail_dialog.dart` 加 `showGachaItemDetailDialog` 與 `GachaItemTapTarget`**

在 `GachaItemDetailDialog` class 下方追加:

```dart
/// 顯示 [GachaItemDetailDialog]。集中 log 與 [showDialog] 呼叫。
Future<void> showGachaItemDetailDialog(
  BuildContext context,
  GachaRecord record,
) {
  Logger('gacha.hoyowiki.detail').info(
    'open name=${record.name} lang=${record.lang} rank=${record.rankType}',
  );
  return showDialog<void>(
    context: context,
    builder: (_) => GachaItemDetailDialog(record: record),
  );
}

/// 把任意 [child](通常是 icon + 名稱 Row/Column)包成可點區塊;
/// [hasHoyoWikiContent] 為 false 時 passthrough,不加任何 hit affordance。
class GachaItemTapTarget extends ConsumerWidget {
  /// 建立 [GachaItemTapTarget]。
  const GachaItemTapTarget({
    super.key,
    required this.record,
    required this.child,
  });

  /// 對應的卡池 record;由 [hasHoyoWikiContent] 判定可點性。
  final GachaRecord record;

  /// 被包裝的子 widget(icon + 名稱組合)。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasHoyoWikiContent(ref, record)) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showGachaItemDetailDialog(context, record),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```powershell
flutter test test/widgets/dialogs/gacha_item_detail_dialog_test.dart
```

Expected: `All tests passed!`(15 個 case 全綠)。

- [ ] **Step 5: 不要 commit,繼續下一個 task**

---

### Task 9: 三處 call site 套用 `GachaItemTapTarget`

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart:9, 388-403`
- Modify: `lib/widgets/cards/timeline_vertical.dart:8, 402-425`
- Modify: `lib/widgets/cards/timeline_horizontal.dart:10, 302-320`

- [ ] **Step 1: `lib/widgets/data/sortable_table.dart`**

加 import:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
```

第 387-403 行(name 欄)改為:
```dart
Expanded(
  flex: 5,
  child: GachaItemTapTarget(
    record: record,
    child: Row(
      children: [
        GachaItemIcon(record: record, size: 32),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            record.name,
            style: highlight,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  ),
),
```

- [ ] **Step 2: `lib/widgets/cards/timeline_vertical.dart`**

加 import:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
```

第 397-425 行(名稱 Tooltip + Row),把現有 `Tooltip > Row` 改成 `Tooltip > GachaItemTapTarget > Row`:

```dart
Tooltip(
  message: entry.name,
  preferBelow: false,
  waitDuration: const Duration(milliseconds: 100),
  child: GachaItemTapTarget(
    record: entry.sourceRecord!,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (entry.sourceRecord != null) ...[
          GachaItemIcon(record: entry.sourceRecord!, size: 32),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            entry.name,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  ),
),
```

注意:既有 `_EntryRow` 內 `entry.sourceRecord` 可能為 null(舊資料),但 `GachaItemTapTarget` 要求 non-null record。`entry.sourceRecord` 為 null 時不包,維持原本結構。把上面那塊改成:

```dart
final tappable = entry.sourceRecord != null;
Widget nameRow = Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    if (entry.sourceRecord != null) ...[
      GachaItemIcon(record: entry.sourceRecord!, size: 32),
      const SizedBox(width: 6),
    ],
    Flexible(
      child: Text(
        entry.name,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
);
if (tappable) {
  nameRow = GachaItemTapTarget(record: entry.sourceRecord!, child: nameRow);
}
return Tooltip(
  message: entry.name,
  preferBelow: false,
  waitDuration: const Duration(milliseconds: 100),
  child: nameRow,
);
```

(此 inline 變數寫法不會破壞既有 `Column > [Tooltip, ..., Tooltip]` 結構,只調整中間那個 Tooltip 的 child。)

- [ ] **Step 3: `lib/widgets/cards/timeline_horizontal.dart`**

加 import:
```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gacha_item_detail_dialog.dart';
```

第 300-320 行(`_EntryColumn.build` 內 Column children),把 `if (entry.sourceRecord != null) ...[icon, sb, ]` + `Text(entry.name, ...)` 重組為:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    if (entry.sourceRecord != null)
      GachaItemTapTarget(
        record: entry.sourceRecord!,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GachaItemIcon(record: entry.sourceRecord!, size: 32),
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      )
    else
      Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    const SizedBox(height: AppSpacing.xs),
    _Node(color: accent, tokens: tokens),
    const SizedBox(height: AppSpacing.xs),
    Text(
      '${_formatShortDate(entry.time)} · ${l.timelineSinceLast(entry.pullsSincePrev)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: 10,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  ],
),
```

- [ ] **Step 4: 不要 commit,進入 verify task**

---

### Task 10: Verify + Tooltip 回歸測試 + Commit 2

**Files:** 無修改(僅執行檢查 + 視需要補 smoke test)

- [ ] **Step 1: dart format**

Run:
```powershell
dart format lib/ test/
```

- [ ] **Step 2: flutter analyze**

Run:
```powershell
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: flutter test**

Run:
```powershell
flutter test
```

Expected: `All tests passed!`

特別注意 `timeline_vertical_test.dart` / `timeline_horizontal_test.dart` / `sortable_table_test.dart` 是否有新增 widget 結構導致 layout 改變;若 fail,讀錯誤訊息修正既有 expect。

- [ ] **Step 4: 手動 smoke(可選但建議)**

```powershell
flutter run -d windows
```

點擊 `SortableTable` 表格內 5 星名稱列、`TimelineVertical` / `TimelineHorizontal` 內 5 星節點旁名稱,確認:
1. Dialog 彈出
2. 上方有 icon(48px)+ 名稱(稀有度色)
3. 下方有 header(若該角色有 header)
4. 「關閉」鈕能關
5. 視窗縮到 640×480 仍不滾動、不溢出

若該 record 是頌願(`gachaType` 1000/2000),確認名稱不可點(cursor 不變)。

- [ ] **Step 5: Commit 2**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(hoyowiki): add GachaItemDetailDialog with icon+name+header

點擊 SortableTable / Timeline 內物品 icon 或名稱時彈出 dialog,
上方顯示 icon + 名稱、下方顯示 HoyoWiki header 大圖。
- AppDialogSize.md (640) + Flexible(loose) + BoxFit.contain,
  保證圖片不溢出視窗、不滾動
- 缺 icon 或 header 任一個就不顯示該項;頌願卡池一律不可點
- GachaItemTapTarget 包裝既有 icon+名稱結構,不破壞 Tooltip

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: commit 成功。

---

## Self-Review Notes

**Spec coverage**:
- ✅ Rename 清單 12 項 → Task 1-4 涵蓋
- ✅ `hasHoyoWikiContent` → Task 6
- ✅ `GachaItemDetailDialog` → Task 7
- ✅ `showGachaItemDetailDialog` helper → Task 8
- ✅ `GachaItemTapTarget` → Task 8
- ✅ 三 call site 改造 → Task 9
- ✅ 圖片不溢出測試 → Task 7 第 4 個 case
- ✅ commit 切分 2 個 → Task 5、Task 10

**待實作期間決定項目已 nail down**:
- ✅ close i18n key:用既有 `l.actionClose`(已驗證存在於所有 arb)
- ✅ name style:`theme.textTheme.headlineSmall.copyWith(color: rarityColor, fontWeight: bold)`
- ✅ header `ClipRRect` 圓角:`AppRadius.md` (10)
- ✅ icon `ClipRRect` 圓角:`AppRadius.sm` (6)
- ✅ 3 星色:`tokens.textPrimary`

**Type consistency**:
- 所有 task `GachaItemIcon` / `GachaItemTapTarget` / `GachaItemDetailDialog` / `showGachaItemDetailDialog` / `hasHoyoWikiContent` 拼字一致
- Logger 命名一律 `gacha.hoyowiki.*`
- `hoyoWikiTargetGachaTypes` const 命名與 spec 一致
