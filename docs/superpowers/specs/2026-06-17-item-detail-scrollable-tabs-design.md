# 物品詳情 Dialog 頁籤改為單行可捲動 + 三角箭頭導航

## 背景與目標

`gacha_item_detail_dialog.dart`（物品詳情 Dialog）目前的切換頁籤以 `Wrap` + `ChoiceChip` 實作，頁籤數量多時會自動換成多行，在窄視窗下擠成好幾行、佔用大量垂直空間。

目標：把頁籤改為**維持一行**，超過寬度可**水平捲動**，並在左右兩側提供**三角箭頭**作為視覺指引與導航快捷鈕，讓使用者知道可以左右切換；箭頭可點擊，到頭／到尾時對應箭頭停用。

## 現況

- 檔案：`lib/widgets/dialogs/gacha_item_detail_dialog.dart`。
- 頁籤目前用 `Wrap`（`spacing: 8, runSpacing: 8`）+ `ChoiceChip`，僅在 `chipEntries.length > 1` 時顯示。
- 頁籤數量是**動態**的，由三類來源組成：
  1. `gallery.list` 逐項（數量不定，圖片 `imgUrl` 為空者略過）；
  2. 大圖卡（`gallery.picUrl` 非空時 1 個）；
  3. Icon（`iconFile` 存在時 1 個，永遠排最後）。
- Dialog 已使用 `AppDialog`（`size: AppDialogSize.md`、`maxHeight: 880`）。
- 專案已有成熟的水平捲動 + 箭頭指引實作：`lib/widgets/cards/timeline_horizontal.dart`，內含 `_ArrowButton`、`_EdgeFade`、以及 `_updateAffordance`（依 scroll offset 判斷箭頭／fade 顯示）。

## 設計

### 整體結構

把現有 `Wrap` 換成單行三欄結構：

```
[← 左三角箭頭]  [ 可水平捲動的 ChoiceChip 列（含邊緣 fade） ]  [→ 右三角箭頭]
```

三欄固定排版：左右箭頭各佔獨立欄位，**不會遮住邊緣的頁籤**；箭頭停用時仍保留位置（版面不跳動）。中間捲動區保留邊緣漸隱 fade 提示可捲方向。

### 元件拆分

呼應「禁止造輪子」與 YAGNI：

1. **抽出共用視覺元件**：把 `timeline_horizontal.dart` 內的 `_ArrowButton`、`_EdgeFade` 移到新檔 `lib/widgets/scroll/`，更名為 `ScrollArrowButton`、`ScrollEdgeFade`，兩處共用。
   - `ScrollArrowButton`：圓形箭頭鈕，含 tooltip、`SystemMouseCursors.click`、`onPressed` 可為 `null` 即停用。**icon 由呼叫端傳入** → timeline 維持 chevron，dialog 傳實心三角（`Icons.arrow_left` / `Icons.arrow_right`）。
   - `ScrollEdgeFade`：邊緣漸隱，跟隨 dialog／卡片背景色。
   - `timeline_horizontal.dart` 改用這兩個共用元件，**行為不變**，只換 import 與型別名稱。

2. **dialog 內新建編排元件** `_GalleryChipBar`（private，就近放在 `gacha_item_detail_dialog.dart`）：負責三欄排版、`ScrollController`、箭頭點擊切頁、fade 顯示判斷。
   - 捲動編排**不抽通用**：它由「選中索引頭尾」驅動，與 timeline 的「scroll offset 驅動」本質不同，過早抽象會引入不必要的彈性（YAGNI）。

### 互動行為（兩套驅動邏輯解耦）

**箭頭 — 由「選中索引」驅動：**

- 左箭頭：`_selectedIndex > 0` 時可用 → 選中 `_selectedIndex - 1`，並把該 chip 以 `Scrollable.ensureVisible`（平滑動畫，沿用 timeline 的 duration／curve）捲入可視範圍；在第一頁時 `onPressed = null`（灰掉停用，仍佔位）。
- 右箭頭：對稱，`_selectedIndex < length - 1` 時可用 → 選中下一個並捲入；最後一頁停用。

**中間 fade — 由「scroll offset」驅動：**

- 沿用 `_updateAffordance` 偵測：`offset > 1` → 顯示左 fade；`offset < maxScrollExtent - 1` → 顯示右 fade（±1px 容差避免抖動）。
- fade 純粹提示該方向尚有被遮住的內容，**與箭頭停用無關**。例如停在第一頁（左箭頭停用）但手動把列往左推一點，左 fade 仍可出現——兩者獨立。

**其他：**

- **手動捲動保留**：可用觸控板／滑鼠拖曳／觸控直接水平捲動 chip 列（`MouseRegion` cursor 用 `resizeLeftRight`，與 timeline 一致），箭頭只是額外的「上／下一頁」快捷。
- **選中時自動捲入**：使用者直接點某個 chip 切換時，也呼叫 `ensureVisible`，確保選中的 chip 不被 fade 半遮。
- **顯示條件**：維持 `chipEntries.length > 1` 才顯示整條 bar；`length <= 1` 時整條（含箭頭）不顯示。

### RWD / 邊界情況

- AppDialog 最窄約「視窗寬 − 80」。兩側箭頭各約 32–40px，中間捲動區吃剩餘空間，永遠至少能完整顯示捲動區，不會 overflow。
- chip 不換行、不擠壓（`Row` + `mainAxisSize.min`），過長靠捲動，符合「維持一行」。
- 索引 clamp 邏輯維持現狀（`clampedIndex`）。
- 初始進入：首幀後觸發一次 `_updateAffordance` 算出 fade 初始狀態；若預設選中非第一個，首幀後 `ensureVisible` 一次。
- `dispose` 要移除 `ScrollController` listener 並 dispose，避免 leak。

### Log

純前端互動，無 I/O／外部 API／Rust bridge，屬不需埋 log 的範疇，保持乾淨**不加** log。

### 測試（widget test）

- `chipEntries.length <= 1` 時整條 bar 不顯示。
- 多頁時：第一頁左箭頭停用、最後一頁右箭頭停用、中間兩者皆可按。
- 點右箭頭 → 選中索引 +1。
- 直接點某 chip → 選中切換正確。
- fade 依賴實際 layout 寬度，較難在 widget test 穩定驗證；以「箭頭停用狀態」與「選中切換」為主要斷言，不為視覺輔助寫脆弱測試。

## 驗收條件

- `fvm flutter analyze` 輸出 `No issues found!`。
- `fvm flutter test` 輸出 `All tests passed!`（含上述新增 widget test）。
- `timeline_horizontal` 改用共用元件後行為不變（既有測試仍綠）。
- 物品詳情 Dialog 頁籤維持一行、可水平捲動，左右三角箭頭可點擊切頁，頭／尾箭頭停用。
