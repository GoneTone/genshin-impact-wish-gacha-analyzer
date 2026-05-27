# 記錄列表名稱欄位點擊範圍收斂

- **日期**：2026-05-24
- **分支**：`feat/hoyowiki-item-image`（規劃在此或新 fix 分支實作）
- **檔案範圍**：`lib/widgets/data/sortable_table.dart`（單檔，兩處）

## 問題

Banner 頁的祈願記錄列表有兩個 hit area 過長的點：

1. **資料列「物品」欄**（`_Row` 內 `flex: 5` 的 cell）：點擊範圍涵蓋整個 cell 寬度。短名稱（例如「迪盧克」「風鷹劍」）右側那一大段空白也被視為可點擊熱區，把游標移過去會變成 click cursor，按下會開啟 `GachaItemDetailDialog`，與「點 icon / 名稱才會開」的視覺暗示不符。
2. **標題列各欄**（`_HeaderCell` 的 `InkWell`）：同樣涵蓋整個 cell 寬度。短 label（例如「種類」「保底內」）右側空白被視為可排序熱區，hover 時整段顯示 Material ripple / hover 色塊，視覺上像「整欄都是按鈕」，與實際 affordance（文字 + 排序圖示）不符。

## 根因

`lib/widgets/data/sortable_table.dart:388-407` 的結構：

```dart
Expanded(
  flex: 5,
  child: GachaItemTapTarget(           // 內含 MouseRegion(click) + GestureDetector(opaque)
    record: record,
    child: Row(                         // 預設 mainAxisSize.max → 撐滿父層
      children: [
        GachaItemIcon(record: record, size: 32),
        const SizedBox(width: 6),
        Expanded(                       // 把 Text 撐滿剩餘空間
          child: Text(record.name, ...),
        ),
      ],
    ),
  ),
),
```

`Expanded(child: Text)` 讓 Text widget 的寬度 = cell 寬度 − icon − spacing，再加上 `GestureDetector(HitTestBehavior.opaque)`，於是整個 flex: 5 的 cell（在常見視窗下可達 200+ px）都接收 pointer 事件。

## 對照組（不需動）

| 檔案 | 行為 | 為什麼正確 |
|---|---|---|
| `lib/widgets/cards/timeline_vertical.dart:321` `_nameRow` | `Row(mainAxisSize: MainAxisSize.min, ...)` | Row 收縮到 icon + 文字實際寬度 |
| `lib/widgets/cards/timeline_horizontal.dart:307` | `Column(mainAxisSize: MainAxisSize.min, ...)` | Column 收縮到內容寬高，配合外層 `SizedBox(width: _colWidth)` 置中 |

`timeline_vertical.dart:422-423` 還寫了註解：「mainAxisSize: min 讓 Row 收縮到 icon+text 實際寬度；否則 Row 預設吃滿父層」。專案內部 hit-area 慣例已存在，只是 sortable_table 沒套上。

## 設計

### 修改 1：資料列「物品」欄

`lib/widgets/data/sortable_table.dart`（原 388-407 行）改為：

```dart
Expanded(
  flex: 5,
  child: Align(
    alignment: AlignmentDirectional.centerStart,
    child: GachaItemTapTarget(
      record: record,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GachaItemIcon(record: record, size: 32),
          const SizedBox(width: 6),
          Flexible(
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
),
```

### 三點關鍵改動

1. **新加 `Align(alignment: AlignmentDirectional.centerStart)`**：讓內層 child 取 intrinsic 寬度（不撐滿父層 `Expanded` 提供的寬度），同時保持左對齊的視覺一致性。
2. **內 Row 加 `mainAxisSize: MainAxisSize.min`**：Row 自身改為以 children intrinsic 寬度為主。
3. **`Expanded(child: Text)` → `Flexible(child: Text)`**：`Expanded` 在 `mainAxisSize.min` 下會 assertion fail；`Flexible(fit: loose)`（預設）讓 Text 可 shrink-wrap 至 intrinsic 寬度，但仍可被 cell 上限約束以觸發 `TextOverflow.ellipsis`。

### 行為結果（資料列）

- 短名稱：Row 寬度 = `iconSize(32) + 6 + textIntrinsicWidth`；游標 / 點擊只在這段範圍內生效。
- 長名稱：cell 可用寬度 < 內容自然寬度時，`Flexible` 讓 Text 收縮，`ellipsis` 截斷，hit area 等於 cell 寬。
- 不需動 `GachaItemTapTarget` 本身（不影響 timeline_vertical / timeline_horizontal）。

### 修改 2：標題列各欄（`_HeaderCell`）

`lib/widgets/data/sortable_table.dart` 內 `_HeaderCell.build` 改為：

```dart
final cell = InkWell(
  mouseCursor: SystemMouseCursors.click,
  onTap: () => onTap(column),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  ),
);
return Expanded(
  flex: flex,
  child: Align(
    alignment: alignEnd
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: tooltip == null
        ? Tooltip(message: tip, child: cell)
        : Tooltip(message: '${tooltip!} · $tip', child: cell),
  ),
);
```

關鍵改動：

1. `Expanded(flex: flex, child: Tooltip(...))` 內包一層 `Align`：alignEnd 欄位（總序號、保底內）用 `centerEnd`，其餘用 `centerStart`，讓 InkWell + Tooltip 取 intrinsic 寬度而非撐滿 cell。
2. Row 加 `mainAxisSize: MainAxisSize.min`：收縮到 `label 文字 + 4 spacing + 14px 排序 icon` 寬。`children` 內第一個本來就是 `Flexible(child: Text(...))`，長 label 仍由 cell 上限觸發 ellipsis。
3. 移除 `mainAxisAlignment: alignEnd ? end : start`：Row 已被 shrink-wrap，內部不再有剩餘空間可分配，這個參數變成 dead code。靠左 / 靠右的視覺位置改由外層 `Align` 決定。
4. 顯式指定 `mouseCursor: SystemMouseCursors.click`：InkWell 的預設 cursor (`MaterialStateMouseCursor.clickable`) 在實機 Windows hover 時未必正常 resolve 為 click，跟隨專案內既有慣例（`team_links_bar.dart:84`、`translator_text.dart:153`）明確指定，避免 hover 時 cursor 保持為箭頭。

### 行為結果（標題列）

- 點擊（觸發排序）與 Material ripple / hover 色塊只在 `label + icon` 範圍內生效，不再覆蓋整個 cell 寬。
- 短 label（如「種類」）與長 label（如「角色活動祈願 保底內」如有翻譯較長者）行為一致：前者收縮，後者由 cell 上限觸發 ellipsis。
- Tooltip 仍由 `Tooltip` 包整個 cell，hover 行為視覺上沒變。

## 拒絕的替代方案

| 方案 | 拒絕原因 |
|---|---|
| 改 `GachaItemTapTarget` 內部加 `Align` | 會打破 `timeline_horizontal.dart` 的置中佈局；該處外層用 `SizedBox(width: _colWidth)` + `Column(crossAxisAlignment: center)`，下沉 Align 會強制改為置左 |
| 抽出 `GachaItemNameLabel` 共用元件包 icon+文字+TapTarget | YAGNI：只有 3 處使用且內部結構（Row / Column / 置中 / 置左 / textStyle）各異，抽共用要傳一堆 axis / alignment / style 參數，反而比現狀更難讀。等出現第 4 處或慣例有真正衝突時再考慮 |
| 用 `Wrap` 取代 Row | 本案無多行需求，多換 layout 元件無收益 |

## 測試與驗證

實作完成前依 `CLAUDE.md` 規定依序：

1. `dart format lib/ test/`
2. `flutter analyze` — 必須 `No issues found!`
3. `flutter test` — 必須 `All tests passed!`

手動驗證（release，依 memory `feedback_perf_check_release_first` 雖然這不是 perf 問題，但 sortable_table 本就在 banner 頁，順手用 release 跑一遍）：

1. `flutter run --release`
2. 進入任一非頌願 banner（例如「角色活動祈願」）
3. 資料列：把滑鼠移到任一短名稱記錄的右側空白處 → 游標 **不應** 變成 click cursor，按下 **不應** 開啟 detail dialog
4. 資料列：移到 icon 或名稱文字本身 → 維持原本：游標為 click cursor，按下開啟 detail dialog
5. 資料列：找一筆 5★ 武器（名稱通常較長）確認長名稱仍 `…` ellipsis 截斷，沒有溢位到下一欄
6. 標題列：把滑鼠移到任一欄標題右側 / 左側空白處 → Material ripple / hover 色塊 **不應** 出現，按下 **不應** 觸發排序
7. 標題列：移到 label 文字或排序 icon 上 → 維持原本：hover 色塊出現、按下觸發排序、tooltip 顯示
8. 標題列：靠右對齊欄（「總序號」「保底內」）的內容仍正確靠右；靠左對齊欄仍正確靠左

不需新增單元測試：純佈局與 hit-test 行為改動，golden / widget test 對 hit area 的驗證成本遠高於收益；現有 `flutter analyze` + 手動 release 驗證已足夠覆蓋。

## 不在此 spec 範圍

- 不調整 `GachaItemTapTarget` 的 API 或行為
- 不重構 `_BannerRow` / `_DesktopRow` 其他欄位
- 不調整 timeline_vertical / timeline_horizontal
- 不抽 `GachaItemNameLabel` 共用元件
- 不改 i18n、不動 Rust bridge
