// lib/pages/app_shell.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/new_version_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';
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
  bool _releaseDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appReleaseProvider.notifier).check(manual: false);
    });
  }

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

    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseAvailable && !_releaseDialogOpen) {
        _releaseDialogOpen = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => NewVersionDialog(releases: next.releases),
        ).whenComplete(() {
          _releaseDialogOpen = false;
        });
      }
    });

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
    final selection = _resolveRailSelection(
      location,
      isSettings: isSettingsActive,
      isContributors: isContributorsActive,
    );

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
                  selection: selection,
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
                  child: activeData == null
                      ? Text(
                          l.footerNotSynced,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        )
                      : RelativeTimeText(
                          time: activeData.lastUpdated,
                          templateBuilder: l.footerLastUpdated,
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

  _RailSelection _resolveRailSelection(
    String path, {
    required bool isSettings,
    required bool isContributors,
  }) {
    if (isSettings || isContributors) return _RailSelection.none;
    if (path == '/') return const _RailSelection(topIndex: 0);
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final wishTypes = gachaTypes
          .where((t) => t.category == GachaCategory.wish)
          .toList(growable: false);
      final wi = wishTypes.indexWhere((t) => t.gachaType == type);
      if (wi >= 0) return _RailSelection(wishIndex: wi);
      final odesTypes = gachaTypes
          .where((t) => t.category == GachaCategory.odes)
          .toList(growable: false);
      final oi = odesTypes.indexWhere((t) => t.gachaType == type);
      if (oi >= 0) return _RailSelection(odesIndex: oi);
    }
    return const _RailSelection(topIndex: 0);
  }
}

class _RailSelection {
  const _RailSelection({this.topIndex, this.wishIndex, this.odesIndex});
  final int? topIndex;
  final int? wishIndex;
  final int? odesIndex;

  static const none = _RailSelection();
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selection,
    required this.isSettingsActive,
    required this.isContributorsActive,
    required this.extended,
    required this.collapsedNoLabel,
    required this.l,
  });
  final _RailSelection selection;
  final bool isSettingsActive;
  final bool isContributorsActive;
  final bool extended;
  final bool collapsedNoLabel;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final wishTypes = gachaTypes
        .where((t) => t.category == GachaCategory.wish)
        .toList(growable: false);
    final odesTypes = gachaTypes
        .where((t) => t.category == GachaCategory.odes)
        .toList(growable: false);

    // 對齊 NavigationRail 預設寬度：collapsed 72dp，extended 256dp。
    final railWidth = extended ? 256.0 : 72.0;

    return SizedBox(
      width: railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.s),
                  _RailDestinationTile(
                    iconInactive: Icons.dashboard_outlined,
                    iconActive: Icons.dashboard,
                    label: l.navOverview,
                    selected: selection.topIndex == 0,
                    onTap: () => context.go('/'),
                    extended: extended,
                    hideLabel: collapsedNoLabel,
                  ),
                  _SectionLabel(
                    label: l.navSectionWish,
                    extended: extended,
                    hideLabel: collapsedNoLabel,
                  ),
                  for (var i = 0; i < wishTypes.length; i++)
                    _RailDestinationTile(
                      iconInactive: _railIconInactive(wishTypes[i].nameKey),
                      iconActive: _railIconActive(wishTypes[i].nameKey),
                      label: _railLabel(wishTypes[i].nameKey, l),
                      selected: selection.wishIndex == i,
                      onTap: () =>
                          context.go('/banner/${wishTypes[i].gachaType}'),
                      extended: extended,
                      hideLabel: collapsedNoLabel,
                    ),
                  _SectionLabel(
                    label: l.navSectionOdes,
                    extended: extended,
                    hideLabel: collapsedNoLabel,
                  ),
                  for (var i = 0; i < odesTypes.length; i++)
                    _RailDestinationTile(
                      iconInactive: _railIconInactive(odesTypes[i].nameKey),
                      iconActive: _railIconActive(odesTypes[i].nameKey),
                      label: _railLabel(odesTypes[i].nameKey, l),
                      selected: selection.odesIndex == i,
                      onTap: () =>
                          context.go('/banner/${odesTypes[i].gachaType}'),
                      extended: extended,
                      hideLabel: collapsedNoLabel,
                    ),
                  const SizedBox(height: AppSpacing.s),
                ],
              ),
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
        ],
      ),
    );
  }
}

/// 自製的 rail 項目，取代 NavigationRailDestination。
///
/// NavigationRail 內部使用 `MainAxisSize.max` 的 Column，無法在
/// `SingleChildScrollView`（垂直無界）內佈局，會導致
/// 「Cannot hit test a render box that has never been laid out.」
/// 自己刻一個有限高度的 tile，就沒有這個問題。
class _RailDestinationTile extends StatelessWidget {
  const _RailDestinationTile({
    required this.iconInactive,
    required this.iconActive,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.extended,
    required this.hideLabel,
  });

  final IconData iconInactive;
  final IconData iconActive;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool extended;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final colorScheme = theme.colorScheme;

    final fgColor = selected ? colorScheme.primary : tokens.textSecondary;
    final icon = Icon(selected ? iconActive : iconInactive, color: fgColor);
    final indicator = BoxDecoration(
      color: selected ? colorScheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    if (extended) {
      // Extended：icon + label 橫向並列，整列寬度
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Container(
              decoration: indicator,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fgColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Collapsed：icon 置中，依需求顯示下方小字 label
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs / 2,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            decoration: indicator,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.s,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (!hideLabel) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: fgColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.extended,
    required this.hideLabel,
  });

  final String label;
  final bool extended;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      child: hideLabel
          ? Divider(height: 1, color: tokens.borderSubtle)
          : Row(
              children: [
                Expanded(child: Divider(color: tokens.borderSubtle)),
                if (extended) ...[
                  const SizedBox(width: AppSpacing.s),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: Divider(color: tokens.borderSubtle)),
                ],
              ],
            ),
    );
  }
}

String _railLabel(String nameKey, AppLocalizations l) => switch (nameKey) {
  'gachaTypeCharacter' => l.navCharacter,
  'gachaTypeWeapon' => l.navWeapon,
  'gachaTypeChronicled' => l.navChronicled,
  'gachaTypeStandard' => l.navStandard,
  'gachaTypeBeginner' => l.navBeginner,
  'gachaTypeOdesEvent' => l.navOdesEvent,
  'gachaTypeOdesStandard' => l.navOdesStandard,
  _ => nameKey,
};

IconData _railIconInactive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person_outline,
  'gachaTypeWeapon' => Icons.shield_outlined,
  'gachaTypeChronicled' => Icons.collections_bookmark_outlined,
  'gachaTypeStandard' => Icons.history,
  'gachaTypeBeginner' => Icons.school_outlined,
  'gachaTypeOdesEvent' => Icons.auto_awesome_outlined,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion_outlined,
  _ => Icons.casino_outlined,
};

IconData _railIconActive(String nameKey) => switch (nameKey) {
  'gachaTypeCharacter' => Icons.person,
  'gachaTypeWeapon' => Icons.shield,
  'gachaTypeChronicled' => Icons.collections_bookmark,
  'gachaTypeStandard' => Icons.history_toggle_off,
  'gachaTypeBeginner' => Icons.school,
  'gachaTypeOdesEvent' => Icons.auto_awesome,
  'gachaTypeOdesStandard' => Icons.auto_awesome_motion,
  _ => Icons.casino,
};

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
