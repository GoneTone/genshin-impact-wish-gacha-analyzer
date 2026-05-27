# Missing-icon Placeholder — `?` 圖佔位

## 背景

缺 HoYoWiki icon 的卡池物品目前走 `lib/widgets/gacha_item_icon.dart` 內的 private `_Placeholder`：依稀有度上色的純色方塊（底色 18% / 邊框 40% alpha / 圓角 4），中央**沒有任何符號**。

出現時機：

- 頌願卡池（gachaType `2000` / `1000`）以外的物品；
- 在 HoYoWiki index 查不到對應 id；
- 或 `iconUrl` 對應的本機 cache 檔還沒下載（含尚未跑過 hoyowiki fetch 的全新匯入帳號）。

影響範圍：所有 `GachaItemIcon` 宿主（timeline 卡片 / sortable table / banner page），以及**分享圖**（`preloadHoYoWikiImages` skip 的記錄會走同一個 placeholder code path）。Detail dialog 不受影響——缺 HoYoWiki content 時 `hasHoYoWikiContent` 為 false，本來就不可點。

純色方塊不夠明示「未知/未抓到」。改成在方塊中央疊一個 `?` 圖示，讓使用者一眼看出「這格是 placeholder、不是真的 icon」。

## 目標

`_Placeholder` 從「純色方塊」升級為「純色方塊 + 中央 `?`」，不新增 asset、不改外部 API、不影響呼叫端。

## 非目標

- 不另外 bundle PNG / SVG asset（評估後採 Flutter 內建 Icon widget，自動隨 theme tint，免維護 @2x/@3x）。
- 不改變 `_Placeholder` 觸發時機或 `GachaItemIcon` 的判斷邏輯。
- 不為 detail dialog 補 placeholder（目前缺 icon 時 dialog 根本不可點，使用者看不到）。
- 不調整稀有度配色（沿用既有 `tokens.fiveStar` / `tokens.fourStar` / `tokens.textMuted`）。

## 設計

### 修改點

只動 `lib/widgets/gacha_item_icon.dart` 的 `_Placeholder.build`：在現有 `Container` 內加一個 `Center(child: Icon(...))`。

```dart
return Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: accent.withValues(alpha: 0.18),
    border: Border.all(color: accent.withValues(alpha: 0.40)),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Center(
    child: Icon(
      Icons.question_mark,
      size: size * 0.55,
      color: accent,
    ),
  ),
);
```

### 視覺規格

| 項目                | 值                                  | 備註                                       |
|-------------------|------------------------------------|------------------------------------------|
| 底色                | `accent.withValues(alpha: 0.18)`   | 沿用                                       |
| 邊框                | `accent.withValues(alpha: 0.40)`   | 沿用                                       |
| 圓角                | `4`                                | 沿用                                       |
| `?` 圖示            | `Icons.question_mark`              | Material 純 `?` 字圖示，無外圈                   |
| `?` 尺寸            | `size * 0.55`                      | 32px 宿主下 ≈ 17.6px，留白 22.5%               |
| `?` 顏色            | `accent`（全色，不打折）                   | 淡底色上 100% accent 對比足夠                    |
| 稀有度 → accent      | 5 → `tokens.fiveStar`；4 → `tokens.fourStar`；其他 → `tokens.textMuted` | 沿用既有 switch |

### 為什麼用 Icon widget 而不是 bundle PNG

- 無需維護 @1x / @2x / @3x 三組 asset。
- `?` 隨 `accent` 顏色自動 tint，3/4/5 星不必各畫一張。
- 深淺色 theme 切換自動跟著走（若未來引入 dark mode）。
- 編譯後檔案小（無 asset bytes）。

## 影響範圍與相容性

- **外部 API 零變動**：`_Placeholder` 是 private、`GachaItemIcon` 對外簽名不變。呼叫端（timeline / sortable_table / banner_page / share image）全數零 diff。
- **分享圖**：`preloadHoYoWikiImages` skip 的記錄會在分享圖上看到 `?`。比現有純色方塊更清楚表達「未知」，視為正面影響。
- **i18n / l10n**：`?` 是 universal 符號，跨語系一致；不需新增翻譯字串。
- **無障礙**：`Icon` 本身沒有 semantic label。`GachaItemIcon` 上層通常已有物品名稱可被讀屏軟體讀到，這裡不額外加 `Semantics`（YAGNI；如後續無障礙 audit 提出可再補）。

## 驗證

### 自動化

- `lib/widgets/gacha_item_icon.dart` 若已有 widget test，補一個 case：缺 cache 時 `find.byIcon(Icons.question_mark)` 預期出現一次，且 `(tester.widget<Icon>(find.byIcon(Icons.question_mark))).size` 等於 `size * 0.55`。若無既有 test 檔，新建 `test/widgets/gacha_item_icon_test.dart`。
- 跑 `flutter analyze`（必須 `No issues found!`）。
- 跑 `flutter test`（必須 `All tests passed!`）。
- 跑 `dart format lib/ test/`（CLAUDE.md 規定不對 `.` 跑）。

### 手動

- 跑 app，找一個 hoyowiki cache 尚未抓到的物品，確認 3 / 4 / 5 星 placeholder 都有 `?` 且色彩正確（金 / 紫 / 灰）。
- 點分享按鈕產出分享圖，截圖確認 `?` 在分享輸出上可辨識（分享圖可能用較高解析度，`size * 0.55` 比例仍正確）。

## Log 變更

無。`_Placeholder` 是純 UI、無 I/O，依 CLAUDE.md「I/O / 錯誤分支 / 外部 API / Rust bridge」原則，這裡不需要新埋 log。
