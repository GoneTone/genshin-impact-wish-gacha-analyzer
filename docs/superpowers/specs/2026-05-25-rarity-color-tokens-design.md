# 稀有度色票調整設計

- 日期：2026-05-25
- 範圍：`lib/theme/tokens.dart`、`lib/widgets/rank_palette.dart`
- 目標：把稀有度 1★～5★ 的色票對齊使用者指定的基準色（接近原神武器/聖遺物配色慣例），並補上目前缺少的 1★ 獨立 token。

## 背景

目前稀有度色票定義在 `lib/theme/tokens.dart` 的 `GachaTokens`，dark / light 各一組；只覆蓋 5★、4★、3★、2★，1★ 在 `lib/widgets/rank_palette.dart` 的 `accentForRank()` 走 `t.textMuted` fallback。

使用者指定新的 baseline 色碼（mid-tone，跨主題視為基準）：

| 星級 | Baseline |
|---|---|
| 5★ | `#b27330` |
| 4★ | `#9c75b7` |
| 3★ | `#5392b8` |
| 2★ | `#519072` |
| 1★ | `#868586` |

跟現況最大差異：

1. **2★ 從灰系（`#6A7080` / `#8A92A6`）變綠系**——對齊原神 2★ 武器綠的視覺慣例。
2. **1★ 從 `textMuted` fallback 升格為獨立 token**。
3. 5★ 從亮金（dark `#E6C477`、light `#B8860B`）變銅金（厚實感）。

使用者明確同意：「顏色可依據深色淺色主題調整，不一定要完全照著上方給的色碼，只要顏色接近就好。」

## 決策

- **範圍**：dark + light token 都調整。
- **1★ token**：正式加入 `GachaTokens.oneStar`，取代 `accentForRank()` 中對 `textMuted` 的隱含 fallback。
- **微調強度**：方案 B（中等，±10～12% L），以 baseline 為中心，dark 提亮、light 加深，色相與飽和度不變。理由：5★ baseline `#b27330` 在 dark `#0C1220` 上的對比約 4.2:1（剛好 AA），方案 B 推到 ~5.6:1；同時跟 baseline 色感差距仍小。
- **衍生變更**：`accentPrimary`、`stateWarning` 目前在 `GachaTokens` 兩個 theme 都設定為與 `fiveStar` 同色（按鈕主色、警告色都採用 5★ 金色），維持此慣例，跟著 5★ 一起換成銅金。主要按鈕、警告 chip 的色感會跟著從亮金變銅金——預期效果，不獨立調整。

## 最終色票

| 星級 | Dark | Light |
|---|---|---|
| 5★ | `#cd8e48` | `#8d5a25` |
| 4★ | `#b594c5` | `#7e589a` |
| 3★ | `#73a8c5` | `#437897` |
| 2★ | `#6dad8a` | `#467b62` |
| 1★ | `#a3a2a3` | `#686769` |

## 程式碼變動

### `lib/theme/tokens.dart`

- `GachaTokens` constructor 加 `required this.oneStar`。
- class 新增 `final Color oneStar;` 欄位（搭配一行 dartdoc）。
- `copyWith` 加 `Color? oneStar` 參數與 `oneStar: oneStar ?? this.oneStar`。
- `lerp` 加 `oneStar: Color.lerp(oneStar, other.oneStar, t)!`。
- `dark` static const：`fiveStar`、`fourStar`、`threeStar`、`twoStar` 換成上表 Dark 欄；新增 `oneStar: Color(0xFFA3A2A3)`。
- `light` static const：對應 Light 欄換色，新增 `oneStar: Color(0xFF686769)`。
- `accentPrimary` 在兩個 theme 都跟 `fiveStar` 同色（維持目前慣例）：
  - dark `accentPrimary: Color(0xFFCD8E48)`
  - light `accentPrimary: Color(0xFF8D5A25)`
- `stateWarning` 目前也跟 5★ 同色，跟著一起換（維持目前慣例）：
  - dark `stateWarning: Color(0xFFCD8E48)`
  - light `stateWarning: Color(0xFF8D5A25)`

### `lib/widgets/rank_palette.dart`

`accentForRank()` switch 加上 `1 => t.oneStar`，default `_ => t.textMuted` 保留處理異常 rank 值。

```dart
Color accentForRank(int rank, GachaTokens t) => switch (rank) {
  5 => t.fiveStar,
  4 => t.fourStar,
  3 => t.threeStar,
  2 => t.twoStar,
  1 => t.oneStar,
  _ => t.textMuted,
};
```

## 範圍外（明確不做）

- 不改 `BannerColors`（卡池配色刻意跟稀有度脫鉤）。
- 不調 `borderEmphasis`、`textSecondary` 等中性 token。
- 不引入色票自動產生 / HSL helper（YAGNI，五個 hex 寫死最易讀）。
- 不新增 0★ 或其他稀有度。
- 不調 `stateDanger`、`stateSuccess`（與稀有度無關）。

## 驗證計畫

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`（既有測試不依賴具體 hex，rarity_pie / overview / banner 都讀 token，預期不破）
4. `flutter run` 手動驗證：
   - 切換 dark / light theme，覽覽頁 stat card、rarity pie、卡池頁的 5★/4★/3★ accent 顏色觀感
   - 分享圖（`share_card.dart`）的 rank5 / rank4 accent 顏色
   - sortable_table、timeline、pity card 等所有用 `accentForRank()` 的元件
   - 確認在兩主題下 5★ chip 都看得清楚（不會在 dark 過暗、不會在 light 過亮）

## 風險

- `GachaTokens` constructor 新增 required 欄位是 breaking change，但唯二的呼叫點就是 `dark` / `light` 兩個 static const，影響範圍可控。
- `accentPrimary` / `stateWarning` 從亮金變銅金後，主要按鈕、警告 chip 的視覺色感會跟著變——預期效果，不視為風險。
