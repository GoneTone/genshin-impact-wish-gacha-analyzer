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
