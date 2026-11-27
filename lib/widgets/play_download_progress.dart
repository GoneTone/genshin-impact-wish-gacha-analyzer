import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/play_update.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// Android 從 Google Play 下載新版時，SnackBar 裡的進度：百分比、進度條與「已下載／總大小」。
///
/// Play 還沒回報總大小前（剛開始、或確認視窗還開著）顯示不確定進度條。
class PlayDownloadProgressBar extends ConsumerWidget {
  /// 建立 [PlayDownloadProgressBar]。
  const PlayDownloadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final p = ref.watch(playDownloadProgressProvider).value;
    final fraction = p == null || p.total <= 0
        ? null
        : (p.bytes / p.total).clamp(0.0, 1.0);
    final accent =
        theme.snackBarTheme.actionTextColor ?? theme.colorScheme.inversePrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.updateDownloadingMessage)),
            if (fraction != null) Text('${(fraction * 100).floor()}%'),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        // 預設底色在反色的 SnackBar 上和進度色太接近（實機上金色對深咖啡），改用同色淡化。
        LinearProgressIndicator(
          value: fraction,
          color: accent,
          backgroundColor: accent.withValues(alpha: 0.25),
        ),
        if (fraction != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_mb(p!.bytes)} / ${_mb(p.total)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: DefaultTextStyle.of(context).style.color,
            ),
          ),
        ],
      ],
    );
  }

  /// 位元組換成「12.3 MB」。
  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
