# Timeline Luck Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 時間軸（及所有「抽數」語意呈現處）依「抽數 / 該池保底」比例呈綠（歐）／金（普通）／紅（非）三階色，並把卡池調色盤移出歐非色帶、補橫向年/月分隔。

**Architecture:** 新增純函式 `luckTierFor`／`luckColorFor`（`luck_palette.dart`）與在地化標籤＋圖例 widget（`luck_legend.dart`）；`gacha_types.dart` 新增集中查詢 helper `gachaTypeFor`／`pityThresholdFor`。兩個時間軸 widget 與記錄列表把抽數相關顏色換成歐非色；卡池調色盤整體移到 cyan→magenta 弧段。

**Tech Stack:** Flutter／Dart、FVM 釘版、Riverpod、flutter gen-l10n（ARB i18n）。

## Global Constraints

- 回答與設計文件用繁體中文 (台灣)；CJK 全形標點，但**省略號一律用 ASCII `...`**。
- commit message／PR 標題用英文、conventional commits。
- 所有 Flutter／Dart 指令優先用 `fvm`（找不到才退回 `flutter`／`dart`）。
- 嚴禁重複造輪子：顏色重用既有 `GachaTokens.stateSuccess`／`stateWarning`／`stateDanger`，**不新增 token**；查詢集中到 `gachaTypeFor`／`pityThresholdFor`。
- 所有宣告（含 private）寫一行 `///` dartdoc（Flutter override 例外）。
- 純 UI 顏色呈現，**不埋 log**。
- 不改 `TimelineEntry` 資料模型；不新增設定選項。
- 分級門檻（具名常數，verbatim）：`ratio <= 0.5` 歐、`0.5 < ratio <= 0.8` 普通、`ratio > 0.8` 非；`ratio = pulls / pityThreshold`。
- 未知卡池 fallback 保底為 `5★90 / 4★10`（原神慣例，**非**姐妹的 80）。
- 提交前依序 `fvm dart format lib/ test/`、`fvm flutter analyze`（No issues found!）、`fvm flutter test`（All tests passed!）全綠；不要 `--no-verify`；不要主動 push。
- 已在分支 `feat/timeline-luck-color`，spec 已 commit。

## File Structure

| 檔案 | 責任 |
|---|---|
| `lib/data/gacha_types.dart`（改） | 新增 `gachaTypeFor` / `pityThresholdFor` 查詢 helper |
| `lib/widgets/luck_palette.dart`（新） | `LuckTier` enum、`luckTierFor`、`luckColorFor` 純函式 |
| `lib/widgets/luck_legend.dart`（新） | `luckTierLabel`、`LuckLegend` widget |
| `lib/l10n/app_*.arb`（改 ×9） | 3 個歐非分級 key |
| `lib/widgets/cards/timeline_horizontal.dart`（改） | 節點/名稱/抽數歐非色、tooltip、移除 colors、年/月帶 |
| `lib/widgets/cards/timeline_vertical.dart`（改） | 節點/名稱/抽數歐非色、meta Text.rich、tooltip、`showLuckLegend` |
| `lib/widgets/data/sortable_table.dart`（改） | 「保底內」欄歐非色 |
| `lib/widgets/banner_colors.dart`（改） | 卡池調色盤移到 cyan→magenta |
| `lib/pages/overview_page.dart`（改） | `TimelineVertical(showLuckLegend: true)` |
| `lib/pages/banner_page.dart`（改） | `ChartCard(legend: LuckLegend())`、移除 `colors` |
| `lib/widgets/share/share_card.dart`（改） | `TimelineVertical(showLuckLegend: true)` |

---

### Task 1: `gacha_types.dart` 集中查詢 helper

**Files:**
- Modify: `lib/data/gacha_types.dart`（檔尾、`convertibleGachaTypes` 之後新增 top-level 函式）
- Test: `test/data/gacha_types_test.dart`（既有檔，`void main()` 內新增 group）

**Interfaces:**
- Produces:
  - `GachaType gachaTypeFor(String gachaType)` — 查 `gachaTypes`，查無回傳帶 `5★90/4★10`、`category: GachaCategory.gacha` 的 fallback。
  - `int pityThresholdFor(String gachaType, int rank)` — 回傳該池該 rank 保底門檻；rank 無對應時回傳主保底門檻。

- [ ] **Step 1: 寫失敗測試**（在 `test/data/gacha_types_test.dart` 的 `void main() {` 內，既有 group 之後新增）

```dart
  group('gachaTypeFor', () {
    test('已知 gachaType 回傳對應 GachaType', () {
      expect(gachaTypeFor('301').nameKey, 'gachaTypeCharacter');
      expect(gachaTypeFor('1000').nameKey, 'gachaTypeOdesStandard');
    });

    test('未知 gachaType 回傳 fallback（5★90 / 4★10 / gacha）', () {
      final t = gachaTypeFor('999');
      expect(t.gachaType, '999');
      expect(t.primaryPity.threshold, 90);
      expect(t.secondaryPity!.threshold, 10);
      expect(t.category, GachaCategory.gacha);
    });
  });

  group('pityThresholdFor', () {
    test('角色池 5★ → 90', () => expect(pityThresholdFor('301', 5), 90));
    test('武器池 5★ → 80', () => expect(pityThresholdFor('302', 5), 80));
    test('新手池 5★ → 20', () => expect(pityThresholdFor('100', 5), 20));
    test('頌願活動 5★ → 70', () => expect(pityThresholdFor('2000', 5), 70));
    test('頌願常駐 4★ → 70', () => expect(pityThresholdFor('1000', 4), 70));
    test('一般祈願 4★ → 10', () => expect(pityThresholdFor('301', 4), 10));
    test('未知池 5★ → fallback 90', () => expect(pityThresholdFor('999', 5), 90));
    test('rank 無對應回傳主保底門檻', () {
      expect(pityThresholdFor('301', 3), 90); // 角色池主保底 5★90
      expect(pityThresholdFor('1000', 5), 70); // 頌願常駐主保底 4★70
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/data/gacha_types_test.dart`
Expected: FAIL（`gachaTypeFor` / `pityThresholdFor` 未定義）

- [ ] **Step 3: 實作**（`lib/data/gacha_types.dart` 結尾，`convertibleGachaTypes` 之後新增）

```dart

/// 依 [gachaType] 字串查 [GachaType]；查無時回傳帶預設保底（5★90／4★10、
/// 一般祈願分類）的 fallback。沿用 timeline 既有的未知卡池保底假設。
GachaType gachaTypeFor(String gachaType) => gachaTypes.firstWhere(
  (t) => t.gachaType == gachaType,
  orElse: () => GachaType(
    gachaType: gachaType,
    nameKey: gachaType,
    category: GachaCategory.gacha,
    pities: const [
      PityRule(rank: 5, threshold: 90),
      PityRule(rank: 4, threshold: 10),
    ],
  ),
);

/// 查 [gachaType] 池中 [rank] 的保底門檻；該池無對應 [rank] 規則時，回傳主保底
/// 門檻當保守值。
int pityThresholdFor(String gachaType, int rank) {
  final type = gachaTypeFor(gachaType);
  for (final p in type.pities) {
    if (p.rank == rank) return p.threshold;
  }
  return type.primaryPity.threshold;
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/data/gacha_types_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/gacha_types.dart test/data/gacha_types_test.dart
git commit -m "feat(gacha-types): add gachaTypeFor/pityThresholdFor lookup helpers"
```

---

### Task 2: `luck_palette.dart` 歐非分級純函式

**Files:**
- Create: `lib/widgets/luck_palette.dart`
- Test: `test/widgets/luck_palette_test.dart`

**Interfaces:**
- Consumes: `GachaTokens`（`lib/theme/tokens.dart`，`.dark`/`.light` const 與 `stateSuccess`/`stateWarning`/`stateDanger`）。
- Produces:
  - `enum LuckTier { lucky, average, unlucky }`
  - `LuckTier luckTierFor(int pulls, int pityThreshold)`
  - `Color luckColorFor(LuckTier tier, GachaTokens t)`

- [ ] **Step 1: 寫失敗測試**（`test/widgets/luck_palette_test.dart`）

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';

void main() {
  group('luckTierFor — 90 池', () {
    test('45 抽（ratio 0.5）= 歐', () => expect(luckTierFor(45, 90), LuckTier.lucky));
    test('46 抽 = 普通', () => expect(luckTierFor(46, 90), LuckTier.average));
    test('72 抽（ratio 0.8）= 普通', () => expect(luckTierFor(72, 90), LuckTier.average));
    test('73 抽 = 非', () => expect(luckTierFor(73, 90), LuckTier.unlucky));
    test('90 抽 = 非', () => expect(luckTierFor(90, 90), LuckTier.unlucky));
    test('91 抽（ratio > 1）= 非', () => expect(luckTierFor(91, 90), LuckTier.unlucky));
  });

  group('luckTierFor — 80 池', () {
    test('40 抽 = 歐', () => expect(luckTierFor(40, 80), LuckTier.lucky));
    test('41 抽 = 普通', () => expect(luckTierFor(41, 80), LuckTier.average));
    test('64 抽 = 普通', () => expect(luckTierFor(64, 80), LuckTier.average));
    test('65 抽 = 非', () => expect(luckTierFor(65, 80), LuckTier.unlucky));
  });

  group('luckTierFor — 20 池', () {
    test('10 抽 = 歐', () => expect(luckTierFor(10, 20), LuckTier.lucky));
    test('11 抽 = 普通', () => expect(luckTierFor(11, 20), LuckTier.average));
    test('16 抽 = 普通', () => expect(luckTierFor(16, 20), LuckTier.average));
    test('17 抽 = 非', () => expect(luckTierFor(17, 20), LuckTier.unlucky));
  });

  group('luckTierFor — 70 池', () {
    test('35 抽 = 歐', () => expect(luckTierFor(35, 70), LuckTier.lucky));
    test('36 抽 = 普通', () => expect(luckTierFor(36, 70), LuckTier.average));
    test('56 抽 = 普通', () => expect(luckTierFor(56, 70), LuckTier.average));
    test('57 抽 = 非', () => expect(luckTierFor(57, 70), LuckTier.unlucky));
  });

  test('pityThreshold <= 0 防呆 = 非', () {
    expect(luckTierFor(1, 0), LuckTier.unlucky);
  });

  group('luckColorFor 對應既有語意色', () {
    const t = GachaTokens.dark;
    test('歐 → stateSuccess', () => expect(luckColorFor(LuckTier.lucky, t), t.stateSuccess));
    test('普通 → stateWarning', () => expect(luckColorFor(LuckTier.average, t), t.stateWarning));
    test('非 → stateDanger', () => expect(luckColorFor(LuckTier.unlucky, t), t.stateDanger));
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/luck_palette_test.dart`
Expected: FAIL（`luck_palette.dart` 不存在）

- [ ] **Step 3: 實作**（`lib/widgets/luck_palette.dart`）

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 歐非分級：依「抽到該筆所花抽數 / 該池保底門檻」的比例分三階。
enum LuckTier {
  /// 歐：半個保底內出貨。
  lucky,

  /// 普通。
  average,

  /// 非：進入軟保底區（接近硬保底）。
  unlucky,
}

/// 歐（綠）上界比例：抽數在保底的一半以內視為歐。
const double _luckyMaxRatio = 0.5;

/// 普通（金）上界比例：超過此比例即進入軟保底區，視為非。
const double _averageMaxRatio = 0.8;

/// 依 [pulls] 相對 [pityThreshold] 的比例回傳分級。
/// `ratio <= 0.5` 歐；`<= 0.8` 普通；其餘（含 ratio > 1）非。
/// [pityThreshold] <= 0 時防呆視為非（避免除以零；正常資料不會發生）。
LuckTier luckTierFor(int pulls, int pityThreshold) {
  if (pityThreshold <= 0) return LuckTier.unlucky;
  final ratio = pulls / pityThreshold;
  if (ratio <= _luckyMaxRatio) return LuckTier.lucky;
  if (ratio <= _averageMaxRatio) return LuckTier.average;
  return LuckTier.unlucky;
}

/// 將分級映射到既有語意色（綠 / 金 / 紅），不新增 token。
Color luckColorFor(LuckTier tier, GachaTokens t) => switch (tier) {
  LuckTier.lucky => t.stateSuccess,
  LuckTier.average => t.stateWarning,
  LuckTier.unlucky => t.stateDanger,
};
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/luck_palette_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/luck_palette.dart test/widgets/luck_palette_test.dart
git commit -m "feat(luck): add luck tier palette (luckTierFor/luckColorFor)"
```

---

### Task 3: i18n — 歐非分級 ARB key（9 個實翻語系）

**Files:**
- Modify: `lib/l10n/app_zh.arb`（zh-Hant 模板）、`app_zh_Hans.arb`、`app_en.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`
- 不碰 22 個空殼（4-key）ARB。

**Interfaces:**
- Produces（`fvm flutter gen-l10n` 後）：`AppLocalizations` 上的 getter `luckTierLucky`、`luckTierAverage`、`luckTierUnlucky`（皆 `String`，無 placeholder）。

- [ ] **Step 1: 在每個實翻 ARB 的最後一個 key 後（檔尾 `}` 前）插入 3 個 key**

三個 key 為純字串、無 placeholder，依本專案慣例**不加 `@description`**（模板亦同）。各語系值：

| ARB | luckTierLucky | luckTierAverage | luckTierUnlucky |
|---|---|---|---|
| `app_zh.arb` | 歐 | 普通 | 非 |
| `app_zh_Hans.arb` | 欧 | 普通 | 非 |
| `app_en.arb` | Lucky | Average | Unlucky |
| `app_ja.arb` | 強運 | 普通 | 不運 |
| `app_es.arb` | Con suerte | Normal | Sin suerte |
| `app_fr.arb` | Chanceux | Normal | Malchanceux |
| `app_pt_BR.arb` | Sortudo | Normal | Azarado |
| `app_th.arb` | โชคดี | ปกติ | โชคร้าย |
| `app_vi.arb` | May mắn | Bình thường | Kém may |

> zh-Hant / zh-Hans / en / ja 逐字對齊姐妹 PR #37；es/fr/pt-BR/th/vi 按語意翻，**插入前對照 `docs/術語表.md`**，若術語表有「歐/非」官方對應就改用官方譯名。

每檔在現有最後一個 key 後加逗號，再加（以 `app_en.arb` 為例）：

```json
  "luckTierLucky": "Lucky",
  "luckTierAverage": "Average",
  "luckTierUnlucky": "Unlucky"
```

（注意 JSON 尾逗號：插在中間就帶逗號、插在最後一個 key 則該 key 不帶尾逗號。）

- [ ] **Step 2: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤；`lib/l10n/generated/app_localizations.dart` 出現 3 個 getter。

- [ ] **Step 3: 驗證 getter 存在（暫時性檢查，不留測試）**

Run: `fvm flutter analyze lib/l10n/generated/app_localizations.dart`
Expected: No issues found!（getter 已生成）

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/
git commit -m "feat(l10n): add luck tier labels (lucky/average/unlucky) to translated ARBs"
```

---

### Task 4: `luck_legend.dart` — 標籤 helper + 圖例 widget

**Files:**
- Create: `lib/widgets/luck_legend.dart`
- Test: `test/widgets/luck_legend_test.dart`

**Interfaces:**
- Consumes: `LuckTier`、`luckColorFor`（Task 2）；`luckTierLucky/Average/Unlucky`（Task 3）；`GachaTokens`、`AppSpacing`（`theme/tokens.dart`）；`theme.gacha` 擴充 getter。
- Produces:
  - `String luckTierLabel(LuckTier tier, AppLocalizations l)`
  - `class LuckLegend extends StatelessWidget`（const 建構）

- [ ] **Step 1: 寫失敗測試**（`test/widgets/luck_legend_test.dart`）

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';

void main() {
  testWidgets('LuckLegend 顯示三個分級標籤', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(body: LuckLegend()),
      ),
    );
    await tester.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.luckTierLucky), findsOneWidget);
    expect(find.text(l.luckTierAverage), findsOneWidget);
    expect(find.text(l.luckTierUnlucky), findsOneWidget);
  });
}
```

> 若 `buildAppTheme` 簽名不同，依 `lib/theme/app_theme.dart` 既有 export 調整（既有 widget 測試如 `timeline_vertical_test.dart` 已有建立含 `theme.gacha` 的 MaterialApp 範例，照抄其 pump helper 即可）。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/luck_legend_test.dart`
Expected: FAIL（`luck_legend.dart` 不存在）

- [ ] **Step 3: 實作**（`lib/widgets/luck_legend.dart`）

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';

/// 將歐非分級對應到目前語言的標籤（供 tooltip 與 [LuckLegend] 共用）。
String luckTierLabel(LuckTier tier, AppLocalizations l) => switch (tier) {
  LuckTier.lucky => l.luckTierLucky,
  LuckTier.average => l.luckTierAverage,
  LuckTier.unlucky => l.luckTierUnlucky,
};

/// 時間軸歐非色圖例：歐／普通／非 三個色點＋標籤，低視窗寬度可換行。
/// 刻意不標抽數——跨池保底門檻不同，標數字會誤導。
class LuckLegend extends StatelessWidget {
  /// 建立 [LuckLegend]。
  const LuckLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.l,
      runSpacing: AppSpacing.xs,
      children: [
        for (final tier in LuckTier.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: luckColorFor(tier, tokens),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                luckTierLabel(tier, l),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/luck_legend_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/luck_legend.dart test/widgets/luck_legend_test.dart
git commit -m "feat(luck): add LuckLegend widget and luckTierLabel helper"
```

---

### Task 5: 垂直時間軸套歐非色 + meta + tooltip + 圖例

**Files:**
- Modify: `lib/widgets/cards/timeline_vertical.dart`
- Modify: `lib/pages/overview_page.dart:430`、`lib/widgets/share/share_card.dart:434`
- Test: `test/widgets/cards/timeline_vertical_test.dart`

**Interfaces:**
- Consumes: `pityThresholdFor`（T1）、`luckTierFor`／`luckColorFor`（T2）、`luckTierLabel`／`LuckLegend`（T4）。
- Produces: `TimelineVertical` 新增可選具名參數 `bool showLuckLegend = false`。

- [ ] **Step 1: 寫失敗測試**（`test/widgets/cards/timeline_vertical_test.dart` 新增；沿用該檔既有 pump helper 與 `TimelineEntry` 建構）

```dart
  testWidgets('節點 tooltip 顯示 名稱 · 分級 · N 抽', (tester) async {
    final entry = TimelineEntry(
      name: '刻晴',
      gachaType: '301', // 90 池
      time: DateTime(2026, 6, 1),
      pullsSincePrev: 40, // 40/90 ≈ 0.44 → 歐
    );
    await pumpTimelineVertical(tester, entries: [entry], targetRank: 5);
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final expected = '刻晴 · ${l.luckTierLucky} · ${l.timelineSinceLast(40)}';
    expect(find.byTooltip(expected), findsWidgets);
  });

  testWidgets('showLuckLegend 時顯示圖例', (tester) async {
    await pumpTimelineVertical(
      tester,
      entries: const [],
      targetRank: 5,
      nowPulls: 10,
      showLuckLegend: true,
    );
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.luckTierLucky), findsOneWidget);
  });
```

> 若既有檔無 `pumpTimelineVertical` helper，依該檔現有 testWidgets 的 MaterialApp 建構抽一個，並讓它接受 `showLuckLegend`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: FAIL（`showLuckLegend` 參數不存在 / tooltip 文案不符）

- [ ] **Step 3a: 加 import 與 `showLuckLegend` 參數**

`timeline_vertical.dart` 頂部 import 區加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';
```

`TimelineVertical` 建構子（`required this.isAcrossBanners` 之後）加參數，並新增 field：

```dart
    this.showLuckLegend = false,
```

```dart
  /// 為 true 時在卡片底部釘上 [LuckLegend]（即使 entries 溢出被裁仍可見）。
  final bool showLuckLegend;
```

- [ ] **Step 3b: `container()` 加底部圖例**

把 `container()` 內 `final Widget content = fillHeight ? ... : body;` 與 `return Container(...)` 改為：在 `showLuckLegend` 時於邊框內底部排 `LuckLegend`：

```dart
      final Widget content;
      if (showLuckLegend) {
        const legend = Padding(
          padding: EdgeInsets.only(top: AppSpacing.s),
          child: LuckLegend(),
        );
        content = fillHeight
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRect(
                      child: OverflowBox(
                        minHeight: 0,
                        maxHeight: double.infinity,
                        alignment: Alignment.topCenter,
                        child: body,
                      ),
                    ),
                  ),
                  legend,
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [body, legend],
              );
      } else {
        content = fillHeight
            ? ClipRect(
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: body,
                ),
              )
            : body;
      }
```

> WHY：`AppSpacing.s` 為 const，`Padding` 與 `LuckLegend` 皆 const → 可宣告 `const legend`。`fillHeight` 路徑用 `Expanded` 占滿剩餘高並自行 `ClipRect` 裁切，圖例釘底部恆可見。

- [ ] **Step 3c: 節點/名稱套歐非色 + tooltip**

`_EntryRow` 新增 `targetRank` field 與建構參數：

```dart
    required this.targetRank,
```

```dart
  /// 主要顯示稀有度，用於查保底門檻換算歐非色。
  final int targetRank;
```

在 `TimelineVertical.build` 的 `for (var i = 0; ...)` 內 `_EntryRow(...)` 補 `targetRank: targetRank,`。

`_EntryRow.build` 開頭，把 `final accent = colors.colorFor(entry.gachaType);` 改為計算歐非：

```dart
    final rank = entry.sourceRecord?.rankType ?? targetRank;
    final pity = pityThresholdFor(entry.gachaType, rank);
    final tier = luckTierFor(entry.pullsSincePrev, pity);
    final luck = luckColorFor(tier, tokens);
```

- `_nameRow` 內 `color: colors.colorFor(entry.gachaType)` → `color: luck`。注意 `_nameRow` 目前是 getter；改為**方法** `Widget _nameRow(Color nameColor)`，或在 `build` 內就地建構名稱 Row 並用 `luck`。最小改法：把 getter 改為 `Widget _nameRowWith(Color color)` 並在兩處呼叫端（`build` 內 Tooltip child）傳 `luck`。
- 節點 `_Node(color: accent, ...)` → `_Node(color: luck, ...)`。
- 三處 `Tooltip(message: entry.name, ...)` 中，**節點那一個**（`SizedBox(width: _haloSize)` 外層）的 message 改為：

```dart
            message:
                '${entry.name} · ${luckTierLabel(tier, l)} · '
                '${l.timelineSinceLast(entry.pullsSincePrev)}',
```

（名稱列與 meta 列的 Tooltip 維持只顯示 `entry.name`。）

- [ ] **Step 3d: meta 行卡池名稱用卡池色、N 抽用歐非色**

把 meta 的 `Text('${...} · ${_bannerName(...)} · ${l.timelineSinceLast(...)}', ...)` 改為 `Text.rich`：

```dart
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      children: [
                        TextSpan(text: '${_formatShortDate(entry.time)} · '),
                        TextSpan(
                          text: _bannerName(entry.gachaType, l),
                          style: TextStyle(
                            color: colors.colorFor(entry.gachaType),
                          ),
                        ),
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: l.timelineSinceLast(entry.pullsSincePrev),
                          style: TextStyle(color: luck),
                        ),
                      ],
                    ),
                  ),
```

（外層仍包在原 `Tooltip(message: entry.name, ...)` 內。）

- [ ] **Step 3e: `_bannerName` 改用 `gachaTypeFor`（DRY）**

把 `_bannerName` 內整段 `gachaTypes.firstWhere(... orElse: GachaType(...))` 改為：

```dart
  /// 依 [gachaType] 查在地化卡池名稱；查無時回傳帶預設保底的 fallback 名稱。
  String _bannerName(String gachaType, AppLocalizations l) =>
      gachaTypeFor(gachaType).resolveName(l);
```

import 區確認已有 `gacha_types.dart`（既有）。

- [ ] **Step 3f: 呼叫端傳 `showLuckLegend: true`**

`lib/pages/overview_page.dart` 的 `TimelineVertical(... isAcrossBanners: true,)` 後加 `showLuckLegend: true,`。
`lib/widgets/share/share_card.dart` 的 `TimelineVertical(... fillHeight: true,)` 後加 `showLuckLegend: true,`。

- [ ] **Step 4: 跑測試**

Run: `fvm flutter test test/widgets/cards/timeline_vertical_test.dart`
Expected: PASS（既有斷言若驗證節點＝卡池色，需同步改為歐非色預期）

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_vertical.dart lib/pages/overview_page.dart lib/widgets/share/share_card.dart test/widgets/cards/timeline_vertical_test.dart
git commit -m "feat(timeline): luck-color vertical timeline nodes, names, pulls, tooltip, legend"
```

---

### Task 6: 橫向時間軸套歐非色 + tooltip + 圖例 + 移除 colors

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`
- Modify: `lib/pages/banner_page.dart:282-300`
- Test: `test/widgets/cards/timeline_horizontal_test.dart`

**Interfaces:**
- Consumes: `pityThresholdFor`（T1）、`luckTierFor`／`luckColorFor`（T2）、`luckTierLabel`／`LuckLegend`（T4）。
- Produces: `TimelineHorizontal` 移除 `colors` 參數；節點/名稱/抽數呈歐非色。

- [ ] **Step 1: 寫失敗測試**（`test/widgets/cards/timeline_horizontal_test.dart` 新增）

```dart
  testWidgets('橫向節點 tooltip 顯示 名稱 · 分級 · N 抽', (tester) async {
    final entry = TimelineEntry(
      name: '魈',
      gachaType: '301',
      time: DateTime(2026, 6, 1),
      pullsSincePrev: 85, // 85/90 ≈ 0.94 → 非
    );
    await pumpTimelineHorizontal(tester, entries: [entry], targetRank: 5);
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final expected = '魈 · ${l.luckTierUnlucky} · ${l.timelineSinceLast(85)}';
    expect(find.byTooltip(expected), findsOneWidget);
  });
```

> `pumpTimelineHorizontal` 依該檔既有 testWidgets 抽出，並**移除**對 `colors:` 的傳入。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: FAIL

- [ ] **Step 3a: import + 移除 `colors` 參數**

頂部加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';
```

`TimelineHorizontal` 移除 `required this.colors,` 與 `final BannerColors colors;`（dartdoc 一併移除）。
build 內 `_EntryColumn(entry: entry, colors: widget.colors, tokens: tokens)` 移除 `colors:`，並把 `for (final entry in widget.entries)` 改為帶 index（給 Task 7 月份用，先改 `for (var i = 0; i < widget.entries.length; i++)`，傳 `entry: widget.entries[i]`）。

> `bannerDistributionEntries` top-level 函式保留不動（其 `BannerColors` 參數獨立於 widget）。

- [ ] **Step 3b: `_EntryColumn` 套歐非色 + tooltip**

`_EntryColumn` 移除 `colors` field／參數；新增 `targetRank`：

```dart
    required this.targetRank,
```

```dart
  /// 該卡池萃取的稀有度（5 或 4），用於查保底門檻。
  final int targetRank;
```

`build` 開頭把 `final accent = colors.colorFor(entry.gachaType);` 改為：

```dart
    final rank = entry.sourceRecord?.rankType ?? targetRank;
    final pity = pityThresholdFor(entry.gachaType, rank);
    final tier = luckTierFor(entry.pullsSincePrev, pity);
    final luck = luckColorFor(tier, tokens);
```

把兩處名稱 `Text(... style: TextStyle(color: accent ...))` 的 `accent` 改 `luck`；`_Node(color: accent, ...)` 改 `_Node(color: luck, ...)`。

`Tooltip(message: entry.name, ...)` 的 message 改為：

```dart
      message:
          '${entry.name} · ${luckTierLabel(tier, l)} · '
          '${l.timelineSinceLast(entry.pullsSincePrev)}',
```

meta 的 `Text('${_formatShortDate(entry.time)} · ${l.timelineSinceLast(entry.pullsSincePrev)}', ...)` 改為 `Text.rich`，把抽數段套歐非色：

```dart
            Text.rich(
              TextSpan(
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                children: [
                  TextSpan(text: '${_formatShortDate(entry.time)} · '),
                  TextSpan(
                    text: l.timelineSinceLast(entry.pullsSincePrev),
                    style: TextStyle(color: luck),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
```

build 內 `_EntryColumn(entry: widget.entries[i], tokens: tokens)` 補 `targetRank: widget.targetRank,`。

- [ ] **Step 3c: banner_page 接線**

`lib/pages/banner_page.dart` 包時間軸的 `ChartCard`（`icon: Icons.timeline`）加 `legend: const LuckLegend(),`；`TimelineHorizontal(...)` 移除 `colors: BannerColors.of(...)` 那行。確認該檔 import 有 `luck_legend.dart`；若移除 `colors` 後 `BannerColors` 不再被該檔其他處使用，移除其 import（analyze 會提示）。

- [ ] **Step 4: 跑測試**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_horizontal.dart lib/pages/banner_page.dart test/widgets/cards/timeline_horizontal_test.dart
git commit -m "feat(timeline): luck-color horizontal timeline, drop banner colors, add legend"
```

---

### Task 7: 記錄列表「保底內」欄套歐非色

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart`
- Test: `test/widgets/data/sortable_table_test.dart`

**Interfaces:**
- Consumes: `pityThresholdFor`（T1）、`luckTierFor`／`luckColorFor`（T2）。`_Row` 新增 `final int mainRank;`。

- [ ] **Step 1: 寫失敗測試**（`test/widgets/data/sortable_table_test.dart` 新增；沿用既有 `RecordRow` 建構與 pump helper）

```dart
  testWidgets('保底內欄依抽數呈歐非色', (tester) async {
    // 角色池(301) 5★：85 抽 → 非(紅 = stateDanger)
    await pumpSortableTable(
      tester,
      rows: [makeRow(gachaType: '301', rankType: 5, mainPityIndex: 85)],
      mainRank: 5,
    );
    final tokens = GachaTokens.dark;
    final text = tester.widget<Text>(find.text('85'));
    expect(text.style?.color, tokens.stateDanger);
  });
```

> `makeRow` / `pumpSortableTable` 依既有測試 helper 命名調整；`mainPityIndex` 對應該欄值。

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/data/sortable_table_test.dart`
Expected: FAIL（「85」目前為 muted 色）

- [ ] **Step 3a: import + `_Row` 新增 `mainRank`**

頂部加：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';
```

`_Row` 建構子（`required this.l,` 之後）加 `required this.mainRank,`，並新增 field：

```dart
  /// 該卡池主稀有度 rank，用於換算「保底內」欄歐非色。
  final int mainRank;
```

`_Row(...)` 建構處（`l: l,` 之後）加 `mainRank: widget.mainRank,`。

- [ ] **Step 3b: 「保底內」欄套歐非色**

`_Row.build` 內，在 `final record = row.record;` 之後加：

```dart
    final pityLuck = luckColorFor(
      luckTierFor(row.mainPityIndex, pityThresholdFor(record.gachaType, mainRank)),
      tokens,
    );
```

把 `mainPityIndex` 那格（`'${row.mainPityIndex}'`）的 `style: mutedNum` 改為：

```dart
              style: TextStyle(
                color: pityLuck,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
```

（`totalIndex` 那格維持 `mutedNum` 不動。）

- [ ] **Step 4: 跑測試**

Run: `fvm flutter test test/widgets/data/sortable_table_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/data/sortable_table.dart test/widgets/data/sortable_table_test.dart
git commit -m "feat(records): luck-color the pity-progress column in record list"
```

---

### Task 8: 卡池調色盤移出歐非色帶

**Files:**
- Modify: `lib/widgets/banner_colors.dart`
- Test: `test/widgets/banner_colors_test.dart`（新建）

**Interfaces:**
- Consumes: `GachaTokens.dark`／`.light` 的 `stateSuccess`／`stateWarning`／`stateDanger`。
- Produces: 8 個卡池色全部落在 cyan→magenta 弧段，皆 ≠ 三歐非色。

- [ ] **Step 1: 寫失敗測試**（`test/widgets/banner_colors_test.dart`）

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';

void main() {
  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, GachaTokens.dark),
    ('light', Brightness.light, GachaTokens.light),
  ]) {
    test('$label：任一卡池色不得等於歐非三色', () {
      final colors = BannerColors.of(brightness);
      final luck = {tokens.stateSuccess, tokens.stateWarning, tokens.stateDanger};
      for (final t in gachaTypes) {
        expect(
          luck.contains(colors.colorFor(t.gachaType)),
          isFalse,
          reason: '${t.gachaType} 撞歐非色',
        );
      }
      expect(luck.contains(colors.fallback), isFalse);
    });
  }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/banner_colors_test.dart`
Expected: FAIL（現況 character=stateSuccess、weapon=stateDanger 撞色）

- [ ] **Step 3: 改 `_dark` / `_light` 色值**（cyan→magenta 弧段；exact hex 可微調，唯一硬約束＝本測試通過）

`_dark`：

```dart
  static const _dark = BannerColors(
    character: Color(0xFF35BFD0), // 青藍
    weapon: Color(0xFF4FA3E8), // 天藍
    chronicled: Color(0xFF6E8BE6), // 矢車菊藍
    standard: Color(0xFF8A7CE0), // 靛藍
    beginner: Color(0xFFA86FD9), // 紫羅蘭
    odesEvent: Color(0xFFC56FD0), // 蘭紫
    odesStandard: Color(0xFFD96BA8), // 桃紅
    fallback: Color(0xFF8A92A6), // 中性
  );
```

`_light`：

```dart
  static const _light = BannerColors(
    character: Color(0xFF1B92A8),
    weapon: Color(0xFF2E6FC0),
    chronicled: Color(0xFF4F5FC0),
    standard: Color(0xFF6A4FC0),
    beginner: Color(0xFF8A3FB0),
    odesEvent: Color(0xFFA63FA8),
    odesStandard: Color(0xFFB23A7E),
    fallback: Color(0xFF6A7080),
  );
```

更新類別 dartdoc：把「避開稀有度 token」改述為「避開歐非語意色（綠/金/紅）」並說明 WHY（節點已改歐非色、卡池色僅用於 meta 卡池名稱與分佈圖）。

- [ ] **Step 4: 跑測試**

Run: `fvm flutter test test/widgets/banner_colors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/banner_colors.dart test/widgets/banner_colors_test.dart
git commit -m "feat(banner-colors): shift palette to cyan-magenta arc clear of luck colors"
```

---

### Task 9: 橫向時間軸年/月分隔

**Files:**
- Modify: `lib/widgets/cards/timeline_horizontal.dart`
- Test: `test/widgets/cards/timeline_horizontal_test.dart`

**Interfaces:**
- Consumes: `l.timelineMonthLabel`（既有）。`_EntryColumn` 新增 `isMonthStart`、`showMonthDivider`。

- [ ] **Step 1: 寫失敗測試**（`test/widgets/cards/timeline_horizontal_test.dart` 新增）

```dart
  testWidgets('跨月顯示年/月標籤', (tester) async {
    final entries = [
      TimelineEntry(name: 'A', gachaType: '301', time: DateTime(2026, 6, 2), pullsSincePrev: 10),
      TimelineEntry(name: 'B', gachaType: '301', time: DateTime(2026, 5, 20), pullsSincePrev: 10),
    ];
    await pumpTimelineHorizontal(tester, entries: entries, targetRank: 5);
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l.timelineMonthLabel('2026', '06')), findsOneWidget);
    expect(find.text(l.timelineMonthLabel('2026', '05')), findsOneWidget);
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: FAIL（無年/月標籤）

- [ ] **Step 3a: 新增 `_monthBandHeight` 常數**

`timeline_horizontal.dart` 常數區（`_haloSize` 附近）加：

```dart
/// 月份標籤帶高度。每欄頂部保留此高（組首填年/月、其餘留白），底部以等高
/// spacer 對稱補回，使節點 y 不因標籤帶位移、仍對齊背景軸線。
const double _monthBandHeight = 26;
```

- [ ] **Step 3b: build 計算 monthStart 並下傳**

在 `build` 的 `return Stack(` 之前計算：

```dart
    // 每欄是否為其月份分組首欄（左→右 = 新→舊，某月最新一筆即該組起點）。
    final monthStart = <bool>[];
    int? prevYearMonth;
    for (final entry in widget.entries) {
      final ym = entry.time.year * 12 + entry.time.month;
      monthStart.add(prevYearMonth != ym);
      prevYearMonth = ym;
    }
```

把 Task 6 的 `for (var i = 0; ...)` 內 `_EntryColumn(...)` 補：

```dart
                        isMonthStart: monthStart[i],
                        showMonthDivider: monthStart[i] && i > 0,
```

- [ ] **Step 3c: `_EntryColumn` 加標籤帶 + 對稱 spacer + 分隔線**

`_EntryColumn` 新增 field／參數：

```dart
    required this.isMonthStart,
    required this.showMonthDivider,
```

```dart
  /// 是否為其月份分組首欄；true 時頂部標籤帶顯示年/月。
  final bool isMonthStart;

  /// 是否在左側畫月份分隔線（月份交界、且非最左欄時為 true）。
  final bool showMonthDivider;
```

`build` 內，計算 label：

```dart
    final monthLabel = isMonthStart
        ? l.timelineMonthLabel(
            entry.time.year.toString(),
            entry.time.month.toString().padLeft(2, '0'),
          )
        : null;
```

把回傳的 `Tooltip(... child: SizedBox(width: _colWidth, child: Column(...)))` 包進帶分隔線的 `Container`，並在 `Column` children **最前**插入標籤帶、**最後**插入對稱 spacer：

```dart
      child: Container(
        decoration: showMonthDivider
            ? BoxDecoration(
                border: Border(left: BorderSide(color: tokens.borderEmphasis)),
              )
            : null,
        child: SizedBox(
          width: _colWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 月份標籤帶（組首填年/月，其餘留白佔位）。
              SizedBox(
                height: _monthBandHeight,
                child: monthLabel == null
                    ? null
                    : Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          monthLabel,
                          maxLines: 1,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
              ),
              // ...（原有 icon+name / _Node / meta 不變）...
              // 對稱補回標籤帶高度，使節點維持原垂直中心、對齊軸線。
              const SizedBox(height: _monthBandHeight),
            ],
          ),
        ),
      ),
```

> WHY：頂部 `_monthBandHeight` 與底部 `_monthBandHeight` 等高 → 欄的垂直中心不變，節點仍落在背景軸線上。`_NowColumn` 不加帶、不受影響（其節點中心與 entry 欄一致）。

- [ ] **Step 4: 跑測試**

Run: `fvm flutter test test/widgets/cards/timeline_horizontal_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/cards/timeline_horizontal.dart test/widgets/cards/timeline_horizontal_test.dart
git commit -m "feat(timeline): add year/month bands and dividers to horizontal timeline"
```

---

### Task 10: 全面驗收

**Files:** 無（驗收與修補）

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 僅格式調整，無破壞。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`（若有未使用 import，如 banner_page 的 `BannerColors`，移除）

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 手動目視（可選，build runner）**

Run: `fvm flutter run -d windows`
確認：單卡池頁時間軸綠/金/紅 + 年月帶 + 圖例；總覽頁 meta 卡池名稱卡池色、N 抽歐非色；記錄列表「保底內」歐非色；分享圖圖例釘底。

- [ ] **Step 5: Commit（若有 analyze/format 修補）**

```bash
git add -A
git commit -m "chore(timeline): formatting and analyze fixups for luck color feature"
```

---

## Self-Review

**Spec coverage：**
- 分級門檻／luckTierFor／luckColorFor → Task 2 ✓
- gachaTypeFor／pityThresholdFor → Task 1 ✓
- luck_legend / luckTierLabel → Task 4 ✓
- 垂直時間軸節點/名稱/meta/tooltip/圖例 → Task 5 ✓
- 橫向時間軸節點/名稱/meta/tooltip/移除 colors/圖例 → Task 6 ✓
- 記錄列表「保底內」欄 → Task 7 ✓
- 卡池調色盤挪移 + 不撞色測試 → Task 8 ✓
- 橫向年/月分隔 → Task 9 ✓
- i18n 9 實翻 ARB、4 對齊姐妹 / 5 語意翻 → Task 3 ✓
- 呼叫端 overview/banner/share 接線 → Task 5（vertical）/ Task 6（horizontal）✓
- 「現在」節點金色共用：已知接受、無需 task ✓
- 全綠驗收 → Task 10 ✓

**Placeholder scan：** 無 TBD/TODO；es/fr/pt-BR/th/vi 譯文為具體字串並註明對照術語表。

**Type consistency：** `luckTierFor(int,int)→LuckTier`、`luckColorFor(LuckTier,GachaTokens)→Color`、`luckTierLabel(LuckTier,AppLocalizations)→String`、`pityThresholdFor(String,int)→int`、`gachaTypeFor(String)→GachaType` 全程一致；`entry.sourceRecord?.rankType ?? targetRank` 取稀有度一致；`_Row.mainRank` 與 `SortableTable.mainRank` 對齊。
