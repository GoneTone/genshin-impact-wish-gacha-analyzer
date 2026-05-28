import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 單一 release 的內容卡片：版本標題 + 發布時間 + Markdown body。
/// 由 `NewVersionDialog` 與 `CurrentReleaseDialog` 共用。
class ReleaseNotesContent extends StatelessWidget {
  /// 建立 [ReleaseNotesContent]。
  const ReleaseNotesContent({super.key, required this.release});

  /// 要呈現的 release 資料。
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                RelativeTimeText(
                  time: release.publishedAt,
                  templateBuilder: l.updateReleasedAt,
                  useDateOnly: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty)
              MarkdownBlock(
                data: release.body,
                config: releaseNotesMarkdownConfig(theme),
              ),
          ],
        ),
      ),
    );
  }
}

/// 依 [theme] 亮暗模式建立 markdown 渲染設定，統一連結樣式。
MarkdownConfig releaseNotesMarkdownConfig(ThemeData theme) {
  final base = theme.brightness == Brightness.dark
      ? MarkdownConfig.darkConfig
      : MarkdownConfig.defaultConfig;
  return base.copy(
    configs: [LinkConfig(style: TextStyle(color: linkBaseColor(theme)))],
  );
}
