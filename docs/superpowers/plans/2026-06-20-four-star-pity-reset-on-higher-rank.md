# 4★ 保底計數應被更高稀有度重置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 `computePity`，使「rank 或以上」的抽卡會重置該 rank 的保底計數（4★ 保底被 5★ 重置；3★ 保底被 4★／5★ 重置），同時讓平均間隔統計維持「只計入恰好該稀有度」。

**Architecture:** `computePity` 內改為單次走訪、兩條獨立累加：保底計數以 `rankType >= rank` 為重置點（產出 `current`／`lastRecordAt`），平均間隔以 `rankType == rank` 為命中（產出 `hitCount` 與距上次精確命中的抽數）。`Pity` 新增 `completedPulls` 欄位承載「已完成精確週期的抽數」，供單卡池與跨卡池平均共用。對 `rank=5` 兩條掃描等價，行為逐位元不變。

**Tech Stack:** Dart／Flutter（FVM 釘版），`flutter_test`。

## Global Constraints

- 指令一律優先 `fvm flutter` / `fvm dart`，找不到 `fvm` 才退回 `flutter` / `dart`。
- 提交前依序通過：`fvm dart format lib/ test/`（**不要對 `.` 跑**）、`fvm flutter analyze`（須 `No issues found!`）、`fvm flutter test`（須 `All tests passed!`）。任一失敗先修，不得 `--no-verify`。
- 專案有 pre-commit 品質閘，**失敗測試的步驟不可 commit**；commit 只在全綠後發生。
- 所有宣告（含 private、新增欄位）寫一行 `///` dartdoc。
- 程式碼註解／dartdoc 用繁體中文 (台灣) 全形標點；省略號用半形 `...`。
- Commit message 用英文、半形標點、conventional commits 格式。
- 不要主動 `git push`。
- 純計算函式不需埋 log（CLAUDE.md 的 log 規則針對 I/O／外部 API／Rust bridge）。

---

### Task 1: 寫下會失敗的測試（RED）

修正既有「把舊 bug 寫死」的測試，並新增涵蓋「5★ 重置 4★ 計數」「4★ 平均維持純 4★」「跨卡池 4★ 平均不含 5★」的測試。本任務只動 `gacha_pity_test.dart`，其斷言全透過 `computePity` / `averageIntervalAcrossBanners`，不直接建構 `Pity`，因此能對舊實作編譯並在斷言處失敗（正確的 RED）。**本任務結尾不 commit。**

**Files:**
- Test: `test/services/gacha_pity_test.dart`

**Interfaces:**
- Consumes: `computePity(List<GachaRecord>, {required int threshold, int rank})` → `Pity{current, threshold, lastRecordAt, averageInterval, hitCount}`；`averageIntervalAcrossBanners(Map<String, List<GachaRecord>>, {required int Function(String) rankFor})` → `double?`。皆為現有簽名（Task 2 僅新增 `Pity.completedPulls` 欄位，不改這兩個簽名）。
- Produces: 無（純測試）。

- [ ] **Step 1: 改寫既有 `rank=4 → counts to last 4★ ignoring 5★` 測試**

在 `test/services/gacha_pity_test.dart` 找到該測試（`test('rank=4 → counts to last 4★ ignoring 5★', () { ... });`，約 line 89–147），**整段替換**為下列新測試。記錄序（新→舊）維持 `3★, 5★, 3★, 4★, 3★`，但預期改為「5★ 會重置 4★ 計數」：`current` 數到最近的 5★（id `4`）而非更舊的 4★（id `2`）。

```dart
    test('rank=4 → 5★ 會重置 4★ 保底計數', () {
      // records (新→舊): 3★, 5★, 3★, 4★, 3★
      // 4★ 保底保證「4★ 或以上」，故中途的 5★ 也是重置點：
      // current 只數到最近的 5★（id '4'），而非更舊的 4★（id '2'）。
      final records = [
        GachaRecord(
          id: '5',
          uid: '1',
          gachaType: '301',
          name: 'a',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 5),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '4',
          uid: '1',
          gachaType: '301',
          name: 'b',
          itemType: '角色',
          rankType: 5,
          time: DateTime(2025, 1, 4),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '3',
          uid: '1',
          gachaType: '301',
          name: 'c',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 3),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '2',
          uid: '1',
          gachaType: '301',
          name: 'd',
          itemType: '角色',
          rankType: 4,
          time: DateTime(2025, 1, 2),
          lang: 'zh-tw',
        ),
        GachaRecord(
          id: '1',
          uid: '1',
          gachaType: '301',
          name: 'e',
          itemType: '角色',
          rankType: 3,
          time: DateTime(2025, 1, 1),
          lang: 'zh-tw',
        ),
      ];
      final p = computePity(records, threshold: 10, rank: 4);
      // 保底計數被 5★ 重置：最近的 3★ 之後遇到 5★ → current=1、lastRecordAt=1/4。
      expect(p.current, 1);
      expect(p.lastRecordAt, DateTime(2025, 1, 4));
      // 平均維持純 4★：只有 id '2' 是恰好 4★，5★ 不算 4★ 命中。
      // 距上次精確 4★ 命中 = 3 抽（3★,5★,3★）→ completed=5-3=2 → avg=2.0。
      expect(p.hitCount, 1);
      expect(p.averageInterval, 2.0);
    });
```

- [ ] **Step 2: 新增「4★ 平均維持純 4★（即使有 5★）」測試**

在同一 `group('computePity', ...)` 內、上一測試之後加入：

```dart
    test('rank=4 → averageInterval 只計入恰好 4★（5★ 不算命中）', () {
      // records (新→舊): 4★, 3★, 5★, 3★, 4★, 3★
      final records = [
        _r(id: '6', rank: 4, time: DateTime(2025, 1, 6)),
        _r(id: '5', rank: 3, time: DateTime(2025, 1, 5)),
        _r(id: '4', rank: 5, time: DateTime(2025, 1, 4)),
        _r(id: '3', rank: 3, time: DateTime(2025, 1, 3)),
        _r(id: '2', rank: 4, time: DateTime(2025, 1, 2)),
        _r(id: '1', rank: 3, time: DateTime(2025, 1, 1)),
      ];
      final p = computePity(records, threshold: 10, rank: 4);
      // 計數：最新即 4★ → current=0。
      expect(p.current, 0);
      // 命中只算 2 個 4★（非 3 個含 5★）；completed=6 → avg=3.0。
      // 若誤把 5★ 也當 4★ 命中，hitCount 會是 3、avg 會是 2.0。
      expect(p.hitCount, 2);
      expect(p.averageInterval, 3.0);
    });
```

- [ ] **Step 3: 新增「跨卡池 4★ 平均不含 5★」測試**

在 `group('averageIntervalAcrossBanners', ...)` 內加入：

```dart
    test('rankFor=4 → 跨卡池平均只計入恰好 4★（5★ 不算命中）', () {
      // '301' (新→舊): 4★, 5★, 4★ → 純4★命中=2、completed=3
      // '302' (新→舊): 3★, 4★      → 純4★命中=1、completed=1
      // 合併 = (3+1)/(2+1) = 4/3
      final r301 = [
        _r(id: '301-3', rank: 4, time: DateTime(2025, 1, 3)),
        _r(id: '301-2', rank: 5, time: DateTime(2025, 1, 2)),
        _r(id: '301-1', rank: 4, time: DateTime(2025, 1, 1)),
      ];
      final r302 = [
        _r(id: '302-2', rank: 3, time: DateTime(2025, 2, 2)),
        _r(id: '302-1', rank: 4, time: DateTime(2025, 2, 1)),
      ];
      final result = averageIntervalAcrossBanners({
        '301': r301,
        '302': r302,
      }, rankFor: (_) => 4);
      expect(result, closeTo(4 / 3, 1e-9));
    });
```

- [ ] **Step 4: 跑這三個測試，確認失敗（RED）**

Run: `fvm flutter test test/services/gacha_pity_test.dart`
Expected: FAIL。`rank=4 → 5★ 會重置 4★ 保底計數` 在 `expect(p.current, 1)`（舊實作得 3）失敗；`averageInterval` 相關斷言失敗；跨卡池測試在 `closeTo(4/3)`（舊實作得 1.0）失敗。其餘既有測試仍 PASS。

> 不要在本任務 commit（測試目前為紅，pre-commit 閘會擋）。

---

### Task 2: 實作雙掃描修正並轉綠（GREEN）

修改 `computePity` 為雙掃描、`Pity` 新增 `completedPulls`、`averageIntervalAcrossBanners` 改用 `completedPulls`；同步補 `pity_card_test.dart` 的 9 個 `Pity(...)` 建構以維持編譯。全綠後一次提交。

**Files:**
- Modify: `lib/services/gacha_pity.dart`（`Pity` 建構式與欄位、`computePity`、`averageIntervalAcrossBanners`）
- Modify: `test/widgets/cards/pity_card_test.dart`（9 個 `Pity(...)` 補 `completedPulls`）
- Test: `test/services/gacha_pity_test.dart`（Task 1 已備）

**Interfaces:**
- Produces: `Pity` 新增 `final int completedPulls;`，建構式新增 `required this.completedPulls`。`computePity` 與 `averageIntervalAcrossBanners` 簽名不變。

- [ ] **Step 1: `Pity` 新增 `completedPulls` 欄位**

在 `lib/services/gacha_pity.dart` 的 `Pity` 建構式（約 line 9–15）新增必填參數：

```dart
  /// 建立 [Pity]。
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastRecordAt,
    required this.averageInterval,
    required this.hitCount,
    required this.completedPulls,
  });
```

並在 `hitCount` 欄位宣告（約 line 30）之後新增欄位與 dartdoc：

```dart
  /// 該 rank 在 records 中的總命中次數。
  final int hitCount;

  /// 落在「已完成的精確（== rank）週期」內的抽數，即 records.length 減去距上次
  /// 精確命中的抽數。單卡池 [averageInterval] 由 completedPulls / hitCount 得出，
  /// 跨卡池 [averageIntervalAcrossBanners] 亦累加各卡池的 completedPulls 當分子。
  final int completedPulls;
```

- [ ] **Step 2: 改寫 `computePity` 為雙掃描**

將 `computePity`（約 line 46–73）整段替換為：

```dart
/// 計算單一卡池對指定 [rank] 的保底狀態。預設 rank=5，4★ pity 傳 rank=4。
///
/// 保底計數（[Pity.current]／[Pity.lastRecordAt]）以「rankType ≥ rank」為重置點：
/// Genshin 的 4★ 保底保證的是「4★ 或以上」，故抽到 5★ 也會重置 4★ pity；3★ 保底
/// 同理被 4★／5★ 重置。對 rank=5 沒有更高稀有度，行為與精確比對相同。
///
/// 平均間隔（[Pity.averageInterval]／[Pity.hitCount]）則只計入「恰好等於 rank」的
/// 命中，維持「平均幾抽出一個該稀有度」的語意，不把更高稀有度算成一次週期結束。
Pity computePity(
  List<GachaRecord> records, {
  required int threshold,
  int rank = 5,
}) {
  // 保底計數：抽到「rank 或以上」即重置。
  var current = 0;
  DateTime? lastAt;
  // 平均間隔：只數「恰好等於 rank」的命中，sinceLastExact 為距上次精確命中的抽數。
  var sinceLastExact = 0;
  var hitCount = 0;
  var exactSeen = false;

  for (final r in records) {
    if (lastAt == null) {
      if (r.rankType >= rank) {
        lastAt = r.time; // 首個「rank 或以上」後鎖定保底計數
      } else {
        current++;
      }
    }
    if (r.rankType == rank) {
      hitCount++;
      exactSeen = true;
    } else if (!exactSeen) {
      sinceLastExact++;
    }
  }

  final completedPulls = records.length - sinceLastExact;
  final averageInterval = hitCount > 0 ? completedPulls / hitCount : null;
  return Pity(
    current: current,
    threshold: threshold,
    lastRecordAt: lastAt,
    averageInterval: averageInterval,
    hitCount: hitCount,
    completedPulls: completedPulls,
  );
}
```

- [ ] **Step 3: `averageIntervalAcrossBanners` 改用 `completedPulls`**

將該函式（約 line 75–91）整段替換為：

```dart
/// 跨卡池合併平均：對每個卡池各自算 [Pity.completedPulls] 與 [Pity.hitCount]，
/// 把分子分母分別累加再相除。與單卡池 [Pity.averageInterval] 語意一致（只計入恰好
/// 等於目標 rank 的命中），每個卡池各算各的 completedPulls，不會把多個卡池的未命中
/// 抽數合計進分子。
double? averageIntervalAcrossBanners(
  Map<String, List<GachaRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  var sumCompleted = 0;
  var sumHits = 0;
  for (final entry in banners.entries) {
    // threshold: 0 — 跨卡池場景不需要 pity progress/distance，此參數被忽略。
    final p = computePity(entry.value, threshold: 0, rank: rankFor(entry.key));
    sumCompleted += p.completedPulls;
    sumHits += p.hitCount;
  }
  return sumHits > 0 ? sumCompleted / sumHits : null;
}
```

- [ ] **Step 4: 補 `pity_card_test.dart` 的 9 個 `Pity(...)` 建構**

`PityCard` 不讀 `completedPulls`（它只看 current／threshold／progress／distance／averageInterval／hitCount／lastRecordAt），但建構式新增必填欄位後這些 fixture 需補上才能編譯。對 `test/widgets/cards/pity_card_test.dart` 內**每一個** `Pity(...)`（line 19、41、64、87、94、101、125、149、171，共 9 處），在 `hitCount: ...,` 之後加一行 `completedPulls: 0,`（此值不影響卡片渲染，0 表示「此測試不關心」）。

範例（以 line 19 那個為例）：

```dart
    final pity = const Pity(
      current: 12,
      threshold: 90,
      lastRecordAt: null,
      averageInterval: null,
      hitCount: 0,
      completedPulls: 0,
    );
```

其餘 8 處比照辦理：在各自的 `hitCount: <值>,` 下方插入 `completedPulls: 0,`。

- [ ] **Step 5: 跑 `gacha_pity_test.dart`，確認轉綠**

Run: `fvm flutter test test/services/gacha_pity_test.dart`
Expected: PASS（含 Task 1 改寫與新增的測試，及所有既有 rank=5 測試）。

- [ ] **Step 6: 跑 `pity_card_test.dart`，確認仍綠**

Run: `fvm flutter test test/widgets/cards/pity_card_test.dart`
Expected: PASS（fixture 補欄位後渲染行為不變）。

- [ ] **Step 7: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 顯示重新格式化或「unchanged」；無非預期改動。

- [ ] **Step 8: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 10: 提交**

```bash
git add lib/services/gacha_pity.dart test/services/gacha_pity_test.dart test/widgets/cards/pity_card_test.dart
git commit -m "fix(pity): reset N-star pity counter on higher-rank pulls"
```

---

## Self-Review

**Spec coverage：**
- 「保底計數以 `>= rank` 重置」→ Task 2 Step 2（`computePity` 雙掃描）。
- 「平均間隔維持 `== rank`」→ Task 2 Step 2（`hitCount`／`sinceLastExact`）＋ Task 1 Step 2 驗證。
- 「`Pity` 新增 `completedPulls`」→ Task 2 Step 1。
- 「`averageIntervalAcrossBanners` 改用 `completedPulls`」→ Task 2 Step 3＋ Task 1 Step 3 驗證。
- 「更新 line-89 測試（移除寫死的舊行為）」→ Task 1 Step 1。
- 「新增 4★ 計數被 5★ 重置／4★ 平均維持純 4★／跨卡池不含 5★」→ Task 1 Step 1–3。
- 「rank=5 行為不變」→ Task 2 Step 5/9（既有 5★ 測試維持綠燈）。
- 「UI／文案不動」→ 計畫未觸碰 `PityCard`／`overview_sections`／`share_card` 的邏輯，僅補 fixture 必填欄位。
- 驗收條件（format／analyze／test 全綠）→ Task 2 Step 7–9。

**Placeholder scan：** 無 TBD／TODO／模糊步驟；所有程式碼步驟皆附完整程式碼與精確指令。

**Type consistency：** `completedPulls`（int）在 Task 2 Step 1 定義、Step 2 產出、Step 3 消費，命名一致；`computePity`／`averageIntervalAcrossBanners` 簽名全程不變，與 Task 1 測試一致。
