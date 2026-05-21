import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

/// AppShell 底部 footer 右側的團隊資訊列：
/// 4 個社群 icon（Facebook / Discord / Line / GitHub）+ 分隔線 + 團隊名稱連結。
class TeamLinksBar extends StatelessWidget {
  /// 建立 [TeamLinksBar]。
  const TeamLinksBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconLink(
          icon: FontAwesomeIcons.facebookF,
          tooltip: 'Facebook',
          url: TeamInfo.facebookUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.discord,
          tooltip: 'Discord',
          url: TeamInfo.discordUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.line,
          tooltip: 'Line',
          url: TeamInfo.lineUrl,
        ),
        _IconLink(
          icon: FontAwesomeIcons.github,
          tooltip: 'GitHub',
          url: AppRepo.githubUrl,
        ),
        const SizedBox(width: AppSpacing.xs),
        Container(width: 1, height: 16, color: tokens.textMuted),
        const SizedBox(width: AppSpacing.s),
        AppLink(
          url: TeamInfo.websiteUrl,
          child: Text(
            TeamInfo.name,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 單一社群平台的圖示連結按鈕。
class _IconLink extends StatelessWidget {
  /// 建立 [_IconLink]。
  const _IconLink({
    required this.icon,
    required this.tooltip,
    required this.url,
  });

  /// FontAwesome 圖示。
  final FaIconData icon;

  /// Tooltip 文字。
  final String tooltip;

  /// 點擊後開啟的目標 URL。
  final String url;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    return IconButton(
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
      mouseCursor: SystemMouseCursors.click,
      icon: FaIcon(icon, color: tokens.textSecondary),
      onPressed: () {
        final uri = Uri.tryParse(url);
        if (uri == null) {
          Logger('ui.link').warning('TeamLinksBar: invalid url "$url"');
          return;
        }
        openExternalUrl(uri);
      },
    );
  }
}
