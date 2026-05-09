// lib/pages/app_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/gacha_types.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
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
    // progress null → 非 null 時開 dialog；dialog 內部偵測 null 自 pop
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

    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _indexFromLocation(location);
    final activeData = ref.watch(
        wishRepositoryProvider.select((s) => s.activeData));
    final width = MediaQuery.of(context).size.width;
    final extendedRail = width >= 1100;
    final version = ref.watch(appVersionProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('$appName v$version'),
        actions: [
          const UidIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('更新資料'),
              onPressed: () async {
                await ref.read(wishRepositoryProvider.notifier).update();
              },
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: (i) => _go(context, i),
                extended: extendedRail,
                labelType: extendedRail ? null : NavigationRailLabelType.all,
                destinations: [
                  NavigationRailDestination(
                    icon: const Icon(Icons.dashboard_outlined),
                    selectedIcon: const Icon(Icons.dashboard),
                    label: Text(l.navOverview),
                  ),
                  ..._buildBannerDestinations(l),
                ],
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: widget.child),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Text(
            activeData == null
                ? '尚未同步'
                : '最後更新：${DateFormat('yyyy-MM-dd HH:mm').format(activeData.lastUpdated.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  List<NavigationRailDestination> _buildBannerDestinations(
      AppLocalizations l) {
    return [
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
  }

  int _indexFromLocation(String path) {
    if (path == '/') return 0;
    if (path.startsWith('/banner/')) {
      final type = path.substring('/banner/'.length);
      final i = gachaTypes.indexWhere((t) => t.gachaType == type);
      return i < 0 ? 0 : i + 1;
    }
    return 0;
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
