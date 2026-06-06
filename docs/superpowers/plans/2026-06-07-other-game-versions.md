# Other Game Versions in About Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在原神祈願分析器設定頁「關於」區塊底部新增「其他遊戲版本」小區塊，提供指向姊妹專案「鳴潮喚取分析器」的文字連結，做法鏡像鳴潮專案。

**Architecture:** 與鳴潮專案對稱——新增 `RelatedProjects` URL 常數類與 `OtherGameVersions` widget（資料抽成 `kOtherGameVersions` 清單常數），在 `_AboutContent` 既有 banner 列之後掛上該 widget。文字連結複用既有 `AppLink`，純文字無 banner 圖片。

**Tech Stack:** Flutter（FVM 釘版）、`flutter gen-l10n`（ARB 多語）、`flutter_test`。所有指令一律優先用 `fvm`（找不到才退回 `flutter`／`dart`）。

**前置（執行起手）：** 本功能為多檔新功能，依專案慣例在 feature 分支進行（例：`feat/other-game-versions`），由 `superpowers:using-git-worktrees` 於執行時建立隔離工作區。所有 commit 落在該分支，**不直接 commit 到 master、不主動 push**。

**重要慣例：**
- 每次 `git commit` 前依序跑：`fvm dart format lib/ test/`、`fvm flutter analyze`（須 `No issues found!`）、`fvm flutter test`（須 `All tests passed!`）。
- `lib/l10n/generated/` 已進 `.gitignore`（`flutter pub get` 自動重生），**不要 commit 產生檔**；改 ARB 後手動跑 `fvm flutter gen-l10n` 讓新 getter 出現以供編譯／測試。
- ARB 結尾省略號一律用**半形三個 ASCII 句點 `...`**，**禁用**全形 `…`（含 CJK 語系）。

---

### Task 1: `RelatedProjects` URL 常數類

**Files:**
- Create: `lib/data/related_projects.dart`
- Test: `test/data/related_projects_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/data/related_projects_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';

void main() {
  test('wutheringWavesAnalyzer points to the WW convene gacha analyzer repo', () {
    expect(
      RelatedProjects.wutheringWavesAnalyzer,
      'https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer',
    );
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/data/related_projects_test.dart`
Expected: 編譯失敗，`Error: Undefined name 'RelatedProjects'` 或 `Couldn't resolve the package ...related_projects.dart`。

- [ ] **Step 3: 建立資料檔**

建立 `lib/data/related_projects.dart`：

```dart
/// 相關遊戲專案（姊妹專案）的外部連結常數。
///
/// 本 App 之外、由同作者維護的其他遊戲版本喚取／祈願分析器。集中於此檔，
/// 與 [AppRepo]（本專案座標）、[TeamInfo]（團隊連結）同性質，便於維護；
/// 未來新增其他遊戲時在此擴充一個常數。
class RelatedProjects {
  /// 防止外部實例化。
  const RelatedProjects._();

  /// 鳴潮喚取分析器專案 GitHub 頁面。
  static const String wutheringWavesAnalyzer =
      'https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer';
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/data/related_projects_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 格式化 + 分析 + commit**

Run: `fvm dart format lib/ test/`
Run: `fvm flutter analyze` — Expected: `No issues found!`

```bash
git add lib/data/related_projects.dart test/data/related_projects_test.dart
git commit -m "feat(data): add RelatedProjects constant for Wuthering Waves analyzer"
```

---

### Task 2: i18n 字串（模板 zh + en）並重新產碼

**Files:**
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`

> 此 Task 只加模板（繁中）與英文，讓後續 widget 與英文 widget 測試可編譯／執行；其餘 7 個語系在 Task 5 補上。

- [ ] **Step 1: 編輯 `lib/l10n/app_zh.arb`**

找到這一行（唯一）：

```
  "settingsAboutVersion": "版本 {version}",
```

替換為：

```
  "settingsAboutVersion": "版本 {version}",
  "settingsOtherGamesTitle": "其他遊戲版本",
  "settingsOtherGamesWutheringWaves": "鳴潮",
  "settingsOtherGamesFuture": "未來可能新增更多遊戲...",
```

（3 個新 key 插在 `settingsAboutVersion` 值與其後的 `@settingsAboutVersion` metadata 之間，JSON 順序不影響；不另加 `@` metadata，對齊鳴潮做法。）

- [ ] **Step 2: 編輯 `lib/l10n/app_en.arb`**

找到這一行（唯一）：

```
  "settingsAboutVersion": "Version {version}",
```

替換為：

```
  "settingsAboutVersion": "Version {version}",
  "settingsOtherGamesTitle": "Versions for Other Games",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "More games may be supported in the future...",
```

- [ ] **Step 3: 重新產生 l10n**

Run: `fvm flutter gen-l10n`
Expected: 無錯誤（成功時通常無輸出或顯示產生路徑）。

- [ ] **Step 4: 驗證 getter 已產生**

Run: `fvm flutter analyze lib/l10n` （或對整包跑 `fvm flutter analyze`）
Expected: `No issues found!`，且 `lib/l10n/generated/app_localizations.dart` 內已含 `settingsOtherGamesTitle`／`settingsOtherGamesWutheringWaves`／`settingsOtherGamesFuture` 三個抽象 getter。

- [ ] **Step 5: commit（只含 .arb，不含產生檔）**

```bash
git add lib/l10n/app_zh.arb lib/l10n/app_en.arb
git commit -m "feat(l10n): add other-game-versions strings (zh template, en)"
```

---

### Task 3: `OtherGameVersions` widget

**Files:**
- Create: `lib/widgets/other_game_versions.dart`
- Test: `test/widgets/other_game_versions_test.dart`

- [ ] **Step 1: 寫失敗測試**

建立 `test/widgets/other_game_versions_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/other_game_versions.dart';

/// 將 [OtherGameVersions] 包進英文語系的 [MaterialApp]，套用提供 `theme.gacha`
/// 的暗色主題。
Widget _wrap() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  theme: buildDarkTheme(),
  home: const Scaffold(body: OtherGameVersions()),
);

void main() {
  testWidgets('renders title, Wuthering Waves link and future note', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    expect(find.text('Versions for Other Games'), findsOneWidget);
    expect(find.text('Wuthering Waves'), findsOneWidget);
    expect(
      find.text('More games may be supported in the future...'),
      findsOneWidget,
    );
  });

  testWidgets('Wuthering Waves link points to the related project url', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    final link = tester.widget<AppLink>(
      find.ancestor(
        of: find.text('Wuthering Waves'),
        matching: find.byType(AppLink),
      ),
    );
    expect(link.url, RelatedProjects.wutheringWavesAnalyzer);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `fvm flutter test test/widgets/other_game_versions_test.dart`
Expected: 編譯失敗，`Error: Undefined name 'OtherGameVersions'`（widget 尚未建立）。

- [ ] **Step 3: 建立 widget**

建立 `lib/widgets/other_game_versions.dart`：

```dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// 單一「其他遊戲版本」項目：在地化遊戲名 + 專案連結。
class OtherGameVersion {
  /// 建立 [OtherGameVersion]。
  const OtherGameVersion({required this.label, required this.url});

  /// 取在地化遊戲名（傳入當前 [AppLocalizations]）。
  final String Function(AppLocalizations l) label;

  /// 點擊開啟的專案 URL。
  final String url;
}

/// 鳴潮遊戲名 resolver。const tear-off 需 top-level function（closure 非 const）。
String _wutheringWavesLabel(AppLocalizations l) =>
    l.settingsOtherGamesWutheringWaves;

/// 目前支援的其他遊戲版本清單。新增遊戲在此補一筆 + 對應 ARB key 即可，
/// 不必改動 [OtherGameVersions] widget 與設定頁。
const List<OtherGameVersion> kOtherGameVersions = [
  OtherGameVersion(
    label: _wutheringWavesLabel,
    url: RelatedProjects.wutheringWavesAnalyzer,
  ),
];

/// 設定頁「關於」區塊內的「其他遊戲版本」區塊：上方分隔線 + 小標 + 每個遊戲
/// 一列（[AppLink] 文字連結 + 靜態 open_in_new 圖示）+ 未來說明。資料來自
/// [kOtherGameVersions]，新增遊戲免改本 widget。
class OtherGameVersions extends StatelessWidget {
  /// 建立 [OtherGameVersions]。
  const OtherGameVersions({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.l),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.l),
        Text(
          l.settingsOtherGamesTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (final game in kOtherGameVersions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // open_in_new 圖示刻意放在 AppLink 之外且固定 textSecondary 色：
                // AppLink 的 hover 只透過 DefaultTextStyle 染文字、不影響 Icon
                // （Icon 取 IconTheme），放進去顏色會對不上；此處圖示僅作「會開
                // 外部瀏覽器」提示，不需隨 hover 變色。
                AppLink(url: game.url, child: Text(game.label(l))),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.open_in_new, size: 14, color: tokens.textSecondary),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s),
        Text(
          l.settingsOtherGamesFuture,
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `fvm flutter test test/widgets/other_game_versions_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 格式化 + 分析 + commit**

Run: `fvm dart format lib/ test/`
Run: `fvm flutter analyze` — Expected: `No issues found!`

```bash
git add lib/widgets/other_game_versions.dart test/widgets/other_game_versions_test.dart
git commit -m "feat(settings): add OtherGameVersions widget linking to WW analyzer"
```

---

### Task 4: 掛進設定頁「關於」區塊

**Files:**
- Modify: `lib/pages/settings_page.dart`（import 區；`_AboutContent.build` 的 banner `Wrap` 之後）

- [ ] **Step 1: 新增 import**

找到（位於 import 區，現行第 39–40 行）：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
```

替換為（依字母序插入新 import）：

```dart
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/export_result_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/other_game_versions.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
```

- [ ] **Step 2: 在 banner 列之後掛上 widget**

找到 `_AboutContent.build` 結尾的第二個 `BannerLink` 與其後收尾（含唯一字串 `genshin_info_banner.png`）：

```dart
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: TeamInfo.websiteUrl,
              semanticLabel: TeamInfo.name,
              height: 64,
            ),
          ],
        ),
      ],
    );
  }
```

替換為：

```dart
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: TeamInfo.websiteUrl,
              semanticLabel: TeamInfo.name,
              height: 64,
            ),
          ],
        ),
        const OtherGameVersions(),
      ],
    );
  }
```

- [ ] **Step 3: 格式化 + 分析**

Run: `fvm dart format lib/ test/`
Run: `fvm flutter analyze` — Expected: `No issues found!`

- [ ] **Step 4: 跑全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: commit**

```bash
git add lib/pages/settings_page.dart
git commit -m "feat(settings): show other game versions in About section"
```

---

### Task 5: 其餘 7 個非空殼語系翻譯

**Files:**
- Modify: `lib/l10n/app_zh_Hans.arb`、`app_es.arb`、`app_fr.arb`、`app_ja.arb`、`app_pt_BR.arb`、`app_th.arb`、`app_vi.arb`

> 遊戲名規則：CJK 用官方在地化名（鸣潮／鳴潮）；其餘語系保留英文「Wuthering Waves」。結尾省略號一律半形 `...`。空殼語系（af/ar/ca/cs/da/de/el/fi/he/hu/it/ko/nl/no/pl/pt/ro/ru/sr/sv/tr/uk）**不動**，留給 Crowdin。

- [ ] **Step 1: `lib/l10n/app_zh_Hans.arb`**

找到：`  "settingsAboutVersion": "版本 {version}",`，替換為：

```
  "settingsAboutVersion": "版本 {version}",
  "settingsOtherGamesTitle": "其他游戏版本",
  "settingsOtherGamesWutheringWaves": "鸣潮",
  "settingsOtherGamesFuture": "未来可能新增更多游戏...",
```

- [ ] **Step 2: `lib/l10n/app_es.arb`**

找到：`  "settingsAboutVersion": "Versión {version}",`，替換為：

```
  "settingsAboutVersion": "Versión {version}",
  "settingsOtherGamesTitle": "Versiones para otros juegos",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "Es posible que se añadan más juegos en el futuro...",
```

- [ ] **Step 3: `lib/l10n/app_fr.arb`**

找到：`  "settingsAboutVersion": "Version {version}",`，替換為：

```
  "settingsAboutVersion": "Version {version}",
  "settingsOtherGamesTitle": "Versions pour d'autres jeux",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "D'autres jeux pourraient être pris en charge à l'avenir...",
```

- [ ] **Step 4: `lib/l10n/app_ja.arb`**

找到：`  "settingsAboutVersion": "バージョン {version}",`，替換為：

```
  "settingsAboutVersion": "バージョン {version}",
  "settingsOtherGamesTitle": "他のゲーム向けバージョン",
  "settingsOtherGamesWutheringWaves": "鳴潮",
  "settingsOtherGamesFuture": "今後、対応ゲームが増える可能性があります...",
```

- [ ] **Step 5: `lib/l10n/app_pt_BR.arb`**

找到：`  "settingsAboutVersion": "Versão {version}",`，替換為：

```
  "settingsAboutVersion": "Versão {version}",
  "settingsOtherGamesTitle": "Versões para outros jogos",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "Mais jogos poderão ser adicionados no futuro...",
```

- [ ] **Step 6: `lib/l10n/app_th.arb`**

找到：`  "settingsAboutVersion": "เวอร์ชัน {version}",`，替換為：

```
  "settingsAboutVersion": "เวอร์ชัน {version}",
  "settingsOtherGamesTitle": "เวอร์ชันสำหรับเกมอื่น ๆ",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "อาจมีการรองรับเกมเพิ่มเติมในอนาคต...",
```

- [ ] **Step 7: `lib/l10n/app_vi.arb`**

找到：`  "settingsAboutVersion": "Phiên bản {version}",`，替換為：

```
  "settingsAboutVersion": "Phiên bản {version}",
  "settingsOtherGamesTitle": "Phiên bản cho các trò chơi khác",
  "settingsOtherGamesWutheringWaves": "Wuthering Waves",
  "settingsOtherGamesFuture": "Có thể sẽ hỗ trợ thêm trò chơi trong tương lai...",
```

- [ ] **Step 8: 重新產碼 + 分析 + 測試**

Run: `fvm flutter gen-l10n`（模板未變，主要確認 ARB 解析無誤）
Run: `fvm dart format lib/ test/`
Run: `fvm flutter analyze` — Expected: `No issues found!`
Run: `fvm flutter test` — Expected: `All tests passed!`

- [ ] **Step 9: commit**

```bash
git add lib/l10n/app_zh_Hans.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_ja.arb lib/l10n/app_pt_BR.arb lib/l10n/app_th.arb lib/l10n/app_vi.arb
git commit -m "feat(l10n): translate other-game-versions strings (7 locales)"
```

---

### Task 6: 最終整體驗收

**Files:** 無（僅驗收）

- [ ] **Step 1: 格式化**

Run: `fvm dart format lib/ test/`
Expected: 無待格式化變更（若有，併入相關 commit 或補一個 `style:` commit）。

- [ ] **Step 2: 靜態分析**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 全套測試**

Run: `fvm flutter test`
Expected: `All tests passed!`

- [ ] **Step 4: 人工確認（可選，建議）**

`fvm flutter run -d windows`，進設定頁 →「關於」區塊底部應出現「其他遊戲版本」小標 +「鳴潮」可點連結（右側 `open_in_new` 圖示）+ 未來說明文字；點擊以系統瀏覽器開啟鳴潮專案 GitHub 頁面。

---

## Self-Review（撰寫者自查紀錄）

**Spec coverage：**
- 新增 `lib/data/related_projects.dart` → Task 1 ✓
- 新增 `lib/widgets/other_game_versions.dart` → Task 3 ✓
- 改 `settings_page.dart` 掛 widget → Task 4 ✓
- 3 個 key 加進 9 個非空殼 ARB（zh/en→Task 2；其餘 7→Task 5）✓
- 遊戲名 CJK 在地化、其餘英文 → Task 2/5 譯文 ✓
- 省略號半形 → 全部 future 字串使用 `...` ✓
- 空殼 22 檔不動 → Task 5 註明 ✓
- 驗收（gen-l10n/format/analyze/test）→ 各 Task + Task 6 ✓

**Placeholder scan：** 無 TBD／TODO；每個 code step 皆含完整內容。

**Type consistency：** 全程一致——常數 `RelatedProjects.wutheringWavesAnalyzer`、ARB key `settingsOtherGamesTitle`／`settingsOtherGamesWutheringWaves`／`settingsOtherGamesFuture`、widget `OtherGameVersions`／資料模型 `OtherGameVersion`／清單 `kOtherGameVersions`／resolver `_wutheringWavesLabel` 在 widget、測試、設定頁、各 Task 引用名稱皆相符。

**已知取捨：** 設定頁掛載（Task 4）未加專屬整合測試（pump 整個 `SettingsPage` 需大量 Riverpod provider 設定，鳴潮專案亦僅有 widget 層測試），改以 `OtherGameVersions` widget 測試 + `analyze` 覆蓋；此為刻意決定，非遺漏。
