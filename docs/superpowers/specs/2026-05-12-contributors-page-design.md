# 貢獻名單頁 (Contributors Page) 設計

**日期**：2026-05-12
**分支**：`flutter-rewrite`
**範圍**：把舊版 (master) `ContributionList.vue` 移植到 Flutter 重寫版，並做配套整理（譯者顯示從 Settings About 搬到本頁）。

---

## 1. 背景

- 舊版 Vue 版本有獨立的「貢獻名單」頁面（`src/views/ContributionList.vue`），透過左側選單進入，列出 6 個區塊：專案負責人、測試人員、GitHub 貢獻者、翻譯審稿人、已翻譯語言、MIT License 全文。
- Flutter 重寫版尚未有對應頁面；目前譯者署名 (`localeTranslator`) 顯示在 `SettingsPage` 的 About 區塊內，與「貢獻者資訊」分散。
- 使用者希望恢復獨立的貢獻名單頁，集中顯示所有貢獻相關資訊。

## 2. 目標

- 新增 `/contributors` 頁面，從 `NavigationRail` 底部入口進入。
- 完整保留舊版 6 個區塊的資訊，但根據新版架構做必要調整（譯者與審稿人分開、MIT License 改用連結而非全文）。
- 配套：拿掉 `SettingsPage` About 區塊的譯者顯示，避免重複。
- 翻譯字串完整覆蓋 10 個 `supportedLocale`，從舊版 JSON 抽取，缺漏走 `zh_Hant` fallback。

## 3. 非目標

- 不從 GitHub API 動態抓取貢獻者頭像或名單（離線無法顯示、複雜度過高）。
- 不做 contributor 名單的動態管理介面或檔案熱載入（YAGNI）。
- 不修改既有的 `localeTranslator` 翻譯字串（仍由 Crowdin 流程管理）。

## 4. 入口與路由

| 項目 | 設計 |
|---|---|
| 路徑 | `/contributors` |
| 加入位置 | `lib/routing/app_router.dart` 的 `ShellRoute` 內，新增一條 `GoRoute` |
| 過渡動畫 | 沿用 `_fade()` 與其他頁面一致 |
| 入口 UI | `app_shell.dart` 的 `_Rail` 底部，於 `_SettingsRailButton` **上方**插入 `_ContributorsRailButton` |
| Icon | `Icons.volunteer_activism_outlined` / `Icons.volunteer_activism` |
| Label key | `navContributors` |
| Active 判定 | `_AppShellState.build` 內新增 `final isContributorsActive = location == '/contributors'`；底部按鈕 active 邏輯擴充 |

`_ContributorsRailButton` 直接複製 `_SettingsRailButton` 的 layout 結構（icon / extended / collapsedNoLabel 三態），只更換 icon、label、目的路由。

## 5. 頁面結構

`lib/pages/contributors_page.dart` — `ConsumerWidget`，骨架完全比照 `SettingsPage`：

```
SingleChildScrollView
  └ Center
    └ ConstrainedBox(maxWidth: 720)
      └ Column
        ├ PageHeader(title: contributorsTitle, subtitle: contributorsSubtitle)
        ├ SectionCard(專案負責人)        ← _ContributorChips(projectLeaders)
        ├ SectionCard(測試人員)          ← _ContributorChips(testers)
        ├ SectionCard(GitHub 貢獻者)     ← TranslatorText 渲染連結
        ├ SectionCard(翻譯審稿人)        ← _ContributorChips(translationReviewers)
        ├ SectionCard(已翻譯語言)        ← _LanguageList + 協助翻譯說明 + Crowdin 連結
        └ SectionCard(專案授權)          ← TranslatorText 渲染「MIT License」連結
```

每張 `SectionCard` 之間用 `SizedBox(height: AppSpacing.xl)`，與 `SettingsPage` 一致。

## 6. 資料模型

新增 `lib/data/contributors.dart`（純資料、無 Widget 依賴、全部 `const`）：

```dart
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

不做 JSON / config / asset 抽象。修改名單時直接改 `contributors.dart` const。

## 7. 內部小元件

頁面檔內 private widgets：

### `_ContributorChips`

接 `List<Contributor>`，渲染 `Wrap`（`spacing: AppSpacing.m`, `runSpacing: AppSpacing.s`），每個 chip：

- 有 `url`：`InkWell` 包裹 `Text`，顏色 `Theme.of(context).colorScheme.primary` 加底線，點擊呼叫 `launchUrl(uri, mode: LaunchMode.externalApplication)`。
- 沒有 `url`：純 `Text`。

### `_LanguageList`

`ConsumerWidget`，`ref.watch(localeMetadataProvider)`，渲染為 `Column` 每列一行：

```
{nativeName} — {translator}
```

`translator` 若為空字串：只顯示 `{nativeName}`，不加破折號。
`translator` 若含 `<a href>`：透過 `TranslatorText` 渲染（既有元件支援）。

語言列表底下再放：
- 一行 `Text(l.contributorsHelpTranslate)`（協助翻譯說明）
- 一行 `TranslatorText(raw: '<a href="$translationCrowdinUrl">$translationCrowdinUrl</a>')`（Crowdin 連結）

兩者之間用 `SizedBox(height: AppSpacing.s)` 分隔。

語言排序沿用既有邏輯：把 `SettingsPage._LocaleDropdown` 內的 `entries.sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName))` 抽到 `localization_metadata.dart` 一個 helper：

```dart
List<MapEntry<String, LocaleMetadata>> sortedLocaleMetadata(
  Map<String, LocaleMetadata> meta,
) => meta.entries.toList()
  ..sort((a, b) => a.value.nativeName.compareTo(b.value.nativeName));
```

`SettingsPage` 與 `ContributorsPage` 共用，避免重複。

### 連結文字直接重用 `TranslatorText`

「GitHub 貢獻者」與「MIT License」這兩個區塊只是「label + 外部連結」一行字。既有 `TranslatorText` 接受 `'<a href="...">label</a>'` 已能完整處理（解析、開外部瀏覽器），不寫新元件。

## 8. 配套修改：移除 SettingsPage About 區塊的譯者顯示

`lib/pages/settings_page.dart` 的 `_AboutContent.build`：

- 移除 `final translator = l.localeTranslator;`
- 移除 `if (translator.isNotEmpty) ...[...]` 整段（含翻譯 icon + `TranslatorText`）
- 留下版本顯示 `Text(l.settingsAboutVersion(version))`
- `_AboutContent` 簡化後可改回 `StatelessWidget`（不再需要 `ref`）

`localeTranslator` ARB 欄位**不刪除**，仍由 `_LanguageList` 使用。

## 9. 翻譯字串

### 新增 keys（10 個，均為 plain string，無 placeholder）

| 新 key | 用途 | 對應舊版 key（譯文參考來源） |
|---|---|---|
| `navContributors` | NavigationRail label | `ui.text.contribution` |
| `contributorsTitle` | PageHeader title | `ui.text.title.contribution_list.name` |
| `contributorsSubtitle` | PageHeader subtitle | `ui.text.title.contribution_list.description` |
| `contributorsProjectLeader` | SectionCard 1 標題 | `ui.text.project_leader` |
| `contributorsTesters` | SectionCard 2 標題 | `ui.text.testers` |
| `contributorsGithubContributors` | SectionCard 3 標題 | `ui.text.github_contributor` |
| `contributorsTranslationReviewer` | SectionCard 4 標題 | `ui.text.translation_reviewer` |
| `contributorsTranslatedLanguages` | SectionCard 5 標題 | `ui.text.translated_language` |
| `contributorsHelpTranslate` | 協助翻譯說明 | `ui.text.help_translate_description` |
| `contributorsProjectLicense` | SectionCard 6 標題 | `ui.text.project_license` |

### 多語覆蓋規則

- `template-arb-file: app_zh_Hant.arb`，所以 **fallback 目標是 `zh_Hant`**。
- `app_zh_Hant.arb` 必須包含全部 10 個 key（缺一就 gen_l10n 編譯失敗）。
- 其他 9 個 ARB：若舊版對應 JSON 該 key 為空字串或缺漏，**不寫入該 key**，由 gen_l10n 走 fallback 到 `zh_Hant`。

### 舊版 JSON 對應來源

| 新版 ARB | 舊版 JSON |
|---|---|
| `app_en.arb` | `src/locales/en_US.json` |
| `app_es.arb` | `src/locales/es_ES.json` |
| `app_fr.arb` | `src/locales/fr_FR.json` |
| `app_ja.arb` | `src/locales/ja_JP.json` |
| `app_pt.arb` | `src/locales/pt_PT.json`（與 `pt_BR.json` 比較後挑用） |
| `app_th.arb` | `src/locales/th_TH.json` |
| `app_vi.arb` | `src/locales/vi_VN.json` |
| `app_zh.arb` | `src/locales/zh_CN.json` |
| `app_zh_Hans.arb` | `src/locales/zh_CN.json` |
| `app_zh_Hant.arb` | `src/locales/zh_TW.json` |

### 重用（不動）

- `localeNativeName`、`localeTranslator`：仍由每個 ARB 提供，由 `_LanguageList` 讀取。

## 10. 檔案異動清單

### 新增
- `lib/data/contributors.dart`
- `lib/pages/contributors_page.dart`
- `test/pages/contributors_page_test.dart`
- `test/data/contributors_test.dart`

### 修改
- `lib/routing/app_router.dart` — 新增 `/contributors` `GoRoute`
- `lib/pages/app_shell.dart` — `_Rail` 底部加 `_ContributorsRailButton`，擴充 active 判定
- `lib/pages/settings_page.dart` — `_AboutContent` 移除譯者顯示，簡化為 `StatelessWidget`；`_LocaleDropdown` 改用 `sortedLocaleMetadata` helper（DRY）
- `lib/state/localization_metadata.dart` — 新增 `sortedLocaleMetadata` helper
- `lib/l10n/app_zh_Hant.arb` — 新增 10 個 key（必填）
- `lib/l10n/app_*.arb`（其餘 9 個）— 從舊版 JSON 抽取，缺漏 skip

### 視情況更新（若存在）
- `test/pages/settings_page_test.dart` — 若有測 About 顯示 translator 的斷言需更新或移除

## 11. 測試策略

| 測試檔 | 驗證重點 |
|---|---|
| `test/data/contributors_test.dart` | 所有 URL 非空且通過 `Uri.parse`；防 typo |
| `test/pages/contributors_page_test.dart` | 渲染 6 張 SectionCard 標題正確；`_ContributorChips` 對 null url 不渲染 InkWell；`_LanguageList` 顯示語言名稱；空 `translator` 不顯示破折號區段 |
| 既有 `app_router` 相關測試 | 若有，補上 `/contributors` 路由可達 |

不測：
- `url_launcher.launchUrl` 實際開啟外部瀏覽器（mock 困難、價值低）。
- 不為現有 `TranslatorText` 加新測試（行為未變）。
- 不測 ARB 譯文內容（譯文由 Crowdin 管理）。

提交前必須 `flutter analyze` → `No issues found!` 且 `flutter test` → `All tests passed!`。

## 12. 風險與緩解

| 風險 | 緩解 |
|---|---|
| `pt_PT` 與 `pt_BR` 譯文不一致 | 抽取時兩者都看，擇優選 `pt_PT`，無譯文才考慮 `pt_BR` |
| 舊版 JSON 某 key 雖有但為亂碼或機翻 | 接受現狀，譯文品質後續由 Crowdin 流程改善 |
| NavigationRail 多一顆按鈕在窄視窗（< 800px）擠不下 | `_Rail` 已用 `Expanded` + 底部固定按鈕；多一顆按鈕仍在垂直空間內可放下 |
| `_LanguageList` 顯示譯者時 `<a href>` 連結點擊與其他 chip 行為不一致 | 全部統一走 `launchUrl(uri, mode: LaunchMode.externalApplication)` |

## 13. 未來可能延伸（**不在本次範圍**）

- 從 GitHub API 抓取貢獻者頭像清單（離線降級需設計）。
- 動態載入貢獻者 JSON 而非 const（目前 YAGNI）。
- License 全文檢視器（目前只連到 GitHub）。
