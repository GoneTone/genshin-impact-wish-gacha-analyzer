# UI/UX 重新設計 — 設計文件

- **日期**：2026-05-09
- **分支**：flutter-rewrite
- **範圍**：整體 UX 重新規劃（視覺語言 + 資訊架構 + 元件庫 + 新功能 + i18n）
- **實作節奏**：兩階段（先骨架、後功能）
- **狀態**：待審閱

---

## 1. 目標與決策摘要

把目前以 Material 3 預設配色、單一 NavigationRail + 兩頁（綜合 / 卡池）+ 純文字數據面板的 UI 重新規劃，加入玩家最在意的核心數據功能（保底計數、5★ 出貨時間軸、表格進階互動），建立可擴展的視覺語言與多語言架構。

### 1.1 設計決策清單（已收斂）

| 決策項 | 結果 |
|---|---|
| 重設目標 | 整體 UX 重新規劃 |
| 視覺調性 | 混合風（儀表板可讀性 + 原神色彩線索） |
| 主版面 | 左 Rail + Bento 卡片網格（layout C） |
| 配色基調 | 深藍夜空（palette A） |
| 主題策略 | Dark + Light，預設跟隨系統 |
| 多語言 | 這次一併引入 i18n 架構（zh-Hant 完整、zh-Hans / en 骨架） |
| 必加功能 | 保底計數、5★/4★ 時間軸、表格排序 / 篩選 / 搜尋、設定頁 |
| 實作節奏 | 兩階段：先骨架，再功能 |

### 1.2 範圍排除

- 跨平台支援（仍是 Windows 桌面，不做 Web / mobile）
- 通知 / Toast 系統（除既有 SnackBar 用法外）
- 後端同步、多人 / 雲端帳號
- 視覺主題自定義（除 dark/light 切換外，不做主色自選）
- Golden / pixel 測試
- 行動 / 觸控優化（< 600 px 寬不專門設計，但要不 overflow）

---

## 2. 視覺語言與 Design Tokens

新建 `lib/theme/tokens.dart` 集中管理所有視覺常量。`lib/theme/app_theme.dart` 內既有 `GachaColors` 改成從 token 取色的薄包裝、callsite 全換完後移除。

### 2.1 色板（Dark 主）

| Role | Token | Hex |
|---|---|---|
| 背景 | `surface.background` | `#0C1220` |
| 一般卡片 / 容器 | `surface.card` | `#141C30` |
| 強調容器 / hover | `surface.cardHigh` | `#1A2438` |
| 邊框 / 分隔線 | `border.subtle` | `#1F2A44` |
| 邊框（強調） | `border.emphasis` | `#27314C` |
| 主要文字 | `text.primary` | `#FFFFFF` |
| 次要文字 | `text.secondary` | `#DDE3EE` |
| 弱化文字 | `text.muted` | `#8A92A6` |
| 5★ 金 | `gacha.fiveStar` | `#E6C477` |
| 4★ 紫 | `gacha.fourStar` | `#A385E0` |
| 3★ 藍 | `gacha.threeStar` | `#5B9BD5` |
| 角色色 | `gacha.character` | `#46B07A` |
| 武器色 | `gacha.weapon` | `#E6736B` |
| 強調色（accent） | `accent.primary` | `#E6C477`（沿用 5★ 金，當主 CTA） |
| 危險 / 失敗 | `state.danger` | `#E6736B` |
| 成功 | `state.success` | `#46B07A` |
| 警示 / 即將保底 | `state.warning` | `#E6C477` |

### 2.2 Light 模式

衍生原則：背景反轉到 `#FAFBFD`、卡片 `#FFFFFF`、邊框 `#E5E8EF`、文字反向。卡池色（5★/4★/3★/角色/武器）保留同一個飽和度，只稍微壓低亮度避免在白底上過於耀眼。具體 hex 在 `tokens.dart` 內以 `LightTokens` / `DarkTokens` 兩組常數列出，由 `themeModeProvider` 切換。

### 2.3 字型

沿用 Material 預設 stack，不加額外字型檔。語意化 size scale：

| Token | 用途 | 規格 |
|---|---|---|
| `display` | 保底大數字（73/90） | 32 / weight 800 / `tabularFigures()` |
| `title` | 頁標、卡標 | 18 / weight 700 |
| `body` | 一般文字 | 14 / weight 400 |
| `label` | 卡片小寫上標 | 11 / weight 600 / 字距 0.6 / uppercase |

### 2.4 間距 / 圓角 / 海拔

- spacing scale：`xs=4 / s=8 / m=12 / l=16 / xl=24 / 2xl=32`
- radius：`sm=6 / md=10 / lg=14`（卡用 md，外層容器用 lg）
- elevation：dark mode 不依賴陰影，改用 `surface.cardHigh` 表達層級感；light mode 才上低海拔陰影

### 2.5 Motion

- 頁面切換 200ms ease-out fade（取代 `NoTransitionPage`，但保留快速感）
- 卡片 hover 上移 2px、150ms
- PityCard 接近保底（≥ 70%）：accent 色條 1.5s 呼吸 loop
- 圖表初次繪製 / 重繪：600ms ease-out
- 全部尊重 `MediaQuery.disableAnimations`，true 時各自降為 0

---

## 3. 資訊架構與路由

### 3.1 路由表

| Path | Page | 備註 |
|---|---|---|
| `/` | OverviewPage | 跨卡池綜合儀表板 |
| `/banner/:type` | BannerPage | 單卡池儀表板（5 個 type） |
| `/settings` | SettingsPage | **新增** |

`go_router` 結構不變，仍是 `ShellRoute(AppShell)` 包以上三個 leaf。`/settings` 用 `NoTransitionPage` 維持與其他頁一致；過場走第 2.5 節定義的 200ms fade。

### 3.2 NavigationRail destinations

```
[綜合]  ← index 0
[角色]
[武器]
[集錄]
[常駐]
[新手]
─────  ← Spacer (push 設定 to bottom)
[設定]  ← 新增，視覺上分隔
```

`extended` 條件由 ≥1100 調整為 ≥1180；< 800 時收為純 icon 寬度（`labelType=none`），不做 Drawer / 不收為 hamburger。< 600 不專門設計，但需確保不 overflow。

### 3.3 多帳號 (UID) 切換的位置

維持現有 AppBar 右側 popup（`UidIndicator`）做「快速切換」；同時在設定頁開「帳號管理」區塊做「移除舊帳號 / 重新攔截 / 設為活躍」這類較少用的操作。Popup 內保留：列出 UID、切換、「重新攔截」。

### 3.4 「更新資料」按鈕的位置

維持 AppBar 右側 FilledButton（最高頻動作）。

### 3.5 底部「最後更新」footer

保留，但只在 OverviewPage / BannerPage 顯示。AppShell 接收子頁的 `bool showLastUpdated` 提示（或由路由判斷：`/settings` 隱藏，其餘顯示）。

---

## 4. 頁面版面

### 4.1 AppShell（共用骨架）

```
┌────────────────────────────────────────────────────────┐
│  AppBar                                                │
│  Genshin Wish Analyzer v1.0.0      [UID ▾] [更新資料]  │
├──────┬─────────────────────────────────────────────────┤
│ Rail │  Page content                                   │
│      │  (Bento grid 或 Settings sections)              │
├──────┴─────────────────────────────────────────────────┤
│  Footer：最後更新 yyyy-MM-dd HH:mm（settings 隱藏）     │
└────────────────────────────────────────────────────────┘
```

AppBar 高 56；Rail 收合 80 / 展開 240；Footer 32。Page content 對齊 16/24 內距。

### 4.2 Responsive breakpoints

| 寬度 | Rail | Bento 欄數 | 三聯卡（row 1） | 圖卡 row | 紀錄表 |
|---|---|---|---|---|---|
| ≥1180 | extended (240) | 12 (3 欄) | 5★ 6 / 4★ 3 / 總抽 3 | 4 / 4 / 4 | 全寬 |
| 1024–1179 | collapsed | 12 (3 欄) | 6 / 3 / 3 | 4 / 4 / 4 | 全寬 |
| 800–1023 | collapsed | 12 (2 欄) | 5★ 12 / 4★ 6 / 總抽 6 | 6 / 6 + timeline 12 | 全寬 |
| <800 | icon-only | 12 (1 欄) | 全部 stack | 全部 stack | 全寬 |

### 4.3 OverviewPage（跨卡池）

```
[H1] 綜合數據（全卡池合計）
[P]  起始於 yyyy-MM-dd · 共 N 個卡池

┌─StatCard────┐ ┌─StatCard─┐ ┌─StatCard─┐
│ 總抽數 1234 │ │ 5★ 抽中 │ │ 4★ 抽中 │
└─────────────┘ └─────────┘ └─────────┘

┌─Pie─────────┐ ┌─Pie─────┐ ┌─Timeline─┐
│ 稀有度分布   │ │ 類型分布│ │ 5★ 列表 │
└─────────────┘ └─────────┘ └─────────┘

[H2] 全部 5★ 紀錄
[FiveStarList]
```

注意：綜合頁**沒有**保底卡（保底是 per-banner 概念）；底下用 `FiveStarList` 而非完整紀錄表（跨卡池會誤導）。

### 4.4 BannerPage（單卡池）

```
[H1] 角色活動祈願
[P]  共 N 抽 · 起始於 yyyy-MM-dd

┌─PityCard (大)─┐ ┌─PityCard─┐ ┌─StatCard─┐
│ 5★ 保底       │ │ 4★ 保底  │ │ 總抽數   │
│  73 / 90      │ │  5 / 10  │ │   428    │
│  ███████░     │ │  ██░     │ │          │
│  距下次保底 17│ │          │ │          │
└───────────────┘ └──────────┘ └──────────┘

┌─Pie─────────┐ ┌─Pie─────┐ ┌─Timeline─┐
│ 稀有度分布   │ │ 類型分布│ │ 5★ 時間軸│
└─────────────┘ └─────────┘ └─────────┘

[H2] 紀錄列表
[Toolbar] [搜尋] [稀有度▾] [類型▾] [↕排序]
[SortableTable]
[Pager]
```

各卡池的保底閾值來自 `GachaType` 常數，新手池閾值 20 表示「20 抽結束」。

### 4.5 SettingsPage（縱向 section list）

頁面 `max-width: 720`、靠左對齊，section 之間 `gap=xl(24)`。

```
[H1] 設定

[Card] 外觀
  [H3] 主題
   ○ 跟隨系統   ○ 深色   ○ 淺色

[Card] 語言
  [Dropdown: 跟隨系統 / 繁中 / 簡中 / EN]

[Card] 資料管理
  [Btn] 匯出 JSON   [Btn] 匯出 CSV
  [Btn] 匯入 JSON
  ──
  [Btn (danger)] 清除目前帳號資料
  [Btn (danger)] 清除所有資料

[Card] 帳號管理
  UID 1234567890   最後更新 04-01 14:23
    [移除] [設為活躍]
  UID 0987654321   ...
  ──
  [Btn] 重新攔截 / 新增帳號

[Card] 關於
  Genshin Wish Analyzer v1.0.0
  [Link] GitHub  [Link] 授權
```

---

## 5. 元件庫

新建 `lib/widgets/cards/` 與 `lib/widgets/data/`，把可複用的卡片原件與資料列表原件分開。每個元件單一職責、API 顯式宣告所需資料。

### 5.1 卡片原件 (`lib/widgets/cards/`)

**`StatCard`**
```dart
StatCard({
  required String label,    // "總抽數"
  required String value,    // "428" / "73 / 90"
  String? subtitle,         // "距下次 17 抽"
  Color? accent,            // 左側色條
  Widget? trailing,         // 進度條 / icon
})
```
- 高度自適應，min 80
- `accent` 帶顏色時左側 3px 色條
- value 用 `text.display` token、`tabularFigures()`

**`PityCard`**（StatCard 的特化版）
```dart
PityCard({
  required int current,
  required int threshold,
  required String label,
  required Color accent,
})
```
- 三個視覺狀態：
  - `< 70%`：一般，accent 色條，進度條 70% 飽和
  - `70%–89%`：「快出了」，進度條漸層（accent → warning），accent 1.5s 呼吸 loop
  - `≥ 90%`：「保底中」，進度條金光、subtitle `state.warning`
- 卡池無保底機制（新手池已結束）：`subtitle = "已結束"`、進度條 100% 灰
- 計算邏輯放 `services/wish_pity.dart`，元件純展示

**`ChartCard`**
```dart
ChartCard({
  required String title,
  required Widget chart,
  Widget? legend,
})
```
- 統一 220 高度
- fl_chart 動效時間統一 600ms
- 餅圖中心放總數（如「428 抽」）

**`TimelineCard`**（5★ 時間軸）
- 橫向 scrollable，每個 5★ 是一個小膠囊：`[icon][名字][抽中時花了 X 抽]`
- 膠囊 hover 顯示日期 tooltip
- < 800 改縱向列表
- 跨卡池版（OverviewPage）膠囊額外標卡池色條

**`SectionCard`**（settings 用通用容器）
- 16 內距、md radius、`surface.card`
- title 用 `text.title` token

### 5.2 資料 / 列表原件 (`lib/widgets/data/`)

**`SortableTable`**（取代既有 `RecordListTable`）
- 4 欄：時間 / 名稱 / 類型 / 稀有度，欄頭可點切 asc/desc
- 預設排序：時間 desc
- 每列 hover 微亮（`surface.cardHigh`）
- 5★/4★ 在「稀有度」欄用 pill（`pill.gold` / `pill.purple`）取代純色文字
- 整列依 rankType 在最左邊有 2px 細色條（5★ 金 / 4★ 紫，3★ 無）
- 表本身不內捲，整頁捲；分頁器固定在表底
- 鍵盤：`←/→` 翻頁、`Home/End` 跳首尾頁；欄頭 focusable + Enter 切排序

**`SearchFilterBar`**
```
[搜尋 名字…] [稀有度: 全部 ▾] [類型: 全部 ▾] [清除篩選]
```
- 搜尋即時、debounce 200ms
- dropdown 用 M3 `DropdownMenu`
- 「清除篩選」只在有 active filter 時出現
- 篩選 / 排序 / 搜尋狀態存頁面 state（不持久化，切卡池 reset）

**`Pager`**
- 中央顯示 `1 / N`，左右 IconButton（`<` `>`），加 `<<` `>>` 跳首尾
- > 20 頁時用單行 dropdown 顯示「第 X 頁」

**`FiveStarList`**（OverviewPage 用）
- 縱向列表
- 每列：`[卡池色條][icon][名字][卡池][抽中花了 X 抽][時間]`
- 預設按時間 desc；無排序 / 無分頁

### 5.3 狀態元件

- `EmptyState`：保留現有，token 化色彩；補三種 factory：
  - `EmptyState.noSync()`、`EmptyState.noRecords()`、`EmptyState.noFiltered()`
- `LoadingState` / Skeleton：卡片占位淡灰膠囊、圖卡占位虛線框 + spinner
- `UpdateProgressDialog`：保留結構，token 化色彩 + AlertDialog 標題的 ✅/❌ emoji 改成 `Icon`

### 5.4 互動 / motion

| 元件 | 互動 | 動效 |
|---|---|---|
| 卡片 | hover 提亮（`surface.card` → `surface.cardHigh`） | 150ms |
| Rail item | hover 提亮、focused 描邊 | 150ms |
| PityCard ≥70% | accent 漸層 | 1.5s 呼吸 loop |
| 表頭 | hover、focused | 150ms |
| 表格列 | hover 提亮 | 150ms |
| 圖表 | initial draw、re-render | 600ms ease-out |
| 頁面切換 | go_router transition | 200ms fade |

### 5.5 退役清單

- `lib/widgets/record_list_table.dart` → 拆解，邏輯移入 `SortableTable`、樣式 token 化
- `lib/widgets/rarity_pie.dart` / `item_type_pie.dart` → 邏輯保留，包成 `ChartCard` + 內部 chart
- `lib/widgets/stats_panel.dart` → 拆成多個 `StatCard`
- `lib/widgets/empty_state.dart` → 加 factory，token 化
- `lib/theme/app_theme.dart` 中的 `GachaColors` → 移到 `tokens.dart`，舊 file 留薄包裝 → callsite 全換完後移除

---

## 6. 計算邏輯（services 層）

| 檔 | 內容 | 備註 |
|---|---|---|
| `services/wish_stats.dart` | 既有 `computeWishStats()` | 不依賴 theme |
| `services/wish_pity.dart`（新） | `computePity(records, threshold)` 回傳 `Pity{ current, threshold, lastFiveStarAt }` | 純函式，`records` 為時間 desc，從第一筆向下數到上次 5★ |
| `services/wish_filter.dart`（新） | `filterRecords(records, RecordFilter)`、`sortRecords(records, RecordSort)` | 純函式 |

各卡池保底閾值放 `data/gacha_types.dart`，擴充 `GachaType`：
```dart
GachaType(gachaType: '301', name: '角色活動祈願', fiveStarPity: 90, fourStarPity: 10),
GachaType(gachaType: '500', name: '集錄', fiveStarPity: 80, fourStarPity: 10),
// 新手池：fiveStarPity = 20（20 抽結束）
```

---

## 7. 狀態管理（Riverpod）

新增 providers：
- `themeModeProvider` — `system | dark | light`，由 settings persistence 載入
- `localeProvider` — `system | zh-Hant | zh-Hans | en`
- `settingsProvider` — 呼叫 `SettingsStorage.load() / save()`，包以上兩者
- `recordFilterProvider.family<gachaType>` — 各卡池一份篩選狀態，`autoDispose`

既有：`wishRepositoryProvider`、`wishStorageProvider`、`appVersionProvider`、`UpdateProgress` 不動。

---

## 8. 持久化

新增 `services/settings_storage.dart`，**新增依賴 `shared_preferences: ^2.x`**。

```
pref.themeMode    : "system" | "dark" | "light"
pref.locale       : "system" | "zh-Hant" | "zh-Hans" | "en"
```

祈願紀錄仍走既有 `WishStorage` 的 JSON 檔。`shared_preferences` 只服務「使用者偏好」這層。

---

## 9. 多語言架構

依賴：`flutter_localizations`（SDK 內建）、`intl`（已有 0.20）。

```
lib/l10n/
  app_zh_Hant.arb   ← 主要、最完整
  app_zh_Hans.arb
  app_en.arb
  l10n.yaml         ← 設定檔
lib/generated/...   ← codegen，已 .gitignore
```

`MaterialApp.router(localizationsDelegates: ..., supportedLocales: ...)` + `pubspec.yaml` 加 `flutter: generate: true`。

**字串掃描清單**：所有 `pages/`、`widgets/`、`update_progress_dialog.dart` 內中文常量，包括 `'尚未同步'、'更新資料'、'總抽數：'、'5★ 中獎率'` 等。**枚舉值**（`gachaTypes` 的 `name`）也必須翻譯。

階段 1 只完整翻譯 `zh-Hant`，`zh-Hans` / `en` 先放骨架（每個 key 都有，但用 zh-Hant 內容當 placeholder + `// TODO i18n`），讓 CI key 完整性 lint 通過。

---

## 10. 邊界 / 錯誤狀態

| 場景 | 處理 |
|---|---|
| `activeData == null` | `EmptyState.noSync()` 居中 + 主 CTA「更新資料」 |
| 卡池無紀錄 | `EmptyState.noRecords()`，PityCard 與圖卡也走 noRecords 變體 |
| 篩選 / 搜尋無結果 | `EmptyState.noFiltered()` + 「清除篩選」 |
| Pity 計算找不到上次 5★ | `current = records.length`、`lastFiveStarAt = null`，subtitle 顯示「暫無 5★」 |
| 主題切換 | `MaterialApp` 自動重建；fl_chart `setState` 即可重繪 |
| 語言切換 | 同上，arb codegen，重建時 `AppLocalizations.of(context)` 取最新 |
| 匯入 JSON 格式錯 | `try/catch`，SnackBar 顯示錯誤訊息（i18n 化） |
| 清除資料 | 兩段式：第一個 dialog 列出影響、第二個 dialog 要求輸入 UID（單帳號）或字面 `DELETE`（清全部） |
| 攔截失敗 | 既有 `UpdateFailed` 流程，token 化色 |
| 多 UID 競態 | 既有 `wish_repository` 處理，不動 |

---

## 11. 階段拆分

### 階段 1 — 骨架

1. `lib/theme/tokens.dart`：色 / 字體 / 間距 / radius tokens（dark + light）
2. `lib/theme/app_theme.dart`：建構兩套 `ThemeData`，`GachaColors` 改為 token 包裝、callsite 全換
3. `services/settings_storage.dart` + `shared_preferences` 依賴 + `themeModeProvider` / `localeProvider`
4. `MaterialApp.router` 接 `themeMode` + `locale`
5. `lib/l10n/` arb 建立 + 把現有字串全搬進去（zh-Hant 完整、zh-Hans / en 骨架）
6. `AppShell` 改版：Rail 加 spacer + 設定入口、breakpoint 邏輯
7. `pages/settings_page.dart` 框架（五個 SectionCard，內容是 placeholder 或基本主題 / 語言切換）
8. `pages/overview_page.dart` / `banner_page.dart` 改套 bento layout（先用既有資料填：StatCard / ChartCard / 既有 record table 包裝）
9. PityCard、TimelineCard、SortableTable 此階段**先不做**

階段 1 完成可發版：UI 看起來是新的，但保底卡 placeholder、表格還是舊行為、設定頁只有主題 + 語言能用。

### 階段 2 — 功能

10. `services/wish_pity.dart` + PityCard 三狀態 + 「快保底」呼吸動效
11. `TimelineCard`（單卡池版 + 跨卡池版）
12. `SortableTable` 取代既有 `RecordListTable` + `SearchFilterBar` + `recordFilterProvider`
13. `SettingsPage` 資料管理（匯出 JSON/CSV、匯入、清除）
14. `SettingsPage` 帳號管理（從 `UidIndicator` popup 抽出共用）
15. `EmptyState` factory + LoadingState / Skeleton

階段 2 完成：所有承諾的功能上線。

---

## 12. 測試策略

| 範圍 | 策略 |
|---|---|
| `wish_stats` | unit test |
| `wish_pity` | unit test：邊界（首抽即 5★、從未 5★、剛好閾值、新手池 20 抽） |
| `wish_filter` | unit test：篩選 + 排序組合 |
| `SettingsStorage` | unit test：load 不存在 key 用預設、save 後讀回一致 |
| `PityCard` | widget test：三狀態渲染（< 70% / 70-89% / ≥ 90%） |
| `SortableTable` | widget test：點欄頭切排序、pager 功能 |
| `SearchFilterBar` | widget test：debounce 200ms、清除篩選按鈕條件出現 |
| i18n 完整性 | CI script：列出所有 arb keys，缺一報錯（純 dart script，不引入 lint 套件） |
| Golden / pixel tests | **不做**（YAGNI） |

---

## 13. 新增依賴

| 套件 | 版本 | 用途 |
|---|---|---|
| `shared_preferences` | `^2.x`（最新穩定） | 主題 / 語言偏好持久化 |
| `flutter_localizations` | SDK 內建 | i18n delegates |

---

## 14. 不做（YAGNI）

- 自定義 ThemeData 主色 / 字型
- 跨平台（macOS / Linux / Web / Mobile）
- 雲端同步、帳號系統
- Toast / 通知中心
- Golden / pixel 測試
- 可拖拽自訂 Bento 排序
- 圖表類型自選（bar / line / pie 切換）
- 紀錄歷史的時序趨勢圖（除 5★ 時間軸外的進階圖表）
- 行動裝置 / 觸控優化
