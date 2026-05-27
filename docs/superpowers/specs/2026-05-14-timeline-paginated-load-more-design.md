# 綜合頁時間軸分頁載入 — Design Spec

- 日期：2026-05-14
- 範圍：綜合頁（Overview）內的 `TimelineVertical` 直向時間軸
- 目的：避免一次渲染全部 5★/4★ 條目造成頁面過長與初次繪製負擔；改為預設顯示最新 10 筆，點擊「載入更多」每次再追加 10 筆。

---

## 1. 動機

綜合頁時間軸目前一次性渲染**全部** 5★/4★ 條目（祈願與頌願兩段各一份）。長期玩家累積數量大時：

- 綜合頁總高度過長，需要捲很久才能看到下方內容。
- 月份分組視覺密度過高，掃讀困難。

改為分頁顯示後：

- 預設只露最新 10 筆（最常被查看的部分），其餘按需展開。
- 整頁高度可控，捲動較舒適。

---

## 2. 範圍與不變式

### 動到的檔案

- `lib/widgets/cards/timeline_vertical.dart`：`TimelineVertical` 從 StatelessWidget 改為 StatefulWidget，內部加 `_visibleCount` 與「載入更多」按鈕。
- `lib/l10n/app_*.arb`（3 個語言檔）：新增 `timelineLoadMore` 文案 key。動到的檔案：`app_zh_Hant.arb`、`app_zh_Hans.arb`、`app_en.arb`。
  - 其他 6 個語言檔（ja/fr/es/pt/th/vi）目前**所有** timeline-* 系列 key 都沒翻譯（會 fallback 到模板 `app_zh_Hant.arb`），故新增的 `timelineLoadMore` 也採同樣處理，維持與既有 timeline UI 翻譯範圍一致。
- `test/widgets/cards/timeline_vertical_test.dart`：新增分頁行為測試 case。

### 不動的範圍

- `lib/pages/overview_page.dart`：`TimelineVertical(...)` 呼叫位置與參數零更動。
- `lib/services/timeline_entries.dart`：資料層完全不動。
- `lib/widgets/cards/timeline_horizontal.dart`：另一個時間軸 widget，不在綜合頁使用，不動。
- `_NowRow`、`_EntryRow`、`_Node` 內部繪製邏輯：不動。

### 對外不變式

- `TimelineVertical` public API 完全不變（`entries`、`colors`、`targetRank`、`nowPulls`、`isAcrossBanners` 五個 named param）。
- 「現在」row 行為不變：`nowPulls != null` 時永遠顯示在最頂端，**不計入分頁**。
- 月份左欄分組行為不變：每個月份首次出現時顯示標籤，跟著當前可見 entries 動態計算（**不會因為被截斷而錯亂或漏顯**）。

---

## 3. 行為規格

| 場景 | 行為 |
|---|---|
| `entries.length == 0` 且 `nowPulls == null` | 照舊：顯示「暫無 N★ 紀錄」，**無按鈕** |
| `entries.length == 0` 且 `nowPulls != null` | 照舊：只顯示 Now row，**無按鈕** |
| `1 ≤ entries.length ≤ 10` | 全部顯示，**無按鈕** |
| `entries.length ≥ 11` | 預設顯示前 10 筆 + **「載入更多（剩餘 N 筆）」按鈕** |
| 點擊按鈕 | `_visibleCount = min(_visibleCount + 10, entries.length)` |
| `_visibleCount == entries.length` | 按鈕隱藏 |

### `_visibleCount` 生命週期

- 初始值：`10`。
- `didUpdateWidget`：比較 `entries.length` 與「首筆 entry 的 `time`」兩個訊號：
  - **兩個訊號同時不同** → reset 回 `10`（對應切換帳號、清資料、重新同步資料集這幾個常見情境，兩個訊號通常都會跟著變）。
  - 其他情況（兩者其一變、或都不變） → 只做 `_visibleCount = _visibleCount.clamp(0, widget.entries.length)`，保留使用者已展開狀態（對應主題切換、視窗大小變動等純視覺 rebuild，或 list identity 不同但內容相同的 rebuild）。

> Note 1：因為 `entries` 在每次父層 `build` 都是新建 list（`_OverviewSection.build` 內呼叫 `buildTimelineEntriesAcrossBanners`），不能用 list identity 判斷；用 `length + firstTime` 穩定且輕量。
>
> Note 2：採 AND（兩者同時不同才 reset）而非 OR，是為了在邊界情境下偏向「不 reset」、保留使用者展開狀態，避免誤判。常見的「切換 dataset」實務情境兩個訊號都會跟著變，AND 仍然正確 reset。

---

## 4. UI 設計

### 按鈕

- Widget：`TextButton.icon(icon: Icons.expand_more, label: Text(l.timelineLoadMore(remaining)))`。
- 位置：時間軸卡片**內部底部**，位於最後一筆 `_EntryRow` 之下、卡片內邊距內。
- 水平對齊：**置中**。
- 文字色：`tokens.textSecondary`（保留 TextButton 預設的 hover/pressed 狀態變化）。
- 上下間距：與 `_EntryRow` 的 `AppSpacing.m` 風格一致；按鈕本身 padding 用 TextButton 預設即可。

### 月份標籤的處理

月份標籤（`showMonthTag`）目前計算邏輯：

```dart
final monthFlag = <bool>[];
int? prevYearMonth;
for (final entry in entries) {
  final ym = entry.time.year * 12 + entry.time.month;
  monthFlag.add(prevYearMonth != ym);
  prevYearMonth = ym;
}
```

改為以 `entries.take(_visibleCount)` 計算，邏輯不變。被截斷後新「最上層」entry 自動成為新月份首 row，視覺正確。

---

## 5. i18n

新增 key：

```
timelineLoadMore
```

帶 placeholder `{n}`（剩餘筆數，`int`）。翻譯範圍跟既有 timeline-* 系列 key 一致，只動 3 個語言檔：

| 語言 | 文案 |
|---|---|
| zh_Hant | `載入更多（剩餘 {n} 筆）` |
| zh_Hans | `加载更多（剩余 {n} 项）` |
| en | `Load more ({n} remaining)` |

其他 6 個語言檔（ja/fr/es/pt/th/vi）不動，會 fallback 到模板 `app_zh_Hant.arb`，跟既有 timeline UI 文案 fallback 行為一致。

3 個 arb 都要附 `@timelineLoadMore` placeholder metadata：

```json
"@timelineLoadMore": {
  "placeholders": { "n": { "type": "int" } }
}
```

---

## 6. 測試

新增 `test/widgets/cards/timeline_vertical_test.dart` 的 case：

1. **`entries.length == 11` → 預設 10 筆 + 按鈕（剩 1）**
   - 渲染後 finds 10 個 entry name；找得到按鈕；按鈕文字含「1」。
2. **點擊按鈕 → 全 11 筆顯示 + 按鈕消失**
   - tap 按鈕後 finds 11 個 entry name；找不到按鈕。
3. **`entries.length == 25` → 點兩次完整展開**
   - 第一次點 → 20 筆 + 按鈕（剩 5）；第二次點 → 25 筆，按鈕消失。
4. **`entries.length == 10` → 無按鈕**
   - finds 10 個 entry name；找不到按鈕。
5. **signature reset：先 25 筆展開到 20，再傳入不同 entries (length=15)** → `_visibleCount` 重置回 10。
6. **clamp（不 reset）：先 25 筆展開到 20，再 rebuild 同 entries** → 仍顯示 20 筆，按鈕仍可繼續點。
7. **既有 5 個測試 case 全部保持綠燈**（entries ≤ 3 不會觸發按鈕，不會 break）。

按鈕在測試中可以用 `find.byIcon(Icons.expand_more)` 或 `find.byType(TextButton)` 定位，文字斷言用 `l.timelineLoadMore(n)`。

---

## 7. 非目標（YAGNI）

以下功能**不**在本次範圍：

- 「收起」按鈕：使用者可用頁面捲動回上方，YAGNI。
- 滾動到底自動載入（infinite scroll）：時間軸在 `SingleChildScrollView` 內，巢狀 scroll listener 引入不必要的複雜度。
- 自訂每頁筆數（10/20/50 可選）：YAGNI。
- 「載入全部」一鍵展開：YAGNI。
- 動畫過場：保留 Flutter 預設 rebuild 行為，不額外加 `AnimatedSize` / `AnimatedSwitcher`。

---

## 8. 影響評估

### 行為相容性

- `overview_page.dart` 呼叫處不變 → 對使用者來說，原本 `entries ≤ 10` 的玩家完全不會感受到改變。
- `entries > 10` 的玩家：首次進入綜合頁看到的時間軸變短，下方多了一顆「載入更多」按鈕。

### 效能影響

- 正面：初次渲染只建立 10 個 `_EntryRow`，而非全部（對長期玩家可能省下幾十到上百個 widget）。
- 中性：點擊「載入更多」會觸發 `setState`，重建整個 `TimelineVertical` 的 children — 但 entries 計算本身在父層 `_OverviewSection.build` 已經完成，這裡只是切片，不重算資料。

### 風險

- 月份標籤計算範圍從「全部 entries」改成「前 _visibleCount 筆」，需確認每次展開後新出現的 entries 仍能正確判斷月份分組（已在 §4 與測試 §6 覆蓋）。
- `didUpdateWidget` 的判斷如果太寬（任一變即 reset），可能在父層每次 rebuild 都 reset；如果太窄（兩者都不變才視為同），可能切帳號後沒 reset。已設計為「`length` AND `firstTime` 兩者同時不同才 reset」：常見切 dataset 兩個訊號都會跟著變，能正確 reset；其餘邊界情境偏向保留展開狀態。
