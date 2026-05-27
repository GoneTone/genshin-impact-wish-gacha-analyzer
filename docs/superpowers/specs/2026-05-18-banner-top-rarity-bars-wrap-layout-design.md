# 卡池主稀有度件數長條圖：兩側文字換行版面（A1）

## 問題

`lib/widgets/cards/banner_top_rarity_bars.dart` 的 `_BannerRow` 是三欄 `Row`：

- 名稱欄：固定 `96px`，`overflow: TextOverflow.ellipsis`
- bar：`Expanded`
- 件數 + `·` + 說明欄：固定 `156px`，subtitle `overflow: TextOverflow.ellipsis`

中文（zh-Hant / zh-Hans）下文字短，固定寬度夠用；但英文、日文等語系下「Character Event Wish」「0 pulls since last 5★」會超出固定寬度被 `…` 截斷，使用者無法看到完整卡池名稱與保底說明。

## 目標

兩側文字（名稱、件數·說明）改為自由換行、**完整顯示不截斷**；中間 bar 縮短讓出空間。維持單列三欄版型，bar 在各列間寬度一致以保有可比性。

## 非目標

- 不改動任何資料 / 業務邏輯：件數計算、`computePity`、顏色、卡池排序、`subtitle` 文案邏輯全部不變。
- 不做 `LayoutBuilder` 響應式百分比欄寬（卡片寬度穩定，YAGNI）。
- 不改 `overview_page.dart`（卡片 `height: null` 已能自適應變高的列）。

## 方案：A1 — 兩側固定加寬欄 + 彈性 bar

排除的替代方案：

- **A2 內容自適應欄寬**：bar 寬度會逐列不同 → bar 失去跨卡池可比性。排除。
- **A3 `LayoutBuilder` 百分比欄寬**：卡片寬度穩定，過度設計。排除。

## 變更範圍

只改 `lib/widgets/cards/banner_top_rarity_bars.dart` 的 `_BannerRow.build`。

### 1. 名稱欄

- 固定 `SizedBox` 寬度由 `96` 加寬到能單行容納最長 CJK 名稱的值（起始值 `120`，實作時實測微調）。
- 移除 `Text` 的 `overflow: TextOverflow.ellipsis`。
- 保留 `textAlign: TextAlign.right`、`style: theme.textTheme.bodyMedium`。
- `maxLines` 不設（預設 `null`）→ 文字依需要自由換多行。

### 2. 右側件數 · 說明欄

- 固定 `SizedBox` 寬度由 `156` 加寬到約 `180`（實作時實測微調）。
- 維持既有結構：`Row(mainAxisSize.min)` → `件數(粗體)` + `SizedBox(6)` + `·` + `SizedBox(6)` + `Expanded(subtitle)`。
- 移除 subtitle `Text` 的 `overflow: TextOverflow.ellipsis`，`maxLines` 預設 `null`。
- 結果：`件數 · ` 留在第一行開頭，subtitle 由其後自由折行排下（與使用者確認的版型一致）。

### 3. bar

- 在 `Expanded` 內把 `_Bar` 外包一層 `ConstrainedBox(constraints: BoxConstraints(minWidth: 56))`（起始值 `56`，實作時實測微調）。
- 窄視窗下 bar 變短但不會塌成 0 寬。
- `_Bar` 內部（高度、漸層、`FractionallySizedBox` `widthFactor`）不變。

### 4. 列對齊

- 維持 `Row` 預設 `crossAxisAlignment: center`：文字折行使該列變高時，10px 高的 bar 對齊到文字區塊垂直置中。

## 像素值決策

`120` / `180` / `56` 為起始值。實作時以所有支援語系（en、ja、zh、zh_Hans）的最長卡池名稱與最長 subtitle 字串實際渲染對照，微調到「常見 CJK 單行、英日約兩行、bar 仍有合理可比寬度」後定稿；確切數值寫進程式碼註解說明調校依據（沿用既有 `// name label column, tuned for…` 註解風格）。

## 預期結果

- 任何語系下名稱與 subtitle 皆完整顯示，無 `…` 截斷。
- 文字折行時該列變高（1～2 行以上），bar 縮短讓出空間。
- 各列 bar 寬度一致（兩側欄固定），維持跨卡池視覺比較。
- 卡片整體高度由父層 `height: null` 自適應。

## 測試

### 既有測試（須維持通過，不修改）

`test/widgets/cards/banner_top_rarity_bars_test.dart` 全部以完整文字 `find.text(...)`、`·` 數量、`FractionallySizedBox.widthFactor`、漸層顏色斷言。文字不再被截斷、bar 比例與顏色邏輯不變 → 應全數續過。

### 新增測試

新增一個 widget test：

- 在受限寬度容器（沿用既有 `_wrap` 的 `SizedBox(width: 800)` 或更窄）下，以英文 locale（最長字串情境）渲染 `BannerTopRarityBars`。
- 斷言能 `find.text(...)` 到至少一個最長卡池完整名稱字串（如 `Character Event Wish`）與一個完整 subtitle 字串 → 證明無截斷。
- 斷言 `FractionallySizedBox` 數量 = `gachaTypes.length` → 證明 bar 在新版面下仍正常渲染。

## 提交前品質檢查（依 CLAUDE.md）

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`
