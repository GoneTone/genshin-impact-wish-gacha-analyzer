// lib/routing/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:genshin_impact_wish_gacha_analyzer/pages/app_shell.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/banner_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/overview_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/contributors_page.dart';
import 'package:genshin_impact_wish_gacha_analyzer/pages/settings_page.dart';

GoRouter buildAppRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', pageBuilder: (_, _) => _fade(const OverviewPage())),
        GoRoute(
          path: '/banner/:type',
          pageBuilder: (_, state) =>
              _fade(BannerPage(gachaType: state.pathParameters['type']!)),
        ),
        GoRoute(
          path: '/contributors',
          pageBuilder: (_, _) => _fade(const ContributorsPage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (_, _) => _fade(const SettingsPage()),
        ),
      ],
    ),
  ],
);

CustomTransitionPage<T> _fade<T>(Widget child) => CustomTransitionPage<T>(
  child: child,
  transitionDuration: const Duration(milliseconds: 200),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  transitionsBuilder: (ctx, animation, _, child) =>
      MediaQuery.of(ctx).disableAnimations
      ? child
      : FadeTransition(opacity: animation, child: child),
);
