// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

ThemeData buildDarkTheme() =>
    _buildTheme(brightness: Brightness.dark, tokens: GachaTokens.dark);

ThemeData buildLightTheme() =>
    _buildTheme(brightness: Brightness.light, tokens: GachaTokens.light);

ThemeData _buildTheme({
  required Brightness brightness,
  required GachaTokens tokens,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: tokens.accentPrimary,
    brightness: brightness,
    surface: tokens.surfaceBackground,
    surfaceContainerLow: tokens.surfaceCard,
    surfaceContainerHigh: tokens.surfaceCardHigh,
    onSurface: tokens.textPrimary,
    primary: tokens.accentPrimary,
    error: tokens.stateDanger,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: tokens.surfaceBackground,
    dividerColor: tokens.borderSubtle,
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[tokens],
    cardTheme: CardThemeData(
      color: tokens.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: AppFontSize.body,
        color: tokens.textSecondary,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontSize: AppFontSize.label,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: tokens.textMuted,
      ),
    ),
  );
}
