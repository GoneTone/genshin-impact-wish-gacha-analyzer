# 標題與按鈕補 icon 設計

## 背景

目前介面有大量標題（頁面標題、Section 標題、圖表卡標題、內聯區塊標題）與部分按鈕沒有 icon，視覺辨識度較弱。本次目標是把「沒有 icon 的標題與按鈕都補上適合的 icon」，讓使用者一眼掃過去就能識別區塊性質。

## 目標

- 所有頁面標題（`PageHeader`）、Section 卡標題（`SectionCard`）、圖表卡標題（`ChartCard`）、頁內內聯區塊標題都帶 icon。
- 所有按鈕（含 dialog actions）都帶 icon。
- 維持既有的字級、padding、色彩 token 系統，不引入新的設計變項。

## 非目標

- 不重新設計 icon 風格（沿用 Material `Icons.*`，不引入 SVG 或第三方 icon set）。
- 不改文案 / 不改 l10n key。
- 不為純資訊區塊（例如 `_AboutContent` 內的「Developed by」那行已有 `Icons.code`、`_LanguageList` 的逐項條目）追加 icon——這些不是「標題」也不是「按鈕」。

## 方案

### 共用元件加 `IconData? icon` 參數

三個標題容器加同名可選欄位，caller 傳入 icon：

| 元件 | 檔案 | 字級 | icon size |
|------|------|------|-----------|
| `PageHeader` | `lib/widgets/page_header.dart` | headlineSmall (22 px) | 24 |
| `SectionCard` | `lib/widgets/cards/section_card.dart` | titleLarge (18 px) | 20 |
| `ChartCard` | `lib/widgets/cards/chart_card.dart` | titleLarge (18 px) | 20 |

渲染規則統一：

```
Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    Icon(icon, size: <20 或 24>, color: tokens.textPrimary),
    SizedBox(width: AppSpacing.s),
    Flexible(child: Text(title, style: ...)),
  ],
)
```

- `icon` 為 `null` 時退化為現行只有 `Text` 的版本（向下相容；只是實作上每個 caller 都會傳 icon）。
- 顏色用 `tokens.textPrimary` 與標題同色——不搶眼但有形狀辨識度。
- 跟 PageHeader 的 `subtitle` 不衝突：subtitle 仍在 icon+title 那行之下，獨立一行。

### 內聯 titleLarge 抽 `InlineSectionTitle`

`overview_page.dart` 與 `banner_page.dart` 內各有一處 `Text(..., style: titleLarge)` 當作 section 分隔標題。這兩處不在卡片裡，所以無法直接用 `SectionCard` / `ChartCard`，但語意一樣。抽一個小元件：

- 位置：`lib/widgets/inline_section_title.dart`
- API：`InlineSectionTitle({required IconData icon, required String title})`
- 渲染：與 `SectionCard` 標題列同樣的 Row 排版（titleLarge + icon size 20）。
- 之後若有第三、第四處內聯標題，都共用此元件。

### 按鈕一律換成 `.icon` 變體

把現有沒有 icon 的 `TextButton(...)`、`FilledButton(...)` 改成 `TextButton.icon(...)` / `FilledButton.icon(...)`，把 child 變成 label，加上 icon。

## icon 對應表

### 頁面標題（PageHeader）

| l10n key / 來源 | icon |
|---|---|
| `pageOverviewTitle` 綜合數據 | `Icons.dashboard_outlined` |
| `gachaTypeCharacter` 角色活動祈願 | `Icons.person_outline` |
| `gachaTypeWeapon` 武器活動祈願 | `Icons.shield_outlined` |
| `gachaTypeChronicled` 集錄祈願 | `Icons.collections_bookmark_outlined` |
| `gachaTypeStandard` 常駐祈願 | `Icons.history` |
| `gachaTypeBeginner` 新手祈願 | `Icons.school_outlined` |
| `settingsTitle` 設定 | `Icons.settings_outlined` |
| `contributorsTitle` 貢獻名單 | `Icons.volunteer_activism_outlined` |

> BannerPage 用一個 caller-local 函式 `_iconForGachaType(String gachaType)` switch，不污染 `data/gacha_types.dart`（model 不該帶 `IconData`）。

### SectionCard 標題

| l10n key | icon |
|---|---|
| `settingsAppearance` 外觀 | `Icons.palette_outlined` |
| `settingsLanguage` 語言 | `Icons.language` |
| `settingsDataManagement` 資料管理 | `Icons.folder_outlined` |
| `settingsAccountManagement` 帳號管理 | `Icons.manage_accounts_outlined` |
| `settingsAbout` 關於 | `Icons.info_outline` |
| `contributorsProjectLeader` 專案負責人 | `Icons.workspace_premium_outlined` |
| `contributorsTesters` 測試人員 | `Icons.bug_report_outlined` |
| `contributorsGithubContributors` GitHub 貢獻者 | `Icons.groups_outlined` |
| `contributorsTranslationReviewer` 翻譯審稿人 | `Icons.translate` |
| `contributorsTranslatedLanguages` 已翻譯語言 | `Icons.public` |
| `contributorsProjectLicense` 專案授權 | `Icons.gavel_outlined` |

### ChartCard 標題

| l10n key | icon |
|---|---|
| `statsRarityDistribution` 稀有度分布 | `Icons.pie_chart_outline` |
| `statsItemTypeDistribution` 類型分布 | `Icons.donut_small_outlined` |
| `bannerFiveStarCountTitle` 各卡池 5★ 件數 | `Icons.bar_chart` |
| `timelineCountFiveStar` 5★ 時間軸 (n) | `Icons.timeline` |

### InlineSectionTitle

| 位置 | 標題 | icon |
|---|---|---|
| `banner_page.dart` 紀錄列表 | `pageBannerRecordList` | `Icons.table_chart_outlined` |
| `overview_page.dart` 5★ 時間軸 inline | `timelineCountFiveStar` | `Icons.timeline` |

### 按鈕 icon

| 位置 | 按鈕（label） | icon |
|---|---|---|
| `confirm_dialog` | 取消 (`confirmCancel`) | `Icons.close` |
| `confirm_dialog` | 刪除 (`confirmDelete`) | `Icons.delete_outline` |
| `accounts_picker_dialog` | 取消 (`confirmCancel`) | `Icons.close` |
| `accounts_picker_dialog` | 確認（匯入/匯出/繼續） | `Icons.check` |
| `update_progress_dialog` | 取消 (`actionCancel`) | `Icons.close` |
| `update_progress_dialog` | 關閉 (`actionClose`) | `Icons.close` |
| `account_management._Row` | 設為活躍 (`accountSetActive`) | `Icons.check_circle_outline` |
| `account_management._Row` | 移除 (`accountRemove`) | `Icons.delete_outline` |

## 受影響檔案

- `lib/widgets/page_header.dart` — 加 `icon` 參數，改渲染。
- `lib/widgets/cards/section_card.dart` — 加 `icon` 參數，改渲染。
- `lib/widgets/cards/chart_card.dart` — 加 `icon` 參數，改渲染。
- `lib/widgets/inline_section_title.dart` — 新增。
- `lib/pages/overview_page.dart` — PageHeader / ChartCard / inline title 都傳 icon。
- `lib/pages/banner_page.dart` — 同上 + `_iconForGachaType`。
- `lib/pages/settings_page.dart` — PageHeader + 5 個 SectionCard 傳 icon。
- `lib/pages/contributors_page.dart` — PageHeader + 6 個 SectionCard 傳 icon。
- `lib/widgets/dialogs/confirm_dialog.dart` — 2 個按鈕改 `.icon`。
- `lib/widgets/dialogs/accounts_picker_dialog.dart` — 2 個按鈕改 `.icon`。
- `lib/widgets/update_progress_dialog.dart` — 2 個按鈕改 `.icon`。
- `lib/widgets/cards/account_management.dart` — `_Row` 內 2 個 TextButton 改 `.icon`。

## 測試

新增 / 補強：

- `test/widgets/page_header_test.dart`：當 `icon` 為 null 維持原樣；當 `icon` 有值時 widget tree 中有對應 `Icon`。
- `test/widgets/section_card_test.dart`：同上。
- `test/widgets/chart_card_test.dart`：同上。
- `test/widgets/inline_section_title_test.dart`：新元件 golden / 結構測試。
- `test/widgets/confirm_dialog_test.dart`：取消按鈕含 `Icons.close`、刪除按鈕含 `Icons.delete_outline`。
- `test/widgets/accounts_picker_dialog_test.dart`：同類別。
- `test/widgets/update_progress_dialog_test.dart`：actions 含 icon。
- `test/widgets/account_management_test.dart`（若有；沒有就在 `_Row` 加 widget test）。

既有測試應該不會 break（API 為向下相容的可選參數）。

## 視覺驗證

- `flutter run` 跑一次，Light + Dark 兩 theme 都檢查：
  - Overview / 各 banner / Settings / Contributors 四種頁。
  - 觸發 confirm dialog、accounts picker dialog、update progress dialog 各一次。
  - 觀察 icon 與 title 對齊、垂直 baseline、間距是否一致。

## YAGNI 邊界

- 不引入 icon theme token（例如 `tokens.iconTitle`）——所有 title icon 統一用 `textPrimary`，足夠就好。
- 不為按鈕設計「危險動作獨立配色」——`stateDanger` 的色彩配置已經是 `FilledButton.styleFrom` 個別設定的，沿用即可。
- 不為 `accountSetActive` 的 `TextButton` 加 styleFrom 顏色，現狀文字色已正確。
