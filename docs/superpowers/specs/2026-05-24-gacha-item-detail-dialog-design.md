# Gacha Item Detail Dialog — Design

**Date**: 2026-05-24
**Branch**: `feat/hoyowiki-item-icon`
**Status**: Approved (pending implementation plan)

## 背景

`feat/hoyowiki-item-icon` 已把 HoyoWiki item icon 接到三處顯示點(`SortableTable`、`TimelineVertical`、`TimelineHorizontal`),且 update pipeline 同步下載並快取 **icon 與 header 兩種圖片**(`HoyoWikiImageKind.icon` / `HoyoWikiImageKind.header`)。目前 header 圖片僅存於 cache,沒有任何介面消費。

本案在使用者點擊 item icon 或名稱時彈出 dialog,於上方顯示 icon + 名稱、下方顯示 header 圖,讓 header 快取派上用場。

同時順手清理本分支殘留的 `Wish*` 命名(2026-05-18 `wish-to-gacha-rename` 後新引入但未跟上中立化規則的部分),統一為 `Gacha*`。

## 範圍

**做**:
- 新增 `GachaItemDetailDialog` 並提供 `showGachaItemDetailDialog` helper
- 新增 `GachaItemTapTarget` 包裝元件,將 icon + 名稱整塊變為可點區
- 新增 `hasHoyoWikiContent` 判定函式
- 在三處 call site 套用 `GachaItemTapTarget`
- **前置 rename**:本分支殘留的 `Wish*` 識別子 / 檔名 / Logger / 註解一併改 `Gacha*`

**不做**:
- 不為頌願卡池(`gachaType` 2000 / 1000)做任何彈出行為
- 不顯示 placeholder/「icon 未取得」等補位元素(缺哪個就不顯示哪個)
- 不在 dialog 內顯示稀有度、類型等 metadata(只 icon + 名稱 + header)
- 不改動 `GachaItemIcon`(rename 自 `WishItemIcon`)的核心邏輯,維持純展示元件
- 不為 header 圖加入縮放/全螢幕檢視(本期 YAGNI)
- 不動 package 名 `genshin_impact_wish_gacha_analyzer`、repo URL `genshin-impact-wish-gacha-analyzer`、i18n 顯示字串值(沿用 2026-05-18 設計決策)

## 既決事項(已確認)

| 主題 | 決定 |
|---|---|
| 觸發範圍 | icon 與名稱整塊可點(同一 hit zone) |
| 頌願處理 | 不可點、不彈出 |
| 缺資料 fallback | icon 或 header 有任一個快取就可彈出;缺的那個直接不顯示(不用 placeholder 占位) |
| dialog 內容 | 只有 icon + 名稱 + header |
| header 顯示 | 原始寬高比,適應 dialog 寬度;不裁切 |
| dialog 尺寸 | `AppDialogSize.md` (640) |
| 圖片不溢出視窗 | header 用 `Flexible(loose) + BoxFit.contain` 吃剩餘高度,不開 `scrollable` |
| 共用元件 | 不抽 `GachaItemClickableRow`(三處 layout 差異大,違反 YAGNI) |
| tap 元件 | `GestureDetector` + `MouseRegion`(避免 InkWell splash 破壞既有低調風格) |
| 中立命名 | 本分支殘留 `Wish*` 一律改 `Gacha*`(`wishGachaTypes` → `hoyoWikiTargetGachaTypes`) |

## 前置 rename(`Wish*` → `Gacha*`)

對齊 `2026-05-18-wish-to-gacha-rename-design.md` 規則,清理本分支新引入的殘留。**先做 rename、再做 dialog**(降低 dialog 實作期間 import / 引用變化的雜訊)。

### Rename 清單

| 類別 | 舊 | 新 |
|---|---|---|
| Class | `WishItemIcon` | `GachaItemIcon` |
| Lib 檔(`git mv`) | `lib/widgets/wish_item_icon.dart` | `lib/widgets/gacha_item_icon.dart` |
| Test 檔(`git mv`) | `test/widgets/wish_item_icon_test.dart` | `test/widgets/gacha_item_icon_test.dart` |
| Logger 名稱 | `wish.hoyowiki` | `gacha.hoyowiki` |
| Logger 名稱 | `wish.hoyowiki.storage` | `gacha.hoyowiki.storage` |
| Logger 名稱 | `wish.hoyowiki.notifier` | `gacha.hoyowiki.notifier` |
| Logger 名稱 | `wish.hoyowiki.preload` | `gacha.hoyowiki.preload` |
| Local const | `wishGachaTypes`(`_fetchHoyoWiki` 內) | `hoyoWikiTargetGachaTypes` |
| Test temp dir prefix | `'wish_item_icon_test_'` | `'gacha_item_icon_test_'` |
| 註解 doc reference | `[WishItemIcon]`(`share_image_helper.dart:52`) | `[GachaItemIcon]` |
| 註解(`hoyowiki_fetcher.dart:53`) | 「Logger 實例(wish.hoyowiki 命名空間…」 | 「Logger 實例(gacha.hoyowiki 命名空間…」 |
| 註解(`gacha_repository.dart:648`) | 「收集所有 UID 全部祈願 record…」 | 「收集所有 UID 全部卡池 record…」 |
| Test 標題字串 | 「每欄名稱上方顯示 WishItemIcon」等 3 處 | 同步改 |
| use site(`timeline_horizontal.dart:304`, `timeline_vertical.dart:408`, `sortable_table.dart:391`) | `WishItemIcon(...)` | `GachaItemIcon(...)` |
| use site(三 widget test 內) | `WishItemIcon` | `GachaItemIcon` |

### 白名單(明確不動)

- repo URL `github.com/.../genshin-impact-wish-gacha-analyzer`(`app_repo.dart`、`contributors.dart`、`contributors_page_test.dart`)
- Crowdin URL `crowdin.com/project/genshin-impact-wish-gacha-analyzer`
- package 名 `genshin_impact_wish_gacha_analyzer`(所有 import 行)
- i18n 顯示字串值(arb 內「祈願 / Wish」)
- `lib/l10n/generated/`、`lib/src/rust/`

### 執行順序

1. `git mv lib/widgets/wish_item_icon.dart lib/widgets/gacha_item_icon.dart`
2. `git mv test/widgets/wish_item_icon_test.dart test/widgets/gacha_item_icon_test.dart`
3. Class / use site / Logger / const / 註解逐一改(用 Edit,不用全域 sed,因 `wish` 子字串會誤命中 package 名與 URL)
4. `dart format lib/ test/`
5. `flutter analyze` → `No issues found!`
6. `flutter test` → `All tests passed!`
7. 殘留檢查:`git grep -nE '[Ww]ish' lib/ test/` 殘留必須只落在白名單(package 名、repo URL、i18n 顯示文字)
8. commit:`refactor(naming): rename residual Wish→Gacha in hoyowiki branch`

## 架構(dialog)

### 新檔

`lib/widgets/dialogs/gacha_item_detail_dialog.dart`,內含四個成員,責任區隔:

- **`hasHoyoWikiContent(WidgetRef, GachaRecord) → bool`**:可點性判定
- **`GachaItemTapTarget`**(`ConsumerWidget`):tap 包裝,不可點時 passthrough
- **`showGachaItemDetailDialog(BuildContext, GachaRecord) → Future<void>`**:helper,集中 log + `showDialog`
- **`GachaItemDetailDialog`**(`ConsumerWidget`):dialog 本體

四者耦合 hoyowiki + dialog + tap,放同檔避免 cross-import。

### 不動

`GachaItemIcon`(rename 自 `WishItemIcon`)不加 tap 行為,維持純展示。

## 元件細節

### 1. `hasHoyoWikiContent`

```dart
bool hasHoyoWikiContent(WidgetRef ref, GachaRecord r) {
  if (r.gachaType == '2000' || r.gachaType == '1000') return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: r.name, lang: r.lang);
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

**重點**:
- 與 `GachaItemIcon` 同一份 lookup 路徑(`index.lookupId` + `hoyowikiCacheFile` + `existsSync`),保證「icon 顯示在元件 ↔ 可點性 ↔ dialog 內展示」三者一致
- `ref.watch` 兩個 provider:cache 完成下載後 `bumpCacheRevision()` 觸發重 build,可點性即時更新
- 不快取 `existsSync` 結果(與 `GachaItemIcon` 同步,避免一邊看到 icon 一邊點不開)

### 2. `GachaItemTapTarget`

```dart
class GachaItemTapTarget extends ConsumerWidget {
  const GachaItemTapTarget({super.key, required this.record, required this.child});
  final GachaRecord record;
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

**`GestureDetector` 而非 `InkWell` 的原因**:三處的視覺風格(時間軸節點、表格 stripe)偏低調,InkWell splash 會破壞既有層級。`MouseRegion` 的 cursor 變化 + 既有 Tooltip 已足夠告訴使用者「可點」。

### 3. `showGachaItemDetailDialog`

```dart
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
```

### 4. `GachaItemDetailDialog` Layout

`AppDialog(size: md, scrollable: false)`,自帶:
- 寬:`min(640, mq.width - 80)` → 內容寬約 596
- 高:`min(720, mq.height - 120)`(透過 `AlertDialog.constraints.maxHeight`)

**內部結構**(`content`):

```
Column(mainAxisSize: min, crossAxisStart)
├── Row(crossAxisCenter)
│     ├── if (hasIconFile) [
│     │     ClipRRect(radius 6,
│     │       child: Image.file(iconFile, 48×48, errorBuilder: SizedBox.shrink)),
│     │     SizedBox(width: 12),
│     │   ]
│     └── Expanded(Text(record.name,
│           style: headlineSmall + 卡稀有度色, maxLines: 2, ellipsis))
└── if (hasHeaderFile) [
      SizedBox(height: 16),
      Flexible(
        fit: FlexFit.loose,
        child: ClipRRect(
          radius: 8,
          child: Image.file(
            headerFile,
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            errorBuilder: SizedBox.shrink,
          ),
        ),
      ),
    ]
```

**為何不會超出視窗**:
- `AlertDialog.constraints.maxHeight` 限制整體高度
- Title row 為固定高度(~64px)
- header `Flexible(loose) + BoxFit.contain` 吃剩餘高度,寬高比保留;若計算後寬度不足以塞下原圖,自動縮小,絕不撐爆

**邊界場景**:
- 只有 header(極罕見):title Row 只有 name,下方畫 header
- 只有 icon(常見:武器多半無 header):title Row 有 icon + name,下方不畫 header
- 兩圖都讀檔失敗(race):兩個 `errorBuilder` 各自讓位 → dialog 只剩 name 與 actions,使用者可關閉

`hasIconFile` / `hasHeaderFile` 在 `build` 內透過 `index.lookupEntry` 重算(`ref.watch(hoyowikiIndexProvider)`),與 `hasHoyoWikiContent` 同一算法。

**actions**:單一關閉按鈕(實作時挑既有 close i18n key,或新增 `gachaItemDetailClose`)。

## 三處 call site 改造(dialog 部分,基於 rename 後的命名)

### a. `SortableTable._Row`(`lib/widgets/data/sortable_table.dart`)

整個 name 欄的 inner Row 包進 `GachaItemTapTarget`:

```dart
Expanded(
  flex: 5,
  child: GachaItemTapTarget(
    record: record,
    child: Row(
      children: [
        GachaItemIcon(record: record, size: 32),
        const SizedBox(width: 6),
        Expanded(child: Text(record.name, ...)),
      ],
    ),
  ),
),
```

### b. `TimelineVertical._EntryRow`(`lib/widgets/cards/timeline_vertical.dart`)

Tooltip 留外層、Row 包進去(確保 hover 名稱仍出 tooltip,點擊出 dialog):

```dart
Tooltip(
  message: entry.name, ...,
  child: GachaItemTapTarget(
    record: entry.sourceRecord!,
    child: Row(mainAxisSize: MainAxisSize.min, ...),
  ),
),
```

`sourceRecord == null` 分支(舊資料相容)維持不包,Tooltip 內直接 Text(name)。

### c. `TimelineHorizontal._EntryColumn`(`lib/widgets/cards/timeline_horizontal.dart`)

不能整欄包(否則節點、日期也算進 hit zone),只包 icon + 名稱兩列:

```dart
if (entry.sourceRecord != null)
  GachaItemTapTarget(
    record: entry.sourceRecord!,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GachaItemIcon(record: entry.sourceRecord!, size: 32),
        const SizedBox(height: AppSpacing.xs),
        Text(entry.name, ...),
      ],
    ),
  )
else
  Text(entry.name, ...),
const SizedBox(height: AppSpacing.xs),
_Node(...),  // 不被包進
```

## 錯誤處理

| 場景 | 處理 |
|---|---|
| 點下去前 cache 檔被刪/壞 | `Image.file(errorBuilder)` 回 `SizedBox.shrink`;若兩圖都壞,dialog 只剩 name + 關閉按鈕,使用者可關閉 |
| Dialog 開啟期間 HoyoWiki index 變動 | `GachaItemDetailDialog` 為 `ConsumerWidget`,`ref.watch(hoyowikiIndexProvider)` 重 build |
| Dialog 開啟期間切頁/widget unmount | `showDialog` 走 root navigator,自動 pop |

## i18n / Logging

- **i18n**:dialog 關閉按鈕優先用既有 close key;若無則新增 `gachaItemDetailClose: "Close" / "關閉"`。title 不額外加 i18n key(name 本身即 title)。
- **Logger 名稱**:`gacha.hoyowiki.detail`(對齊 rename 後的 `gacha.hoyowiki.*` 樹)
- **Log 等級**:
  - `info`:dialog 開啟(name + lang + rank)
  - `warning`:`Image.file.errorBuilder` 觸發(極端 race,記下 id + kind)
- 純 UI 動作,不埋 `fine` / `severe`。

## 測試

新增 `test/widgets/dialogs/gacha_item_detail_dialog_test.dart`:

### 1. `hasHoyoWikiContent` 判定矩陣

用 fake `HoyoWikiIndex` + temp dir,逐項驗證:

| 情境 | 期望 |
|---|---|
| `gachaType = '2000'`(頌願) | false |
| `gachaType = '1000'`(頌願) | false |
| lookup miss(`lookupId == null`) | false |
| entry 存在但兩 URL 都空 | false |
| URL 存在但 cache file 未到 | false |
| 只 icon file 存在 | true |
| 只 header file 存在 | true |
| 兩者都存在 | true |

### 2. Dialog 渲染

`ProviderScope.overrides` 注入 fake index + temp dir(含預製假圖檔):

- **兩圖齊全**:title row 找得到一個 `Image.file`(icon)+ name `Text`,content 找得到第二個 `Image.file`(header)
- **只有 icon**:title row 有 icon `Image.file` + name,整個 dialog 只有一個 `Image.file`
- **只有 header**:title row 無 icon(找不到第一個 `Image.file`),只剩 name + 下方 header
- **不會 vertical overflow**:`tester.binding.setSurfaceSize(Size(640, 480))` 設小視窗,`tester.takeException()` 為 null

### 3. Tap 行為

- clickable record:點 `GachaItemTapTarget.child` → `find.byType(GachaItemDetailDialog)` 出現
- 不可 clickable(頌願 / lookup miss / 全部 cache miss):點下去 dialog 不出現
- 不可 clickable 時,`GachaItemTapTarget` 是 passthrough(找不到 `MouseRegion(cursor: click)` 那層)

### 4. 不影響既有 Tooltip(timeline 場景)

`GachaItemTapTarget` 包進 Tooltip 內後,長 hover 仍能觸發 Tooltip 顯示。`tester.longPress` / `pumpAndSettle` 後,`find.text(entry.name)` 至少兩個(元件內 + tooltip overlay)。

### 既有測試影響

- `gacha_item_icon_test.dart`(原 `wish_item_icon_test.dart`):僅檔名 + import + 類別參考改名,測試邏輯零變動,零回歸
- `SortableTable` / `TimelineVertical` / `TimelineHorizontal` 既有測試:`WishItemIcon` 引用改 `GachaItemIcon`;若有 widget pump,需確認 `GachaItemTapTarget` 包進去後 layout 未爆;必要時補一條 smoke test

## 待實作期間決定

- 關閉按鈕的 i18n key:實作時 grep `commonClose` / `close` / `dialogClose`,優先重用;真無則新增 `gachaItemDetailClose`
- title row name 的文字 style:取既有 `theme.textTheme.headlineSmall` 或 `titleLarge`,套稀有度色(`tokens.fiveStar` / `tokens.fourStar` / 預設色)
- header `ClipRRect` 圓角值:`AppRadius.md`(對齊既有卡片風格)
- icon `ClipRRect` 圓角值:6(對齊既有 `GachaItemIcon` 內部)

## Commit 切分

兩個 commit,順序固定:

1. `refactor(naming): rename residual Wish→Gacha in hoyowiki branch` — 純 rename,no behavior change
2. `feat(hoyowiki): add GachaItemDetailDialog with icon+name+header` — 新 dialog + 三處 call site 包裝
