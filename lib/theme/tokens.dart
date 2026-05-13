// lib/theme/tokens.dart
import 'package:flutter/material.dart';

/// 中性 scale：間距 / 圓角 / 字級。dark 與 light 共用。
abstract class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
}

/// 字級語意（搭配 ThemeData.textTheme 對應 M3 名稱）。
abstract class AppFontSize {
  static const double display = 32; // 保底大數字
  static const double pageTitle = 22; // 頁標
  static const double title = 18; // 卡標
  static const double body = 14;
  static const double label = 11; // uppercase 小寫上標
}

/// 卡池 / 應用層級的色 token。透過 ThemeExtension 注入。
@immutable
class GachaTokens extends ThemeExtension<GachaTokens> {
  const GachaTokens({
    required this.surfaceBackground,
    required this.surfaceCard,
    required this.surfaceCardHigh,
    required this.borderSubtle,
    required this.borderEmphasis,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.fiveStar,
    required this.fourStar,
    required this.threeStar,
    required this.character,
    required this.weapon,
    required this.accentPrimary,
    required this.stateDanger,
    required this.stateSuccess,
    required this.stateWarning,
  });

  final Color surfaceBackground;
  final Color surfaceCard;
  final Color surfaceCardHigh;
  final Color borderSubtle;
  final Color borderEmphasis;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color fiveStar;
  final Color fourStar;
  final Color threeStar;
  final Color character;
  final Color weapon;
  final Color accentPrimary;
  final Color stateDanger;
  final Color stateSuccess;
  final Color stateWarning;

  /// Dark = 深藍夜空 (palette A)
  static const dark = GachaTokens(
    surfaceBackground: Color(0xFF0C1220),
    surfaceCard: Color(0xFF141C30),
    surfaceCardHigh: Color(0xFF1A2438),
    borderSubtle: Color(0xFF1F2A44),
    borderEmphasis: Color(0xFF27314C),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFDDE3EE),
    textMuted: Color(0xFF8A92A6),
    fiveStar: Color(0xFFE6C477),
    fourStar: Color(0xFFA385E0),
    threeStar: Color(0xFF5B9BD5),
    character: Color(0xFF46B07A),
    weapon: Color(0xFFE6736B),
    accentPrimary: Color(0xFFE6C477),
    stateDanger: Color(0xFFE6736B),
    stateSuccess: Color(0xFF46B07A),
    stateWarning: Color(0xFFE6C477),
  );

  /// Light = 由 dark 衍生（背景反轉、卡池色稍降亮度）
  static const light = GachaTokens(
    surfaceBackground: Color(0xFFFAFBFD),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceCardHigh: Color(0xFFF1F4FA),
    borderSubtle: Color(0xFFE5E8EF),
    borderEmphasis: Color(0xFFD0D5E0),
    textPrimary: Color(0xFF0C1220),
    textSecondary: Color(0xFF2C3245),
    textMuted: Color(0xFF6A7080),
    fiveStar: Color(0xFFB8860B),
    fourStar: Color(0xFF7A4FB8),
    threeStar: Color(0xFF2E7CC2),
    character: Color(0xFF2E7D32),
    weapon: Color(0xFFC62828),
    accentPrimary: Color(0xFFB8860B),
    stateDanger: Color(0xFFC62828),
    stateSuccess: Color(0xFF2E7D32),
    stateWarning: Color(0xFFB8860B),
  );

  @override
  GachaTokens copyWith({
    Color? surfaceBackground,
    Color? surfaceCard,
    Color? surfaceCardHigh,
    Color? borderSubtle,
    Color? borderEmphasis,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? fiveStar,
    Color? fourStar,
    Color? threeStar,
    Color? character,
    Color? weapon,
    Color? accentPrimary,
    Color? stateDanger,
    Color? stateSuccess,
    Color? stateWarning,
  }) => GachaTokens(
    surfaceBackground: surfaceBackground ?? this.surfaceBackground,
    surfaceCard: surfaceCard ?? this.surfaceCard,
    surfaceCardHigh: surfaceCardHigh ?? this.surfaceCardHigh,
    borderSubtle: borderSubtle ?? this.borderSubtle,
    borderEmphasis: borderEmphasis ?? this.borderEmphasis,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    fiveStar: fiveStar ?? this.fiveStar,
    fourStar: fourStar ?? this.fourStar,
    threeStar: threeStar ?? this.threeStar,
    character: character ?? this.character,
    weapon: weapon ?? this.weapon,
    accentPrimary: accentPrimary ?? this.accentPrimary,
    stateDanger: stateDanger ?? this.stateDanger,
    stateSuccess: stateSuccess ?? this.stateSuccess,
    stateWarning: stateWarning ?? this.stateWarning,
  );

  @override
  GachaTokens lerp(ThemeExtension<GachaTokens>? other, double t) {
    if (other is! GachaTokens) return this;
    return GachaTokens(
      surfaceBackground: Color.lerp(
        surfaceBackground,
        other.surfaceBackground,
        t,
      )!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceCardHigh: Color.lerp(surfaceCardHigh, other.surfaceCardHigh, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderEmphasis: Color.lerp(borderEmphasis, other.borderEmphasis, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      fiveStar: Color.lerp(fiveStar, other.fiveStar, t)!,
      fourStar: Color.lerp(fourStar, other.fourStar, t)!,
      threeStar: Color.lerp(threeStar, other.threeStar, t)!,
      character: Color.lerp(character, other.character, t)!,
      weapon: Color.lerp(weapon, other.weapon, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      stateDanger: Color.lerp(stateDanger, other.stateDanger, t)!,
      stateSuccess: Color.lerp(stateSuccess, other.stateSuccess, t)!,
      stateWarning: Color.lerp(stateWarning, other.stateWarning, t)!,
    );
  }
}

/// Theme.of(context) 取 token 的便捷 extension。
extension GachaTokensX on ThemeData {
  GachaTokens get gacha => extension<GachaTokens>()!;
}
