import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 卡池配色表,給 Timeline 系列 widget 共用。
@immutable
class BannerColors {
  const BannerColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.odesEvent,
    required this.odesStandard,
    required this.fallback,
  });

  /// 從 [GachaTokens] 推導預設配色;
  /// 邏輯與原 `FiveStarListColors` 一致。
  factory BannerColors.fromTokens(GachaTokens tokens) => BannerColors(
    character: tokens.character,
    weapon: tokens.weapon,
    chronicled: tokens.accentPrimary,
    standard: tokens.threeStar,
    beginner: tokens.textMuted,
    odesEvent: tokens.odesEvent,
    odesStandard: tokens.odesStandard,
    fallback: tokens.textMuted,
  );

  final Color character;
  final Color weapon;
  final Color chronicled;
  final Color standard;
  final Color beginner;
  final Color odesEvent;
  final Color odesStandard;
  final Color fallback;

  Color colorFor(String gachaType) => switch (gachaType) {
    '301' => character,
    '302' => weapon,
    '500' => chronicled,
    '200' => standard,
    '100' => beginner,
    '2000' => odesEvent,
    '1000' => odesStandard,
    _ => fallback,
  };
}
