import 'package:flutter/material.dart';

/// 中性 scale：間距 / 圓角 / 字級。dark 與 light 共用。
abstract class AppSpacing {
  /// 4dp。
  static const double xs = 4;

  /// 8dp。
  static const double s = 8;

  /// 12dp。
  static const double m = 12;

  /// 16dp。
  static const double l = 16;

  /// 24dp。
  static const double xl = 24;

  /// 32dp。
  static const double xxl = 32;

  /// 48dp。
  static const double xxxl = 48;
}

/// 圓角常數（single-source）。
abstract class AppRadius {
  /// 小圓角，用於 chip、badge 等。
  static const double sm = 6;

  /// 中圓角，用於卡片、按鈕等。
  static const double md = 10;

  /// 大圓角，用於 dialog、bottom sheet 等。
  static const double lg = 14;
}

/// 字級語意（搭配 ThemeData.textTheme 對應 M3 名稱）。
abstract class AppFontSize {
  /// 32sp，保底大數字展示用。
  static const double display = 32;

  /// 22sp，頁面標題。
  static const double pageTitle = 22;

  /// 18sp，卡片標題。
  static const double title = 18;

  /// 14sp，正文。
  static const double body = 14;

  /// 11sp，uppercase 小寫上標。
  static const double label = 11;
}

/// 應用層級的色 token。透過 ThemeExtension 注入。
///
/// 卡池配色不放在這裡（見 [BannerColors]）— 那組顏色刻意跟稀有度脫鉤，
/// 自成一套 palette。
@immutable
class GachaTokens extends ThemeExtension<GachaTokens> {
  /// 建立 [GachaTokens]。
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
    required this.twoStar,
    required this.accentPrimary,
    required this.stateDanger,
    required this.stateSuccess,
    required this.stateWarning,
  });

  /// Scaffold 最底層背景色。
  final Color surfaceBackground;

  /// 卡片底色。
  final Color surfaceCard;

  /// 較高層級卡片底色（nested card）。
  final Color surfaceCardHigh;

  /// 低對比邊框色。
  final Color borderSubtle;

  /// 較高對比邊框色。
  final Color borderEmphasis;

  /// 主要文字色。
  final Color textPrimary;

  /// 次要文字色。
  final Color textSecondary;

  /// 輔助（muted）文字色。
  final Color textMuted;

  /// 五星稀有度色。
  final Color fiveStar;

  /// 四星稀有度色。
  final Color fourStar;

  /// 三星稀有度色。
  final Color threeStar;

  /// 二星稀有度色。
  final Color twoStar;

  /// 品牌主色（按鈕、強調色）。
  final Color accentPrimary;

  /// 危險狀態色（錯誤、刪除）。
  final Color stateDanger;

  /// 成功狀態色。
  final Color stateSuccess;

  /// 警告狀態色。
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
    twoStar: Color(0xFF6A7080),
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
    twoStar: Color(0xFF8A92A6),
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
    Color? twoStar,
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
    twoStar: twoStar ?? this.twoStar,
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
      twoStar: Color.lerp(twoStar, other.twoStar, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      stateDanger: Color.lerp(stateDanger, other.stateDanger, t)!,
      stateSuccess: Color.lerp(stateSuccess, other.stateSuccess, t)!,
      stateWarning: Color.lerp(stateWarning, other.stateWarning, t)!,
    );
  }
}

/// Theme.of(context) 取 token 的便捷 extension。
extension GachaTokensX on ThemeData {
  /// 取出 [GachaTokens] 主題延伸；未注入時拋出 [Null] error。
  GachaTokens get gacha => extension<GachaTokens>()!;
}
