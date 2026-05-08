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
              builder: (_, state) => const OverviewPage(),
            ),
            GoRoute(
              path: '/banner/:type',
              builder: (_, state) =>
                  BannerPage(gachaType: state.pathParameters['type']!),
            ),
          ],
        ),
      ],
    );
