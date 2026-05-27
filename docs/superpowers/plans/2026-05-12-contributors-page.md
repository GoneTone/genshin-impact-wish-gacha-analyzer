# 貢獻名單頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `/contributors` 獨立頁面，移植舊版 Vue `ContributionList.vue` 的 6 個區塊（專案負責人、測試人員、GitHub 貢獻者、翻譯審稿人、已翻譯語言+譯者、MIT License），並把 Settings About 的譯者顯示搬到本頁的「已翻譯語言」區塊。

**Architecture:** 純資料 const 放 `lib/data/contributors.dart`；頁面骨架完全比照 `SettingsPage`（`PageHeader` + 多張 `SectionCard`）；連結文字直接重用既有 `TranslatorText`，避免新元件。NavigationRail 底部加入口（樣式複製 `_SettingsRailButton`）。語言排序 helper `sortedLocaleMetadata` 抽到 `localization_metadata.dart` 給 Settings 與 ContributorsPage 共用（DRY）。10 個新 l10n key，`zh_Hant` 為 fallback 模板，必填；其他 9 個 locale 從舊版 `master:src/locales/*.json` 抽取，缺漏直接 skip 走 fallback。

**Tech Stack:** Flutter、`go_router`、`flutter_riverpod`、`url_launcher`、既有 `TranslatorText` / `SectionCard` / `PageHeader` widgets、gen_l10n。

**Spec:** `docs/superpowers/specs/2026-05-12-contributors-page-design.md`（本地保留，不進版控）。

**CLAUDE.md 規範：** 每個 task 的 commit 前必跑：
1. `dart format lib/ test/`（**不要**對 `.` 跑，會動到 `rust_builder/`）
2. `flutter analyze` → `No issues found!`
3. `flutter test` → `All tests passed!`

任一失敗就先修，不要用 `--no-verify` 跳過 hooks。

---

## File Structure

### 新增（committed）
- `lib/data/contributors.dart` — `Contributor` model 與 const 名單 / URL
- `lib/pages/contributors_page.dart` — 頁面、內部 `_ContributorChips` / `_LanguageList`
- `test/data/contributors_test.dart` — URL `Uri.parse` 健檢
- `test/pages/contributors_page_test.dart` — 頁面 widget test

### 修改（committed）
- `lib/state/localization_metadata.dart` — 新增 `sortedLocaleMetadata` helper
- `lib/routing/app_router.dart` — 新增 `/contributors` `GoRoute`
- `lib/pages/app_shell.dart` — `_Rail` 底部加 `_ContributorsRailButton`、active 判定擴充
- `lib/pages/settings_page.dart` — `_AboutContent` 移除譯者顯示；`_LocaleDropdown` 改用 `sortedLocaleMetadata`
- `lib/l10n/app_zh_Hant.arb` — 補 10 個 key（必填，fallback 模板）
- `lib/l10n/app_en.arb` / `app_zh.arb` / `app_zh_Hans.arb` / `app_es.arb` / `app_fr.arb` / `app_ja.arb` / `app_pt.arb` / `app_th.arb` — 從舊版 JSON 抽取，缺漏 skip
- `lib/l10n/app_vi.arb` — 舊版完全沒譯文，本次不動（全部走 fallback）
- `lib/l10n/generated/*` — gen_l10n 自動產出（commit）

---

## Task 1: 抽 `sortedLocaleMetadata` helper（refactor，行為不變）

**Files:**
- Modify: `lib/state/localization_metadata.dart`
- Modify: `test/l10n/locale_metadata_test.dart`
- Modify: `lib/pages/settings_page.dart` (lines 125–162，`_LocaleDropdown.build`)

### Step 1.1: 在 `test/l10n/locale_metadata_test.dart` 末端新增 helper 測試

- [ ] **在最後一個 group 之後（檔尾 `}` 前）插入：**

```dart
  group('sortedLocaleMetadata', () {
    test('依 nativeName 字典序排列', () {
      final input = <String, LocaleMetadata>{
        'b': const LocaleMetadata(nativeName: 'Banana', translator: ''),
        'a': const LocaleMetadata(nativeName: 'Apple', translator: ''),
        'c': const LocaleMetadata(nativeName: 'Cherry', translator: ''),
      };
      final sorted = sortedLocaleMetadata(input);
      expect(sorted.map((e) => e.value.nativeName), [
        'Apple',
        'Banana',
        'Cherry',
      ]);
    });

    test('空 Map → 空 List', () {
      expect(sortedLocaleMetadata(const {}), isEmpty);
    });
  });
```

### Step 1.2: 跑測試確認失敗

Run: `flutter test test/l10n/locale_metadata_test.dart`
Expected: 編譯錯誤或 `sortedLocaleMetadata is not defined`

### Step 1.3: 在 `lib/state/localization_metadata.dart` 加 helper

- [ ] **在檔尾（最後一個 `}` 之後）加：**

```dart
/// 將 `localeMetadataProvider` 的結果依 `nativeName` 字典序排序，
/// `SettingsPage._LocaleDropdown` 與 `ContributorsPage._LanguageList` 共用。
List<MapEntry<String, LocaleMetadata>> sortedLocaleMetadata(
  Map<String, LocaleMetadata> meta,
) => meta.entries.toList()
  ..sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName));
```

### Step 1.4: 跑測試確認通過

Run: `flutter test test/l10n/locale_metadata_test.dart`
Expected: `All tests passed!`

### Step 1.5: 改 `_LocaleDropdown.build` 用 helper

- [ ] **在 `lib/pages/settings_page.dart` 找這段：**

```dart
    return asyncMeta.when(
      data: (metadata) {
        final sorted = metadata.entries.toList()
          ..sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName));
        final selectableTags = metadata.keys.toSet();
```

**替換為：**

```dart
    return asyncMeta.when(
      data: (metadata) {
        final sorted = sortedLocaleMetadata(metadata);
        final selectableTags = metadata.keys.toSet();
```

### Step 1.6: 跑品質檢查

Run: `dart format lib/ test/`
Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: `All tests passed!`

### Step 1.7: Commit

```bash
git add lib/state/localization_metadata.dart lib/pages/settings_page.dart test/l10n/locale_metadata_test.dart
git commit -m "refactor(l10n): extract sortedLocaleMetadata helper for reuse"
```

---

## Task 2: 新增 `lib/data/contributors.dart` 與 URL 健檢測試

**Files:**
- Create: `lib/data/contributors.dart`
- Create: `test/data/contributors_test.dart`

### Step 2.1: 寫 `test/data/contributors_test.dart`

- [ ] **建立檔案：**

```dart
// test/data/contributors_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';

void main() {
  group('Contributor lists', () {
    test('projectLeaders 名單非空且 URL 可解析', () {
      expect(projectLeaders, isNotEmpty);
      for (final c in projectLeaders) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull, reason: '${c.name} URL 無法解析');
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });

    test('testers 名單非空且 URL 可解析', () {
      expect(testers, isNotEmpty);
      for (final c in testers) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull);
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });

    test('translationReviewers 名單非空且 URL 可解析', () {
      expect(translationReviewers, isNotEmpty);
      for (final c in translationReviewers) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull);
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });
  });

  group('External URLs', () {
    test('githubContributorsUrl 是 https URL', () {
      final uri = Uri.parse(githubContributorsUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('github.com'));
    });

    test('translationCrowdinUrl 是 https URL', () {
      final uri = Uri.parse(translationCrowdinUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('crowdin.com'));
    });

    test('licenseUrl 是 https URL', () {
      final uri = Uri.parse(licenseUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('github.com'));
    });
  });
}
```

### Step 2.2: 跑測試確認失敗

Run: `flutter test test/data/contributors_test.dart`
Expected: 編譯錯誤 `Target of URI doesn't exist: 'package:.../data/contributors.dart'`

### Step 2.3: 實作 `lib/data/contributors.dart`

- [ ] **建立檔案：**

```dart
// lib/data/contributors.dart

class Contributor {
  const Contributor({required this.name, this.url});
  final String name;
  final String? url;
}

const projectLeaders = <Contributor>[
  Contributor(name: 'GoneTone', url: 'https://github.com/GoneTone'),
];

const testers = <Contributor>[
  Contributor(
    name: '世界へいわ',
    url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
  ),
  Contributor(
    name: 'Zhi',
    url: 'https://www.hoyolab.com/genshin/accountCenter/gameRecord?id=8094152',
  ),
];

const translationReviewers = <Contributor>[
  Contributor(
    name: '世界へいわ',
    url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
  ),
  Contributor(name: 'pan93412'),
  Contributor(name: 'Lemon7777'),
];

const githubContributorsUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors';
const translationCrowdinUrl =
    'https://crowdin.com/project/genshin-impact-wish-gacha-analyzer';
const licenseUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/blob/master/LICENSE';
```

### Step 2.4: 跑測試確認通過

Run: `flutter test test/data/contributors_test.dart`
Expected: `All tests passed!`

### Step 2.5: 跑品質檢查 + Commit

Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

```bash
git add lib/data/contributors.dart test/data/contributors_test.dart
git commit -m "feat(data): add contributors lists and external URLs"
```

---

## Task 3: 補 `app_zh_Hant.arb` 10 個 contributors keys（fallback 模板，必填）

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`
- (generated) `lib/l10n/generated/app_localizations.dart` / `app_localizations_zh.dart`

### Step 3.1: 編輯 `lib/l10n/app_zh_Hant.arb`

- [ ] **在 `"navSettings": "設定",` 那一行下方加：**

```json
  "navContributors": "貢獻者",
```

- [ ] **找到 `"settingsPlaceholderPhase2": "(即將推出)",`（或檔尾倒數第二塊），在它之後插入：**

```json

  "contributorsTitle": "貢獻名單",
  "contributorsSubtitle": "感謝以下為此軟體貢獻的夥伴！",
  "contributorsProjectLeader": "專案負責人",
  "contributorsTesters": "測試人員",
  "contributorsGithubContributors": "GitHub 貢獻者",
  "contributorsTranslationReviewer": "翻譯審稿人",
  "contributorsTranslatedLanguages": "已翻譯語言",
  "contributorsHelpTranslate": "沒有您的語言嗎？協助我們翻譯！",
  "contributorsProjectLicense": "專案授權",
```

> 若 `settingsPlaceholderPhase2` 不存在，插在 `localeTranslator` 區塊之後任一處皆可——JSON 順序不影響 gen_l10n 結果。

### Step 3.2: 生成 l10n 並確認編譯通過

Run: `flutter gen-l10n`
Expected: 沒有輸出（成功）或無錯誤訊息。`lib/l10n/generated/app_localizations.dart` 應出現 `String get navContributors` 等抽象 getter。

Run: `flutter analyze`
Expected: `No issues found!`

### Step 3.3: 加 ARB 簡單測試（驗 zh_Hant 全部 key 都已加上）

- [ ] **在 `test/l10n/locale_metadata_test.dart` 的 `'AppLocalizations locale metadata'` group 內加：**

```dart
    test('zh_Hant 提供全部 contributors keys（fallback 模板必填）', () async {
      final l = await AppLocalizations.delegate.load(
        const Locale('zh', 'Hant'),
      );
      expect(l.navContributors, isNotEmpty);
      expect(l.contributorsTitle, isNotEmpty);
      expect(l.contributorsSubtitle, isNotEmpty);
      expect(l.contributorsProjectLeader, isNotEmpty);
      expect(l.contributorsTesters, isNotEmpty);
      expect(l.contributorsGithubContributors, isNotEmpty);
      expect(l.contributorsTranslationReviewer, isNotEmpty);
      expect(l.contributorsTranslatedLanguages, isNotEmpty);
      expect(l.contributorsHelpTranslate, isNotEmpty);
      expect(l.contributorsProjectLicense, isNotEmpty);
    });
```

### Step 3.4: 跑測試 + 品質檢查 + Commit

Run: `flutter test` → `All tests passed!`
Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`

```bash
git add lib/l10n/app_zh_Hant.arb lib/l10n/generated/ test/l10n/locale_metadata_test.dart
git commit -m "feat(l10n): add contributors keys to zh_Hant template ARB"
```

---

## Task 4: 補其他 8 個 locale 的 contributors keys（缺漏走 fallback）

> 9 個 locale 中 `app_vi.arb` 完全沒譯文（master 的 vi_VN.json 全部缺漏），所以本 task 只動 8 個檔。

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hans.arb`
- Modify: `lib/l10n/app_es.arb`
- Modify: `lib/l10n/app_fr.arb`
- Modify: `lib/l10n/app_ja.arb`
- Modify: `lib/l10n/app_pt.arb`
- Modify: `lib/l10n/app_th.arb`
- (generated) `lib/l10n/generated/app_localizations_*.dart`

> 為了方便對照，每個 ARB 列出**這次該補的所有 key**。把它們插到該檔最後一個既有 key 後面（在收尾 `}` 前），逗號分隔。`navContributors` 與其他 9 個 `contributors*` 並列即可，JSON 順序對 gen_l10n 無影響。

### Step 4.1: `app_en.arb`

- [ ] **補上全部 10 個 key：**

```json
  "navContributors": "Contribution",
  "contributorsTitle": "Contributors",
  "contributorsSubtitle": "Special thanks to the following partners who have contributed to the development of this software!",
  "contributorsProjectLeader": "Project moderator",
  "contributorsTesters": "Testers",
  "contributorsGithubContributors": "GitHub Contributors",
  "contributorsTranslationReviewer": "Translation proofreaders",
  "contributorsTranslatedLanguages": "Available languages",
  "contributorsHelpTranslate": "Unavailable in your preferred languages? Help us translate it!",
  "contributorsProjectLicense": "Project License",
```

### Step 4.2: `app_zh.arb` 與 `app_zh_Hans.arb`（兩檔內容相同）

- [ ] **兩個檔都補上：**

```json
  "navContributors": "贡献",
  "contributorsTitle": "贡献名单",
  "contributorsSubtitle": "感谢以下为此软件贡献的伙伴！",
  "contributorsProjectLeader": "专案负责人",
  "contributorsTesters": "测试人员",
  "contributorsGithubContributors": "GitHub 贡献者",
  "contributorsTranslationReviewer": "翻译审稿人",
  "contributorsTranslatedLanguages": "已翻译语言",
  "contributorsHelpTranslate": "没有您的语言吗？帮助我们翻译！",
  "contributorsProjectLicense": "专案许可证",
```

### Step 4.3: `app_es.arb`

- [ ] **補上全部 10 個 key：**

```json
  "navContributors": "Contribucion",
  "contributorsTitle": "Contribuidores",
  "contributorsSubtitle": "¡Agradecemos especialmente a los siguientes socios que han contribuido al desarrollo de este software!",
  "contributorsProjectLeader": "Moderador del proyecto",
  "contributorsTesters": "Testers",
  "contributorsGithubContributors": "Contribuidores en GitHub",
  "contributorsTranslationReviewer": "Correctores de traduccion",
  "contributorsTranslatedLanguages": "Ha sido traducido a",
  "contributorsHelpTranslate": "¡¿No esta tu lenguaje? Ayudanos a traducirlo!",
  "contributorsProjectLicense": "Licencia del proyecto",
```

### Step 4.4: `app_fr.arb`（舊版只有 3 個 key，其餘 skip 走 fallback）

- [ ] **補上 3 個 key：**

```json
  "navContributors": "Contribution",
  "contributorsTitle": "Contributeurs",
  "contributorsSubtitle": "Remerciements particuliers aux partenaires suivants qui ont contribué au développement de ce logiciel!",
```

### Step 4.5: `app_ja.arb`（舊版缺 3 個 key：title.name、title.description、help_translate）

- [ ] **補上 7 個 key：**

```json
  "navContributors": "貢献",
  "contributorsProjectLeader": "プロジェクトマネージャー",
  "contributorsTesters": "テストスタッフ",
  "contributorsGithubContributors": "GitHub コントリビューター",
  "contributorsTranslationReviewer": "翻訳レビュアー",
  "contributorsTranslatedLanguages": "翻訳済み言語",
  "contributorsProjectLicense": "プロジェクトライセンス",
```

### Step 4.6: `app_pt.arb`（舊版 pt_PT 為空檔；改採 pt_BR 的 3 個 key）

- [ ] **補上 3 個 key（譯文摘自舊版 pt_BR）：**

```json
  "contributorsProjectLeader": "O líder do projeto",
  "contributorsTesters": "Os testadores",
  "contributorsGithubContributors": "Os contribuintes de Github",
```

### Step 4.7: `app_th.arb`

- [ ] **補上全部 10 個 key：**

```json
  "navContributors": "ผลงาน",
  "contributorsTitle": "รายชื่อผู้ให้การสนับสนุน",
  "contributorsSubtitle": "ขอขอบคุณเป็นพิเศษสำหรับผู้ที่มีส่วนช่วยเหลือต่อไปนี้ที่มีส่วนร่วมในการพัฒนาซอฟต์แวร์นี้!",
  "contributorsProjectLeader": "หัวหน้าโปรเจค",
  "contributorsTesters": "ผู้ทดสอบ",
  "contributorsGithubContributors": "ผู้ร่วมให้ข้อมูล GitHub",
  "contributorsTranslationReviewer": "ผู้ตรวจสอบการแปล",
  "contributorsTranslatedLanguages": "ภาษาที่แปล",
  "contributorsHelpTranslate": "ไม่มีให้บริการในภาษาที่คุณต้องการ ? ช่วยเราแปล ！",
  "contributorsProjectLicense": "ใบอนุญาตโปรเจค",
```

### Step 4.8: `app_vi.arb` — 確認不動

> 舊版 `master:src/locales/vi_VN.json` 完全沒有 `ui.text.contribution*` 系列譯文。
> 不在 `app_vi.arb` 加任何 contributors key；gen_l10n 會走 fallback 到 `app_zh_Hant.arb`。

### Step 4.9: 生成 l10n + 品質檢查

Run: `flutter gen-l10n`
Expected: 無錯誤。`lib/l10n/generated/app_localizations_<lang>.dart` 多了 contributor getter（有譯文的 override、無譯文的不 override → 走 fallback）。

Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

### Step 4.10: Commit

```bash
git add lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_zh_Hans.arb lib/l10n/app_es.arb lib/l10n/app_fr.arb lib/l10n/app_ja.arb lib/l10n/app_pt.arb lib/l10n/app_th.arb lib/l10n/generated/
git commit -m "feat(l10n): port contributors translations from legacy locale JSONs"
```

---

## Task 5: 新增 ContributorsPage 骨架 + `/contributors` 路由

> 此 task 只放 PageHeader 與 6 張空 `SectionCard`（標題正確、內容暫為 `SizedBox.shrink()`）。後續 task 逐張填內容。

**Files:**
- Create: `lib/pages/contributors_page.dart`
- Create: `test/pages/contributors_page_test.dart`
- Modify: `lib/routing/app_router.dart`

### Step 5.1: 寫 `test/pages/contributors_page_test.dart`

- [ ] **建立檔案：**

```dart
// test/pages/contributors_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/contributors_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale('zh', 'Hant'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('PageHeader 顯示 contributorsTitle', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('貢獻名單'), findsOneWidget);
  });

  testWidgets('渲染 6 張 SectionCard 標題', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('專案負責人'), findsOneWidget);
    expect(find.text('測試人員'), findsOneWidget);
    expect(find.text('GitHub 貢獻者'), findsOneWidget);
    expect(find.text('翻譯審稿人'), findsOneWidget);
    expect(find.text('已翻譯語言'), findsOneWidget);
    expect(find.text('專案授權'), findsOneWidget);
  });
}
```

### Step 5.2: 跑測試確認失敗

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: 編譯錯誤 `Target of URI doesn't exist: '.../pages/contributors_page.dart'`

### Step 5.3: 實作 `lib/pages/contributors_page.dart` 骨架

- [ ] **建立檔案：**

```dart
// lib/pages/contributors_page.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

class ContributorsPage extends StatelessWidget {
  const ContributorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.contributorsTitle,
                subtitle: l.contributorsSubtitle,
              ),
              SectionCard(
                title: l.contributorsProjectLeader,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTesters,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsGithubContributors,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTranslationReviewer,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTranslatedLanguages,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsProjectLicense,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 5.4: 加 `/contributors` 路由

- [ ] **修改 `lib/routing/app_router.dart`：在 `import settings_page` 那行之後加：**

```dart
import 'package:genshin_impact_wish_gacha_analyzer/pages/contributors_page.dart';
```

- [ ] **在 `routes:` list 中、`/settings` 那條之前插入：**

```dart
        GoRoute(
          path: '/contributors',
          pageBuilder: (_, _) => _fade(const ContributorsPage()),
        ),
```

### Step 5.5: 跑測試確認通過

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: `All tests passed!`

### Step 5.6: 品質檢查 + Commit

Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

```bash
git add lib/pages/contributors_page.dart lib/routing/app_router.dart test/pages/contributors_page_test.dart
git commit -m "feat(pages): add ContributorsPage skeleton and /contributors route"
```

---

## Task 6: `_ContributorChips` + 前 4 張 SectionCard 內容

> 前 4 張 card：專案負責人、測試人員、GitHub 貢獻者、翻譯審稿人。
> 「GitHub 貢獻者」用 `TranslatorText`（標籤就是 URL 自身），其餘 3 張用 `_ContributorChips`。

**Files:**
- Modify: `lib/pages/contributors_page.dart`
- Modify: `test/pages/contributors_page_test.dart`

### Step 6.1: 擴充測試

- [ ] **在 `test/pages/contributors_page_test.dart` 既有兩個 testWidgets 之後加：**

```dart
  testWidgets('專案負責人 SectionCard 顯示 GoneTone 並包成 InkWell', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('GoneTone'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('GoneTone'), matching: find.byType(InkWell)),
      findsOneWidget,
    );
  });

  testWidgets('測試人員 SectionCard 顯示兩位 testers', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('世界へいわ'), findsWidgets);
    expect(find.text('Zhi'), findsOneWidget);
  });

  testWidgets('翻譯審稿人 SectionCard 顯示三人；pan93412 / Lemon7777 為純文字（無 url）', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('pan93412'), findsOneWidget);
    expect(find.text('Lemon7777'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('pan93412'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('Lemon7777'), matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('GitHub 貢獻者 SectionCard 顯示完整 URL', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors',
      ),
      findsOneWidget,
    );
  });
```

### Step 6.2: 跑測試確認失敗

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: 多個 `findsOneWidget` fail（4 張 SectionCard 內容仍是 `SizedBox.shrink()`）

### Step 6.3: 在 `contributors_page.dart` 加 `_ContributorChips` 與 imports

- [ ] **在檔首 imports 之後加：**

```dart
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';
```

- [ ] **在 `ContributorsPage` class 之後（檔尾）加：**

```dart
class _ContributorChips extends StatelessWidget {
  const _ContributorChips(this.items);
  final List<Contributor> items;

  @override
  Widget build(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.s,
      children: [
        for (final c in items)
          if (c.url == null)
            Text(c.name)
          else
            InkWell(
              onTap: () => _open(c.url!),
              child: Text(
                c.name,
                style: TextStyle(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
```

### Step 6.4: 把前 4 張 SectionCard 內容換成實際 widget

- [ ] **`ContributorsPage.build` 中：**

把 `SectionCard(title: l.contributorsProjectLeader, child: const SizedBox.shrink())` 改為：

```dart
              SectionCard(
                title: l.contributorsProjectLeader,
                child: const _ContributorChips(projectLeaders),
              ),
```

把測試人員那段改為：

```dart
              SectionCard(
                title: l.contributorsTesters,
                child: const _ContributorChips(testers),
              ),
```

把 GitHub 貢獻者那段改為：

```dart
              SectionCard(
                title: l.contributorsGithubContributors,
                child: const TranslatorText(
                  raw:
                      '<a href="$githubContributorsUrl">$githubContributorsUrl</a>',
                ),
              ),
```

把翻譯審稿人那段改為：

```dart
              SectionCard(
                title: l.contributorsTranslationReviewer,
                child: const _ContributorChips(translationReviewers),
              ),
```

### Step 6.5: 跑測試確認通過

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: `All tests passed!`

### Step 6.6: 品質檢查 + Commit

Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

```bash
git add lib/pages/contributors_page.dart test/pages/contributors_page_test.dart
git commit -m "feat(pages): render contributors chips and GitHub link"
```

---

## Task 7: `_LanguageList` + 「已翻譯語言」SectionCard

> 內容：依 `nativeName` 字典序列出每個 locale；有譯者就 `{nativeName} — {translator}`（translator 含 `<a href>` 用 `TranslatorText` 渲染），無譯者只顯示 `{nativeName}`。底下放協助翻譯說明與 Crowdin 連結。

**Files:**
- Modify: `lib/pages/contributors_page.dart`
- Modify: `test/pages/contributors_page_test.dart`

### Step 7.1: 擴充測試

- [ ] **加：**

```dart
  testWidgets('已翻譯語言 SectionCard 顯示繁體中文 / 簡體中文 / English', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.textContaining('English'), findsWidgets);
  });

  testWidgets('已翻譯語言 SectionCard 含協助翻譯說明與 Crowdin 連結', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('沒有您的語言嗎'), findsOneWidget);
    expect(
      find.text('https://crowdin.com/project/genshin-impact-wish-gacha-analyzer'),
      findsOneWidget,
    );
  });
```

### Step 7.2: 跑測試確認失敗

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: 新增的兩個 testWidgets fail

### Step 7.3: 在 `contributors_page.dart` 加 imports 與 `_LanguageList`

- [ ] **在現有 imports 之後加：**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
```

- [ ] **`ContributorsPage` 從 `StatelessWidget` 改成 `ConsumerWidget`**：

把 class 開頭兩行改成：

```dart
class ContributorsPage extends ConsumerWidget {
  const ContributorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

（`final l = AppLocalizations.of(context)!;` 那行保留）

- [ ] **在檔尾加 `_LanguageList`：**

```dart
class _LanguageList extends ConsumerWidget {
  const _LanguageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMeta = ref.watch(localeMetadataProvider);
    return asyncMeta.when(
      data: (metadata) {
        final sorted = sortedLocaleMetadata(metadata);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: entry.value.translator.isEmpty
                    ? Text(entry.value.nativeName)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${entry.value.nativeName} — '),
                          Expanded(
                            child: TranslatorText(raw: entry.value.translator),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Failed to load locale metadata: $e'),
    );
  }
}
```

### Step 7.4: 把第 5 張 SectionCard 內容換掉

- [ ] **把：**

```dart
              SectionCard(
                title: l.contributorsTranslatedLanguages,
                child: const SizedBox.shrink(),
              ),
```

**換成：**

```dart
              SectionCard(
                title: l.contributorsTranslatedLanguages,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LanguageList(),
                    const SizedBox(height: AppSpacing.m),
                    Text(l.contributorsHelpTranslate),
                    const SizedBox(height: AppSpacing.s),
                    const TranslatorText(
                      raw:
                          '<a href="$translationCrowdinUrl">$translationCrowdinUrl</a>',
                    ),
                  ],
                ),
              ),
```

### Step 7.5: 跑測試 + 品質檢查 + Commit

Run: `flutter test test/pages/contributors_page_test.dart` → `All tests passed!`
Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

```bash
git add lib/pages/contributors_page.dart test/pages/contributors_page_test.dart
git commit -m "feat(pages): render translated languages list with translators"
```

---

## Task 8: 「專案授權」SectionCard

**Files:**
- Modify: `lib/pages/contributors_page.dart`
- Modify: `test/pages/contributors_page_test.dart`

### Step 8.1: 擴充測試

- [ ] **加：**

```dart
  testWidgets('專案授權 SectionCard 顯示「MIT License」', (tester) async {
    await tester.pumpWidget(_wrap(const ContributorsPage()));
    await tester.pumpAndSettle();
    expect(find.text('MIT License'), findsOneWidget);
  });
```

### Step 8.2: 跑測試確認失敗

Run: `flutter test test/pages/contributors_page_test.dart`
Expected: 新增的測試 fail

### Step 8.3: 把第 6 張 SectionCard 內容換掉

- [ ] **把：**

```dart
              SectionCard(
                title: l.contributorsProjectLicense,
                child: const SizedBox.shrink(),
              ),
```

**換成：**

```dart
              SectionCard(
                title: l.contributorsProjectLicense,
                child: const TranslatorText(
                  raw: '<a href="$licenseUrl">MIT License</a>',
                ),
              ),
```

### Step 8.4: 跑測試 + 品質檢查 + Commit

Run: `flutter test test/pages/contributors_page_test.dart` → `All tests passed!`
Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → `All tests passed!`

```bash
git add lib/pages/contributors_page.dart test/pages/contributors_page_test.dart
git commit -m "feat(pages): render MIT License link in contributors page"
```

---

## Task 9: NavigationRail 加 `_ContributorsRailButton`

**Files:**
- Modify: `lib/pages/app_shell.dart`

### Step 9.1: 擴充 active 判定

- [ ] **在 `_AppShellState.build` 找：**

```dart
    final isSettingsActive = location == '/settings';
    final selectedIndex = isSettingsActive
        ? null
        : _bannerIndexFromLocation(location);
```

**改為：**

```dart
    final isSettingsActive = location == '/settings';
    final isContributorsActive = location == '/contributors';
    final selectedIndex = (isSettingsActive || isContributorsActive)
        ? null
        : _bannerIndexFromLocation(location);
```

- [ ] **找 `_Rail(` 那行傳參，加一個：**

```dart
                _Rail(
                  selectedIndex: selectedIndex,
                  isSettingsActive: isSettingsActive,
                  isContributorsActive: isContributorsActive,
                  extended: extendedRail,
                  collapsedNoLabel: collapsedNoLabel,
                  l: l,
                ),
```

### Step 9.2: 擴充 `_Rail` constructor 與 build

- [ ] **`class _Rail` 開頭：**

把：

```dart
class _Rail extends StatelessWidget {
  const _Rail({
    required this.selectedIndex,
    required this.isSettingsActive,
    required this.extended,
    required this.collapsedNoLabel,
    required this.l,
  });
  final int? selectedIndex;
  final bool isSettingsActive;
  final bool extended;
  final bool collapsedNoLabel;
  final AppLocalizations l;
```

**改為：**

```dart
class _Rail extends StatelessWidget {
  const _Rail({
    required this.selectedIndex,
    required this.isSettingsActive,
    required this.isContributorsActive,
    required this.extended,
    required this.collapsedNoLabel,
    required this.l,
  });
  final int? selectedIndex;
  final bool isSettingsActive;
  final bool isContributorsActive;
  final bool extended;
  final bool collapsedNoLabel;
  final AppLocalizations l;
```

- [ ] **`_Rail.build` 中的底部按鈕區塊：**

把：

```dart
          // 設定入口（與其他 destination 視覺分隔，固定在底部，與 rail 同寬）
          _SettingsRailButton(
            active: isSettingsActive,
            extended: extended,
            hideLabel: collapsedNoLabel,
            label: l.navSettings,
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(height: AppSpacing.s),
```

**改為：**

```dart
          // 貢獻者入口
          _BottomRailButton(
            active: isContributorsActive,
            extended: extended,
            hideLabel: collapsedNoLabel,
            label: l.navContributors,
            iconActive: Icons.volunteer_activism,
            iconInactive: Icons.volunteer_activism_outlined,
            onPressed: () => context.go('/contributors'),
          ),
          // 設定入口（固定在底部）
          _BottomRailButton(
            active: isSettingsActive,
            extended: extended,
            hideLabel: collapsedNoLabel,
            label: l.navSettings,
            iconActive: Icons.settings,
            iconInactive: Icons.settings_outlined,
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(height: AppSpacing.s),
```

### Step 9.3: 把 `_SettingsRailButton` 抽成通用 `_BottomRailButton`（rename + parametrize）

> 既有 `_SettingsRailButton` 已硬編 settings icons。為避免複製整段（CLAUDE.md：嚴禁重複造輪子），把 icon 改成參數，並 rename 為 `_BottomRailButton`。

- [ ] **`lib/pages/app_shell.dart` 檔尾的 `class _SettingsRailButton extends StatelessWidget { ... }` 整個區塊替換為：**

```dart
class _BottomRailButton extends StatelessWidget {
  const _BottomRailButton({
    required this.active,
    required this.extended,
    required this.hideLabel,
    required this.label,
    required this.iconActive,
    required this.iconInactive,
    required this.onPressed,
  });
  final bool active;
  final bool extended;
  final bool hideLabel;
  final String label;
  final IconData iconActive;
  final IconData iconInactive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : tokens.textSecondary;
    final icon = Icon(active ? iconActive : iconInactive, color: color);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.m,
            horizontal: AppSpacing.s,
          ),
          child: extended
              ? Row(
                  children: [
                    const SizedBox(width: AppSpacing.xs),
                    icon,
                    const SizedBox(width: AppSpacing.m),
                    Text(label, style: TextStyle(color: color)),
                  ],
                )
              : (hideLabel
                    ? Center(child: icon)
                    : Column(
                        children: [
                          icon,
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            label,
                            style: TextStyle(color: color, fontSize: 11),
                          ),
                        ],
                      )),
        ),
      ),
    );
  }
}
```

### Step 9.4: 跑測試 + 品質檢查 + Commit

> NavigationRail 已有功能性測試（既存）；如果現有測試引用了 `_SettingsRailButton` 名稱會 break，需先確認。

Run: `flutter test` → `All tests passed!`
Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`

```bash
git add lib/pages/app_shell.dart
git commit -m "feat(navigation): add contributors entry to rail and unify bottom buttons"
```

---

## Task 10: 拿掉 SettingsPage About 區塊譯者顯示

> 此資訊已搬到 ContributorsPage `_LanguageList`，避免重複。

**Files:**
- Modify: `lib/pages/settings_page.dart`

### Step 10.1: 替換 `_AboutContent`

- [ ] **找 `class _AboutContent extends ConsumerWidget { ... }` 整個區塊（從 `class _AboutContent` 到對應的閉合 `}`），替換為：**

```dart
class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final version = ref.watch(appVersionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(l.settingsAboutVersion(version))],
    );
  }
}
```

> 留 `ConsumerWidget` 因為仍要 `ref.watch(appVersionProvider)`；只是不再讀 `localeTranslator`。

### Step 10.2: 確認 `_AboutContent` 使用處傳入 `const`

- [ ] **找 `SectionCard(title: l.settingsAbout, child: _AboutContent())` 那行，改為：**

```dart
              SectionCard(title: l.settingsAbout, child: const _AboutContent()),
```

> 如果原本沒帶 `const` 不要硬加，視 analyzer 警告補。

### Step 10.3: 移除 `TranslatorText` import（若未再使用）

- [ ] **檢查 `lib/pages/settings_page.dart` 是否還有其他地方用 `TranslatorText`。**

Run: `flutter analyze`
Expected: 若出現 `Unused import: 'translator_text.dart'`，刪掉該 import。

### Step 10.4: 跑測試 + 品質檢查 + Commit

Run: `flutter test` → `All tests passed!`
Run: `dart format lib/ test/`
Run: `flutter analyze` → `No issues found!`

```bash
git add lib/pages/settings_page.dart
git commit -m "refactor(settings): remove translator from About (moved to contributors page)"
```

---

## Task 11: 最終手動冒煙測試

> 不寫測試、不 commit；確認桌面 app 跑起來功能正常。

### Step 11.1: 啟動 dev build

Run: `flutter run -d windows`（或 macOS / linux 視開發環境）
Expected: app 開啟。

### Step 11.2: 點擊 NavigationRail 底部「貢獻者」按鈕

- [ ] 確認頁面切換到 `/contributors`，6 張 SectionCard 全顯示，標題對。
- [ ] 點擊 GoneTone、世界へいわ、Zhi 名字 → 系統瀏覽器開啟對應網址。
- [ ] 點擊 GitHub 貢獻者連結 → 開啟 GitHub contributors 頁面。
- [ ] 點擊「協助翻譯」下方 Crowdin 連結 → 開啟 Crowdin 專案頁。
- [ ] 點擊「MIT License」 → 開啟 GitHub LICENSE 檔。

### Step 11.3: 切換語言驗 fallback

- [ ] 設定頁切換語言至 `Tiếng Việt`（vi）→ ContributorsPage 切去看：
  - vi 沒譯文，文字應 fallback 到 zh_Hant（「貢獻名單」「專案負責人」等繁中標題）。
- [ ] 切換到 `Français`（fr）→ 部分標題顯示法文（Contributeurs / Contribution），部分 fallback 繁中。
- [ ] 切換到 `日本語`（ja）→ 大部分日文，title.name / title.description / help_translate 顯示繁中 fallback。
- [ ] 切換到 `English`（en）→ 全英文。
- [ ] 切換回 `繁體中文` → 全繁中。

### Step 11.4: 視窗縮放

- [ ] 把視窗縮到 < 800px 寬：rail 變窄、底部 contributors 按鈕仍可見、可點。
- [ ] 拉到 >= 1180px：rail 展開，contributors 按鈕顯示 icon + label。

### Step 11.5: 確認 Settings About 不再顯示譯者

- [ ] 切到 `/settings`，About 區塊只有版本號，沒有「Translated by」那一列。

---

## Self-Review

**Spec 覆蓋檢查（對照 `2026-05-12-contributors-page-design.md`）：**

| Spec 條目 | 對應 Task |
|---|---|
| §4 入口 / 路由 | Task 5（路由）、Task 9（NavigationRail 入口） |
| §5 頁面結構 6 張卡 | Task 5（骨架）、Task 6 / 7 / 8（內容） |
| §6 資料模型 | Task 2 |
| §7 `_ContributorChips` | Task 6 |
| §7 `_LanguageList` | Task 7 |
| §7 連結文字重用 `TranslatorText` | Task 6 / 7 / 8 |
| §7 抽 `sortedLocaleMetadata` 與 SettingsPage 共用 | Task 1 |
| §8 拿掉 About 譯者 | Task 10 |
| §9 翻譯 keys 新增 / 多語覆蓋 | Task 3 / 4 |
| §10 檔案異動清單 | 所有 task 都對應 |
| §11 測試策略（contributors_test / contributors_page_test） | Task 2 / 5 / 6 / 7 / 8 |

✅ 全部覆蓋。

**Placeholder 掃描：** 無 TBD/TODO；每個 step 含完整代碼與命令。

**型別一致性：** `Contributor` model（Task 2）與 `_ContributorChips` 使用（Task 6）一致；`sortedLocaleMetadata` signature（Task 1）與 `_LanguageList` 使用（Task 7）一致；`_BottomRailButton` props（Task 9）兩處呼叫一致。

**手動冒煙非典型 task 但保留：** 因為 Flutter widget test 無法驗 url_launcher 真的開外部瀏覽器，Task 11 是必要的最後關卡。

---

## Execution Handoff

實作計畫完成。
