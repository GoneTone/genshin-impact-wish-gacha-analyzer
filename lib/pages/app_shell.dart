// lib/pages/app_shell.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/team_links_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/update_progress_dialog.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next != null && !_dialogOpen) {
          _dialogOpen = true;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const UpdateProgressDialog(),
          ).whenComplete(() {
            _dialogOpen = false;
          });
        }
      },
    );

    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final location = GoRouterState.of(context).uri.path;
    final activeData = ref.watch(
      wishRepositoryProvider.select((s) => s.activeData),
    );
    final width = MediaQuery.of(context).size.width;
    final extendedRail = width >= 1180;
    final version = ref.watch(appVersionProvider);

    final isSettingsActive = location == '/settings';
    final isContributorsActive = location == '/contributors';
    final selectedIndex = (isSettingsActive || isContributorsActive)
        ? null
        : _bannerIndexFromLocation(location);

    final collapsedNoLabel = !extendedRail && width < 800;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/app_icon.png',
              // 40dp = AppBar 預設高度 56dp 上下各留 8dp padding；
              // multi-resolution 1x/2x/3x = 64/128/256，任何 DPR 下都
              // 大於 display 物理像素，避免 upscale 模糊。
              width: 40,
              height: 40,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(width: AppSpacing.s),
            Text('${l.appName} v$version'),
          ],
        ),
        actions: [
          const UidIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s,
            ),
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(l.actionUpdate),
              onPressed: () async {
                await ref.read(wishRepositoryProvider.notifier).update();
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Rail(
                  selectedIndex: selectedIndex,
                  isSettingsActive: isSettingsActive,
                  isContributorsActive: isContributorsActive,
                  extended: extendedRail,
                  collapsedNoLabel: collapsedNoLabel,
                  l: l,
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: widget.child),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.xs * 1.5,
            ),
            color: tokens.surfaceCardHigh,
            child: Row(
              children: [
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
                const SizedBox(width: AppSpacing.s),
                const TeamLinksBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _bannerIndexFromLocation(String path) {
    if (path == '/') return 0;
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final i = gachaTypes.indexWhere((t) => t.gachaType == type);
      return i < 0 ? 0 : i + 1;
    }
    return 0;
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selectedIndex,
    required this.isSettingsActive,
    required this.isContributorsActive,
    required this.extended,
    required this.collapsedNoLabel,
    required this.l,
  });
  final int? selectedIndex;
  final bool isSettingsActive;
  final bool isContributorsActive;
  final bool extended;
  final bool collapsedNoLabel;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final destinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_outlined),
        selectedIcon: const Icon(Icons.dashboard),
        label: Text(l.navOverview),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: Text(l.navCharacter),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.shield_outlined),
        selectedIcon: const Icon(Icons.shield),
        label: Text(l.navWeapon),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.collections_bookmark_outlined),
        selectedIcon: const Icon(Icons.collections_bookmark),
        label: Text(l.navChronicled),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.history),
        selectedIcon: const Icon(Icons.history_toggle_off),
        label: Text(l.navStandard),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.school_outlined),
        selectedIcon: const Icon(Icons.school),
        label: Text(l.navBeginner),
      ),
    ];

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => _go(context, i),
              extended: extended,
              labelType: extended
                  ? null
                  : (collapsedNoLabel
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all),
              destinations: destinations,
              groupAlignment: -1.0,
            ),
          ),
          // 貢獻者入口
          _BottomRailButton(
            active: isContributorsActive,
            extended: extended,
            hideLabel: collapsedNoLabel,
            label: l.navContributors,
            iconActive: Icons.volunteer_activism,
            iconInactive: Icons.volunteer_activism_outlined,
            onPressed: () => context.go('/contributors'),
          ),
          // 設定入口（固定在底部）
          _BottomRailButton(
            active: isSettingsActive,
            extended: extended,
            hideLabel: collapsedNoLabel,
            label: l.navSettings,
            iconActive: Icons.settings,
            iconInactive: Icons.settings_outlined,
            onPressed: () => context.go('/settings'),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    );
  }

  void _go(BuildContext context, int i) {
    if (i == 0) {
      context.go('/');
    } else {
      final type = gachaTypes[i - 1].gachaType;
      context.go('/banner/$type');
    }
  }
}

class _BottomRailButton extends StatelessWidget {
  const _BottomRailButton({
    required this.active,
    required this.extended,
    required this.hideLabel,
    required this.label,
    required this.iconActive,
    required this.iconInactive,
    required this.onPressed,
  });
  final bool active;
  final bool extended;
  final bool hideLabel;
  final String label;
  final IconData iconActive;
  final IconData iconInactive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    final color = active
        ? Theme.of(context).colorScheme.primary
        : tokens.textSecondary;
    final icon = Icon(active ? iconActive : iconInactive, color: color);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.m,
            horizontal: AppSpacing.s,
          ),
          child: extended
              ? Row(
                  children: [
                    const SizedBox(width: AppSpacing.xs),
                    icon,
                    const SizedBox(width: AppSpacing.m),
                    Text(label, style: TextStyle(color: color)),
                  ],
                )
              : (hideLabel
                    ? Center(child: icon)
                    : Column(
                        children: [
                          icon,
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            label,
                            style: TextStyle(color: color, fontSize: 11),
                          ),
                        ],
                      )),
        ),
      ),
    );
  }
}
