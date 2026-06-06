import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// 單一「其他遊戲版本」項目：在地化遊戲名 + 專案連結。
class OtherGameVersion {
  /// 建立 [OtherGameVersion]。
  const OtherGameVersion({required this.label, required this.url});

  /// 取在地化遊戲名（傳入當前 [AppLocalizations]）。
  final String Function(AppLocalizations l) label;

  /// 點擊開啟的專案 URL。
  final String url;
}

/// 鳴潮遊戲名 resolver。const tear-off 需 top-level function（closure 非 const）。
String _wutheringWavesLabel(AppLocalizations l) =>
    l.settingsOtherGamesWutheringWaves;

/// 目前支援的其他遊戲版本清單。新增遊戲在此補一筆 + 對應 ARB key 即可，
/// 不必改動 [OtherGameVersions] widget 與設定頁。
const List<OtherGameVersion> kOtherGameVersions = [
  OtherGameVersion(
    label: _wutheringWavesLabel,
    url: RelatedProjects.wutheringWavesAnalyzer,
  ),
];

/// 設定頁「關於」區塊內的「其他遊戲版本」區塊：上方分隔線 + 小標 + 每個遊戲
/// 一列（[AppLink] 文字連結 + 靜態 open_in_new 圖示）+ 未來說明。資料來自
/// [kOtherGameVersions]，新增遊戲免改本 widget。
class OtherGameVersions extends StatelessWidget {
  /// 建立 [OtherGameVersions]。
  const OtherGameVersions({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.l),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.l),
        Text(
          l.settingsOtherGamesTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (final game in kOtherGameVersions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // open_in_new 圖示刻意放在 AppLink 之外且固定 textSecondary 色：
                // AppLink 的 hover 只透過 DefaultTextStyle 染文字、不影響 Icon
                // （Icon 取 IconTheme），放進去顏色會對不上；此處圖示僅作「會開
                // 外部瀏覽器」提示，不需隨 hover 變色。
                AppLink(url: game.url, child: Text(game.label(l))),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.open_in_new, size: 14, color: tokens.textSecondary),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.s),
        Text(
          l.settingsOtherGamesFuture,
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
