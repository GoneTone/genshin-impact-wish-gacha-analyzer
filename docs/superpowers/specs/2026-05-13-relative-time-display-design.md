# 相對時間顯示 (Relative Time Display) 設計規格

- **日期**: 2026-05-13
- **狀態**: 已確認設計,待寫實作計畫
- **作者**: GoneTone / Claude (brainstorming)

## 目標

把專案中「最後更新日期」「版本發布日期」「祈願記錄列表時間」改為相對時間顯示(`X 分鐘前`、`X 天前`、`現在` …),提升閱讀直覺。同時保留原始絕對時間的可查方式(tooltip / 並列顯示)。

## 範圍

### 會改動的時間顯示位置

| # | 位置 | 檔案 | 顯示方式 |
|---|---|---|---|
| 1 | App 底部 footer「最後更新」 | `lib/pages/app_shell.dart:155` | 改純相對時間 + tooltip 原時間 |
| 2 | 設定頁帳號卡片「最後更新」 | `lib/widgets/cards/account_management.dart:232` | 同上 |
| 3 | 帳號匯入對話框「最後更新」 | `lib/widgets/dialogs/accounts_picker_dialog.dart:179, 209` | 同上 |
| 4 | 新版本對話框「發布於」 | `lib/widgets/dialogs/new_version_dialog.dart:102, 125` | 同上 |
| 5 | 祈願記錄列表「時間」欄 | `lib/widgets/data/sortable_table.dart:310, 340` | `絕對時間 (相對時間)` 並列,**不訂閱 ticker** |

### 不在本次範圍

- 不引入 `timeago` 套件(預設文案不符,客製化成本與自寫相當)
- 不使用 calendar-based 特殊詞(「昨天 / 上週 / 上個月 / 去年」),統一用數字單位,避免使用者對「上個月」「去年」的歧義(例如「上個月底」與「13 天前」邊界混淆)
- 不顯示未來時間(時鐘飄移或剛同步完的些微差),統一顯示為「現在」
- 不對記錄列表加自動刷新 ticker(成本/效益不划算)

## 設計

### 1. 相對時間 helper

新增 `lib/utils/relative_time.dart`,純函式:

```dart
String relativeTime(DateTime t, AppLocalizations l, {DateTime? now});
```

**門檻表**(依序判斷,擊中即返回):

| 條件 | 輸出 | i18n key |
|---|---|---|
| `diff < 5s` 或 `t > now`(時鐘飄移) | 現在 | `relativeNow` |
| `< 60s` | X 秒前 | `relativeSecondsAgo(n)` |
| `< 60min` | X 分鐘前 | `relativeMinutesAgo(n)` |
| `< 24h` | X 小時前 | `relativeHoursAgo(n)` |
| `< 30 天` | X 天前 | `relativeDaysAgo(n)` |
| `< 12 個月`(以 30 天/月近似) | X 個月前 | `relativeMonthsAgo(n)` |
| 其他 | X 年前(以 365 天/年近似) | `relativeYearsAgo(n)` |

`now` 參數預設 `DateTime.now()`,僅為了測試可注入固定時間。

### 2. 絕對時間 helper(統一格式)

同檔內:

```dart
String formatAbsoluteDateTime(DateTime t) =>
    DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());

String formatAbsoluteDate(DateTime t) =>
    DateFormat('yyyy-MM-dd').format(t.toLocal());
```

讓所有需要絕對時間(包括 tooltip 與記錄列表並列)的位置統一引用,移除散落於各 widget 的 `DateFormat(...)` 重複實例。

### 3. ARB i18n keys

每個語言新增 7 條 key。`zh_Hant` 範例:

```jsonc
"relativeNow": "現在",
"relativeSecondsAgo": "{count} 秒前",
"@relativeSecondsAgo": { "placeholders": { "count": { "type": "int" } } },
"relativeMinutesAgo": "{count} 分鐘前",
"@relativeMinutesAgo": { "placeholders": { "count": { "type": "int" } } },
"relativeHoursAgo": "{count} 小時前",
"@relativeHoursAgo": { "placeholders": { "count": { "type": "int" } } },
"relativeDaysAgo": "{count} 天前",
"@relativeDaysAgo": { "placeholders": { "count": { "type": "int" } } },
"relativeMonthsAgo": "{count} 個月前",
"@relativeMonthsAgo": { "placeholders": { "count": { "type": "int" } } },
"relativeYearsAgo": "{count} 年前",
"@relativeYearsAgo": { "placeholders": { "count": { "type": "int" } } }
```

需要 plural 的語言用 ICU 語法,如 `en`:

```jsonc
"relativeSecondsAgo": "{count, plural, =1{1 second ago} other{{count} seconds ago}}"
```

語言清單:`zh / zh_Hant / zh_Hans / en / ja / fr / es / pt / th / vi`,共 10 個 ARB 各加 7 條 = 70 條翻譯。

### 4. Ticker provider

新增 `lib/state/clock_tick.dart`:

```dart
final clockTickProvider = StreamProvider<DateTime>((ref) {
  return Stream.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  ).asBroadcastStream();
});
```

**訂閱對象**: footer / 帳號卡片 / 兩個 dialog。
**不訂閱**: `sortable_table.dart` 的記錄列表。

訂閱端的 widget 改為 `ConsumerWidget`/`ConsumerStatefulWidget`,在 `build` 中 `ref.watch(clockTickProvider)`,觸發每 30 秒重繪。實際時間仍以 `DateTime.now()` 為準(provider 的值不需取出來用)。

### 5. 套用點細節

#### 5a. Footer (`app_shell.dart`)

- 訂閱 `clockTickProvider`
- 把 `DateFormat('yyyy-MM-dd HH:mm').format(...)` 替換為 `relativeTime(activeData.lastUpdated, l)`
- 整個 `Text(l.footerLastUpdated(...))` 用 `Tooltip(message: formatAbsoluteDateTime(activeData.lastUpdated), child: Text(...))` 包起來

#### 5b. 帳號卡片 (`account_management.dart`)

- 改為 `ConsumerStatefulWidget`(目前 StatefulWidget)或在內部加 `Consumer` 局部訂閱
- 同上替換 + Tooltip

#### 5c. 帳號匯入對話框 (`accounts_picker_dialog.dart`)

- 第 179 行的 `lastUpdated` 變數從「絕對字串」改為「相對字串」
- 因 subtitle 是 `'${l.accountLastUpdated(lastUpdated)} ・ ${l.accountRecordCount(entry.recordCount)}'`,只對「最後更新」那段加 Tooltip,需要拆成 `RichText` / `Row` 才能局部包 Tooltip
- 訂閱 `clockTickProvider`

#### 5d. 新版本對話框 `_ReleaseCard` (`new_version_dialog.dart`)

- 改為 `ConsumerWidget`
- `dateText` 改成 `relativeTime(release.publishedAt, l)`
- `Text(l.updateReleasedAt(dateText))` 用 `Tooltip(message: formatAbsoluteDate(release.publishedAt), child: ...)` 包起來

#### 5e. 記錄列表 (`sortable_table.dart`)

- `_formatTime(record.time)` 改為 `'${formatAbsoluteDateTime(record.time)} (${relativeTime(record.time, l)})'`
- 把硬寫的格式化邏輯移除,改用共用 helper
- **不**訂閱 ticker;每次列表 rebuild(切頁/重整/排序)會自然重算

### 6. 測試

#### 單元測試: `test/utils/relative_time_test.dart`

覆蓋每個門檻邊界(注入固定 `now`):

- 未來時間 / 0s / 4s → 現在
- 5s / 30s / 59s → 秒前
- 60s / 30min / 3599s → 分鐘前
- 60min / 12h / 23h59m → 小時前
- 24h / 7 days / 29 days → 天前
- 30 days / 6 months / 359 days → 個月前
- 360 days / 1 year / 5 years → 年前

#### 既有 widget tests 更新

任何斷言 footer / 帳號卡片 / dialog 顯示「最後更新 yyyy-MM-dd...」的測試需改為斷言「最後更新 X 分鐘前」+ 驗證 Tooltip message 仍含原時間。

需檢查的測試檔(grep 出):
- `test/widgets/cards/account_management_test.dart`
- `test/widgets/dialogs/accounts_picker_dialog_test.dart`
- (其他若有需 grep 確認)

## 風險與權衡

- **30 秒 tick 頻率**: 對「秒前」精度不足。權衡:1 秒 tick 對 footer 等永久可見元件 CPU 浪費明顯;5 秒 tick 對「現在 → 5 秒前 → 10 秒前」漂移夠用。最終選 30 秒符合「分鐘級顯示」常見實務,且「現在」狀態保留約 5 秒(< 5s 門檻)。
- **記錄列表不訂閱 ticker**: 切到表格停留時相對時間會逐漸過期(例:5 分鐘前看到的「3 分鐘前」實際已是「8 分鐘前」)。權衡: 1000+ 列每 30 秒 rebuild 對捲動有可感卡頓,而表格內容絕對時間已並列,過期不會誤事。
- **月/年近似**: 用 30 天/月、365 天/年,不嚴格 calendar。可接受誤差(2 月、閏年):「29 天前」顯示「29 天前」、「30 天前」顯示「1 個月前」,使用者直覺可接受。
- **i18n 工作量**: 70 條翻譯,首次成本不低。但只是字串,長期維護成本低。
- **plurals**: 中、日、泰、越無 plural;英、法、西、葡有。ARB 用 ICU plural 語法統一處理。

## 後續(實作計畫範圍)

- 寫 `relative_time.dart` 與單元測試(TDD 優先)
- 加 ARB keys 並跑 codegen (`flutter gen-l10n`)
- 加 `clockTickProvider`
- 改 5 個套用點
- 修既有 widget tests
- `dart format` + `flutter analyze` + `flutter test` 全通過後 commit
