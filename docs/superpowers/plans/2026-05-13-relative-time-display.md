# Relative Time Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把專案中最後更新日期、版本發布日期、祈願記錄列表時間改成相對時間顯示(「3 分鐘前」「2 天前」「現在」),且保留絕對時間可查(tooltip 或並列)。

**Architecture:** 新增純函式 `relativeTime` helper(7 階門檻) + 共用 `formatAbsoluteDate(Time)` 格式化函式;加 `clockTickProvider` (Riverpod `StreamProvider`) 讓 footer / 帳號卡片 / 兩個 dialog 每 30 秒重繪,記錄列表不訂閱 ticker。每個套用點用 `Tooltip` 顯示絕對時間,記錄列表則並列顯示。

**Tech Stack:** Flutter + Riverpod 3 + `intl` + ARB i18n(10 個語言)

**Spec:** `docs/superpowers/specs/2026-05-13-relative-time-display-design.md`

---

## File Structure

### 新增

- `lib/utils/relative_time.dart` — `relativeTime()`, `formatAbsoluteDateTime()`, `formatAbsoluteDate()` (純函式,無相依 widget)
- `lib/state/clock_tick.dart` — `clockTickProvider` (Riverpod `StreamProvider<DateTime>`)
- `test/utils/relative_time_test.dart` — 單元測試

### 修改

- `lib/l10n/app_*.arb` × 10 (zh / zh_Hant / zh_Hans / en / ja / fr / es / pt / th / vi) — 新增 7 條 i18n key
- `lib/pages/app_shell.dart` — footer 訂閱 tick + Tooltip
- `lib/widgets/cards/account_management.dart` — `_Row` 訂閱 tick + Tooltip
- `lib/widgets/dialogs/accounts_picker_dialog.dart` — `_PickerRow` 訂閱 tick + 拆 subtitle 加局部 Tooltip
- `lib/widgets/dialogs/new_version_dialog.dart` — `_ReleaseCard` 改 ConsumerWidget + Tooltip
- `lib/widgets/data/sortable_table.dart` — `_Row` 顯示「絕對 (相對)」,不訂閱 tick

---

### Task 1: `relativeTime` helper(TDD)

**Files:**
- Create: `lib/utils/relative_time.dart`
- Test: `test/utils/relative_time_test.dart`

- [ ] **Step 1.1: 先寫失敗測試**

寫到 `test/utils/relative_time_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';

/// 用 zh_Hant locale 取得 AppLocalizations(離線載入,無需 widget tree)。
Future<AppLocalizations> _loadL10n() async {
  return AppLocalizations.delegate.load(const Locale('zh', 'Hant'));
}

void main() {
  late AppLocalizations l;
  setUpAll(() async {
    // 確保 binding 已初始化(載入 ARB 需要)。
    TestWidgetsFlutterBinding.ensureInitialized();
    l = await _loadL10n();
  });

  final now = DateTime(2026, 5, 13, 14, 0, 0);

  String rt(DateTime t) => relativeTime(t, l, now: now);

  group('relativeTime', () {
    test('未來時間視為現在', () {
      expect(rt(now.add(const Duration(minutes: 5))), '現在');
    });

    test('差距小於 5 秒回傳「現在」', () {
      expect(rt(now), '現在');
      expect(rt(now.subtract(const Duration(seconds: 4))), '現在');
    });

    test('5~59 秒回傳「X 秒前」', () {
      expect(rt(now.subtract(const Duration(seconds: 5))), '5 秒前');
      expect(rt(now.subtract(const Duration(seconds: 30))), '30 秒前');
      expect(rt(now.subtract(const Duration(seconds: 59))), '59 秒前');
    });

    test('60 秒~59 分回傳「X 分鐘前」', () {
      expect(rt(now.subtract(const Duration(seconds: 60))), '1 分鐘前');
      expect(rt(now.subtract(const Duration(minutes: 30))), '30 分鐘前');
      expect(rt(now.subtract(const Duration(minutes: 59))), '59 分鐘前');
    });

    test('60 分~23 小時 59 分回傳「X 小時前」', () {
      expect(rt(now.subtract(const Duration(minutes: 60))), '1 小時前');
      expect(rt(now.subtract(const Duration(hours: 12))), '12 小時前');
      expect(
        rt(now.subtract(const Duration(hours: 23, minutes: 59))),
        '23 小時前',
      );
    });

    test('24 小時~29 天回傳「X 天前」', () {
      expect(rt(now.subtract(const Duration(days: 1))), '1 天前');
      expect(rt(now.subtract(const Duration(days: 15))), '15 天前');
      expect(rt(now.subtract(const Duration(days: 29))), '29 天前');
    });

    test('30 天~364 天回傳「X 個月前」(以 30 天/月)', () {
      expect(rt(now.subtract(const Duration(days: 30))), '1 個月前');
      expect(rt(now.subtract(const Duration(days: 90))), '3 個月前');
      expect(rt(now.subtract(const Duration(days: 359))), '11 個月前');
    });

    test('365 天以上回傳「X 年前」', () {
      expect(rt(now.subtract(const Duration(days: 365))), '1 年前');
      expect(rt(now.subtract(const Duration(days: 365 * 5))), '5 年前');
    });
  });

  group('formatAbsoluteDateTime / formatAbsoluteDate', () {
    test('formatAbsoluteDateTime 用 yyyy-MM-dd HH:mm', () {
      expect(
        formatAbsoluteDateTime(DateTime(2026, 5, 13, 14, 30)),
        '2026-05-13 14:30',
      );
    });

    test('formatAbsoluteDate 用 yyyy-MM-dd', () {
      expect(
        formatAbsoluteDate(DateTime(2026, 5, 13, 14, 30)),
        '2026-05-13',
      );
    });
  });
}
```

- [ ] **Step 1.2: 跑測試確認失敗**

Run:
```powershell
flutter test test/utils/relative_time_test.dart
```
Expected: FAIL — `package:.../utils/relative_time.dart` 不存在 / 無 export。

- [ ] **Step 1.3: 寫 helper 實作**

建立 `lib/utils/relative_time.dart`:

```dart
import 'package:intl/intl.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 把 [t] 轉成相對時間字串(「3 分鐘前」「現在」…)。
///
/// 門檻(由小到大;擊中即返回):
/// - `diff < 5s` 或 `t > now`(時鐘飄移) → `relativeNow`
/// - `< 60s` → `relativeSecondsAgo(n)`
/// - `< 60min` → `relativeMinutesAgo(n)`
/// - `< 24h` → `relativeHoursAgo(n)`
/// - `< 30 天` → `relativeDaysAgo(n)`
/// - `< 12 個月`(以 30 天/月近似) → `relativeMonthsAgo(n)`
/// - 其他(以 365 天/年近似) → `relativeYearsAgo(n)`
///
/// [now] 預設 `DateTime.now()`,僅用於測試注入。
String relativeTime(DateTime t, AppLocalizations l, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diffSec = n.difference(t).inSeconds;

  if (diffSec < 5) return l.relativeNow;
  if (diffSec < 60) return l.relativeSecondsAgo(diffSec);

  final diffMin = diffSec ~/ 60;
  if (diffMin < 60) return l.relativeMinutesAgo(diffMin);

  final diffHour = diffMin ~/ 60;
  if (diffHour < 24) return l.relativeHoursAgo(diffHour);

  final diffDay = diffHour ~/ 24;
  if (diffDay < 30) return l.relativeDaysAgo(diffDay);

  final diffMonth = diffDay ~/ 30;
  if (diffMonth < 12) return l.relativeMonthsAgo(diffMonth);

  final diffYear = diffDay ~/ 365;
  return l.relativeYearsAgo(diffYear);
}

/// `yyyy-MM-dd HH:mm` 轉 local。用於 footer / 帳號卡片 / 帳號匯入對話框 /
/// 記錄列表 tooltip 與並列顯示。
String formatAbsoluteDateTime(DateTime t) =>
    DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());

/// `yyyy-MM-dd` 轉 local。用於新版本對話框「發布於」。
String formatAbsoluteDate(DateTime t) =>
    DateFormat('yyyy-MM-dd').format(t.toLocal());
```

> 註: 此檔依賴 Task 2 才會建立的 7 條 ARB key。Task 1.4 跑測試會 compile error(missing getters on AppLocalizations),預期需先做 Task 2 才能通過。請先繼續到 Task 2,再回 Task 1.4。

- [ ] **Step 1.4: (待 Task 2 完成後) 跑測試確認通過**

Run:
```powershell
flutter test test/utils/relative_time_test.dart
```
Expected: PASS(13 個 test cases)。

- [ ] **Step 1.5: Commit(待 Task 2 完成後一起 commit;此步驟先跳過)**

---

### Task 2: 新增 7 條 i18n key 到 10 個 ARB 檔

**Files:**
- Modify: `lib/l10n/app_zh_Hant.arb`(template)
- Modify: `lib/l10n/app_zh.arb` `app_zh_Hans.arb` `app_en.arb` `app_ja.arb` `app_fr.arb` `app_es.arb` `app_pt.arb` `app_th.arb` `app_vi.arb`

7 個 key 名稱:
- `relativeNow`
- `relativeSecondsAgo` (count: int)
- `relativeMinutesAgo` (count: int)
- `relativeHoursAgo` (count: int)
- `relativeDaysAgo` (count: int)
- `relativeMonthsAgo` (count: int)
- `relativeYearsAgo` (count: int)

- [ ] **Step 2.1: 加到 `app_zh_Hant.arb`(template,放在 `footerLastUpdated` 區塊後)**

在 `lib/l10n/app_zh_Hant.arb` 第 41 行的 `},` 之後、第 43 行 `"uidSwitchTooltip"` 之前插入:

```jsonc
  "relativeNow": "現在",
  "relativeSecondsAgo": "{count} 秒前",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count} 分鐘前",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count} 小時前",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count} 天前",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count} 個月前",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count} 年前",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.2: 加到 `app_zh_Hans.arb`**

放在 `footerLastUpdated` 區塊後(類似位置):

```jsonc
  "relativeNow": "现在",
  "relativeSecondsAgo": "{count} 秒前",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count} 分钟前",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count} 小时前",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count} 天前",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count} 个月前",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count} 年前",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.3: 加到 `app_zh.arb`(簡體中文 fallback,內容同 zh_Hans)**

使用 Step 2.2 內容(zh.arb 通常 fallback 到 zh_Hans;若 zh.arb 內容與 zh_Hans 一致則直接複製)。先 grep 確認 `app_zh.arb` 已存在的字串風格是簡體還是繁體,複製對應內容。

```powershell
# 確認 zh.arb 是簡體
Select-String -Path lib/l10n/app_zh.arb -Pattern "appName"
```

依結果用 Step 2.1(繁)或 Step 2.2(簡)的內容。

- [ ] **Step 2.4: 加到 `app_en.arb`**

英文用 ICU plural:

```jsonc
  "relativeNow": "Just now",
  "relativeSecondsAgo": "{count, plural, =1{1 second ago} other{{count} seconds ago}}",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count, plural, =1{1 minute ago} other{{count} minutes ago}}",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count, plural, =1{1 hour ago} other{{count} hours ago}}",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count, plural, =1{1 day ago} other{{count} days ago}}",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count, plural, =1{1 month ago} other{{count} months ago}}",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count, plural, =1{1 year ago} other{{count} years ago}}",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.5: 加到 `app_ja.arb`**

```jsonc
  "relativeNow": "たった今",
  "relativeSecondsAgo": "{count} 秒前",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count} 分前",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count} 時間前",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count} 日前",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count} か月前",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count} 年前",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.6: 加到 `app_fr.arb`(法文,有 plural)**

```jsonc
  "relativeNow": "À l'instant",
  "relativeSecondsAgo": "{count, plural, =1{Il y a 1 seconde} other{Il y a {count} secondes}}",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count, plural, =1{Il y a 1 minute} other{Il y a {count} minutes}}",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count, plural, =1{Il y a 1 heure} other{Il y a {count} heures}}",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count, plural, =1{Il y a 1 jour} other{Il y a {count} jours}}",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count, plural, =1{Il y a 1 mois} other{Il y a {count} mois}}",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count, plural, =1{Il y a 1 an} other{Il y a {count} ans}}",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.7: 加到 `app_es.arb`(西文,有 plural)**

```jsonc
  "relativeNow": "Ahora",
  "relativeSecondsAgo": "{count, plural, =1{Hace 1 segundo} other{Hace {count} segundos}}",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count, plural, =1{Hace 1 minuto} other{Hace {count} minutos}}",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count, plural, =1{Hace 1 hora} other{Hace {count} horas}}",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count, plural, =1{Hace 1 día} other{Hace {count} días}}",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count, plural, =1{Hace 1 mes} other{Hace {count} meses}}",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count, plural, =1{Hace 1 año} other{Hace {count} años}}",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.8: 加到 `app_pt.arb`(葡文,有 plural)**

```jsonc
  "relativeNow": "Agora",
  "relativeSecondsAgo": "{count, plural, =1{Há 1 segundo} other{Há {count} segundos}}",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count, plural, =1{Há 1 minuto} other{Há {count} minutos}}",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count, plural, =1{Há 1 hora} other{Há {count} horas}}",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count, plural, =1{Há 1 dia} other{Há {count} dias}}",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count, plural, =1{Há 1 mês} other{Há {count} meses}}",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count, plural, =1{Há 1 ano} other{Há {count} anos}}",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.9: 加到 `app_th.arb`(泰文,無 plural)**

```jsonc
  "relativeNow": "ตอนนี้",
  "relativeSecondsAgo": "{count} วินาทีที่แล้ว",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count} นาทีที่แล้ว",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count} ชั่วโมงที่แล้ว",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count} วันที่แล้ว",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count} เดือนที่แล้ว",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count} ปีที่แล้ว",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.10: 加到 `app_vi.arb`(越南文,無 plural)**

```jsonc
  "relativeNow": "Vừa xong",
  "relativeSecondsAgo": "{count} giây trước",
  "@relativeSecondsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMinutesAgo": "{count} phút trước",
  "@relativeMinutesAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeHoursAgo": "{count} giờ trước",
  "@relativeHoursAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeDaysAgo": "{count} ngày trước",
  "@relativeDaysAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeMonthsAgo": "{count} tháng trước",
  "@relativeMonthsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
  "relativeYearsAgo": "{count} năm trước",
  "@relativeYearsAgo": {
    "placeholders": { "count": { "type": "int" } }
  },
```

- [ ] **Step 2.11: 跑 l10n codegen 並確認沒錯誤**

Run:
```powershell
flutter gen-l10n
```
Expected: 無錯誤;`lib/l10n/generated/app_localizations.dart` 與 `app_localizations_*.dart` 自動更新並出現 `relativeNow`, `relativeSecondsAgo(...)`, … getters/methods。

```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 2.12: 回頭跑 Task 1.4 測試**

Run:
```powershell
flutter test test/utils/relative_time_test.dart
```
Expected: PASS。

- [ ] **Step 2.13: Commit(Task 1 + Task 2 一起)**

```powershell
git add lib/utils/relative_time.dart test/utils/relative_time_test.dart lib/l10n/app_*.arb lib/l10n/generated/
git commit -m "feat(utils): add relativeTime helper and ARB keys for 10 locales"
```

---

### Task 3: `clockTickProvider`

**Files:**
- Create: `lib/state/clock_tick.dart`

- [ ] **Step 3.1: 建立 provider**

寫到 `lib/state/clock_tick.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每 30 秒 emit 一次 `DateTime.now()`。
///
/// 訂閱對象: footer / 帳號卡片 / 帳號匯入對話框 / 新版本對話框。
/// 取出的值本身可以不使用 — 只要 watch 它就會跟著 rebuild。
final clockTickProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  );
});
```

- [ ] **Step 3.2: 確認沒 analyze 錯誤**

Run:
```powershell
flutter analyze lib/state/clock_tick.dart
```
Expected: `No issues found!`

- [ ] **Step 3.3: Commit**

```powershell
git add lib/state/clock_tick.dart
git commit -m "feat(state): add clockTickProvider for relative time rebuild"
```

---

### Task 4: Footer 套用相對時間 + Tooltip

**Files:**
- Modify: `lib/pages/app_shell.dart:5-6, 151-163`

- [ ] **Step 4.1: 改 import**

把 `app_shell.dart` 開頭的 import 區塊:

```dart
import 'package:intl/intl.dart' show DateFormat;
```

改成:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
```

(`DateFormat` 不再直接用,改透過 helper。)

- [ ] **Step 4.2: 在 build 中 watch tick**

在 `_AppShellState.build` 內、`final activeData = ref.watch(...)` 那行下方加:

```dart
    // 訂閱 30 秒 tick 讓 footer 相對時間自動更新。
    ref.watch(clockTickProvider);
```

- [ ] **Step 4.3: 替換 footer 文字內容並包 Tooltip**

把:

```dart
                Expanded(
                  child: Text(
                    activeData == null
                        ? l.footerNotSynced
                        : l.footerLastUpdated(
                            DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(activeData.lastUpdated.toLocal()),
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
```

改成:

```dart
                Expanded(
                  child: activeData == null
                      ? Text(
                          l.footerNotSynced,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Tooltip(
                          message: formatAbsoluteDateTime(
                            activeData.lastUpdated,
                          ),
                          child: Text(
                            l.footerLastUpdated(
                              relativeTime(activeData.lastUpdated, l),
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
```

- [ ] **Step 4.4: 跑 analyze + format**

```powershell
dart format lib/pages/app_shell.dart
flutter analyze lib/pages/app_shell.dart
```
Expected: `No issues found!`

- [ ] **Step 4.5: Commit**

```powershell
git add lib/pages/app_shell.dart
git commit -m "feat(app-shell): show last-updated as relative time with tooltip"
```

---

### Task 5: 帳號卡片(設定頁)套用相對時間 + Tooltip

**Files:**
- Modify: `lib/widgets/cards/account_management.dart:5-7, 117-130, 231-238`

- [ ] **Step 5.1: 改 import**

把:

```dart
import 'package:intl/intl.dart' show DateFormat;
```

改成:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
```

- [ ] **Step 5.2: `_Row` 改成 ConsumerStatefulWidget**

把:

```dart
class _Row extends StatefulWidget {
```
改:
```dart
class _Row extends ConsumerStatefulWidget {
```

把:

```dart
  @override
  State<_Row> createState() => _RowState();
```
改:
```dart
  @override
  ConsumerState<_Row> createState() => _RowState();
```

把:

```dart
class _RowState extends State<_Row> {
```
改:
```dart
class _RowState extends ConsumerState<_Row> {
```

- [ ] **Step 5.3: 在 `_RowState.build` 內訂閱 tick + 包 Tooltip**

在 `_RowState.build` 開頭(`final l = AppLocalizations.of(context)!;` 後)加:

```dart
    ref.watch(clockTickProvider);
```

把 `_RowState.build` 中:

```dart
                Text(
                  l.accountLastUpdated(
                    DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(widget.lastUpdated.toLocal()),
                  ),
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
```

改成:

```dart
                Tooltip(
                  message: formatAbsoluteDateTime(widget.lastUpdated),
                  child: Text(
                    l.accountLastUpdated(
                      relativeTime(widget.lastUpdated, l),
                    ),
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
                ),
```

- [ ] **Step 5.4: 跑 analyze + format**

```powershell
dart format lib/widgets/cards/account_management.dart
flutter analyze lib/widgets/cards/account_management.dart
```
Expected: `No issues found!`

- [ ] **Step 5.5: Commit**

```powershell
git add lib/widgets/cards/account_management.dart
git commit -m "feat(account-management): show last-updated as relative time with tooltip"
```

---

### Task 6: 帳號匯入對話框(`accounts_picker_dialog.dart`)套用

**Files:**
- Modify: `lib/widgets/dialogs/accounts_picker_dialog.dart:1-12, 160-215`

訂閱 tick + 把 subtitle 拆成 `Row`/`RichText`,只對「最後更新」那段加 Tooltip。

- [ ] **Step 6.1: 改 import**

加 `flutter_riverpod` 並把 `DateFormat` import 換掉:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
```

移除原本 `import 'package:intl/intl.dart' show DateFormat;`(若還有別的用途請保留)。

```powershell
# 確認是否還有別處用 DateFormat
Select-String -Path lib/widgets/dialogs/accounts_picker_dialog.dart -Pattern "DateFormat"
```

- [ ] **Step 6.2: `_PickerRow` 改成 ConsumerWidget**

把:

```dart
class _PickerRow extends StatelessWidget {
```
改:
```dart
class _PickerRow extends ConsumerWidget {
```

把:

```dart
  @override
  Widget build(BuildContext context) {
```
改:
```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

- [ ] **Step 6.3: 訂閱 tick + 拆 subtitle**

`_PickerRow.build` 整段替換為:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockTickProvider);

    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final alias = entry.alias;
    final title = (alias != null && alias.isNotEmpty)
        ? '${entry.uid} ($alias)'
        : entry.uid;
    final lastUpdatedText = l.accountLastUpdated(
      relativeTime(entry.lastUpdated, l),
    );
    final badge = entry.badge;
    return CheckboxListTile(
      value: selected,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.stateDanger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: tokens.stateDanger,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: DefaultTextStyle.merge(
        style: TextStyle(color: tokens.textMuted, fontSize: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: formatAbsoluteDateTime(entry.lastUpdated),
              child: Text(lastUpdatedText),
            ),
            const Text(' ・ '),
            Text(l.accountRecordCount(entry.recordCount)),
          ],
        ),
      ),
    );
  }
```

說明:
- subtitle 從單一 `Text` 拆成 `Row`,讓 `Tooltip` 只包「最後更新」那個 `Text`。
- `DefaultTextStyle.merge` 統一套樣式,避免在每個子 `Text` 重複 style。
- 中間分隔符維持原本 `・`(全形)。

- [ ] **Step 6.4: 跑 analyze + format**

```powershell
dart format lib/widgets/dialogs/accounts_picker_dialog.dart
flutter analyze lib/widgets/dialogs/accounts_picker_dialog.dart
```
Expected: `No issues found!`

- [ ] **Step 6.5: 跑相關 widget test 確認沒壞**

```powershell
flutter test test/widgets/dialogs/accounts_picker_dialog_test.dart
```
Expected: All tests pass(既有測試不檢查日期字串,應不受影響)。

- [ ] **Step 6.6: Commit**

```powershell
git add lib/widgets/dialogs/accounts_picker_dialog.dart
git commit -m "feat(accounts-picker): show last-updated as relative time with tooltip"
```

---

### Task 7: 新版本對話框(`new_version_dialog.dart`)套用

**Files:**
- Modify: `lib/widgets/dialogs/new_version_dialog.dart:1-9, 93-143`

把 `_ReleaseCard` 從 `StatelessWidget` 改 `ConsumerWidget`,訂閱 tick 並包 Tooltip。

- [ ] **Step 7.1: 改 import(移除 DateFormat 直接 import,改用 helper)**

把:

```dart
import 'package:intl/intl.dart' show DateFormat;
```

改成:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
```

- [ ] **Step 7.2: `_ReleaseCard` 改 ConsumerWidget**

把:

```dart
class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release, required this.l});
  final AppRelease release;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
```

改成:

```dart
class _ReleaseCard extends ConsumerWidget {
  const _ReleaseCard({required this.release, required this.l});
  final AppRelease release;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockTickProvider);
```

- [ ] **Step 7.3: 替換 dateText 並包 Tooltip**

把:

```dart
    final dateText = DateFormat(
      'yyyy-MM-dd',
    ).format(release.publishedAt.toLocal());
```

改:

```dart
    final dateText = relativeTime(release.publishedAt, l);
```

並把:

```dart
                Text(
                  l.updateReleasedAt(dateText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
```

改:

```dart
                Tooltip(
                  message: formatAbsoluteDate(release.publishedAt),
                  child: Text(
                    l.updateReleasedAt(dateText),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ),
```

- [ ] **Step 7.4: 跑 analyze + format**

```powershell
dart format lib/widgets/dialogs/new_version_dialog.dart
flutter analyze lib/widgets/dialogs/new_version_dialog.dart
```
Expected: `No issues found!`

- [ ] **Step 7.5: Commit**

```powershell
git add lib/widgets/dialogs/new_version_dialog.dart
git commit -m "feat(new-version-dialog): show published-at as relative time with tooltip"
```

---

### Task 8: 記錄列表(`sortable_table.dart`)並列顯示「絕對 (相對)」,**不**訂閱 tick

**Files:**
- Modify: `lib/widgets/data/sortable_table.dart:60-100, 270-345`

- [ ] **Step 8.1: 加 helper import**

在檔頭加:

```dart
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
```

- [ ] **Step 8.2: `_Row` 加 `l` 欄位**

`_Row` 目前 4 個欄位(`row`, `isStripe`, `theme`, `tokens`),加 `l`:

```dart
class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.isStripe,
    required this.theme,
    required this.tokens,
    required this.l,
  });
  final RecordRow row;
  final bool isStripe;
  final ThemeData theme;
  final GachaTokens tokens;
  final AppLocalizations l;
```

- [ ] **Step 8.3: 改 `_Row` 在 `_SortableTableState.build` 的 instantiation**

把:

```dart
              for (var i = 0; i < slice.length; i++)
                _Row(
                  row: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
                ),
```

改成:

```dart
              for (var i = 0; i < slice.length; i++)
                _Row(
                  row: slice[i],
                  isStripe: i.isOdd,
                  theme: theme,
                  tokens: tokens,
                  l: l,
                ),
```

- [ ] **Step 8.4: 替換 `_Row` 內時間顯示**

把:

```dart
          Expanded(flex: 4, child: Text(_formatTime(record.time))),
```

改:

```dart
          Expanded(
            flex: 4,
            child: Text(
              '${formatAbsoluteDateTime(record.time)}'
              ' (${relativeTime(record.time, l)})',
            ),
          ),
```

並刪除 `_Row` 末尾的 `static String _formatTime(...)` 整個方法(已由 `formatAbsoluteDateTime` 取代):

```dart
  static String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
```

- [ ] **Step 8.5: 跑 analyze + format + 表格 widget test**

```powershell
dart format lib/widgets/data/sortable_table.dart
flutter analyze lib/widgets/data/sortable_table.dart
flutter test test/widgets/data/sortable_table_test.dart
```
Expected: 全綠。

- [ ] **Step 8.6: Commit**

```powershell
git add lib/widgets/data/sortable_table.dart
git commit -m "feat(sortable-table): append relative time after absolute time in record rows"
```

---

### Task 9: 提交前全套品質檢查

依 `CLAUDE.md` 規則,commit 前都要過。最後一個套用點(Task 8)已 commit,這 task 是把專案級檢查再跑一次確認跨檔沒有遺漏。

- [ ] **Step 9.1: 全專案 format**

Run:
```powershell
dart format lib/ test/
```
Expected: 無檔案被改寫(若有,代表前面 task 漏跑 format)。

- [ ] **Step 9.2: 全專案 analyze**

Run:
```powershell
flutter analyze
```
Expected: `No issues found!`

- [ ] **Step 9.3: 全專案測試**

Run:
```powershell
flutter test
```
Expected: `All tests passed!`

- [ ] **Step 9.4: 若 Step 9.1 有改檔,把 format 結果 commit**

```powershell
git status
# 若有改動:
git add -A
git commit -m "chore: dart format"
```

否則跳過此步驟。

---

## Self-Review

**Spec 覆蓋對照**:

| Spec 段落 | 對應 Task |
|---|---|
| 1. relative time helper | Task 1 |
| 2. 絕對時間 helper | Task 1(同檔) |
| 3. 7 條 ARB key × 10 語言 | Task 2 |
| 4. clockTickProvider | Task 3 |
| 5a. Footer | Task 4 |
| 5b. 帳號卡片 | Task 5 |
| 5c. 帳號匯入對話框 | Task 6 |
| 5d. 新版本對話框 | Task 7 |
| 5e. 記錄列表 | Task 8 |
| 6. 單元測試 | Task 1 |
| 提交前品質檢查 | Task 9 |

**Placeholder scan**: 已掃過,每 step 都有具體程式碼/指令;Step 1.1 內第一個 `formatAbsoluteDateTime` 斷言寫了較繞的版本後改用精簡版,實際採後者。

**Type consistency**: 函式簽名跨 task 一致 — `relativeTime(DateTime, AppLocalizations, {DateTime? now})`、`formatAbsoluteDateTime(DateTime)`、`formatAbsoluteDate(DateTime)`、`clockTickProvider`(`StreamProvider<DateTime>`)。
