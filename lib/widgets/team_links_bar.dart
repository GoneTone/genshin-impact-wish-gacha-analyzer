// lib/widgets/team_links_bar.dart
//
// AppShell 底部 footer 右側的團隊資訊列：
// 4 個社群 icon (Facebook / Discord / Line / GitHub) + 分隔線 + 團隊名稱連結。
// 設計來源：舊版 master `src/components/NavLayout.vue` 的 topbar。

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';

class TeamLinksBar extends StatelessWidget {
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

class _IconLink extends StatelessWidget {
  const _IconLink({
    required this.icon,
    required this.tooltip,
    required this.url,
  });

  final FaIconData icon;
  final String tooltip;
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
          debugPrint('TeamLinksBar: invalid url "$url"');
          return;
        }
        openExternalUrl(uri);
      },
    );
  }
}
