// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 提供給 callsite 的舊 GachaColors 包裝（過渡用，搬完後移除）。
///
/// 新程式請改用 `Theme.of(context).extension<GachaTokens>()!`。
@Deprecated('Use Theme.of(context).extension<GachaTokens>()! instead')
abstract class GachaColors {
  static Color fiveStar = GachaTokens.dark.fiveStar;
  static Color fourStar = GachaTokens.dark.fourStar;
  static Color threeStar = GachaTokens.dark.threeStar;
  static Color character = GachaTokens.dark.character;
  static Color weapon = GachaTokens.dark.weapon;
  static const Color unknown = Color(0xFF9E9E9E);
}

ThemeData buildDarkTheme() => _buildTheme(
      brightness: Brightness.dark,
      tokens: GachaTokens.dark,
    );

ThemeData buildLightTheme() => _buildTheme(
      brightness: Brightness.light,
      tokens: GachaTokens.light,
    );

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
