// lib/routing/app_router.dart
import 'package:go_router/go_router.dart';

import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';

GoRouter buildAppRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: OverviewPage()),
            ),
            GoRoute(
              path: '/banner/:type',
              pageBuilder: (_, state) => NoTransitionPage(
                child: BannerPage(gachaType: state.pathParameters['type']!),
              ),
            ),
          ],
        ),
      ],
    );
