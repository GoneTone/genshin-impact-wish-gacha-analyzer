import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/luck_palette.dart';

/// 將歐非分級對應到目前語言的標籤（供 tooltip 與 [LuckLegend] 共用）。
String luckTierLabel(LuckTier tier, AppLocalizations l) => switch (tier) {
  LuckTier.lucky => l.luckTierLucky,
  LuckTier.average => l.luckTierAverage,
  LuckTier.unlucky => l.luckTierUnlucky,
};

/// 時間軸歐非色圖例：歐／普通／非 三個色點＋標籤，低視窗寬度可換行。
/// 刻意不標抽數——跨池保底門檻不同，標數字會誤導。
class LuckLegend extends StatelessWidget {
  /// 建立 [LuckLegend]。
  const LuckLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.l,
      runSpacing: AppSpacing.xs,
      children: [
        for (final tier in LuckTier.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: luckColorFor(tier, tokens),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                luckTierLabel(tier, l),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
