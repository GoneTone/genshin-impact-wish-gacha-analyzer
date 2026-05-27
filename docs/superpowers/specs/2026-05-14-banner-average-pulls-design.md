# Spec:各卡池頁顯示「平均幾抽出 1 個」

- 日期:2026-05-14
- 分支:`flutter-rewrite`(預計開新分支實作)
- 來源:使用者要求在各卡池頁 PityCard 旁、以及 OverviewPage 祈願綜合區塊,顯示對應稀有度的平均抽中間隔。

## 1. 背景

`BannerPage` 第一列目前是三聯卡:

1. 主保底 `PityCard`(顯示 `current / threshold`、保底進度、副文字如「距下次保底 12 抽」)
2. 副保底 `PityCard`(若該卡池有副保底)
3. 總抽數 `StatCard`

`OverviewPage` 祈願綜合區塊有三聯 `StatCard`:總抽數、5★ 件數(subtitle「佔總抽 X%」)、4★ 件數(subtitle「佔總抽 X%」)。

`PityCard` 與 `StatCard` 已能呈現「當前 pity」「件數」等瞬時數值,但目前缺少一個歷史性指標:**這個玩家**,平均花幾抽才出 1 個對應稀有度。

## 2. 目標

1. **BannerPage**:在主、副保底 `PityCard` 副文字旁,inline 顯示「平均 N 抽出」,N 保留 2 位小數。
2. **OverviewPage 祈願綜合**:在 5★ 件數 / 4★ 件數 `StatCard` 的 subtitle 後 inline 並接「· 平均 N 抽出」。**跨 5 個祈願卡池(301/302/500/200/100)合併計算**。
3. 計算邏輯與 `Pity` 模型同源,呼叫端不重算。
4. 0 命中時不顯示平均段。
5. 三種顯示語系(`en` / `zh_Hant` / `zh_Hans`)補完文案;其餘語言由 Flutter i18n fallback 到 template(繁中)。

## 3. 非目標(YAGNI)

- 不改既有 `current` / `progress` / `distance` 邏輯。
- 不為 `OverviewPage` 的**頌願綜合**區塊加平均(使用者明確指定只算祈願)。
- 不做間隔中位數 / 標準差等更複雜的統計。
- 不為 `app_zh.arb` / `ja` / `fr` / `es` / `pt` / `th` / `vi` 補新 key —— 由 i18n fallback 到 `zh_Hant` template。

## 4. 設計

### 4.1 計算定義

每一個「目標稀有度命中」對應一個「保底內第幾抽」(自上一個同稀有度命中之後第幾抽抽到)。
平均 = 全部命中的「保底內幾抽」加總 ÷ 命中次數。

等價數學形式(`records` 為新→舊順序,`current` = 從最新往舊數到第一個命中前的未中數):

```
averageInterval = (records.length − current) / hitCount     (hitCount ≥ 1)
                  null                                       (hitCount == 0)
```

**驗證範例**:三個 5★ 各自保底內 72 / 25 / 40 抽 → 平均 = (72+25+40)/3 = **45.67**。

**邊界**:

| 情境 | `current` | `hitCount` | `averageInterval` |
|---|---|---|---|
| `records.isEmpty` | 0 | 0 | `null` |
| 有抽但無命中 | `total` | 0 | `null` |
| 1 件命中、之後 5 抽未中 | 5 | 1 | `1.0`(對應「保底內 1 抽就出」) |
| n 件命中 | 與舊邏輯一致 | n | `(total−current)/n` |

回傳型別為 `double?`,UI 端用 `.toStringAsFixed(2)` 格式化。**不**在 service 層做 round。

### 4.2 資料模型:`Pity` 加兩個欄位

`lib/services/wish_pity.dart`:

```dart
class Pity {
  const Pity({
    required this.current,
    required this.threshold,
    required this.lastRecordAt,
    required this.averageInterval,
    required this.hitCount,
  });

  final int current;
  final int threshold;
  final DateTime? lastRecordAt;

  /// 已落地週期的平均抽數,hitCount == 0 時為 null。
  final double? averageInterval;

  /// 該 rank 在 records 中的總命中次數。
  final int hitCount;

  // 既有 progress / distance getter 不變
}
```

### 4.3 `computePity` 邏輯

把原本「遇到第一個命中就 `break`」改寫為「掃完整個 records,順便統計 `hitCount`」:

```dart
Pity computePity(List<WishRecord> records, {required int threshold, int rank = 5}) {
  var current = 0;
  var hitCount = 0;
  DateTime? lastAt;
  for (final r in records) {
    if (r.rankType == rank) {
      lastAt ??= r.time;  // 首次命中後鎖定(等同原 break 後不再賦值)
      hitCount++;
    } else if (lastAt == null) {
      current++;          // 只在尚未命中之前累加(等同原 break 前的行為)
    }
  }
  final averageInterval = hitCount > 0
      ? (records.length - current) / hitCount
      : null;
  return Pity(
    current: current,
    threshold: threshold,
    lastRecordAt: lastAt,
    averageInterval: averageInterval,
    hitCount: hitCount,
  );
}
```

**不變式**:`current` 與 `lastRecordAt` 的計算結果與舊版完全一致(原本 `break` 等同於「在第一次命中後不再累加 current」,新版用 `else if (lastAt == null)` 達到相同效果)。

### 4.4 PityCard 副文字呈現

`lib/widgets/cards/pity_card.dart` 的 `_Subtitle`:把單一 `Text` 改為 `Text.rich` 讓「狀態文字」與「· 平均 N 抽出」inline 並接,且窄畫面能自動換行。

文字組合規則:

| `_Phase` | 狀態文字 | 是否串接「· 平均」 |
|---|---|---|
| `normal`(`lastRecordAt == null`) | `pityNoMainRarity(rank)`(「暫無 N★」) | ❌(此時 hitCount=0) |
| `normal`(有命中過) | `pityDistance(distance)` | ✅ `hitCount ≥ 1` 時 |
| `close` | `pityClose(distance)` | ✅ |
| `guaranteed` | `pityGuaranteed` | ✅ |
| `ended`(新手池) | `pityBeginnerEnded` | ✅ `hitCount ≥ 1` 時 |

**顏色**:狀態文字的警示色保持原邏輯(`stateWarning` / `textMuted`),平均段一律用 `tokens.textMuted`,避免警示色被中性資訊稀釋。

**範例輸出**(主保底 5★ 卡):

- normal: `距下次保底 12 抽 · 平均 70.50 抽出`
- close: `快保底了!剩餘 8 抽 · 平均 70.50 抽出`
- guaranteed: `保底中 · 平均 70.50 抽出`
- ended: `已結束 · 平均 12.33 抽出`
- 暫無 5★:`暫無 5★`(不接平均)

### 4.5 i18n

範圍:**僅 3 份 ARB 動 key**,其餘 7 份由 Flutter gen-l10n fallback 到 `zh_Hant`(template)。

| 檔案 | 新增 key |
|---|---|
| `lib/l10n/app_zh_Hant.arb`(template) | `"pityAverageInterval": "平均 {n} 抽出"` |
| `lib/l10n/app_zh_Hans.arb` | `"pityAverageInterval": "平均 {n} 抽出"` |
| `lib/l10n/app_en.arb` | `"pityAverageInterval": "Avg {n} pulls"` |

`placeholders` 用 `String`(對齊既有 `statsShareOfTotal`),UI 端先 `pity.averageInterval!.toStringAsFixed(2)` 再傳入。

不動的 ARB:`app_zh.arb`、`app_ja.arb`、`app_fr.arb`、`app_es.arb`、`app_pt.arb`、`app_th.arb`、`app_vi.arb`。

> **副作用**:這 7 個語系暫時會在這一行 fallback 顯示繁中。可接受 —— 使用者明確同意。

### 4.6 BannerPage 呼叫端

`lib/widgets/cards/pity_card.dart` 的 `_Subtitle.build` 內,從 `widget.pity` 讀 `averageInterval` 與 `hitCount`,組裝 `Text.rich` 的 spans。

`lib/pages/banner_page.dart` 不動(已透過 `computePity` 取得 `Pity` 並傳入 `PityCard`)。

`lib/widgets/cards/banner_top_rarity_bars.dart` 不動(只讀 `current`)。

### 4.7 OverviewPage 跨卡池平均

#### 4.7.1 跨卡池 helper

`lib/services/wish_pity.dart` 新增 helper(命名對齊既有的 `pullsSinceLastRankedAcrossBanners` / `buildTimelineEntriesAcrossBanners`):

```dart
/// 跨卡池合併平均:對每個卡池各自算 (records.length − current) 與 hitCount,
/// 把分子分母分別累加再相除。與單卡池 [Pity.averageInterval] 語意一致。
///
/// 每個卡池各算各的 `current`,不會把多個卡池「未命中當前 pity」合計進分子。
double? crossBannerAverageInterval(
  Map<String, List<WishRecord>> banners, {
  required int Function(String gachaType) rankFor,
}) {
  var sumCompleted = 0;
  var sumHits = 0;
  for (final entry in banners.entries) {
    final p = computePity(
      entry.value,
      threshold: 0,  // 跨卡池不需要 pity progress/distance,此欄位被忽略
      rank: rankFor(entry.key),
    );
    sumCompleted += entry.value.length - p.current;
    sumHits += p.hitCount;
  }
  return sumHits > 0 ? sumCompleted / sumHits : null;
}
```

> **`threshold: 0` 註記**:`computePity` 必填 `threshold`,但跨卡池場景不用 `Pity.progress` / `distance`。傳 0 是 sentinel,helper 內加註解說明。若日後 `Pity` 介面再演化,可考慮把 threshold 改為可選或拆出 `_scanPity` 內部函式。本次 YAGNI 不做。

#### 4.7.2 OverviewPage 呼叫端

`lib/pages/overview_page.dart` 的 `build` 內,只動**祈願綜合**區塊(頌願不動):

```dart
final wish5StarAvg = crossBannerAverageInterval(
  wishBanners,
  rankFor: (_) => 5,
);
final wish4StarAvg = crossBannerAverageInterval(
  wishBanners,
  rankFor: (_) => 4,
);

String _shareSubtitle(double rate, double? avg) {
  final share = l.statsShareOfTotal(rate.toStringAsFixed(2));
  if (avg == null) return share;
  return '$share · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
}

final wishStatCards = <Widget>[
  StatCard(label: l.statsTotal, value: '${wishStats.total}', accent: tokens.accentPrimary),
  StatCard(
    label: l.statsFiveStarCount,
    value: '${wishStats.fiveStarCount}',
    accent: tokens.fiveStar,
    subtitle: _shareSubtitle(wishStats.fiveStarRate * 100, wish5StarAvg),
  ),
  StatCard(
    label: l.statsFourStarCount,
    value: '${wishStats.fourStarCount}',
    accent: tokens.fourStar,
    subtitle: _shareSubtitle(wishStats.fourStarRate * 100, wish4StarAvg),
  ),
];
```

字串拼接 `'$share · $avg'` 直接寫在 Dart code 中。理由:
- `·` 分隔符 OverviewPage / banner_top_rarity_bars 已用過,風格一致
- 兩段 i18n key 都是獨立完整片語,合併不需新 key
- 若日後英文需要逗號分隔之類,再開新 i18n key 也不遲(YAGNI)

`StatCard` 的 `subtitle` 是單行 `Text`,寬度不足會 ellipsis。**接受**:OverviewPage 三聯卡與 wishStats 兩張卡共用同樣 grid,寬度足夠(實測 zh_Hant: 「佔總抽 5.23% · 平均 70.50 抽出」約 25 字)。若窄畫面 ellipsis 只截掉「平均」段,主要數值仍可見。

#### 4.7.3 頌願綜合區塊

`odesStatCards` 完全不動。

## 5. 測試

### 5.1 `test/services/wish_pity_test.dart`

新增測試 group `averageInterval / hitCount`:

| Test case | records(新→舊) | 期望 |
|---|---|---|
| 空 records | `[]` | `current=0, hitCount=0, averageInterval=null` |
| 有抽無命中(查 rank=5) | `[4★×10]` | `current=10, hitCount=0, averageInterval=null` |
| 最舊抽即 5★ | `[未中×4, 5★]`(5 筆) | `current=4, hitCount=1, averageInterval=1.0` |
| 兩件命中 | `[未中×3, 5★, 未中×7, 5★]`(12 筆) | `current=3, hitCount=2, averageInterval=4.5` |
| 最新抽即 5★ | `[5★, 未中×5]`(6 筆) | `current=0, hitCount=1, averageInterval=6.0` |
| rank=4 查詢 | `[未中×3, 4★, 未中×2, 5★]`(7 筆) | rank=4 查詢:`current=3, hitCount=1, averageInterval=4.0` |
| 帶小數 | `[5★, 未中×3, 5★, 未中×4, 5★]`(10 筆) | `current=0, hitCount=3, averageInterval≈3.333…`(`toStringAsFixed(2)` = `"3.33"`) |

既有測試保持綠,確認 `current` / `lastRecordAt` / `progress` / `distance` 不受影響。

### 5.2 `test/widgets/cards/pity_card_test.dart`

新增 widget test:

1. `hitCount == 0` → 副文字**不含**「· 平均」段。
2. `hitCount ≥ 1` + normal phase + `averageInterval == 70.5` → 副文字為「距下次保底 N 抽 · 平均 70.50 抽出」。
3. `hitCount ≥ 1` + guaranteed phase → 副文字為「保底中 · 平均 70.50 抽出」(平均段一律 `textMuted` 顏色)。

### 5.3 `test/services/wish_pity_test.dart` 跨卡池

新增 `crossBannerAverageInterval` group:

| Test case | banners 構造 | rankFor | 期望 |
|---|---|---|---|
| 全空 | `{'301': [], '302': []}` | `(_) => 5` | `null` |
| 單卡池有命中 | `{'301': [未中×3, 5★, 未中×7, 5★]}` (12 筆) | `(_) => 5` | (8+1)/2 = `4.5` |
| 多卡池合併 | `{'301': [未中×4, 5★], '302': [未中×3, 5★, 未中×7, 5★]}` | `(_) => 5` | (1+9)/(1+2) = `3.333...` |
| 空卡池被略過 | `{'301': [], '302': [未中×4, 5★]}` | `(_) => 5` | `1.0`(sumHits=1, sumCompleted=1) |
| 不同 rankFor | 同上「多卡池合併」 | `(_) => 4`(假設全無 4★) | `null` |

### 5.4 OverviewPage widget 級驗證

不單獨新增 OverviewPage 測試檔案(若不存在則不新建)。`crossBannerAverageInterval` 的單測 + `StatCard` subtitle 顯示行為,已能覆蓋這條路徑。

## 6. 提交前品質檢查

依 `CLAUDE.md`:

1. `dart format lib/ test/`
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`
4. `flutter gen-l10n`(template-arb-file 變動後重生 `app_localizations*.dart`)—— 確認 gen 結果與 arb 對得上。

## 7. 風險與權衡

- **未匯入歷史**:若 records 不是從遊戲第 1 抽起完整匯入,最舊的命中之前的「未匯入歷史」會被算進該命中的保底內,平均會偏高一點。可接受,使用者匯入的就是「有資料的範圍」。
- **i18n 不一致**:7 個語系在這一行會 fallback 顯示繁中。已徵得同意。
- **`Pity` 物件多 2 個欄位**:序列化點不存在(`Pity` 只在執行期計算、不入庫),無向後相容問題。
