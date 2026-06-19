# 時間軸歐非配色設計（對齊姐妹專案 PR #37）

## 背景與目標

時間軸目前以**卡池顏色**上色，整條同色、看不出每次出貨「歐還是非」。本設計改為依
**抽到該筆所花的抽數相對該池保底門檻的比例**，呈現綠（歐）／金（普通）／紅（非）
三階，並把這套歐非色一致延伸到所有「抽數」語意的呈現處，同時調整卡池調色盤避免與
歐非色混淆。

對齊姐妹專案 [wuthering-waves-convene-gacha-analyzer PR #37](https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer/pull/37)
的設計與做法，並依本專案差異調整（保底門檻、頌願卡池、ARB 語系範圍）。

## 分級門檻

| 比例（`pulls / pity`） | 分級 | 顏色 token |
|---|---|---|
| `ratio <= 0.5` | 歐（lucky） | `stateSuccess`（綠） |
| `0.5 < ratio <= 0.8` | 普通（average） | `stateWarning`（金/琥珀） |
| `ratio > 0.8`（含 `> 1`） | 非（unlucky） | `stateDanger`（紅） |

- 門檻 `0.5`／`0.8` 以具名常數定義，附 WHY 註解（綠＝半保底內、紅＝進入軟保底區）。
- `pity <= 0` 防呆視為「非」（避免除以零；正常資料不會發生）。
- 顏色一律**重用既有語意色**、**不新增 token**；中階是金/琥珀（非純黃），刻意接受。

門檻依各卡池保底**自動換算**，本專案各池保底已定義於 `gachaTypes`：

| 卡池 | gacha_type | 主稀有度 | 保底門檻 |
|---|---|---|---|
| 角色活動祈願 | 301 | 5★ | 90 |
| 武器活動祈願 | 302 | 5★ | 80 |
| 集錄祈願 | 500 | 5★ | 90 |
| 常駐祈願 | 200 | 5★ | 90 |
| 新手祈願 | 100 | 5★ | 20 |
| 頌願活動 | 2000 | 5★ | 70 |
| 頌願常駐 | 1000 | 4★ | 70 |

頌願（odes）走同一 `BannerPage`／`TimelineVertical`，自動涵蓋。`頌願常駐` 主稀有度為
4★，故門檻查詢一律用 `pityThresholdFor(gachaType, rank)` 帶 rank，rank 由 entry 的實際
稀有度決定（缺值退回 targetRank）。

## 架構與元件

### 新增：`lib/widgets/luck_palette.dart`

純函式核心，不 import l10n：

```dart
enum LuckTier { lucky, average, unlucky }

/// 依「抽數 / 保底門檻」比例回傳分級。ratio <= 0.5 歐；<= 0.8 普通；其餘（含 > 1）非。
/// pityThreshold <= 0 防呆視為非。
LuckTier luckTierFor(int pulls, int pityThreshold);

/// 將分級映射到既有語意色（綠 / 金 / 紅），不新增 token。
Color luckColorFor(LuckTier tier, GachaTokens t);
```

`luckColorFor`：lucky → `stateSuccess`、average → `stateWarning`、unlucky → `stateDanger`。

### 新增：`lib/widgets/luck_legend.dart`

```dart
/// 分級 → 在地化標籤（供 tooltip 與 LuckLegend 共用）。
String luckTierLabel(LuckTier tier, AppLocalizations l);

/// 歐非色圖例：歐／普通／非 三個色點＋在地化標籤，Wrap 可換行。
class LuckLegend extends StatelessWidget { ... }
```

- 色點樣式對齊既有 `DistributionLegend`（10×10、圓角 2），但**不重用**——後者強制帶
  count／百分比兩欄，不適合純色說明。
- 刻意**不標抽數**——跨池保底門檻不同，標數字會誤導。

### 修改：`lib/data/gacha_types.dart`

新增集中查詢 helper，消除散落各處的 `firstWhere`：

```dart
/// 依 gachaType 字串查 GachaType；查無時回傳帶預設保底（5★90／4★10）的 fallback。
GachaType gachaTypeFor(String gachaType);

/// 查指定卡池、指定 rank 的保底門檻；該池無對應 rank 規則時回傳主保底門檻。
int pityThresholdFor(String gachaType, int rank);
```

- `gachaTypeFor` 的 fallback 沿用 `timeline_vertical.dart` 現有 `_bannerName` 內那組
  （未知 type → `PityRule(5,90)`＋`PityRule(4,10)`，`category: GachaCategory.gacha`）。
  **與姐妹專案不同**：姐妹 fallback 主保底 80，本專案沿用既有 90（原神角色池慣例）。
- 順手把 `timeline_vertical.dart` 的 `_bannerName` 改用 `gachaTypeFor`，移除重複的
  firstWhere-with-fallback。

### 修改：`lib/widgets/cards/timeline_vertical.dart`（總覽頁／分享圖）

- `_EntryRow` 新增 `targetRank` 參數（由 `TimelineVertical.targetRank` 下傳）。
- 顏色計算：
  ```dart
  final rank = entry.sourceRecord?.rankType ?? targetRank;
  final pity = pityThresholdFor(entry.gachaType, rank);
  final tier = luckTierFor(entry.pullsSincePrev, pity);
  final luck = luckColorFor(tier, tokens);
  ```
  `luck` 用於**節點**與**物品名稱文字**（`_nameRow`）。
- meta 行（原 `日期 · 卡池名稱 · N抽`）改用 `Text.rich`：
  - 卡池名稱字串用 `colors.colorFor(entry.gachaType)` 上色（保留「哪個池子」辨識）；
  - 「N 抽」那段套**歐非色**；
  - 日期維持 `textMuted`。
- 節點 `Tooltip` 訊息改為 `{名稱} · {luckTierLabel} · {timelineSinceLast(pulls)}`。
- 新增可選參數 `bool showLuckLegend = false`；為 `true` 時把圖例**釘在卡片底部**：
  - `fillHeight` 時 `container()` 內容區改 `Column[Expanded(裁切內容), LuckLegend]`，
    確保 entries 溢出被裁時圖例仍可見；
  - 非 `fillHeight` 時 `Column[內容, LuckLegend]` 自然排在內容下方。

### 修改：`lib/widgets/cards/timeline_horizontal.dart`（單卡池頁）

- `_EntryColumn` 新增 `targetRank` 參數（由 `TimelineHorizontal.targetRank` 下傳）。
- 顏色計算同上，`luck` 取代原 `accent`，用於**節點**與**物品名稱文字**。
- meta 行 `MM/dd · N抽` 的「N 抽」改用 `Text.rich` 套歐非色，日期維持 muted。
- 節點 `Tooltip` 訊息補上 `分級 · N 抽`（同垂直版格式）。
- 移除已無用的 `colors` 參數（節點/名稱改歐非色後卡池色未用於本元件）。
  - `bannerDistributionEntries` helper 仍保留（供 `DistributionLegend` 分佈圖用），
    其 `BannerColors` 參數不受影響。
- 橫向圖例改走既有 `ChartCard.legend` slot：`banner_page` 在包住時間軸的 `ChartCard`
  傳 `legend: const LuckLegend()`（該 ChartCard 目前無 legend，乾淨新增）。

### 修改：`lib/widgets/data/sortable_table.dart`（記錄列表）

- 「保底內」欄（`row.mainPityIndex`，距上次主稀有度的抽數）改用歐非色：
  ```dart
  luckColorFor(
    luckTierFor(row.mainPityIndex, pityThresholdFor(record.gachaType, widget.mainRank)),
    tokens,
  )
  ```
  `_Row` 為此新增 `mainRank` 欄位（由 `SortableTable.mainRank` 下傳）。
- 「總抽數」欄（`row.totalIndex`，累積序號、非運氣指標）維持 `textMuted`。

### 修改：呼叫端

- `lib/pages/overview_page.dart`：`TimelineVertical(... showLuckLegend: true)`。
- `lib/pages/banner_page.dart`：包橫向時間軸的 `ChartCard` 傳 `legend: const LuckLegend()`；
  `TimelineHorizontal` 不再傳 `colors`。
- `lib/widgets/share/share_card.dart`：`TimelineVertical(... fillHeight: true,
  showLuckLegend: true)`——圖例釘在卡片底部，即使 entries 溢出被裁仍可見。

## 卡池調色盤挪移（避免撞色）

**動機**：本專案 `BannerColors` 與語意色**直接撞 hex**：
- `character` dark `0xFF46B07A` ＝ 歐綠 `stateSuccess`；
- `weapon` dark `0xFFE6736B` ＝ 非紅 `stateDanger`；
- `chronicled` 橘 ≈ 琥珀 `stateWarning`。

歐非色與卡池名稱在 meta 行並存會混淆，故把 8 個卡池色（character / weapon / chronicled
/ standard / beginner / odesEvent / odesStandard / fallback）整體重排到 **cyan → magenta**
弧段，全部避開綠/琥珀/紅；dark 與 light 各一組（色相一致、light 加深）。**未新增任何
token**。

提案色相（exact hex 實作時可微調，唯一硬約束為下方測試）：

| 卡池 | dark | light |
|---|---|---|
| character（青藍） | `0xFF35BFD0` | `0xFF1B92A8` |
| weapon（天藍） | `0xFF4FA3E8` | `0xFF2E6FC0` |
| chronicled（矢車菊藍） | `0xFF6E8BE6` | `0xFF4F5FC0` |
| standard（靛藍） | `0xFF8A7CE0` | `0xFF6A4FC0` |
| beginner（紫羅蘭） | `0xFFA86FD9` | `0xFF8A3FB0` |
| odesEvent（蘭紫） | `0xFFC56FD0` | `0xFFA63FA8` |
| odesStandard（桃紅） | `0xFFD96BA8` | `0xFFB23A7E` |
| fallback（中性，不動） | `0xFF8A92A6` | `0xFF6A7080` |

**約束固化**：`test/widgets/banner_colors_test.dart` 新增斷言「任一卡池色不得等於該主題
的 `stateSuccess`／`stateWarning`／`stateDanger`」（dark + light 各一）。

**取捨**：原 `BannerColors` 註解要求「卡池色避開稀有度 token（5★金/4★紫/3★藍/2★灰）」；
節點改歐非色後卡池色不再上節點、只用於 meta 卡池名稱小字與分佈圖，此約束放寬，改以
**避開歐非色**為主軸；與稀有度 token 的少量色相接近可接受（不同元件、不同語境）。

## 「現在」節點金色共用（已知並接受）

本專案 `stateWarning` ＝ `accentPrimary` ＝ `fiveStar` ＝ `0xFFD6A268`，故「普通」階金色
與時間軸「現在」節點同色。可接受——「現在」是**中空節點＋文字標籤**，視覺可區分；與
姐妹「中階金/琥珀刻意接受」一致。不另做處理。

## tooltip 文案

節點 tooltip 由「只有物品名稱」改為組裝既有片段：

```
{物品名稱} · {分級名稱} · {timelineSinceLast(pulls)}
```

例：`刻晴 · 歐 · 40 抽`。分級名稱取自下方 l10n key，抽數重用既有 `timelineSinceLast`，
不另外新增 tooltip 專用 key。

## 橫向時間軸年/月分隔（對齊垂直版）

本專案橫向時間軸目前**無**年/月分隔（垂直版有）。本次補上，與垂直版一致：

- 每個月份分組（左→右＝新→舊，該月最新一筆為組首）在組首欄**上方標年/月**（重用
  `timelineMonthLabel`），月份**交界畫垂直分隔線**（畫在組首欄左側 `Border`；最左欄＝
  最新月份起點不畫）。
- **節點對齊關鍵**：每欄頂部保留固定高 `_monthBandHeight` 的標籤帶（組首填標籤、其餘
  留白且標籤靠上對齊），**底部以等高 spacer 對稱補回**。置中欄加等高上下 padding 不改變
  其垂直中心，故節點 y 不位移、仍對齊背景軸線；「現在」欄不加帶、不受影響。

## i18n

新增 3 個 key：`luckTierLucky`（歐）／`luckTierAverage`（普通）／`luckTierUnlucky`（非），
**同時用於 `LuckLegend` 標籤與節點 tooltip 分級名稱**。

範圍：新增到**所有實翻 ARB（9 個）**，跳過 22 個空殼 ARB（4-key，留給 Crowdin pipeline）。

實翻 ARB：`app_zh.arb`（zh-Hant 模板）、`app_zh_Hans.arb`、`app_en.arb`、`app_es.arb`、
`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`。

**翻譯與姐妹專案一致**（zh-Hant / zh-Hans / en / ja 逐字對齊姐妹 PR #37）；
`es / fr / pt-BR / th / vi` 姐妹專案無對應，按語意新翻（實作時對照 `docs/術語表.md`）：

| key | zh-Hant | zh-Hans | en | ja | es | fr | pt-BR | th | vi |
|---|---|---|---|---|---|---|---|---|---|
| `luckTierLucky` | 歐 | 欧 | Lucky | 強運 | Con suerte | Chanceux | Sortudo | โชคดี | May mắn |
| `luckTierAverage` | 普通 | 普通 | Average | 普通 | Normal | Normal | Normal | ปกติ | Bình thường |
| `luckTierUnlucky` | 非 | 非 | Unlucky | 不運 | Sin suerte | Malchanceux | Azarado | โชคร้าย | Kém may |

（es/fr/pt-BR/th/vi 為提案，實作時對照術語表定稿。）

- generated l10n 為 gitignore，改完 ARB 後跑 `fvm flutter gen-l10n`。
- 省略號等標點依專案慣例；分級名稱皆無 placeholder。

## 測試

- `test/widgets/luck_palette_test.dart`：`luckTierFor` 各池邊界
  - 90 池：45→歐、46→普通、72→普通、73→非、90→非、91→非。
  - 80 池：40→歐、41→普通、64→普通、65→非。
  - 20 池：10→歐、11→普通、16→普通、17→非。
  - 70 池：35→歐、36→普通、56→普通、57→非。
  - 防呆：`pityThreshold = 0` → 非。
  - `luckColorFor` 對應 `stateSuccess`／`stateWarning`／`stateDanger`。
- `test/data/gacha_types_test.dart`：`gachaTypeFor`（已知 301→角色、未知→fallback 5★90/4★10）、
  `pityThresholdFor`（301 5★→90、302 5★→80、100 5★→20、1000 4★→70、任一 4★→10、未知→90、
  rank 無對應→主保底）。
- `test/widgets/luck_legend_test.dart`：3 標籤皆顯示、色點對應歐非色。
- 既有時間軸 widget 測試：斷言節點/名稱顏色＝歐非色、tooltip 文案、meta「N 抽」歐非色、
  月份分組（含橫向新增）。
- `test/widgets/banner_colors_test.dart`：任一卡池色 ≠ 該主題 stateSuccess/Warning/Danger。
- `test/widgets/data/sortable_table_test.dart`：「保底內」欄歐非色、「總抽數」維持 muted。
- `test/widgets/share/share_card_test.dart`：分享圖呈歐非色、entries 溢出時圖例底部仍在卡片內。

## 驗收條件

- `fvm dart format lib/ test/`、`fvm flutter analyze`（No issues found!）、
  `fvm flutter test`（All tests passed!）全綠。
- 單卡池頁時間軸節點/名稱顏色隨抽數呈綠/金/紅，下方有圖例；橫向有年/月分隔。
- 總覽頁時間軸節點/名稱呈歐非色，meta 卡池名稱以卡池色顯示、「N 抽」呈歐非色，下方有圖例。
- 記錄列表「保底內」欄呈歐非色，「總抽數」維持 muted。
- 節點 tooltip 顯示「名稱 · 分級 · N 抽」。
- 分享圖呈歐非色，且時間軸卡片底部有圖例（即使 entries 溢出被裁仍可見）。
- 卡池調色盤全避開歐非色帶，測試固化不撞色。

## 日誌

本功能為純 UI／顏色呈現，無 I/O、外部 API 或錯誤分支，依專案慣例不額外埋 log。
