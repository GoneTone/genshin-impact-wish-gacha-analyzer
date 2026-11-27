import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/clock_tick.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/empty_state.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 目前帳號的「最後更新」文字；尚未同步時顯示「尚未同步」。外殼底部列與手機橫向頁首共用。
///
/// 放得下就顯示完整文字；放不下（放大字級、窄視窗）時前綴換成時鐘圖示，只留相對時間，
/// 整塊點一下顯示完整文字，長按時間仍看得到絕對時間。
class LastUpdatedLabel extends ConsumerWidget {
  /// 建立 [LastUpdatedLabel]；[style] 為 null 時用 `bodySmall`。
  const LastUpdatedLabel({super.key, this.style});

  /// 文字樣式。
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final activeData = ref.watch(
      gachaRepositoryProvider.select((s) => s.activeData),
    );
    // 相對時間會變長變短（例如「59 分鐘前」→「1 小時前」），跟著重新判斷放不放得下。
    ref.watch(clockTickProvider);
    final textStyle = style ?? Theme.of(context).textTheme.bodySmall;
    if (activeData == null) {
      return Text(
        l.footerNotSynced,
        style: textStyle,
        overflow: TextOverflow.ellipsis,
      );
    }
    final time = activeData.lastUpdated;
    final full = l.footerLastUpdated(relativeTime(time, l));
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: full, style: textStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        painter.dispose();
        if (fits) {
          return RelativeTimeText(
            time: time,
            templateBuilder: l.footerLastUpdated,
            style: textStyle,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Tooltip(
          message: full,
          triggerMode: tapTooltipTrigger(context),
          // 整列高 48dp，點擊範圍才夠。
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.update, size: 16, semanticLabel: full),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: RelativeTimeText(
                    time: time,
                    templateBuilder: (s) => s,
                    style: textStyle,
                    overflow: TextOverflow.ellipsis,
                    tooltipOnTap: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 手機橫向（沒有底部狀態列）時頁面自己顯示的弱色最後更新時間（放在頁首標題旁）；其他情況回傳 null。
LastUpdatedLabel? phoneLandscapeLastUpdated(BuildContext context) {
  if (phoneOrientationOf(context) != PhoneOrientation.landscape) return null;
  return LastUpdatedLabel(
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).gacha.textMuted),
  );
}

/// 尚未同步時的頁面內容；手機橫向在左上角多顯示「尚未同步」。
Widget noSyncPageBody(BuildContext context) {
  final label = phoneLandscapeLastUpdated(context);
  if (label == null) return EmptyState.noSync(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.all(AppSpacing.m), child: label),
      Expanded(child: EmptyState.noSync(context)),
    ],
  );
}
