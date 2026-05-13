import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';

/// 顯示「<前綴><相對時間><後綴>」格式的 localized 字串,並只對相對時間
/// 那段套 Tooltip(滑鼠 hover 顯示絕對時間)。
///
/// 用 sentinel `￼` (OBJECT REPLACEMENT CHARACTER) 對 [templateBuilder]
/// 套用 placeholder 後的字串做切割 — 此字元在任何自然語言翻譯都不會出現。
///
/// 自動訂閱 [clockTickProvider],每 30 秒重繪。
class RelativeTimeText extends ConsumerWidget {
  const RelativeTimeText({
    super.key,
    required this.time,
    required this.templateBuilder,
    this.useDateOnly = false,
    this.style,
    this.overflow,
  });

  /// 要轉成相對時間的目標時間。
  final DateTime time;

  /// 接受 placeholder 字串、回傳套用後的整段 localized 字串。
  /// 範例:`(s) => l.footerLastUpdated(s)`、`(s) => l.updateReleasedAt(s)`。
  final String Function(String placeholder) templateBuilder;

  /// Tooltip 是否只顯示日期(無時:分)。
  /// `false`(預設) → `formatAbsoluteDateTime`;`true` → `formatAbsoluteDate`。
  final bool useDateOnly;

  final TextStyle? style;
  final TextOverflow? overflow;

  static const _sentinel = '￼';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockTickProvider);

    final l = AppLocalizations.of(context)!;
    final relative = relativeTime(time, l);
    final tooltipMessage = useDateOnly
        ? formatAbsoluteDate(time)
        : formatAbsoluteDateTime(time);

    final template = templateBuilder(_sentinel);
    final idx = template.indexOf(_sentinel);
    final prefix = idx >= 0 ? template.substring(0, idx) : template;
    final suffix = idx >= 0 ? template.substring(idx + _sentinel.length) : '';

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: tooltipMessage,
              child: Text(relative, style: style),
            ),
          ),
          if (suffix.isNotEmpty) TextSpan(text: suffix),
        ],
      ),
      overflow: overflow,
    );
  }
}
