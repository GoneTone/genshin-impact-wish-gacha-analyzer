# 4★ 保底計數應被更高稀有度重置

## 背景與問題

`lib/services/gacha_pity.dart` 的 `computePity` 用單一判定 `r.rankType == rank` 來認定「命中」，並以此同時驅動兩件事：保底計數（`current` / `lastRecordAt`）與平均間隔統計（`hitCount` / `averageInterval`）。

對 4★ 保底（`rank: 4`）而言，這個精確比對代表抽到 **5★ 會被當成「沒中」**，繼續累加 `current`。但 Genshin 的實際機制是：4★ 保底保證的是「**每 N 抽至少出一個 4★ 或以上**」，所以抽到 5★ 也會重置 4★ 保底計數。兩者是各自獨立、但都以「rank ≥ 4」為重置事件的計數器。同理，頌願常駐池（`gachaType` `1000`）的主保底是 3★（threshold 5），其 3★ 保底計數也應被 4★／5★ 重置。

現有測試 `test/services/gacha_pity_test.dart` 的 `rank=4 → counts to last 4★ ignoring 5★`（約 line 89）把這個錯誤行為當成預期寫死了。

## 決策：保底計數修正，平均間隔維持「純該稀有度」

`computePity` 的兩種輸出採用**不同判定**：

| 輸出 | 語意 | 判定 |
|---|---|---|
| `current` / `lastRecordAt` / `progress` / `distance`（保底計數） | 抽到「該稀有度**或以上**」即重置 | `rankType >= rank`（**本次修正**） |
| `hitCount` / `averageInterval`（平均間隔） | 只數「**恰好**該稀有度」 | `rankType == rank`（維持原樣） |

對 `rank = 5`，`>= 5` 等同 `== 5`（沒有更高稀有度），因此 **5★ 保底的所有數字逐位元不變**。只有 4★、3★ 保底的計數會被更高稀有度正確重置。

平均間隔維持「純該稀有度」是使用者的明確選擇：總覽頁與分享卡的「4★ 平均」維持「平均幾抽出一個 4★」的直覺，不把 5★ 也算成一次 4★ 週期結束。

## 實作

### `lib/services/gacha_pity.dart`

1. `computePity` 內改成**兩條獨立掃描**（單次走訪 records 即可同時推進）：
   - 保底計數掃描：以 `rankType >= rank` 認定重置點，產出 `current` 與 `lastRecordAt`。
   - 平均間隔掃描：以 `rankType == rank` 認定命中，產出 `hitCount` 與「距上次精確命中的抽數」。
2. `Pity` 新增欄位 `completedPulls`（int）：落在「已完成的精確週期」內的抽數，即 `records.length − 距上次精確命中的抽數`。
   - `averageInterval = hitCount > 0 ? completedPulls / hitCount : null`。
3. `averageIntervalAcrossBanners` 改用 `p.completedPulls` 累加分子（取代現行的 `entry.value.length − p.current`），使 4★ 跨卡池平均維持純 4★。同步更新該函式上方說明註解。

### 不需要的改動

- **UI 完全不動**：`PityCard`、`overview_sections`、`share_card` 都讀同一批欄位，數值會自動修正。`PityCard` 的 4★ 卡副標題將同時顯示「距上次保底（含 5★ 重置）」與「平均 N 抽出（純 4★）」，符合本決策。
- **保底文案（label）不動**：「4★ 保底」「距上次 4★」等標籤描述的本就是「4★ 或以上」的保底機制，語意正確。
- **Timeline、`buildRecordRows`、稀有度長條的「主稀有度數量」** 都各有獨立的精確比對邏輯，與保底計數無關，不動。

### `test/services/gacha_pity_test.dart`

- 更新 `rank=4 → counts to last 4★ ignoring 5★`：改為驗證「中途 5★ 會重置 4★ 保底計數」（`current` 數到最近的 5★ 而非更舊的 4★），並加註說明為何 5★ 也算重置。
- 新增涵蓋：
  - 4★ 保底計數被中途 5★ 重置（`current` 與 `lastRecordAt` 指向 5★）。
  - 同一份資料下 4★ `averageInterval` 仍只計入恰好 4★ 的命中（純 4★）。
  - `averageIntervalAcrossBanners` 對 4★ 的跨卡池平均不把 5★ 算進命中。

## 驗收條件

- `fvm dart format lib/ test/` 無變更殘留。
- `fvm flutter analyze` 輸出 `No issues found!`。
- `fvm flutter test` 輸出 `All tests passed!`，且涵蓋上述新增／更新的測試。
- `rank = 5` 路徑的既有測試全部維持綠燈（行為不變）。
