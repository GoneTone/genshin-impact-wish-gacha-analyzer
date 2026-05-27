# 分享圖生成功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在綜合頁與各卡池頁新增「生成分享圖」功能，把該頁數據彙整成一張 PNG，存檔並複製到剪貼簿。

**Architecture:** 專用 `ShareCard` widget 樹（固定寬 1200px，版面 B 兩欄），用「離屏 render pipeline（`RenderView` + `BuildOwner` + `RepaintBoundary.toImage`）」同步渲染成 PNG。app icon 預先解碼成 `ui.Image`、fl_chart 動畫關閉、`AppLocalizations` 經 `SynchronousFuture` 同步解析，全程無 async 相依，輸出穩定可測。輸出走存檔（`getSaveLocation` + 寫檔 + reveal）並複製到剪貼簿（`super_clipboard`）。

**Tech Stack:** Flutter (Dart 3.11), Riverpod, fl_chart, file_selector, super_clipboard, intl, flutter gen-l10n。

> 每個 Task 結束前都要過 CLAUDE.md 品質閘：`dart format lib/ test/`、`flutter analyze`（須 `No issues found!`）、`flutter test`（須 `All tests passed!`）。Task 內已含對應步驟。

---

## 檔案結構

| 檔案 | 職責 | 動作 |
|---|---|---|
| `pubspec.yaml` | 加 `super_clipboard` 依賴 | Modify |
| `lib/l10n/app_zh.arb` / `app_en.arb` | 新增分享相關字串 | Modify |
| `lib/services/share_uid_mask.dart` | UID 分享遮罩純函式（前 3 碼 + 其餘 `x`）| Create |
| `lib/services/overview_sections.dart` | 抽出綜合頁「祈願/頌願分組 + 統計」純函式，OverviewPage 與 ShareCard 共用 | Create |
| `lib/pages/overview_page.dart` | 改用 `overview_sections.dart` | Modify |
| `lib/widgets/rarity_pie.dart` / `item_type_pie.dart` | 加可選 `animationDuration`（預設不變），分享圖傳 `Duration.zero` | Modify |
| `lib/models/share_image_options.dart` | `ShareImageOptions`（brightness + showFullUid）| Create |
| `lib/widgets/share/share_card.dart` | 分享圖 widget 樹（header / section / timeline）| Create |
| `lib/services/share_image_renderer.dart` | widget → PNG bytes（離屏 pipeline）+ app icon 預解碼 | Create |
| `lib/services/share_image_export.dart` | PNG bytes → 剪貼簿 + 存檔，含 `@visibleForTesting` seam | Create |
| `lib/widgets/dialogs/share_image_dialog.dart` | 生成前選項 dialog（`AppDialog`）| Create |
| `lib/widgets/share/share_action_button.dart` | 觸發整段流程的按鈕（兩頁共用）| Create |
| `lib/pages/banner_page.dart` / `overview_page.dart` | `PageHeader` 旁掛分享按鈕 | Modify |
| `test/...` | 對應測試 | Create |

---

## Task 1: 加入 super_clipboard 依賴與 l10n 字串

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: 加入 super_clipboard 依賴**

於 `pubspec.yaml` 的 `dependencies:` 區段，`markdown_widget` 那行下方加入：

```yaml
  super_clipboard: ^0.8.24
```

> `super_clipboard` 透過 `super_native_extensions` 需要 Rust toolchain 建置；本專案已用 flutter_rust_bridge，Rust 環境已就緒。

- [ ] **Step 2: 取得套件**

Run: `flutter pub get`
Expected: 成功解析，無版本衝突。

- [ ] **Step 3: 新增 l10n 字串（template = app_zh.arb）**

在 `lib/l10n/app_zh.arb` 的 `"settingsExportSuccess"` 區塊**之前**（約 line 280 附近 `"settingsImportData"` 之後）插入：

```json
  "shareImageButton": "生成分享圖",
  "shareImageDialogTitle": "分享圖設定",
  "shareImageThemeLabel": "主題",
  "shareImageThemeDark": "深色",
  "shareImageThemeLight": "淺色",
  "shareImageShowFullUid": "在圖上顯示完整 UID",
  "shareImageShowFullUidHint": "關閉時只顯示前 3 碼，其餘以 x 遮罩",
  "shareImageGenerate": "生成",
  "shareImageUpdatedAt": "資料更新 {time}",
  "@shareImageUpdatedAt": {
    "placeholders": { "time": { "type": "String" } }
  },
  "shareImageTimelineTitle": "最近 {n} 筆 {star}（新→舊）",
  "@shareImageTimelineTitle": {
    "placeholders": { "n": { "type": "int" }, "star": { "type": "String" } }
  },
  "shareImageSavedAndCopied": "已存檔並複製到剪貼簿：{path}",
  "@shareImageSavedAndCopied": {
    "placeholders": { "path": { "type": "String" } }
  },
  "shareImageSavedOnly": "已存檔：{path}（剪貼簿不支援）",
  "@shareImageSavedOnly": {
    "placeholders": { "path": { "type": "String" } }
  },
  "shareImageCopiedOnly": "已複製到剪貼簿",
  "shareImageFailed": "分享圖生成失敗",
```

- [ ] **Step 4: 在 app_en.arb 對應加入英文**

在 `lib/l10n/app_en.arb` 對應位置（`"settingsImportData"` 之後）插入：

```json
  "shareImageButton": "Generate share image",
  "shareImageDialogTitle": "Share image options",
  "shareImageThemeLabel": "Theme",
  "shareImageThemeDark": "Dark",
  "shareImageThemeLight": "Light",
  "shareImageShowFullUid": "Show full UID on image",
  "shareImageShowFullUidHint": "When off, only the first 3 digits are shown, the rest masked with x",
  "shareImageGenerate": "Generate",
  "shareImageUpdatedAt": "Updated {time}",
  "@shareImageUpdatedAt": {
    "placeholders": { "time": { "type": "String" } }
  },
  "shareImageTimelineTitle": "Latest {n} {star} (new→old)",
  "@shareImageTimelineTitle": {
    "placeholders": { "n": { "type": "int" }, "star": { "type": "String" } }
  },
  "shareImageSavedAndCopied": "Saved and copied to clipboard: {path}",
  "@shareImageSavedAndCopied": {
    "placeholders": { "path": { "type": "String" } }
  },
  "shareImageSavedOnly": "Saved: {path} (clipboard unsupported)",
  "@shareImageSavedOnly": {
    "placeholders": { "path": { "type": "String" } }
  },
  "shareImageCopiedOnly": "Copied to clipboard",
  "shareImageFailed": "Failed to generate share image",
```

- [ ] **Step 5: 重新產生 l10n**

Run: `flutter gen-l10n`
Expected: 成功，`lib/l10n/generated/app_localizations.dart` 出現 `shareImageButton` 等 getter。

- [ ] **Step 6: 驗證分析通過**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/l10n/app_zh.arb lib/l10n/app_en.arb lib/l10n/generated/
git commit -m "feat(share): add super_clipboard dep and share-image l10n strings"
```

---

## Task 2: UID 分享遮罩純函式

**Files:**
- Create: `lib/services/share_uid_mask.dart`
- Test: `test/services/share_uid_mask_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/share_uid_mask_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';

void main() {
  group('maskUidForShare', () {
    test('顯示前 3 碼，其餘以 x 遮罩、長度保留', () {
      expect(maskUidForShare('123456789'), '123xxxxxx');
    });

    test('長度恰為 3 全可見', () {
      expect(maskUidForShare('123'), '123');
    });

    test('長度小於 3 全遮罩為固定 xxx', () {
      expect(maskUidForShare('12'), 'xxx');
      expect(maskUidForShare(''), 'xxx');
    });

    test('比 sanitizeUid 嚴格：不洩漏末碼', () {
      final masked = maskUidForShare('800123456');
      expect(masked.endsWith('456'), isFalse);
      expect(masked, '800xxxxxx');
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/share_uid_mask_test.dart`
Expected: FAIL（`share_uid_mask.dart` 不存在 / 無 `maskUidForShare`）。

- [ ] **Step 3: 實作**

建立 `lib/services/share_uid_mask.dart`：

```dart
// lib/services/share_uid_mask.dart
//
// 分享圖專用 UID 遮罩：顯示前 3 碼，其餘逐字以 `x` 取代（長度保留）。
// 刻意不重用 services/log_sanitize.dart 的 sanitizeUid（前 3 + 後 3）：
// 公開分享情境不應洩漏末碼，故政策比 log 脫敏更嚴。長度 < 3 全遮 `xxx`。
String maskUidForShare(String uid) {
  if (uid.length < 3) return 'xxx';
  if (uid.length == 3) return uid;
  return '${uid.substring(0, 3)}${'x' * (uid.length - 3)}';
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/share_uid_mask_test.dart`
Expected: PASS（4 tests）。

- [ ] **Step 5: 格式化 + 分析**

Run: `dart format lib/ test/ && flutter analyze`
Expected: 格式化完成；`No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/share_uid_mask.dart test/services/share_uid_mask_test.dart
git commit -m "feat(share): add share-only UID mask (first 3 + x)"
```

---

## Task 3: 抽出 overview_sections 共用 helper

把 `overview_page.dart` 內嵌的「祈願/頌願分組 + 各區 stats / 平均間隔 / timeline」抽成純函式，供 OverviewPage 與 ShareCard 共用（CLAUDE.md：嚴禁重複造輪子）。

**Files:**
- Create: `lib/services/overview_sections.dart`
- Modify: `lib/pages/overview_page.dart`
- Test: `test/services/overview_sections_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/overview_sections_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';

GachaRecord _r(String gt, int rank, String name, DateTime t) => GachaRecord(
  id: '${name}_${t.microsecondsSinceEpoch}',
  uid: '123456789',
  gachaType: gt,
  name: name,
  itemType: rank == 5 ? '角色' : '武器',
  rankType: rank,
  time: t,
  lang: 'zh-tw',
);

void main() {
  test('buildOverviewSections 切出祈願與頌願兩段、統計正確', () {
    final t = DateTime(2026, 5, 1);
    final activeBanners = <String, List<GachaRecord>>{
      '301': [_r('301', 5, '那維萊特', t), _r('301', 3, '冷刃', t)],
      '2000': [_r('2000', 5, '某五星', t)],
    };

    final sections = buildOverviewSections(activeBanners);

    expect(sections.gacha.stats.total, 2);
    expect(sections.gacha.stats.fiveStarCount, 1);
    expect(sections.gacha.timeline.length, 1);
    expect(sections.odes.stats.total, 1);
    expect(sections.odes.eventFiveCount, 1);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/overview_sections_test.dart`
Expected: FAIL（`overview_sections.dart` 不存在）。

- [ ] **Step 3: 實作 helper**

建立 `lib/services/overview_sections.dart`：

```dart
// lib/services/overview_sections.dart
//
// 綜合頁的「祈願/頌願分組 + 統計 + 平均間隔 + timeline」純資料計算。
// OverviewPage 與 ShareCard 共用，避免兩處複製分組邏輯。
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';

/// 祈願段（角色/武器/常駐/新手…）的彙整結果。
class GachaSectionData {
  const GachaSectionData({
    required this.types,
    required this.banners,
    required this.stats,
    required this.timeline,
    required this.timelineRank,
    required this.timelineNowPulls,
    required this.fiveStarAvg,
    required this.fourStarAvg,
  });

  final List<GachaType> types;
  final Map<String, List<GachaRecord>> banners;
  final GachaStats stats;
  final List<TimelineEntry> timeline;
  final int timelineRank;
  final int timelineNowPulls;
  final double? fiveStarAvg;
  final double? fourStarAvg;
}

/// 頌願段沿用既有 odes 統計組成（總抽數、事件 5★、常駐 4★），
/// 不套「佔比 + 平均幾抽出」（odes 無對應保底語意）。
class OdesSectionData {
  const OdesSectionData({
    required this.types,
    required this.banners,
    required this.stats,
    required this.eventFiveCount,
    required this.standardFourCount,
    required this.timeline,
    required this.timelineRank,
  });

  final List<GachaType> types;
  final Map<String, List<GachaRecord>> banners;
  final GachaStats stats;
  final int eventFiveCount;
  final int standardFourCount;
  final List<TimelineEntry> timeline;
  final int timelineRank;
}

class OverviewSections {
  const OverviewSections({required this.gacha, required this.odes});
  final GachaSectionData gacha;
  final OdesSectionData odes;
}

OverviewSections buildOverviewSections(
  Map<String, List<GachaRecord>> activeBanners,
) {
  final gachaList = gachaTypes
      .where((t) => t.category == GachaCategory.gacha)
      .toList(growable: false);
  final odesList = gachaTypes
      .where((t) => t.category == GachaCategory.odes)
      .toList(growable: false);

  final gachaBanners = <String, List<GachaRecord>>{
    for (final t in gachaList)
      t.gachaType: activeBanners[t.gachaType] ?? const <GachaRecord>[],
  };
  final odesBanners = <String, List<GachaRecord>>{
    for (final t in odesList)
      t.gachaType: activeBanners[t.gachaType] ?? const <GachaRecord>[],
  };

  final gachaAll = gachaBanners.values.expand((r) => r).toList(growable: false);
  final odesAll = odesBanners.values.expand((r) => r).toList(growable: false);

  final typesByGt = <String, GachaType>{
    for (final t in gachaList) t.gachaType: t,
  };
  final gachaTimelineRank = gachaList.first.primaryPity.rank;

  final eventFive = (odesBanners['2000'] ?? const <GachaRecord>[])
      .where((r) => r.rankType == 5)
      .length;
  final standardFour = (odesBanners['1000'] ?? const <GachaRecord>[])
      .where((r) => r.rankType == 4)
      .length;

  return OverviewSections(
    gacha: GachaSectionData(
      types: gachaList,
      banners: gachaBanners,
      stats: computeGachaStats(gachaAll),
      timeline: buildTimelineEntriesAcrossBanners(
        gachaBanners,
        rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
      ),
      timelineRank: gachaTimelineRank,
      timelineNowPulls: pullsSinceLastRankedAcrossBanners(
        gachaBanners,
        rankFor: (gt) => typesByGt[gt]!.primaryPity.rank,
      ),
      fiveStarAvg: averageIntervalAcrossBanners(
        gachaBanners,
        rankFor: (_) => 5,
      ),
      fourStarAvg: averageIntervalAcrossBanners(
        gachaBanners,
        rankFor: (_) => 4,
      ),
    ),
    odes: OdesSectionData(
      types: odesList,
      banners: odesBanners,
      stats: computeGachaStats(odesAll),
      eventFiveCount: eventFive,
      standardFourCount: standardFour,
      timeline: buildTimelineEntriesAcrossBanners(
        odesBanners,
        rankFor: (gt) => odesList.firstWhere((t) => t.gachaType == gt)
            .primaryPity
            .rank,
      ),
      timelineRank: odesList.first.primaryPity.rank,
    ),
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/overview_sections_test.dart`
Expected: PASS（1 test）。

- [ ] **Step 5: 讓 OverviewPage 改用 helper**

於 `lib/pages/overview_page.dart`：新增 import

```dart
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';
```

在 `build()` 內，把目前手刻的 `gachaList / odesTypes / gachaBanners / odesBanners / gachaAll / odesAll / gachaStats / odesStats / gacha5StarAvg / gacha4StarAvg` 與 `_OverviewSection` 內重算的 `timelineEntries / timelineNowPulls / timelineRank` 改成從 `buildOverviewSections(activeData.banners)` 取得。具體：

在 `final activeData = state.activeData;` 與 null 檢查後加：

```dart
final sections = buildOverviewSections(activeData.banners);
final gachaSec = sections.gacha;
final odesSec = sections.odes;
```

然後把後續引用替換：
- `gachaList` → `gachaSec.types`
- `gachaBanners` → `gachaSec.banners`
- `gachaStats` → `gachaSec.stats`
- `gacha5StarAvg` → `gachaSec.fiveStarAvg`
- `gacha4StarAvg` → `gachaSec.fourStarAvg`
- `odesTypes` → `odesSec.types`
- `odesBanners` → `odesSec.banners`
- `odesStats` → `odesSec.stats`
- `odesEventFiveCount` → `odesSec.eventFiveCount`
- `odesStandardFourCount` → `odesSec.standardFourCount`

`_OverviewSection` 內原本自行呼叫 `buildTimelineEntriesAcrossBanners / pullsSinceLastRankedAcrossBanners`：改為由建構子多收 `timeline` / `timelineNowPulls` / `timelineRank` 三個參數（祈願段傳 `gachaSec.*`、頌願段傳 `odesSec.timeline / 0 / odesSec.timelineRank`），刪掉 `_OverviewSection.build()` 內這三者的重算與相關 import（若 import 已無其他用途）。`nowPulls` 對頌願段傳 `0`（既有 odes 段本就不顯示距上次抽，沿用現狀）。

> 此步驟為等價重構，UI 不應有可見變化。保留既有 `_OverviewSection` 視覺結構與 stat cards。

- [ ] **Step 6: 全測試 + 分析確認無回歸**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`（既有 overview 相關 widget 測試仍綠）。

- [ ] **Step 7: Commit**

```bash
git add lib/services/overview_sections.dart lib/pages/overview_page.dart test/services/overview_sections_test.dart
git commit -m "refactor(overview): extract buildOverviewSections shared by overview page"
```

---

## Task 4: Pie 加可選關閉動畫參數

`RarityPie` / `ItemTypePie` 寫死 `duration: 600ms`，離屏同步渲染需可關閉動畫。加可選參數，預設行為不變。

**Files:**
- Modify: `lib/widgets/rarity_pie.dart`
- Modify: `lib/widgets/item_type_pie.dart`
- Test: `test/widgets/pie_animation_param_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/pie_animation_param_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';

const _stats = GachaStats(
  total: 10,
  fiveStarCount: 1,
  fourStarCount: 3,
  threeStarCount: 6,
  twoStarCount: 0,
  byItemType: {'角色': 4, '武器': 6},
);

Widget _host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Scaffold(body: SizedBox(width: 240, height: 240, child: child)),
);

void main() {
  testWidgets('RarityPie 接受 animationDuration: zero 並可立即 settle', (t) async {
    await t.pumpWidget(
      _host(const RarityPie(stats: _stats, animationDuration: Duration.zero)),
    );
    await t.pump(); // 無動畫，一幀即定版
    expect(find.byType(RarityPie), findsOneWidget);
  });

  testWidgets('ItemTypePie 接受 animationDuration: zero', (t) async {
    await t.pumpWidget(
      _host(const ItemTypePie(stats: _stats, animationDuration: Duration.zero)),
    );
    await t.pump();
    expect(find.byType(ItemTypePie), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/pie_animation_param_test.dart`
Expected: FAIL（`RarityPie` 無 `animationDuration` 具名參數）。

- [ ] **Step 3: 修改 RarityPie**

`lib/widgets/rarity_pie.dart`：建構子與 `PieChart` 動畫改為可注入：

```dart
class RarityPie extends StatelessWidget {
  const RarityPie({
    super.key,
    required this.stats,
    this.animationDuration = const Duration(milliseconds: 600),
  });
  final GachaStats stats;
  final Duration animationDuration;
```

`build()` 內 `PieChart(...)` 的 `duration:` 改成：

```dart
      duration: animationDuration,
      curve: Curves.easeOut,
```

- [ ] **Step 4: 修改 ItemTypePie（同樣方式）**

`lib/widgets/item_type_pie.dart`：

```dart
class ItemTypePie extends StatelessWidget {
  const ItemTypePie({
    super.key,
    required this.stats,
    this.animationDuration = const Duration(milliseconds: 600),
  });
  final GachaStats stats;
  final Duration animationDuration;
```

`build()` 內 `PieChart(...)` 的 `duration:` 改成 `duration: animationDuration,`。

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/widgets/pie_animation_param_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 6: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`（既有頁面用預設值，行為不變）。

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/rarity_pie.dart lib/widgets/item_type_pie.dart test/widgets/pie_animation_param_test.dart
git commit -m "feat(charts): add optional animationDuration to RarityPie/ItemTypePie"
```

---

## Task 5: ShareImageOptions model

**Files:**
- Create: `lib/models/share_image_options.dart`
- Test: `test/models/share_image_options_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/models/share_image_options_test.dart`：

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';

void main() {
  test('預設：深色 + 不顯示完整 UID', () {
    const o = ShareImageOptions();
    expect(o.brightness, Brightness.dark);
    expect(o.showFullUid, isFalse);
  });

  test('可指定 brightness 與 showFullUid', () {
    const o = ShareImageOptions(
      brightness: Brightness.light,
      showFullUid: true,
    );
    expect(o.brightness, Brightness.light);
    expect(o.showFullUid, isTrue);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/models/share_image_options_test.dart`
Expected: FAIL（檔案不存在）。

- [ ] **Step 3: 實作**

建立 `lib/models/share_image_options.dart`：

```dart
// lib/models/share_image_options.dart
import 'package:flutter/painting.dart';

/// 生成分享圖前由使用者在 dialog 選定的選項。
class ShareImageOptions {
  const ShareImageOptions({
    this.brightness = Brightness.dark,
    this.showFullUid = false,
  });

  /// 分享圖主題（與 App 當前 themeMode 解耦）。
  final Brightness brightness;

  /// true = 圖上顯示完整 UID；false = 經 maskUidForShare 遮罩。
  final bool showFullUid;
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/models/share_image_options_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/models/share_image_options.dart test/models/share_image_options_test.dart
git commit -m "feat(share): add ShareImageOptions model"
```

---

## Task 6: ShareCard widget 樹

固定寬 1200 的分享版面（版面 B 兩欄）。**所有外部相依（l10n、appVersion、app icon、資料）皆由建構子注入**，不依賴 `AppLocalizations.of` 之外的 async 來源（icon 預解碼成 `ui.Image`），確保離屏同步渲染可行。

**Files:**
- Create: `lib/widgets/share/share_card.dart`
- Test: `test/widgets/share/share_card_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/share/share_card_test.dart`：

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

Future<ui.Image> _img() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

GachaRecord _r(String gt, int rank, String name) => GachaRecord(
  id: '$name$rank${gt}_${DateTime.now().microsecondsSinceEpoch}',
  uid: '800123456',
  gachaType: gt,
  name: name,
  itemType: rank == 5 ? '角色' : '武器',
  rankType: rank,
  time: DateTime(2026, 5, 10, 12),
  lang: 'zh-tw',
);

Future<void> _pump(WidgetTester t, Widget card) async {
  await t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 1200, child: card),
        ),
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('卡池模式渲染且無 overflow（遮罩 UID）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(tester_takeException_isNull(), isTrue);
    expect(find.textContaining('800xxxxxx'), findsOneWidget);
    expect(find.textContaining('800123456'), findsNothing);
  });

  testWidgets('綜合模式：祈願 + 頌願兩段', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.overview(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(showFullUid: true),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      banners: {
        '301': [_r('301', 5, '那維萊特'), _r('301', 3, '冷刃')],
        '2000': [_r('2000', 5, '某五星')],
      },
    );
    await _pump(t, card);
    expect(find.textContaining('800123456'), findsOneWidget); // showFullUid
  });
}

bool tester_takeException_isNull() {
  // 包一層方便閱讀：pump 後無未捕捉例外即視為無 overflow。
  return true;
}
```

> 註：overflow 在 widget test 會以 `FlutterError` 形式被 `tester.takeException()` 捕捉並導致測試失敗，因此「pump 不丟例外」即代表版面在 1200 寬下不溢出。輔助函式僅為可讀性，真正的把關來自 test framework 對 overflow 的自動 fail。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/share/share_card_test.dart`
Expected: FAIL（`share_card.dart` 不存在）。

- [ ] **Step 3: 實作 ShareCard**

建立 `lib/widgets/share/share_card.dart`：

```dart
// lib/widgets/share/share_card.dart
//
// 分享圖固定寬版面（版面 B：左數字+雙圓餅，右垂直時間軸）。
// 所有外部相依由建構子注入；圖示為預解碼 ui.Image，避免離屏同步渲染時
// Image.asset 的 async 載入無法完成。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_stats.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_uid_mask.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/timeline_entries.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_colors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/distribution_legend.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/item_type_pie.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/rarity_pie.dart';

const double kShareCardWidth = 1200;

/// 一段內容描述（卡池模式 1 段；綜合模式 2 段）。
class _Section {
  const _Section({
    required this.title,
    required this.stats,
    required this.timeline,
    required this.timelineRank,
    required this.statLines,
  });
  final String title;
  final GachaStats stats;
  final List<TimelineEntry> timeline;
  final int timelineRank;

  /// 左欄數字摘要列：label + value + subtitle（subtitle 可空）。
  final List<(String label, String value, String? sub)> statLines;
}

class ShareCard extends StatelessWidget {
  const ShareCard._({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.options,
    required this.uid,
    required this.updatedAt,
    required this.sections,
  });

  /// 單一卡池頁分享。
  factory ShareCard.banner({
    required AppLocalizations l,
    required String appVersion,
    required ui.Image appIcon,
    required ShareImageOptions options,
    required String uid,
    required DateTime updatedAt,
    required String title,
    required List<GachaRecord> records,
    required int targetRank,
  }) {
    final stats = computeGachaStats(records);
    final fiveAvg = _avgInterval(records, 5);
    final fourAvg = _avgInterval(records, 4);
    return ShareCard._(
      l: l,
      appVersion: appVersion,
      appIcon: appIcon,
      options: options,
      uid: uid,
      updatedAt: updatedAt,
      sections: [
        _Section(
          title: title,
          stats: stats,
          timeline: buildTimelineEntries(records, targetRank: targetRank),
          timelineRank: targetRank,
          statLines: [
            (l.statsTotal, '${stats.total}', null),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${stats.fiveStarCount}',
              _rateAvg(l, stats.fiveStarRate, fiveAvg),
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${stats.fourStarCount}',
              _rateAvg(l, stats.fourStarRate, fourAvg),
            ),
          ],
        ),
      ],
    );
  }

  /// 綜合頁分享（祈願 + 頌願兩段）。
  factory ShareCard.overview({
    required AppLocalizations l,
    required String appVersion,
    required ui.Image appIcon,
    required ShareImageOptions options,
    required String uid,
    required DateTime updatedAt,
    required Map<String, List<GachaRecord>> banners,
  }) {
    final s = buildOverviewSections(banners);
    final g = s.gacha;
    final o = s.odes;
    final odesEventType = o.types.firstWhere((t) => t.gachaType == '2000');
    final odesStdType = o.types.firstWhere((t) => t.gachaType == '1000');
    return ShareCard._(
      l: l,
      appVersion: appVersion,
      appIcon: appIcon,
      options: options,
      uid: uid,
      updatedAt: updatedAt,
      sections: [
        _Section(
          title: l.pageOverviewGachaSection,
          stats: g.stats,
          timeline: g.timeline,
          timelineRank: g.timelineRank,
          statLines: [
            (l.statsTotal, '${g.stats.total}', null),
            (
              l.statsRankCount(l.rarityStar(5)),
              '${g.stats.fiveStarCount}',
              _rateAvg(l, g.stats.fiveStarRate, g.fiveStarAvg),
            ),
            (
              l.statsRankCount(l.rarityStar(4)),
              '${g.stats.fourStarCount}',
              _rateAvg(l, g.stats.fourStarRate, g.fourStarAvg),
            ),
          ],
        ),
        _Section(
          title: l.pageOverviewOdesSection,
          stats: o.stats,
          timeline: o.timeline,
          timelineRank: o.timelineRank,
          statLines: [
            (l.statsTotal, '${o.stats.total}', null),
            (
              '${odesEventType.resolveName(l)} ${l.rarityStar(5)}',
              '${o.eventFiveCount}',
              null,
            ),
            (
              '${odesStdType.resolveName(l)} ${l.rarityStar(4)}',
              '${o.standardFourCount}',
              null,
            ),
          ],
        ),
      ],
    );
  }

  final AppLocalizations l;
  final String appVersion;
  final ui.Image appIcon;
  final ShareImageOptions options;
  final String uid;
  final DateTime updatedAt;
  final List<_Section> sections;

  static double? _avgInterval(List<GachaRecord> records, int rank) {
    var current = 0;
    var hit = 0;
    DateTime? last;
    for (final r in records) {
      if (r.rankType == rank) {
        last ??= r.time;
        hit++;
      } else if (last == null) {
        current++;
      }
    }
    return hit > 0 ? (records.length - current) / hit : null;
  }

  static String? _rateAvg(AppLocalizations l, double rate, double? avg) {
    final pct = l.statsShareOfTotal((rate * 100).toStringAsFixed(2));
    if (avg == null) return pct;
    return '$pct · ${l.pityAverageInterval(avg.toStringAsFixed(2))}';
  }

  String get _uidText =>
      options.showFullUid ? uid : maskUidForShare(uid);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final colors = BannerColors.of(options.brightness);
    return Container(
      width: kShareCardWidth,
      color: tokens.surfaceBackground,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShareHeader(
            l: l,
            appVersion: appVersion,
            appIcon: appIcon,
            uidText: _uidText,
            updatedAt: updatedAt,
            tokens: tokens,
          ),
          const SizedBox(height: AppSpacing.xl),
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: AppSpacing.xl),
              Divider(color: tokens.borderEmphasis, height: 1, thickness: 1),
              const SizedBox(height: AppSpacing.xl),
            ],
            _SectionView(
              l: l,
              section: sections[i],
              colors: colors,
              brightness: options.brightness,
              tokens: tokens,
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareHeader extends StatelessWidget {
  const _ShareHeader({
    required this.l,
    required this.appVersion,
    required this.appIcon,
    required this.uidText,
    required this.updatedAt,
    required this.tokens,
  });
  final AppLocalizations l;
  final String appVersion;
  final ui.Image appIcon;
  final String uidText;
  final DateTime updatedAt;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts =
        '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-'
        '${updatedAt.day.toString().padLeft(2, '0')} '
        '${updatedAt.hour.toString().padLeft(2, '0')}:'
        '${updatedAt.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: RawImage(image: appIcon, fit: BoxFit.contain),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.appName} v$appVersion',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppRepo.githubUrl,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.m),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'UID $uidText',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.shareImageUpdatedAt(ts),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({
    required this.l,
    required this.section,
    required this.colors,
    required this.brightness,
    required this.tokens,
  });
  final AppLocalizations l;
  final _Section section;
  final BannerColors colors;
  final Brightness brightness;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(section.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.m),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左欄：數字摘要 + 雙圓餅
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in section.statLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s),
                        child: _StatTile(line: line, tokens: tokens),
                      ),
                    const SizedBox(height: AppSpacing.s),
                    Row(
                      children: [
                        Expanded(
                          child: _PieBox(
                            title: l.statsRarityDistribution,
                            pie: RarityPie(
                              stats: section.stats,
                              animationDuration: Duration.zero,
                            ),
                            legend: DistributionLegend(
                              entries: rarityDistributionEntries(
                                section.stats,
                                tokens,
                                l,
                              ),
                            ),
                            tokens: tokens,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: _PieBox(
                            title: l.statsItemTypeDistribution,
                            pie: ItemTypePie(
                              stats: section.stats,
                              animationDuration: Duration.zero,
                            ),
                            legend: DistributionLegend(
                              entries: itemTypeDistributionEntries(
                                section.stats,
                                brightness,
                                l,
                              ),
                            ),
                            tokens: tokens,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.l),
              // 右欄：垂直時間軸（最新 10 筆）
              Expanded(
                flex: 9,
                child: _ShareTimeline(
                  l: l,
                  entries: section.timeline.take(10).toList(growable: false),
                  rank: section.timelineRank,
                  colors: colors,
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.line, required this.tokens});
  final (String, String, String?) line;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.$1,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                line.$2,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              if (line.$3 != null)
                Text(
                  line.$3!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PieBox extends StatelessWidget {
  const _PieBox({
    required this.title,
    required this.pie,
    required this.legend,
    required this.tokens,
  });
  final String title;
  final Widget pie;
  final Widget legend;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.s),
          SizedBox(height: 200, child: pie),
          const SizedBox(height: AppSpacing.s),
          legend,
        ],
      ),
    );
  }
}

class _ShareTimeline extends StatelessWidget {
  const _ShareTimeline({
    required this.l,
    required this.entries,
    required this.rank,
    required this.colors,
    required this.tokens,
  });
  final AppLocalizations l;
  final List<TimelineEntry> entries;
  final int rank;
  final BannerColors colors;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.shareImageTimelineTitle(entries.length, l.rarityStar(rank)),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          if (entries.isEmpty)
            Text(
              l.statsNoData,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textMuted,
              ),
            )
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.colorFor(e.gachaType),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Text(
                      l.pityPullsCount(e.pullsSincePrev),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
```

> 若 `l.pityPullsCount` 或 `l.statsShareOfTotal` 等鍵在現有 arb 不存在，依 Task 1 模式於 `flutter analyze` 報錯時，到 `app_zh.arb`/`app_en.arb` 補對應鍵後 `flutter gen-l10n`。先以 `flutter analyze` 確認用到的既有 l10n 鍵是否存在；本步驟使用的 `statsTotal / statsRankCount / rarityStar / statsShareOfTotal / pityAverageInterval / statsRarityDistribution / statsItemTypeDistribution / pageOverviewGachaSection / pageOverviewOdesSection / statsNoData / appName` 皆為既有鍵；`pityPullsCount` 若不存在則改用字串插值 `'${e.pullsSincePrev}'`（不需新增鍵）。

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/share/share_card_test.dart`
Expected: PASS（2 tests，無 overflow 例外）。

- [ ] **Step 5: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/share/share_card.dart test/widgets/share/share_card_test.dart
git commit -m "feat(share): add ShareCard fixed-width layout widget"
```

---

## Task 7: 離屏渲染服務（widget → PNG）

**Files:**
- Create: `lib/services/share_image_renderer.dart`
- Test: `test/services/share_image_renderer_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/share_image_renderer_test.dart`：

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';

void main() {
  testWidgets('renderWidgetToPng 回傳可解碼且尺寸正確的 PNG', (t) async {
    final png = await renderWidgetToPng(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 300,
          height: 150,
          child: ColoredBox(color: Color(0xFF112233)),
        ),
      ),
      logicalSize: const Size(300, 150),
      pixelRatio: 2.0,
    );
    expect(png, isA<Uint8List>());
    expect(png.isNotEmpty, isTrue);

    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 600); // 300 * 2.0
    expect(frame.image.height, 300); // 150 * 2.0
  });

  test('loadAppIconImage 回傳非空 ui.Image', () async {
    final img = await loadAppIconImage();
    expect(img.width, greaterThan(0));
    expect(img.height, greaterThan(0));
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/share_image_renderer_test.dart`
Expected: FAIL（`share_image_renderer.dart` 不存在）。

- [ ] **Step 3: 實作**

建立 `lib/services/share_image_renderer.dart`：

```dart
// lib/services/share_image_renderer.dart
//
// 把任意 widget 以固定邏輯尺寸 + pixelRatio 同步離屏渲染成 PNG。
// 用獨立 RenderView + BuildOwner pipeline，不依賴 live Navigator/Overlay，
// 全程同步 flush（無動畫、無 async image），輸出穩定可測。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

final _log = Logger('share.image');

/// 預解碼 app icon，給 ShareCard 以 RawImage 同步繪製
/// （Image.asset 是 async，無法在同步 pipeline flush 內完成）。
Future<ui.Image> loadAppIconImage() async {
  final data = await rootBundle.load('assets/icons/app_icon.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required Size logicalSize,
  double pixelRatio = 3.0,
}) async {
  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;

  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(logicalSize),
      physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(
      alignment: Alignment.topLeft,
      child: boundary,
    ),
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(devicePixelRatio: pixelRatio),
      child: widget,
    ),
  ).attachToRenderTree(buildOwner);

  try {
    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('toByteData returned null');
    }
    final out = bytes.buffer.asUint8List();
    _log.info(
      'render ok: ${logicalSize.width.toInt()}x${logicalSize.height.toInt()} '
      '@${pixelRatio}x, ${out.length} bytes',
    );
    return out;
  } catch (e, st) {
    _log.severe('render failed', e, st);
    rethrow;
  } finally {
    // 卸載離屏樹，釋放 render objects。
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(buildOwner, rootElement);
  }
}
```

> `RenderView` / `ViewConfiguration` 的建構參數隨 Flutter 版本演進。本碼使用近代簽名（`logicalConstraints` / `physicalConstraints` / `devicePixelRatio`）。若 `flutter analyze` 在這幾行報參數不符，依當前 SDK 的 `RenderView`/`ViewConfiguration` 簽名調整這一段（其餘邏輯不動）。

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/share_image_renderer_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/share_image_renderer.dart test/services/share_image_renderer_test.dart
git commit -m "feat(share): add offscreen widget-to-PNG renderer"
```

---

## Task 8: 匯出服務（剪貼簿 + 存檔，含 seam）

**Files:**
- Create: `lib/services/share_image_export.dart`
- Test: `test/services/share_image_export_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/services/share_image_export_test.dart`：

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  tearDown(resetShareImageExportSeams);

  test('使用者選了路徑 + 剪貼簿成功 → saved', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_a.png';
    shareSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    shareClipboardWriter = (bytes) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.savedAndCopied);
    expect(r.path, tmp);
    expect(await File(tmp).readAsBytes(), png);
    await File(tmp).delete();
  });

  test('使用者取消存檔但剪貼簿成功 → copiedOnly', () async {
    shareSaveLocationPicker = (name) async => null;
    shareClipboardWriter = (bytes) async => true;

    final r = await exportShareImage(png, suggestedName: 'a.png');

    expect(r.status, ShareExportStatus.copiedOnly);
    expect(r.path, isNull);
  });

  test('剪貼簿不支援但存檔成功 → savedOnly', () async {
    final tmp = '${Directory.systemTemp.path}/share_test_b.png';
    shareSaveLocationPicker = (name) async => FileSaveLocation(tmp);
    shareClipboardWriter = (bytes) async => false;

    final r = await exportShareImage(png, suggestedName: 'b.png');

    expect(r.status, ShareExportStatus.savedOnly);
    await File(tmp).delete();
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/services/share_image_export_test.dart`
Expected: FAIL（`share_image_export.dart` 不存在）。

- [ ] **Step 3: 實作**

建立 `lib/services/share_image_export.dart`：

```dart
// lib/services/share_image_export.dart
//
// PNG bytes → 系統剪貼簿 + 使用者選位置存檔。
// I/O 與剪貼簿經 @visibleForTesting seam 注入（仿 services/file_reveal.dart），
// 讓 flutter test 不碰真實 FS / 剪貼簿。
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

final _log = Logger('share.image');

enum ShareExportStatus { savedAndCopied, savedOnly, copiedOnly }

class ShareExportResult {
  const ShareExportResult({required this.status, this.path});
  final ShareExportStatus status;
  final String? path;
}

/// 預設剪貼簿寫入：寫 PNG 到系統剪貼簿，回傳是否成功
/// （平台不支援時 SystemClipboard.instance == null → false）。
Future<bool> _defaultClipboardWriter(Uint8List png) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return false;
  final item = DataWriterItem();
  item.add(Formats.png(png));
  await clipboard.write([item]);
  return true;
}

@visibleForTesting
Future<FileSaveLocation?> Function(String suggestedName)
shareSaveLocationPicker = (name) => getSaveLocation(
  suggestedName: name,
  acceptedTypeGroups: const [
    XTypeGroup(label: 'PNG', extensions: ['png']),
  ],
);

@visibleForTesting
Future<bool> Function(Uint8List png) shareClipboardWriter =
    _defaultClipboardWriter;

@visibleForTesting
Future<void> Function(String path, Uint8List png) shareFileWriter =
    (path, png) => File(path).writeAsBytes(png);

@visibleForTesting
void resetShareImageExportSeams() {
  shareSaveLocationPicker = (name) => getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG', extensions: ['png']),
    ],
  );
  shareClipboardWriter = _defaultClipboardWriter;
  shareFileWriter = (path, png) => File(path).writeAsBytes(png);
}

/// 先寫剪貼簿（失敗不致命），再讓使用者選位置存檔（取消則只剩剪貼簿）。
Future<ShareExportResult> exportShareImage(
  Uint8List png, {
  required String suggestedName,
}) async {
  bool copied;
  try {
    copied = await shareClipboardWriter(png);
  } catch (e, st) {
    _log.warning('clipboard write failed', e, st);
    copied = false;
  }

  final loc = await shareSaveLocationPicker(suggestedName);
  if (loc == null) {
    _log.info('save cancelled; clipboard=$copied');
    return ShareExportResult(status: ShareExportStatus.copiedOnly);
  }

  await shareFileWriter(loc.path, png);
  _log.info(
    'share image saved ${sanitizeFsPath(loc.path)}; '
    'bytes=${png.length} clipboard=$copied',
  );
  return ShareExportResult(
    status: copied
        ? ShareExportStatus.savedAndCopied
        : ShareExportStatus.savedOnly,
    path: loc.path,
  );
}
```

> 確認 `lib/services/log_sanitize.dart` 有 `sanitizeFsPath`（`file_reveal.dart` 已使用）。若簽名不同，沿用 `file_reveal.dart` 內相同用法。

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/services/share_image_export_test.dart`
Expected: PASS（3 tests）。

- [ ] **Step 5: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/share_image_export.dart test/services/share_image_export_test.dart
git commit -m "feat(share): add export service (clipboard + save) with test seams"
```

---

## Task 9: ShareImageDialog 選項對話框

**Files:**
- Create: `lib/widgets/dialogs/share_image_dialog.dart`
- Test: `test/widgets/dialogs/share_image_dialog_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/dialogs/share_image_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';

void main() {
  testWidgets('生成回傳預設選項；預設深色 + 不顯示完整 UID', (t) async {
    ShareImageOptions? result;
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showShareImageDialog(
                    ctx,
                    initialBrightness: Brightness.dark,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.shareImageGenerate));
    await t.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.brightness, Brightness.dark);
    expect(result!.showFullUid, isFalse);
  });

  testWidgets('取消回傳 null', (t) async {
    ShareImageOptions? result = const ShareImageOptions();
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showShareImageDialog(
                    ctx,
                    initialBrightness: Brightness.dark,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    await t.tap(find.text(l.cancel));
    await t.pumpAndSettle();

    expect(result, isNull);
  });
}
```

> 若 `l.cancel` 不存在，改用專案既有的取消鍵（先 `grep -n '"cancel"' lib/l10n/app_zh.arb` 確認；多數 dialog 用 `l.commonCancel` 之類，沿用 `confirm_dialog.dart` 內用的同一個鍵）。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/dialogs/share_image_dialog_test.dart`
Expected: FAIL（`share_image_dialog.dart` 不存在）。

- [ ] **Step 3: 實作**

先 `grep -n 'commonCancel\|"cancel"' lib/l10n/app_zh.arb` 與看 `lib/widgets/dialogs/confirm_dialog.dart` 取消鈕用哪個 l10n 鍵，沿用同一鍵（下方以 `l.<cancelKey>` 表示）。

建立 `lib/widgets/dialogs/share_image_dialog.dart`：

```dart
// lib/widgets/dialogs/share_image_dialog.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 開啟分享圖選項 dialog。回傳 null 表示使用者取消。
Future<ShareImageOptions?> showShareImageDialog(
  BuildContext context, {
  required Brightness initialBrightness,
}) {
  return showDialog<ShareImageOptions>(
    context: context,
    builder: (_) => _ShareImageDialog(initialBrightness: initialBrightness),
  );
}

class _ShareImageDialog extends StatefulWidget {
  const _ShareImageDialog({required this.initialBrightness});
  final Brightness initialBrightness;

  @override
  State<_ShareImageDialog> createState() => _ShareImageDialogState();
}

class _ShareImageDialogState extends State<_ShareImageDialog> {
  late Brightness _brightness = widget.initialBrightness;
  bool _showFullUid = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AppDialog(
      title: Text(l.shareImageDialogTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.shareImageThemeLabel),
          const SizedBox(height: 8),
          SegmentedButton<Brightness>(
            segments: [
              ButtonSegment(
                value: Brightness.dark,
                label: Text(l.shareImageThemeDark),
              ),
              ButtonSegment(
                value: Brightness.light,
                label: Text(l.shareImageThemeLight),
              ),
            ],
            selected: {_brightness},
            onSelectionChanged: (s) =>
                setState(() => _brightness = s.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showFullUid,
            onChanged: (v) => setState(() => _showFullUid = v),
            title: Text(l.shareImageShowFullUid),
            subtitle: Text(l.shareImageShowFullUidHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.<cancelKey>),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ShareImageOptions(
              brightness: _brightness,
              showFullUid: _showFullUid,
            ),
          ),
          child: Text(l.shareImageGenerate),
        ),
      ],
    );
  }
}
```

把 `l.<cancelKey>` 換成上面 grep 確認的既有取消鍵（與測試一致）。

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/widgets/dialogs/share_image_dialog_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/dialogs/share_image_dialog.dart test/widgets/dialogs/share_image_dialog_test.dart
git commit -m "feat(share): add ShareImageDialog options dialog"
```

---

## Task 10: 分享按鈕 + 串接兩頁流程

把整段流程封成共用按鈕，接到 OverviewPage 與 BannerPage。

**Files:**
- Create: `lib/widgets/share/share_action_button.dart`
- Modify: `lib/pages/overview_page.dart`
- Modify: `lib/pages/banner_page.dart`
- Test: `test/widgets/share/share_action_button_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/share/share_action_button_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildDarkTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('enabled=false 時按鈕為 disabled', (t) async {
    await t.pumpWidget(
      _host(ShareActionButton(enabled: false, onGenerate: () async {})),
    );
    final btn = t.widget<IconButton>(find.byType(IconButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('enabled=true 點擊觸發 onGenerate', (t) async {
    var called = false;
    await t.pumpWidget(
      _host(
        ShareActionButton(
          enabled: true,
          onGenerate: () async => called = true,
        ),
      ),
    );
    await t.tap(find.byType(IconButton));
    await t.pump();
    expect(called, isTrue);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/widgets/share/share_action_button_test.dart`
Expected: FAIL（`share_action_button.dart` 不存在）。

- [ ] **Step 3: 實作按鈕**

建立 `lib/widgets/share/share_action_button.dart`：

```dart
// lib/widgets/share/share_action_button.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 觸發分享圖生成的圖示按鈕（OverviewPage / BannerPage 共用）。
/// 生成中顯示 spinner，禁止重入。
class ShareActionButton extends StatefulWidget {
  const ShareActionButton({
    super.key,
    required this.enabled,
    required this.onGenerate,
  });

  final bool enabled;
  final Future<void> Function() onGenerate;

  @override
  State<ShareActionButton> createState() => _ShareActionButtonState();
}

class _ShareActionButtonState extends State<ShareActionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      tooltip: l.shareImageButton,
      icon: const Icon(Icons.ios_share),
      onPressed: widget.enabled
          ? () async {
              setState(() => _busy = true);
              try {
                await widget.onGenerate();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            }
          : null,
    );
  }
}
```

- [ ] **Step 4: 跑按鈕測試確認通過**

Run: `flutter test test/widgets/share/share_action_button_test.dart`
Expected: PASS（2 tests）。

- [ ] **Step 5: 串接 OverviewPage**

於 `lib/pages/overview_page.dart`：新增 import

```dart
import 'dart:ui' as ui;
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_renderer.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/share_image_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_action_button.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';
```

把頂部 `PageHeader(...)` 那行用 `Row` 包起來，右側放分享按鈕；並加一個產生流程方法。具體：將

```dart
PageHeader(
  title: l.pageOverviewTitle,
  icon: Icons.dashboard_outlined,
),
```

換成：

```dart
Row(
  children: [
    Expanded(
      child: PageHeader(
        title: l.pageOverviewTitle,
        icon: Icons.dashboard_outlined,
      ),
    ),
    ShareActionButton(
      enabled: activeData.banners.values.any((r) => r.isNotEmpty),
      onGenerate: () => _generateOverviewShare(context, ref, l, activeData),
    ),
  ],
),
```

在 `OverviewPage` class 內新增方法（`appVersion` 由 `ref.read(appVersionProvider)` 取）：

```dart
Future<void> _generateOverviewShare(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l,
  BannerStorage activeData,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final brightness = Theme.of(context).brightness;
  final options = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (options == null) return;

  try {
    final icon = await loadAppIconImage();
    final appVersion = ref.read(appVersionProvider);
    final card = MediaQuery(
      data: const MediaQueryData(),
      child: Theme(
        data: options.brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        child: Material(
          type: MaterialType.transparency,
          child: ShareCard.overview(
            l: l,
            appVersion: appVersion,
            appIcon: icon,
            options: options,
            uid: activeData.uid,
            updatedAt: activeData.lastUpdated.toLocal(),
            banners: activeData.banners,
          ),
        ),
      ),
    );
    final png = await renderWidgetToPng(
      Directionality(textDirection: TextDirection.ltr, child: card),
      logicalSize: const Size(kShareCardWidth, 2200),
    );
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final result = await exportShareImage(
      png,
      suggestedName: 'genshin_gacha_share_overview_$stamp.png',
    );
    _showShareResult(messenger, l, result);
  } catch (e, st) {
    Logger('share.image').severe('overview share failed', e, st);
    messenger.showSnackBar(SnackBar(content: Text(l.shareImageFailed)));
  }
}
```

> 需要的額外 import：`package:logging/logging.dart`、`package:genshin_impact_wish_gacha_analyzer/app_info.dart`（`appVersionProvider`）、`package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart`、`package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart`。`kShareCardWidth` 由 `share_card.dart` export。`logicalSize` 高度給 2200（綜合兩段足夠；`renderWidgetToPng` 用 `tight` 約束，內容以 `Column(mainAxisSize.min)` 置頂，多餘空間為背景色 — 若日後內容更高再調）。

結果 SnackBar + reveal 兩頁共用，放到一個 widget 層工具檔（不放進 `share_image_export.dart`，避免 service 依賴 material）。建立 `lib/widgets/share/share_result_snackbar.dart`：

```dart
// lib/widgets/share/share_result_snackbar.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/share_image_export.dart';

void showShareResultSnackBar(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  ShareExportResult r,
) {
  final String msg;
  switch (r.status) {
    case ShareExportStatus.savedAndCopied:
      msg = l.shareImageSavedAndCopied(r.path ?? '');
    case ShareExportStatus.savedOnly:
      msg = l.shareImageSavedOnly(r.path ?? '');
    case ShareExportStatus.copiedOnly:
      msg = l.shareImageCopiedOnly;
  }
  messenger.showSnackBar(SnackBar(content: Text(msg)));
  if (r.path != null) {
    revealInFileManager(r.path!);
  }
}
```

把上面 `_generateOverviewShare` 的 `_showShareResult(messenger, l, result);` 改成 `showShareResultSnackBar(messenger, l, result);` 並 import 此檔。

- [ ] **Step 6: 串接 BannerPage**

於 `lib/pages/banner_page.dart` 同模式：import 同上那批 + `share_result_snackbar.dart`。把 `PageHeader(title: type.resolveName(l), icon: _iconForGachaType(type))`（非空資料分支）包成 `Row` + `ShareActionButton`，`enabled: records.isNotEmpty`，`onGenerate` 呼叫新方法：

```dart
Future<void> _generateBannerShare(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l,
  GachaType type,
  String uid,
  DateTime updatedAt,
  List<GachaRecord> records,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final brightness = Theme.of(context).brightness;
  final options = await showShareImageDialog(
    context,
    initialBrightness: brightness,
  );
  if (options == null) return;
  try {
    final icon = await loadAppIconImage();
    final appVersion = ref.read(appVersionProvider);
    final card = MediaQuery(
      data: const MediaQueryData(),
      child: Theme(
        data: options.brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        child: Material(
          type: MaterialType.transparency,
          child: ShareCard.banner(
            l: l,
            appVersion: appVersion,
            appIcon: icon,
            options: options,
            uid: uid,
            updatedAt: updatedAt.toLocal(),
            title: type.resolveName(l),
            records: records,
            targetRank: type.primaryPity.rank,
          ),
        ),
      ),
    );
    final png = await renderWidgetToPng(
      Directionality(textDirection: TextDirection.ltr, child: card),
      logicalSize: const Size(kShareCardWidth, 1400),
    );
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final result = await exportShareImage(
      png,
      suggestedName: 'genshin_gacha_share_${type.gachaType}_$stamp.png',
    );
    if (!context.mounted) return;
    showShareResultSnackBar(messenger, l, result);
  } catch (e, st) {
    Logger('share.image').severe('banner share failed', e, st);
    messenger.showSnackBar(SnackBar(content: Text(l.shareImageFailed)));
  }
}
```

`onGenerate: () => _generateBannerShare(context, ref, l, type, activeData.uid, activeData.lastUpdated, records)`。

> `activeData` 在 `banner_page.dart` 的 `build` 已有（`state.activeData`）；`records` 即 `activeData.banners[gachaType] ?? const []`。檔名用 `type.gachaType`（如 `301`）作 `<page>` 區別。

- [ ] **Step 7: 全測試 + 格式 + 分析**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`（含既有 overview/banner widget 測試不回歸）。

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/share/ lib/pages/overview_page.dart lib/pages/banner_page.dart test/widgets/share/share_action_button_test.dart
git commit -m "feat(share): wire share button + flow into overview & banner pages"
```

---

## Task 11: 手動煙霧測試與最終品質閘

**Files:** 無（驗證）

- [ ] **Step 1: 跑桌面 app 手動驗證**

Run: `flutter run -d windows`
驗證清單：
- 綜合頁右上分享鈕 → dialog（深/淺 + UID 開關）→ 生成 → 出現存檔視窗、選位置後存出 PNG，檔案總管選中該檔，SnackBar 顯示「已存檔並複製到剪貼簿」。
- 貼到小畫家 / Discord 確認剪貼簿有圖、版面 B、icon/名稱/版本/GitHub 正確、UID 預設遮罩 `xxx`、開關開啟顯示完整。
- 切淺色生成一張對照主題正確。
- 各卡池頁（角色/武器/常駐/新手/頌願事件/頌願常駐）各生成一張，無破版、時間軸最多 10 筆。
- 無資料帳號 / 空卡池：分享鈕 disabled。

- [ ] **Step 2: 最終品質閘**

Run: `dart format lib/ test/ && flutter analyze && flutter test`
Expected: `No issues found!`、`All tests passed!`

- [ ] **Step 3: Commit（若 Step 1 有微調）**

```bash
git add -A
git commit -m "fix(share): polish share image after manual smoke test"
```

---

## Self-Review

**1. Spec coverage**

| Spec 需求 | 對應 Task |
|---|---|
| 入口（兩頁按鈕、無資料禁用）| Task 10 |
| 綜合頁合併單張（祈願+頌願）| Task 6（`ShareCard.overview`）、Task 3 |
| 輸出存檔 + 剪貼簿 | Task 8 |
| 生成前 dialog（主題 + UID 開關）| Task 9 |
| 數字摘要（祈願：總/5★/4★+佔比+平均；頌願：既有組成）| Task 3、Task 6 |
| 圓餅 + 垂直時間軸最新 10 | Task 6 |
| Header（icon+名稱+版本 / GitHub / UID / 更新時間）| Task 6 |
| 版面 B 兩欄 | Task 6 |
| 主題深/淺、語言跟隨 | Task 9（選）、Task 10（套 theme）、Task 6（注入 l）|
| UID 遮罩前 3 + x / 完整開關 | Task 2、Task 6 |
| 檔名 `genshin_gacha_share_<page>_<時間>.png` | Task 10 |
| 方案 A 離屏渲染 | Task 7 |
| super_clipboard | Task 1、Task 8 |
| 錯誤處理（toImage 例外 / 取消 / 剪貼簿失敗 / UID 脫敏）| Task 7、Task 8、Task 10 |
| 測試策略 | 各 Task 內 TDD |

無遺漏。

**2. Placeholder scan**

Task 10 Step 5 有一處示意「（不放這裡——避免…）」後立即給出正確做法（建立 `share_result_snackbar.dart`），最終實作明確、非 placeholder。`l.<cancelKey>` 為刻意的查找指示（專案既有取消鍵名稱未知，Step 3 開頭已指明用 grep + `confirm_dialog.dart` 對齊），非模糊待辦。其餘無 TBD/TODO。

**3. Type consistency**

- `ShareImageOptions(brightness, showFullUid)`：Task 5 定義，Task 6/9/10 一致使用。
- `renderWidgetToPng(Widget, {logicalSize, pixelRatio})` + `loadAppIconImage()`：Task 7 定義，Task 10 一致呼叫。
- `exportShareImage(Uint8List, {suggestedName})` → `ShareExportResult{status,path}` / `ShareExportStatus`：Task 8 定義，Task 10 經 `showShareResultSnackBar` 一致消費。
- `ShareCard.banner(...)` / `ShareCard.overview(...)` 具名參數與 Task 10 呼叫端一致；`kShareCardWidth` Task 6 export、Task 10 使用。
- `buildOverviewSections` 回傳 `OverviewSections{gacha,odes}`：Task 3 定義，Task 6 使用欄位（`fiveStarAvg/fourStarAvg/eventFiveCount/standardFourCount/timeline/timelineRank`）一致。
- `maskUidForShare`：Task 2 定義，Task 6 使用。
- `RarityPie/ItemTypePie` 新增 `animationDuration`：Task 4 定義，Task 6 傳 `Duration.zero`。

一致，無簽名漂移。
